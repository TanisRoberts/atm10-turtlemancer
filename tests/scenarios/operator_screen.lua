-- The Operator's screens on the computer and on monitors of different sizes; taps and keys.
local cc = require("sim.cc")
local T  = require("sim.test")

local COMP                                   -- the computer of the last build, for taps on its own screen
local PORT = { "bigreactors:reactoraccessport", "inventory" }
local function port() return cc.Inv.new{ size = 9, types = PORT } end

-- two reactors, Storage stand-in reporting uranium; sizes = { w, h } of the computer, mon = { w, h } of a monitor
local function build(w, h, mon, opts)
  opts = opts or {}
  local world = cc.world(); local net = world:net()
  local i1, o1, i2, o2 = port(), port(), port(), port()
  i1:give("mekanism:ingot_uranium", 12); i2:give("mekanism:ingot_uranium", 8)
  local ra = world:reactor{ stored = 620000, active = true, prod = 3000, demand = 1200, rodScale = true, rodLevel = 40,
    inPort = i1, outPort = o1, fuel = 2800 }
  local rb = world:reactor{ stored = 910000, active = false, prod = 3000, demand = 1200, rodScale = true, rodLevel = 40,
    inPort = i2, outPort = o2, fuel = 1600 }
  net:add("BigReactors-Reactor_0", ra); net:add("BigReactors-Reactor_1", rb)
  net:add("in_0", i1); net:add("out_0", o1); net:add("in_1", i2); net:add("out_1", o2)
  o1:give("bigreactors:cyanite_ingot", 64 * 9)                      -- reactor 1's outlet is full and never drains
  local c = world:computer{ id = 5, label = "Operator", w = w, h = h }
  COMP = c
  c:attach("back", cc.wired(net)); c:attach("top", cc.wireless{ ender = true })
  local m = mon and c:monitor("right", mon[1], mon[2])
  c:installRole("operator")
  for n = 0, 3 do net:add("enderstorage:ender_chest_" .. n, cc.Inv.new{ size = n == 1 and 1 or 27 }) end
  net.devices["enderstorage:ender_chest_1"]:give("bigreactors:cyanite_ingot", 64)       -- reactor 1's waste chest is full too
  c:writeTable("operator.cfg", { nextNum = { reactor = 2 }, units = {
    ["BigReactors-Reactor_0"] = { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true, input = "in_0", output = "out_0",
      fuelChest = "enderstorage:ender_chest_0", wasteChest = "enderstorage:ender_chest_1" },
    ["BigReactors-Reactor_1"] = { kind = "reactor", num = 2, label = "Reactor-2", mode = "auto", enabled = true, input = "in_1", output = "out_1",
      fuelChest = "enderstorage:ender_chest_2", wasteChest = "enderstorage:ender_chest_3" } } })
  c:run("operator")
  world:run(opts.run or 20)
  return world, c, m, ra, rb
end


local ENV = require("sim.env")
local COL = ENV.colors

local function at(scr, text, fromRow)          -- fromRow 3: skip the header and the notice row
  for y = fromRow or 1, scr.h do
    local x = scr:line(y):find(text, 1, true)
    if x then return x, y end
  end
  error("not on screen: " .. text .. "\n" .. scr:text())
end
local function press(world, m, x, y)
  if m.comp then m:touch(x, y) else COMP:click(x, y) end
  world:run(0.6)
end
local function touch(world, m, text, dx)
  local x, y = at(m, text)
  press(world, m, x + (dx or 1), y)
end
local function touchIn(world, m, rowText, pat)           -- the pattern in the row that holds rowText
  local _, y = at(m, rowText, 3)
  local x = m:line(y):find(pat, 1, true)
  assert(x, "no " .. pat .. " in row " .. y .. ": " .. m:line(y))
  press(world, m, x + 1, y)
end
local function rec(c) return c.G and c.G.last end
local function level(r) return 100 - r.rodLevel end

