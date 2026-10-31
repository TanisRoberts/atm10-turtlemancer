-- Miner: first-run setup at the dock, a number from the Foreman, then one order to mine.
-- Every miner has one dock barrel. Canary (Mining Dimension); Starling (the End) fuels himself from it.
-- A tiny stand-in Foreman answers on the radio (tests/sim/miners.lua); the real ones have their own scenarios.
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

-- Dock at 0,64,0 facing north, stone below (Y 40..63), one dock barrel east with coal in it.
local function base()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:stone")
  local dock = MS.barrel()
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  dock:give("minecraft:coal", 64)
  local t = MS.turtle(w)
  return w, t, dock
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

T.test("miner: a Starling in the End has one dock barrel too, and an old two-barrel save sets up again", function()
  local w, t = base()
  MS.setup(w, t, "4")
  w:run(20)
  T.running(t)
  T.contains(t:output(), "Dock barrel: on my right")
  T.contains(t:output(), "I'm a Starling (the_end)")
  local st = t:readTable("miner.state")
  T.eq(st.dockDir, 1)
  -- a save from the old DUMP + FUEL dock: no dock barrel, so setup again at boot
  st.dockDir, st.dumpDir, st.fuelDir, st.num = nil, 1, 3, 5
  t:writeTable("miner.state", st)
  t:reboot(); w:run(2)
  T.contains(t:output(), "I don't know my dock barrel")
  t:type("4"); t:key(257)
  w:run(20)
  T.eq(t:readTable("miner.state").dockDir, 1)
  T.eq(t:readTable("miner.state").num, 5)
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
local function mineWorld(dim)
  local w, t, dock = base()
  local f = MS.foreman(w, { kind = dim == "4" and "starling" or "canary" })
  w:setBlock(3, 62, 3, "minecraft:iron_ore")
  w:setBlock(5, 61, 7, "minecraft:diamond_ore")
  w:setBlock(9, 62, 12, "minecraft:coal_ore")
  MS.setup(w, t, dim)
  w:run(10)
  return w, t, dock, nil, f
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

T.test("miner: a Starling mines and fuels himself from his one dock barrel (no Foreman serves the End)", function()
  local w, t, dock, _, f = mineWorld("4")
  MS.order(f)
  T.waitFor(w, MS.finished(f), 1200, "never finished the range")
  T.running(t)
  T.eq(dock:count("minecraft:diamond"), 1)
  T.eq(dock:count("minecraft:raw_iron"), 1)
  T.truthy(w:getBlock(1, 64, 0), "dock barrel still standing")
  T.truthy(t.body.fuel > 400, "took fuel from his dock")
  T.eq(f.G.requests, 0, "never asked a Foreman for fuel")
end)

T.test("miner: a reboot in the middle of a run resumes where it was", function()
  local w, t, dock, _, f = mineWorld()
  MS.order(f)
  w:run(150)
  T.eq(f.G.lastStatus.state, "mining")
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
  local s = f.G.lastStatus
  T.eq(s.chunky, true)
  T.truthy((s.swaps or 0) >= 2, "swapped at the start and during the run")
  T.eq(s.chunkyNote, nil)
  T.eq(t.body.up.right, "computercraft:wireless_modem_advanced")
  local n = 0
  for _, sl in pairs(t.body.slots) do if sl.name == "advancedperipherals:chunk_controller" then n = n + sl.count end end
  T.eq(n, 1, "controller still in the bag")
end)

T.test("miner: an order with no range, or one above his dock, says why instead of 'Range finished'", function()
  local w, t = base()
  local f = MS.foreman(w)
  MS.setup(w, t)
  w:run(10)
  f.G.order = { want = "run", seq = 5 }                    -- no minY / maxY
  w:run(10)
  T.contains(f.G.lastStatus.msg, "No range from the MD Foreman")
  T.eq(t.body.y, 64)
  MS.order(f, { minY = 70, maxY = 80, seq = 6 })
  w:run(10)
  T.contains(f.G.lastStatus.msg, "Range Y 70..80 isn't below my dock (Y 64)")
  T.absent(f.G.lastStatus.msg, "Range finished")
  MS.order(f, { seq = 7 })                                       -- a good one: he goes
  T.waitFor(w, MS.finished(f), 1200, "never mined the good range")
end)

T.test("miner: netherrack and end stone are dumped underground, never brought home (an old junk.txt gets them too)", function()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:netherrack")
  w:fill(0, 60, 0, 15, 61, 15, "minecraft:end_stone")
  w:setBlock(5, 61, 7, "minecraft:diamond_ore")
  local dock = MS.barrel()
  dock:give("minecraft:coal", 64)
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  local t = MS.turtle(w)
  t:writeFile("junk.txt", "cobblestone\nnetherrack\n")          -- made before the dump lines existed
  local f = MS.foreman(w)
  MS.setup(w, t)
  w:run(10)
  T.contains(t:readFile("junk.txt"), "dump end_stone")
  MS.order(f)
  T.waitFor(w, MS.finished(f), 1500, "never finished the range")
  T.eq(dock:count("minecraft:diamond"), 1)
  T.eq(dock:count("minecraft:netherrack"), 0, "no netherrack came home")
  T.eq(dock:count("minecraft:end_stone"), 0, "no end stone came home")
end)

T.test("miner: losing his ender modem mid-run he stops mining and goes home, instead of mining on deaf", function()
  local w, t, dock, _, f = mineWorld()
  MS.order(f, { minY = 50, maxY = 63 })
  w:run(120)
  T.eq(f.G.lastStatus.state, "mining")
  t.body:equip("right", nil)                                -- the modem is gone (a chunk controller in its place, say)
  T.waitFor(w, function() return t.body.x == 0 and t.body.y == 64 and t.body.z == 0 end, 600, "never came home")
  w:run(20)
  T.eq(t.body.y, 64, "stays home")
  T.contains(t:output(), "No ender modem")
  t.body:equip("right", "computercraft:wireless_modem_advanced")   -- put back: he hears his Foreman again
  T.waitFor(w, function() return f.G.lastStatus.state == "mining" end, 60, "never went back to mining")
end)

T.test("miner: many chunk swaps while the radio is busy never lose his modem or controller, nor crash", function()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-24, 58, -24, 39, 63, 39, "minecraft:stone")
  local dock = MS.barrel()
  dock:give("minecraft:coal", 64)
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  local t = MS.turtle(w, { fuel = 5000, items = { [16] = { "advancedperipherals:chunk_controller", 1 } } })
  local f = MS.foreman(w)
  -- chatter on his protocol 20 times a second: his radio loop wakes all the time, also mid-swap
  local chat = w:computer{ id = 60, label = "Chatter" }
  chat:attach("top", cc.wireless{ ender = true })
  chat:writeFile("chat.lua", 'rednet.open("top") while true do rednet.broadcast({ type = "noise" }, "tanis-miner") os.sleep(0.05) end')
  chat:run("chat")
  MS.setup(w, t)
  w:run(10)
  MS.order(f, { minY = 61, maxY = 63, c2 = 1 })                 -- 3x3 chunks: a swap in every one
  T.waitFor(w, MS.finished(f), 4000, "never finished the 9 chunks")
  T.running(t)
  T.eq(t.body.up.right, "computercraft:wireless_modem_advanced", "modem still fitted")
  local n = 0
  for _, sl in pairs(t.body.slots) do if sl.name == "advancedperipherals:chunk_controller" then n = n + sl.count end end
  T.eq(n, 1, "controller still in his bag")
  T.eq(dock:count("advancedperipherals:chunk_controller") + dock:count("computercraft:wireless_modem_advanced"), 0, "no gear in the dock")
  T.truthy((f.G.lastStatus.swaps or 0) >= 9, "swapped in every chunk")
end)

