-- The setup wizard: a new reactor waits for setup, then four pages (found, inlet, outlet, check), Find it, Not now,
-- and Run setup again.
local cc = require("sim.cc")
local T  = require("sim.test")
local ENV = require("sim.env")
local COL = ENV.colors

local PORT = { "bigreactors:reactoraccessport", "inventory" }
local function port() return cc.Inv.new{ size = 9, types = PORT } end
local COMP

-- one reactor, four ports: in_0 holds uranium, out_0 holds cyanite, in_1 and out_1 are empty
local function build(w, h, mon)
  local world = cc.world(); local net = world:net()
  local p = { in0 = port(), out0 = port(), in1 = port(), out1 = port() }
  p.in0:give("mekanism:ingot_uranium", 12); p.out0:give("bigreactors:cyanite_ingot", 3)
  local r = world:reactor{ stored = 200000, prod = 3000, demand = 1200, rodScale = true, rodLevel = 40, fuel = 2000, inPort = p.in0, outPort = p.out0 }
  net:add("BigReactors-Reactor_0", r)
  for name, inv in pairs({ in_0 = p.in0, out_0 = p.out0, in_1 = p.in1, out_1 = p.out1 }) do net:add(name, inv) end
  local c = world:computer{ id = 5, label = "Operator", w = w or 51, h = h or 19 }
  COMP = c
  c:attach("back", cc.wired(net)); c:attach("top", cc.wireless{ ender = true })
  local m = mon and c:monitor("right", mon[1], mon[2])
  c:installRole("operator")
  c:run("operator")
  world:run(15)
  return world, c, m, r, p
end

local function at(scr, text, from)
  for y = from or 1, scr.h do
    local x = scr:line(y):find(text, 1, true)
    if x then return x, y end
  end
  error("not on screen: " .. text .. "\n" .. scr:text())
end
local function press(world, m, x, y)
  if m.comp then m:touch(x, y) else COMP:click(x, y) end
  world:run(0.6)
end
local function touch(world, m, text, dx, from)
  local x, y = at(m, text, from)
  press(world, m, x + (dx or 1), y)
end

T.test("operator wizard: a new reactor shows the awaiting card and is not switched", function()
  local world, c, _, r = build()
  T.eq(c.error, nil)
  local s = c.screen
  T.truthy(s:find("New Reactor Awaiting Setup"), s:text())
  T.truthy(s:find("Not switched until set up") and s:find("Set up  >"), s:text())
  T.truthy(s:find("1 to set up"), "summary\n" .. s:text())
  local x, y = at(s, "Reactor_0")
  local _, bg = s:colourAt(x - 2, y)
  T.eq(bg, COL.cyan, "card stripe")
  world:run(30)
  T.truthy(not r.on, "an un-setup reactor must not be switched (buffer is at 20%)")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].input, nil, "nothing guessed may be saved")
end)

T.test("operator wizard: found, inlet, outlet, check and finish", function()
  local world, c, _, r = build()
  local s = c.screen
  touch(world, s, "Set up  >")
  T.truthy(s:find("FOUND ON THE CABLE") and s:find("step 1 of 4"), s:text())
  T.truthy(s:find("4 found"), "ports counted\n" .. s:text())
  touch(world, s, "Start >")
  T.truthy(s:find("Which port feeds fuel IN?") and s:find("step 2 of 4"), s:text())
  local _, ry = at(s, "in_0", 3)
  T.truthy(s:line(ry):find("suggested") and s:line(ry):find("uranium"), "the port holding uranium should be suggested: " .. s:line(ry))
  -- search narrows
  COMP:type("in_1"); world:run(0.6)
  T.truthy(s:find("in_1") and not s:find("out_0") and not s:find("in_0"), s:text())
  touch(world, s, "in_1", 0); touch(world, s, "in_1", 0)
  T.falsy(s:find("Which port feeds"), "one tap on a port then two must pick it\n" .. s:text())
  T.truthy(s:find("Which port takes waste OUT?") and s:find("step 3 of 4"), s:text())
  T.falsy(s:find("in_1"), "the inlet is not offered as the outlet")
  local _, oy = at(s, "out_0", 3)
  T.truthy(s:line(oy):find("suggested") and s:line(oy):find("3 cyanite"), s:line(oy))
  touch(world, s, "out_0", 0); touch(world, s, "out_0", 0)
  T.truthy(s:find("CHECK IT") and s:find("step 4 of 4"), s:text())
  T.truthy(s:find("in_1") and s:find("out_0") and s:find("30%") and s:find("90%"), s:text())
  -- rename: tap the name box, type a letter
  local nx, ny = at(s, "Name", 3)
  press(world, s, nx + 6, ny)
  COMP:type("X"); world:run(0.6)
  touch(world, s, "Finish")
  local u = c:readTable("operator.cfg").units["BigReactors-Reactor_0"]
  T.eq(u.input, "in_1"); T.eq(u.output, "out_0"); T.eq(u.setup, true); T.eq(u.label, "Reactor-1X")
  T.falsy(s:find("Awaiting Setup"), "the card should be gone\n" .. s:text())
  T.truthy(s:find("Reactor-1X"), s:text())
  T.waitFor(world, function() return r.on end, 20, "a set-up reactor must be switched")
  T.eq(c.error, nil)
end)

