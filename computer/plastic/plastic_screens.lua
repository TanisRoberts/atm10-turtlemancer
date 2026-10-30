-- plastic_screens.lua  --  plastic factory: its screens, built only from the UI kit (docs/systems/ui.md,
-- design: docs/design/plastic.md). One dashboard on the computer's own screen and on the monitor, a report page for
-- /status and /list, and the typed commands (shared/slash.lua). Machine logic stays in plastic.lua, which hands over
-- what the screen needs:
--   S.snap()         -> the current picture: { cfg, F, tapState, unitState, furnState, problems, note, dockFuel,
--                       dockPlastic, rate (plastic/h or nil), state ("running"|"paused"|"waiting"), furnaceOn }
--   S.lines()        -> the status lines (also sent to the mainframe)
--   S.setPaused(p), S.scan(), S.findMonitor() -> wrapped monitor, its peripheral name (or nil)
--   S.unitCap        -> a unit's tank size in mB
-- Returns { run = fn }: run() is the event loop (taps, keys, typed commands) and never returns.

local ui = require("ui")
local slash = require("slash")
local fit = ui.text.fit

return function(S)
local views = { ui.view(term.current()) }
local states = { term = { page = "home" }, monitor = { page = "home" } }
local function stateFor(v) return states[v.side and "monitor" or "term"] end

local function pct(a, b) if not b or b <= 0 then return 0 end return math.floor(a / b * 100 + 0.5) end
local function num(n)
  local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return s
