-- The drip trial: a new ore goes into a factory one item at a time (computer/smelter/drip.lua), so a trial
-- uses as few items as possible. Runs the real smelter and storage against a mock Mekanism factory (sim/factory.lua).
local cc = require("sim.cc")
local T = require("sim.test")

local MACHINE = "mekanism:advanced_enriching_factory_0"
local FEED, OUT = "sophisticatedstorage:barrel_65", "sophisticatedstorage:barrel_63"
local DUST = "mekanism:dust_iron"

-- opts: procs, recipes, progress ("rises"|"end"), cfg (extra smelter.cfg keys), factory (false: cfg points at nothing), raw
local function setup(opts)
  opts = opts or {}
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 3 do inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
  local feed = net:add(FEED, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  local out = net:add(OUT, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  for i = 0, 1 do net:add("minecraft:furnace_" .. i, w:furnace()) end
  local fac
  if opts.factory ~= false then
    fac = net:add(MACHINE, w:factory{ procs = opts.procs or 5, feed = feed, out = out, progress = opts.progress,
      recipes = opts.recipes or { ["minecraft:raw_iron"] = { n = 3, out = DUST, made = 4 } } })
    fac.eject, fac.autoSort = true, true
  end
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net))
  st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  local sm = w:computer{ id = 2, label = "Smelter" }
  sm:attach("back", cc.wired(net))
  sm:installRole("smelter")
  sm:writeFile("smelt.txt", "iron all\n")
  local mon = sm:monitor("top", 57, 24)
  local cfg = { factories = { { machine = MACHINE, feed = FEED, out = OUT } } }
  for k, v in pairs(opts.cfg or {}) do cfg[k] = v end
  sm:writeTable("smelter.cfg", cfg)
  inv[2]:give(opts.raw or "minecraft:raw_iron", opts.count or 48)
  inv[2]:give("minecraft:coal", 32)
  return w, st, sm, inv, fac, mon, feed, out
end

local function learned(sm, ore) local c = sm:readTable("smelter.cfg"); return c and c.enrich and c.enrich[ore or "minecraft:raw_iron"] end

T.test("drip: a 3-in recipe in a 3-process factory learns used=3 made=4 with 3 items, and settings come back", function()
  local w, st, sm, inv, fac, mon, feed = setup{ procs = 3 }
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return learned(sm) end, 400, "never learned raw iron")
  local e = learned(sm)
  T.contains({ text = function() return sm:output() end }, "Factory: 3 raw iron -> 4")
  T.eq(e.out, DUST); T.eq(e.used, 3, "used"); T.eq(e.made, 4, "made"); T.eq(e.drip, true, "drip marker")
  T.eq(fac.eject, true, "eject restored"); T.eq(fac.autoSort, true, "auto-sort restored")
  T.eq(sm:readTable("smelter.cfg").trialSaved, nil, "nothing left to restore")
  T.running(sm)
end)

T.test("drip: a 1-in recipe on a 5-process factory uses exactly one item", function()
  local w, st, sm, inv, fac = setup{ procs = 5, raw = "minecraft:ancient_debris", count = 30,
    recipes = { ["minecraft:ancient_debris"] = { n = 1, out = "mekanism:dust_netherite_scrap", made = 2 } } }
  sm:writeFile("smelt.txt", "netherite_scrap all\n")
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return learned(sm, "minecraft:ancient_debris") end, 400, "never learned debris")
  local e = learned(sm, "minecraft:ancient_debris")
  T.eq(e.used, 1, "used"); T.eq(e.made, 2, "made")
  T.contains({ text = function() return sm:output() end }, "Factory: 1 ancient debris -> 2")
end)

T.test("drip: progress detector (setting on) learns the same, faster", function()
  local w, st, sm, inv, fac = setup{ procs = 5, progress = "rises", cfg = { dripProgress = true } }
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return learned(sm) end, 400, "never learned")
  local e = learned(sm)
  T.eq(e.used, 3); T.eq(e.made, 4)
end)

T.test("drip: the progress detector can't tell a process started if progress stays 0: fallback setting still works", function()
  local w, st, sm, inv, fac = setup{ procs = 5, progress = "end" }
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return learned(sm) end, 400, "never learned")
  T.eq(learned(sm).used, 3)
