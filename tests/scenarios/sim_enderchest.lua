-- Ender Storage in the sim (sim/ender.lua) and the Weaver site helper (sim/weaver.lua).
local cc = require("sim.cc")
local T  = require("sim.test")
local W  = require("sim.weaver")

local CODE = { "red", "blue", "white" }

local function homeComputer(site, script)
  local net = site.w:net()
  site.net = net
  site:home(0)
  local barrel = net:add("minecraft:barrel_0", cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  local c = site.w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  if script then c:writeFile("s.lua", script); c:run("s") end
  return c, barrel
end

T.test("ender: the turtle drops at the site, storage sees it on the cable and pulls it", function()
  local site = W.site{ code = CODE }
  local c, barrel = homeComputer(site, [[
    local e = peripheral.wrap("enderstorage:ender_chest_0")
    _G.type0 = peripheral.getType("enderstorage:ender_chest_0")
    while true do
      local l = e.list()
      if l[1] then _G.seen = l[1].name; _G.moved = peripheral.wrap("minecraft:barrel_0").pullItems("enderstorage:ender_chest_0", 1) ; break end
      sleep(1)
    end
  ]])
  local t = site.turtle
  t.body.slots[1] = { name = "minecraft:cobblestone", count = 40 }
  t:writeFile("t.lua", "turtle.select(1) _G.ok = turtle.dropDown()")
  t:run("t")
  T.waitFor(site.w, function() return barrel:count("minecraft:cobblestone") == 40 end, 30, "storage never got the items")
  T.eq(c.G.seen, "minecraft:cobblestone")
  T.eq(c.G.type0, "enderstorage:ender_chest")
  T.eq(site.chest:count("minecraft:cobblestone"), 0)
end)

T.test("ender: storage pushes into the chest and the turtle sucks it out at the site", function()
  local site = W.site{ code = CODE }
  local c, barrel = homeComputer(site, [[
    sleep(1)
    _G.pushed = peripheral.wrap("minecraft:barrel_0").pushItems("enderstorage:ender_chest_0", 1)
  ]])
  barrel:give("minecraft:sandstone", 64)
  local t = site.turtle
  t:writeFile("t.lua", [[
    while not turtle.suckDown() do sleep(0.5) end
    _G.got = turtle.getItemCount(1)
  ]])
  t:run("t")
  T.waitFor(site.w, function() return t.G.got == 64 end, 30, "turtle never received the stack")
  T.eq(c.G.pushed, 64)
  T.truthy(barrel:isEmpty())
end)

T.test("ender: a different dye code is a different chest; two ends of one code share everything", function()
  local w = cc.world()
  local es = w:ender()
  es:place(0, 64, 0, CODE)
  es:place(50, 64, 50, "red,blue,white")     -- same chest, another place (the string form)
  es:place(5, 64, 5, { "red", "blue", "black" })
  w:getBlock(0, 64, 0).inv:insert("minecraft:coal", 10)
  T.eq(w:getBlock(50, 64, 50).inv:count("minecraft:coal"), 10)
  T.eq(w:getBlock(5, 64, 5).inv:count("minecraft:coal"), 0)
  local net = w:net()
  local e = es:onNet(net, 3, CODE)
  T.eq(e:count("minecraft:coal"), 10)
  T.truthy(net:get("enderstorage:ender_chest_3"))
  e:extract(1, 4)
  T.eq(w:getBlock(0, 64, 0).inv:count("minecraft:coal"), 6)
  T.falsy(pcall(es.inv, es, { "red", "blue", "plaid" }))
end)

T.test("ender: delivery delay (optional) - items show up at the other end after N seconds", function()
  local site = W.site{ code = CODE, delay = 5 }
  local c, barrel = homeComputer(site)
  local home = site.net:get("enderstorage:ender_chest_0")
  local t = site.turtle
  t.body.slots[1] = { name = "minecraft:cobblestone", count = 10 }
  t:writeFile("t.lua", "turtle.select(1) turtle.dropDown()")
  t:run("t")
  site.w:run(3)
  T.eq(t.body.slots[1], nil, "left the turtle at once")
  T.eq(home:count("minecraft:cobblestone"), 0, "still in flight")
  site.w:run(5)
  T.eq(home:count("minecraft:cobblestone"), 10)
end)

T.test("weaver site: ground, dock, turtle kit; diff reports the first mismatches", function()
  local site = W.site{ y = 70, radius = 5 }
  local w = site.w
  T.eq(w:getBlock(0, 70, 0).name, "enderstorage:ender_chest")
  T.eq(site.body.y, 71)
  T.eq(site.body.up.right, "computercraft:wireless_modem_advanced")
  T.eq(site.body.slots[16].name, "advancedperipherals:chunk_controller")
  T.eq(w:getBlock(3, 70, 3).name, "minecraft:sand")
  w:setBlock(2, 71, 2, { name = "minecraft:sandstone_stairs", state = { facing = "north", half = "top" } })
  w:setBlock(3, 71, 2, "minecraft:stone")
  local ok = W.diff(w, { ["2,71,2"] = { name = "minecraft:sandstone_stairs", state = { facing = "north" } }, ["3,71,2"] = "minecraft:stone" })
  T.truthy(ok)
  local ok2, bad, total = W.diff(w, {
    ["2,71,2"] = { name = "minecraft:sandstone_stairs", state = { facing = "south", half = "top" } },
    ["3,71,2"] = "minecraft:cobblestone",
    ["4,71,2"] = "minecraft:stone",
  }, { max = 2 })
  T.falsy(ok2)
  T.eq(total, 3)
  T.eq(#bad, 2)
  T.contains(bad[1], "(2,71,2) wanted minecraft:sandstone_stairs[facing=south,half=top], found minecraft:sandstone_stairs[facing=north,half=top]")
  -- a box: anything not listed must be air
  local ok3, bad3 = W.diff(w, { ["2,71,2"] = "minecraft:sandstone_stairs" }, { box = { 0, 71, 0, 4, 71, 4 } })
  T.falsy(ok3)
  T.contains(bad3[1], "(3,71,2) should be air")
  T.falsy(pcall(W.expect, w, { ["9,71,9"] = "minecraft:stone" }))
end)
