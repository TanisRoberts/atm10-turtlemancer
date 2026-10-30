-- fm_draw.lua  --  Foreman engine: formatting, the screens (monitor + the computer's own) and drawing helpers.
-- A part of fm.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
K = colours
STATES = {
  mining = { "MINING", K.lime }, returning = { "RETURNING", K.yellow }, docked = { "DOCKED", K.lightBlue },
  waiting = { "WAITING", K.orange }, error = { "ERROR", K.red }, lost = { "LOST", K.red },
  retired = { "RETIRED", K.grey }, rebooting = { "REBOOTING", K.purple },
}
DIMS = { overworld = "Overworld", the_nether = "Nether", the_end = "End", ["allthemodium:mining"] = "Mining" }

function fmtNum(n)
  if type(n) ~= "number" then return tostring(n or "?") end
  local s = tostring(math.floor(n))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
function fmtAgo(s)
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end
function pretty(id)
  local s = tostring(id):gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end
function presetName(a, b, r1, r2)
  for _, p in ipairs(cfg.presets) do
    if p.minY == a and p.maxY == b and (r1 == nil or (p.r1 == r1 and p.r2 == r2)) then return p.name end
  end
end
function rangeText(a, b, r1, r2)
  if not a then return "-" end
  local n = presetName(a, b, r1, r2)
  return (n and (n .. " ") or "") .. a .. ".." .. b
end
function sq(r) return 2 * r + 1 end
-- How many chunks rings r1..r2 cover (ring 0 = the dock's chunk; from ring r1 skips the middle (2*r1-1)^2)
function chunkCount(r1, r2)
  r1, r2 = r1 or 0, r2 or DEF_R2
  return sq(r2) * sq(r2) - (r1 > 0 and sq(r1 - 1) * sq(r1 - 1) or 0)
end
function ringText(r1, r2)
  r1, r2 = r1 or 0, r2 or DEF_R2
  if r1 <= 0 then return ("chunk rings 0-%d, %d chunks (%dx%d)"):format(r2, chunkCount(r1, r2), sq(r2), sq(r2)) end
  return ("chunk rings %d-%d, %d chunks"):format(r1, r2, chunkCount(r1, r2))
end
function isSelected(dd, p)
  return dd.pMin == p.minY and dd.pMax == p.maxY and dd.pR1 == p.r1 and dd.pR2 == p.r2
end
function posText(s)
  if not s or not s.pos then return "position unknown" end
  return ("%d, %d, %d"):format(s.pos.x, s.pos.y, s.pos.z)
end
function stateOf(id)
  local d, l = entry(id), live[id]
  if d and d.retired then return "RETIRED", K.grey end
  if not l then return "NO SIGNAL", K.grey end
  local m = STATES[l.s.state] or { tostring(l.s.state or "?"):upper(), K.white }
  if os.clock() - l.seen > STALE then return m[1], K.grey end
  return m[1], m[2]
end

-- Sorted list of miner IDs to show
function digIds(showRetired)
  local out = {}
  for _, id in ipairs(allIds()) do
    if (entry(id).retired == true) == (showRetired == true) then out[#out + 1] = id end
  end
  table.sort(out, function(a, b) return sortKey(a) < sortKey(b) end)
  if not showRetired then
    -- Heard on the air but never asked for a number: running an old program
    local odd = {}
    for id in pairs(live) do if not entry(id) and ownsStatus(live[id].s) then odd[#odd + 1] = id end end
    table.sort(odd)
    for _, id in ipairs(odd) do out[#out + 1] = id end
  end
  return out
end

---------------------------------------------------------------------------
-- Screens: the monitor (if one touches the computer) and the computer's own screen.
-- Both show the same page; each keeps its own tap areas.
---------------------------------------------------------------------------
-- Each screen has its own page state (ui is pointed at the right one while drawing / handling a tap)
function newUi()
  return { page = "overview", id = nil, scroll = 1, showRetired = false, confirmRetire = nil, notice = nil,
           pscroll = 1, lscroll = 1, edit = nil, cmd = nil }
end
ui = nil

-- The monitor: the biggest one touching the computer, else one picked from the cable (shared/screens.lua,
-- docs/systems/screens.md). Asked once here at boot; findMonitor only re-reads it. Both the engine's drawing and
-- the UI-kit profiles (foreman_screens.lua, via F.findMonitor) look through this one place.
scr = require("screens").new({ slots = { { id = "wall", label = P.name .. "'s screen", required = false, scale = TEXT_SCALE } } })
scr:open()
function findMonitor() return scr:current("wall") end
function repickMonitor() scr:repick("wall"); os.reboot() end
mon, monSide = scr:get("wall")
views = {
  { dev = function() return mon end, kind = "monitor", hits = {}, ui = newUi() },
  { dev = function() return term end, kind = "term", hits = {}, ui = newUi() },
}
termUi = views[2].ui
ui = termUi

d, hits = nil -- current device and its hit list while drawing
function at(x, y, text, fg, bg)
  d.setCursorPos(x, y)
  d.setBackgroundColour(bg or K.black)
  d.setTextColour(fg or K.white)
  d.write(text)
end
function pad(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s > w then return s:sub(1, w) end
  return s .. (" "):rep(w - #s)
end
function lr(x, y, w, left, right, fgL, fgR)
  at(x, y, pad(left, w), fgL or K.lightGrey)
  if right then
    right = tostring(right):sub(1, w)
    at(x + w - #right, y, right, fgR or K.white)
  end
end
function bar(x, y, w, frac, colour)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  at(x, y, (" "):rep(w), K.white, K.grey)
  if n > 0 then at(x, y, (" "):rep(n), K.white, colour) end
end
function hit(x1, y1, x2, y2, fn) hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn } end
function button(x, y, w, rows, label, bg, fn, fg)
  for r = 0, rows - 1 do at(x, y + r, (" "):rep(w), K.black, bg) end
  label = label:sub(1, w)
  at(x + math.floor((w - #label) / 2), y + math.floor(rows / 2), label, fg or K.black, bg)
  hit(x, y, x + w - 1, y + rows - 1, fn)
end
function smallButton(x, y, label, bg, fn, fg)
  at(x, y, " " .. label .. " ", fg or K.black, bg)
  hit(x, y, x + #label + 1, y, fn)
  return x + #label + 3
end

function header(w, title, right)
  at(1, 1, (" "):rep(w), K.cyan, K.grey)
  at(2, 1, title, K.cyan, K.grey)
  if right and #right + #title + 4 < w then at(w - #right, 1, right, K.lightGrey, K.grey) end
  if ui.notice and os.clock() < ui.notice.untilT then
    at(2, 2, pad(ui.notice.text, w - 2), ui.notice.colour)
  end
end

-- Notices show on every screen
function say(text, colour)
  for _, v in ipairs(views) do v.ui.notice = { text = text, colour = colour or K.lime, untilT = os.clock() + 5 } end
end