T.test("miner: a chunk swap landing while the radio loop waits in receive never crashes him (issue 96)", function()
  -- a slow swap (each equip a few ticks, like the game): the radio loop's 0.2 s nap ends with the modem still off
  local cost = require("sim.turtle").cost
  local old = { cost.equipLeft, cost.equipRight }
  cost.equipLeft, cost.equipRight = 0.2, 0.2
  -- the radio loop wakes on a 1 s timer; start the run at twelve offsets so a swap lands inside it somewhere
  local hits = 0
  for i = 0, 11 do
    local w = cc.world()
    w.gpsOn = true
    w:fill(-24, 58, -24, 39, 63, 39, "minecraft:stone")
    local dock = MS.barrel()
    dock:give("minecraft:coal", 64)
    w:setBlock(1, 64, 0, "minecraft:barrel", dock)
    local t = MS.turtle(w, { fuel = 5000, items = { [16] = { "advancedperipherals:chunk_controller", 1 } } })
    local f = MS.foreman(w)
    MS.setup(w, t)
    w:run(10 + i * 0.09)
    MS.order(f, { minY = 61, maxY = 63, c2 = 1 })
    w:run(400)
    T.running(t)
    T.eq(t:output():find("No such method", 1, true), nil, "offset " .. i .. ": " .. t:output())
    T.truthy(f.G.lastStatus ~= nil, "still reporting")
    hits = hits + (w.staleHits or 0)
  end
  cost.equipLeft, cost.equipRight = old[1], old[2]
end)
