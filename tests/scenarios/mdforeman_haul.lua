-- MD Foreman #94: full docks, three full Overflow barrels and an empty Output must drain into the Output,
-- and the screen must show the real Overflow slot counts.
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

local function setup()
  local w = cc.world()
  w.ticks = true
  local net = w:net()
  local b = { docks = {}, over = {} }
  local cfg = { docks = {}, overflows = {}, outputs = { "minecraft:barrel_10" }, stocks = { "minecraft:barrel_11" },
    factoryIns = { "minecraft:barrel_12" }, factoryOuts = { "minecraft:barrel_13" }, imported = true }
  for i = 1, 3 do
    b.docks[i] = net:add("minecraft:barrel_" .. i, MS.barrel()); cfg.docks[i] = "minecraft:barrel_" .. i
    b.over[i] = net:add("minecraft:barrel_" .. (i + 3), MS.barrel()); cfg.overflows[i] = "minecraft:barrel_" .. (i + 3)
  end
  b.out = net:add("minecraft:barrel_10", MS.barrel())
  net:add("minecraft:barrel_11", MS.barrel()); net:add("minecraft:barrel_12", MS.barrel()); net:add("minecraft:barrel_13", MS.barrel())
  for i = 1, 3 do
    for s = 1, 27 do b.docks[i]:give("minecraft:raw_iron", 64); b.over[i]:give("minecraft:cobblestone", 64) end
  end
  local c = w:computer{ id = 3, label = "MD Foreman" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("mdforeman")
  c:writeTable("mdforeman.cfg", cfg)
  c:run("mdforeman")
  w:run(3)
  return { w = w, c = c, mon = mon, b = b }
end

T.test("md foreman: full docks and Overflow with an empty Output drain, and Overflow shows its real slots", function()
  local e = setup()
  e.w:run(30)
  T.running(e.c)
  T.contains(e.mon, "Overflow (81/81 slots)")
  T.eq(e.mon:text():find("(0/0 slots)", 1, true), nil, "no 0/0 Overflow")
end)

T.test("md foreman: 11 full docks with 27 slots each can't hang a pass (the 256-event queue never overflows)", function()
  local w = cc.world()
  w.ticks = true
  local net = w:net()
  local cfg = { docks = {}, overflows = { "minecraft:barrel_20" }, outputs = { "minecraft:barrel_21" }, stocks = { "minecraft:barrel_22" },
    factoryIns = { "minecraft:barrel_23" }, factoryOuts = { "minecraft:barrel_24" }, imported = true }
  local docks = {}
  for i = 1, 11 do
    docks[i] = net:add("minecraft:barrel_" .. i, MS.barrel()); cfg.docks[i] = "minecraft:barrel_" .. i
    for s = 1, 27 do docks[i]:give("minecraft:raw_iron", 64) end
  end
  for i = 20, 24 do net:add("minecraft:barrel_" .. i, MS.barrel()) end
  local c = w:computer{ id = 3, label = "MD Foreman" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("mdforeman")
  c:writeTable("mdforeman.cfg", cfg)
  c:run("mdforeman")
  w:run(60)
  T.eq(c.dropped or 0, 0, "events dropped")
  T.eq(mon:text():find("(0/0 slots)", 1, true), nil, "no 0/0 Overflow")
  T.contains(mon, "Overflow (")
end)

T.test("md foreman: a barrel pass that never finishes shows on the screen", function()
  local w = cc.world()
  local net = w:net()
  local dock = net:add("minecraft:barrel_1", MS.barrel())
  dock.list = function() while true do coroutine.yield("task_complete") end end   -- a call that never answers
  local cfg = { docks = { "minecraft:barrel_1" }, outputs = { "minecraft:barrel_2" }, imported = true,
    overflows = {}, stocks = {}, factoryIns = {}, factoryOuts = {} }
  net:add("minecraft:barrel_2", MS.barrel())
  local c = w:computer{ id = 3, label = "MD Foreman" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("mdforeman")
  c:writeTable("mdforeman.cfg", cfg)
  c:run("mdforeman")
  w:run(100)
  T.contains(mon, "Barrel pass stuck")
end)
