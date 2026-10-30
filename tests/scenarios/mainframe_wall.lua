-- The mainframe's monitor wall on the UI kit (#28): the real mainframe.lua with stand-in machines on the radio,
-- at 57x24, 57x38, 36x24 and 164x81. Rows, colours, the visitor column, grey rows after 30 s, the board paging.
local cc = require("sim.cc")
local T  = require("sim.test")

local function envDetector() return { types = { "environment_detector" }, peripheralMethods = {} } end

-- Stand-ins: Storage, Smelter, the neural lab and two Canaries talk to the mainframe; Canary-07 goes quiet after `quiet`.
local STAND = [[
  rednet.open("top")
  local t0 = os.clock()
  while true do
    rednet.broadcast({ type = "storage", used = 790, total = 1000, kinds = 120 }, "tanis-base")
    rednet.broadcast({ type = "smelter", state = "ok", note = "6 cooking" }, "tanis-base")
    rednet.broadcast({ type = "neural", state = "running", note = "6 columns", power = 80 }, "tanis-base")
    sleep(2)
  end
]]
local CANARY = [[
  rednet.open("top")
  local id, quiet = os.getComputerID(), %s
  while true do
    if not quiet or os.clock() < quiet then
      rednet.broadcast({ type = "status", id = id, num = %d, label = "%s", state = "%s", y = -40, fuel = 900, slots = 3 }, "tanis-miner")
    end
    sleep(2)
  end
]]

local VISITORS = { rows = { { name = "Alex", when = "here", tone = "good", here = true },
                            { name = "Steve", when = "2h ago", tone = "dim" } },
                   detector = true, foot = { text = "You're home", tone = "good" } }

-- opts: w, h, canaries (extra Canary stand-ins), visitors
local function build(opts)
  opts = opts or {}
  local world = cc.world()
  local mf = world:computer{ id = 1, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  mf:attach("right", envDetector())
  local mon = mf:monitor("bottom", opts.w or 57, opts.h or 24)
  mf:installRole("mainframe")
  mf.files["butler.lua"] = nil                 -- no Inventory Manager here: the visitor column is fed by the test
  mf:run("mainframe")
  local st = world:computer{ id = 7, label = "Storage" }
  st:attach("top", cc.wireless{ ender = true })
  st:writeFile("st.lua", STAND); st:run("st")
  local function canary(id, num, label, state, quiet)
    local c = world:computer{ id = id, label = label }
    c:attach("top", cc.wireless{ ender = true })
    c:writeFile("c.lua", CANARY:format(quiet and tostring(quiet) or "nil", num, label, state)); c:run("c")
  end
  canary(21, 4, "Canary-04", "working")
  canary(22, 7, "Canary-07", "waiting", opts.quiet)
  for i = 1, (opts.canaries or 0) do canary(30 + i, 10 + i, ("Canary-%02d"):format(10 + i), "working") end
  if opts.visitors ~= false then
    world:at(3, function() mf.env._G.WALL_VISITORS = VISITORS end)
  end
  return world, mf, mon
end

local function rowOf(mon, label)
  local _, y = mon:find(label)
  T.truthy(y, "no '" .. label .. "' on screen:\n" .. mon:text())
  return mon:line(y), y
end

T.test("mainframe wall 57x24: strip, board rows and the visitor column", function()
  local world, mf, mon = build()
  world:run(20)
  T.eq(mf.error, nil)
  T.truthy(mon:find("ISLAND"), mon:text())
  T.truthy(mon:find("Moon "), mon:text())
  T.truthy(mon:find("All clear"), mon:text())
  T.truthy(mon:find("MACHINES"), mon:text())
  T.truthy(mon:find("VISITORS"), mon:text())
  local r = rowOf(mon, "Storage")
  T.truthy(r:find("ok", 1, true) and r:find("79% ful", 1, true), r)
  r = rowOf(mon, "Canary-04")
  T.truthy(r:find("working", 1, true) and r:find("Y -40", 1, true), r)
  local x, y = mon:find("Alex")
  T.truthy(x and x > 35, mon:text())
  T.truthy(mon:line(y):find("here", 1, true), mon:line(y))
  T.truthy(mon:find("You're home"), mon:text())
  -- the board sits under the strip: the header is on row 5
  T.truthy(mon:line(5):find("MACHINES", 1, true), mon:line(5))
end)

T.test("mainframe wall: a row not heard from for 30 s goes grey with a still ?", function()
  local world, mf, mon = build{ quiet = 6 }
  world:run(15)
  local x, y = mon:find("Canary-07")
  local live = mon:colourAt(x, y)
  world:run(45)
  T.eq(mf.error, nil)
  x, y = mon:find("Canary-07")
  T.truthy(x, mon:text())
  T.truthy(mon:colourAt(x, y) ~= live, "name did not change colour")
  T.truthy(mon:line(y):find("?", 1, true), mon:line(y))
  local x4, y4 = mon:find("Canary-04")
  T.eq(mon:colourAt(x4, y4), live)
end)

T.test("mainframe wall 36x24: no visitor column, board uses the width", function()
  local world, mf, mon = build{ w = 36 }
  world:run(20)
  T.eq(mf.error, nil)
  T.truthy(mon:find("MACHINES"), mon:text())
  T.falsy(mon:find("VISITORS"), mon:text())
  T.falsy(mon:find("You're home"), mon:text())
  T.truthy(mon:find("Canary-04"), mon:text())
end)

T.test("mainframe wall 57x38: more rows, nothing paged", function()
  local world, mf, mon = build{ h = 38, canaries = 4 }
  world:run(20)
  T.eq(mf.error, nil)
  for _, n in ipairs({ "Canary-04", "Canary-07", "Canary-11", "Canary-14" }) do T.truthy(mon:find(n), mon:text()) end
  T.falsy(mon:line(38):find("o .", 1, true), mon:line(38))
end)

T.test("mainframe wall: rows that do not fit page every 8 s", function()
  local world, mf, mon = build{ canaries = 18 }
  world:run(20)
  T.eq(mf.error, nil)
  local first = mon:text()
  T.truthy(mon:line(24):find("[o%.] [o%.]"), mon:line(24))
  T.truthy(mon:find("Canary-04"), first)
  world:run(8)
  T.truthy(mon:find("Canary-29") or mon:find("Canary-27"), mon:text())
  T.falsy(mon:find("Canary-04"), mon:text())
end)

T.test("mainframe wall 164x81: station, grouped board and visitors in three columns", function()
  local world, mf, mon = build{ w = 164, h = 81 }
  world:run(20)
  T.eq(mf.error, nil)
  T.truthy(mon:find("ISLAND STATION"), mon:text())
  T.truthy(mon:find("NEARBY"), mon:text())
  for _, g in ipairs({ "STORAGE", "MINING", "LABS" }) do T.truthy(mon:find(g), g .. "\n" .. mon:text()) end
  local _, ym = mon:find("MINING")
  local _, yc = mon:find("Canary-04")
  T.truthy(yc > ym, "Canary under MINING")
  local xv = mon:find("VISITORS")
  T.truthy(xv and xv > 120, mon:text())
end)
