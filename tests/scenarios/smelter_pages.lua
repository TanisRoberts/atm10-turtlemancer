-- Every smelter page opens and draws without an error (a smoke test after the module split, #4).
local cc = require("sim.cc")
local T = require("sim.test")

local function tap(w, mon, label, optional)
  local x, y = mon:find(label)
  if not x and optional then return end
  T.truthy(x, "no '" .. label .. "' on screen:\n" .. mon:text())
  mon:touch(x, y)
  w:run(2)
end

for _, size in ipairs({ { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }) do
  T.test(("smelter pages: every page opens at %dx%d"):format(size[1], size[2]), function()
    local w = cc.world()
    local net = w:net()
    for i = 0, 2 do net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
    for i = 0, 2 do net:add("minecraft:furnace_" .. i, w:furnace()) end
    local st = w:computer{ id = 1, label = "Storage" }
    st:attach("back", cc.wired(net))
    st:installRole("storage")
    st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
    local sm = w:computer{ id = 2, label = "Smelter" }
    sm:attach("back", cc.wired(net))
    sm:installRole("smelter")
    sm:writeFile("smelt.txt", "iron all\n")
    local mon = sm:monitor("top", size[1], size[2])
    st:run("storage"); sm:run("smelter")
    w:run(10)
    for _, page in ipairs({ "Recipes", "Factories", "TRAIN" }) do
      tap(w, mon, page, size[1] < 39)       -- the narrowest footer has no room for every page
      T.running(sm)
      local x, y = mon:find("Back")
      if x then mon:touch(x, y); w:run(2) end
      T.running(sm)
    end
    tap(w, mon, "Pause"); T.running(sm)
    tap(w, mon, "Run"); T.running(sm)
  end)
end
