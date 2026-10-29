-- Several standing rules at once: each rule with work gets its share of the furnaces, so an "all"
-- rule with a steady flow of input (logs) can't keep every furnace to itself (#92).
local cc = require("sim.cc")
local T = require("sim.test")
local Inv = require("sim.inv")

Inv.Furnace.recipes["mekanism:dust_uranium"] = "mekanism:ingot_uranium"
Inv.Furnace.recipes["minecraft:cod"] = "minecraft:cooked_cod"

local function base(rules, nf)
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 4 do
    inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local furnaces = {}
  for i = 0, nf - 1 do furnaces[i] = net:add("minecraft:furnace_" .. i, w:furnace()) end
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net))
  st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  local sm = w:computer{ id = 2, label = "Smelter" }
  sm:attach("back", cc.wired(net))
  sm:installRole("smelter")
  sm:writeFile("smelt.txt", rules)
  sm:writeTable("smelter.cfg", { learned = {
    ingot_uranium = { out = "mekanism:ingot_uranium", inputs = { "mekanism:dust_uranium" }, per = { ["mekanism:dust_uranium"] = 1 }, at = 1 },
    cooked_cod = { out = "minecraft:cooked_cod", inputs = { "minecraft:cod" }, per = { ["minecraft:cod"] = 1 }, at = 1 },
  }, speed = {}, factories = {}, enrich = {} })
  return w, st, sm, inv, furnaces
end

local function holding(furnaces, name)
  local n = 0
  for _, f in pairs(furnaces) do if f.slots[1] and f.slots[1].name == name then n = n + 1 end end
  return n
end

T.test("smelter: logs, cod and uranium dust rules all get furnaces", function()
  local w, st, sm, inv, furnaces = base("charcoal all\ncooked_cod 4\ningot_uranium all\n", 6)
  inv[2]:give("minecraft:oak_log", 640)
  inv[3]:give("mekanism:dust_uranium", 1000)
  inv[4]:give("minecraft:cod", 128)
  inv[4]:give("minecraft:coal", 64)
  st:run("storage"); sm:run("smelter")
  w:run(60)
  T.running(st); T.running(sm)
  T.eq(holding(furnaces, "minecraft:oak_log"), 2, "logs in their share of the furnaces")
  T.eq(holding(furnaces, "minecraft:cod"), 2, "cod in its share")
  T.eq(holding(furnaces, "mekanism:dust_uranium"), 2, "uranium dust in its share")
end)

T.test("smelter: a rule that already holds every furnace gives some up to the next rule", function()
  local w, st, sm, inv, furnaces = base("charcoal all\ningot_uranium all\n", 4)
  for i = 0, 3 do furnaces[i]:give("minecraft:oak_log", 40) end
  inv[2]:give("minecraft:oak_log", 1000)
  inv[3]:give("mekanism:dust_uranium", 1000)
  inv[4]:give("minecraft:coal", 64)
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return holding(furnaces, "mekanism:dust_uranium") == 2 end, 900, "uranium dust never got a furnace")
  w:run(60)
  T.eq(holding(furnaces, "minecraft:oak_log"), 2, "logs keep the other half")
  T.eq(holding(furnaces, "mekanism:dust_uranium"), 2, "dust keeps its half")
end)

T.test("smelter: furnaces one rule can't use go to the rule that can", function()
  local w, st, sm, inv, furnaces = base("charcoal all\ningot_uranium all\n", 6)
  inv[2]:give("minecraft:oak_log", 16)
  inv[3]:give("mekanism:dust_uranium", 1000)
  inv[4]:give("minecraft:coal", 64)
  st:run("storage"); sm:run("smelter")
  w:run(30)
  T.eq(holding(furnaces, "mekanism:dust_uranium") >= 4, true, "dust in every furnace the logs don't need")
  T.waitFor(w, function() return inv[2]:count("minecraft:charcoal") + inv[3]:count("minecraft:charcoal") + inv[4]:count("minecraft:charcoal") >= 16 end, 600, "logs never finished")
end)
