-- #64: the Factories page's "+ Item" button and pick page, the ORES states (queued / trying n), and Retry / Remove
-- on a selected row. Same functions as the terminal's `enrich add / forget / remove`.
local cc = require("sim.cc")
local T = require("sim.test")

local MACHINE = "mekanism:advanced_enriching_factory_0"
local FEED, OUT = "sophisticatedstorage:barrel_65", "sophisticatedstorage:barrel_63"
local DIRTY = "mekanism:dirty_netherite_scrap"
local DEBRIS, SCRAP, IRON, DUST = "minecraft:ancient_debris", "minecraft:netherite_scrap", "minecraft:raw_iron", "mekanism:dust_iron"

-- opts: w, h, factory (false: the configured machine is not on the cable, so a hand-added item stays queued), enrich
local function setup(opts)
  local W, H = opts.w or 57, opts.h or 24
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 3 do inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
  local feed = net:add(FEED, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  local out = net:add(OUT, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  for i = 0, 1 do net:add("minecraft:furnace_" .. i, w:furnace()) end
  if opts.factory ~= false then net:add(MACHINE, w:factory{ procs = 5, feed = feed, out = out, recipes = { [DEBRIS] = { n = 1, out = SCRAP, made = 1 }, [DIRTY] = { n = 1, out = SCRAP, made = 1 } } }) end
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net)); st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  local sm = w:computer{ id = 2, label = "Smelter", w = W, h = H }
  sm:attach("back", cc.wired(net)); sm:installRole("smelter")
  sm:writeFile("smelt.txt", "netherite_scrap 1\n")
  sm:writeTable("smelter.cfg", { factories = { { machine = MACHINE, feed = FEED, out = OUT } },
    enrich = opts.enrich, enrichExtra = opts.extra })
  local mon = sm:monitor("top", W, H)
  inv[2]:give(DEBRIS, 30); inv[2]:give(DIRTY, 30); inv[2]:give(IRON, 40); inv[2]:give("minecraft:diamond", 500); inv[2]:give("minecraft:coal", 32)
  return w, st, sm, mon
end

local function tap(w, mon, ...)
  for _, label in ipairs({ ... }) do
    local x, y = mon:find(label)
    if x then mon:touch(x, y); w:run(1.5); return end
  end
  error("none of " .. table.concat({ ... }, ", ") .. " on screen:\n" .. mon:text())
end
local function cfgOf(sm) return sm:readTable("smelter.cfg") or {} end
local IRON_LEARNED = { [IRON] = { out = DUST, made = 4, used = 3, drip = true } }

for _, size in ipairs({ { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }) do
  local W, H = size[1], size[2]
  T.test(("item: + Item, pick ancient debris, it is queued on the ORES list (%dx%d)"):format(W, H), function()
    local w, st, sm, mon = setup{ w = W, h = H, factory = false, enrich = IRON_LEARNED }
    st:run("storage"); sm:run("smelter"); w:run(12)
    tap(w, mon, "Factories", "Fact")
    T.contains(mon, "FACTORIES"); T.contains(mon, "+ Item")
    tap(w, mon, "+ Item")
    T.contains(mon, "ADD AN ITEM")
    T.contains(mon, "already on")                           -- raw iron is on the list
    T.absent(mon, "diamond", "smeltable only: no furnace cooks a diamond")
    tap(w, mon, "All")
    T.contains(mon, "diamond")
    tap(w, mon, "Smeltable", "Smelt")
    tap(w, mon, "ancient debris")
    tap(w, mon, "Try it")
    T.contains(mon, "FACTORIES"); T.contains(mon, "queued")
    T.contains(sm.screen, "ancient debris queued")
    T.truthy(mon:text():find("+ancient", 1, true), "the + mark:\n" .. mon:text())
    T.eq(cfgOf(sm).enrichExtra[1], DEBRIS)
    T.absent(mon, "Screen error"); T.running(sm)
  end)
end

T.test("item: Cancel and an already-on item add nothing", function()
  local w, st, sm, mon = setup{ enrich = IRON_LEARNED }
  st:run("storage"); sm:run("smelter"); w:run(12)
  tap(w, mon, "Factories"); tap(w, mon, "+ Item")
  tap(w, mon, "raw iron"); tap(w, mon, "Try it")
  T.contains(mon, "ADD AN ITEM", "an already-on item can't be picked")
  tap(w, mon, "Back")
  T.contains(mon, "FACTORIES")
  T.eq(#(cfgOf(sm).enrichExtra or {}), 0)
end)

T.test("item: a hand-added item shows trying n or queued, then what it learned; Retry forgets it, Remove (tap twice) drops it", function()
  local w, st, sm, mon = setup{ extra = { DEBRIS } }
  st:run("storage"); sm:run("smelter"); w:run(2)
  tap(w, mon, "Factories")
  T.truthy(mon:text():find("queued", 1, true) or mon:text():find("trying", 1, true), "queued or trying:\n" .. mon:text())
  T.waitFor(w, function() return cfgOf(sm).enrich and cfgOf(sm).enrich[DEBRIS] end, 600, "never learned")
  w:run(3)
  -- Retry
  tap(w, mon, "netherite scrap per")
  T.contains(mon, "Retry"); T.contains(mon, "Remove")
  tap(w, mon, "Retry")
  T.eq(cfgOf(sm).enrichExtra[1], DEBRIS, "Retry keeps it on the list")
  T.waitFor(w, function() return cfgOf(sm).enrich and cfgOf(sm).enrich[DEBRIS] end, 600, "never learned again")
  w:run(3)
  -- Remove, tap twice
  tap(w, mon, "netherite scrap per"); tap(w, mon, "Remove")
  T.contains(mon, "Sure?"); T.eq(cfgOf(sm).enrichExtra[1], DEBRIS, "one tap does not remove")
  tap(w, mon, "Sure?")
  T.eq(#(cfgOf(sm).enrichExtra or {}), 0); T.eq((cfgOf(sm).enrich or {})[DEBRIS], nil)
  T.absent(mon, "ORES")
end)

T.test("item: a learned ore (not hand-added) can be retried but not removed", function()
  local w, st, sm, mon = setup{ enrich = IRON_LEARNED }
  st:run("storage"); sm:run("smelter"); w:run(12)
  tap(w, mon, "Factories"); tap(w, mon, "iron ->")
  T.contains(mon:line(mon.h), "Retry"); T.absent(mon:line(mon.h), "Remove")
  tap(w, mon, "Retry")
  T.eq((cfgOf(sm).enrich or {})[IRON], nil)
end)

T.test("item: enrich remove drops a hand-added item and its result", function()
  local w, st, sm, mon = setup{ extra = { DEBRIS }, enrich = { [DEBRIS] = { out = SCRAP, made = 1, used = 1, drip = true, direct = true } } }
  st:run("storage"); sm:run("smelter"); w:run(12)
  sm:type("enrich remove ancient_debris"); sm:key(257); w:run(1.5)
  T.contains(sm.screen, "ancient debris is off the factory list")
  T.eq(#(cfgOf(sm).enrichExtra or {}), 0); T.eq((cfgOf(sm).enrich or {})[DEBRIS], nil)
  sm:type("enrich remove ancient_debris"); sm:key(257); w:run(1.5)
  T.contains(sm.screen, "was added by hand")
end)
