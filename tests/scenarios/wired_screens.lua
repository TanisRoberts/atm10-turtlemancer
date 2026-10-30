-- Storage, smelter and operator pick their monitor with shared/screens.lua (#100): a touching monitor wins as before
-- (the existing scenarios); with none touching, the monitor on the cable is numbered, a tap picks, a reboot remembers.
local cc = require("sim.cc")
local T  = require("sim.test")

local B = function(i) return "minecraft:barrel_" .. i end
local function barrels(net, n)
  local inv = {}
  for i = 0, n do inv[i] = net:add(B(i), cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
  return inv
end

-- Boot, see the number, tap it, see the screen drawn there, reboot and see it come straight back.
local function pickAndReboot(w, c, mon, role, cfgLine, shows)
  w:run(3)
  T.contains(mon, "Tap to pick")
  T.contains(c.screen, "1 monitor_12")
  mon:touch(10, 10)
  w:run(20)
  T.eq(c.error, nil)
  T.contains(mon, shows)
  T.absent(mon, "Tap to pick")
  T.eq(c:readFile("monitors.cfg"), cfgLine)
  c:reboot(); c:run(role)
  w:run(20)
  T.eq(c.error, nil)
  T.absent(c.screen, "Pick")
  T.contains(mon, shows)
end

T.test("storage: no touching monitor, the one on the cable is numbered, a tap picks, it survives a reboot", function()
  local w = cc.world(); local net = w:net()
  local mon = net:monitor("monitor_12", 57, 24)
  local inv = barrels(net, 4)
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net)); c:attach("top", cc.wireless{ ender = true })
  c:installRole("storage")
  c:writeTable("storage.cfg", { inputs = { B(0) }, output = B(1) })
  inv[0]:give("minecraft:iron_ingot", 64)
  c:run("storage")
  pickAndReboot(w, c, mon, "storage", "screen=monitor_12\n", "Iron Ingot")
  local x, y = mon:find("Iron Ingot")
  T.truthy(x, "iron is listed")
  mon:touch(x, y); w:run(2)                                 -- a tap on the wired monitor reaches the controller
  T.truthy(inv[1]:count("minecraft:iron_ingot") > 0, "a tap on the wired monitor sent iron to the output")
end)

T.test("smelter: no touching monitor, the one on the cable is numbered, a tap picks, it survives a reboot", function()
  local w = cc.world(); local net = w:net()
  local mon = net:monitor("monitor_12", 57, 24)
  barrels(net, 3)
  for i = 0, 2 do net:add("minecraft:furnace_" .. i, w:furnace()) end
  local c = w:computer{ id = 2, label = "Smelter" }
  c:attach("back", cc.wired(net)); c:installRole("smelter")
  c:writeFile("smelt.txt", "iron all\n")
  c:run("smelter")
  pickAndReboot(w, c, mon, "smelter", "screen=monitor_12\n", "SMELTER")
end)

T.test("operator: no touching monitor, the one on the cable is numbered, a tap picks, it survives a reboot", function()
  local w = cc.world(); local net = w:net()
  local mon = net:monitor("monitor_12", 57, 24)
  local c = w:computer{ id = 5, label = "Operator" }
  c:attach("back", cc.wired(net)); c:attach("top", cc.wireless{ ender = true })
  c:installRole("operator")
  c:run("operator")
  pickAndReboot(w, c, mon, "operator", "screen=monitor_12\n", "OPERATOR")
end)
