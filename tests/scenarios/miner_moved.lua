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
