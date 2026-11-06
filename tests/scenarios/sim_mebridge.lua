-- Checks the ME Bridge mock (tests/sim/me.lua): AE2's insert/extract order, cell bytes and types, storage
-- buses, export/import with real inventories, AP's getDrives quirk and offline behaviour.
local cc = require("sim.cc")
local T = require("sim.test")

local COBBLE, IRON, DEEP = "minecraft:cobblestone", "minecraft:iron_ingot", "minecraft:deepslate"

local function setup()
  local w = cc.world()
  local net = w:net()
  local me = net:add("me_bridge_0", w:meBridge{})
  local function chest(name, size, limit)
    return net:add(name, cc.Inv.new{ size = size or 27, slotLimit = limit, types = { "minecraft:barrel", "inventory" } })
  end
  return w, net, me, chest
end

-- run `n` of `name` through the grid's insert path (a chest on the cable and importItem)
local function put(me, chest, name, n)
  chest:clear()
  chest:give(name, n)
  return me:importItem(chest.netName, { name = name })
end

T.test("mebridge: cell bytes and types follow AE2", function()
  local _, _, me = setup()
  local d = me:addDrive{}
  local c = me:addCell(d, "1k")
  T.eq(c.bytesPerType, 8, "1k bytesPerType")
  T.eq(me:addCell(d, "4k").bytesPerType, 32)
  T.eq(me:addCell(d, "16k").bytesPerType, 128)
  T.eq(me:addCell(d, "64k").bytesPerType, 512)
  T.eq(me:addCell(d, "256k").bytesPerType, 2048)
  T.eq(me:addCell(d, "256M").maxBytes, 268435456)
  T.eq(c.maxTypes, 63)
  T.eq(c:usedBytes(), 0)
  me:fill(c, COBBLE, 100)
  T.eq(c:usedBytes(), 8 + 13, "one type: 8 + ceil(100/8)")
  me:fill(c, IRON, 200)
  T.eq(c:usedBytes(), 2 * 8 + 38, "two types: 16 + ceil(300/8)")   -- the whole cell's total rounds up, not each type
  local info = me:getCells()[1]
  T.eq(info.usedBytes, 54)
  T.eq(info.maxBytes, 1024)
  T.eq(info.type, "ae2:i")
  T.eq(info.item.name, "ae2:item_storage_cell_1k")
  T.eq(me:getUsedItemStorage(), 54)
  T.eq(me:getMaxItemStorage(), 1024 + 4096 + 16384 + 65536 + 262144 + 268435456)
  T.eq(me:getAvailableItemStorage(), me:getMaxItemStorage() - 54)
end)

T.test("mebridge: insert goes to the highest priority, then cells that already hold the item", function()
  local _, _, me, chest = setup()
  local lo = me:addRack{ n = 1, priority = 0, cell = "1k" }[1]
  local hi = me:addDrive{ priority = 10 }
  local a, b = me:addCell(hi, "1k"), me:addCell(hi, "1k")
  local inp = chest("minecraft:barrel_0", 27)
  -- nothing holds iron: the highest priority wins, first built cell first
  T.eq(put(me, inp, IRON, 50), 50)
  T.eq(a:count(IRON), 50)
  T.eq(lo.cells[1]:count(IRON), 0)
  -- b already holds cobblestone, so it beats a (same priority, built earlier)
  me:fill(b, COBBLE, 5)
  T.eq(put(me, inp, COBBLE, 20), 20)
  T.eq(b:count(COBBLE), 25)
  T.eq(a:count(COBBLE), 0)
  -- a low-priority cell that holds the item does NOT beat a higher priority cell
  me:fill(lo.cells[1], DEEP, 7)
  T.eq(put(me, inp, DEEP, 9), 9)
  T.eq(lo.cells[1]:count(DEEP), 7)
  T.eq(a:count(DEEP), 9)
end)

T.test("mebridge: an insert that doesn't fit spills to the next cell, then the next priority", function()
  local _, _, me, chest = setup()
  local hi = me:addDrive{ priority = 5 }
  local small = me:addCell(hi, "1k")            -- room for (1024 - 8) * 8 = 8128 of one type
  local lo = me:addDrive{ priority = 0 }
  local big = me:addCell(lo, "4k")
  local inp = chest("minecraft:barrel_0", 1, 1000000)
  T.eq(put(me, inp, COBBLE, 10000), 10000)
  T.eq(small:count(COBBLE), 8128)
  T.eq(big:count(COBBLE), 10000 - 8128)
  T.eq(small:usedBytes(), 1024, "cell is full")
end)

T.test("mebridge: extract takes from the lowest priority first", function()
  local _, _, me, chest = setup()
  local hiD, loD = me:addDrive{ priority = 10 }, me:addDrive{ priority = 0 }
  local hi, lo = me:addCell(hiD, "64k"), me:addCell(loD, "64k")
  me:fill(hi, COBBLE, 300)
  me:fill(lo, COBBLE, 100)
  local out = chest("minecraft:barrel_0", 27)
  T.eq(me:exportItem(out.netName, { name = COBBLE, count = 150 }), 150, "moved in one call")
  T.eq(lo:count(COBBLE), 0, "low priority emptied first")
  T.eq(hi:count(COBBLE), 250)
  T.eq(out:count(COBBLE), 150)
end)

