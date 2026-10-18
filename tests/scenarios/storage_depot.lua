-- Storage: a Depot (/assign > + Add > Depot > container > item > summary) is kept full of one item.
local cc = require("sim.cc")
local T = require("sim.test")

local function base()
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 4 do
    inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:monitor("right", 57, 24)
  c:installRole("storage")
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  return w, c, inv
end

local function tap(w, c, text)
  local x, y = c.screen:find(text)
  assert(x, "no '" .. text .. "' on screen:\n" .. c.screen:text())
  c:click(x, y)
  w:run(1)
end

T.test("storage: /assign > Add > Depot > container > item > summary > Save, then it is topped up", function()
  local w, c, inv = base()
  inv[0]:give("minecraft:bucket", 40)
  inv[0]:give("minecraft:cobblestone", 20)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  w:run(5)
  c:type("/assign"); c:key(257)
  w:run(2)
  tap(w, c, "+ Add")
  T.contains(c.screen, "what kind")
  c:click(3, 5); w:run(1)                       -- the Depot button (first of the kinds)
  T.contains(c.screen, "step 1 of 3")
  c:type("barrel_4"); w:run(1)
  c:key(257); w:run(1)                          -- the only match
  T.contains(c.screen, "step 2 of 3")
  T.contains(c.screen, "Bucket"); T.contains(c.screen, "Cobblestone")
  c:type("buck"); w:run(1)
  T.absent(c.screen, "Cobblestone")
  c:key(257); w:run(1)
  T.contains(c.screen, "step 3 of 3")
  T.contains(c.screen, "Keeps Bucket")
  c:click(3, select(2, c.screen:find("Cancel"))); w:run(2)   -- the Save button, left of Cancel
  T.contains(c.screen, "Saved")
  local cfg = c:readTable("storage.cfg")
  T.eq(cfg.depots["minecraft:barrel_4"], "minecraft:bucket")
  c:click(12, select(2, c.screen:find("Done"))); w:run(1)
  T.waitFor(w, function() return inv[4]:count("minecraft:bucket") == 40 end, 60, "depot never filled")
  T.eq(inv[4]:count("minecraft:cobblestone"), 0)
end)

T.test("storage: a depot is not storage and keeps filling when stock arrives later", function()
  local w, c, inv = base()
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1",
    depots = { ["minecraft:barrel_4"] = "minecraft:bucket" } })
  inv[0]:give("minecraft:bucket", 30)
  inv[0]:give("minecraft:iron_ingot", 64)
  c:run("storage")
  T.waitFor(w, function() return inv[4]:count("minecraft:bucket") == 30 end, 60, "depot never filled")
  T.eq(inv[4]:count("minecraft:iron_ingot"), 0, "other items must not land in the depot")
  inv[0]:give("minecraft:bucket", 5)
  T.waitFor(w, function() return inv[4]:count("minecraft:bucket") == 35 end, 60, "late stock never topped up")
  inv[4]:extract(1, 10)
  inv[0]:give("minecraft:bucket", 10)
  T.waitFor(w, function() return inv[4]:count("minecraft:bucket") == 35 end, 60, "refill after use")
  T.running(c)
end)

T.test("storage: /assign > Add > Fluid depot > tank > fluid > summary > Save, then the tank is filled from another tank", function()
  local w, c, inv = base()
  local net = inv[0].net
  local source = net:add("pneumaticcraft:small_tank_0", cc.Inv.Tank.new{ capacity = 16000, fluid = "minecraft:lava", amount = 9000 })
  local depot = net:add("pneumaticcraft:small_tank_1", cc.Inv.Tank.new{ capacity = 4000 })
  c:run("storage")
  w:run(5)
  c:type("/assign"); c:key(257)
  w:run(2)
  tap(w, c, "+ Add")
  T.contains(c.screen, "Fluid depot")
  c:click(3, 8); w:run(1)                       -- the Fluid depot button
  T.contains(c.screen, "ADD FLUID DEPOT"); T.contains(c.screen, "step 1 of 3")
  T.contains(c.screen, "small_tank_1"); T.contains(c.screen, "small_tank_0")
  T.absent(c.screen, "barrel_2", "barrels are not tanks")
  c:type("tank_1"); w:run(1)
  c:key(257); w:run(1)
  T.contains(c.screen, "step 2 of 3")
  T.contains(c.screen, "Lava")
  c:type("lava"); w:run(1)
  c:key(257); w:run(1)
  T.contains(c.screen, "step 3 of 3")
  T.contains(c.screen, "Keeps Lava")
  T.absent(c.screen, "Input", "a tank offers no item jobs")
  c:click(3, select(2, c.screen:find("Cancel"))); w:run(2)
  T.contains(c.screen, "Saved")
  T.eq(c:readTable("storage.cfg").fluidDepots["pneumaticcraft:small_tank_1"], "minecraft:lava")
  c:click(12, select(2, c.screen:find("Done"))); w:run(1)
  T.waitFor(w, function() return depot.amount == 4000 end, 60, "tank never filled")
  T.eq(source.amount, 5000)
  depot.amount = 1000                           -- the machine used some
  T.waitFor(w, function() return depot.amount == 4000 end, 60, "tank never topped up")
  T.running(c)
end)

T.test("storage: a tank is never touched when it is not a fluid depot or the fluid is not there", function()
  local w, c, inv = base()
  local net = inv[0].net
  local a = net:add("pneumaticcraft:small_tank_0", cc.Inv.Tank.new{ fluid = "minecraft:water", amount = 5000 })
  local depot = net:add("pneumaticcraft:small_tank_1", cc.Inv.Tank.new{ capacity = 4000 })
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1",
    fluidDepots = { ["pneumaticcraft:small_tank_1"] = "minecraft:lava" } })
  c:run("storage")
  w:run(30)
  T.eq(a.amount, 5000); T.eq(depot.amount, 0)
  a.fluid, a.amount = "minecraft:lava", 3000    -- lava turns up
  T.waitFor(w, function() return depot.amount == 3000 end, 60, "lava never moved")
  T.running(c)
end)

T.test("storage: a tank that also has item slots (PneumaticCraft bucket slots) is still a tank, not storage", function()
  local w, c, inv = base()
  local net = inv[0].net
  net:add("pneumaticcraft:small_tank_0", cc.Inv.Tank.new{ capacity = 16000, fluid = "minecraft:lava", amount = 9000 })
  local depot = net:add("pneumaticcraft:small_tank_1", cc.Inv.Tank.new{ capacity = 4000,
    types = { "pneumaticcraft:small_tank", "fluid_storage", "inventory" } })
  depot.peripheralMethods = { "tanks", "pushFluid", "pullFluid", "size", "list" }
  function depot:size() return 2 end
  function depot:list() return {} end
  inv[0]:give("minecraft:iron_ingot", 10)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60)
  c:type("/assign"); c:key(257)
  w:run(2)
  tap(w, c, "+ Add")
  c:click(3, 8); w:run(1)
  T.contains(c.screen, "small_tank_1")
  local text = c.screen:text()
  local _, count = text:gsub("small_tank_1", "")
  T.eq(count, 1, "listed once")
  T.running(c)
end)
