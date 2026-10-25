-- Storage: /assign pages for a depot's rule (#78): the rule form, pick list, "Something like this",
-- priority, editing and removing a rule depot. The engine itself is in storage_rules.lua.
local cc = require("sim.cc")
local T = require("sim.test")

local ENCH = { { name = "minecraft:mending", level = 1 } }
local B = function(i) return "minecraft:barrel_" .. i end

local function base(depots, prep)
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 5 do
    inv[i] = net:add(B(i), cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:monitor("right", 57, 24)
  c:installRole("storage")
  c:writeTable("storage.cfg", { inputs = { B(0) }, output = B(1), depots = depots })
  inv[0]:give("minecraft:diamond_sword", 1, nil, { nbt = "e", tags = { ["c:enchantables"] = true }, enchantments = ENCH })
  inv[0]:give("minecraft:iron_sword", 1, nil, { nbt = "p", tags = { ["c:enchantables"] = true } })
  inv[0]:give("minecraft:enchanted_book", 5, nil, { nbt = "b", tags = { ["c:enchantables"] = true }, enchantments = ENCH })
  inv[0]:give("minecraft:cobblestone", 30)
  if prep then prep(inv) end
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(5)
  return w, c, inv
end

local function tap(w, c, text)
  local x, y = c.screen:find(text)
  assert(x, "no '" .. text .. "' on screen:\n" .. c.screen:text())
  c:click(x, y)
  w:run(1)
end

local function addDepot(w, c, container)
  c:type("/assign"); c:key(257)
  w:run(2)
  tap(w, c, "+ Add")
  c:click(3, 5); w:run(1)                       -- the Depot button
  c:type(container); w:run(1)
  c:key(257); w:run(1)
  T.contains(c.screen, "step 2 of 3")
end

T.test("storage: /assign rule form: Tag + Enchanted + priority, live preview, Save, then only enchanted gear comes over", function()
  local w, c, inv = base{}
  addDepot(w, c, "barrel_4")
  c:click(14, 5); w:run(1)                      -- Tag
  T.contains(c.screen, "c:enchantables")
  T.contains(c.screen, "DEPOT TAG")
  c:type("ench"); w:run(1)
  c:key(257); w:run(1)                          -- ticks the only match
  tap(w, c, "Done")
  T.contains(c.screen, "c:enchantables")
  T.contains(c.screen, "Matches now: 3 kinds")
  tap(w, c, "Yes")
  T.contains(c.screen, "Matches now: 2 kinds")
  T.contains(c.screen, "Diamond Sword")
  T.absent(c.screen, "Iron Sword")
  tap(w, c, "Next")
  T.contains(c.screen, "step 3 of 3")
  T.contains(c.screen, "Tag c:enchantables, enchanted")
  local _, y = c.screen:find("Priority")
  c:click(13, y); w:run(1)
  c:type("x7a"); w:run(1)                       -- digits only
  tap(w, c, " Save ")
  T.contains(c.screen, "Saved")
  local d = c:readTable("storage.cfg").depots[B(4)]
  T.eq(d.tag[1], "c:enchantables"); T.eq(d.enchanted, true); T.eq(d.priority, 7); T.eq(d.item, nil)
  tap(w, c, "Done")
  T.waitFor(w, function() return inv[4]:count("minecraft:diamond_sword") == 1 end, 60, "depot never filled")
  w:run(10)
  T.eq(inv[4]:count("minecraft:iron_sword"), 0, "plain sword stays in storage")
  T.eq(inv[4]:count("minecraft:cobblestone"), 0)
  T.running(c)
end)

T.test("storage: /assign rule form: Next stays off until a condition is set; Any clears one", function()
  local w, c, inv = base{}
  addDepot(w, c, "barrel_4")
  c:click(4, 5)                                 -- nowhere near a button on the Next row yet
  tap(w, c, "Yes")
  tap(w, c, "Any")                              -- the Enchanted Any button (first one on the screen)
  T.contains(c.screen, "Set at least one")
  local nx = c.screen:find("Next")
  c:click(nx, select(2, c.screen:find("Next"))); w:run(1)
  T.contains(c.screen, "step 2 of 3", "a disabled Next does nothing")
  c:click(14, 6); w:run(1)                      -- Mod
  T.contains(c.screen, "minecraft")
  c:type("minec"); w:run(1)
  c:key(257); w:run(1)                          -- ticks the only match
  tap(w, c, "Done")
  T.contains(c.screen, "Matches now")
  c:click(14, 6); w:run(1)
  tap(w, c, "Any")                              -- clears the Mod again
  T.contains(c.screen, "Set at least one")
end)

T.test("storage: /assign shows, edits and removes an existing rule depot", function()
  local w, c, inv = base{ [B(4)] = { tag = "c:enchantables", enchanted = true, priority = 3, added = 1 } }
  c:type("/assign"); c:key(257)
  w:run(2)
  tap(w, c, "DEPOT ")
  T.contains(c.screen, "Holds"); T.contains(c.screen, "Tag c:enchantables, enchanted")
  T.contains(c.screen, "Matches")
  tap(w, c, "Tag c:enchantables")                -- Holds opens the form
  T.contains(c.screen, "DEPOT RULE")
  tap(w, c, "No")
  T.contains(c.screen, "Matches now: 1 kind")
  tap(w, c, "Next")
  T.contains(c.screen, "not enchanted")
  tap(w, c, " Save ")
  T.contains(c.screen, "Saved")
  local d = c:readTable("storage.cfg").depots[B(4)]
  T.eq(d.enchanted, false); T.eq(d.priority, 3, "priority kept"); T.eq(d.added, 1, "added kept")
  tap(w, c, "DEPOT ")
  local dx, dy = c.screen:find("Cancel   Delete")   -- the Delete button, not the words in the hint line
  c:click(dx + 10, dy); w:run(1)
  tap(w, c, "Sure? Delete")
  T.eq(c:readTable("storage.cfg").depots[B(4)], nil)
  T.running(c)
end)

T.test("storage: /assign rule overlaps are named on the summary", function()
  local w, c, inv = base({ [B(3)] = { tag = "c:enchantables", enchanted = true, priority = 0, added = 1 } },
    function(inv) for _ = 1, 27 do inv[3]:give("minecraft:dirt", 64) end end)   -- full: the winner keeps nothing new
  addDepot(w, c, "barrel_4")
  c:click(14, 5); w:run(1)
  c:type("ench"); w:run(1)
  c:key(257); w:run(1)
  tap(w, c, "Done")
  tap(w, c, "Next")
  T.contains(c.screen, "Overlaps")
  T.contains(c.screen, "barrel_3 wins 2 kinds")
end)

T.test("storage: /assign Something like this: drop one example in, tick lines, Use these fills the form", function()
  local w, c, inv = base{}
  addDepot(w, c, "barrel_4")
  tap(w, c, "Something like this")
  T.contains(c.screen, "Drop ONE item")
  inv[4]:give("minecraft:diamond_sword", 1, nil, { nbt = "e", tags = { ["c:enchantables"] = true }, enchantments = ENCH })
  w:run(4)
  T.contains(c.screen, "SOMETHING LIKE THIS")
  T.contains(c.screen, "Diamond Sword")
  T.contains(c.screen, "c:enchantables")
  c:click(3, 6); w:run(1)                       -- tick Enchanted
  c:click(3, 7); w:run(1)                       -- tick the tag
  tap(w, c, "Use these")
  T.contains(c.screen, "minecraft:diamond_sword")
  T.contains(c.screen, "c:enchantables")
  tap(w, c, "Next")
  tap(w, c, " Save ")
  local d = c:readTable("storage.cfg").depots[B(4)]
  T.eq(d.item[1], "minecraft:diamond_sword"); T.eq(d.tag[1], "c:enchantables"); T.eq(d.enchanted, true)
  T.truthy(inv[4]:count("minecraft:diamond_sword") >= 1, "the example stays in the depot")
  T.running(c)
end)

T.test("storage: /assign Something like this ignores other inventories gaining items", function()
  local w, c, inv = base{}
  addDepot(w, c, "barrel_4")
  tap(w, c, "Something like this")
  T.contains(c.screen, "Drop ONE item")
  inv[3]:give("minecraft:cobblestone", 1)       -- a hopper fills some other barrel first
  w:run(2)
  T.contains(c.screen, "Drop ONE item")
  inv[4]:give("minecraft:diamond_sword", 1, nil, { nbt = "e", tags = { ["c:enchantables"] = true }, enchantments = ENCH })
  w:run(4)
  T.contains(c.screen, "SOMETHING LIKE THIS")
  T.contains(c.screen, "Diamond Sword")
end)

T.test("storage: /assign pick list ticks several values, Done returns to the form showing them", function()
  local w, c, inv = base{}
  addDepot(w, c, "barrel_4")
  c:click(14, 6); w:run(1)                      -- Mod
  T.contains(c.screen, "DEPOT MOD")
  c:type("minec"); w:run(1)
  c:key(257); w:run(1)                          -- ticks minecraft
  T.contains(c.screen, "1 ticked")
  tap(w, c, "Done")
  T.contains(c.screen, "minecraft")
  T.contains(c.screen, "Matches now")
  c:click(14, 6); w:run(1)
  tap(w, c, "minecraft")                        -- untick
  T.contains(c.screen, "tap to tick")
  tap(w, c, "minecraft")                        -- tick again
  tap(w, c, "Done")
  tap(w, c, "Next")
  T.contains(c.screen, "Mod minecraft")
  tap(w, c, " Save ")
  local d = c:readTable("storage.cfg").depots[B(4)]
  T.eq(d.mod[1], "minecraft"); T.eq(#d.mod, 1)
end)

T.test("storage: /assign Item pick list ticks two items; the form row lists them and the summary joins with or", function()
  local w, c, inv = base{}
  addDepot(w, c, "barrel_4")
  c:click(14, 4); w:run(1)                      -- Item
  tap(w, c, "Iron Sword")
  tap(w, c, "Cobblestone")
  T.contains(c.screen, "2 ticked")
  tap(w, c, "Done")
  T.contains(c.screen, "minecraft:iron_sword, +1")   -- the two names do not fit the row
  T.contains(c.screen, "Matches now: 2 kinds")
  tap(w, c, "Next")
  T.contains(c.screen, "Item minecraft:iron_sword or ")
end)
