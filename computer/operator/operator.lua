-- operator.lua  --  the Operator: runs the Extreme Reactors 2 power plant on its own.
--
-- Needs: an advanced computer with a wired modem on the reactor cable (reactor computer port, its input and
-- output access ports and a waste barrel on that cable), plus a wireless or ender modem for the mainframe.
-- A monitor touching a side shows the same plain text as the computer's screen (the pretty screen is separate).
--
-- What it does: finds every unit on the cable (opplant.lua), drives each reactor through a driver (opdrivers.lua),
-- lets a policy (oppolicy.lua) decide who runs (on below ON_BELOW % of the buffer, off above OFF_ABOVE %), keeps
-- waste moving from the output port into the barrel, works out what each reactor needs / has / is missing
-- (opneeds.lua) and tells the mainframe (protocol tanis-operator) once every few seconds.
-- Settings: operator.env (plant-wide, live) and operator.cfg (per unit, keyed by peripheral name: mode auto|on|off,
-- enabled, onBelow, offAbove, input, output, waste). Log: operator.log.
local envfile = require("envfile")
local plantlib = require("opplant")
local policies = require("oppolicy")
local needs = require("opneeds")

local PROTOCOL = "tanis-operator"
local LOG, CFG = "operator.log", "operator.cfg"

local env = envfile.new("operator.env", "Operator settings.", {
  { "ON_BELOW",     30, "Switch a reactor ON when its buffer drops below this percent." },
  { "OFF_ABOVE",    90, "Switch a reactor OFF when its buffer rises above this percent." },
  { "POLICY",       "follow", "Who runs: follow = every reactor on its own thresholds." },
  { "TICK",         2,  "Seconds between control passes." },
  { "SLOW",         30, "Seconds between full re-checks of the cable and of what each reactor needs." },
  { "STATUS_EVERY", 5,  "Seconds between status messages to the mainframe (also the heartbeat)." },
})
env.load()
local E = env.v

-- Log ---------------------------------------------------------------------
local function log(msg)
  local line = ("[%d] %s"):format(math.floor(os.clock()), msg)
  local ok = pcall(function()
    if fs.exists(LOG) and fs.getSize(LOG) > 20000 then
      if fs.exists(LOG .. ".old") then fs.delete(LOG .. ".old") end
      fs.move(LOG, LOG .. ".old")
    end
    local f = fs.open(LOG, "a"); f.writeLine(line); f.close()
  end)
  return ok
end

local plant = plantlib.new(CFG, function(m) print(m); log(m) end)

-- Radio -------------------------------------------------------------------
local netOn = false
peripheral.find("modem", function(name, m)
  if m.isWireless and m.isWireless() then rednet.open(name); netOn = true end
  return false
end)

-- State -------------------------------------------------------------------
local st = { units = {}, lastScan = -1e9, lastSend = -1e9, dirty = true, bufFull = {} }
local E_NOW = {}

local function fmt(n, d) if type(n) ~= "number" then return "?" end return ("%." .. (d or 0) .. "f"):format(n) end

-- Waste: move cyanite from the output port into the barrel, one stack per call. Never voided.
local function clearWaste(u)
  u.wasteStuck = false
  if not (u.output and u.waste) or u.outputGone then return end
  local port = peripheral.wrap(u.output)
  local l = plantlib.listOf(u.output)
  if not (port and l) then return end
  for slot, it in pairs(l) do
    if plantlib.isWaste(it.name) then
      local ok, moved = pcall(port.pushItems, u.waste, slot)
      if not ok or (moved or 0) == 0 then u.wasteStuck = true; break end
    end
  end
  if u.wasteStuck and not u.wasteWarned then log(u.label .. ": waste not clearing") end
  u.wasteWarned = u.wasteStuck
end

-- Check what a reactor needs
local function recheck(u, s)
  u.needs = needs.evaluate({ unit = u, status = s, plant = plant.found, driver = u.driver, E = E })
end