end
local function short(n) return n:match("_(%d+)$") or n end
local function tapWord(s) return s.stalled and "DRY" or s.full and "full" or "ok", s.stalled and "bad" or s.full and "warn" or "good" end
local function problemList(snap)
  local out = {}
  for _, msg in pairs(snap.problems) do out[#out + 1] = (msg:gsub("^Plastic factory: ", "")) end
  table.sort(out)
  return out
end

---------------------------------------------------------------------------
-- The monitor is looked up in plastic.lua (S.findMonitor); the view gets its peripheral name so taps find it
---------------------------------------------------------------------------
local function syncMonitor()
  local mon, name = S.findMonitor()
  if views[2] and views[2].side == name then views[2].t = mon or views[2].t; views[2]:measure(); return end
  views[2] = mon and ui.view(mon, { side = name }) or nil
end

---------------------------------------------------------------------------
-- The dashboard
---------------------------------------------------------------------------
local TAP_W = 12
local function tapCells(v, snap, x, y, w, last)
  local per = math.max(1, math.floor((w + 1) / TAP_W))
  for i, t in ipairs(snap.F.taps) do
    local row, col = math.floor((i - 1) / per), (i - 1) % per
    if y + row > last then break end
    local word, tone = tapWord(snap.tapState[t] or {})
    v:put(x + col * TAP_W, y + row, fit(("#%s %s"):format(short(t), word), TAP_W - 1), tone, "bg")
  end
  return y + math.ceil(#snap.F.taps / per)
end

local function furnaceLines(snap)
  local out = {}
  for _, fz in ipairs(snap.F.furnaces) do
    local s = snap.furnState[fz] or {}
    out[#out + 1] = { ("Furnace %s: %d cooking, fuel %d%s"):format(short(fz), s.cooking or 0, s.fuel or 0,
      snap.furnaceOn and "" or " (FURNACE=no)"), "fg" }
  end
  if #snap.F.furnaces == 0 then out[#out + 1] = { "No furnace: rubber goes to the dock, then the smelter", "dim" } end
  if snap.F.dock then
    out[#out + 1] = { ("Dock: fuel for %d, %d plastic out"):format(snap.dockFuel, snap.dockPlastic), "fg" }
  else
    out[#out + 1] = { "Dock: none found", "warn" }
  end
  return out
end

-- Everything on the full page, as blocks of known height, so the page can tell whether it fits before it draws.
local function fullBlocks(v, snap, probs)
  local W = v.W
  local blocks = {}
  for _, u in ipairs(snap.F.units) do
    local s = snap.unitState[u] or {}
    blocks[#blocks + 1] = { h = s.cap and 4 or 3, draw = function(y)
      y = v:section(2, y, W - 2, "Latex unit " .. short(u))
      v:bar(2, y, W - 2, "latex", (s.latex or 0) / S.unitCap, { kind = "progress" }); y = y + 1
      v:bar(2, y, W - 2, "water", (s.water or 0) / S.unitCap, { kind = "progress" }); y = y + 1
      if s.cap then v:bar(2, y, W - 2, "power", (s.energy or 0) / s.cap, { kind = "fuel" }); y = y + 1 end
    end }
  end
  if #snap.F.units == 0 then
    blocks[#blocks + 1] = { h = 1, draw = function(y) v:alert(2, y, W - 2, "No latex unit on the cable", "warn") end }
  end
  if #snap.F.taps > 0 then
    local per = math.max(1, math.floor((W - 2 + 1) / TAP_W))
    blocks[#blocks + 1] = { h = 1 + math.ceil(#snap.F.taps / per), draw = function(y)
      y = v:section(2, y, W - 2, "Taps")
      tapCells(v, snap, 2, y, W - 2, v.H)
    end }
  end
  local fl = furnaceLines(snap)
  blocks[#blocks + 1] = { h = 1 + #fl, draw = function(y)
    y = v:section(2, y, W - 2, "Furnaces and dock")
    for _, l in ipairs(fl) do v:put(2, y, fit(l[1], W - 2), l[2], "bg"); y = y + 1 end
  end }
  if #probs > 0 then
    blocks[#blocks + 1] = { h = #probs, draw = function(y)
      for _, m in ipairs(probs) do v:alert(2, y, W - 2, m, "bad"); y = y + 1 end
    end }
  end
  return blocks
end

-- The short page: one line per thing, problems first.
local function compactPage(v, snap, probs, y, last)
  local W = v.W - 2
  local function line(text, tone, alert)
    if y > last then return end
    if alert then v:alert(2, y, W, text, tone) else v:put(2, y, fit(text, W), tone or "fg", "bg") end
    y = y + 1
  end
  for _, m in ipairs(probs) do line(m, "bad", true) end
  for _, u in ipairs(snap.F.units) do
    local s = snap.unitState[u] or {}
    line(("Unit %s L%d W%d%s"):format(short(u), pct(s.latex or 0, S.unitCap), pct(s.water or 0, S.unitCap),
      s.cap and (" P" .. pct(s.energy or 0, s.cap)) or ""))
  end
  if #snap.F.units == 0 then line("No latex unit on the cable", "warn") end
  local dry = 0
  for _, t in ipairs(snap.F.taps) do if (snap.tapState[t] or {}).stalled then dry = dry + 1 end end
  line(("Taps %d ok%s"):format(#snap.F.taps - dry, dry > 0 and (", " .. dry .. " DRY") or ""), dry > 0 and "bad" or "good")
  local cooking = 0
  for _, fz in ipairs(snap.F.furnaces) do cooking = cooking + ((snap.furnState[fz] or {}).cooking or 0) end
  line(#snap.F.furnaces > 0 and ("Furnace: %d cooking"):format(cooking) or "No furnace")
  line(snap.F.dock and ("Dock fuel %d"):format(snap.dockFuel) or "No dock", snap.F.dock and "dim" or "warn")
end

local function dashboard(v, snap)
  local W, H = v.W, v.H
  local last = H - 1 - (v.side and 0 or 1)                       -- the command bar sits above the footer
  local right = snap.rate and ("~%.1f plastic/h"):format(snap.rate) or nil
  v:header("Plastic factory", { state = snap.state, right = right,
    color = snap.state == "running" and "good" or snap.state == "paused" and "warn" or "gold" })
  local made = ("Made %s plastic"):format(num(snap.cfg.plastic))
  local probs = problemList(snap)
  local blocks = fullBlocks(v, snap, probs)
  local y = 3
  -- roomy (a blank row between blocks), tight (none), else the short page
  local gap
  for _, g in ipairs({ 1, 0 }) do
    local need = 3
    for _, b in ipairs(blocks) do need = need + g + b.h end
    if need <= last and W >= 26 and H >= 16 then gap = g; break end
  end
  if gap then
    v:put(2, y, fit(made, W - 2), "fg", "bg"); y = y + 1
    for _, b in ipairs(blocks) do
      y = y + gap
      b.draw(y); y = y + b.h
    end
  else
    local r = snap.rate and ("  ~%.1f/h"):format(snap.rate) or ""
    v:put(2, y, fit(("Made %s%s"):format(num(snap.cfg.plastic), r), W - 2), "fg", "bg")
    compactPage(v, snap, probs, y + 1, last)
  end
  v:footer({})
  v:buttons(2, H, { { label = snap.cfg.paused and "Run" or "Pause", id = "pause",
    style = snap.cfg.paused and "primary" or "idle", fn = function() S.setPaused(not snap.cfg.paused) end } })
end

---------------------------------------------------------------------------
-- /status and /list
---------------------------------------------------------------------------
local function report(v, st, snap)
  local rows = {}
  for _, r in ipairs(st.rows) do rows[#rows + 1] = r end
  if st.page == "status" then
    for _, m in ipairs(problemList(snap)) do rows[#rows + 1] = { alert = m, tone = "bad" } end
  end
  v:report{ title = st.title, state = snap.state, color = snap.state == "running" and "good" or "warn",
    rows = rows, back = function() st.page = "home"; v.page = 1 end }
end

local function openReport(page, title, rows)
  local v, st = views[1], states.term
  st.page, st.title, st.rows = page, title, rows
  v.page = 1
end

---------------------------------------------------------------------------
-- Typed commands
---------------------------------------------------------------------------
local cmds = slash.new()
cmds:add({ name = "status", help = "what is going on", max = 0, run = function()
  local rows = {}
  for _, l in ipairs(S.lines()) do rows[#rows + 1] = { text = l } end
  openReport("status", "Status", rows)
  return true, "Status", "plain"
end })
cmds:add({ name = "list", help = "what I found on my cable", max = 0, run = function()
  S.scan()
  local F = S.snap().F
  local rows = {}
  local function group(title, list)
    rows[#rows + 1] = { section = title }
    if #list == 0 then rows[#rows + 1] = { text = "none", tone = "dim" } end
    for _, n in ipairs(list) do rows[#rows + 1] = { text = n } end
  end
  group("Taps", F.taps); group("Units", F.units); group("Water", F.water); group("Buffers", F.buffers)
  group("Furnaces", F.furnaces); group("Dock", { F.dock })
  if F.dockNote then rows[#rows + 1] = { alert = F.dockNote, tone = "warn" } end
  openReport("list", "On my cable", rows)
  return true, "On my cable", "plain"
end })
cmds:add({ name = "home", help = "back to the dashboard", max = 0, run = function()
  states.term.page = "home"; views[1].page = 1; return true, "Dashboard" end })
cmds:add({ name = "pause", help = "stop moving things (machines keep their contents)", max = 0,
  run = function() S.setPaused(true); return true, "Paused.", "warn" end })
cmds:add({ name = "stop", help = "same as /pause", max = 0,
  run = function() S.setPaused(true); return true, "Paused.", "warn" end })
for _, n in ipairs({ "resume", "go", "run" }) do
  cmds:add({ name = n, help = "carry on", max = 0, run = function() S.setPaused(false); return true, "Running." end })
end

local field
field = ui.field{ hint = "type a command, / lists them", max = 60,
  on_commit = function(t) field.text = ""; if not t:match("^%s*$") then cmds:exec(t) end end }

---------------------------------------------------------------------------
-- The loop
---------------------------------------------------------------------------
local lastErr
local function draw(v)
  local st = stateFor(v)
  local snap = S.snap()
  local ok, err = pcall(function()
    if v.side or st.page == "home" then dashboard(v, snap) else report(v, st, snap) end
  end)
  if not ok and err ~= lastErr then lastErr = err; ui.say("Screen error: " .. tostring(err), "bad") end
  if not v.side then v:search(field, { commands = cmds:commands() }) end
end

local function run()
  ui.loadAnim("plastic.env")
  syncMonitor()
  ui.run(views, draw, { tick = 1, on_event = function(e)
    if e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then syncMonitor() end
  end })
end

return { run = run, cmds = cmds, views = views }
end