end)

T.test("drip: an ore the factory refuses is recorded no, one item is stuck in the hopper, and Tanis is told", function()
  local w, st, sm, inv, fac, mon = setup{ recipes = { ["minecraft:raw_gold"] = { n = 3, out = "mekanism:dust_gold", made = 4 } } }
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() local e = learned(sm); return e and e.no end, 400, "never refused")
  T.eq(fac.hopper and fac.hopper.count, 1, "one item in the hopper")
  T.contains(sm.screen, "stuck")
  T.eq(fac.eject, true); T.eq(fac.autoSort, true)
end)

T.test("drip: 16 items with nothing started calls the trial off, learns nothing, says what's inside", function()
  local w, st, sm, inv, fac, mon = setup{ recipes = { ["minecraft:raw_iron"] = { n = 40, out = DUST, made = 4 } } }
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return sm:output():find("nothing started", 1, true) end, 900, "trial never called off")
  T.eq(learned(sm), nil, "nothing learned")
  T.eq(fac:total(), 16, "16 items dripped")
  T.contains({ text = function() return sm:output() end }, "16 raw iron")
  T.eq(fac.eject, true); T.eq(fac.autoSort, true)
end)

T.test("drip: nothing is learned while the factory has no power; it carries on when power returns", function()
  local w, st, sm, inv, fac = setup{ procs = 3, count = 400 }   -- plenty: the furnaces take ore while the factory is down
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return fac:total() >= 1 end, 300, "never started")
  fac.energy = 0
  w:run(300)
  T.eq(learned(sm), nil, "nothing learned at 0 energy")
  T.eq(fac:total() <= 3, true, "no more than the recipe needs went in")
  fac.energy = 1
  T.waitFor(w, function() return learned(sm) end, 600, "never learned after power came back")
  T.eq(learned(sm).used, 3)
end)

T.test("drip: cancelling a trial (factory remove) puts eject and auto-sort back", function()
  local w, st, sm, inv, fac = setup{ procs = 3 }
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return fac.eject == false and fac.autoSort == false end, 300, "trial never began")
  sm:type("factory remove 1"); sm:key(257)
  T.waitFor(w, function() return fac.eject == true and fac.autoSort == true end, 60, "settings not restored after cancel")
  T.eq(sm:readTable("smelter.cfg").trialSaved, nil)
end)

T.test("drip: a reboot mid-trial puts eject and auto-sort back", function()
  local w, st, sm, inv, fac = setup{ procs = 3 }
  st:run("storage"); sm:run("smelter")
  T.waitFor(w, function() return fac.eject == false and fac.autoSort == false end, 300, "trial never began")
  T.eq(sm:readTable("smelter.cfg").trialSaved[MACHINE].eject, true, "originals saved")
  sm:reboot(); sm:run("smelter")
  T.waitFor(w, function() return fac.eject == true and fac.autoSort == true end, 120, "settings not restored after reboot")
  T.eq(sm:readTable("smelter.cfg").trialSaved, nil)
end)

T.test("drip: a factory that's gone is called missing, re-add it, on the screen and the terminal", function()
  local w, st, sm, inv, fac, mon = setup{ factory = false }
  st:run("storage"); sm:run("smelter")
  w:run(60)
  T.contains(sm.screen, "missing")
  T.contains({ text = function() return sm:output() end }, "re-add it")
end)

T.test("drip: the probe command drips one item at a time and logs every sample", function()
  local w, st, sm, inv, fac = setup{ procs = 5, progress = "rises" }
  sm:writeFile("smelt.txt", "stone 1\n")           -- no rule wants iron: only the probe runs
  st:run("storage"); sm:run("smelter")
  w:run(10)
  sm:type("probe raw_iron"); sm:key(257)
  T.waitFor(w, function() return sm:readFile("probe.log") end, 600, "no probe.log")
  local log = sm:readFile("probe.log")
  T.eq(log:find("prog=", 1, true) ~= nil, true, "samples have progress")
  T.eq(log:find("p4 in=", 1, true) ~= nil, true, "one column per process")
  T.eq(fac.eject, true); T.eq(fac.autoSort, true)
  T.eq(learned(sm), nil, "the probe learns nothing")
end)