T.test("operator screen: overview at 51x19 with the Power Grid column and a tile per reactor", function()
  local world, c, _, ra, rb = build(51, 19)
  T.eq(c.error, nil)
  local s = c.screen
  for _, t in ipairs({ "OPERATOR", "2 reactors  1 problem", "POWER GRID", "REACTORS", "Reactor-1", "Reactor-2",
    "Outlet not emptying", "All good", "Reactors on", "1/2", "1 needs fixing", "FE/t", "Buffer" }) do
    T.truthy(s:find(t), "missing on the overview: " .. t .. "\n" .. s:text())
  end
  -- the tile stripe: orange while something is missing, light blue when idle
  local x, y = at(s, "Reactor-1")
  local _, b1 = s:colourAt(x - 2, y)
  T.eq(b1, COL.orange, "tile 1 stripe")
  local x2, y2 = at(s, "Reactor-2")
  local _, b2 = s:colourAt(x2 - 2, y2)
  T.eq(b2, COL.lightBlue, "tile 2 stripe")
  -- the column and the tiles do not run past the edge
  for yy = 1, 19 do T.truthy(#s:line(yy) <= 51) end
end)

T.test("operator screen: tap a tile, step the level, hold, back to Auto, ON and OFF", function()
  local world, c, _, ra = build(51, 19)
  local s = c.screen
  touch(world, s, "Reactor-1")
  T.truthy(s:find("POWER LEVEL") and s:find("Run"), "no Power tab\n" .. s:text())
  T.truthy(s:find("rods at"), "no rod caption")
  local before = level(ra)
  touch(world, s, ">>")
  T.eq(level(ra), before + 5, "level should rise 5% a tap")
  T.truthy(s:find("Manual Hold:"), "no hold line")
  -- the countdown sits at the right edge of the screen
  local _, hy = at(s, "Manual Hold:")
  T.truthy(s:line(hy):find("%d:%d%d$") or s:line(hy):find("%d:%d%d ?$"), "countdown not at the right edge: " .. s:line(hy))
  T.truthy(#s:line(hy) <= 51, "hold line too long")
  T.truthy(s:find("tap AUTO to return now"))
  -- bars: the lime part of the rods grows with the level (rods are drawn with cells, look for the lime)
  local lime = 0
  for yy = 4, 10 do local _, b = s:colourAt(4, yy); if b == COL.lime then lime = lime + 1 end end
  T.truthy(lime >= 2, "rods not drawn in lime")
  touch(world, s, "<<"); touch(world, s, "<<")
  T.eq(level(ra), before - 5)
  -- the held level is not moved by Auto
  world:run(30)
  T.eq(level(ra), before - 5, "Auto moved a held level")
  touchIn(world, s, "Run", "AUTO")
  T.falsy(s:find("Manual Hold"), "hold should end on AUTO")
  T.truthy(s:find("Auto set:"), "no Auto set line\n" .. s:text())
  local _, ay = at(s, "Auto set:")
  T.truthy(s:line(ay):find("%d+[sm]%s*$"), "age not at the right edge: " .. s:line(ay))
  touchIn(world, s, "Run", "OFF")
  T.waitFor(world, function() return not ra.on end, 10, "OFF ignored")
  T.truthy(s:find("Forced off"))
  touchIn(world, s, "Run", "ON")
  T.waitFor(world, function() return ra.on end, 10, "ON ignored")
  touchIn(world, s, "Run", "AUTO")
  -- Back returns to the overview
  touch(world, s, "Back")
  T.truthy(s:find("POWER GRID"), "back should show the overview")
end)

T.test("operator screen: the level stops at the limits with a notice", function()
  local world, c, _, ra = build(51, 19)
  local s = c.screen
  c:writeTable("operator.cfg", { nextNum = { reactor = 2 }, plant = { levelMax = 60 }, units = {
    ["BigReactors-Reactor_0"] = { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true, input = "in_0", output = "out_0" },
    ["BigReactors-Reactor_1"] = { kind = "reactor", num = 2, label = "Reactor-2", mode = "auto", enabled = true, input = "in_1", output = "out_1" } } })
  world:run(8)
  touch(world, s, "Reactor-1")
  for _ = 1, 12 do touch(world, s, ">>") end
  T.eq(level(ra), 60, "should stop at Highest")
  T.truthy(s:find("Highest is 60%"), "no notice\n" .. s:text())
end)

T.test("operator screen: Needs tab lists the checks, and a tap on a problem says why", function()
  local world, c = build(51, 19)
  local s = c.screen
  touch(world, s, "Reactor-1")
  touch(world, s, "Needs")
  T.truthy(s:find("NEEDS  9 ok  1 missing  0 unknown"), "counts\n" .. s:text())
  T.truthy(s:find("! Waste clearing") and s:find("1 problem"), "missing row")
  T.falsy(s:find("Fuel supply") or s:find("Power output"), "those two checks are gone")
    T.truthy(s:find("+ Computer port"), "ok row")
  T.truthy(s:find("- Coolant and turbine"), "not needed row")
  T.truthy(s:find("Needs%*") or s:find("Needs*", 1, true), "tab star")
  touch(world, s, "! Waste clearing")
  T.truthy(s:find("outlet not emptying") and s:find("Manually assign") and s:find("Ignore this"), "no fix page\n" .. s:text())
  -- Reactor-2 has nothing missing: no star on the tab... it still has unknowns, so it keeps it; but no "!" row
  touch(world, s, "Back"); touch(world, s, "Back"); touch(world, s, "Reactor-2")
  touch(world, s, "Needs")
  T.falsy(s:find("! ", 1, true), "Reactor-2 has nothing missing\n" .. s:text())
end)

T.test("operator screen: Set tab saves thresholds and limits, for one reactor or all", function()
  local world, c = build(51, 19)
  local s = c.screen
  touch(world, s, "Reactor-1")
  touch(world, s, "Set")
  T.truthy(s:find("SWITCHING") and s:find("LEVEL") and s:find("default"), "set tab\n" .. s:text())
  touchIn(world, s, "ON below", ">>")
  local cfg = c:readTable("operator.cfg")
  T.eq(cfg.units["BigReactors-Reactor_0"].onBelow, 35)
  T.truthy(s:find("local"), "override not marked")
  do  -- the buttons stop short of the status text: a gap of at least two cells
    local _, ry = at(s, "ON below", 3)
    local row = s:line(ry)
    local gx = row:find(">>", 1, true)
    local tx = row:find("local", 1, true)
    T.truthy(tx and gx and tx - (gx + 3) >= 2, "no gap before the status: " .. row)
  end
  -- ON below stays 10 under OFF above
  for _ = 1, 20 do touchIn(world, s, "ON below", ">>") end
  cfg = c:readTable("operator.cfg")
  T.eq(cfg.units["BigReactors-Reactor_0"].onBelow, 80)
  T.truthy(s:find("at least 10 points"), "no notice\n" .. s:text())
  -- all reactors
  touch(world, s, "All reactors")
  touchIn(world, s, "OFF above", ">>")
  cfg = c:readTable("operator.cfg")
  T.eq(cfg.plant.offAbove, 95)
  -- hold time
  touchIn(world, s, "Back to Auto", "<<")
  -- run it NO
  touch(world, s, "NO", 0)
  cfg = c:readTable("operator.cfg")
  T.eq(cfg.units["BigReactors-Reactor_0"].manage, false)
  -- reset needs two taps
  touch(world, s, "Reset to defaults")
  cfg = c:readTable("operator.cfg")
  T.eq(cfg.units["BigReactors-Reactor_0"].onBelow, 80, "one tap must only arm")
  touch(world, s, "Sure?")
  cfg = c:readTable("operator.cfg")
  T.eq(cfg.units["BigReactors-Reactor_0"].onBelow, nil)
  T.eq(cfg.units["BigReactors-Reactor_0"].manage, nil)
end)

for _, size in ipairs({ { 39, 13 }, { 26, 20 } }) do
  T.test(("operator screen: a monitor %dx%d shows the overview and takes taps"):format(size[1], size[2]), function()
    local world, c, m, ra = build(51, 19, size)
    T.eq(c.error, nil)
    T.truthy(m:find("OPERATOR") and m:find("Reactor-1") and m:find("Reactor-2"), m:text())
    T.truthy(m:find("1 needs fix") or m:find("1 of 2 on"), "no summary\n" .. m:text())
    for yy = 1, size[2] do T.truthy(#m:line(yy) <= size[1], "row too wide: " .. m:line(yy)) end
    touch(world, m, "Reactor-1")
    T.truthy(m:find("POWER LEVEL") and m:find("AUTO"), "power tab\n" .. m:text())
    local before = level(ra)
    touch(world, m, ">>")
    T.eq(level(ra), before + 5)
    touch(world, m, size[1] >= 39 and "Needs" or "Need")
    T.truthy(m:find("NEEDS"), "needs tab\n" .. m:text())
    T.truthy(m:find("Waste clearing"), "waste row\n" .. m:text())
    touch(world, m, "Set")
    T.truthy(m:find("ON below"), "set tab\n" .. m:text())
    -- the computer's own screen keeps its own page
    T.truthy(c.screen:find("POWER GRID"), "computer screen should still be on the overview")
  end)
end

T.test("operator screen: one reactor on a narrow screen opens straight on its Power tab", function()
  local world = cc.world(); local net = world:net()
  local r = world:reactor{ stored = 500000, active = true, prod = 3000, demand = 1200, rodScale = true, rodLevel = 40, fuel = 2000 }
  net:add("BigReactors-Reactor_0", r)
  local c = world:computer{ id = 5, label = "Operator", w = 26, h = 20 }
  c:attach("back", cc.wired(net)); c:attach("top", cc.wireless{ ender = true })
  COMP = c
  c:installRole("operator"); c:writeFile("operator.env", "SETUP_WIZARD=no\n"); c:run("operator"); world:run(10)
  T.truthy(c.screen:find("POWER LEVEL"), c.screen:text())
  c:click(2, 20); world:run(0.6)
  T.truthy(c.screen:find("OPERATOR"), "Back should show the overview\n" .. c.screen:text())
end)

T.test("operator screen: the wall shows panels, the chart and the recent events", function()
  local world, c, m, ra = build(51, 19, { 164, 81 }, { run = 400 })
  T.eq(c.error, nil)
  for _, t in ipairs({ "POWER GRID", "OUTPUT", "BUFFER", "PLANT", "NEEDS ATTENTION", "Reactor-1", "Reactor-2", "POWER LEVEL", "READINGS",
    "PLANT BUFFER, LAST 30 MINUTES", "RECENT", "Operator   started", "-30 min", "now", "Supply (Storage)" }) do
    T.truthy(m:find(t), "missing on the wall: " .. t .. "\n" .. m:text())
  end
  for yy = 1, 81 do T.truthy(#m:line(yy) <= 164, "row too wide") end
  -- the chart has lime bars
  local lime = 0
  for yy = 40, 75 do for xx = 46, 160 do local _, b = m:colourAt(xx, yy); if b == COL.lime then lime = lime + 1 end end end
  T.truthy(lime > 20, "no lime in the chart")
  -- the controls on a panel work by touch
  local before = level(ra)
  touch(world, m, ">>")
  T.eq(level(ra), before + 5, "level step on the wall")
  T.truthy(m:find("Manual Hold:"))
  -- a tap on a panel's controls works
end)

local function row(s, text, from) local _, y = at(s, text, from or 3); return s:line(y) end
local function toNeeds(world, s, who)
  touch(world, s, who or "Reactor-1")
  touch(world, s, "Needs")
end

T.test("operator screen: assign an inlet and an outlet by hand from a Needs row, search to narrow, clear", function()
  local world, c = build(51, 19)
  local s = c.screen
  toNeeds(world, s)
  touch(world, s, "! Waste clearing")
  T.truthy(s:find("Its outlet port"), "no fix section\n" .. s:text())
  touch(world, s, "Manually assign")
  T.truthy(s:find("ASSIGN OUTLET"), "no picker\n" .. s:text())
  for _, n in ipairs({ "in_0", "out_0", "in_1", "out_1" }) do T.truthy(s:find(n), "candidate missing: " .. n) end
  T.falsy(s:find("modem"), "a modem is not a candidate")
  COMP:type("out_1"); world:run(0.6)
  T.truthy(s:find("out_1") and not s:find("in_0") and not s:find("out_0"), "search did not narrow the list\n" .. s:text())
  touch(world, s, "out_1", 0)                 -- first tap selects
  T.truthy(s:find("ASSIGN OUTLET"), "one tap must only select")
  touch(world, s, "out_1", 0)                 -- second picks
  local cfg = c:readTable("operator.cfg")
  T.eq(cfg.units["BigReactors-Reactor_0"].output, "out_1")
  T.truthy(s:find("Waste clearing"), "back on the need page\n" .. s:text())
  T.truthy(s:find("out_1"), "the pick is shown")
  -- the waste problem is gone once the new outlet is watched (out_1 is empty)
  world:run(6)
  -- clear: back to auto-detect
  touch(world, s, "Clear")
  cfg = c:readTable("operator.cfg")
  T.truthy(cfg.units["BigReactors-Reactor_0"].output ~= "out_1", "Clear should drop the pick")
  T.eq(c.error, nil)
end)

T.test("operator screen: a problem can be ignored and counted again", function()
  local world, c = build(51, 19)
  local s = c.screen
  toNeeds(world, s)
  T.truthy(s:find("NEEDS  9 ok  1 missing  0 unknown"))
  touch(world, s, "! Waste clearing")
  T.truthy(s:find("outlet not emptying") and s:find("Ignore this"), "need page\n" .. s:text())
  touch(world, s, "Ignore this")
  T.truthy(s:find("ignored") and s:find("Stop ignoring"), "not ignored\n" .. s:text())
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].ignore.wasteTo, true)
  touch(world, s, "Back")
  T.truthy(s:find("NEEDS  8 ok  0 missing  0 unknown") or s:find("all good"), "an ignored need must stop counting\n" .. s:text())
  T.truthy(row(s, "Waste clearing"):find("ignored"), row(s, "Waste clearing"))
  touch(world, s, "Waste clearing")
  touch(world, s, "Stop ignoring")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].ignore, nil)
  touch(world, s, "Back")
  T.truthy(s:find("NEEDS  9 ok  1 missing  0 unknown"), s:text())
end)

