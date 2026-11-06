-- Storage in ME mode (#124): an ME Bridge on the cable makes AE2 the storage; every job goes through it.
local cc = require("sim.cc")
local T = require("sim.test")

local BARREL = { "minecraft:barrel", "inventory" }
local B = function(i) return "minecraft:barrel_" .. i end

-- barrels: 0 input, 1 output, 2 dock, 3 depot, 4 Canary fuel, 5 smelter feed (furnace-side barrel), 6 unassigned.
-- Plus an `ae2:drive`-like inventory on the cable that must never be touched.
local function base(opts)
  opts = opts or {}
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 6 do inv[i] = net:add(B(i), cc.Inv.new{ size = 27, types = BARREL }) end
  inv.drive = net:add("ae2:drive_0", cc.Inv.new{ size = 10, types = { "ae2:drive", "inventory" } })
  inv.drive:give("minecraft:cobblestone", 5)
  local me
  if not opts.noBridge then
    me = net:add("me_bridge_0", w:meBridge{})
    me:addRack{ n = 1, priority = 0, cell = "64k" }
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("storage")
  local cfg = { inputs = { B(0) }, output = B(1), docks = { B(2) }, depots = { [B(3)] = "minecraft:bucket" },
                fuels = { B(4) } }
  for k, v in pairs(opts.cfg or {}) do cfg[k] = v end
  c:writeTable("storage.cfg", cfg)
  return w, c, inv, me, mon
end

T.test("storage ME: an input chest empties into AE2 and the list comes from the bridge", function()
  local w, c, inv, me, mon = base()
  inv[0]:give("minecraft:iron_ingot", 64)
  inv[0]:give("minecraft:cobblestone", 100)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60, "input never emptied")
  w:run(10)
  T.eq(me:total("minecraft:iron_ingot"), 64)
  T.eq(me:total("minecraft:cobblestone"), 100)
  T.contains(mon, "Iron Ingot")
  T.contains(mon, "bytes")
  T.absent(mon, "slots")
end)

T.test("storage ME: tapping an item sends it to the output from AE2", function()
  local w, c, inv, me, mon = base()
  me:fill(me:cells()[1], "minecraft:iron_ingot", 200)
  c:run("storage"); w:run(10)
  T.contains(mon, "Iron Ingot")
  mon:touch(mon:find("Stack"), 24); w:run(1)
  mon:touch(3, select(2, mon:find("Iron Ingot")))
  T.waitFor(w, function() return inv[1]:count("minecraft:iron_ingot") == 64 end, 30, "iron never reached the output")
  w:run(5)
  T.eq(me:total("minecraft:iron_ingot"), 136, "AE2 lost exactly what was sent")
end)

T.test("storage ME: a dock, a depot and a Canary fuel barrel are filled from AE2", function()
  local w, c, inv, me = base()
  local cell = me:cells()[1]
  me:fill(cell, "minecraft:lava_bucket", 10)
  me:fill(cell, "minecraft:bucket", 40)
  me:fill(cell, "minecraft:coal_block", 20)
  c:run("storage")
  T.waitFor(w, function() return inv[2]:count("minecraft:lava_bucket") == 4 end, 90, "dock never got its lava")
  T.waitFor(w, function() return inv[3]:count("minecraft:bucket") == 40 end, 90, "depot never filled")
  T.waitFor(w, function() return inv[4]:count("minecraft:coal_block") > 0 end, 90, "fuel barrel never filled")
  w:run(10)
  T.eq(me:total("minecraft:lava_bucket"), 6)
  T.eq(me:total("minecraft:bucket"), 0)
end)

