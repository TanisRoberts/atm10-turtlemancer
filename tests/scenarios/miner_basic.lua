-- Miner: first-run setup at the dock, a number from the Foreman, then one order to mine.
-- Canary: one dock barrel (Mining Dimension). Starling: DUMP + FUEL barrels (the End).
-- A tiny stand-in Foreman answers on the radio (tests/sim/miners.lua); the real ones have their own scenarios.
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

-- Dock at 0,64,0 facing north, stone below (Y 40..63). Canary: one dock barrel east with coal in it.
-- Starling (two = true): dump barrel east, fuel barrel west.
local function base(two)
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:stone")
  local dock, fuel = MS.barrel(), nil
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  if two then
    fuel = MS.barrel()
    fuel:give("minecraft:coal", 64)
    w:setBlock(-1, 64, 0, "minecraft:barrel", fuel)
  else
    dock:give("minecraft:coal", 64)
  end
  local t = MS.turtle(w)
  return w, t, dock, fuel
end

T.test("miner: first-run setup in the Mining Dimension finds its one dock barrel", function()
  local w, t = base()
  t:run("miner")
  w:run(1)
  T.contains(t.screen, "Dimension")
  T.contains(t.screen, "Mining")
  t:key(257)                                      -- Enter: Mining is the default
  w:run(20)
  T.running(t)
  T.contains(t:output(), "GPS says I'm at 0 64 0")
  T.contains(t:output(), "I'm facing north")
  T.contains(t:output(), "Dock barrel: on my right")
  T.contains(t:output(), "I'm a Canary (allthemodium:mining)")
  local st = t:readTable("miner.state")
  T.eq(st.dockY, 64); T.eq(st.dockDir, 1); T.eq(st.dumpDir, nil)
  T.eq(t.body.x, 0, "back on the dock"); T.eq(t.body.y, 64); T.eq(t.body.z, 0)
end)

T.test("miner: a Starling in the End finds its dump and fuel barrels", function()
  local w, t = base(true)
  MS.setup(w, t, "4")
  w:run(20)
  T.running(t)
  T.contains(t:output(), "Fuel barrel: on my left. Dump barrel: on my right")
  T.contains(t:output(), "I'm a Starling (the_end)")
  local st = t:readTable("miner.state")
  T.eq(st.dumpDir, 1); T.eq(st.fuelDir, 3); T.eq(st.dockDir, nil)
end)

T.test("miner: the Foreman names it and it writes startup.lua for auto-resume", function()
  local w, t = base()
  MS.foreman(w)
  MS.setup(w, t)
  w:run(30)
  T.eq(t.label, "Canary-01")
  T.eq(t:readFile("startup.lua"), 'shell.run("miner")\n')
  T.eq(t:readTable("miner.state").num, 1)
end)

-- A dock chunk with three ores in it and the Foreman's order to mine Y 60..63.
local function mineWorld(two, dim)
  local w, t, dock, fuel = base(two)
  local f = MS.foreman(w)
  w:setBlock(3, 62, 3, "minecraft:iron_ore")
  w:setBlock(5, 61, 7, "minecraft:diamond_ore")
  w:setBlock(9, 62, 12, "minecraft:coal_ore")
  MS.setup(w, t, dim)
  w:run(10)
  return w, t, dock, fuel, f
end

T.test("miner: a Canary mines its chunk, brings the ore home and leaves the barrel alone", function()
  local w, t, dock, _, f = mineWorld()
  MS.order(f)
  T.waitFor(w, MS.finished(f), 1200, "never finished the range")
  T.running(t)
  T.eq(dock:count("minecraft:diamond"), 1)
  T.eq(dock:count("minecraft:raw_iron"), 1)
  T.truthy(w:getBlock(1, 64, 0), "dock barrel still standing")
  T.eq(w:count("minecraft:iron_ore", 0, 40, 0, 15, 63, 15), 0, "iron ore left behind")
  T.eq(w:count("minecraft:diamond_ore", 0, 40, 0, 15, 63, 15), 0, "diamond ore left behind")
  T.eq(t.body.x, 0); T.eq(t.body.y, 64); T.eq(t.body.z, 0)
  T.truthy(t.body.fuel > 400, "took fuel from his dock when nobody answered")
  for _, s in pairs(t.body.slots) do T.falsy(s.name == "minecraft:diamond", "nothing valuable left in the bag") end
end)

T.test("miner: a Starling mines with its two barrels", function()
  local w, t, dump, fuel, f = mineWorld(true, "4")
  MS.order(f)
  T.waitFor(w, MS.finished(f), 1200, "never finished the range")
  T.running(t)
  T.eq(dump:count("minecraft:diamond"), 1)
  T.eq(dump:count("minecraft:raw_iron"), 1)
  T.eq(dump:count("minecraft:coal"), 1)
  T.truthy(w:getBlock(1, 64, 0) and w:getBlock(-1, 64, 0), "dock barrels still standing")
  T.truthy(t.body.fuel > 400, "refuelled from the fuel barrel")
end)

T.test("miner: a reboot in the middle of a run resumes where it was", function()
  local w, t, dock, _, f = mineWorld()
  MS.order(f)
  w:run(150)
  T.eq(f.env._G.lastStatus.state, "mining")
  t:reboot()                                      -- chunk unload / server restart: startup.lua runs the miner again
  w:run(5)
  T.running(t)
  T.waitFor(w, MS.finished(f), 1500, "never finished after the reboot")
  T.eq(dock:count("minecraft:diamond"), 1)
  T.eq(dock:count("minecraft:raw_iron"), 1)
end)

T.test("miner: with a chunk controller he swaps it on as he goes (core.chunk) and keeps his modem", function()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:stone")
  local dock = MS.barrel()
  dock:give("minecraft:coal", 64)
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  local t = MS.turtle(w, { items = { [16] = { "advancedperipherals:chunk_controller", 1 } } })
  local f = MS.foreman(w)
  MS.setup(w, t)
  w:run(10)
  T.contains(t:output(), "Chunk controller on board")
  MS.order(f)
  T.waitFor(w, MS.finished(f), 1200, "never finished the range")
  local s = f.env._G.lastStatus
  T.eq(s.chunky, true)
  T.truthy((s.swaps or 0) >= 2, "swapped at the start and during the run")
  T.eq(s.chunkyNote, nil)
  T.eq(t.body.up.right, "computercraft:wireless_modem_advanced")
  local n = 0
  for _, sl in pairs(t.body.slots) do if sl.name == "advancedperipherals:chunk_controller" then n = n + sl.count end end
  T.eq(n, 1, "controller still in the bag")
end)
