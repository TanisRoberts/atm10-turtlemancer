-- The Architect's monitor shows just the map, following Weaver, with a progress line on top (Architect v2).
local cc = require("sim.cc")
local T  = require("sim.test")
local A  = require("sim.architect")

local function setup(mw, mh)
  local w = cc.world()
  local a = w:computer{ id = 1 }
  a:attach("top", cc.wireless{ ender = true })
  local mon = mw and a:monitor("right", mw, mh)
  local s = w:computer{ id = 2, label = "Weaver-01" }
  s:attach("top", cc.wireless{ ender = true })
  a:installRole("architect")
  local hash = A.prepare(a)
  s:install("tests/demo/weaver_stub.lua", "weaver_stub.lua")
  s:writeFile("hash.txt", hash)
  s:run("weaver_stub")
  w:run(0.5)
  s.G.STATUS = { state = "building", msg = "", n = 1, label = "Weaver-01", layer = 1, total = 3, idx = 31, cells = 120, work = "layer",
                 x = 5, y = 1, z = 2, fuel = 12000, gaps = 0, hash = hash }
  a:run("architect")
  w:run(15)
  return w, a, s, mon
end

T.test("architect: a 2x2 monitor shows the map and the build progress, the terminal keeps its Status tab", function()
  local w, a, s, mon = setup(36, 24)
  T.contains(mon, "Weaver-01 building")
  T.contains(mon, "Layer 1/3")                 -- the map's caption
  T.contains(a.screen, "Placement Test")       -- the computer itself is still on the Status tab
  assert(not mon:text():find("Placement Test", 1, true), "the monitor is the map only")
  local drawn = 0
  for y = 2, 23 do
    for x = 1, 36 do
      local fg, bg = mon:colourAt(x, y)
      if bg ~= 32768 then drawn = drawn + 1 end
    end
  end
  assert(drawn > 20, "map drawn on the monitor")
end)

T.test("architect: the monitor follows Weaver to the next layer, whatever tab the terminal is on", function()
  local w, a, s, mon = setup(36, 24)
  a:type("log"); a:key(257); w:run(2)
  s.G.STATUS.layer = 2; s.G.STATUS.idx = 10
  w:run(8)
  T.contains(mon, "Layer 2/3")
  T.contains(mon, "Y 66")                      -- layer 2 is the second row of blocks above the corner's Y 65
end)

T.test("architect: no monitor is fine, and one plugged in later gets drawn", function()
  local w, a = setup()
  T.contains(a.screen, "Placement Test")
  local mon = a:monitor("right", 36, 24)
  a:queue("peripheral", "right")
  w:run(5)
  T.contains(mon, "Weaver-01 building")
end)
