-- Storage: depot rules (#74/#77): matching, which depot wins, send-all on input, top-up of winners only.
local cc = require("sim.cc")
local T = require("sim.test")

local ENCH = { { name = "minecraft:mending", level = 1 } }
local function sword(tags) return { nbt = "s1", tags = { ["c:enchantables"] = true }, enchantments = tags and ENCH or nil } end

local function base(depots)
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 5 do
    inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:monitor("right", 57, 24)
  c:installRole("storage")
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1", depots = depots })
  return w, c, inv
end

local B = function(i) return "minecraft:barrel_" .. i end

T.test("storage rules: books go to the book depot, enchanted gear to the disenchanter, plain gear to neither", function()
  local w, c, inv = base{
    [B(3)] = { item = "minecraft:enchanted_book", priority = 0, added = 1 },
    [B(4)] = { tag = "c:enchantables", enchanted = true, priority = 0, added = 2 },
  }
  local book = { nbt = "b1", tags = { ["c:enchantables"] = true }, enchantments = ENCH }
  inv[0]:give("minecraft:enchanted_book", 5, nil, book)
  inv[0]:give("minecraft:diamond_sword", 1, nil, { nbt = "e", tags = { ["c:enchantables"] = true }, enchantments = ENCH })
  inv[0]:give("minecraft:iron_sword", 1, nil, { nbt = "p", tags = { ["c:enchantables"] = true } })
  inv[0]:give("minecraft:cobblestone", 30)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(10)
  T.eq(inv[3]:count("minecraft:enchanted_book"), 5, "books (Item beats Tag + Enchanted) go to the book depot")
  T.eq(inv[4]:count("minecraft:enchanted_book"), 0)
  T.eq(inv[4]:count("minecraft:diamond_sword"), 1, "enchanted sword goes to the disenchanter")
  T.eq(inv[4]:count("minecraft:iron_sword"), 0, "plain sword stays in storage")
  T.eq(inv[3]:count("minecraft:iron_sword"), 0)
  T.eq(inv[3]:count("minecraft:cobblestone") + inv[4]:count("minecraft:cobblestone"), 0)
  T.running(c)
end)

T.test("storage rules: a full winner keeps the item in storage, it never falls to the next depot", function()
  local w, c, inv = base{
    [B(3)] = { mod = "minecraft", priority = 5, added = 1 },
    [B(4)] = { mod = "minecraft", priority = 1, added = 2 },
  }
  for i = 1, 27 do inv[3]:give("minecraft:dirt", 64) end
  inv[0]:give("minecraft:cobblestone", 10)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(10)
  T.eq(inv[4]:count("minecraft:cobblestone"), 0, "must not go to the lower depot")
  T.eq(inv[3]:count("minecraft:cobblestone"), 0)
  inv[3]:extract(1, 64)                        -- room appears: it comes over from storage
  T.waitFor(w, function() return inv[3]:count("minecraft:cobblestone") == 10 end, 60, "never came over")
  T.running(c)
end)

T.test("storage rules: priority breaks a tie, then the depot added first", function()
  local w, c, inv = base{
    [B(3)] = { tag = "c:ores", priority = 1, added = 1 },
    [B(4)] = { tag = "c:ores", priority = 9, added = 2 },
    [B(5)] = { tag = "c:gems", priority = 0, added = 4 },
  }
  inv[0]:give("minecraft:iron_ore", 8, nil, { tags = { ["c:ores"] = true } })
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(5)
  T.eq(inv[4]:count("minecraft:iron_ore"), 8, "higher priority wins")
end)

T.test("storage rules: an old string depot still works and is upgraded to a rule", function()
  local w, c, inv = base{ [B(4)] = "minecraft:bucket", [B(5)] = "" }
  inv[0]:give("minecraft:bucket", 12)
  inv[0]:give("minecraft:cobblestone", 12)
  c:run("storage")
  T.waitFor(w, function() return inv[4]:count("minecraft:bucket") == 12 end, 60, "bucket depot not filled")
  T.eq(inv[4]:count("minecraft:cobblestone"), 0)
  T.eq(inv[5]:count("minecraft:cobblestone"), 0, "a depot with no rule yet gets nothing")
  T.running(c)
end)

T.test("storage rules: top-up pulls only what each depot wins", function()
  local w, c, inv = base{
    [B(3)] = { item = "minecraft:enchanted_book", priority = 0, added = 1 },
    [B(4)] = { tag = "c:enchantables", priority = 0, added = 2 },
  }
  inv[2]:give("minecraft:enchanted_book", 3, nil, { nbt = "b", tags = { ["c:enchantables"] = true } })
  inv[2]:give("minecraft:iron_sword", 1, nil, { nbt = "i", tags = { ["c:enchantables"] = true } })
  c:run("storage")
  T.waitFor(w, function() return inv[3]:count("minecraft:enchanted_book") == 3 end, 60, "books never moved")
  T.waitFor(w, function() return inv[4]:count("minecraft:iron_sword") == 1 end, 60, "sword never moved")
  T.eq(inv[4]:count("minecraft:enchanted_book"), 0, "the book belongs to the more specific depot")
  T.running(c)
end)

T.test("storage rules: engine counts what a rule would win and lists tags and mods", function()
  local cfg = { depots = { [B(3)] = { item = "minecraft:enchanted_book", priority = 0, added = 1 } } }
  local info = {
    ["minecraft:enchanted_book#b"] = { tags = { ["c:enchantables"] = true }, enchanted = true },
    ["minecraft:diamond_sword#e"] = { tags = { ["c:enchantables"] = true }, enchanted = true },
    ["minecraft:iron_sword#p"] = { tags = { ["c:enchantables"] = true }, enchanted = false },
    ["apotheosis:gem"] = { tags = {}, enchanted = false },
  }
  local items = {
    { key = "minecraft:enchanted_book#b", name = "minecraft:enchanted_book", count = 41, label = "Enchanted book" },
    { key = "minecraft:diamond_sword#e", name = "minecraft:diamond_sword", count = 2, label = "Diamond sword" },
    { key = "minecraft:iron_sword#p", name = "minecraft:iron_sword", count = 3, label = "Iron sword" },
    { key = "apotheosis:gem", name = "apotheosis:gem", count = 7, label = "Gem" },
  }
  local R = loadfile(cc.ROOT .. "/computer/storage/storage_rules.lua")()({
    cfg = function() return cfg end, info = info, items = function() return items end })
  local p = R.preview({ tag = "c:enchantables", enchanted = true }, B(4))
  T.eq(p.kinds, 1); T.eq(p.items, 2)
  T.eq(p.lost[B(3)], 1, "the book would go to the book depot")
  T.eq(R.preview({ mod = "apotheosis" }).items, 7)
  T.eq(R.preview({}).kinds, 0)
  local tags = R.tags()
  T.eq(tags[1].tag, "c:enchantables"); T.eq(tags[1].kinds, 3); T.eq(tags[1].items, 46)
  local mods = R.mods()
  T.eq(mods[1].mod, "minecraft"); T.eq(mods[1].items, 46); T.eq(mods[2].mod, "apotheosis")
  T.eq(R.describe({ tag = "c:enchantables", enchanted = true }), "Tag c:enchantables, enchanted")
  T.eq(R.winner("minecraft:iron_sword#p", "minecraft:iron_sword"), nil)
  cfg.depots = { [B(3)] = { tag = "c:enchantables", priority = 3, added = 2 }, [B(4)] = { tag = "c:enchantables", priority = 3, added = 1 } }
  T.eq(R.winner("minecraft:iron_sword#p", "minecraft:iron_sword"), B(4), "equal priority: the depot added first")
end)
