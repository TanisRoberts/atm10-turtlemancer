-- The Architect's monitor shows just the map, following Weaver, with a progress line on top.
local cc = require("sim.cc")
local T  = require("sim.test")

local function setup(mw, mh)
  local w = cc.world()
  local a = w:computer{ id = 1, label = "Architect" }
  a:attach("top", cc.wireless{ ender = true })
  local mon = mw and a:monitor("right", mw, mh)
  local s = w:computer{ id = 2, label = "Weaver" }
  s:attach("top", cc.wireless{ ender = true })
  a:installRole("architect")
  s:install("tests/demo/weaver_stub.lua", "weaver_stub.lua")
  s:run("weaver_stub")
  a:run("architect")
  w:run(15)
  return w, a, s, mon
end

T.test("architect: a 2x2 monitor shows the map and the build progress, the terminal keeps its Status tab", function()
  local w, a, s, mon = setup(36, 24)
  T.contains(mon, "Weaver-01 building")
  T.contains(mon, "25%")                       -- 30 of 120 placed
  T.contains(mon, "Weaver Y 70")               -- the map's labels
  T.contains(a.screen, "Plan")                 -- the computer itself is still on the Status tab
  assert(not mon:text():find("Plan", 1, true), "the monitor is the map only")
  -- some map pixels are drawn (the slab), not just blank
  local drawn = 0
  for y = 2, 23 do for x = 1, 36 do local ch = mon:line(y):sub(x, x); if ch ~= " " then drawn = drawn + 1 end end end
  assert(drawn > 20, "map drawn on the monitor")
end)

T.test("architect: the monitor follows Weaver to the next layer, whatever tab the terminal is on", function()
  local w, a, s, mon = setup(36, 24)
  a:type("log"); a:key(257); w:run(2)
  s.G.STATUS.layer = 2; s.G.STATUS.placed = 90
  w:run(8)
  T.contains(mon, "75%")
  T.contains(mon, "Y 64")                      -- layer 2 is sea 62 + ybase 1 + 2 - 1
end)

T.test("architect: no monitor is fine, and one plugged in later gets drawn", function()
  local w, a = setup()
  T.contains(a.screen, "Plan")
  local mon = a:monitor("right", 36, 24)
  a:queue("peripheral", "right")
  w:run(5)
  T.contains(mon, "Weaver-01 building")
end)
