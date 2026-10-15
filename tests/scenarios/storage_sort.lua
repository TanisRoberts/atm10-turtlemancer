-- Storage: the input chest gets sorted into the storage barrels, and the search screen can send an item out.
local cc = require("sim.cc")
local T = require("sim.test")

-- A storage computer on a cable with: input barrel, output barrel, three storage barrels, a monitor.
local function base()
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 4 do
    local name = "minecraft:barrel_" .. i
    inv[i] = net:add(name, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("storage")
  -- pre-assigned jobs, as /assign would have saved them
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  return w, c, inv, mon
end

T.test("storage: sorts the input barrel into storage", function()
  local w, c, inv, mon = base()
  inv[0]:give("minecraft:iron_ingot", 64)
  inv[0]:give("minecraft:cobblestone", 64)
  inv[0]:give("minecraft:cobblestone", 30)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60, "input barrel never emptied")
  T.running(c)
  local total = {}
  for i = 2, 4 do for n, k in pairs(inv[i]:totals()) do total[n] = (total[n] or 0) + k end end
  T.eq(total["minecraft:iron_ingot"], 64)
  T.eq(total["minecraft:cobblestone"], 94)
  T.eq(inv[1]:isEmpty(), true, "output barrel untouched")
end)

T.test("storage: monitor lists items and a tap on Stack then an item sends it to the output", function()
  local w, c, inv, mon = base()
  inv[0]:give("minecraft:iron_ingot", 64)
  inv[0]:give("minecraft:cobblestone", 94)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(10)
  T.contains(mon, "Iron Ingot"); T.contains(mon, "Cobblestone")
  T.contains(mon, "2 items")
  mon:touch(mon:find("Stack"), 24)             -- the Stack button
  w:run(1)
  mon:touch(3, select(2, mon:find("Iron Ingot")))
  T.waitFor(w, function() return inv[1]:count("minecraft:iron_ingot") == 64 end, 30, "iron never reached the output")
  w:run(10)
  T.absent(mon, "Iron Ingot", "the list updates once the stack is gone")
end)

T.test("storage: typing in the search bar filters and Enter sends the top match", function()
  local w, c, inv = base()
  inv[0]:give("minecraft:iron_ingot", 10)
  inv[0]:give("minecraft:cobblestone", 94)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(10)
  c:type("cobb")
  w:run(1)
  T.absent(c.screen, "Iron Ingot", "list is filtered while typing")
  T.contains(c.screen, "Cobblestone")
  c:key(257)                                    -- Enter
  T.waitFor(w, function() return inv[1]:count("minecraft:cobblestone") > 0 end, 30, "nothing sent")
  T.eq(inv[1]:count("minecraft:iron_ingot"), 0)
end)
