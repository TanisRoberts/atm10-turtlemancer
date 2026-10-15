-- Checks the simulator itself: clock, screens, inventories, rednet, turtles. If one of these fails,
-- fix the mock before blaming a program.
local cc = require("sim.cc")
local T = require("sim.test")

T.test("sim: timers fire on the virtual clock", function()
  local w = cc.world()
  local c = w:computer{ id = 1 }
  c:writeFile("t.lua", [[
    local t0 = os.clock()
    sleep(5)
    _G.slept = os.clock() - t0
    print("done")
  ]])
  c:run("t")
  w:run(4)
  T.truthy(c.alive, "still sleeping at 4s")
  w:run(2)
  T.eq(c.env.slept, 5)
  T.eq(c.finished, true)
  T.eq(c:output(), "done")
end)

T.test("sim: screen text and wrapping", function()
  local w = cc.world()
  local c = w:computer{ id = 1, w = 20, h = 5 }
  c:writeFile("t.lua", [[
    term.setCursorPos(3, 2); term.write("hello")
    term.setCursorPos(1, 4); print("x")
    sleep(1)
  ]])
  c:run("t"); w:run(0.1)
  local x, y = c.screen:find("hello")
  T.eq(x, 3); T.eq(y, 2)
  T.contains(c.screen, "x")
end)

T.test("sim: pushItems moves one stack and merges", function()
  local w = cc.world()
  local net = w:net()
  local a = net:add("minecraft:barrel_0", cc.Inv.new{ size = 3, types = { "minecraft:barrel", "inventory" } })
  local b = net:add("minecraft:barrel_1", cc.Inv.new{ size = 3, types = { "minecraft:barrel", "inventory" } })
  a:give("minecraft:cobblestone", 64, 1); a:give("minecraft:cobblestone", 30, 2)
  b:give("minecraft:cobblestone", 50, 1)
  T.eq(a:pushItems("minecraft:barrel_1", 1, 64), 64)       -- 14 merge into slot 1, 50 fill slot 2
  T.eq(b.slots[1].count, 64); T.eq(b.slots[2].count, 50)
  T.eq(b:pullItems("minecraft:barrel_0", 2, 100), 30)      -- pull from slot 2 of a: 30 -> b
  T.eq(b:count("minecraft:cobblestone"), 64 + 50 + 30)
  local ok, err = pcall(a.pushItems, a, "nope", 1, 1)
  T.falsy(ok); T.contains(err, "does not exist")
end)

T.test("sim: furnace cooks in virtual time", function()
  local w = cc.world()
  local f = w:furnace()
  f:give("minecraft:coal", 1, 2)
  f:give("minecraft:raw_iron", 3, 1)
  w:run(25)
  T.eq(f:count("minecraft:iron_ingot"), 2)
  w:run(10)
  T.eq(f:count("minecraft:iron_ingot"), 3)
end)

T.test("sim: peripherals on a cable, rednet between computers", function()
  local w = cc.world()
  local net = w:net()
  net:add("minecraft:barrel_0", cc.Inv.new{ size = 9 })
  local a, b = w:computer{ id = 1 }, w:computer{ id = 2 }
  a:attach("back", cc.wired(net)); b:attach("back", cc.wired(net))
  b:attach("top", cc.wireless())
  a:writeFile("a.lua", [[
    rednet.open("back")
    print(peripheral.getType("minecraft:barrel_0"))
    sleep(1)                                   -- let b open its modem first
    rednet.send(2, { hi = "there" }, "test")
    local id, msg = rednet.receive("test", 5)
    print(id, msg and msg.back)
  ]])
  b:writeFile("b.lua", [[
    rednet.open("back"); rednet.open("top")
    local id, msg = rednet.receive("test", 5)
    rednet.send(id, { back = msg.hi }, "test")
  ]])
  b:run("b"); a:run("a"); w:run(2)
  T.contains(a:output(), "minecraft:chest")
  T.contains(a:output(), "2 there", "reply made it back")
end)

T.test("sim: turtle moves, digs and picks up", function()
  local w = cc.world()
  w:fill(-2, 63, -2, 2, 63, 2, "minecraft:stone")
  w:setBlock(0, 64, -1, "minecraft:iron_ore")
  local t = w:turtle{ id = 3, x = 0, y = 64, z = 0, facing = 0, fuel = 10, left = "minecraft:diamond_pickaxe" }
  t:writeFile("t.lua", [[
    print(turtle.dig(), turtle.forward(), turtle.getFuelLevel())
    print(turtle.digDown())
    print(turtle.getItemDetail(1).name, turtle.getItemDetail(2).name)
    print(turtle.back(), turtle.turnRight())
  ]])
  t:run("t"); w:run(10)                      -- moves and digs take 0.4s each
  T.eq(t.body.z, 0); T.eq(t.body.fuel, 8)
  T.eq(w:getBlock(0, 63, -1), nil)
  T.eq(t.body.slots[1].name, "minecraft:raw_iron")
end)
