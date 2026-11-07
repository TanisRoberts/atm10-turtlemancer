-- Calibrate (issue #134): a run on a ramping reactor settles, saves maxOutput and restores mode and level; the figure
-- survives a reboot with the reactor idle; each abort; the estimate fallback; the breaker is left alone.
local cc = require("sim.cc")
local T  = require("sim.test")

local PORT = { "bigreactors:reactoraccessport", "inventory" }
local function mainframe(w)
  local m = w:computer{ id = 9, label = "Mainframe" }
  m:attach("top", cc.wireless{ ender = true })
  m:writeFile("mon.lua", [[
    rednet.open("top"); _G.last = nil
    while true do local _, m = rednet.receive("tanis-operator"); if m.type == "operator" then _G.last = m end end]])
  m:run("mon")
  return m
end
local function ser(t)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = ("%s=%s"):format(k, type(v) == "string" and ("%q"):format(v) or tostring(v)) end
  return "{" .. table.concat(out, ",") .. "}"
end
local function send(w, msg)
  w.chatN = (w.chatN or 0) + 1
  local m = w:computer{ id = 20 + w.chatN, label = "Chat" .. w.chatN }
  m:attach("top", cc.wireless{ ender = true })
  m:writeFile("cmd.lua", "rednet.open('top'); rednet.broadcast(" .. ser(msg) .. ", 'tanis-operator')")
  m:run("cmd")
  w:run(3)
end
local function setup(opts, env, cfg)
  local w = cc.world(); local net = w:net()
  opts.rodScale = true
  opts.fuel = opts.fuel or 4000
  local r = w:reactor(opts)
  net:add("BigReactors-Reactor_0", r)
  local d = net:add("energy_detector_0", w:detector{ rate = opts.draw or 0 })
  local mf = mainframe(w)
  local c = w:computer{ id = 5, label = "Operator" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:installRole("operator")
  c:writeFile("operator.env", "SETUP_WIZARD=no\nSTATUS_EVERY=1\nRODS=off\n" .. (env or ""))
  if cfg then c:writeFile("operator.cfg", cfg) end
  return w, net, r, mf, c, d
end
local function unit(mf) return mf.G.last.units[1] end

T.test("calibrate: a ramping reactor settles, maxOutput is saved, mode and level come back", function()
  local w, _, r, mf, c = setup{ stored = 400000, active = true, prod = 12400, demand = 14000, rodLevel = 50, ramp = 20, heat = 1 }
  c:run("operator"); w:run(10)
  r.heat = 0.1                                  -- cold core: output is climbing when the run starts
  send(w, { type = "operator_cmd", calibrate = true })
  w:run(10)
  T.truthy(unit(mf).calibrating, "not calibrating")
  T.eq(r.rodLevel, 0, "rods should be fully out")
  T.truthy(unit(mf).calibrating.fe > 0, "no running figure")
  T.waitFor(w, function() return not unit(mf).calibrating end, 600, "never finished")
  local cfg = c:readTable("operator.cfg")
  local saved = cfg.units["BigReactors-Reactor_0"].maxOutput
  T.truthy(saved and math.abs(saved - 12400) <= 12400 * 0.02, "saved " .. tostring(saved))
  T.truthy(cfg.units["BigReactors-Reactor_0"].maxAt, "no date")
  T.eq(r.rodLevel, 50, "level not restored")
  T.eq(r.on, true, "run state not restored")
  T.eq(unit(mf).maxOutput, saved)
  T.eq(unit(mf).calibrating, false)
  T.truthy(c:readFile("operator.log"):find("calibration done", 1, true), "no log line")
end)

T.test("calibrate: a ramp that has not levelled off is not taken as settled", function()
  local w, _, r, mf, c = setup{ stored = 400000, active = true, prod = 12400, demand = 14000, rodLevel = 50, ramp = 200, heat = 0 }
  c:run("operator"); w:run(5)
  send(w, { type = "operator_cmd", calibrate = true })
  w:run(120)
  T.truthy(unit(mf).calibrating, "settled while still climbing steeply")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].maxOutput, nil)
end)

