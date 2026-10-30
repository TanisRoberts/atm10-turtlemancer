-- The Nether Foreman on the UI kit (docs/systems/nether.md): overview with the barrels line, a Firecrest's page,
-- Rules, the Barrels button and the typed commands, at 57x24 (monitor), 51x19, 39x13 and 26x20, with a stand-in
-- Firecrest on the radio (tests/scenarios/nether_basic.lua covers the barrels and the orders).
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")
local SIZES = { { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }
-- o.w, o.h: the computer's screen; o.monitor = { w, h }; o.noBarrels: nothing assigned yet; o.stock: items for Stock
local function world(o)
  o = o or {}
  local w = cc.world()
  local net = w:net()
  local b = {
    dock = net:add("minecraft:barrel_0", MS.barrel()), out = net:add("minecraft:barrel_1", MS.barrel()),
    stock = net:add("minecraft:barrel_2", MS.barrel()), input = net:add("minecraft:barrel_3", MS.barrel()),
  }
  local c = w:computer{ id = 2, label = "Nether Foreman", w = o.w or 51, h = o.h or 19 }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = o.monitor and c:monitor("right", o.monitor[1], o.monitor[2])
  c:installRole("nether")
  if o.noBarrels then c:writeTable("nether.cfg", {})
  else
    c:writeTable("nether.cfg", { docks = { "minecraft:barrel_0" }, outputs = { "minecraft:barrel_1" },
      stocks = { "minecraft:barrel_2" }, inputs = { "minecraft:barrel_3" } })
  end
  b.stock:give("minecraft:bucket", 3)
  b.stock:give("minecraft:coal", 30)
  c:run("nether")
  local f = MS.standIn(w, { id = 9 })
  w:run(8)
  return { w = w, c = c, mon = mon, f = f, b = b, s = c.screen }
end

local function tapOn(e, scr, text, last)
  local a, z, step = 3, scr.h, 1
  if last then a, z, step = scr.h, 3, -1 end
  for row = a, z, step do
    local x = scr:line(row):find(text, 1, true)
    if x then
      if scr == e.c.screen then e.c:click(x, row) else scr:touch(x, row) end
      e.w:run(1)
      return
    end
  end
  error("no " .. text .. " on the screen:\n" .. scr:text(), 2)
end
local function cmd(e, line) e.c:type(line); e.c:key(257); e.w:run(1) end
local function cfg(e) return e.c:readTable("nether.cfg") end

T.test("nether screens: the overview at every size - tile, barrels line, buttons", function()
  for _, sz in ipairs(SIZES) do
    local e = world({ w = sz[1], h = sz[2] })
    local s = e.s
    T.contains(s, "NETHER FOREMAN")
    T.contains(s, "ok")
    T.contains(s, "Firecrest-01")
    T.contains(s, "docked")
    T.contains(s, "Fuel")
    T.contains(s, "Stock 3 buckets")
    T.contains(s, "Presets")
    T.contains(s, "Rule")
    if sz[1] >= 51 then T.contains(s, "1 firecrest"); T.contains(s, "out 27/27 free") end
    if sz[2] > 14 then T.contains(s, "Bar") else T.absent(s, "Barrels", "no Barrels button on a short screen") end
    if sz[1] >= 39 then T.contains(s, "oot") end
    T.absent(s, "Dock all", "the Nether Foreman has no Dock all")
  end
end)

T.test("nether screens: no barrels yet says so", function()
  local e = world({ w = 57, h = 24, noBarrels = true })
  T.contains(e.s, "tap Barrels (or /assign) to give them jobs")
  T.contains(e.s, "Barrels")
end)

T.test("nether screens: a Firecrest's page at every size - lava, bucket, barrel, layers in Nether Y", function()
  for _, sz in ipairs(SIZES) do
    local e = world({ w = sz[1], h = sz[2] })
    local s = e.s
    tapOn(e, s, "Firecrest-01")
    T.contains(s, "FIRECREST-01")
    T.contains(s, "docked")
    if sz[1] >= 44 then
      T.contains(s, "drinks under 25%")
      T.contains(s, "LAYERS"); T.contains(s, "Debris deep"); T.contains(s, "Above lava")
      T.contains(s, "Min Y"); T.contains(s, "START")
      T.contains(s, "Barrel")
    elseif sz[1] > 30 then
      T.contains(s, "Info")
    else
      T.contains(s, "Lava")
    end
  end
end)

T.test("nether screens: the Min Y stepper stays inside the Nether (6..120)", function()
  local e = world({ w = 57, h = 24 })
  tapOn(e, e.s, "Firecrest-01")
  local mx, y = e.s:find("Min Y")
  local x = e.s:line(y):find("-", mx + 5, true)
  for _ = 1, 8 do e.c:click(x, y); e.w:run(0.3) end
  T.eq(cfg(e).firecrests[9].pMin, 6, "stops at the Nether floor")
end)

T.test("nether screens: START and the layers go out with the lava rule", function()
  local e = world({ w = 57, h = 24 })
  tapOn(e, e.s, "Firecrest-01")
  tapOn(e, e.s, "Above lava")
  tapOn(e, e.s, "START", true)
  e.w:run(4)
  local m = e.f.env._G.lastCmd
  T.eq(m.want, "run"); T.eq(m.minY, 33); T.eq(m.maxY, 44)
  T.eq(m.hungryAt, 25); T.eq(m.fullAt, 75)
end)

T.test("nether screens: Rules at every size - lava steppers, keep steppers, have, junk", function()
  for _, sz in ipairs(SIZES) do
    local e = world({ w = sz[1], h = sz[2] })
    local s = e.s
    tapOn(e, s, "Rule", true)
    T.contains(s, "RULES")
    if sz[1] >= 51 then T.contains(s, "kept, 15 junk") end
    T.contains(s, "LAVA")
    T.contains(s, "Drink under")
    T.contains(s, "KEEP IN THE NETHER")
    T.contains(s, "have")
    T.contains(s, "Bucket")
    if sz[2] >= 22 then T.contains(s, "FIRECREST THROWS AWAY"); T.contains(s, "netherrack") end
    if sz[2] > 14 then T.contains(s, "Keep"); T.contains(s, "Junk") end
    -- Drink under + 5%
    local _, y = s:find("Drink under")
    if sz[1] < 30 then y = y + 1 end
    local line = s:line(y)
    local x = line:find("+", 1, true)
    T.truthy(x, s:text())
    e.c:click(x, y); e.w:run(1)
    T.eq(cfg(e).hungryAt, 30, "drink under at " .. sz[1])
    -- a keep stepper: Bucket + 1
    local _, by = s:find("Bucket")
    if sz[1] < 30 then by = by + 1 end
    local bx = s:line(by):find("+", 1, true)
    T.truthy(bx, s:text())
    e.c:click(bx, by); e.w:run(1)
    T.eq(cfg(e).keep["minecraft:bucket"], 5, "bucket keep at " .. sz[1])
    tapOn(e, s, "<", true)
    T.contains(s, "Presets")
  end
end)

T.test("nether screens: Rules shows what Stock holds next to what is kept", function()
  local e = world({ w = 57, h = 24 })
  tapOn(e, e.s, "Rules")
  local _, y = e.s:find("Coal")
  T.contains(e.s:line(y), "64")                -- keep 64
  T.contains(e.s:line(y), "30")                -- Stock holds 30
end)

T.test("nether screens: + Keep and + Junk start the command on the computer, a monitor says where to type", function()
  local e = world({ w = 57, h = 24, monitor = { 57, 24 } })
  tapOn(e, e.s, "Rules")
  tapOn(e, e.s, "+ Keep", true)
  T.contains(e.s, "/keep ")
  e.c:type("coal 32"); e.c:key(257); e.w:run(1)
  T.eq(cfg(e).keep["minecraft:coal"], 32)
  tapOn(e, e.mon, "Rules")
  tapOn(e, e.mon, "+ Junk", true)
  T.contains(e.mon, "Type it on the computer: /junk <item>")
end)

T.test("nether screens: Barrels opens the shared assign screen on the computer and Back returns", function()
  local e = world({ w = 57, h = 24, monitor = { 57, 24 } })
  tapOn(e, e.s, "Barrels", true)
  T.contains(e.s, "NETHER BARRELS")
  T.contains(e.s, "barrel_0")
  tapOn(e, e.s, "Back", true)
  T.contains(e.s, "Presets")
  T.contains(e.s, "Firecrest-01", "back on the overview, and the kit draws again")
  e.w:run(3)
  tapOn(e, e.s, "Rules", true)
  T.contains(e.s, "KEEP IN THE NETHER")
  tapOn(e, e.mon, "Barrels", true)
  T.contains(e.mon, "Barrels: type /assign on the Nether computer")
end)

T.test("nether screens: every command, and /help lists them", function()
  local e = world({ w = 57, h = 24 })
  cmd(e, "/rules"); T.contains(e.s, "KEEP IN THE NETHER")
  cmd(e, "/home"); T.contains(e.s, "Firecrest-01")
  cmd(e, "keep coal 128"); T.eq(cfg(e).keep["minecraft:coal"], 128); T.contains(e.s, "Keeping 128 Coal")
  cmd(e, "/keep coal 0"); T.eq(cfg(e).keep["minecraft:coal"], nil); T.contains(e.s, "Not keeping Coal")
  cmd(e, "/junk tuff")
  local junk = cfg(e).junk
  T.eq(junk[#junk], "tuff")
  cmd(e, "/unjunk tuff")
  junk = cfg(e).junk
  T.truthy(junk[#junk] ~= "tuff")
  cmd(e, "/help")
  for _, name in ipairs({ "/rules", "/assign", "/keep", "/junk", "/unjunk", "/presets", "/reboot", "/redock" }) do
    T.contains(e.s, name)
  end
  cmd(e, "/assign")
  T.contains(e.s, "NETHER BARRELS")
end)

T.test("nether screens: a new preset starts at the Nether's Y range", function()
  local e = world({ w = 57, h = 24 })
  cmd(e, "/new Fresh")
  T.contains(e.s, "NEW PRESET")
  local _, y = e.s:find("Min Y")
  T.contains(e.s:line(y), "12")
  T.contains(e.s:line(y + 1), "17")
end)

T.test("nether screens: no Firecrest yet shows the waiting text", function()
  local w = cc.world()
  local c = w:computer{ id = 2, label = "Nether Foreman", w = 51, h = 19 }
  c:attach("top", cc.wireless{ ender = true })
  c:installRole("nether")
  c:run("nether")
  w:run(5)
  T.contains(c.screen, "Waiting for the first firecrest")
  T.contains(c.screen, "Presets")
end)
