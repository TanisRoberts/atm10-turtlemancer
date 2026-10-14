-- farmhand.lua  --  the Farmhand: control screen for every farm turtle (Partridge, Woodpecker...)
--
-- Needs: an advanced computer with a wireless or ENDER modem (ender reaches farms anywhere) and an
-- advanced monitor touching it (any size; the computer's own screen works too, click with the mouse).
--
-- Overview: one card per farm turtle: what it's doing, fuel, its last round, when the next one is.
-- Tap one to open it:
--   ROUNDS NOW, PAUSE / GO, RE-MAP (walk the farm again: new rows, moved paths), FOUND (after you've
--   carried a lost turtle home), REBOOT (it finishes what it's doing, restarts and updates)
--   Settings, changed live: how often it does rounds, how many seeds/saplings it keeps, how often it
--   re-maps. They're written into the turtle's own .env file.
--   Its exact position (with GPS), last haul and everything it has brought in since it started.
--   MAP: the farm from above (north up once it's pinned to GPS): border, dock, every plot by crop
--   (capital letter = harvested last round, small = growing, red dot = empty) or every tree spot
--   (sapling / just replanted / empty), and an arrow where the turtle is right now, live. Big farms
--   follow the turtle; the arrow buttons (or the mouse wheel) pan. Tap a block to see what's there.
-- Orders repeat every few seconds until the turtle confirms them, so it picks them up whenever it's
-- in range. The mainframe board shows every farm turtle and a Farmhand row; chat commands
-- (island partridge rounds...) keep working alongside this screen.

local PROTOCOL   = "tanis-farm"
local CONFIG     = "farmhand.cfg"
local SEND_EVERY = 3
local STALE      = 20      -- seconds without news before a turtle greys out
local TEXT_SCALE = 0.5
local REBOOT_WAIT = 600000 -- ms: give up on an unconfirmed reboot after this

local K = colours

---------------------------------------------------------------------------
-- Registry: every farm turtle seen, by computer ID
--   { label, role, want, seq, set = {KEY=value}, setSeq, reboot, rebootAt }
---------------------------------------------------------------------------
local cfg = { turtles = {} }
local function loadCfg()
  if fs.exists(CONFIG) then
    local f = fs.open(CONFIG, "r"); local t = textutils.unserialize(f.readAll() or ""); f.close()
    if type(t) == "table" and type(t.turtles) == "table" then cfg = t end
  end
end
local function saveCfg()
  local f = fs.open(CONFIG .. ".new", "w"); f.write(textutils.serialize(cfg)); f.close()
  if fs.exists(CONFIG) then fs.delete(CONFIG) end
  fs.move(CONFIG .. ".new", CONFIG)
end

local live = {}         -- id -> { s = status, seen = os.clock() }
local maps = {}         -- id -> the turtle's last map message (see farmbot.lua B.mapMsg)
local mapAskedAt = {}   -- id -> os.clock() of the last map request
local sendNow = {}
local radioOK = nil

local function entry(id)
  local t = cfg.turtles[id]
  if not t then t = {}; cfg.turtles[id] = t end
  return t
end

local function order(id, want)
  local t = entry(id)
  t.want, t.seq = want, os.epoch("utc")
  saveCfg()
  sendNow[id] = true
end
local function requestReboot(id)
  local t = entry(id)
  t.reboot, t.rebootAt = os.epoch("utc"), os.epoch("utc")
  saveCfg()
  sendNow[id] = true
end

-- Settings the Farmhand can change, per role: { key, label, unit, step, min, max }
local SETTINGS = {
  farmer = {
    { "EVERY", "Rounds every", "min", 1, 1, 240 },
    { "KEEP_SEEDS", "Keep seeds", "", 16, 0, 1024 },
    { "RESURVEY_EVERY", "Re-map every", "rounds", 1, 0, 100 },
  },
  lumberjack = {
    { "EVERY", "Rounds every", "min", 5, 1, 240 },
    { "KEEP_SAPLINGS", "Keep saplings", "", 8, 0, 512 },
    { "RESURVEY_EVERY", "Re-map every", "rounds", 1, 0, 100 },
  },
}
local ROLE_NAME = { farmer = "crops", lumberjack = "trees" }

-- Current value: what we're sending (not yet confirmed) or what the turtle reports
local function settingValue(id, k)
  local t, l = cfg.turtles[id], live[id]
  local reported = l and l.s.settings and l.s.settings[k]
  if t and t.set and t.set[k] ~= nil and not (l and (l.s.setSeq or 0) >= (t.setSeq or 0)) then return t.set[k], true end
  return reported, false
end
local function changeSetting(id, k, value)
  local t = entry(id)
  local l = live[id]
  -- Start from what it reports, plus anything still unconfirmed
  local set = {}
  if t.set and not (l and (l.s.setSeq or 0) >= (t.setSeq or 0)) then for a, b in pairs(t.set) do set[a] = b end end
  set[k] = value
  t.set, t.setSeq = set, os.epoch("utc")
  saveCfg()
  sendNow[id] = true
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local STATES = {
  working = { "WORKING", K.lime }, surveying = { "MAPPING", K.lime }, docked = { "DOCKED", K.lightBlue },
  waiting = { "WAITING", K.orange }, error = { "ERROR", K.red }, lost = { "LOST", K.red },
  rebooting = { "REBOOTING", K.purple },
}
local function fmtNum(n)
  if type(n) ~= "number" then return tostring(n or "?") end
  local s = tostring(math.floor(n))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function fmtAgo(s)
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end
local function fmtMins(secs)
  if not secs then return "-" end
  if secs < 60 then return "under a min" end
  return math.ceil(secs / 60) .. " min"
end
local function pretty(id)
  local s = tostring(id):gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end
local function posText(s)
  if not s or not s.pos then return "position unknown" end
  return ("%d, %d, %d"):format(s.pos.x, s.pos.y, s.pos.z)
end
local function stateOf(id)
  local l = live[id]
  if not l then return "NO SIGNAL", K.grey end
  local st = l.s.state
  if l.s.paused and st == "docked" then st = "paused" end
  local m = STATES[st] or (st == "paused" and { "PAUSED", K.orange }) or { tostring(st or "?"):upper(), K.white }
  if os.clock() - l.seen > STALE then return m[1], K.grey end
  return m[1], m[2]
end
local function nameOf(id)
  local l, t = live[id], cfg.turtles[id]
  return (l and l.s.label) or (t and t.label) or ("Turtle #" .. id)
end
local function lastRoundText(s)
  local r = s and s.lastRound
  if not r then return "no round yet" end
  if s.role == "lumberjack" then return ("chopped %d, planted %d"):format(r.chopped or 0, r.planted or 0) end
  return ("harvested %d, planted %d"):format(r.harvested or 0, r.planted or 0)
end
local function nextText(s)
  if not s then return "" end
  if s.state == "working" and s.progress then return "round " .. s.progress end
  if s.paused then return "paused" end
  if s.nextRound then return "next in " .. fmtMins(s.nextRound) end
  return ""
end

local function ids()
  local out = {}
  for id in pairs(cfg.turtles) do out[#out + 1] = id end
  table.sort(out, function(a, b)
    local na, nb = nameOf(a):lower(), nameOf(b):lower()
    if na ~= nb then return na < nb end
    return a < b
  end)
  return out
end

local function problems()
  local n, worst = 0, nil
  for _, id in ipairs(ids()) do
    local l = live[id]
    local bad = not l or os.clock() - l.seen > STALE or l.s.state == "error" or l.s.state == "lost" or l.s.state == "waiting"
    if bad then
      n = n + 1
      worst = worst or (nameOf(id) .. ": " .. (not l and "never heard" or os.clock() - l.seen > STALE and "silent"
        or tostring(l.s.msg or l.s.state)))
    end
  end
  return n, worst
end

---------------------------------------------------------------------------
-- Screens: monitor + the computer's own screen, each with its own page
---------------------------------------------------------------------------
local function newUi() return { page = "overview", id = nil, scroll = 1, notice = nil, confirm = nil, follow = true } end
local function findMonitor()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then return peripheral.wrap(side), side end
  end
end
local mon, monSide = findMonitor()
local views = {
  { dev = function() return mon end, kind = "monitor", hits = {}, ui = newUi() },
  { dev = function() return term end, kind = "term", hits = {}, ui = newUi() },
}
local ui = views[2].ui

local d, hits
local function at(x, y, text, fg, bg)
  d.setCursorPos(x, y)
  d.setBackgroundColour(bg or K.black)
  d.setTextColour(fg or K.white)
  d.write(text)
end
local function pad(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s > w then return s:sub(1, w) end
  return s .. (" "):rep(w - #s)
end
local function lr(x, y, w, left, right, fgL, fgR)
  left = tostring(left)
  if right then
    right = tostring(right):sub(1, w)
    -- Never let the two halves run into each other: the label gives way first
    local room = w - #right - 1
    if #left > room then left = room > 0 and left:sub(1, room) or "" end
  end
  at(x, y, pad(left, w), fgL or K.lightGrey)
  if right then at(x + w - #right, y, right, fgR or K.white) end
end
local function bar(x, y, w, frac, colour)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  at(x, y, (" "):rep(w), K.white, K.grey)
  if n > 0 then at(x, y, (" "):rep(n), K.white, colour) end
end
local function hit(x1, y1, x2, y2, fn) hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn } end
local function button(x, y, w, rows, label, bg, fn, fg)
  for r = 0, rows - 1 do at(x, y + r, (" "):rep(w), K.black, bg) end
  label = label:sub(1, w)
  at(x + math.floor((w - #label) / 2), y + math.floor(rows / 2), label, fg or K.black, bg)
  hit(x, y, x + w - 1, y + rows - 1, fn)
end
local function smallButton(x, y, label, bg, fn, fg)
  at(x, y, " " .. label .. " ", fg or K.black, bg)
  hit(x, y, x + #label + 1, y, fn)
  return x + #label + 3
end
local function header(w, title, right)
  at(1, 1, (" "):rep(w), K.cyan, K.grey)
  at(2, 1, title, K.cyan, K.grey)
  if right and #right + #title + 4 < w then at(w - #right, 1, right, K.lightGrey, K.grey) end
  if ui.notice and os.clock() < ui.notice.untilT then at(2, 2, pad(ui.notice.text, w - 2), ui.notice.colour) end
end
local function say(text, colour)
  for _, v in ipairs(views) do v.ui.notice = { text = text, colour = colour or K.lime, untilT = os.clock() + 5 } end
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local function drawOverview(w, h)
  local list = ids()
  if radioOK == false and not (ui.notice and os.clock() < ui.notice.untilT) then
    ui.notice = { text = "No wireless/ender modem on me: the turtles can't hear me", colour = K.red, untilT = os.clock() + 1e9 }
  end
  local nProb = problems()
  header(w, "FARMHAND", ("%d turtle%s%s"):format(#list, #list == 1 and "" or "s",
    nProb > 0 and ("  " .. nProb .. " need" .. (nProb == 1 and "s" or "") .. " you") or "  all fine"))
  local top, bottom = 3, h - 2
  local rowH = (h >= 16) and 3 or 1
  local per = math.max(1, math.floor((bottom - top + 1) / rowH))
  local pages = math.max(1, math.ceil(#list / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))

  if #list == 0 then
    local lines = { "No farm turtles heard yet.", "Set up a turtle as Partridge (crops) or Woodpecker (trees):",
                    "it shows up here as soon as it's on the air." }
    for i, l in ipairs(lines) do at(2, top + i, pad(l, w - 2), i == 1 and K.white or K.lightGrey) end
  end

  for i = 1, per do
    local id = list[(ui.scroll - 1) * per + i]
    if not id then break end
    local l = live[id]
    local s = l and l.s
    local y = top + (i - 1) * rowH
    local st, colour = stateOf(id)
    local stale = not l or os.clock() - l.seen > STALE
    local bg = (rowH == 3) and K.black or (i % 2 == 0 and K.grey or K.black)
    at(1, y, (" "):rep(w), K.white, bg)
    at(2, y, pad(nameOf(id), 10), stale and K.lightGrey or K.white, bg)
    at(13, y, pad(st, 10), colour, bg)
    local bits = {}
    if s then
      bits[#bits + 1] = ROLE_NAME[s.role] or s.role or "?"
      if type(s.fuel) == "number" and type(s.fuelLimit) == "number" and s.fuelLimit > 0 then
        bits[#bits + 1] = ("fuel %d%%"):format(math.floor(s.fuel / s.fuelLimit * 100))
      end
      local nt = nextText(s)
      if nt ~= "" then bits[#bits + 1] = nt end
    end
    local arrow = w >= 56
    local room = w - 24 - (arrow and 3 or 0)
    if room > 4 then at(24, y, pad(table.concat(bits, "  "), room), stale and K.grey or K.lightGrey, bg) end
    if arrow then at(w - 1, y, ">", K.cyan, bg) end
    if rowH == 3 then
      local left
      if stale then
        left = l and ("not heard for " .. fmtAgo(math.floor(os.clock() - l.seen))) or "never heard from"
      elseif s.state == "docked" and s.lastRound then
        left = "Last round: " .. lastRoundText(s)
      else
        left = tostring(s.msg or "")
      end
      local where = s and s.pos and posText(s) or ""
      local roomL = w - 5 - #where - 2
      at(4, y + 1, pad(left, roomL), stale and K.grey or (s and (s.state == "error" or s.state == "lost") and K.orange or K.lightGrey))
      if #where > 0 then at(w - #where, y + 1, where, K.grey) end
    end
    hit(1, y, w, y + rowH - 1, function() ui.page, ui.id, ui.confirm = "turtle", id, nil end)
  end

  local fy = h
  at(1, fy, (" "):rep(w))
  local x = 2
  if #list > 0 then
    x = smallButton(x, fy, "Rounds all", K.lime, function()
      for _, id in ipairs(ids()) do order(id, "rounds") end
      say("Every farm turtle is off on its rounds.")
    end)
    x = smallButton(x, fy, "Pause all", K.orange, function()
      for _, id in ipairs(ids()) do order(id, "stop") end
      say("Every farm turtle will stay docked (Go to start again).", K.orange)
    end)
    if w >= 50 then
      x = smallButton(x, fy, "Reboot all", K.purple, function()
        for _, id in ipairs(ids()) do requestReboot(id) end
        say("Reboot sent: each finishes what it's doing, then restarts.", K.purple)
      end, K.white)
    end
  end
  if pages > 1 then
    local label = ("%d/%d"):format(ui.scroll, pages)
    local px = w - #label - 9
    if px > x then
      smallButton(px, fy, "<", ui.scroll > 1 and K.cyan or K.grey, function() ui.scroll = ui.scroll - 1 end)
      at(px + 4, fy, label, K.lightGrey)
      smallButton(w - 3, fy, ">", ui.scroll < pages and K.cyan or K.grey, function() ui.scroll = ui.scroll + 1 end)
    end
  end
end

---------------------------------------------------------------------------
-- One turtle
---------------------------------------------------------------------------
local function drawStatus(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  local st, colour = stateOf(id)
  local function line(fn) if y <= maxY then fn() end y = y + 1 end
  line(function() at(x, y, pad(st, w), colour) end)
  line(function() at(x, y, pad(s and s.msg or "Waiting to hear from it", w), K.lightGrey) end)
  line(function() at(x, y, pad(l and ("Seen " .. fmtAgo(math.floor(os.clock() - l.seen)) .. " ago") or "Never heard", w), K.grey) end)
  y = y + 1
  local f, lim = s and s.fuel, s and s.fuelLimit
  local frac = (type(f) == "number" and type(lim) == "number" and lim > 0) and f / lim or 1
  line(function() lr(x, y, w, "Fuel", type(f) == "number" and fmtNum(f) or (f or "-")) end)
  line(function() bar(x, y, w, s and frac or 0, frac < 0.1 and K.red or K.lime) end)
  if s and s.role == "lumberjack" then
    line(function() lr(x, y, w, "Zone", s.mapped and ("%s blocks, %s trees"):format(fmtNum(s.cells), fmtNum(s.spots)) or "not mapped") end)
    line(function() lr(x, y, w, "Saplings", fmtNum(s.saplings)) end)
  else
    line(function()
      local crop = s and s.crop and pretty(tostring(s.crop):gsub("_seeds$", ""):gsub("^.-:", "")) or nil
      lr(x, y, w, "Farm", s and s.mapped and (fmtNum(s.plots) .. " plots" .. (crop and (", " .. crop) or "")) or "not mapped")
    end)
    line(function() lr(x, y, w, "Seeds", s and fmtNum(s.seeds) or "-") end)
  end
  line(function() lr(x, y, w, "Last round", s and lastRoundText(s) or "-") end)
  line(function() lr(x, y, w, "Next", s and (nextText(s) ~= "" and nextText(s) or "-") or "-") end)
  line(function() lr(x, y, w, "Rounds done", s and fmtNum(s.rounds) or "-") end)
  y = y + 1
  line(function() lr(x, y, w, "At", posText(s), K.lightGrey, K.white) end)
  line(function() lr(x, y, w, s and s.facing and ("facing " .. s.facing) or "", s and s.home and ("home %d, %d, %d"):format(s.home.x, s.home.y, s.home.z) or "", K.lightGrey, K.lightGrey) end)
  line(function()
    local txt = not s and "-" or s.anchored and "pinned to GPS: never lost" or s.gps and "GPS seen, not pinned yet" or "no GPS: counting moves"
    lr(x, y, w, "GPS", txt, K.grey, s and not s.anchored and K.orange or K.grey)
  end)
  return y
end

local function drawHaul(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  local function list(title, items)
    if y > maxY then return end
    at(x, y, pad(title, w), K.grey); y = y + 1
    if (not items or #items == 0) and y <= maxY then at(x, y, pad("Nothing yet", w), K.grey); y = y + 1 end
    for _, e in ipairs(items or {}) do
      if y > maxY then break end
      lr(x, y, w, pretty(e[1]), fmtNum(e[2]), K.white, K.cyan)
      y = y + 1
    end
    y = y + 1
  end
  list("LAST HAUL", s and s.lastHaul)
  list("BROUGHT IN SO FAR", s and s.totals)
  return y
end

local function drawControls(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  local t = cfg.turtles[id] or {}
  local bh = (maxY - y >= 22) and 3 or 1
  local gap = bh == 3 and 1 or 0
  local function big(label, bg, fn, fg)
    if y + bh - 1 > maxY then return end
    button(x, y, w, bh, label, bg, fn, fg); y = y + bh + gap
  end
  big("ROUNDS NOW", K.lime, function() order(id, "rounds"); say(nameOf(id) .. " is off on its rounds.") end)
  if s and s.paused then
    big("GO", K.lime, function() order(id, "go"); say(nameOf(id) .. " is back on its timer.") end)
  else
    big("PAUSE", K.orange, function() order(id, "stop"); say(nameOf(id) .. " will stay docked.", K.orange) end)
  end
  big("RE-MAP", K.lightBlue, function() order(id, "survey"); say(nameOf(id) .. " will walk its farm again.", K.lightBlue) end)
  if s and s.state == "lost" then
    big("FOUND", K.yellow, function()
      order(id, "found"); say("Put " .. nameOf(id) .. " on its home spot first: it works out the rest.", K.yellow)
    end)
  end
  local pendingReboot = t.reboot ~= nil
  big(pendingReboot and "REBOOTING..." or "REBOOT", K.purple, function()
    requestReboot(id); say(nameOf(id) .. " reboots once it's finished what it's doing.", K.purple)
  end, K.white)

  -- Settings
  if y + 1 > maxY then return end
  y = y + (gap > 0 and 0 or 1)
  at(x, y, pad("SETTINGS", w), K.grey); y = y + 1
  for _, def in ipairs(SETTINGS[s and s.role or ""] or {}) do
    if y > maxY then break end
    local k, label, unit, step, mn, mx = def[1], def[2], def[3], def[4], def[5], def[6]
    local v, pending = settingValue(id, k)
    local val = (v == nil) and "?" or (tostring(v) .. (unit ~= "" and (" " .. unit) or ""))
    if k == "RESURVEY_EVERY" and v == 0 then val = "never" end
    local bx = x + w - 3
    local vx = bx - 1 - #val
    local mxL = vx - 4 - x - 1                 -- room left for the label
    if #label > mxL then label = label:gsub("^Rounds every", "Every"):gsub("^Re%-map every", "Re-map"):gsub("^Keep ", "") end
    at(x, y, pad(label:sub(1, math.max(0, mxL)), w), K.lightGrey)
    at(math.max(x, vx - 4), y, " - ", K.black, (v and v > mn) and K.cyan or K.grey)
    hit(math.max(x, vx - 4), y, math.max(x, vx - 4) + 2, y, function()
      if type(v) == "number" then changeSetting(id, k, math.max(mn, v - step)) end
    end)
    at(vx, y, val, pending and K.yellow or K.white)
    at(bx, y, " + ", K.black, (v and v < mx) and K.cyan or K.grey)
    hit(bx, y, bx + 2, y, function()
      if type(v) == "number" then changeSetting(id, k, math.min(mx, v + step)) end
    end)
    y = y + 1
  end
  if y <= maxY then at(x, y, pad("Yellow = sent, not confirmed yet", w), K.grey) end
end

local function drawTurtle(w, h)
  local id = ui.id
  if not cfg.turtles[id] then ui.page = "overview"; return drawOverview(w, h) end
  header(w, "< " .. nameOf(id), "computer #" .. id)
  hit(1, 1, math.min(w, 16), 1, function() ui.page = "overview" end)
  if w >= 44 then
    local cw = math.floor((w - 3) / 2)
    local y = drawStatus(id, 2, 3, cw, h - 1)
    drawHaul(id, 2, y + 1, cw, h - 1)
    drawControls(id, cw + 3, 3, w - cw - 3, h - 2)
  else
    local y = drawStatus(id, 1, 3, w, h - 1)
    drawControls(id, 1, y + 1, w, h - 2)
  end
  local l = live[id]
  local stale = not l or os.clock() - l.seen > 120
  local x = 2
  if stale then
    if ui.confirm == "forget" then
      x = smallButton(x, h, "Sure? Forget it", K.red, function()
        cfg.turtles[id] = nil; live[id] = nil; saveCfg(); ui.page, ui.confirm = "overview", nil
        say("Forgotten. If it talks again it comes back.", K.orange)
      end, K.white)
    else
      x = smallButton(x, h, "Forget", K.grey, function() ui.confirm = "forget" end, K.white)
    end
  end
  smallButton(w - 15, h, "Map", K.cyan, function() ui.page, ui.confirm, ui.follow = "map", nil, true; mapAskedAt[id] = nil end)
  smallButton(w - 7, h, "Back", K.grey, function() ui.page, ui.confirm = "overview", nil end, K.white)
end

---------------------------------------------------------------------------
-- Map page: the farm from above, what's planted where, and where the turtle is right now
---------------------------------------------------------------------------
local HEX = "0123456789abcdef"
local BLIT = {}
for i = 0, 15 do BLIT[2 ^ i] = HEX:sub(i + 1, i + 1) end
local ARROW = { [0] = "\30", "\16", "\31", "\17" }      -- facing north / east / south / west
local SPADE = "\6"                                        -- looks like a little tree

-- Crop colours (by the seed/crop id); anything else gets one from the spare list
local CROP_COLOURS = {
  { "wheat", K.yellow }, { "carrot", K.orange }, { "potato", K.white }, { "beetroot", K.red },
  { "nether_wart", K.red }, { "melon", K.lime }, { "pumpkin", K.orange }, { "hemp", K.lime },
  { "immersiveengineering", K.lime }, { "mysticalagriculture", K.magenta }, { "berr", K.pink },
  { "sugar_cane", K.lime }, { "cotton", K.white }, { "flax", K.lightBlue },
}
local SPARE = { K.cyan, K.pink, K.lightBlue, K.purple, K.white, K.lime, K.yellow }
local function cropColour(name, i)
  name = tostring(name)
  for _, c in ipairs(CROP_COLOURS) do if name:find(c[1], 1, true) then return c[2] end end
  return SPARE[((i or 1) - 1) % #SPARE + 1]
end
local function cropName(id)
  local n = tostring(id):gsub("^.-:", ""):gsub("_seeds?$", ""):gsub("_crop$", ""):gsub("_", " ")
  if n == "seed" then n = "hemp" end
  return (n:gsub("^%l", string.upper))
end

-- One cell -> character, text colour, background
local function cellLook(m, c, st)
  if c == " " then return " ", K.black, K.black end
  if c == "#" then return " ", K.grey, K.grey end                          -- slab border
  if c == "@" then return "D", K.black, K.yellow end                       -- dock barrel
  if c == "%" then return "\127", K.grey, K.black end                      -- something solid
  if c == "," then return "~", K.lightBlue, K.blue end                     -- water / path
  if c == "&" then return "o", K.orange, K.brown end                       -- pumpkin/melon spot
  if m.role == "lumberjack" then
    if c == "." then return " ", K.green, K.green end                      -- lane
    if c == "!" then return SPADE, K.lime, K.brown end                     -- wild tree, gets chopped
    if c == "+" then
      if st == "h" then return SPADE, K.yellow, K.green end                -- chopped + replanted
      if st == "g" then return SPADE, K.lime, K.green end                  -- sapling growing
      if st == "e" then return "+", K.red, K.green end                     -- nothing planted
      return "+", K.lightGrey, K.green                                     -- not visited yet
    end
  end
  if c == "." then return " ", K.grey, K.black end
  if c == "*" then return ".", K.lightGrey, K.brown end
  local i = c:byte() - 96
  if i >= 1 and i <= 26 then
    local name = m.crops and m.crops[i]
    local letter = cropName(name or "?"):sub(1, 1)
    if st == "e" then return ".", K.red, K.brown end                       -- empty: no seed
    local col = cropColour(name, i)
    if st == "h" then return letter:upper(), col, K.brown end              -- harvested last round
    return letter:lower(), col, K.brown                                    -- growing
  end
  return "?", K.white, K.black
end

local function mapStats(m)
  local n = { cells = 0 }
  local perCrop = {}
  for r = 1, m.h do
    local row, srow = m.rows[r], m.states[r] or ""
    for c = 1, m.w do
      local ch, st = row:sub(c, c), srow:sub(c, c)
      if ch ~= " " and ch ~= "#" and ch ~= "%" then n.cells = n.cells + 1 end
      n[ch] = (n[ch] or 0) + 1
      local key = ch .. st
      n[key] = (n[key] or 0) + 1
      local i = ch:byte() - 96
      if i >= 1 and i <= 26 then
        perCrop[i] = perCrop[i] or { all = 0, h = 0, g = 0, e = 0 }
        perCrop[i].all = perCrop[i].all + 1
        if st ~= " " then perCrop[i][st] = (perCrop[i][st] or 0) + 1 end
      end
    end
  end
  return n, perCrop
end

local function drawMap(w, h)
  local id = ui.id
  if not cfg.turtles[id] then ui.page = "overview"; return drawOverview(w, h) end
  local m = maps[id]
  local l = live[id]
  local s = l and l.s
  local stale = not l or os.clock() - l.seen > STALE
  local sub = m and not m.none and (m.north and "north is up" or "up = way it faced when mapped") or ""
  header(w, "< " .. nameOf(id) .. " - map", sub)
  hit(1, 1, math.min(w, 24), 1, function() ui.page = "turtle" end)
  local function footer()
    at(1, h, (" "):rep(w))
    smallButton(w - 7, h, "Back", K.grey, function() ui.page = "turtle" end, K.white)
  end
  if not m or m.none then
    at(2, 4, pad(not m and "Asking " .. nameOf(id) .. " for its map..." or "It hasn't mapped its farm yet.", w - 2), K.lightGrey)
    if not m and s and s.mapStamp == nil then
      at(2, 6, pad("No map from it yet: reboot it once so it gets the new program.", w - 2), K.orange)
    end
    footer()
    return
  end

  -- Layout: map on the left, key on the right if there's room for both, else the key goes below
  local side = 22
  local top, bottom = 3, h - 2
  local cw = 2
  local useSide = w - 2 >= m.w * 2 + side or (w - 2 >= m.w + side and w >= 60)
  local areaW = useSide and (w - side - 2) or (w - 2)
  if m.w * 2 > areaW then cw = 1 end
  local keyRows = useSide and 0 or 2
  local areaH = bottom - top + 1 - keyRows
  local cols, rows = math.floor(areaW / cw), areaH
  local fitsX, fitsY = m.w <= cols, m.h <= rows

  -- Where the turtle is on the map (it reports its spot in the map's own frame)
  local tc, tr
  if s and s.mp and s.mapStamp then
    tc, tr = s.mp.x - m.x0 + 1, s.mp.z - m.z0 + 1
  end
  -- Scroll: centre on the turtle while following, otherwise where the arrows left it
  if ui.follow or ui.mapC == nil then
    ui.mapC = tc and (tc - math.floor(cols / 2)) or 1
    ui.mapR = tr and (tr - math.floor(rows / 2)) or 1
  end
  ui.mapC = fitsX and 1 or math.max(1, math.min(ui.mapC, m.w - cols + 1))
  ui.mapR = fitsY and 1 or math.max(1, math.min(ui.mapR, m.h - rows + 1))
  local ox = 2 + (fitsX and math.floor((cols - m.w) / 2) * cw or 0)
  local oy = top + (fitsY and math.floor((rows - m.h) / 2) or 0)

  for r = 0, math.min(rows, m.h) - 1 do
    local mr = ui.mapR + r
    local row, srow = m.rows[mr] or "", m.states[mr] or ""
    local txt, fg, bg = {}, {}, {}
    for c = 0, math.min(cols, m.w) - 1 do
      local mc = ui.mapC + c
      local ch, f, b = cellLook(m, row:sub(mc, mc), srow:sub(mc, mc))
      if tc and mc == tc and mr == tr then
        ch, f, b = ARROW[s.mp.h or 0] or "@", K.white, stale and K.grey or K.magenta
      end
      for _ = 1, cw do
        txt[#txt + 1] = ch; fg[#fg + 1] = BLIT[f]; bg[#bg + 1] = BLIT[b]
        if ch ~= "\127" then ch = " " end    -- 2-wide cells: the symbol once, then a blank
      end
    end
    d.setCursorPos(ox, oy + r)
    d.blit(table.concat(txt), table.concat(fg), table.concat(bg))
  end
  -- Tap a cell: say what's there
  local shownW, shownH = math.min(cols, m.w) * cw, math.min(rows, m.h)
  hit(ox, oy, ox + shownW - 1, oy + shownH - 1, function(x, y)
    local mc, mr = ui.mapC + math.floor((x - ox) / cw), ui.mapR + (y - oy)
    local ch = (m.rows[mr] or ""):sub(mc, mc)
    local st = (m.states[mr] or ""):sub(mc, mc)
    local what = ({ ["#"] = "the slab border", ["@"] = "the dock barrel", ["%"] = "something solid",
      [","] = "water or a path (skipped)", ["&"] = "pumpkin/melon spot", ["."] = "lane",
      ["!"] = "a wild tree (gets chopped, then it's a lane)", ["*"] = "a plot (crop not known yet)", [" "] = "outside the farm" })[ch]
    if ch == "+" then what = "tree spot: " .. (({ h = "chopped last round, replanted", g = "sapling growing", e = "nothing planted (no sapling)" })[st] or "not visited yet") end
    local i = ch ~= "" and ch:byte() - 96 or 0
    if i >= 1 and i <= 26 then
      what = cropName(m.crops[i] or "?") .. ": " .. (({ h = "harvested last round, replanted", g = "growing", e = "empty (no seeds)" })[st] or "not visited yet")
    end
    if tc and mc == tc and mr == tr then what = nameOf(id) .. " is here" end
    local wx, wz
    if tc and s.pos and m.north then                   -- world coords from its own position
      wx, wz = s.pos.x + (mc - tc), s.pos.z + (mr - tr)
    end
    say((wx and ("%d, %d: "):format(wx, wz) or "") .. (what or "?"), K.white)
  end)

  -- Key
  local n, perCrop = mapStats(m)
  local lines = {}
  local function add(ch, f, b, text, colour, short) lines[#lines + 1] = { ch, f, b, text, colour, short } end
  add(ARROW[s and s.mp and s.mp.h or 0], K.white, stale and K.grey or K.magenta,
    nameOf(id) .. (stale and " (not heard)" or (tc and "" or " (off the map)")), stale and K.grey or K.white)
  if m.role == "lumberjack" then
    add(SPADE, K.yellow, K.green, ("chopped+replanted %d"):format(n["+h"] or 0), nil, ("replanted %d"):format(n["+h"] or 0))
    add(SPADE, K.lime, K.green, ("saplings %d"):format(n["+g"] or 0))
    add("+", K.red, K.green, ("empty spots %d"):format(n["+e"] or 0), (n["+e"] or 0) > 0 and K.orange or nil,
      ("empty %d"):format(n["+e"] or 0))
    if (n["+ "] or 0) > 0 then add("+", K.lightGrey, K.green, ("not visited %d"):format(n["+ "]), nil, "unvisited") end
    if (n["!"] or 0) > 0 then add(SPADE, K.lime, K.brown, ("wild trees %d"):format(n["!"]), nil, "wild") end
    add(" ", K.green, K.green, "lane")
  else
    for i, name in ipairs(m.crops or {}) do
      local pc = perCrop[i] or { all = 0, h = 0, g = 0, e = 0 }
      add(cropName(name):sub(1, 1):upper(), cropColour(name, i), K.brown,
        ("%s %d"):format(cropName(name), pc.all) .. ((pc.e or 0) > 0 and (" (" .. pc.e .. " empty)") or ""),
        (pc.e or 0) > 0 and K.orange or nil, cropName(name))
    end
    add("A", K.white, K.brown, "capital = harvested", nil, "harvested")
    add("a", K.white, K.brown, "small = growing", nil, "growing")
    add(".", K.red, K.brown, "empty (no seeds)", nil, "empty")
    if (n[","] or 0) > 0 then add("~", K.lightBlue, K.blue, "water / path", nil, "water") end
    if (n["&"] or 0) > 0 then add("o", K.orange, K.brown, "pumpkin/melon spot", nil, "gourd") end
  end
  add("D", K.black, K.yellow, "dock")
  add(" ", K.grey, K.grey, "slab border", nil, "border")
  if (n["%"] or 0) > 0 then add("\127", K.grey, K.black, "blocked") end
  local ago = m.roundAt and fmtAgo(math.max(0, math.floor((os.epoch("utc") - m.roundAt) / 1000))) or nil
  if useSide then
    local kx, y = w - side + 1, top
    for _, e in ipairs(lines) do
      if y > bottom then break end
      at(kx, y, e[1], e[2], e[3]); at(kx + 1, y, " " .. pad(e[4], side - 3), e[5] or K.lightGrey)
      y = y + 1
    end
    y = y + 1
    if y <= bottom then at(kx, y, pad(("%dx%d, %d blocks"):format(m.w, m.h, n.cells), side - 1), K.grey); y = y + 1 end
    if y <= bottom then at(kx, y, pad(ago and ("last round " .. ago .. " ago") or "no round yet", side - 1), K.grey); y = y + 1 end
    if y <= bottom and s and s.progress then at(kx, y, pad("round " .. s.progress .. " (live)", side - 1), K.lime) end
  else
    -- Compact: the most useful entries across two rows
    local y, x = bottom - 1, 2
    for i, e in ipairs(lines) do
      local text = i == 1 and (stale and "(not heard)" or "here") or (e[6] or e[4])
      local len = #text + 3
      if x + len > w then y = y + 1; x = 2 end
      if y > bottom then break end
      at(x, y, e[1], e[2], e[3]); at(x + 1, y, " " .. text, e[5] or K.lightGrey)
      x = x + len
    end
  end

  -- Footer: panning when the map is bigger than the screen
  at(1, h, (" "):rep(w))
  local x = 2
  if not (fitsX and fitsY) then
    local step = math.max(2, math.floor(math.min(cols, rows) / 3))
    local function pan(dc, dr) return function()
      ui.follow = false
      ui.mapC, ui.mapR = ui.mapC + dc, ui.mapR + dr
    end end
    x = smallButton(x, h, "\17", K.cyan, pan(-step, 0))
    x = smallButton(x, h, "\30", K.cyan, pan(0, -step))
    x = smallButton(x, h, "\31", K.cyan, pan(0, step))
    x = smallButton(x, h, "\16", K.cyan, pan(step, 0))
    x = smallButton(x, h, ui.follow and "Following" or "Follow", ui.follow and K.lime or K.grey,
      function() ui.follow = true end, ui.follow and K.black or K.white)
  elseif w >= 40 then
    at(x, h, "Tap a block to see what's there", K.grey)
  end
  smallButton(w - 7, h, "Back", K.grey, function() ui.page = "turtle" end, K.white)
end

local function draw()
  for _, v in ipairs(views) do
    d = v.dev()
    if d then
      hits = {}
      ui = v.ui
      local ok = pcall(function()
        if v.kind == "monitor" then d.setTextScale(TEXT_SCALE) end
        local w, h = d.getSize()
        if not w then return end
        d.setBackgroundColour(K.black); d.clear()
        if ui.page == "turtle" then drawTurtle(w, h)
        elseif ui.page == "map" then drawMap(w, h)
        else drawOverview(w, h) end
      end)
      v.hits = hits
      if not ok and v.kind == "monitor" then mon, monSide = findMonitor() end
    end
  end
end

---------------------------------------------------------------------------
-- Radio
---------------------------------------------------------------------------
local function sendOrder(id)
  local t = cfg.turtles[id]
  local l = live[id]
  if t.reboot and os.epoch("utc") - (t.rebootAt or 0) > REBOOT_WAIT then
    t.reboot, t.rebootAt = nil, nil
    saveCfg()
    say(nameOf(id) .. " never confirmed its reboot: old program? Reboot it by hand once.", K.orange)
  end
  local msg = { type = "cmd", to = id }
  local need = false
  if t.seq and not (l and (l.s.seq or 0) >= t.seq) then msg.want, msg.seq = t.want, t.seq; need = true end
  if t.setSeq and t.set and not (l and (l.s.setSeq or 0) >= t.setSeq) then msg.set, msg.setSeq = t.set, t.setSeq; need = true end
  if t.reboot then msg.reboot = t.reboot; need = true end
  if need then rednet.send(id, msg, PROTOCOL) end
end

local function summary()
  local n = 0
  for _ in pairs(cfg.turtles) do n = n + 1 end
  local nProb, worst = problems()
  local working = 0
  for id, l in pairs(live) do if cfg.turtles[id] and l.s.state == "working" and os.clock() - l.seen <= STALE then working = working + 1 end end
  return { type = "farmhand", id = os.getComputerID(), label = os.getComputerLabel() or "Farmhand",
           turtles = n, working = working, problems = nProb,
           note = nProb > 0 and worst or (n == 0 and "no farm turtles yet"
             or ("%d turtle%s, %s"):format(n, n == 1 and "" or "s", working > 0 and (working .. " working") or "all docked")) }
end

local function netLoop()
  local opened = 0
  radioOK = false
  peripheral.find("modem", function(name, m)
    rednet.open(name); opened = opened + 1
    if m.isWireless() then radioOK = true end
    return false
  end)
  if opened == 0 then
    say("No modem! I need a wireless or ender modem to reach the farm turtles.", K.red)
    while true do draw(); os.sleep(5) end
  end
  local lastSend, lastSummary = -100, -100
  while true do
    local from, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "status" and (msg.role == "farmer" or msg.role == "lumberjack") then
      local id = tonumber(msg.id) or from
      live[id] = { s = msg, seen = os.clock() }
      local t = cfg.turtles[id]
      if not t or t.label ~= msg.label or t.role ~= msg.role then
        t = entry(id); t.label, t.role = msg.label, msg.role; saveCfg()
      end
      if t.reboot and msg.rebootDone == t.reboot and msg.state ~= "rebooting" then
        t.reboot, t.rebootAt = nil, nil; saveCfg()
        say(nameOf(id) .. " is back up.", K.lime)
      end
    end
    if type(msg) == "table" and msg.type == "map" and cfg.turtles[tonumber(msg.id) or from] then
      maps[tonumber(msg.id) or from] = msg
    end
    -- Maps: only fetched while someone's looking at one, and again whenever the turtle says it changed
    for _, v in ipairs(views) do
      local mid = v.ui.page == "map" and v.ui.id
      if mid then
        local l, m = live[mid], maps[mid]
        local changed = not m or (l and l.s.mapStamp and l.s.mapStamp ~= m.stamp)
        if changed and os.clock() - (mapAskedAt[mid] or -100) >= 5 then
          rednet.send(mid, { type = "mapreq", to = mid }, PROTOCOL)
          mapAskedAt[mid] = os.clock()
        end
      end
    end
    local all = os.clock() - lastSend >= SEND_EVERY
    for id in pairs(cfg.turtles) do if all or sendNow[id] then sendOrder(id) end end
    sendNow = {}
    if all then lastSend = os.clock() end
    if os.clock() - lastSummary >= 5 then rednet.broadcast(summary(), PROTOCOL); lastSummary = os.clock() end
    draw()
  end
end

local function inputLoop()
  while true do
    local e, a, b, c = os.pullEvent()
    local v, x, y
    if e == "monitor_touch" and a == monSide then v, x, y = views[1], b, c
    elseif e == "mouse_click" then v, x, y = views[2], b, c
    elseif e == "mouse_scroll" then
      local u = views[2].ui
      if u.page == "overview" then u.scroll = u.scroll + a
      elseif u.page == "map" then u.follow = false; u.mapR = (u.mapR or 1) + a * 3 end
      draw()
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      mon, monSide = findMonitor(); draw()
    end
    if v then
      ui = v.ui
      for _, r in ipairs(v.hits) do
        if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then r.fn(x, y); break end
      end
      draw()
    end
  end
end

loadCfg()
draw()
parallel.waitForAny(netLoop, inputLoop)
