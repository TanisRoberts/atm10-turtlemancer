-- opcal.lua  --  Calibrate (issue #134): measure a reactor's true full-power output and keep it as `maxOutput`.
-- A run forces the reactor ON with the rods fully out (level 100), samples getEnergyProducedLastTick once a pass and
-- is SETTLED when the output has not risen more than CAL_SETTLE_PCT % over the last CAL_SETTLE_S seconds. The rounded
-- figure goes in the reactor's operator.cfg entry (`maxOutput`, `maxAt` = "YYYY-MM-DD"), then the run state and the rods go
-- back as they were. Auto and the rod stepping skip a unit while `u.cal` is set (operator.lua). Aborts, keeping the
-- old figure: the reactor stops answering, its buffer reaches CAL_BUF_MAX %, CAL_MAX_MIN minutes pass, or Cancel.
-- While it runs the breaker's potential for the unit stays at what it was (oppower.lua), so a ramp can't trip it.
local ui = require("ui")
local C = {}

local function num(v, d) return tonumber(v) or d end
local function tryRestore(u, c)
  local d = u.driver
  if not d then return end
  if c.prevLevel and d:has("setAllControlRodLevels") then d:setOutput(100 - c.prevLevel); u.level = c.prevLevel end
  if c.prevActive ~= nil then d:setActive(c.prevActive) end
  u.lastRod = os.clock()
end

local function today()
  local ok, s = pcall(os.date, "%Y-%m-%d")
  return ok and s or nil
end

-- Why a run can't start (a text), or nil.
function C.refuse(u, E)
  if not (u and u.kind == "reactor") then return "no such reactor" end
  if u.cal then return "already calibrating" end
  if u.awaiting then return "finish its setup first" end
  if u.cfg.enabled == false then return "it is disabled" end
  if u.cfg.manage == false then return "the Operator is not running it" end
  if not (u.present and u.driver and u.status and u.status.answers) then return "the reactor is not answering" end
  if not u.driver:has("setActive") then return "the reactor can't be switched" end
  local buf = u.status.buf
  if buf and buf * 100 >= num(E.CAL_BUF_MAX, 95) then return "run it when the batteries have room" end
end

function C.running(u) return u.cal ~= nil end

-- Start. Returns true, or false and why.
function C.start(u, now, E, hooks)
  local why = C.refuse(u, E)
  if why then
    if u and u.label and hooks.log then hooks.log(u.label .. ": calibration not started: " .. why) end
    return false, why
  end
  local s = u.status
  local pot = tonumber(u.cfg.maxOutput) or u.potential or 0
  u.cal = { t0 = now, prevActive = s.active, prevLevel = u.level or s.level, samples = {}, pot = pot, fe = s.fe or 0 }
  u.driver:setActive(true)
  if u.driver:has("setAllControlRodLevels") then u.driver:setOutput(0); u.level, u.lastRod = 100, now end
  if hooks.log then hooks.log(u.label .. ": calibration started (rods out, forced on)") end
  if hooks.event then hooks.event(u.label, "calibrating") end
  return true
end

local function finish(u, now, hooks, ok, text)
  local c = u.cal
  tryRestore(u, c)
  if u.hold then u.hold.untilT = u.hold.untilT + (now - c.t0) end     -- the time spent calibrating isn't taken off a hold
  u.cal = nil
  u.calMsg = { text = text, ok = ok, at = now }
  local took = math.floor(now - c.t0 + 0.5)
  if hooks.log then hooks.log(("%s: calibration %s (%s, took %d s)"):format(u.label, ok and "done" or "stopped", text, took)) end
  if hooks.event then hooks.event(u.label, ok and "calibrated" or "calibration stopped") end
  ui.say(u.label .. ": " .. text, ok and "good" or "warn")
  if hooks.dirty then hooks.dirty() end
end

-- Cancel a run (Cancel button, /calibrate cancel). Returns true when one was running.
function C.cancel(u, now, hooks)
  if not u.cal then return false end
  finish(u, now, hooks, false, "calibration cancelled, old figure kept")
  return true
end

-- One pass for a calibrating unit (after its status was read).
function C.step(u, now, E, hooks, save)
  local c = u.cal
  if not c then return end
  local s = u.status or {}
  if not (u.present and u.driver and s.answers) then
    return finish(u, now, hooks, false, "the reactor stopped answering, old figure kept")
  end
  if s.buf and s.buf * 100 >= num(E.CAL_BUF_MAX, 95) then
    return finish(u, now, hooks, false, "buffer full before it settled: run it when the batteries have room")
  end
  if now - c.t0 >= num(E.CAL_MAX_MIN, 10) * 60 then
    return finish(u, now, hooks, false, "took longer than " .. num(E.CAL_MAX_MIN, 10) .. " min, old figure kept")
  end
  -- hold it at full: ON, rods out (something else may have switched it)
  if s.active == false then u.driver:setActive(true) end
  if s.level and s.level ~= 100 and u.driver:has("setAllControlRodLevels") then u.driver:setOutput(0); u.level = 100 end
  local fe = s.fe
  if type(fe) ~= "number" then return end
  c.fe = fe
  local sm = c.samples
  sm[#sm + 1] = { t = now, v = fe }
  local win = num(E.CAL_SETTLE_S, 30)
  while #sm >= 2 and sm[2].t <= now - win do table.remove(sm, 1) end
  if s.active and fe > 0 and sm[1].t <= now - win and fe <= sm[1].v * (1 + num(E.CAL_SETTLE_PCT, 0.5) / 100) then
    local max = math.floor(fe + 0.5)
    u.cfg.maxOutput, u.cfg.maxAt = max, today()
    u.potential = max
    if save then save() end
    finish(u, now, hooks, true, ("max output %d FE/t"):format(max))
  end
end

-- What the screens say: { fe, elapsed } while running, else nil.
function C.progress(u, now)
  local c = u.cal
  if c then return { fe = c.fe, elapsed = now - c.t0 } end
end

return C