local function tick()
  if env.refresh() then log("settings reloaded") end
  if plant:reloadIfEdited() then st.dirty = true end
  local now = os.clock()
  if st.dirty or now - st.lastScan >= E.SLOW then
    if plant:scan() then log("cable changed: " .. plant.sig) end
    st.lastScan, st.dirty, st.rechecked = now, false, true
  end

  -- read every reactor
  local list, decide = {}, {}
  local sum = { stored = 0, cap = 0 }
  for _, u in ipairs(plant.units) do
    if u.kind == "reactor" then
      local s = (u.present and u.driver) and u.driver:status() or { answers = false }
      u.status = s
      if s.answers and s.stored and s.cap then sum.stored, sum.cap = sum.stored + s.stored, sum.cap + s.cap end
      if st.rechecked then recheck(u, s) end
      local on, off = plantlib.thresholds(u, E)
      list[#list + 1] = { id = u.id, label = u.label, mode = u.cfg.mode or "auto", enabled = u.cfg.enabled ~= false,
                          on = on, off = off, status = s.answers and s or nil }
    end
  end
  st.rechecked = false
  sum.buf = sum.cap > 0 and sum.stored / sum.cap or nil

  -- decide, then act
  decide = policies.get(E.POLICY)(sum, list)
  for _, u in ipairs(plant.units) do
    if u.kind == "reactor" and u.present and u.driver and u.status.answers then
      local d = decide[u.id]
      u.why = d and d.why or u.why
      if d and d.active ~= nil and u.status.active ~= d.active then
        if u.driver:setActive(d.active) then
          u.status.active = d.active
          log(("%s %s (%s, buffer %s%%)"):format(u.label, d.active and "ON" or "OFF", d.why, fmt((u.status.buf or 0) * 100)))
        else
          u.why = "can't switch (call failed)"
        end
      end
      local wasStuck = u.wasteStuck
      clearWaste(u)
      if (wasStuck or false) ~= (u.wasteStuck or false) then recheck(u, u.status) end
      -- passive reactors may keep burning with a full buffer: log what we see once per change so it can be confirmed
      local full = (u.status.buf or 0) >= 0.99 and u.status.active == true
      if full ~= (st.bufFull[u.id] or false) then
        st.bufFull[u.id] = full
        if full then log(("%s: buffer full and still on: burn %s mB/t, %s FE/t"):format(u.label, fmt(u.status.burn, 4), fmt(u.status.fe))) end
      end
    end
  end
end

