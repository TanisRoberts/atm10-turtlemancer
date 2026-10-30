-- storage_screens.lua  --  storage: the item list (monitor touch and the computer's search bar), the "/" commands,
-- report pages, the lock screen and the two kit loops. Built only from the UI kit (docs/systems/ui.md); nothing here
-- writes to a terminal behind its back. The sorting and moving logic stays in storage.lua, which hands over what the
-- screens need in S (docs/design/storage.md). Part of computer/storage/storage.lua.

return function(S)
local ui = require("ui")
local slash = require("slash")
local lock = dofile("storage_lock.lua")
local fit = ui.text.fit
local TEXT_SCALE = S.TEXT_SCALE

local Scr = {}

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
local function commas(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
local function fmt(n)
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e4 then return ("%dk"):format(math.floor(n / 1e3)) end
  return commas(n)
end
Scr.fmt, Scr.commas = fmt, commas

---------------------------------------------------------------------------
-- Take amounts: x1, x16 or one stack (shared by the monitor and the computer's screen)
---------------------------------------------------------------------------
local takeMode = "stack"
local TAKE = { { id = "x1", label = "x1" }, { id = "x16", label = "x16" }, { id = "stack", label = "Stack" } }
local AMOUNT = { x1 = 1, x16 = 16 }

local function take(e)
  local cfg = S.cfg()
  if not cfg.output then ui.say("No output chest yet: /assign on the computer", "warn"); return end
  local n, full = S.send(e.key, AMOUNT[takeMode] or e.max or 64)
  ui.say(n > 0 and ("Sent %d %s%s"):format(n, e.label, full and " (output full)" or "") or "Output chest is full",
    n > 0 and "good" or "warn")
end

---------------------------------------------------------------------------
-- Views: the computer's own screen and the monitor touching it. Only a monitor touching a side belongs to this
-- computer (screens out on the cable belong to other computers); this is the one place that looks for it.
---------------------------------------------------------------------------
local function findMonitor()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then
      local m = peripheral.wrap(side)
      local ok, w = pcall(m.getSize)
      if ok and w then return m, side end
    end
  end
end

local termView = ui.view(term.current())
local monViews = {}
local function syncMonitor()
  local mon, name = findMonitor()
  local cur = monViews[1]
  if cur and cur.side == name then
    if mon then cur.t = mon; cur:measure() end
    if not mon then monViews[1] = nil end
    return
  end
  monViews[1] = mon and ui.view(mon, { side = name, scale = TEXT_SCALE }) or nil
end
syncMonitor()

local state = { page = "list" }                 -- the computer's own screen: list, report or busy
local monState = { f = ui.field{ max = 1 } }     -- the monitor: always the list, no typing
state.f = ui.field{ hint = "type to search, / for commands", max = 60, on_commit = function()
  if state.first then take(state.first) end
end }

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
Scr.cmds = slash.new()
local cmds = Scr.cmds
-- The view's own commands go last in the list, after storage's (storage.lua adds those first), with /help at the very end.
function Scr.addViewCommands()
  for _, t in ipairs(TAKE) do
    cmds:add({ name = t.id, help = t.id == "stack" and "take a whole stack per tap" or ("take " .. t.id:sub(2) .. " per tap"),
      run = function() takeMode = t.id; return true, "Taking " .. t.label .. " per tap" end })
  end
  cmds:add({ name = "sort", args = "qty|az", min = 1, max = 1, help = "sort the list by count or name",
    run = function(a)
      local w = a.words[1]:lower()
      if w ~= "qty" and w ~= "az" then return false, "Say qty or az" end
      S.cfg().sort = w; S.saveCfg(); S.buildItems(); state.page = "list"
      return true, w == "az" and "Sorted A-Z" or "Sorted by count"
    end })
  cmds:add(cmds.byName.help)
end

-- Old names for a command: they still run (typed with or without the slash) and sit at the end of the "/" list.
local aliases = {}
function Scr.alias(old, target)
  cmds.byName[old] = cmds.byName[target]
  aliases[#aliases + 1] = { name = old, help = "old name for /" .. target,
    fn = function(arg) cmds:exec(target .. " " .. (arg or "")) end }
end
local function commandList()
  local out = cmds:commands()
  for _, a in ipairs(aliases) do out[#out + 1] = a end
  return out
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
local function shownItems(f)
  local items = S.items()
  local q = f.text
  if q == "" or q:sub(1, 1) == "/" then return items end
  q = q:lower()
  local out = {}
  for _, e in ipairs(items) do
    if e.label:lower():find(q, 1, true) or e.name:find(q, 1, true) then out[#out + 1] = e end
  end
  return out
end

local function drawList(v, st)
  local cfg, stats = S.cfg(), S.stats()
  local W = v.W
  local pct = stats.total > 0 and math.floor(stats.used / stats.total * 100) or 0
  local right = ("%s/%s slots  %d%%"):format(commas(stats.used), commas(stats.total), pct)
  local fuel = S.fuelPercent()
  if fuel then right = ("Fuel %d%%  "):format(fuel) .. right end
  if not v.side and S.isLocked() then right = "MONITOR LOCKED  " .. right end
  v:header("STORAGE", { state = pct >= 90 and ("%d%% full"):format(pct) or "ok", color = pct >= 90 and "warn" or "good", right = right })

  -- Row 3: sort, and take buttons where they fit (the computer's row, else the footer on a monitor)
  local sortId = cfg.sort == "az" and "az" or "qty"
  v:put(2, 3, "Sort", "dim", "bg")
  local nx = v:switch(7, 3, { { id = "qty", label = "Qty" }, { id = "az", label = "A-Z" } }, sortId, function(id)
    cfg.sort = id; S.saveCfg(); S.buildItems(); v.page = 1
  end, { id = "sort" })
  local function takeSwitch(x, y, maxx)
    v:switch(x, y, TAKE, takeMode, function(id) takeMode = id end, { id = "take", maxx = maxx })
  end
  local top = 4
  if not v.side and W >= 39 then
    takeSwitch(math.max(nx + 1, W - 16), 3, W - 1)
  elseif v.side and W < 30 then
    takeSwitch(2, 4, W - 1); top = 5
  end

  local list = shownItems(st.f)
  st.first = list[1]
  local rows = {}
  for _, e in ipairs(list) do rows[#rows + 1] = { name = e.label, value = fmt(e.count), e = e } end
  if #list == 0 then
    v:put(2, top, fit(st.f.text ~= "" and "Nothing matches." or "Empty. Drop items in the input chest.", W - 2), "dim", "bg")
  end
  v:list(rows, { top = top, input = not v.side, once = true, on = function(row) take(row.e) end })
  v:footer({})
  if v.side and W >= 30 then takeSwitch(1, v.H, W - 14) end
  if not v.side then v:search(st.f, { hint = W >= 39 and "type to search, / for commands" or "search, / commands", commands = commandList() }) end
end

local function drawReport(v, st)
  local r = st.report
  v:report({ title = r.title, state = r.state, color = r.color, right = r.right, rows = r.rows,
    back = function() st.page = "list"; v.page = 1 end })
end

local function drawBusy(v, st)
  local b = st.busy
  v:header(b.title, { state = "working", color = "busy" })
  local y = v:spinner_line(2, 4, b.line or "")
  for _, l in ipairs(b.lines or {}) do
    if y < v.H then v:put(2, y, fit(l, v.W - 2), "dim", "bg"); y = y + 1 end
  end
end

local lastErr
local function draw(v)
  local st = v.side and monState or state
  if v.side then
    local locked, why = S.isLocked()
    if locked then lock.draw(v, why, TEXT_SCALE); return end
    lock.release(v, TEXT_SCALE)
  end
  local page = v.side and "list" or st.page
  local fn = page == "report" and drawReport or page == "busy" and drawBusy or drawList
  local ok, err = pcall(fn, v, st)
  if not ok and err ~= lastErr then lastErr = err; ui.say("Screen error: " .. tostring(err), "bad") end
end

---------------------------------------------------------------------------
-- What the commands use: report pages, progress, a plain screen for prompts, a screen that takes over (/assign)
---------------------------------------------------------------------------
-- { title, state, color, right, rows = { { section }, { key, value, tone }, { alert, tone }, { text, tone } } }
function Scr.report(r)
  state.report, state.page = r, "report"
  termView.page = 1
end

-- A long command's progress: shows at once (the loop is busy running the command).
function Scr.progress(title, line, lines)
  state.busy, state.page = { title = title, line = line, lines = lines }, "busy"
  termView:frame(draw)
end
function Scr.idle() state.page = "list"; termView.page = 1 end

-- Prompts written with print/read (the marker /setup, a dock's keep list) get a cleared terminal, then the kit again.
function Scr.plain(fn)
  term.setCursorBlink(false)
  term.setBackgroundColour(colours.black); term.setTextColour(colours.white)
  term.clear(); term.setCursorPos(1, 1)
  local ok, err = pcall(fn)
  termView:invalidate()
  state.page = "list"
  if not ok then ui.say("Error: " .. tostring(err), "bad") end
end

-- Run fn once the command that asked has returned and the term loop has stopped (it needs a loop of its own).
function Scr.later(fn)
  Scr.pending = fn
  ui.quit()
end

Scr.view = function() return termView end
Scr.findMonitor = findMonitor

---------------------------------------------------------------------------
-- The loops: the computer's screen and the monitor each run a kit loop, side by side
---------------------------------------------------------------------------
local function termLoop()
  while true do
    local fn = Scr.pending
    if fn then
      Scr.pending = nil
      local ok, err = pcall(fn)
      if not ok then ui.say("Error: " .. tostring(err), "bad") end
      termView:invalidate()
      state.page = "list"
    end
    ui.run({ termView }, draw, { tick = 1 })
  end
end

local function monLoop()
  while true do
    ui.run(monViews, draw, { tick = 1, on_event = function(e)
      if e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then syncMonitor() end
    end })
  end
end

function Scr.loop() parallel.waitForAny(termLoop, monLoop) end

return Scr
end
