-- base.lua  --  runs the Island Station, Storage and Miner Panel together on one computer.
-- (Started by startup.lua after it has pulled the latest files from GitHub.)
--
-- Monitor wall layout:   [ island strip, 3 lines ]
--                        [ divider               ]
--                        [ storage touch screen  ]
-- Miner panel: its own monitor (1x3 or 3x2). The first time two screens are attached,
-- you're asked to tap the miner panel once so the computer knows which is which.
-- The keyboard belongs to storage (search, /setup, ...).
-- Any program can be missing or crash; the others keep running.

local STATION_LINES = 3
local TEXT_SCALE    = 0.5
local MON_CONFIG    = "monitors.cfg"

-- Find monitors and decide which is the wall and which is the miner panel
local names = {}
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.hasType(n, "monitor") then names[#names + 1] = n end
end

local mcfg = {}
if fs.exists(MON_CONFIG) then
  local f = fs.open(MON_CONFIG, "r"); mcfg = textutils.unserialize(f.readAll()) or {}; f.close()
end
local function present(n) for _, m in ipairs(names) do if m == n then return true end end return false end

local panelName
if #names >= 2 then
  if not (mcfg.panel and present(mcfg.panel)) then
    for _, n in ipairs(names) do
      local m = peripheral.wrap(n)
      m.setTextScale(1); m.setBackgroundColour(colours.black); m.clear()
      m.setCursorPos(1, 1); m.setTextColour(colours.yellow); m.write("Miner panel?")
      m.setCursorPos(1, 2); m.write("Tap me if so")
    end
    print("Two screens found. Tap the MINER PANEL screen.")
    local _, side = os.pullEvent("monitor_touch")
    mcfg.panel = side
    local f = fs.open(MON_CONFIG, "w"); f.write(textutils.serialize(mcfg)); f.close()
    print("Saved: miner panel is " .. side)
  end
  panelName = mcfg.panel
end

-- The wall is the biggest monitor that isn't the panel
local wallName, best = nil, -1
for _, n in ipairs(names) do
  if n ~= panelName then
    local m = peripheral.wrap(n); m.setTextScale(TEXT_SCALE)
    local w, h = m.getSize()
    if w * h > best then wallName, best = n, w * h end
  end
end

-- A window that looks like a monitor to the scripts (they call setTextScale, which windows lack)
local function asMonitor(win)
  return setmetatable({ setTextScale = function() end }, { __index = win })
end

local stationTarget, storageTarget, panelTarget, offset
if wallName then
  local mon = peripheral.wrap(wallName)
  mon.setTextScale(TEXT_SCALE)          -- set before making windows: they keep their size
  local w, h = mon.getSize()
  mon.setBackgroundColour(colours.black); mon.clear()
  mon.setCursorPos(1, STATION_LINES + 1)
  mon.setBackgroundColour(colours.grey); mon.clearLine()
  offset = STATION_LINES + 1
  stationTarget = asMonitor(window.create(mon, 1, 1, w, STATION_LINES))
  storageTarget = asMonitor(window.create(mon, 1, offset + 1, w, h - offset))
else
  local w, h = term.getSize()
  stationTarget = asMonitor(window.create(term.current(), 1, 1, w, h, false)) -- hidden
end
if panelName then panelTarget = peripheral.wrap(panelName) end

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

parallel.waitForAll(
  runScript("island.lua",       sandbox(stationTarget, true, nil),                 "Island station", wallName and stationTarget),
  runScript("storage.lua",      sandbox(storageTarget, false, wallName, offset),   "Storage",        wallName and storageTarget),
  runScript("miner_panel.lua",  sandbox(panelTarget, true, panelName),             "Miner panel",    panelTarget),
  runScript("rigger_link.lua",  sandbox(nil, true, nil),                           "Rigger link",    nil),
  runScript("farm_link.lua",    sandbox(nil, true, nil),                           "Farm link",      nil)
)
