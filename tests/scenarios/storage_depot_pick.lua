-- Storage: the depot rule's Item pick list (#108): search narrows it, and a ticked item that storage has run out
-- of is still listed, so it can be found and unticked.
local cc = require("sim.cc")
local T = require("sim.test")

local function base(depot)
  local w = cc.world()
  w.ticks = true                                -- inventory calls cost a game tick and drop keys typed meanwhile, as in CC
  local net = w:net()
  local inv = {}
  for i = 0, 4 do
    inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:installRole("storage")
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1",
    depots = depot and { ["minecraft:barrel_4"] = depot } or nil })
  return w, c, inv
end

local function tap(w, c, text)
  local x, y = c.screen:find(text)
  assert(x, "no '" .. text .. "' on screen:\n" .. c.screen:text())
  c:click(x, y)
  w:run(1)
end

-- /assign > barrel_4 > Holds > Item
local function openItems(w, c)
  c:type("/assign"); c:key(257); w:run(2)
  tap(w, c, "barrel_4")
  tap(w, c, "barrel_4")
  local _, y = c.screen:find("Holds")
  c:click(12, y); w:run(1)
  c:click(14, select(2, c.screen:find("Item"))); w:run(1)
  T.contains(c.screen, "DEPOT ITEM")
end

local ITEMS = { "minecraft:cobblestone", "minecraft:iron_ingot", "minecraft:gold_ingot", "minecraft:oak_log",
  "minecraft:dirt", "minecraft:sand", "minecraft:gravel", "minecraft:stone", "minecraft:andesite", "minecraft:diorite",
  "minecraft:granite", "minecraft:bucket", "minecraft:coal", "minecraft:redstone", "minecraft:glass", "minecraft:string" }

T.test("storage depot pick: a ticked item storage has run out of is listed first and can be unticked; search finds it", function()
  local w, c, inv = base({ item = { "minecraft:copper_ingot" } })
  for _, n in ipairs(ITEMS) do inv[0]:give(n, 5) end
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(5)
  openItems(w, c)
  T.contains(c.screen, "[x] Copper ingot")
  c:type("copp"); w:run(1)
  T.contains(c.screen, "[x] Copper ingot")
  T.absent(c.screen, "Cobblestone")
  tap(w, c, "Copper ingot")
  T.contains(c.screen, "[ ] Copper ingot", "unticked, and still there to tick again")
  tap(w, c, "Done")
  T.absent(c.screen, "copper_ingot")
end)

T.test("storage depot pick: typing narrows the list after a tick and on the next page", function()
  local w, c, inv = base({ item = { "minecraft:cobblestone" } })
  for _, n in ipairs(ITEMS) do inv[0]:give(n, 5) end
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(5)
  openItems(w, c)
  tap(w, c, "Bucket")                          -- tick one first
  T.contains(c.screen, "[x] Bucket")
  c:type("redst"); w:run(1)
  T.contains(c.screen, "Redstone")
  T.absent(c.screen, "Bucket")
  c:key(259); c:key(259); c:key(259); c:key(259); c:key(259); w:run(1)  -- backspace
  c:type("string"); w:run(1)
  T.contains(c.screen, "String")
  T.absent(c.screen, "Redstone")
end)

T.test("storage depot pick: every key typed on the container pick and the item list reaches the search", function()
  local w, c, inv = base(nil)
  for _, n in ipairs(ITEMS) do inv[0]:give(n, 5) end
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(5)
  c:type("/assign"); c:key(257); w:run(2)
  tap(w, c, "+ Add")
  tap(w, c, " Depot ")
  c:type("barrel_4"); w:run(1)
  T.contains(c.screen, "> barrel_4")
  c:key(257); w:run(1)
  c:click(14, select(2, c.screen:find("Item"))); w:run(1)
  c:type("iron ingot"); w:run(1)
  T.contains(c.screen, "> iron ingot")
  T.contains(c.screen, "Iron Ingot")
  T.absent(c.screen, "Gold Ingot")
end)