T.test("operator screen: a monitor can pick a port from the list (no typing there)", function()
  local world, c, m = build(51, 19, { 51, 19 })
  toNeeds(world, m)
  touch(world, m, "! Waste clearing")
  touch(world, m, "Manually assign")
  T.truthy(m:find("ASSIGN OUTLET") and m:find("out_1"), m:text())
  touch(world, m, "out_1", 0); touch(world, m, "out_1", 0)
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].output, "out_1")
end)

T.test("operator screen: typed commands, with and without the slash; a monitor has no command bar", function()
  local world, c, m, ra, rb = build(51, 19, { 51, 19 })
  local KEYS = ENV.keys
  local s = c.screen
  T.contains(s:line(18), "/ = commands")
  T.absent(m:text(), "/ = commands", "the wall monitor has no keyboard")
  local function run(line) c:type(line); world:run(0.3); c:key(KEYS.enter); world:run(0.5) end
  c:type("/"); world:run(0.3)
  for _, name in ipairs({ "/status", "/on", "/off", "/auto", "/level", "/help" }) do T.contains(s:text(), name) end
  c:key(KEYS.backspace); world:run(0.3)
  run("/help")
  T.contains(s:line(2), "/status"); T.contains(s:line(2), "/on")  -- bare words run too (no list to search here)
  run("status")
  T.contains(s:line(2), "of 2 reactors on")
  run("/off reactor-1")
  T.waitFor(world, function() return not ra.on end, 10, "/off ignored")
  T.contains(s:line(2), "Reactor-1: OFF")
  run("on 1")
  T.waitFor(world, function() return ra.on end, 10, "on ignored")
  run("/auto")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_1"].mode, "auto")
  run("/level 55 2")
  T.contains(s:line(2), "Reactor-2: level 55% held")
  run("/level abc")
  T.contains(s:line(2), "not a whole number")
  run("/on 9")
  T.contains(s:line(2), "No reactor '9'")
end)

