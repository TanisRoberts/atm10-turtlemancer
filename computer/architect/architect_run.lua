-- architect_run.lua  --  commands, drawing, the event loops and start(). A part of architect.lua.

local floor, max, min = math.floor, math.max, math.min

---------------------------------------------------------------------------
-- Commands (typed on the command bar; with a leading / the bar lists them)
---------------------------------------------------------------------------
local function cmdLayer(arg)
  local n = tonumber(arg)
  if not (P and n and n >= 1 and n <= P.total) then ui.say("layer 1 to " .. (P and P.total or "?"), "warn"); return end
  V.layer, V.follow, V.tab = n, false, "map"
end
COMMANDS = {
  { name = "build", help = "start or continue the build", fn = function() sendOrder("build") end },
  { name = "stop", help = "stop and go home", fn = function() sendOrder("stop") end },
  { name = "home", help = "go to the dock", fn = function() sendOrder("home") end },
  { name = "reboot", help = "reboot (and update) at the dock", fn = function() sendOrder("reboot") end },
  { name = "refresh", help = "ask him for his status now", fn = function() sendOrder("status") end },
  { name = "layer", help = "layer <n>: look at a layer on the map", fn = cmdLayer },
  { name = "follow", help = "map follows the Weaver again", fn = function() V.layer, V.follow = nil, true end },
  { name = "setup", help = "open the setup wizard", fn = function() openWizard(S.n and 2 or 1) end },
  { name = "monitors", help = "pick the monitor again", fn = function() scr:repick("wall"); os.reboot() end },
  { name = "help", help = "list the commands", fn = function()
      local names = {}
      for _, c in ipairs(COMMANDS) do names[#names + 1] = c.name end
      ui.say(table.concat(names, " "), "plain")
    end },
}
V.cmd = ui.field({ hint = "type a command (help)", max = 40, on_commit = function(text)
  local word, arg = text:match("^%s*/?(%S+)%s*(.-)%s*$")
  V.cmd.text = ""
  if not word then return end
  for _, c in ipairs(COMMANDS) do if c.name == word:lower() then c.fn(arg); return end end
  ui.say("Unknown command " .. word .. ". Try help.", "warn")
end })

---------------------------------------------------------------------------
-- Monitor
---------------------------------------------------------------------------
scr = require("screens").new({ slots = { { id = "wall", label = "the Architect map", required = false, scale = 0.5 } } })
views = {}
function syncMonitor()
  local dev, side = scr:current("wall")
  if views[2] and (not dev or views[2].side ~= side) then pcall(function() views[2]:close() end); views[2] = nil end
  if dev and not views[2] then
    pcall(dev.setTextScale, 0.5)
    views[2] = ui.view(dev, { side = side })
  end
end

function draw(v)
  if v.side then drawMonitor(v); return end
  if V.mode == "wizard" then drawWizard(v); return end
  drawTab(v)
  v:search(V.cmd, { commands = COMMANDS, hint = "type a command (help)" })
  v:footer({ tabs = TABS, tab = V.tab, on_tab = function(id) V.tab = id end })
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function radioLoop()
  while true do
    local from, msg, proto = rednet.receive(nil, 1)
    if type(msg) == "table" then
      if proto == PROTOCOL then onWeaver(from, msg) elseif proto == BASE then onBase(from, msg) end
    end
    pump()
  end
end

-- a dropped file is read here, in its own coroutine, so the screen keeps going while it converts
local function readLoop()
  while true do
    local _, name, bytes = os.pullEvent("arch_file")
    local ok, err = pcall(readFile, name, bytes)
    if not ok then R.read = { name = name, err = "could not read it: " .. tostring(err) } end
    os.queueEvent("arch_read_done")
  end
end

local function onDrop(obj)
  local files = obj and obj.getFiles and obj.getFiles() or {}
  local f = files[1]
  if not f then return end
  local okMode = V.mode == "wizard" and (V.step == 2 or V.sub == "relink")
  if not okMode then ui.say("Type setup first, then drop the file", "warn"); if f.close then f.close() end; return end
  local name = f.getName and f.getName() or "file"
  local bytes = f.readAll()
  if f.close then f.close() end
  if #files > 1 then ui.say("One file at a time: using " .. name, "warn") end
  if not bytes or #bytes == 0 then R.read = { name = name, err = "the file is empty" }; return end
  R.read = { name = name, size = #bytes, step = 0 }
  os.queueEvent("arch_file", name, bytes)
end

local function onEvent(e, a, b, ...)
  scr:handle(e, a, b, ...)
  if e == "file_transfer" then onDrop(a)
  elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" or e == "screens_changed" then syncMonitor()
  elseif e == "key" and V.mode == "tabs" and V.tab == "map" and P then
    if a == keys.pageUp or a == keys.pageDown then
      local k = viewLayer()
      V.layer, V.follow = min(max(k + (a == keys.pageUp and 1 or -1), 1), P.total), false
    end
  end
end

function start()
  if not fs.exists("startup.lua") then
    local f = fs.open("startup.lua", "w"); f.write('shell.run("architect")\n'); f.close()
  end
  openModem()
  local ln = (os.getComputerLabel() or ""):match("^Architect%-(%d+)$")
  if ln then S.n = tonumber(ln) end
  if S.n and (os.getComputerLabel() or "") ~= label() then os.setComputerLabel(label()) end
  if S.file then
    local ok, err = loadBuild()
    if not ok then addLog("the saved build could not be loaded: " .. tostring(err)); S.file, S.hash, S.started = nil, nil, false end
  end
  if S.started and not (P and siteOK(S.site)) then S.started = false end
  if S.order and S.order.want == "reboot" then S.order = nil end
  initialMode()
  views[1] = ui.view(term.current())
  scr:open()
  scr:get("wall")
  syncMonitor()
  term.clear(); term.setCursorPos(1, 1)
  parallel.waitForAny(
    function() ui.run(views, draw, { tick = 1, on_event = onEvent }) end,
    radioLoop,
    readLoop)
end