T.test("storage ME: smelter ops fill a furnace feed from AE2 and store its contents back", function()
  local w, c, inv, me = base({ cfg = { smelterFeeds = { [B(5)] = true } } })
  me:fill(me:cells()[1], "minecraft:raw_iron", 64)
  inv[5]:give("minecraft:iron_ingot", 3, 2)
  c:run("storage"); w:run(5)
  local sm = w:computer{ id = 7, label = "Smelter" }
  sm:attach("top", cc.wireless{ ender = true })
  sm:writeFile("send.lua", ([[
    rednet.open("top")
    rednet.send(1, { type = "smelt_ops", id = 1, ops = {
      { op = "fill", fz = %q, slot = 1, item = "minecraft:raw_iron", count = 20 },
      { op = "store", fz = %q, slot = 2 },
    } }, "tanis-base")
    local _, r = rednet.receive("tanis-base", 10)
    reply = r
  ]]):format(B(5), B(5)))
  sm:run("send"); w:run(10)
  T.eq(inv[5]:count("minecraft:raw_iron"), 20, "furnace feed filled from AE2")
  T.eq(inv[5]:count("minecraft:iron_ingot"), 0, "slot 2 stored")
  T.eq(me:total("minecraft:iron_ingot"), 3, "into AE2")
  T.eq(me:total("minecraft:raw_iron"), 44)
  T.eq(sm.G.reply and sm.G.reply.type, "smelt_done")
end)

T.test("storage ME: unassigned inventories and ae2:drive inventories on the cable are never touched", function()
  local w, c, inv, me = base()
  inv[6]:give("minecraft:diamond", 8)             -- an unassigned barrel
  me:fill(me:cells()[1], "minecraft:iron_ingot", 10)
  c:run("storage"); w:run(40)
  T.eq(inv[6]:count("minecraft:diamond"), 8, "unassigned barrel kept its items")
  T.eq(me:total("minecraft:diamond"), 0, "not sorted into AE2 either")
  T.eq(inv.drive:count("minecraft:cobblestone"), 5, "ae2:drive untouched")
  T.eq(me:total("minecraft:cobblestone"), 0, "and not counted")
end)

T.test("storage ME: bridge offline shows ME offline, keeps the last list, input waits, and recovers", function()
  local w, c, inv, me, mon = base()
  me:fill(me:cells()[1], "minecraft:iron_ingot", 10)
  c:run("storage"); w:run(10)
  T.contains(mon, "Iron Ingot")
  me:setOnline(false)
  inv[0]:give("minecraft:gold_ingot", 5)
  w:run(40)
  T.running(c)
  T.contains(mon, "ME offline")
  T.contains(mon, "Iron Ingot")
  T.eq(inv[0]:count("minecraft:gold_ingot"), 5, "input waits while the grid is down")
  me:setOnline(true)
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60, "input never emptied after the grid came back")
  w:run(35)
  T.absent(mon, "ME offline")
  T.eq(me:total("minecraft:gold_ingot"), 5)
end)

T.test("storage ME: the status broadcast is in bytes", function()
  local w, c, inv, me = base()
  me:fill(me:cells()[1], "minecraft:iron_ingot", 800)
  local mf = w:computer{ id = 9, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  mf:writeFile("listen.lua", [[
    rednet.open("top")
    local deadline = os.clock() + 20
    while os.clock() < deadline do
      local _, m = rednet.receive("tanis-base", 2)
      if type(m) == "table" and m.type == "storage" then st = m; break end
    end
  ]])
  c:run("storage")
  mf:run("listen"); w:run(25)
  local st = mf.G.st
  assert(st, "no status heard")
  T.eq(st.unit, "bytes")
  T.eq(st.used, me:getUsedItemStorage())
  T.eq(st.total, me:getMaxItemStorage())
  T.eq(st.types, nil, "no used-types per cell from the bridge")
end)

T.test("storage ME: without a bridge it is the old storage (unit nil, barrels sorted)", function()
  local w, c, inv = base({ noBridge = true })
  inv[0]:give("minecraft:iron_ingot", 10)
  inv[6]:give("minecraft:diamond", 3)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  T.eq(inv[5]:count("minecraft:iron_ingot") + inv[6]:count("minecraft:iron_ingot") + inv.drive:count("minecraft:iron_ingot"), 10, "sorted into the unassigned barrels as before")
end)