T.test("operator screen: the chests have Needs rows with Manually assign and Clear, and the Power tab shows the fuel chest", function()
  local world, c = build(51, 19)
  local s = c.screen
  touch(world, s, "Reactor-1")
  T.truthy(s:find("in chest"), "no fuel chest on the Power tab\n" .. s:text())
  touch(world, s, "Needs")
  T.truthy(s:find("+ Fuel chest") and s:find("+ Waste chest"), "both chest rows\n" .. s:text())
  -- Reactor-1 loses its chests (two reactors: the Operator doesn't guess), so the rows turn into things to fix
  local cfg0 = c:readTable("operator.cfg")
  cfg0.units["BigReactors-Reactor_0"].fuelChest, cfg0.units["BigReactors-Reactor_0"].wasteChest = nil, nil
  c:writeTable("operator.cfg", cfg0); world:run(5)
  T.truthy(s:find("? Fuel chest") and s:find("? Waste chest"), "unknown rows\n" .. s:text())
  touch(world, s, "? Fuel chest")
  T.truthy(s:find("Its fuel chest") and s:find("Manually assign") and s:find("Clear"), "no fix section\n" .. s:text())
  touch(world, s, "Manually assign")
  T.truthy(s:find("ASSIGN FUEL CHEST"), "no picker\n" .. s:text())
  T.truthy(s:find("ender_chest_0") and s:find("ender_chest_3"), "chests are candidates\n" .. s:text())
  COMP:type("chest_3"); world:run(0.6)
  touch(world, s, "ender_chest_3", 0)
  touch(world, s, "ender_chest_3", 0)
  local cfg = c:readTable("operator.cfg").units
  T.eq(cfg["BigReactors-Reactor_0"].fuelChest, "enderstorage:ender_chest_3")
  T.eq(cfg["BigReactors-Reactor_1"].wasteChest, nil, "taken from the other reactor")
  touch(world, s, "Clear")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].fuelChest, nil)
end)
