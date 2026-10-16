-- The Operator's control rods: the level follows the buffer in steps, holds, limits, and no rods at all.
local cc = require("sim.cc")
local T  = require("sim.test")

local PORT = { "bigreactors:reactoraccessport", "inventory" }

local function plant(w, net)
  local c = w:computer{ id = 5, label = "Operator" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:installRole("operator")
  return c
end
local function mainframe(w)
  local m = w:computer{ id = 9, label = "Mainframe" }
  m:attach("top", cc.wireless{ ender = true })
  m:writeFile("mon.lua", [[
    rednet.open("top"); _G.last = nil
    while true do local _, m = rednet.receive("tanis-operator"); if m.type == "operator" then _G.last = m end end]])
  m:run("mon")
  return m
end
local function send(w, msg)
  w.chatN = (w.chatN or 0) + 1
  local m = w:computer{ id = 20 + w.chatN, label = "Chat" .. w.chatN }
  m:attach("top", cc.wireless{ ender = true })
  m:writeFile("cmd.lua", "rednet.open('top'); rednet.broadcast(" .. textutils_ser(msg) .. ", 'tanis-operator')")
  m:run("cmd")
  w:run(3)
end
function textutils_ser(t)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = ("%s=%s"):format(k, type(v) == "string" and ("%q"):format(v) or tostring(v)) end
  return "{" .. table.concat(out, ",") .. "}"
end
local function level(r) return 100 - r.rodLevel end
-- run `secs` one second at a time, and note each time the rods moved: { {t, level}, ... }
local function watch(w, r, secs)
  local seen, last, t = {}, r.rodLevel, 0
  for _ = 1, secs do
    w:run(1); t = t + 1
    if r.rodLevel ~= last then seen[#seen + 1] = { t = t, level = level(r), jump = math.abs(r.rodLevel - last) }; last = r.rodLevel end
  end
  return seen
end
local function setup(opts)
  local w = cc.world(); local net = w:net()
  opts.rodScale = true
  opts.fuel = opts.fuel or 4000
  local r = w:reactor(opts)
  net:add("BigReactors-Reactor_0", r)
  local mf = mainframe(w)
  local c = plant(w, net)
  return w, net, r, mf, c
end

T.test("operator rods: a draining buffer takes the rods out in steps, no faster than every 5 s", function()
  local w, _, r, mf, c = setup{ stored = 250000, active = true, prod = 3000, demand = 2000, rodLevel = 90 }   -- 25%, level 10
  c:run("operator")
  local seen = watch(w, r, 90)
  T.truthy(#seen >= 3, "rods never moved")
  local prev = 0
  for _, s in ipairs(seen) do
    T.truthy(s.jump <= 10, "step bigger than ROD_STEP: " .. s.jump)
    T.truthy(s.t - prev >= 5 or prev == 0, "steps closer than ROD_EVERY")
    prev = s.t
  end
  local top = 0
  for _, s in ipairs(seen) do top = math.max(top, s.level) end
  T.eq(top, 100, "should reach full power while the buffer is below the ON threshold")
  T.eq(seen[1].level, 20)
  T.eq(mf.env._G.last.units[1].rodCount, 5)
end)

T.test("operator rods: a filling buffer takes them in, and at steady load they stop moving", function()
  local w, _, r, mf, c = setup{ stored = 800000, active = true, prod = 3000, demand = 1000, rodLevel = 0 }   -- 80%, level 100
  c:run("operator")
  local seen = watch(w, r, 100)
  T.truthy(#seen >= 2, "rods never moved in")
  T.truthy(level(r) < 100 and level(r) >= 10, "level not between the limits")
  T.eq(mf.env._G.last.units[1].levelWhy, "buffer filling")
  T.truthy(r.on, "reactor must stay on inside the band")
  -- settled around the load (33% of 3000 FE/t = 1000): the level only drifts inside the LEVEL_BAND, a few
  -- small steps, never a swing
  w:run(200)
  local later = watch(w, r, 300)
  for _, s in ipairs(later) do
    T.truthy(s.level >= 26 and s.level <= 40, "level swings at steady load: " .. s.level)
    T.truthy(s.jump <= 5, "big step at steady load: " .. s.jump)
  end
  T.truthy(#later <= 8, "rods hunting at steady load: " .. #later .. " moves in 5 minutes")
end)

T.test("operator rods: off keeps the last level, switching on does not reset it", function()
  local w, _, r, mf, c = setup{ stored = 950000, active = true, prod = 3000, demand = 500, rodLevel = 70 }   -- 95%: off
  c:run("operator")
  w:run(10)
  T.truthy(not r.on, "should be off")
  T.eq(level(r), 30, "rods moved while off")
  r.stored = 100000                                                  -- drained: back on
  T.waitFor(w, function() return r.on end, 20, "never switched on")
  T.eq(level(r) >= 30, true)
end)

T.test("operator rods: a manual level in operator.cfg, and the lowest and highest limits", function()
  local w, _, r, mf, c = setup{ stored = 500000, active = true, prod = 3000, demand = 2000, rodLevel = 100 }
  c:writeTable("operator.cfg", { nextNum = { reactor = 1 }, units = { ["BigReactors-Reactor_0"] =
    { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true, level = 60 } } })
  c:run("operator")
  w:run(8)
  T.eq(level(r), 60)
  T.eq(mf.env._G.last.units[1].levelWhy, "manual")
  -- limits: lowest 40, highest 80, buffer low wants full power
  local w2, _, r2, mf2, c2 = setup{ stored = 100000, active = true, prod = 3000, demand = 2000, rodLevel = 100 }
  c2:writeTable("operator.cfg", { nextNum = { reactor = 1 }, units = { ["BigReactors-Reactor_0"] =
    { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true, levelMin = 40, levelMax = 80 } } })
  c2:run("operator")
  w2:run(60)
  T.eq(level(r2), 80)
end)

T.test("operator rods: a level from the mainframe holds, then Auto takes over after 10 minutes", function()
  local w, _, r, mf, c = setup{ stored = 600000, active = true, prod = 3000, demand = 1500, rodLevel = 50 }
  c:run("operator")
  w:run(10)
  send(w, { type = "operator_cmd", level = 80 })
  w:run(4)
  T.eq(level(r), 80)
  local u = mf.env._G.last.units[1]
  T.eq(u.mode, "on"); T.truthy(u.holdLeft and u.holdLeft > 500, "no hold countdown")
  w:run(560)
  T.eq(level(r), 80, "hold ended early")
  w:run(60)
  u = mf.env._G.last.units[1]
  T.eq(u.mode, "auto"); T.eq(u.holdLeft, nil)
  T.truthy(c:readFile("operator.log"):find("back to Auto", 1, true), "hold end not logged")
  -- a mode command is saved
  send(w, { type = "operator_cmd", unit = "Reactor-1", mode = "off" })
  w:run(4)
  T.truthy(not r.on, "off command ignored")
  T.eq(c:readTable("operator.cfg").units["BigReactors-Reactor_0"].mode, "off")
end)

T.test("operator rods: a reactor with no rod methods, or RODS=off, is left alone and nothing crashes", function()
  local w, _, r, mf, c = setup{ stored = 200000, prod = 3000, demand = 2000,
    without = { "getControlRodLevel", "setAllControlRodLevels", "getNumberOfControlRods" } }
  c:run("operator")
  T.waitFor(w, function() return r.on end, 20, "never switched on")
  w:run(20)
  T.eq(c.error, nil)
  T.eq(mf.env._G.last.units[1].level, nil)
  local w2, _, r2, _, c2 = setup{ stored = 200000, active = true, prod = 3000, demand = 2000, rodLevel = 90 }
  c2:writeFile("operator.env", "RODS=off\n")
  c2:run("operator")
  w2:run(40)
  T.eq(r2.rodLevel, 90, "RODS=off must leave the rods")
end)
