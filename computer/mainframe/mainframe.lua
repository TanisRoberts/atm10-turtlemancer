-- mainframe.lua  --  the island's "server": chat commands, alerts, displays (CC:Tweaked, ATM10)
-- Started by startup.lua after it has pulled the latest files from GitHub.
--
-- Needs: an Advanced Computer with a wireless or ender modem, an Environment Detector, and
-- optionally a Chat Box. Storage and smelting run on their own computers; the mainframe hears
-- from them over the network (base_link.lua) and shows everything.
--
-- Monitor wall layout:   [ island strip, 3 lines                  ]
--                        [ divider                                ]
--                        [ status board: every machine | visitors ]
-- The visitor column only appears when the wall is wide enough (VISITOR_W + 30 characters).
-- butler.lua (Inventory Manager + Player Detector) draws the visitor column.
-- Only monitors touching the computer count; the biggest one is the wall.
-- Mining control lives on its own computer now (the Foreman); dig_link just listens to the Diggers.
-- Any program can be missing or crash; the others keep running.

local STATION_LINES = 3
local TEXT_SCALE    = 0.5
local VISITOR_W     = 20   -- width of the visitor column right of the status board (0 = none)

-- Find the monitors: the biggest one is the wall.
-- Only monitors touching the computer count: screens out on the cable belong to other computers.
local names = {}
for _, n in ipairs(rs.getSides()) do
  if peripheral.hasType(n, "monitor") then names[#names + 1] = n end
end

-- The wall is the biggest monitor
local wallName, best = nil, -1
for _, n in ipairs(names) do
  do
    local m = peripheral.wrap(n); m.setTextScale(TEXT_SCALE)
    local w, h = m.getSize()
    if w * h > best then wallName, best = n, w * h end
  end
end

-- A window that looks like a monitor to the scripts (they call setTextScale, which windows lack)
local function asMonitor(win)
  return setmetatable({ setTextScale = function() end }, { __index = win })
end

local stationTarget, boardTarget, visitorTarget, offset
if wallName then
  local mon = peripheral.wrap(wallName)
  mon.setTextScale(TEXT_SCALE)          -- set before making windows: they keep their size
  local w, h = mon.getSize()
  mon.setBackgroundColour(colours.black); mon.clear()
  mon.setCursorPos(1, STATION_LINES + 1)
  mon.setBackgroundColour(colours.grey); mon.clearLine()
  offset = STATION_LINES + 1
  stationTarget = asMonitor(window.create(mon, 1, 1, w, STATION_LINES))
  local boardW = w
  if VISITOR_W > 0 and w >= VISITOR_W + 30 then
    boardW = w - VISITOR_W - 1
    mon.setBackgroundColour(colours.grey)                 -- 1-column divider
    for y = offset + 1, h do mon.setCursorPos(boardW + 1, y); mon.write(" ") end
    mon.setBackgroundColour(colours.black)
    visitorTarget = asMonitor(window.create(mon, boardW + 2, offset + 1, VISITOR_W, h - offset))
  end
  boardTarget = asMonitor(window.create(mon, 1, offset + 1, boardW, h - offset))
else
  local w, h = term.getSize()
  stationTarget = asMonitor(window.create(term.current(), 1, 1, w, h, false)) -- hidden
end

-- Give a script its own view of the world: its own "monitor", optional silenced print,
-- only the touches from its own screen, shifted so its window's top row is y = 1.
local function sandbox(target, quiet, screenName, yOffset)
  local env = {}
  env.peripheral = setmetatable({
    find = function(kind, ...)
      if kind == "monitor" then return target end
      return peripheral.find(kind, ...)
    end,
  }, { __index = peripheral })
  if quiet then env.print = function() end end
  env.os = setmetatable({
    pullEvent = function(filter)
      while true do
        local ev = table.pack(os.pullEvent(filter))
        if ev[1] ~= "monitor_touch" then return table.unpack(ev, 1, ev.n) end
        if ev[2] == screenName then
          local y = ev[4] - (yOffset or 0)
          if y >= 1 then
            ev[4] = y
            return table.unpack(ev, 1, ev.n)
          end
        end
        -- touches on other screens, the island strip or the divider are ignored
      end
    end,
  }, { __index = os })
  return env
end

local function runScript(path, env, label, target)
  return function()
    if not fs.exists(path) then
      if target then
        target.setCursorPos(2, 1); target.setTextColour(colours.grey)
        target.write(label .. " not installed (" .. path .. ")")
      end
      return os.pullEvent("never")
    end
    local ok, res = pcall(os.run, env, path)
    local err = not ok and res or (res and "finished" or "crashed, see the computer screen")
    if target then
      target.setCursorPos(2, 1); target.setTextColour(colours.red)
      target.write((label .. " stopped: " .. tostring(err)):sub(1, 200))
    end
    printError(label .. " stopped: " .. tostring(err))
    return os.pullEvent("never") -- keep the other programs running
  end
end

term.clear(); term.setCursorPos(1, 1)
print("Mainframe running: island station, status board, butler, links.")
print("Reboot (hold Ctrl+R) to update. Type reset to give this computer a new role.")
parallel.waitForAll(
  runScript("island.lua",       sandbox(stationTarget, true, nil),                 "Island station", wallName and stationTarget),
  runScript("board.lua",        sandbox(boardTarget, true, nil),                   "Status board",   wallName and boardTarget),
  runScript("butler.lua",       sandbox(visitorTarget, true, nil),                 "Butler",         wallName and visitorTarget),
  runScript("base_link.lua",    sandbox(nil, true, nil),                           "Base link",      nil),
  runScript("dig_link.lua",     sandbox(nil, true, nil),                           "Digger link",    nil),
  runScript("rigger_link.lua",  sandbox(nil, true, nil),                           "Rigger link",    nil),
  runScript("farm_link.lua",    sandbox(nil, true, nil),                           "Farm link",      nil)
)
