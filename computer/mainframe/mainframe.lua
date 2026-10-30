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
-- wall.lua draws all of it on the UI kit; island.lua, board.lua and butler.lua (Inventory Manager +
-- Player Detector) only hand it what to show. The visitor column only appears when the wall is wide enough.
-- Only monitors touching the computer count; the biggest one is the wall.
-- Mining control lives on its own computer now (the Foreman); dig_link just listens to the Canaries.
-- Any program can be missing or crash; the others keep running.

local TEXT_SCALE    = 0.5

-- Find the wall, the one place that looks: the biggest monitor touching the computer.
-- Monitors out on the cable belong to other computers.
local wallName, best = nil, -1
for _, n in ipairs(rs.getSides()) do
  if peripheral.hasType(n, "monitor") then
    local m = peripheral.wrap(n); m.setTextScale(TEXT_SCALE)
    local w, h = m.getSize()
    if w * h > best then wallName, best = n, w * h end
  end
end

-- Give a script its own view of the world: optional silenced print.
local function sandbox(quiet)
  local env = {}
  -- os.run gives a program the globals only, and `require` belongs to the shell's program (not a global), so pass it on
  env.require = require
  if quiet then env.print = function() end end
  return env
end

local function runScript(path, env, label)
  return function()
    if not fs.exists(path) then
      return os.pullEvent("never")
    end
    local ok, res = pcall(os.run, env, path)
    local err = not ok and res or (res and "finished" or "crashed, see the computer screen")
    printError(label .. " stopped: " .. tostring(err))
    return os.pullEvent("never") -- keep the other programs running
  end
end

-- The wall: wall.lua draws on the monitor, given its peripheral name so taps find it.
local function runWall()
  if not wallName then return os.pullEvent("never") end
  local ok, err = pcall(function() require("wall").run(peripheral.wrap(wallName), wallName) end)
  printError("Wall stopped: " .. tostring(err))
  return os.pullEvent("never")
end

term.clear(); term.setCursorPos(1, 1)
print("Mainframe running: island station, status board, butler, links.")
print("Reboot (hold Ctrl+R) to update. Type reset to give this computer a new role.")
parallel.waitForAll(
  runWall,
  runScript("island.lua",        sandbox(true), "Island station"),
  runScript("board.lua",         sandbox(true), "Status board"),
  runScript("butler.lua",        sandbox(true), "Butler"),
  runScript("base_link.lua",     sandbox(true), "Base link"),
  runScript("dig_link.lua",      sandbox(true), "Canary link"),
  runScript("weaver_link.lua",   sandbox(true), "Weaver link"),
  runScript("farm_link.lua",     sandbox(true), "Farm link"),
  runScript("operator_link.lua", sandbox(true), "Operator link")
)
