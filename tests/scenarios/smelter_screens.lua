-- The smelter's screens on the UI kit (#20): lists, taps, the training page from idle to learned, the factories page
-- (ORES states, the missing-factory message, add and remove), the typed commands, and the notices that must stay.
local cc = require("sim.cc")
local T = require("sim.test")

local RAW, INGOT = "create:raw_zinc", "create:zinc_ingot"
cc.Inv.Furnace.recipes[RAW] = INGOT
local MACHINE = "mekanism:advanced_enriching_factory_0"
local FEED, OUT = "sophisticatedstorage:barrel_65", "sophisticatedstorage:barrel_63"
local DUST = "mekanism:dust_iron"

-- opts: w, h (size of both screens), cfg, factory (false: the cfg's machine is not on the cable), raw (put in the trainer)
local function setup(opts)
  opts = opts or {}
  local W, H = opts.w or 57, opts.h or 24
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 3 do inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
  local feed = net:add(FEED, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  local out = net:add(OUT, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  for i = 0, 2 do net:add("minecraft:furnace_" .. i, w:furnace()) end
  local tr = net:add("minecraft:furnace_9", w:furnace())
  local fac
  if opts.factory ~= false then fac = net:add(MACHINE, w:factory{ procs = 5, feed = feed, out = out, recipes = {} }) end
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net)); st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  local sm = w:computer{ id = 2, label = "Smelter", w = W, h = H }
  sm:attach("back", cc.wired(net)); sm:installRole("smelter")
  sm:writeFile("smelt.txt", "iron all\nstone 20\n")
  local cfg = { trainer = "minecraft:furnace_9", factories = { { machine = MACHINE, feed = FEED, out = OUT } } }
  for k, v in pairs(opts.cfg or {}) do cfg[k] = v end
  sm:writeTable("smelter.cfg", cfg)
  local mon = sm:monitor("top", W, H)
  inv[2]:give("minecraft:coal", 32)
  inv[2]:give("minecraft:raw_iron", 40)
  if opts.raw then tr:give(RAW, 1) end
  return w, st, sm, mon, inv, tr, net, fac
end

local function tap(w, mon, label)
  local x, y = mon:find(label)
  T.truthy(x, "no '" .. label .. "' on screen:\n" .. mon:text())
  mon:touch(x, y); w:run(1.5)
end
-- The lowest match: a button is under the page title that shares its word (TRAIN under TRAINING)
local function tapLast(w, mon, label)
  for y = mon.h, 1, -1 do
    local x = mon:line(y):find(label, 1, true)
    if x then mon:touch(x, y); w:run(1.5); return end
  end
  error("no '" .. label .. "' on screen:\n" .. mon:text())
end
local function say(w, sm, line) sm:type(line); sm:key(257); w:run(1.5) end
local function colourAt(mon, label)
  local x, y = mon:find(label)
  T.truthy(x, "no '" .. label .. "' on screen:\n" .. mon:text())
  return mon:colourAt(x, y)
end
local COL = require("sim.env").colors

---------------------------------------------------------------------------------------------------------
T.test("smelter screens: home lists the array, the trainer, the factories and the rules; a tile tap says its speed", function()
  local w, st, sm, mon = setup{ raw = true }
  st:run("storage"); sm:run("smelter"); w:run(40)
  T.contains(mon, "SMELTER"); T.contains(mon, "3 furnaces"); T.contains(mon, "cooking")
  T.contains(mon, "TRAINER"); T.contains(mon, "1 zinc: tap TRAIN")
  T.contains(mon, "FACTORIES"); T.contains(mon, "F1")
  T.contains(mon, "RULES"); T.contains(mon, "iron")
  T.contains(mon, "iron", "the item in a cooking tile")
  T.absent(mon, "Screen error")
  tap(w, mon, "FURNACE")
  T.contains(mon, "per item", "a tile tap says its speed")
  T.running(sm)
end)

T.test("smelter screens: Pause and Run, the paused header, a one-off job in the list", function()
  local w, st, sm, mon = setup()
  st:run("storage"); sm:run("smelter"); w:run(10)
  tap(w, mon, "Pause")
  T.contains(mon, "paused"); T.contains(mon, "Run")
  T.eq(sm:readTable("smelter.cfg").paused, true)
  tap(w, mon, "Run"); T.absent(mon, "paused")
  say(w, sm, "smelt stone 400")
  T.contains(mon, "ONE-OFF JOBS"); T.contains(mon, "400 left")
end)

T.test("smelter screens: storage not heard shows the red alert line and the error state", function()
  local w, st, sm, mon = setup()
  sm:run("smelter"); w:run(30)                              -- no storage computer
  T.contains(mon, "Storage not heard"); T.contains(mon, "error")
  local _, bg = colourAt(mon, "Storage not heard")
  T.eq(bg, COL.black)
  local fg = colourAt(mon, "Storage not heard")
  T.eq(fg, COL.red, "red alert text")
end)

T.test("smelter screens: recipes list marks what is learned, one tap opens a rule, Save keeps a rule", function()
  local w, st, sm, mon = setup{ cfg = { learned = { zinc_ingot = { out = INGOT, inputs = { RAW }, per = { [RAW] = 1 }, at = 1 } } } }
  st:run("storage"); sm:run("smelter"); w:run(10)
  tap(w, mon, "Recipes")
  T.contains(mon, "RECIPES"); T.contains(mon, "known"); T.contains(mon, "learned")
  T.contains(mon, "zinc ingot")
  T.contains(mon, "all", "the iron rule's tag")
  tap(w, mon, "zinc ingot")
  T.contains(mon, "ZINC INGOT"); T.contains(mon, "Makes"); T.contains(mon, "learned")
  T.contains(mon, "Forget", "a learned recipe can be forgotten")
  tap(w, mon, "Keep N stacks")
  T.contains(mon, "Keep"); T.contains(mon, "(tap Save)")
  tapLast(w, mon, "Save")
  T.contains(mon, "RECIPES", "Save goes back to where the rule was opened")
  T.contains(sm:readFile("smelt.txt"), "zinc_ingot")
  -- forget is tap-twice
  tap(w, mon, "zinc ingot"); tap(w, mon, "Forget")
  T.contains(mon, "Sure?"); T.truthy(sm:readTable("smelter.cfg").learned.zinc_ingot, "not forgotten by one tap")
  tap(w, mon, "Sure?")
  T.eq(sm:readTable("smelter.cfg").learned.zinc_ingot, nil, "forgotten by the second")
end)

T.test("smelter screens: a rule page queues a one-off job", function()
  local w, st, sm, mon = setup()
  st:run("storage"); sm:run("smelter"); w:run(10)
  tap(w, mon, "Recipes"); tap(w, mon, "cobblestone >"); T.contains(mon, "DO IT NOW")
  tap(w, mon, "Smelt 64")
  T.contains(mon, "Queued 64")
end)

---------------------------------------------------------------------------------------------------------
T.test("smelter screens: training goes idle, ready, cooking, learned; the rule is chosen and saved", function()
  local w, st, sm, mon, inv, tr = setup{}
  st:run("storage"); sm:run("smelter"); w:run(10)
  tap(w, mon, "TRAIN")
  T.contains(mon, "TRAINING"); T.contains(mon, "Put the raw item"); T.contains(mon, "PUT IN"); T.contains(mon, "COMES OUT")
  tr:give(RAW, 1); w:run(3)
  T.contains(mon, "Ready: 1 raw zinc"); T.contains(mon, "raw zinc")
  tapLast(w, mon, "TRAIN")
  w:run(5)
  T.contains(mon, "working"); T.contains(mon, "CANCEL")
  T.waitFor(w, function() return mon:text():find("Learned: raw zinc", 1, true) end, 300, "never reached the learned screen")
  T.contains(mon, "What should I do with zinc ingot?")
  T.contains(mon, "No rule"); T.contains(mon, "Keep N stacks"); T.contains(mon, "Smelt all"); T.contains(mon, "Just learn it")
  tap(w, mon, "Smelt all"); tap(w, mon, "Save")
  T.contains(mon, "SMELTER"); T.contains(mon, "Rule saved: smelt all")
  T.contains(sm:readFile("smelt.txt"), "zinc_ingot all")
  T.running(sm)
end)

T.test("smelter screens: Just learn it saves the recipe with no rule; Cancel is tap-twice", function()
  local w, st, sm, mon, inv, tr = setup{ raw = true }
  st:run("storage"); sm:run("smelter"); w:run(10)
  tap(w, mon, "TRAIN"); tapLast(w, mon, "TRAIN"); w:run(5)
  tap(w, mon, "CANCEL"); T.contains(mon, "Sure?"); T.absent(mon, "cancelled")
  tap(w, mon, "Sure?"); T.contains(mon, "Training cancelled")
  w:run(60)
  tr:give(RAW, 1); w:run(3)
  tapLast(w, mon, "TRAIN")
  T.waitFor(w, function() return mon:text():find("Just learn it", 1, true) end, 300, "never learned")
  tap(w, mon, "Just learn it")
  T.contains(mon, "Learned zinc_ingot, no rule")
  T.truthy(sm:readTable("smelter.cfg").learned.zinc_ingot)
  T.absent(sm:readFile("smelt.txt"), "zinc")
end)

T.test("smelter screens: no trainer asks for one; the pick page lists the furnaces; a tap makes one the trainer", function()
  local w, st, sm, mon = setup{ cfg = { trainer = false } }
  sm:writeTable("smelter.cfg", { factories = {} })
  st:run("storage"); sm:run("smelter"); w:run(10)
  tap(w, mon, "TRAIN"); T.contains(mon, "No training furnace yet")
  tap(w, mon, "PICK THE TRAINER")
  T.contains(mon, "PICK THE TRAINER"); T.contains(mon, "Tap one to make it the trainer"); T.contains(mon, "furnace_9")
  tap(w, mon, "furnace_9")
  T.contains(mon, "TRAINING"); T.contains(mon, "furnace_9 is the trainer now")
  T.eq(sm:readTable("smelter.cfg").trainer, "minecraft:furnace_9")
  tap(w, mon, "Change trainer"); tap(w, mon, "No trainer")
  T.contains(mon, "Sure?"); tap(w, mon, "Sure?")
  T.contains(mon, "SMELTER"); T.eq(sm:readTable("smelter.cfg").trainer, nil)
end)

T.test("smelter screens: a run cut off by a power cut says so on the screen (#12)", function()
  local w, st, sm, mon = setup{ cfg = { training = { input = RAW } } }
  st:run("storage"); sm:run("smelter"); w:run(2)
  T.contains(mon, "Restarted mid-training")
  T.contains(sm.screen, "Restarted mid-training")
end)

---------------------------------------------------------------------------------------------------------
T.test("smelter screens: the factories page has the card, the ORES list with its states, and a tap-twice Remove", function()
  local w, st, sm, mon = setup{ cfg = { learned = { dust_iron = { out = "minecraft:iron_ingot", inputs = { DUST }, per = { [DUST] = 1 }, at = 1 } }, enrich = {
    ["minecraft:raw_iron"] = { out = DUST, made = 4, used = 3, drip = true },
    ["minecraft:ancient_debris"] = { out = "minecraft:netherite_scrap", made = 1, used = 1, drip = true, direct = true },
    ["minecraft:raw_tin"] = { no = true } } } }
  st:run("storage"); sm:run("smelter"); w:run(15)
  tap(w, mon, "Factories")
  T.contains(mon, "FACTORIES"); T.contains(mon, "1 set up"); T.contains(mon, "Factory 1"); T.contains(mon, "advanced_enriching_factory_0")
  T.contains(mon, "ORES")
  T.contains(mon, "iron -> 4 dust iron per 3"); T.contains(mon, "via dust")
  T.contains(mon, "ancient debris -> 1 netherite scrap per 1"); T.contains(mon, "direct")
  T.contains(mon, "tin"); T.contains(mon, "refused")
  T.contains(mon, "direct"); T.eq((colourAt(mon, "direct")), COL.lime, "direct is lime")
  T.eq((colourAt(mon, "via dust")), COL.lime, "via dust is lime")
  T.eq((colourAt(mon, "refused")), COL.orange, "refused is orange")
  T.contains(mon, "+ Item")
  T.absent(mon:line(mon.h), "Remove")
  tap(w, mon, "Factory 1")
  T.contains(mon, "Remove F1")
  tap(w, mon, "Remove F1"); T.contains(mon, "Sure?")
  T.eq(#sm:readTable("smelter.cfg").factories, 1, "one tap does not remove")
  tap(w, mon, "Sure?")
  T.eq(#(sm:readTable("smelter.cfg").factories or {}), 0, "the second does")
  T.contains(mon, "No factories yet")
end)

T.test("smelter screens: a factory whose machine is gone says so, in red, with the cable note", function()
  local w, st, sm, mon = setup{ factory = false }
  st:run("storage"); sm:run("smelter"); w:run(60)
  T.contains(mon, "factory missing")
  tap(w, mon, "Factories")
  T.contains(mon, "factory missing, re-add it"); T.contains(mon, "not on the cable")
  T.eq((colourAt(mon, "factory missing, re-add it")), COL.red)
  T.eq(mon:line(1):find("FACTORIES", 1, true) ~= nil, true, "the terminal log lines do not push the header off")
  tap(w, mon, "Factory 1"); T.contains(mon, "Remove F1")
end)

T.test("smelter screens: + Add walks machine, feed barrel and out barrel", function()
  local w, st, sm, mon, inv, tr, net = setup{ cfg = { factories = {} } }
  net:add("minecraft:barrel_20", cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  net:add("minecraft:barrel_21", cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  st:run("storage"); sm:run("smelter"); w:run(10)
  tap(w, mon, "Factories"); tapLast(w, mon, "+ Add")
  T.contains(mon, "ADD A FACTORY"); T.contains(mon, "step 1/3"); T.contains(mon, "Pick the factory")
  tap(w, mon, "advanced_enriching_factory_0")
  T.contains(mon, "step 2/3"); T.contains(mon, "FEED barrel"); T.contains(mon, "factory advanced_enriching_factory_0")
  tap(w, mon, "barrel_20")
  T.contains(mon, "step 3/3"); T.contains(mon, "OUT barrel")
  tap(w, mon, "barrel_21")
  T.contains(mon, "FACTORIES"); T.contains(mon, "Factory 1 added")
  local f = sm:readTable("smelter.cfg").factories[1]
  T.eq(f.feed, "minecraft:barrel_20"); T.eq(f.out, "minecraft:barrel_21")
end)

---------------------------------------------------------------------------------------------------------
T.test("smelter screens: typed commands, with or without the slash, and /help", function()
  local w, st, sm, mon = setup{}
  st:run("storage"); sm:run("smelter"); w:run(10)
  say(w, sm, "/help")
  T.contains(sm.screen, "/smelt"); T.contains(sm.screen, "/help")
  say(w, sm, "help factory"); T.contains(sm.screen, "factory add <machine> <feed> <out>")
  say(w, sm, "smelt stone 400")
  T.contains(sm.screen, "Queued 400"); T.contains(sm.screen, "400 left")
  say(w, sm, "/smelt stone")
  T.contains(sm.screen, "Usage: /smelt <item> <n>")
  say(w, sm, "recipes"); T.contains(sm.screen, "RECIPES")
  say(w, sm, "home"); T.contains(sm.screen, "SMELTER")
  say(w, sm, "rule iron"); T.contains(sm.screen, "IRON")
  say(w, sm, "factories"); T.contains(sm.screen, "FACTORIES")
  say(w, sm, "trainer"); T.contains(sm.screen, "PICK THE TRAINER")
  say(w, sm, "train"); T.contains(sm.screen, "TRAINING")
  say(w, sm, "pause"); T.eq(sm:readTable("smelter.cfg").paused, true)
  say(w, sm, "run"); T.eq(sm:readTable("smelter.cfg").paused, false)
  say(w, sm, "status"); T.contains(sm.screen, "furnace(s)")
  say(w, sm, "nonsense"); T.contains(sm.screen, "Unknown command /nonsense")
  T.running(sm)
end)

T.test("smelter screens: enrich add and forget, factory remove and probe stop through the command bar", function()
  local w, st, sm, mon, inv = setup{ cfg = { enrich = { ["minecraft:raw_iron"] = { out = DUST, made = 4, used = 3, drip = true } } } }
  inv[2]:give("minecraft:ancient_debris", 4)
  st:run("storage"); sm:run("smelter"); w:run(15)
  say(w, sm, "enrich add ancient_debris")
  T.contains(sm.screen, "ancient debris will be tried in a factory")
  T.eq(sm:readTable("smelter.cfg").enrichExtra[1], "minecraft:ancient_debris")
  say(w, sm, "/enrich forget raw_iron")
  T.contains(sm.screen, "Forgot what the factories learned about raw_iron")
  say(w, sm, "enrich add nosuchthing"); T.contains(sm.screen, "No 'nosuchthing' in storage")
  say(w, sm, "probe stop"); T.contains(sm.screen, "Probe stopped")
  say(w, sm, "factory remove 7"); T.contains(sm.screen, "No factory 7")
  say(w, sm, "factory remove 1"); T.contains(sm.screen, "Factory 1 removed")
  say(w, sm, "factory add nothing a b"); T.contains(sm.screen, "No factory called nothing")
  T.running(sm)
end)

T.test("smelter screens: the / command bar lists the commands and runs the chosen one", function()
  local w, st, sm, mon = setup{}
  st:run("storage"); sm:run("smelter"); w:run(10)
  sm:type("/"); w:run(1)
  T.contains(sm.screen, "/smelt"); T.contains(sm.screen, "/enrich"); T.contains(sm.screen, "/probe")
  sm:type("pau"); w:run(1)
  T.contains(sm.screen, "/pause"); T.absent(sm.screen, "/probe")
  sm:key(257); w:run(1.5)
  T.eq(sm:readTable("smelter.cfg").paused, true)
end)

for _, size in ipairs({ { 51, 19 }, { 39, 13 }, { 26, 20 } }) do
  T.test(("smelter screens: training and ORES draw at %dx%d without losing the buttons"):format(size[1], size[2]), function()
    local w, st, sm, mon, inv, tr = setup{ w = size[1], h = size[2], raw = true, cfg = { enrich = { ["minecraft:raw_iron"] = { out = DUST, made = 4, used = 3, drip = true } } } }
    st:run("storage"); sm:run("smelter"); w:run(10)
    local function has(a, b) return mon:find(a) or mon:find(b) end
    T.truthy(has("TRAIN", "Train")); tap(w, mon, has("TRAIN", "Train") and (mon:find("TRAIN") and "TRAIN" or "Train"))
    T.contains(mon, "TRAINING")
    tapLast(w, mon, "TRAIN")
    T.waitFor(w, function() return mon:text():find("Just learn it", 1, true) or mon:text():find("Learn", 1, true) end, 300, "never learned")
    T.truthy(mon:find("Save"), "Save is reachable:\n" .. mon:text())
    T.truthy(mon:find("Smelt all") or mon:find("All"), "the rule switch is reachable:\n" .. mon:text())
    T.running(sm)
  end)
end