T.test("calibrate: the figure survives a reboot with the reactor idle, and potential uses it at once", function()
  local cfg = "{ nextNum = { reactor = 1 }, units = { [\"BigReactors-Reactor_0\"] = { kind = \"reactor\", num = 1, label = \"Reactor-1\", mode = \"auto\", enabled = true, maxOutput = 8000, maxAt = \"2026-11-07\" } }, plant = {} }"
  local w, _, r, mf, c = setup({ stored = 950000, active = false, prod = 12400, demand = 100, draw = 4000 }, "", cfg)
  c:run("operator"); w:run(15)
  local p = mf.G.last.power
  T.eq(p.potential, 8000)
  T.truthy(math.abs(p.pct - 50) < 1, "pct " .. tostring(p.pct))
  T.eq(p.estimated, nil)
  T.eq(unit(mf).maxOutput, 8000)
  T.contains(c.screen, "FE/t")
end)

T.test("calibrate: without a figure the potential is an estimate, flagged", function()
  local w, _, r, mf, c = setup{ stored = 400000, active = true, prod = 2000, demand = 1000, rodLevel = 50, draw = 500 }
  c:run("operator"); w:run(15)
  T.eq(mf.G.last.power.estimated, true)
  T.eq(unit(mf).maxOutput, nil)
  T.truthy(mf.G.last.power.potential > 1900, "estimate " .. tostring(mf.G.last.power.potential))
  T.contains(c.screen, "est.")
end)

local function aborted(w, mf, c, why)
  T.waitFor(w, function() return not unit(mf).calibrating and unit(mf).calMsg end, 700, "never stopped")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].maxOutput, nil, "a figure was saved")
  T.contains(c:readFile("operator.log"), why)
end

T.test("calibrate: aborts when the buffer fills before it settles; mode and level come back", function()
  local w, _, r, mf, c = setup{ stored = 900000, active = true, prod = 12400, demand = 100, rodLevel = 50, ramp = 60, heat = 0.3, cap = 1000000 }
  c:run("operator"); w:run(5)
  send(w, { type = "operator_cmd", calibrate = true })
  aborted(w, mf, c, "batteries have room")
  T.eq(r.rodLevel, 50)
end)

T.test("calibrate: will not start with the buffer already full", function()
  local w, _, r, mf, c = setup{ stored = 990000, active = true, prod = 12400, demand = 100, rodLevel = 50 }
  c:run("operator"); w:run(5)
  send(w, { type = "operator_cmd", calibrate = true })
  w:run(5)
  T.eq(unit(mf).calibrating, false)
  T.eq(r.rodLevel, 50)
  T.contains(c:readFile("operator.log"), "batteries have room")
end)

T.test("calibrate: gives up after CAL_MAX_MIN and keeps the old figure", function()
  local w, _, r, mf, c = setup({ stored = 300000, active = true, prod = 12400, demand = 14000, rodLevel = 50, ramp = 5000, heat = 0 }, "CAL_MAX_MIN=1\n")
  c:run("operator"); w:run(5)
  send(w, { type = "operator_cmd", calibrate = true })
  aborted(w, mf, c, "longer than 1 min")
  T.eq(r.rodLevel, 50)
end)

T.test("calibrate: Cancel stops it and puts everything back", function()
  local w, _, r, mf, c = setup{ stored = 300000, active = false, prod = 12400, demand = 14000, rodLevel = 70, ramp = 100, heat = 0 }
  c:run("operator"); w:run(5)
  send(w, { type = "operator_cmd", calibrate = true })
  w:run(10)
  T.truthy(unit(mf).calibrating, "not running")
  T.eq(r.on, true)
  send(w, { type = "operator_cmd", calibrate = false })
  w:run(4)
  T.eq(unit(mf).calibrating, false)
  T.eq(r.rodLevel, 70)
  T.contains(c:readFile("operator.log"), "cancelled")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].maxOutput, nil)