-- Status record --------------------------------------------------------------
local function record()
  local units, tot = {}, { fe = 0, stored = 0, cap = 0, running = 0, reactors = 0, uranium = 0, waste = 0 }
  for _, u in ipairs(plant.units) do
    local r = { id = u.id, label = u.label, kind = u.kind, present = u.present }
    if u.kind == "reactor" then
      local s = u.status or {}
      local uran = u.input and plantlib.contents(u.input)
      r.kind, r.driver = "reactor", u.driver and u.driver.kind
      r.answers = s.answers or false
      r.active, r.fe, r.buf = s.active, s.fe, s.buf
      r.fuel, r.fuelMax, r.waste = s.fuel, s.fuelMax, s.waste
      r.fuelTemp, r.casing, r.uranium = s.fuelTemp, s.casing, uran
      r.mode, r.enabled, r.why = u.cfg.mode or "auto", u.cfg.enabled ~= false, u.why
      r.wasteStuck, r.needs = u.wasteStuck or false, u.needs
      r.note = u.wasteStuck and "waste not clearing" or needs.summary(u.needs)
      tot.reactors = tot.reactors + 1
      if s.answers then
        tot.fe = tot.fe + (s.fe or 0); tot.stored = tot.stored + (s.stored or 0); tot.cap = tot.cap + (s.cap or 0)
        if s.active then tot.running = tot.running + 1 end
        tot.waste = tot.waste + (s.waste or 0)
      end
      tot.uranium = tot.uranium + (uran or 0)
    end
    units[#units + 1] = r
  end
  tot.buf = tot.cap > 0 and tot.stored / tot.cap or nil
  return { type = "operator", id = os.getComputerID(), label = os.getComputerLabel() or "Operator", t = os.clock(),
           units = units, plant = tot }
end

-- Plain text screen -----------------------------------------------------------
local function render(t, rec)
  local w = t.getSize()
  local y = 1
  local function line(s, col)
    if col and t.isColour and t.isColour() then t.setTextColour(col) end
    t.setCursorPos(1, y); t.clearLine(); t.write(tostring(s):sub(1, w)); y = y + 1
    if t.setTextColour then t.setTextColour(colours.white) end
  end
  t.setBackgroundColour(colours.black); t.setTextColour(colours.white); t.clear()
  local p = rec.plant
  line(("%s: %d reactor%s, %d running"):format(rec.label, p.reactors, p.reactors == 1 and "" or "s", p.running), colours.cyan)
  line(("Plant: %s FE/t, buffer %s%%"):format(fmt(p.fe), p.buf and fmt(p.buf * 100) or "?"))
  for _, r in ipairs(rec.units) do
    if r.kind == "reactor" then
      local state = not r.present and "OFFLINE" or not r.answers and "SILENT" or r.active and "ON" or "off"
      line(("%s %s %s%% %s FE/t"):format(r.label, state, r.buf and fmt(r.buf * 100) or "?", fmt(r.fe)),
        (r.active and colours.lime) or colours.white)
      line(("  fuel %s/%s, uranium %s, waste %s"):format(fmt(r.fuel), fmt(r.fuelMax), r.uranium and fmt(r.uranium) or "?", fmt(r.waste)))
      line(("  fuel %s C, casing %s C"):format(fmt(r.fuelTemp), fmt(r.casing)))
      for _, n in ipairs(r.needs or {}) do
        if n.state ~= "ok" then line(("  %s %s: %s"):format(n.state == "missing" and "MISSING" or "?", n.title, n.why),
          n.state == "missing" and colours.red or colours.yellow) end
      end
    else
      line(("%s (%s)%s"):format(r.label, r.kind, r.present and "" or " OFFLINE"))
    end
  end
  if p.reactors == 0 then line("No reactor found on the cable (BigReactors-Reactor).", colours.red) end
end

local function draw(rec)
  render(term.current(), rec)
  peripheral.find("monitor", function(_, m)
    m.setTextScale(0.5)
    render(m, rec)
    return false
  end)
end

-- First boot: say what was found -------------------------------------------------
local function report()
  local f = plant.found
  log("Operator started. Found: " .. #f.reactor .. " reactor, " .. #f.port .. " access port, " .. #f.barrel .. " barrel, "
    .. #f.turbine .. " turbine, " .. #f.storage .. " energy storage.")
  for _, u in ipairs(plant.units) do
    if u.kind == "reactor" then
      log(("%s = %s (%s driver); input port %s, output port %s, waste barrel %s"):format(u.label, u.id,
        u.driver and u.driver.kind or "none", tostring(u.input), tostring(u.output), tostring(u.waste)))
    end
  end
  for _, k in ipairs({ "port", "barrel" }) do for _, n in ipairs(f[k]) do log(k .. ": " .. n .. " (" .. tostring(peripheral.getType(n)) .. ")") end end
end

-- Main loop ---------------------------------------------------------------------
term.clear(); term.setCursorPos(1, 1)
print("Operator starting. Reboot (hold Ctrl+R) to update. Type reset to give this computer a new role.")
plant:scan(); st.lastScan = os.clock()
report()

local timer = os.startTimer(0)
while true do
  local ev, a = os.pullEvent()
  if ev == "timer" and a == timer then
    local ok, err = pcall(tick)
    if not ok then log("tick failed: " .. tostring(err)) end
    local rec = record()
    if netOn and os.clock() - st.lastSend >= E.STATUS_EVERY then
      st.lastSend = os.clock()
      rednet.broadcast(rec, PROTOCOL)
    end
    pcall(draw, rec)
    timer = os.startTimer(E.TICK)
  elseif ev == "peripheral" or ev == "peripheral_detach" then
    st.dirty = true
  end
end
