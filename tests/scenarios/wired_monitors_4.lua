-- Foreman (UI kit), MD Foreman (engine drawing), Nether Foreman and Farmhand pick their monitor off the cable with
-- shared/screens.lua (#101): with none touching, the cable monitor is numbered, a tap picks it and the controller
-- draws on it. `/monitors` asks again.
local cc = require("sim.cc")
local T  = require("sim.test")

local function pick(role, id, label, caption, wired)
  local w = cc.world()
  local net = w:net()
  local cable = net:monitor("monitor_3", 57, 24)
  local c = w:computer{ id = id, label = label }
  c:attach("top", cc.wireless{ ender = true })
  c:attach("back", cc.wired(net))
  c:installRole(role)
  c:run(role)
  w:run(4)
  T.eq(c.error, nil)
  T.contains(cable, "Tap to pick " .. caption)
  cable:touch(10, 10)
  w:run(10)
  T.eq(c.error, nil)
  T.absent(cable, "Tap to pick")
  T.eq(c:readFile("monitors.cfg"), "wall=monitor_3\n")
  -- the picked monitor is drawn on and taps on it reach the controller
  T.truthy(cable:line(1):find("%S"), "something is drawn on the cable monitor")
  c:type("/monitors"); c:key(257); w:run(3)
  T.falsy((c:readFile("monitors.cfg") or ""):find("monitor_3", 1, true), "the pick is forgotten")
end

T.test("foreman: no touching monitor, the cable one is picked", function() pick("foreman", 1, "Foreman", "the Foreman's screen") end)
T.test("md foreman: no touching monitor, the cable one is picked", function() pick("mdforeman", 2, "MD Foreman", "the MD Foreman's screen") end)
T.test("nether foreman: no touching monitor, the cable one is picked", function() pick("nether", 3, "Nether Foreman", "the Nether Foreman's screen") end)
T.test("farmhand: no touching monitor, the cable one is picked", function() pick("farmhand", 4, "Farmhand", "the Farmhand screen") end)

T.test("foreman: a touching monitor still wins with no prompt", function()
  local w = cc.world()
  local net = w:net()
  local cable = net:monitor("monitor_3", 57, 24)
  local c = w:computer{ id = 1, label = "Foreman" }
  c:attach("top", cc.wireless{ ender = true })
  c:attach("back", cc.wired(net))
  local mon = c:monitor("right", 57, 24)
  c:installRole("foreman")
  c:run("foreman")
  w:run(5)
  T.eq(c.error, nil)
  T.absent(cable, "Tap to pick")
  T.truthy(mon:line(1):find("%S"), "drawn on the touching monitor")
  T.falsy(c:readFile("monitors.cfg"), "nothing saved")
end)
