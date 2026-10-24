-- Miner carried somewhere else (another dock, another dimension): he offers to set up there, keeping his
-- number and label, and never tunnels back to his old dock. Carried a little way: the old way home.
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

-- A Canary set up and numbered at 0,64,0 (dock barrel east), stone below. Returns w, t, f.
local function setUp()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:stone")
  local dock = MS.barrel()
  dock:give("minecraft:coal", 16)
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  local t = MS.turtle(w)
  local f = MS.foreman(w)
  MS.setup(w, t)
  w:run(30)
  T.eq(t.label, "Canary-01")
  return w, t, f
end

-- Pick him up and put him down at x, y, z facing `facing` (he reboots when placed)
local function carry(w, t, x, y, z, facing)
  t.body.x, t.body.y, t.body.z, t.body.facing = x, y, z, facing or 0
  t:reboot()
  w:run(3)
end

local function stoneLeft(w) return w:count("minecraft:stone", -20, 40, -20, 20, 63, 20) end

T.test("miner moved: carried to a new dock far away he offers to set up there and keeps his number", function()
  local w, t, f = setUp()
  local stone = stoneLeft(w)
  w:setBlock(40, 120, 41, "minecraft:barrel", MS.barrel())       -- the new dock's barrel, south of him
  carry(w, t, 40, 120, 40, 1)
  T.contains(t.screen, "I'VE BEEN MOVED")
  T.contains(t.screen, "I stay Canary-01")
  w:run(4)
  T.contains(f.env._G.lastStatus.msg, "confirm on my screen")
  t:type("1"); t:key(257)                                       -- yes, set up here
  w:run(1)
  T.contains(t.screen, "Dimension")
  t:key(257)                                                    -- Mining
  w:run(20)
  T.running(t)
  local st = t:readTable("miner.state")
  T.eq(st.home.x, 40); T.eq(st.home.y, 120); T.eq(st.home.z, 40)
  T.eq(st.dim, "allthemodium:mining")
  T.eq(st.num, 1, "kept his number")
  T.eq(st.dockDir, 1, "dock barrel on his right (he faces east, it is south)")
  T.eq(st.facing, 1)
  T.eq(t.label, "Canary-01", "kept his label")
  T.contains(t:output(), "I'm still Canary-01")
  T.eq(t.body.x, 40); T.eq(t.body.y, 120); T.eq(t.body.z, 40)
  T.eq(stoneLeft(w), stone, "never dug towards the old dock")
  w:run(10)
  T.eq(f.env._G.lastStatus.state, "docked")
  T.eq(f.env._G.lastStatus.num, 1)
end)

T.test("miner moved: carried far with no barrel next to him he waits to be carried back", function()
  local w, t, f = setUp()
  local stone = stoneLeft(w)
  carry(w, t, 300, 90, -200)
  MS.order(f)                                                   -- START doesn't send him tunnelling either
  w:run(60)
  T.running(t)
  T.contains(f.env._G.lastStatus.msg, "Carry me back to 0 64 0")
  T.eq(f.env._G.lastStatus.pos.x, 300)
  T.eq(t.body.x, 300); T.eq(t.body.y, 90); T.eq(t.body.z, -200)
  T.eq(stoneLeft(w), stone, "never dug anything")
  -- carried back onto his dock: he picks up where he was
  carry(w, t, 0, 64, 0)
  w:run(10)
  T.running(t)
  T.falsy(t:readTable("miner.state").far, "knows he's home")
end)

T.test("miner moved: saying no to the new dock leaves him waiting, not tunnelling", function()
  local w, t, f = setUp()
  local stone = stoneLeft(w)
  w:setBlock(41, 120, 40, "minecraft:barrel", MS.barrel())
  carry(w, t, 40, 120, 40)
  t:type("2"); t:key(257)
  w:run(30)
  T.running(t)
  T.contains(f.env._G.lastStatus.msg, "Carry me back")
  T.eq(t.body.x, 40); T.eq(t.body.y, 120)
  T.eq(stoneLeft(w), stone)
  T.eq(t:readTable("miner.state").home.x, 0, "still his old dock")
end)

