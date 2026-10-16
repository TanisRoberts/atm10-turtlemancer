-- The Operator on a simulated reactor cable: hysteresis, waste, a full barrel, two reactors, needs/has/missing.
local cc = require("sim.cc")
local T  = require("sim.test")

local PORT = { "bigreactors:reactoraccessport", "inventory" }
local function port() return cc.Inv.new{ size = 9, types = PORT } end
local function barrel() return cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } } end

-- opts.status: collect radio messages on a mainframe stand-in
local function plant(w, net, opts)
  opts = opts or {}
  local c = w:computer{ id = 5, label = "Operator" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:installRole("operator")
  c:writeFile("operator.env", "SETUP_WIZARD=no\n")      -- these scenarios are about the control loop, not the wizard
  c:writeFile("mon.lua", [[
    rednet.open("top"); _G.last, _G.beats = nil, 0
    while true do local _, m = rednet.receive("tanis-operator"); _G.last = m; _G.beats = _G.beats + 1 end]])
  return c
end
local function listener(w)
  local m = w:computer{ id = 9, label = "Mainframe" }
  m:attach("top", cc.wireless{ ender = true })
  m:writeFile("mon.lua", [[
    rednet.open("top"); _G.last, _G.beats = nil, 0
    while true do local _, m = rednet.receive("tanis-operator"); if m.type == "operator" then _G.last = m; _G.beats = _G.beats + 1 end end]])
  m:run("mon")
  return m
end
-- Storage stand-in on the same cable: drains the outlet port into a chest; reports its uranium count.
-- opts.drain = false leaves the outlet alone; opts.supply = n reports n uranium.
local function storage(w, net, outName, opts)
  opts = opts or {}
  local chest = net:add("minecraft:chest_9", cc.Inv.new{ size = 54 })
  local c = w:computer{ id = 7, label = "Storage" }
  c:attach("back", cc.wired(net)); c:attach("top", cc.wireless{ ender = true })
  c:writeFile("st.lua", ("local out, drain, supply = %q, %s, %s\nrednet.open('top')\nwhile true do\n"
    .. "  if drain then local o = peripheral.wrap(out); for slot in pairs(o.list()) do o.pushItems('minecraft:chest_9', slot) end end\n"
    .. "  if supply then rednet.broadcast({ type = 'uranium', total = supply }, 'tanis-operator') end\n  sleep(1)\nend")
    :format(outName, tostring(opts.drain ~= false), tostring(opts.supply)))
  c:run("st")
  return chest
end
local function unit(rec, label) for _, u in ipairs(rec.units) do if u.label == label then return u end end end
local function need(u, key) for _, n in ipairs(u.needs or {}) do if n.key == key then return n end end end

T.test("operator: on below 30%, off above 90%, hysteresis in between", function()
  local w, net = cc.world(), nil
  net = w:net()
  local inP, outP = port(), port()
  inP:give("mekanism:ingot_uranium", 10)
  local r = w:reactor{ stored = 200000, inPort = inP, outPort = outP }       -- 20%: should switch on
  net:add("BigReactors-Reactor_0", r); net:add("port_in", inP); net:add("port_out", outP)
  storage(w, net, "port_out")
  local mf = listener(w)
  local c = plant(w, net)
  c:run("operator")
  T.waitFor(w, function() return r.on end, 20, "never switched on at 20%")
  -- keeps running through the band, switches off above 90%
  T.waitFor(w, function() return not r.on end, 120, "never switched off above 90%")
  T.truthy(r.stored / r.cap > 0.9, "off too early")
  -- falls back through the band without switching on until below 30%
  w:run(20)
  T.truthy(not r.on, "switched on inside the band")
  T.waitFor(w, function() return r.on end, 300, "never came back on below 30%")
  T.truthy(r.stored / r.cap < 0.31, "on too late")
  -- the mainframe hears a heartbeat with units and plant totals
  local rec = mf.env._G.last
  T.truthy(rec and rec.units and rec.plant, "no status at the mainframe")
  T.eq(rec.plant.reactors, 1)
  T.eq(rec.units[1].label, "Reactor-1")
  T.truthy(mf.env._G.beats >= 3, "no heartbeat")
  T.contains(c.screen, "Reactor-1")
end)

T.test("operator: ports are worked out, Storage drains the outlet, the Operator moves nothing", function()
  local w = cc.world(); local net = w:net()
  local inP, outP = port(), port()
  inP:give("mekanism:ingot_uranium", 20)
  local r = w:reactor{ stored = 100000, inPort = inP, outPort = outP }
  net:add("BigReactors-Reactor_0", r); net:add("port_a", inP); net:add("port_b", outP)
  local other = net:add("minecraft:chest_3", cc.Inv.new{ size = 27 })    -- Storage's own chest: ignored
  other:give("minecraft:iron_ingot", 40)
  net:add("minecraft:barrel_5", cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  local chest = storage(w, net, "port_b", { supply = 500 })
  local mf = listener(w)
  local c = plant(w, net); c:run("operator")
  T.waitFor(w, function() return chest:count("bigreactors:cyanite_ingot") >= 2 end, 120, "Storage never got the waste")
  w:run(6)
  local u = unit(mf.env._G.last, "Reactor-1")
  T.truthy(u.fuel and u.fuel > 0, "no fuel reading")
  T.truthy(u.uranium ~= nil and u.uranium < 20, "uranium in the inlet not reported")
  T.eq(u.wasteStuck, false)
  T.eq(need(u, "fuelIn").state, "ok")
  T.eq(need(u, "wasteOut").state, "ok")
  T.eq(need(u, "wasteTo").state, "ok")
  T.eq(mf.env._G.last.plant.supply, 500)
  local log = c:readFile("operator.log")
  T.truthy(log:find("port_a", 1, true), "ports not logged")
  T.truthy(log:find("minecraft:chest_3", 1, true), "first boot must list every peripheral and its type")
  T.truthy(log:find("bigreactors:reactoraccessport", 1, true), "port types not logged")
  T.eq(other:count("minecraft:iron_ingot"), 40, "touched Storage's chest")
  T.eq(inP:count("mekanism:ingot_uranium") + 0 <= 20, true)
  local cfg = c:readTable("operator.cfg")
  T.eq(cfg.units["BigReactors-Reactor_0"].input, "port_a")
  T.eq(cfg.units["BigReactors-Reactor_0"].output, "port_b")
  T.eq(cfg.units["minecraft:chest_3"], nil, "a chest became a unit")
end)

T.test("operator: an outlet that doesn't empty is reported, nothing is moved, and it never shuts down for low fuel", function()
  local w = cc.world(); local net = w:net()
  local inP, outP = port(), port()
  local r = w:reactor{ stored = 100000, inPort = inP, outPort = outP, fuel = 0 }   -- no uranium anywhere
  net:add("BigReactors-Reactor_0", r); net:add("port_in", inP); net:add("port_out", outP)
  outP:give("bigreactors:cyanite_ingot", 5)
  local mf = listener(w)                                                          -- no Storage on the cable
  local c = plant(w, net)
  c:writeTable("operator.cfg", { nextNum = { reactor = 1 }, units = { ["BigReactors-Reactor_0"] =
    { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true, input = "port_in", output = "port_out" } } })
  c:run("operator")
  w:run(15)
  local u = unit(mf.env._G.last, "Reactor-1")
  T.eq(u.wasteStuck, false, "reported too early")
  w:run(130)                                                                      -- cyanite sat there past STUCK_AFTER
  u = unit(mf.env._G.last, "Reactor-1")
  T.eq(u.wasteStuck, true)
  T.eq(u.note, "waste not clearing")
  T.eq(need(u, "wasteTo").state, "missing")
  T.truthy(outP:count("bigreactors:cyanite_ingot") >= 5, "waste was voided or moved")
  T.truthy(u.active == true, "reactor must still run with an empty fuel supply")
  T.eq(need(u, "fuel").state, "missing")
end)

T.test("operator: a completely full outlet is reported at once, and a draining one is not", function()
  local w = cc.world(); local net = w:net()
  local inP, outP = port(), cc.Inv.new{ size = 2, types = PORT }
  local r = w:reactor{ stored = 500000, inPort = inP, outPort = outP }
  net:add("BigReactors-Reactor_0", r); net:add("port_in", inP); net:add("port_out", outP)
  outP:give("bigreactors:cyanite_ingot", 128)                                     -- both slots full
  local mf = listener(w)
  local c = plant(w, net); c:run("operator")
  w:run(8)
  T.eq(unit(mf.env._G.last, "Reactor-1").wasteStuck, true)
end)

T.test("operator: two reactors on one cable each follow their own buffer", function()
  local w = cc.world(); local net = w:net()
  local i1, o1, i2, o2 = port(), port(), port(), port()
  i1:give("mekanism:ingot_uranium", 10); i2:give("mekanism:ingot_uranium", 10)
  local ra = w:reactor{ stored = 200000, inPort = i1, outPort = o1 }     -- 20%: on
  local rb = w:reactor{ stored = 950000, inPort = i2, outPort = o2, active = true }  -- 95%: off
  net:add("BigReactors-Reactor_0", ra); net:add("BigReactors-Reactor_1", rb)
  net:add("in_0", i1); net:add("out_0", o1); net:add("in_1", i2); net:add("out_1", o2)
  local chest = storage(w, net, "out_0")
  local mf = listener(w)
  local c = plant(w, net)
  c:writeTable("operator.cfg", { nextNum = { reactor = 2 }, units = {
    ["BigReactors-Reactor_0"] = { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true, input = "in_0", output = "out_0" },
    ["BigReactors-Reactor_1"] = { kind = "reactor", num = 2, label = "Reactor-2", mode = "auto", enabled = true, input = "in_1", output = "out_1", onBelow = 10 } } })
  c:run("operator")
  T.waitFor(w, function() return ra.on and not rb.on end, 20, "reactors didn't follow their own state")
  w:run(15)
  local rec = mf.env._G.last
  T.eq(rec.plant.reactors, 2)
  T.eq(unit(rec, "Reactor-1").active, true)
  T.eq(unit(rec, "Reactor-2").active, false)
  -- each reactor's own waste goes through its own port
  T.waitFor(w, function() return chest:count("bigreactors:cyanite_ingot") >= 1 end, 120, "reactor 1 waste never drained")
  -- Reactor-2 has its own, lower ON threshold (10%): at ~25% it stays off (the default 30% would switch it on)
  rb.stored = 300000
  w:run(3)
  T.truthy(not rb.on, "per-unit threshold ignored")
  -- manual override
  local cfg = c:readTable("operator.cfg")
  cfg.units["BigReactors-Reactor_1"].mode = "on"
  c:writeTable("operator.cfg", cfg)
  T.waitFor(w, function() return rb.on end, 20, "manual on ignored")
end)

T.test("operator: needs/has/missing for different reactors", function()
  local w = cc.world(); local net = w:net()
  -- A: no ports at all
  local ra = w:reactor{ stored = 500000 }
  -- B: actively cooled, no turbine, can't read rods or temperatures
  local rb = w:reactor{ stored = 500000, activelyCooled = true, without = { "getControlRodLevel", "getNumberOfControlRods", "getFuelTemperature" } }
  net:add("BigReactors-Reactor_0", ra); net:add("BigReactors-Reactor_1", rb)
  local mf = listener(w)
  local c = plant(w, net); c:run("operator")
  w:run(12)
  local a, b = unit(mf.env._G.last, "Reactor-1"), unit(mf.env._G.last, "Reactor-2")
  T.eq(a.driver, "passive"); T.eq(b.driver, "active")
  T.eq(need(a, "computer").state, "ok")
  T.eq(need(a, "fuelIn").state, "unknown")
  T.eq(need(a, "wasteOut").state, "unknown")
  T.eq(need(a, "wasteTo").state, "unknown")
  T.eq(need(a, "turbine").state, "na")
  T.eq(need(b, "turbine").state, "missing")
  T.eq(need(b, "turbine").why, "no turbine on the cable")
  T.eq(need(b, "rods").state, "unknown")
  T.eq(need(b, "ftemp").state, "unknown")
  T.truthy(a.active ~= nil and b.active ~= nil, "reactors should still be controlled")
  -- a turbine appears: the check is redone when the cable changes
  net:add("BigReactors-Turbine_0", cc.Inv.new{ size = 1, types = { "BigReactors-Turbine" } })
  w:run(8)
  T.eq(need(unit(mf.env._G.last, "Reactor-2"), "turbine").state, "ok")
  T.contains(c.screen, "Turbine-1")
end)

T.test("operator: a reactor that goes silent is reported, and nothing crashes", function()
  local w = cc.world(); local net = w:net()
  local r = w:reactor{ stored = 500000, without = { "getActive", "getEnergyStored", "getEnergyCapacity" } }
  net:add("BigReactors-Reactor_0", r)
  local mf = listener(w)
  local c = plant(w, net); c:run("operator")
  w:run(10)
  T.eq(c.error, nil)
  local u = unit(mf.env._G.last, "Reactor-1")
  T.eq(u.answers, false)
  T.eq(need(u, "computer").state, "missing")
  net:remove("BigReactors-Reactor_0")
  w:run(8)
  T.eq(unit(mf.env._G.last, "Reactor-1").present, false)
  T.eq(c.error, nil)
end)

T.test("operator: machines that merely have an energy buffer are not plant units, and old Storage-N entries go", function()
  local w = cc.world(); local net = w:net()
  local r = w:reactor{ stored = 500000 }
  net:add("BigReactors-Reactor_0", r)
  for i = 1, 5 do net:add("ironfurnaces:emerald_furnace_" .. i, cc.Inv.new{ size = 3, types = { "ironfurnaces:emerald_furnace", "inventory", "energy_storage" } }) end
  local mf = listener(w)
  local c = plant(w, net)
  c:writeTable("operator.cfg", { nextNum = { reactor = 1, storage = 5 }, units = {
    ["BigReactors-Reactor_0"] = { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true },
    ["ironfurnaces:emerald_furnace_1"] = { kind = "storage", num = 1, label = "Storage-1", mode = "auto", enabled = true } } })
  c:run("operator")
  w:run(12)
  T.eq(#mf.env._G.last.units, 1, "only the reactor is a unit")
  T.falsy(c.screen:find("(storage)", 1, true), c.screen:text())
  local cfg = c:readTable("operator.cfg")
  T.eq(cfg.units["ironfurnaces:emerald_furnace_1"], nil)
  T.eq(cfg.nextNum.storage, nil)
end)
