-- Every smelter page opens, draws and goes back without an error, at four screen sizes (the layout check for the
-- UI-kit screens, #20): home, recipes, a rule, factories, the add wizard, training, pick the trainer.
local cc = require("sim.cc")
local T = require("sim.test")

local MACHINE = "mekanism:advanced_enriching_factory_0"
local FEED, OUT = "sophisticatedstorage:barrel_65", "sophisticatedstorage:barrel_63"

-- Tap the first of these labels that is on the screen (narrow footers use short ones). Returns whether one was.
local function tap(w, mon, ...)
  for _, label in ipairs({ ... }) do
    local x, y = mon:find(label)
    if x then mon:touch(x, y); w:run(2); return true end
  end
  return false
end
local function must(w, mon, ...)
  T.truthy(tap(w, mon, ...), "none of " .. table.concat({ ... }, ", ") .. " on screen:\n" .. mon:text())
end
-- Back is "< Back" on wider screens, a bare "<" pill on narrow ones
local function back(w, mon)
  if not tap(w, mon, "Back") then
    local y = mon.h
    local x = mon:line(y):find("<", 1, true)
    T.truthy(x, "no Back on screen:\n" .. mon:text())
    mon:touch(x, y); w:run(2)
  end
end

for _, size in ipairs({ { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }) do
  local W, H = size[1], size[2]
  T.test(("smelter pages: every page opens at %dx%d"):format(W, H), function()
    local w = cc.world()
    local net = w:net()
    for i = 0, 3 do net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
    local feed = net:add(FEED, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
    local out = net:add(OUT, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
    for i = 0, 2 do net:add("minecraft:furnace_" .. i, w:furnace()) end
    net:add("minecraft:furnace_9", w:furnace())
    net:add(MACHINE, w:factory{ procs = 5, feed = feed, out = out, recipes = {} })
    local st = w:computer{ id = 1, label = "Storage" }
    st:attach("back", cc.wired(net))
    st:installRole("storage")
    st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
    local sm = w:computer{ id = 2, label = "Smelter", w = W, h = H }
    sm:attach("back", cc.wired(net))
    sm:installRole("smelter")
    sm:writeFile("smelt.txt", "iron all\nstone 20\n")
    sm:writeTable("smelter.cfg", { trainer = "minecraft:furnace_9", factories = { { machine = MACHINE, feed = FEED, out = OUT } },
      enrich = { ["minecraft:raw_iron"] = { out = "mekanism:dust_iron", made = 4, used = 3, drip = true },
                 ["minecraft:ancient_debris"] = { out = "minecraft:netherite_scrap", made = 1, used = 1, drip = true, direct = true },
                 ["minecraft:raw_tin"] = { no = true } } })
    local mon = sm:monitor("top", W, H)
    st:run("storage"); sm:run("smelter")
    w:run(10)
    T.contains(mon, "SMELTER"); T.contains(sm.screen, "SMELTER")
    if W >= 46 then T.contains(mon, "furnace") end

    -- Recipes, one rule, and back to Recipes and home
    must(w, mon, "Recipes", "Rec"); T.contains(mon, "RECIPES"); T.running(sm)
    T.truthy(tap(w, mon, "iron"), "an iron row")
    T.contains(mon, "IRON"); T.contains(mon, "Makes"); T.running(sm)
    back(w, mon); T.contains(mon, "RECIPES")
    back(w, mon); T.contains(mon, "SMELTER")

    -- Factories: the card, the ORES list and the add wizard
    must(w, mon, "Factories", "Fact"); T.contains(mon, "FACTORIES"); T.truthy(mon:text():find("F1", 1, true) or mon:text():find("Factory 1", 1, true), "the factory card:\n" .. mon:text())
    if H >= 13 then T.contains(mon, "ORES") end
    T.running(sm)
    must(w, mon, "+ Add"); T.contains(mon, "ADD A FACTORY"); T.running(sm)
    back(w, mon); T.contains(mon, "FACTORIES")
    back(w, mon); T.contains(mon, "SMELTER")

    -- Training and the trainer pick
    must(w, mon, "TRAIN", "Train"); T.contains(mon, "TRAINING"); T.running(sm)
    must(w, mon, "Change trainer", "Change"); T.contains(mon, "PICK THE TRAINER"); T.running(sm)
    must(w, mon, "Find it"); T.contains(mon, "Drop any item"); T.running(sm)
    must(w, mon, "STOP")
    back(w, mon); T.contains(mon, "TRAINING")
    back(w, mon); T.contains(mon, "SMELTER")

    must(w, mon, "Pause"); T.contains(mon, "paused"); T.running(sm)
    must(w, mon, "Run"); T.running(sm)
    T.absent(mon, "Screen error"); T.absent(sm.screen, "Screen error")
  end)
end