T.test("miner moved: carried a few blocks along his own level he waits for an order, as before", function()
  local w, t, f = setUp()
  carry(w, t, 3, 64, 2)
  w:run(20)
  T.running(t)
  T.contains(f.env._G.lastStatus.msg, "Moved by hand")
  T.absent(t.screen, "I'VE BEEN MOVED")
end)

T.test("miner moved: a saved state with no dock barrel sets up again at boot, keeping his number", function()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:stone")
  local dock = MS.barrel()
  dock:give("minecraft:coal", 16)
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  local t = MS.turtle(w)
  t:writeTable("miner.state", { x = 0, y = 0, z = 0, h = 0, dockY = 64, home = { x = 0, y = 64, z = 0 }, facing = 0,
    num = 3, dim = "Mining Dimension", cbc = true, want = "dock" })
  t:run("miner"); w:run(2)
  T.contains(t:output(), "I don't know my dock barrel")
  t:key(257)                                      -- Mining
  w:run(20)
  T.running(t)
  local st = t:readTable("miner.state")
  T.eq(st.dockDir, 1); T.eq(st.num, 3); T.eq(st.dim, "allthemodium:mining")
  T.contains(t:output(), "I'm still")
end)

-- A Canary on an MD-style dock: barrel east, walls on the other three sides (no free side to step into)
local function boxedIn()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:stone")
  local dock = MS.barrel()
  dock:give("minecraft:coal", 16)
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  local t = MS.turtle(w)
  local f = MS.foreman(w)
  MS.setup(w, t)
  w:run(30)
  w:setBlock(0, 64, -1, "minecraft:stone"); w:setBlock(-1, 64, 0, "minecraft:stone"); w:setBlock(0, 64, 1, "minecraft:stone")
  return w, t, f
end

T.test("miner: unloaded mid-turn on a dock with no free side, he finds his heading by his dock barrel", function()
  local w, t, f = boxedIn()
  local st = t:readTable("miner.state")
  st.turning, st.h = true, 2                         -- unloaded mid-turn: his heading is unknown
  t:writeTable("miner.state", st)
  t.body.facing = 2                                   -- facing south, not north as he thinks
  t:reboot(); w:run(15)
  T.running(t)
  local s = t:readTable("miner.state")
  T.falsy(s.lost, "not lost")
  T.eq(s.h, 0); T.eq(t.body.facing, 0, "faces the way he faced at setup")
  T.absent(f.env._G.lastStatus.msg, "Can't tell")
  MS.order(f)
  T.waitFor(w, MS.finished(f), 1200, "never mined after finding himself")
end)

T.test("miner: a re-dock from his Foreman sets his dock up where he stands, keeping his number", function()
  local w, t, f = boxedIn()
  -- carried to a new dock 3 blocks east (same chunk, same height: he thinks he's been moved by hand)
  w:setBlock(4, 64, -1, "minecraft:barrel", MS.barrel())
  t.body.x, t.body.y, t.body.z = 3, 64, -1
  t:reboot(); w:run(10)
  T.contains(f.env._G.lastStatus.msg, "Moved by hand")
  f.env._G.redock = 1
  f.env._G.order = { want = "dock", seq = 9 }
  w:run(15)
  local s = t:readTable("miner.state")
  T.eq(s.home.x, 3); T.eq(s.home.z, -1); T.eq(s.dockDir, 1); T.eq(s.num, 1)
  T.contains(t:output(), "Re-docked here")
  T.eq(f.env._G.lastStatus.redockDone, 1)
end)

T.test("miner: lost with no GPS he still takes a reboot or a re-dock from his Foreman", function()
  local w, t, f = boxedIn()
  w.gpsOn = false
  local st = t:readTable("miner.state")
  st.turning = true
  st.x, st.z = 5, 5                                   -- lost out in his area, no GPS to find himself
  t:writeTable("miner.state", st)
  t:reboot(); w:run(10)
  T.contains(f.env._G.lastStatus.msg, "Lost")
  f.env._G.redock = 2
  f.env._G.order = { want = "dock", seq = 7 }
  w:run(10)
  T.contains(t:output(), "an order from my Foreman came in")
  T.eq(f.env._G.lastStatus.redockDone, 2, "the re-dock got through")
  T.running(t)
end)