T.test("mebridge: a cell at its type limit or out of bytes refuses a new type", function()
  local _, _, me, chest = setup()
  local d = me:addDrive{}
  local c = me:addCell(d, "1k")
  for i = 1, 63 do T.eq(me:fill(c, "mod:item_" .. i, 1), 1) end
  T.eq(c:types(), 63)
  T.eq(me:fill(c, "mod:item_64", 1), 0, "64th type refused")
  T.eq(me:fill(c, "mod:item_1", 5), 5, "more of a held type is fine")
  -- bytes: a cell holding one type full of items takes no new type
  local d2 = me:addDrive{}
  local full = me:addCell(d2, "1k")
  T.eq(me:fill(full, COBBLE, 100000), 8128)
  T.eq(full:usedBytes(), 1024)
  T.eq(me:fill(full, IRON, 1), 0)
  -- through the bridge: only the one cell with room takes it
  local inp = chest("minecraft:barrel_0", 27)
  T.eq(put(me, inp, "mod:item_64", 4), 0, "no cell in the grid can take a 64th type")
  T.eq(inp:count("mod:item_64"), 4, "refused items stay in the inventory")
  T.eq(me:total("mod:item_64"), 0)
end)

T.test("mebridge: a void storage bus destroys what doesn't fit; a plain one refuses it", function()
  local _, _, me, chest = setup()
  me:addRack{ n = 1, priority = 0, cell = "256k" }
  me:addBus{ priority = 9999, capacity = 256000, void = true }
  local inp = chest("minecraft:barrel_0", 1, 1000000)
  T.eq(put(me, inp, DEEP, 300000), 300000, "all taken: the surplus is voided")
  T.truthy(inp:isEmpty())
  T.eq(me:total(DEEP), 256000, "the drawer keeps 256k")
  T.eq(me:where(DEEP)[1].kind, "bus")
  T.eq(put(me, inp, DEEP, 10), 10, "full drawer still takes (and voids) more")
  T.eq(me:total(DEEP), 256000)
  -- items without a void bus go to the cells; the bus is counted in getItems
  T.eq(put(me, inp, COBBLE, 500), 500)
  local seen = {}
  for _, it in ipairs(me:getItems()) do seen[it.name] = it.count end
  T.eq(seen[DEEP], 256000, "buses count in getItems")
  T.eq(seen[COBBLE], 500)
  T.eq(#me:getCells(), 10, "getCells doesn't list buses")
  -- a bus without void refuses the surplus
  local w2 = cc.world()
  local n2 = w2:net()
  local m2 = n2:add("me_bridge_0", w2:meBridge{})
  local i2 = n2:add("minecraft:barrel_0", cc.Inv.new{ size = 1, slotLimit = 1000 })
  m2:addBus{ priority = 5, capacity = 100 }
  T.eq(put(m2, i2, COBBLE, 250), 100)
  T.eq(i2:count(COBBLE), 150)
end)

T.test("mebridge: export and import move many stacks in one call and report the count", function()
  local w, _, me, chest = setup()
  me:addRack{ n = 1, priority = 0, cell = "64k" }
  local src = chest("minecraft:barrel_0", 27)
  for _ = 1, 27 do src:give(COBBLE, 64) end
  T.eq(me:importItem(src.netName), 27 * 64, "import with no filter takes every stack")
  T.truthy(src:isEmpty())
  T.eq(me:total(COBBLE), 1728)
  local dst = chest("minecraft:barrel_1", 27)
  T.eq(me:exportItem(dst.netName, { name = COBBLE, count = 200 }), 200, "200 over four stacks, one call")
  T.eq(dst:count(COBBLE), 200)
  T.eq(me:total(COBBLE), 1528)
  -- toSlot, and an inventory that fills up part-way
  local one = chest("minecraft:barrel_2", 27)
  T.eq(me:exportItem(one.netName, { name = COBBLE, count = 10, toSlot = 5 }), 10)
  T.eq(one.slots[5].count, 10)
  local tiny = chest("minecraft:barrel_3", 1)
  T.eq(me:exportItem(tiny.netName, { name = COBBLE, count = 500 }), 64, "only one stack fits")
  T.eq(me:total(COBBLE), 1528 - 10 - 64)
  -- import filters: name, fromSlot, count
  local mix = chest("minecraft:barrel_4", 27)
  mix:give(IRON, 30); mix:give(COBBLE, 30)
  T.eq(me:importItem(mix.netName, { name = IRON, count = 12 }), 12)
  T.eq(mix:count(IRON), 18)
  T.eq(me:importItem(mix.netName, { fromSlot = 2 }), 30)
  T.eq(mix:count(COBBLE), 0)
  -- unknown inventory, no such item
  local r, err = me:exportItem("minecraft:barrel_99", { name = COBBLE })
  T.eq(r, nil); T.eq(err, "INVENTORY_NOT_FOUND")
  r, err = me:importItem("minecraft:barrel_99")
  T.eq(r, nil); T.eq(err, "INVENTORY_NOT_FOUND")
  T.eq(me:exportItem(dst.netName, { name = "mod:nothing" }), 0)
  -- getItem / getItems shape
  local it = me:getItem{ name = IRON }
  T.eq(it.count, 12); T.eq(it.displayName, "Iron Ingot"); T.eq(it.isCraftable, false)
  T.eq(type(it.tags), "table"); T.eq(type(it.components), "table")
  T.eq(me:getItem{ name = "mod:nothing" }.count, 0)
  w:run(1)
end)

T.test("mebridge: getDrives reports AP's zero bytes and leaves empty slots out", function()
  local _, _, me = setup()
  local d = me:addDrive{ name = "Rack 1 Drive 1", x = 10, y = 70, z = -4, priority = 3 }
  local c = me:addCell(d, "4k", 3)
  me:fill(c, COBBLE, 64)
  local drives = me:getDrives()
  T.eq(#drives, 1)
  local dr = drives[1]
  T.eq(dr.type, "ae2:drive"); T.eq(dr.name, "Rack 1 Drive 1"); T.eq(dr.priority, 3)
  T.eq(dr.position.x, 10); T.eq(dr.position.y, 70); T.eq(dr.position.z, -4)
  T.eq(dr.usedBytes, 0, "AP bug: a drive's own usedBytes is 0")
  T.eq(dr.totalBytes, 0, "AP bug: a drive's own totalBytes is 0")
  T.eq(dr.cells[1], nil, "empty slots aren't listed")
  T.eq(dr.cells[3].usedBytes, 32 + 8, "but the cell in slot 3 carries its bytes")
  T.eq(dr.cells[3].maxBytes, 4096)
end)

T.test("mebridge: racks, one priority per rack", function()
  local _, _, me = setup()
  local rack = me:addRack{ n = 8, priority = 7, cell = "1k", x = 100 }
  T.eq(#rack, 8)
  T.eq(#me:getCells(), 80)
  for _, d in ipairs(me:getDrives()) do T.eq(d.priority, 7) end
  T.eq(me:getDrives()[8].position.x, 107)
end)

T.test("mebridge: offline, or without a grid connection", function()
  local _, _, me, chest = setup()
  me:addRack{ n = 1, cell = "1k" }
  local inp = chest("minecraft:barrel_0", 27)
  inp:give(IRON, 5)
  T.eq(me:isConnected(), true); T.eq(me:isOnline(), true)
  me:setOnline(false)
  T.eq(me:isConnected(), true); T.eq(me:isOnline(), false)
  for _, call in ipairs{
    function() return me:getItems() end, function() return me:getItem{ name = IRON } end,
    function() return me:getCells() end, function() return me:getDrives() end,
    function() return me:exportItem(inp.netName, { name = IRON }) end,
    function() return me:importItem(inp.netName) end,
    function() return me:getUsedItemStorage() end, function() return me:getMaxItemStorage() end,
    function() return me:getAvailableItemStorage() end, function() return me:getStoredEnergy() end,
  } do
    local r, err = call()
    T.eq(r, nil); T.eq(err, "NOT_CONNECTED")
  end
  T.eq(inp:count(IRON), 5, "nothing moved while offline")
  me:setOnline(true); me:setConnected(false)
  T.eq(me:isConnected(), false)
  local r, err = me:getItems()
  T.eq(r, nil); T.eq(err, "NOT_CONNECTED")
  me:setConnected(true)
  T.eq(me:importItem(inp.netName), 5, "back on")
  T.truthy(me:getStoredEnergy() > 0); T.truthy(me:getEnergyCapacity() > 0); T.truthy(me:getEnergyUsage() > 0)
end)

T.test("mebridge: a program on the cable sees it as me_bridge, and every call costs a tick", function()
  local w, net, me, chest = setup()
  w.ticks = true
  me:addRack{ n = 1, cell = "64k" }
  local inp = chest("minecraft:barrel_0", 27)
  inp:give(IRON, 64)
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:writeFile("t.lua", [[
    local b = peripheral.find("me_bridge")
    _G.type_ = peripheral.getType(peripheral.getName(b))
    local t0 = os.clock()
    _G.moved = b.importItem("minecraft:barrel_0", { name = "minecraft:iron_ingot" })
    b.isConnected(); b.isOnline()
    _G.spent = os.clock() - t0
    _G.items = b.getItems()
    _G.drives = b.getDrives()
  ]])
  c:run("t")
  T.waitFor(w, function() return c.finished end, 5, "program never finished")
  T.eq(c.env.moved, 64)
  T.eq(c.env.type_, "me_bridge")
  T.truthy(c.env.spent >= 0.15 - 1e-6, "three calls take at least three ticks, got " .. tostring(c.env.spent))
  T.eq(c.env.items[1].name, IRON)
  T.eq(#c.env.drives, 1)
end)
