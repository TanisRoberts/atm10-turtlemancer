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
  canary(22, 7, "Canary-07", opts.calm and "working" or "waiting", opts.quiet)
  for i = 1, (opts.canaries or 0) do canary(30 + i, 10 + i, ("Canary-%02d"):format(10 + i), "working") end
  if opts.visitors ~= false then
    world:at(3, function() mf.G.WALL_VISITORS = VISITORS end)
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

T.test("mainframe wall: SCALE=0.5 in wall.env keeps the smallest text", function()
  local world = cc.world()
  local mf = world:computer{ id = 1, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  mf:attach("right", envDetector())
  local mon = mf:monitor("bottom", 57, 24)
  mf:installRole("mainframe")
  mf.files["butler.lua"] = nil
  mf:writeFile("wall.env", "SCALE=0.5\n")
  mf:run("mainframe")
  world:run(10)
  T.eq(mf.error, nil)
  T.eq(mon:getTextScale(), 0.5)
  T.truthy(mon:line(5):find("MACHINES", 1, true), mon:text())
end)

-- 82x40 (an 8x6 wall at scale 1): the floor-readable wall
-- The Operator's record goes straight into the mainframe's globals, as operator_link would hand it.
local function setPower(mf, pw)
  mf.G.OPERATOR = { label = "Operator", plant = { fe = 1000, buf = 0.41 }, units = {}, power = pw }
  mf.G.OPERATOR_SEEN = mf.G.os.clock()
end

local function bgAt(mon, x, y) local _, b = mon:colourAt(x, y); return b end
local COL = require("sim.env").colors

T.test("mainframe wall 82x40: board half, dots, glance half, wall.env", function()
  local world, mf, mon = build{ w = 82, h = 40, canaries = 12 }
  world:run(20)
  T.eq(mf.error, nil)
  local env = mf:readFile("wall.env")
  T.truthy(env and env:find("SCALE=1", 1, true) and env:find("PAGE_S=3", 1, true), env)
  T.eq(mon:getTextScale(), 1)
  T.eq(mf.bootAt, 0)
  T.truthy(mon:line(1):find("MACHINES", 1, true) and mon:line(1):find("VISITORS", 1, true), mon:line(1))
  T.eq(mon:line(1):sub(62, 62), " ", "divider")
  -- two-row entries: name and state on one row, detail under it, fixed slots
  local r, y = rowOf(mon, "Storage")
  T.truthy(r:find("ok", 1, true), r)
  T.truthy(mon:line(y + 1):find("79% full", 1, true), mon:line(y + 1))
  T.eq(y, 2, "first slot on row 2")
  -- 16 machines on 9 slots: two pages, dots on row 20
  T.truthy(mon:line(20):find("[o%.] [o%.]"), mon:line(20))
  T.truthy(mon:find("Alex"), mon:text())
  T.truthy(mon:line(20):find("You're home", 1, true), mon:line(20))
  local first = mon:text()
  world:run(3)
  T.truthy(mon:text() ~= first, "the page turned after 3 s")
  T.falsy(mon:find("Storage"), "storage was on page 1 only")
  -- rows 21 rule, 23 chip and header, 34 Needs you, 40 island line
  T.truthy(mon:line(21):find("^%-*$") or mon:line(21):find("\140", 1, true), mon:line(21))
  T.truthy(mon:line(23):find("ISLAND", 1, true) and mon:line(23):find("POWER USE", 1, true), mon:line(23))
  T.truthy(mon:line(34):find("NEEDS YOU", 1, true), mon:line(34))
  T.truthy(mon:line(40):find("All clear on the island", 1, true), mon:line(40))
  T.truthy(mon:line(31):find("day ", 1, true), mon:line(31))
  T.truthy(mon:line(32):find("Moon ", 1, true), mon:line(32))
end)

T.test("mainframe wall 82x40: clock in block digits, Needs you slots", function()
  local world, mf, mon = build{ w = 82, h = 40, quiet = 6 }
  world:run(30)
  T.eq(mf.error, nil)
  local lit = 0
  for y = 25, 29 do for x = 2, 39 do if bgAt(mon, x, y) == COL.white then lit = lit + 1 end end end
  T.truthy(lit > 20, "clock digits drawn in rows 25-29, lit cells: " .. lit)
  T.truthy(mon:line(25):sub(2, 39):find("^%s*$"), "digits are cells, not letters")
  -- Canary-07 waiting is orange in slot 1; nothing red
  T.truthy(mon:line(35):find("Canary-07 waiting", 1, true), mon:line(35))
  T.eq(bgAt(mon, 2, 35), COL.orange)
  T.falsy(mon:find("Nothing needs you."), mon:text())
end)

T.test("mainframe wall 82x40: nothing needs you says so and sums up", function()
  local world, mf, mon = build{ w = 82, h = 40, calm = true }
  world:run(20)
  T.eq(mf.error, nil)
  T.truthy(mon:line(35):find("Nothing needs you.", 1, true), mon:text())
  T.eq(bgAt(mon, 2, 35), COL.lime)
  T.truthy(mon:line(36):find("machines:", 1, true) and mon:line(36):find("none lost", 1, true), mon:line(36))
  T.eq(mon:line(37):gsub("%s", ""), "", "slots 3-4 blank")
end)

T.test("mainframe wall 82x40: power slot lime under 100%, orange over, dim without data", function()
  local world, mf, mon = build{ w = 82, h = 40 }
  world:run(10)
  local function lit(tone)
    local n = 0
    for y = 25, 29 do for x = 42, 81 do if bgAt(mon, x, y) == tone then n = n + 1 end end end
    return n
  end
  -- no Operator: dim dashes and the note
  T.truthy(mon:line(31):find("Operator not reporting", 1, true), mon:line(31))
  T.truthy(lit(COL.lightGrey) > 0 or lit(COL.grey) > 0)
  -- 62%: lime digits, Buffer note
  world:at(world.now + 0.1, function() setPower(mf, { draw = 1860, potential = 3000, pct = 62, seen = 0 }) end)
  world:run(1.5)
  T.truthy(mon:line(31):find("1,860 of 3,000 FE/t", 1, true), mon:line(31))
  T.truthy(mon:line(32):find("Buffer 41%", 1, true), mon:line(32))
  T.truthy(lit(COL.lime) > 20, "lime digits")
  T.eq(lit(COL.orange), 0)
  T.falsy(mon:line(23):find("THROTTLED", 1, true))
  -- 113%: orange, not an alert
  mf.G.OPERATOR.power = { draw = 3400, potential = 3000, pct = 113, seen = 0 }
  world:run(1.5)
  T.truthy(lit(COL.orange) > 20, "orange digits")
  T.eq(lit(COL.lime), 0)
  T.truthy(mon:line(32):find("Over output, buffer 41% falling", 1, true), mon:line(32))
  T.falsy(mon:find("Power throttled"), "over output is not an alert")
  T.falsy(mon:line(23):find("THROTTLED", 1, true))
  -- exactly 100%: orange
  mf.G.OPERATOR.power = { draw = 3000, potential = 3000, pct = 100, seen = 0 }
  world:run(1.5)
  T.truthy(lit(COL.orange) > 20)
end)

T.test("mainframe wall 82x40: THROTTLED only while power.limit is set, red, and first in Needs you", function()
  local world, mf, mon = build{ w = 82, h = 40 }
  world:run(10)
  setPower(mf, { draw = 2700, potential = 3000, pct = 90, seen = 0, limit = 2700, asked = 4800, askedFor = 120 })
  world:run(1.5)
  T.truthy(mon:line(23):find("THROTTLED", 1, true), mon:line(23))
  T.truthy(mon:line(31):find("Throttled at 2,700 FE/t", 1, true), mon:line(31))
  T.truthy(mon:line(32):find("Asked for 4,800 (160%) for 2m", 1, true), mon:line(32))
  T.truthy(mon:line(35):find("Power throttled", 1, true), mon:line(35))
  T.eq(bgAt(mon, 2, 35), COL.red)
  local n = 0
  for y = 25, 29 do for x = 42, 81 do if bgAt(mon, x, y) == COL.red then n = n + 1 end end end
  T.truthy(n > 20, "red digits")
  -- the limit goes: the tag and the entry go with it
  mf.G.OPERATOR.power = { draw = 2000, potential = 3000, pct = 67, seen = 0 }
  world:run(1.5)
  T.falsy(mon:line(23):find("THROTTLED", 1, true))
  T.falsy(mon:find("Power throttled"))
end)
