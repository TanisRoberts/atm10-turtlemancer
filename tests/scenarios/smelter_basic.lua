-- Smelter + Storage on one cable: raw iron in storage gets smelted when the rules say "iron all".
-- The smelter decides, Storage moves the items (it is the only computer that touches storage).
local cc = require("sim.cc")
local T = require("sim.test")

local function base(rules)
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 3 do
    inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local furnaces = {}
  for i = 0, 2 do furnaces[i] = net:add("minecraft:furnace_" .. i, w:furnace()) end

  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net))
  st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })

  local sm = w:computer{ id = 2, label = "Smelter" }
  sm:attach("back", cc.wired(net))
  sm:installRole("smelter")
  sm:writeFile("smelt.txt", rules)
  local mon = sm:monitor("top", 57, 24)
  return w, st, sm, inv, furnaces, mon
end

T.test("smelter: raw iron in storage is smelted in the furnaces", function()
  local w, st, sm, inv, furnaces, mon = base("iron all\n")
  inv[2]:give("minecraft:raw_iron", 48)
  inv[2]:give("minecraft:coal", 32)
  st:run("storage"); sm:run("smelter")
  local function stored(name)
    local n = 0
    for i = 2, 3 do n = n + inv[i]:count(name) end
    return n
  end
  T.waitFor(w, function() return stored("minecraft:iron_ingot") == 48 end, 600, "not all the iron got smelted and stored")
  T.running(st); T.running(sm)
  T.eq(stored("minecraft:raw_iron"), 0, "no raw iron left in storage")
  for i = 0, 2 do T.eq(furnaces[i]:count("minecraft:raw_iron"), 0, "furnace " .. i .. " is empty of ore") end
  T.contains(mon, "SMELTER")
  T.contains(mon, "3 furnaces")
end)

T.test("smelter: with no matching rule nothing is smelted", function()
  local w, st, sm, inv, furnaces = base("stone 20\n")
  inv[2]:give("minecraft:raw_iron", 16)
  inv[2]:give("minecraft:coal", 8)
  st:run("storage"); sm:run("smelter")
  w:run(60)
  T.running(sm)
  T.eq(inv[2]:count("minecraft:raw_iron"), 16)
  T.eq(inv[2]:count("minecraft:iron_ingot"), 0)
end)

T.test("smelter: says so on screen when storage is not on the network", function()
  local w, st, sm, inv, furnaces, mon = base("iron all\n")
  sm:run("smelter")                                  -- storage never started
  w:run(30)
  T.contains(mon, "Storage not heard")
end)
