-- The Operator reads the energy detector: draw, potential, percent in the status and on the screens.
local cc = require("sim.cc")
local T  = require("sim.test")

local PORT = { "bigreactors:reactoraccessport", "inventory" }
local function port() return cc.Inv.new{ size = 9, types = PORT } end

local function plant(w, net)
  local c = w:computer{ id = 5, label = "Operator" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:installRole("operator")
  c:writeFile("operator.env", "SETUP_WIZARD=no\nSTATUS_EVERY=1\n")
  return c
end
local function listener(w)
  local m = w:computer{ id = 9, label = "Mainframe" }
  m:attach("top", cc.wireless{ ender = true })
  m:writeFile("mon.lua", [[
    rednet.open("top"); _G.last = nil
    while true do local _, m = rednet.receive("tanis-operator"); if m.type == "operator" then _G.last = m end end]])
  m:run("mon")
  return m
end

T.test("operator power: draw, potential and percent; the detector is not a unit", function()
  local w = cc.world(); local net = w:net()
  local inP, outP = port(), port()
  inP:give("mekanism:ingot_uranium", 10)
  -- 2000 FE/t at full power, rods at 50% insertion = level 50 -> makes 1000, so full power is 2000
  local r = w:reactor{ stored = 200000, active = true, prod = 2000, rodScale = true, rodLevel = 50, rods = 4, inPort = inP, outPort = outP }
  net:add("BigReactors-Reactor_0", r); net:add("port_in", inP); net:add("port_out", outP)
  local d = net:add("energy_detector_0", w:detector{ rate = 500, limit = 4000 })
  local mf = listener(w)
  local c = plant(w, net); c:run("operator")
  w:run(15)
  local p = mf.G.last and mf.G.last.power
  T.truthy(p, "no power in the status")
  T.eq(mf.G.last.plant.power.draw, p.draw)
  T.truthy(math.abs(p.draw - 500) < 1, "draw " .. tostring(p.draw))
  T.eq(p.limit, nil)                       -- no breaker tripped: no limit in the status
  T.eq(d.limit, 1000000000)                -- and a limit left on the detector was lifted to its maximum
  T.truthy(p.potential > 1900 and p.potential <= 2100, "potential " .. tostring(p.potential))
  T.truthy(p.pct > 20 and p.pct < 30, "pct " .. tostring(p.pct))
  T.truthy(p.seen and p.seen < 10, "seen")
  for _, u in ipairs(mf.G.last.units) do T.truthy(u.kind == "reactor", "detector became a unit: " .. tostring(u.id)) end
  T.truthy(c:readTable("operator.cfg").detectors["energy_detector_0"].label == "Detector-1", "detector not labelled")
  -- smoothed: a jump to 1500 shows up as a blend first, then settles
  d.rate = 1500
  T.waitFor(w, function() local x = mf.G.last.power.draw; return x > 600 and x < 1400 end, 10, "never saw a smoothed blend")
  w:run(15)
  T.truthy(math.abs(mf.G.last.power.draw - 1500) < 1, "never settled")
  T.contains(c.screen, "Draw")
  T.contains(c.screen, "FE/t")
end)

T.test("operator power: no detector means no power record", function()
  local w = cc.world(); local net = w:net()
  local inP, outP = port(), port()
  local r = w:reactor{ stored = 200000, active = true, inPort = inP, outPort = outP }
  net:add("BigReactors-Reactor_0", r); net:add("port_in", inP); net:add("port_out", outP)
  local mf = listener(w)
  local c = plant(w, net); c:run("operator")
  w:run(15)
  T.truthy(mf.G.last, "no status")
  T.eq(mf.G.last.power, nil)
end)

T.test("operator power: an idle reactor keeps its full-power figure; forced off or disabled counts for nothing", function()
  local w = cc.world(); local net = w:net()
  local inP, outP = port(), port()
  inP:give("mekanism:ingot_uranium", 10)
  local r = w:reactor{ stored = 200000, active = true, prod = 2000, rodScale = true, rodLevel = 50, rods = 4, inPort = inP, outPort = outP }
  net:add("BigReactors-Reactor_0", r); net:add("port_in", inP); net:add("port_out", outP)
  net:add("energy_detector_0", w:detector{ rate = 500 })
  local mf = listener(w)
  local c = plant(w, net); c:run("operator")
  w:run(15)
  T.truthy(mf.G.last.power.potential > 1900, "potential " .. tostring(mf.G.last.power.potential))
  -- Auto idles it (switched off on a full buffer): still counts at its last full-power figure
  r:setActive(false)
  w:run(10)
  T.truthy(mf.G.last.power.potential > 1900, "idle reactor dropped to " .. tostring(mf.G.last.power.potential))
  -- forced off by hand: counts for nothing
  local cfg = c:readTable("operator.cfg")
  cfg.units["BigReactors-Reactor_0"].mode = "off"
  c:writeTable("operator.cfg", cfg)
  w:run(15)
  T.eq(mf.G.last.power.potential, 0)
end)

-- The breaker (#121) ---------------------------------------------------------------------------------------------
local function rig(opts)
  opts = opts or {}
  local w = cc.world(); local net = w:net()
  local inP, outP = port(), port()
  inP:give("mekanism:ingot_uranium", 10)
  local r = w:reactor{ stored = 200000, active = true, prod = 2000, rodScale = true, rodLevel = 50, rods = 4, inPort = inP, outPort = outP }
  net:add("BigReactors-Reactor_0", r); net:add("port_in", inP); net:add("port_out", outP)
  local d = net:add("energy_detector_0", w:detector{ rate = 500 })
  local mf = listener(w)
  local c = plant(w, net); c:run("operator")
  w:run(15)
  return w, c, d, mf, net
end
local function cmd(w, mf, body)
  local s = w:computer{ id = 30, label = "Sender" }
  s:attach("top", cc.wireless{ ender = true })
  s:writeFile("send.lua", "rednet.open('top'); rednet.broadcast(" .. body .. ", 'tanis-operator')")
  s:run("send"); w:run(4)
end

T.test("operator breaker: a surge under SURGE_FOR does not trip", function()
  local w, c, d, mf = rig()
  d.rate = 3500                                  -- about 175% of 2000
  w:run(6)
  d.rate = 500
  w:run(20)
  T.eq(mf.G.last.power.limit, nil)
  T.eq(d.limit, 1000000000)
end)

T.test("operator breaker: a sustained surge trips, caps at 90%, and stays tripped when the draw drops", function()
  local w, c, d, mf = rig()
  d.rate = 3500
  w:run(25)
  local p = mf.G.last.power
  T.truthy(p.limit, "never tripped")
  T.truthy(p.limit > 1700 and p.limit <= 1900, "limit " .. tostring(p.limit))
  T.truthy(math.abs(d.limit - p.limit) <= 1, "detector limit " .. tostring(d.limit))
  T.truthy(p.asked > 3000, "asked " .. tostring(p.asked))
  T.truthy(p.askedFor and p.askedFor >= 0, "askedFor")
  T.truthy(c:readTable("operator.cfg").breaker.tripped, "not saved")
  local before = p.askedFor
  d.rate = 100                                   -- demand falls: still tripped, it never lifts itself
  w:run(60)
  T.truthy(mf.G.last.power.limit, "lifted by itself")
  T.truthy(mf.G.last.power.askedFor > before + 40, "askedFor not growing")
  T.truthy(d.limit < 1000000, "detector uncapped")
end)

T.test("operator breaker: a reboot keeps it tripped; Reset (operator_cmd) lifts it to the max", function()
  local w, c, d, mf = rig()
  d.rate = 3500
  w:run(25)
  T.truthy(mf.G.last.power.limit, "never tripped")
  d.rate = 100
  d.limit = 777                                 -- a stale limit would be wrong either way
  c:reboot(); c:run("operator"); w:run(20)
  T.truthy(mf.G.last.power.limit, "reboot cleared the trip")
  T.truthy(d.limit < 1000000, "detector uncapped by the reboot")
  cmd(w, mf, "{ type = 'operator_cmd', power = 'reset' }")
  w:run(6)
  T.eq(mf.G.last.power.limit, nil)
  T.eq(d.limit, 1000000000)
  T.eq(c:readTable("operator.cfg").breaker, nil)
  d.rate = 100; w:run(30)
  T.eq(d.limit, 1000000000)                      -- and it stays lifted at low draw
end)

T.test("operator breaker: the /reset command and a limit left on at boot", function()
  local w, c, d, mf = rig()
  d.limit = 777                                  -- someone left a cap on the detector
  w:run(8)
  T.eq(d.limit, 1000000000)
  d.rate = 3500; w:run(25)
  T.truthy(mf.G.last.power.limit, "never tripped")
  c:type("/reset"); w:run(0.3); c:key(require("sim.env").keys.enter); w:run(5)
  T.eq(mf.G.last.power.limit, nil)
  T.eq(d.limit, 1000000000)
end)

T.test("operator breaker: potential 0 never trips", function()
  local w, c, d, mf = rig()
  local cfg = c:readTable("operator.cfg")
  cfg.units["BigReactors-Reactor_0"].mode = "off"
  c:writeTable("operator.cfg", cfg)
  w:run(10)
  T.eq(mf.G.last.power.potential, 0)
  d.rate = 50000; w:run(40)
  T.eq(mf.G.last.power.limit, nil)
  T.eq(d.limit, 1000000000)
end)
