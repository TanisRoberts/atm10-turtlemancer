-- #62: "enrich add <item>" and direct final products (ancient debris -> netherite scrap in a factory).
-- A direct product never waits on a dust check; raw iron still goes the dust route.
local cc = require("sim.cc")
local T = require("sim.test")

local MACHINE = "mekanism:advanced_enriching_factory_0"
local FEED, OUT = "sophisticatedstorage:barrel_65", "sophisticatedstorage:barrel_63"
local DEBRIS, SCRAP = "minecraft:ancient_debris", "minecraft:netherite_scrap"

local function setup(opts)
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 3 do inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
  local feed = net:add(FEED, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  local out = net:add(OUT, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  for i = 0, 1 do net:add("minecraft:furnace_" .. i, w:furnace()) end
  local fac = net:add(MACHINE, w:factory{ procs = 5, feed = feed, out = out, recipes = opts.recipes })
  fac.eject, fac.autoSort = true, true
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net))
  st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  local sm = w:computer{ id = 2, label = "Smelter" }
  sm:attach("back", cc.wired(net))
  sm:installRole("smelter")
  sm:writeFile("smelt.txt", opts.rules or "netherite_scrap 1\n")
  sm:writeTable("smelter.cfg", { factories = { { machine = MACHINE, feed = FEED, out = OUT } }, enrich = opts.enrich })
  for item, n in pairs(opts.items) do inv[2]:give(item, n) end
  inv[2]:give("minecraft:coal", 32)
  return w, st, sm, inv, fac, out
end

local function cfgOf(sm) return sm:readTable("smelter.cfg") or {} end
local function learned(sm, ore) local c = cfgOf(sm); return c.enrich and c.enrich[ore] end
local function scrapEverywhere(inv, out)
  local n = out:count(SCRAP)
  for i = 0, 3 do n = n + inv[i]:count(SCRAP) end
  return n
end
local DEBRIS_RECIPE = { [DEBRIS] = { n = 1, out = SCRAP, made = 2 } }

T.test("direct: enrich add queues a trial, the entry is marked direct, debris goes through the factory into storage", function()
  local w, st, sm, inv, fac, out = setup{ items = { [DEBRIS] = 30 }, recipes = DEBRIS_RECIPE }
  st:run("storage"); sm:run("smelter")
  w:run(15)
  sm:type("enrich add ancient_debris"); sm:key(257)
  T.waitFor(w, function() return cfgOf(sm).enrichExtra and cfgOf(sm).enrichExtra[1] == DEBRIS end, 30, "not saved to enrichExtra")
  T.waitFor(w, function() return learned(sm, DEBRIS) end, 600, "never learned debris")
  local e = learned(sm, DEBRIS)
  T.eq(e.direct, true, "direct marker"); T.eq(e.out, SCRAP); T.eq(e.made, 2); T.eq(e.used, 1)
  -- the keep-N rule on netherite_scrap now pulls debris through the factory (2 scrap per debris)
  T.waitFor(w, function() return scrapEverywhere(inv, out) >= 6 end, 900, "scrap never reached storage")
  T.eq(fac.eject, true)
  T.running(sm)
end)

T.test("direct: a direct product never sits on hold waiting for a dust check (trainer set, nothing to check)", function()
  local w, st, sm, inv, fac, out = setup{ items = { [DEBRIS] = 30 }, recipes = DEBRIS_RECIPE,
    enrich = { [DEBRIS] = { out = SCRAP, used = 1, made = 2, drip = true, at = 1 } } }
  local c = cfgOf(sm); c.trainer = "minecraft:furnace_1"; sm:writeTable("smelter.cfg", c)
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return scrapEverywhere(inv, out) >= 4 end, 900, "debris waited instead of going to the factory")
end)

T.test("direct: raw iron still takes the dust route (not marked direct)", function()
  local w, st, sm, inv, fac = setup{ items = { ["minecraft:raw_iron"] = 24 }, rules = "iron all\n",
    recipes = { ["minecraft:raw_iron"] = { n = 3, out = "mekanism:dust_iron", made = 4 } } }
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return learned(sm, "minecraft:raw_iron") end, 600, "never learned")
  local e = learned(sm, "minecraft:raw_iron")
  T.eq(e.direct, nil, "not direct"); T.eq(e.out, "mekanism:dust_iron")
end)

T.test("direct: an added item whose output smelts into nothing stays in the furnaces", function()
  local w, st, sm, inv, fac = setup{ items = { ["minecraft:clay_ball"] = 400 }, rules = "brick all\n",
    recipes = { ["minecraft:clay_ball"] = { n = 1, out = "mymod:weird_gravel", made = 2 } } }
  st:run("storage"); sm:run("smelter")
  w:run(15)
  sm:type("enrich add clay_ball"); sm:key(257)
  T.waitFor(w, function() return learned(sm, "minecraft:clay_ball") end, 600, "never learned")
  T.eq(learned(sm, "minecraft:clay_ball").direct, nil, "not direct: the furnace makes brick, not gravel")
  local before = fac:total()
  T.waitFor(w, function()
    local n = 0
    for i = 0, 3 do n = n + inv[i]:count("minecraft:brick") end
    return n >= 10
  end, 900, "the furnaces never took the clay")
  T.eq(fac:total() <= before + 2, true, "nothing more is routed to the factory")
end)

T.test("direct: enrich forget re-trials but keeps the item on the list; a restart keeps the list", function()
  local w, st, sm, inv, fac, out = setup{ items = { [DEBRIS] = 30 }, recipes = DEBRIS_RECIPE }
  st:run("storage"); sm:run("smelter")
  w:run(15)
  sm:type("enrich add ancient_debris"); sm:key(257)
  T.waitFor(w, function() return learned(sm, DEBRIS) end, 600, "never learned")
  sm:type("enrich forget ancient_debris"); sm:key(257)
  T.waitFor(w, function() return learned(sm, DEBRIS) == nil end, 30, "not forgotten")
  T.eq(cfgOf(sm).enrichExtra[1], DEBRIS, "still on the list")
  sm:reboot(); sm:run("smelter")
  T.eq(cfgOf(sm).enrichExtra[1], DEBRIS, "list survives a restart")
  T.waitFor(w, function() return learned(sm, DEBRIS) end, 900, "not re-trialled")
  T.eq(learned(sm, DEBRIS).direct, true)
end)
