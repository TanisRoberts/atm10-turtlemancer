-- Storage: turtle docks (#41). Lava buckets first, coal only without lava, best fuel in slot 1, empties taken back,
-- and the dock_report handshake. See docs/systems/turtle.md.
local cc = require("sim.cc")
local T = require("sim.test")

local BARREL = { "minecraft:barrel", "inventory" }
local DOCK = "minecraft:barrel_3"

-- Storage with an input (0), output (1), a store (2) and one dock barrel (3). The dock is also a block in the world
-- at 0,64,-1, so a turtle at 0,64,0 facing north can reach it.
local function base(opts)
  opts = opts or {}
  local w = cc.world()
  w.gpsOn = true
  local net = w:net()
  local inv = {}
  for i = 0, 2 do inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = BARREL }) end
  inv[3] = net:add(DOCK, cc.Inv.new{ size = 27, types = BARREL })
  w:setBlock(0, 64, -1, "minecraft:barrel", inv[3])
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:monitor("right", 57, 24)
  c:installRole("storage")
  local cfg = { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1", docks = { DOCK } }
  for k, v in pairs(opts.cfg or {}) do cfg[k] = v end
  c:writeTable("storage.cfg", cfg)
  return w, c, inv
end

local function lavaIn(inv) return inv:count("minecraft:lava_bucket") end

T.test("storage docks: stocked with lava buckets up to DOCK_LAVA, and no coal while there is lava", function()
  local w, c, inv = base()
  inv[2]:give("minecraft:lava_bucket", 10)
  inv[2]:give("minecraft:coal", 64)
  c:run("storage")
  T.waitFor(w, function() return lavaIn(inv[3]) == 4 end, 60, "dock never got its 4 lava buckets")
  w:run(10)
  T.eq(lavaIn(inv[3]), 4, "stops at the tunable")
  T.eq(inv[3]:count("minecraft:coal"), 0, "no coal when there is lava")
  T.eq(lavaIn(inv[2]), 6)
end)

T.test("storage docks: coal and charcoal only when storage has no lava", function()
  local w, c, inv = base()
  inv[2]:give("minecraft:charcoal", 20)
  inv[2]:give("minecraft:coal", 64)
  c:run("storage")
  T.waitFor(w, function() return inv[3]:count("minecraft:charcoal") + inv[3]:count("minecraft:coal") == 32 end, 60,
    "dock never got about 32 coal worth")
  T.eq(inv[3]:count("minecraft:charcoal"), 20, "charcoal first")
  T.eq(inv[3]:count("minecraft:coal"), 12)
  T.eq(lavaIn(inv[3]), 0)
end)

T.test("storage docks: empty buckets are taken back, lava stays, and the best fuel sits in slot 1", function()
  local w, c, inv = base()
  inv[3]:give("minecraft:coal", 10, 1)            -- coal in slot 1 ...
  inv[3]:give("minecraft:bucket", 2, 5)           -- ... and two empties from a turtle
  inv[2]:give("minecraft:lava_bucket", 10)
  c:run("storage")
  T.waitFor(w, function() return inv[3]:count("minecraft:bucket") == 0 and lavaIn(inv[3]) == 4 end, 60,
    "empties still in the dock, or no lava")
  T.waitFor(w, function() local l = inv[3]:list(); return l[1] and l[1].name == "minecraft:lava_bucket" end, 30,
    "lava never moved to slot 1")
  local bucketsHome = 0
  for i = 0, 2 do bucketsHome = bucketsHome + inv[i]:count("minecraft:bucket") end
  T.eq(bucketsHome, 2, "both empty buckets are in storage")
  T.eq(inv[3]:count("minecraft:coal"), 10, "the coal is still in the dock, just not first")
end)

T.test("storage docks: a turtle drinks a bucket, the empty goes back, and the dock is refilled", function()
  local w, c, inv = base()
  inv[2]:give("minecraft:lava_bucket", 10)
  local t = w:turtle{ id = 5, x = 0, y = 64, z = 0, facing = 0, fuel = 100, right = "computercraft:wireless_modem_advanced" }
  t:installRole("woodpecker")
  t:writeFile("probe.lua", 'local core = dofile("turtlecore.lua")\ncore.fuel.refuelFromDock("front", 1000)')
  c:run("storage")
  T.waitFor(w, function() return lavaIn(inv[3]) == 4 end, 60, "dock never stocked")
  t:run("probe"); w:run(5)
  T.eq(t.body.fuel, 1100, "he drank one bucket")
  T.waitFor(w, function() return lavaIn(inv[3]) == 4 and inv[3]:count("minecraft:bucket") == 0 end, 60,
    "dock not refilled / empty bucket not taken back")
  local empties = 0
  for i = 0, 2 do empties = empties + inv[i]:count("minecraft:bucket") end
  T.eq(empties, 1, "the empty bucket is in storage")
end)

-- A stand-in turtle: sends dock reports and keeps the acks
local function turtleSending(w, id, label, role, x, y, z)
  local t = w:computer{ id = id, label = label }
  t:attach("top", cc.wireless{ ender = true })
  t:writeFile("send.lua", ([[
    rednet.open("top")
    acks = {}
    rednet.broadcast({ type = "dock_report", id = os.getComputerID(), label = %q, role = %q, x = %d, y = %d, z = %d, dir = "north" }, "tanis-base")
    local deadline = os.clock() + 3
    while os.clock() < deadline do
      local _, reply = rednet.receive("tanis-base", 1)
      if type(reply) == "table" and reply.type == "dock_ack" and reply.id == os.getComputerID() then acks[#acks + 1] = reply end
    end
  ]]):format(label, role, x, y, z))
  return t
end

T.test("storage docks: dock_report is acked as unassigned, then assigned once /assign linked the barrel", function()
  local w, c, inv = base()
  c:run("storage"); w:run(5)
  local t = turtleSending(w, 5, "Woodpecker-01", "lumberjack", 0, 64, -1)
  t:run("send"); w:run(5)
  local acks = t.env._G.acks
  T.eq(#acks, 1, "an ack came back")
  T.eq(acks[1].assigned, nil, "nothing linked yet: unassigned dock")
  -- Link the barrel to that turtle (what /assign does), then reboot Storage to read it
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1", docks = { DOCK },
    dockLink = { [DOCK] = { label = "Woodpecker-01", x = 0, y = 64, z = -1 } } })
  c:reboot(); c:run("storage"); w:run(10)
  local t2 = turtleSending(w, 6, "Woodpecker-01", "lumberjack", 0, 64, -1)
  t2:run("send"); w:run(5)
  T.eq(t2.env._G.acks[1].assigned, DOCK, "the linked barrel is named")
  -- Same turtle, dock moved: the link no longer matches
  local t3 = turtleSending(w, 7, "Woodpecker-01", "lumberjack", 5, 64, 5)
  t3:run("send"); w:run(5)
  T.eq(t3.env._G.acks[1].assigned, nil, "a moved dock is not assigned")
end)

T.test("storage docks: a miner's dock report is answered but never listed (its Foreman owns that dock)", function()
  local w, c = base()
  c:run("storage"); w:run(5)
  local t = turtleSending(w, 5, "Canary-01", "miner", 10, 253, 10)
  t:run("send"); w:run(5)
  T.eq(#t.env._G.acks, 1)
  T.eq(t.env._G.acks[1].assigned, nil)
  local saved = c:readTable("storage.cfg")
  T.eq(saved.dockReports and saved.dockReports["Canary-01"], nil, "not remembered")
end)