end)

T.test("calibrate: the reactor going quiet aborts the run", function()
  local w, net, r, mf, c = setup{ stored = 300000, active = true, prod = 12400, demand = 14000, rodLevel = 50, ramp = 100, heat = 0 }
  c:run("operator"); w:run(5)
  send(w, { type = "operator_cmd", calibrate = true })
  w:run(10)
  net:remove("BigReactors-Reactor_0")
  w:run(40)
  T.contains(c:readFile("operator.log"), "stopped answering")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].maxOutput, nil)
end)

T.test("calibrate: a run does not trip the breaker, and a typed /calibrate starts one", function()
  local w, _, r, mf, c = setup{ stored = 400000, active = true, prod = 12400, demand = 14000, rodLevel = 50, ramp = 20, heat = 1, draw = 2900 }
  c:run("operator"); w:run(10)
  T.eq(mf.G.last.power.limit, nil)
  c:type("/calibrate"); w:run(0.3); c:key(require("sim.env").keys.enter); w:run(12)
  T.truthy(unit(mf).calibrating, "typed calibrate did not start")
  w:run(60)
  T.eq(mf.G.last.power.limit, nil, "breaker tripped during the run")
  T.eq(c:readTable("operator.cfg").breaker, nil)
end)

T.test("calibrate: the Power tab shows the figure and a Calibrate button that needs two taps, then Cancel", function()
  local w, _, r, mf, c = setup{ stored = 400000, active = true, prod = 12400, demand = 14000, rodLevel = 50, ramp = 100, heat = 0.5 }
  c:run("operator"); w:run(10)
  local function pos(text)
    for y = 1, c.screen.h do
      local line, last = c.screen:line(y), nil
      local from = 1
      while true do local x = line:find(text, from, true); if not x then break end; last = x; from = x + 1 end
      if last then return last + 1, y end
    end
    error("not on screen: " .. text .. "\n" .. c.screen:text())
  end
  local function tap(text) local x, y = pos(text); c:click(x, y); w:run(0.6) end
  tap("Reactor-1")
  T.contains(c.screen, "estimated")
  tap("Calibrate")
  T.eq(unit(mf).calibrating, false, "one tap should only ask")
  T.contains(c.screen, "Sure?")
  tap("Sure?"); w:run(3)
  T.truthy(unit(mf).calibrating, "two taps did not start it\n" .. c.screen:text())
  T.contains(c.screen, "Cancel")
  T.contains(c.screen, "FE/t")
  tap("Cancel"); w:run(3)
  T.eq(unit(mf).calibrating, false)
  T.eq(r.rodLevel, 50)
end)

T.test("calibrate: a tall screen shows the full lines (calibrated date, Calibrating, settling)", function()
  local w, net, r, mf, c = setup{ stored = 400000, active = true, prod = 12400, demand = 14000, rodLevel = 50, ramp = 100, heat = 0.5 }
  local mon = c:monitor("right", 80, 30)
  c:run("operator"); w:run(10)
  local function find(text)
    for y = 1, mon.h do local x = mon:line(y):find(text, 1, true); if x then return x + 1, y end end
  end
  local x, y = find("Reactor-1"); mon:touch(x, y); w:run(0.6)
  T.contains(mon, "Max output")
  T.contains(mon, "estimated, tap Calibrate")
  send(w, { type = "operator_cmd", calibrate = true }); w:run(5)
  T.contains(mon, "Calibrating:")
  T.contains(mon, "settling")
  T.contains(mon, "Running")
  send(w, { type = "operator_cmd", calibrate = false }); w:run(3)
  r.heat = 1; r.ramp = nil
  send(w, { type = "operator_cmd", calibrate = true }); w:run(60)
  T.contains(mon, "calibrated")
end)