T.test("operator wizard: Find it sees which port got the ingot, and Not it watches again", function()
  local world, c, _, _, p = build()
  local s = c.screen
  touch(world, s, "Set up  >"); touch(world, s, "Start >")
  touch(world, s, "Find it")
  T.truthy(s:find("Drop ONE uranium ingot") and s:find("Watching"), s:text())
  world:run(2)
  T.falsy(s:find("Found:"), "nothing dropped yet")
  p.in1:give("mekanism:ingot_uranium", 1)
  world:run(2)
  T.truthy(s:find("Found: in_1"), s:text())
  touch(world, s, "Not it")
  T.truthy(s:find("Watching"), "Not it should watch again\n" .. s:text())
  p.out1:give("bigreactors:cyanite_ingot", 1)
  world:run(2)
  T.truthy(s:find("Found: out_1"), s:text())
  touch(world, s, "That's it >")
  T.truthy(s:find("Which port takes waste OUT?"), "That's it should move on with out_1 as the inlet\n" .. s:text())
  T.falsy(s:find("out_1"), "the port picked as the inlet is not offered again")
  -- Find it on the outlet page, and Pick from list returns to the list
  touch(world, s, "Find it")
  T.truthy(s:find("Drop ONE item"), s:text())
  touch(world, s, "Pick from list")
  T.truthy(s:find("Which port takes waste OUT?"), s:text())
end)

T.test("operator wizard: Not now leaves the card, Back walks back, and a monitor can run it too", function()
  local world, c, m = build(51, 19, { 39, 13 })
  touch(world, c.screen, "Set up  >"); touch(world, c.screen, "Not now")
  T.truthy(c.screen:find("Awaiting Setup") and c.screen:find("POWER GRID"), c.screen:text())
  T.truthy(m:find("Awaiting Setup"), "the monitor shows the card\n" .. m:text())
  touch(world, m, "Reactor_0")
  T.truthy(m:find("FOUND") and m:find("1/4") or m:find("step 1 of 4"), m:text())
  touch(world, m, "Start >")
  T.truthy(m:find("Fuel IN port?"), m:text())
  touch(world, m, "in_0", 0); touch(world, m, "in_0", 0)
  T.truthy(m:find("Waste OUT port?"), m:text())
  touch(world, m, "<", 0, 13)
  T.truthy(m:find("Fuel IN port?"), "Back should return to the inlet page\n" .. m:text())
  touch(world, m, "in_0", 0); touch(world, m, "in_0", 0)
  touch(world, m, "out_0", 0); touch(world, m, "out_0", 0)
  touch(world, m, "Finish")
  local u = c:readTable("operator.cfg").units["BigReactors-Reactor_0"]
  T.eq(u.setup, true); T.eq(u.input, "in_0"); T.eq(u.output, "out_0")
  T.falsy(m:find("Awaiting"), m:text())
end)

T.test("operator wizard: Run setup again brings the card back; a reactor with ports already saved never asks", function()
  local world, c, _, _, p = build()
  c:writeTable("operator.cfg", { nextNum = { reactor = 1 }, units = { ["BigReactors-Reactor_0"] =
    { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true, input = "in_0", output = "out_0" } } })
  world:run(6)
  local s = c.screen
  T.falsy(s:find("Awaiting Setup"), "ports saved by hand or an earlier version: no wizard\n" .. s:text())
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].setup, true)
  touch(world, s, "Reactor-1"); touch(world, s, "Set")
  touch(world, s, "Run setup again"); touch(world, s, "Sure?")
  T.truthy(s:find("Awaiting Setup"), s:text())
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].setup, false)
end)
