-- operator.lua  --  the Operator: runs the Extreme Reactors 2 power plant on its own.
--
-- Needs: an advanced computer with a wired modem on the cable that holds the reactor (computer port) and its inlet and
-- outlet access ports (the cable is shared with Storage; everything that isn't a reactor or its ports is ignored), plus
-- a wireless or ender modem for the mainframe.
-- The Operator never moves items. Storage fills the inlet port and drains the outlet port (issue #37); the Operator
-- only reads them: uranium in the inlet, and whether the outlet is emptying.
-- The computer's screen and every monitor touching a side show the same pages (opscreen.lua, on the UI kit):
-- a plant overview, and per reactor a Power, Needs and Set tab. Taps change the run mode, the held level and the settings.
--
-- What it does: finds every unit on the cable (opplant.lua), drives each reactor through a driver (opdrivers.lua),
-- lets a policy (oppolicy.lua) decide who runs (on below ON_BELOW % of the buffer, off above OFF_ABOVE %), watches the
-- outlet port ("waste not clearing" when it fills or stops emptying), works out what each reactor needs / has / is
-- missing (opneeds.lua) and tells the mainframe (protocol tanis-operator) once every few seconds.
-- Storage tells the Operator how much uranium it holds with  { type = "uranium", total = <ingots> }  on the same
-- protocol; without it "fuel supply" reads unknown.
-- Control rods: the policy picks a power level per running reactor from its buffer (full power at the ON threshold,
-- LEVEL_MIN at the OFF threshold); oprods.lua steps the rods toward it, ROD_STEP percent every ROD_EVERY seconds.
-- A level set by hand holds for HOLD_MIN minutes, then control returns to Auto.
-- Settings: operator.env (plant-wide, live) and operator.cfg (per unit, keyed by peripheral name: mode auto|on|off,
-- enabled, onBelow, offAbove, levelMin, levelMax, level, input, output). Log: operator.log.
-- Commands (mainframe or screen), protocol tanis-operator:
--   { type = "operator_cmd", unit = <label or id; nil = every reactor>, mode = "auto"|"on"|"off", level = 1..100 }
--   a mode is saved in operator.cfg; a level is a manual hold.
local envfile = require("envfile")
local plantlib = require("opplant")
local policies = require("oppolicy")
local needs = require("opneeds")
local rods = require("oprods")
local ui = require("ui")
local screen = require("opscreen")

local PROTOCOL = "tanis-operator"
local LOG, CFG = "operator.log", "operator.cfg"

local env = envfile.new("operator.env", "Operator settings.", {
  { "ON_BELOW",     30, "Switch a reactor ON when its buffer drops below this percent." },
  { "OFF_ABOVE",    90, "Switch a reactor OFF when its buffer rises above this percent." },
  { "POLICY",       "follow", "Who runs: follow = every reactor on its own thresholds." },
  { "SETUP_WIZARD", "yes", "yes = a new reactor waits for the setup wizard (and is not switched until it is done); no = skip the wizard and work its ports out from what they hold." },
  { "RODS",         "auto", "auto = the power level follows the buffer; off = leave the control rods alone." },
  { "LEVEL_MIN",    10, "Lowest power level (percent, 100 = rods fully out) Auto will run a reactor at." },
  { "LEVEL_MAX",    100, "Highest power level Auto will run a reactor at." },
  { "ROD_STEP",     10, "Most percent Auto moves the level in one step." },
  { "ROD_EVERY",    5,  "Fewest seconds between Auto's steps." },
  { "LEVEL_BAND",   5,  "Auto leaves the rods alone while the level is within this many percent of where it wants to be." },
  { "MANUAL_LEVEL", 0,  "Hold every reactor at this power level (1 to 100). 0 = off, Auto decides." },
  { "HOLD_MIN",     10, "Minutes a level set by hand (screen or mainframe) is held before control returns to Auto." },
  { "TICK",         2,  "Seconds between control passes." },
  { "SLOW",         30, "Seconds between full re-checks of the cable and of what each reactor needs." },
  { "STUCK_AFTER",  120, "Seconds an outlet port may hold cyanite without ever dropping before it is reported as not clearing." },
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
plant.wizard = E.SETUP_WIZARD ~= "no"

-- Radio -------------------------------------------------------------------
local netOn = false
peripheral.find("modem", function(name, m)
  if m.isWireless and m.isWireless() then rednet.open(name); netOn = true end
  return false
end)

-- State -------------------------------------------------------------------
local st = { supply = nil, supplyAt = 0, units = {}, lastScan = -1e9, lastSend = -1e9, dirty = true, bufFull = {},
  hist = {}, events = {}, netS = {}, feS = {}, lastHist = -1e9, rec = nil }
local E_NOW = {}

-- A short event log (newest first, 8 entries) for the screen and the mainframe, and the plant buffer history
-- (a sample every 15 s, 120 of them = 30 minutes).
local function event(label, text)
  local at = "--:--"
  pcall(function() at = os.date("%H:%M") end)
  local last = st.events[1]
  if last and last.who == label and text:find("^level ") and last.text:find("^level ") then table.remove(st.events, 1) end
  table.insert(st.events, 1, { at = at, who = label, text = text })
  while #st.events > 8 do table.remove(st.events) end
end

local ctlHooks = { log = log, event = event, dirty = function() st.dirty = true end }
local ctl = require("opctl")(plant, E, ctlHooks)

local function fmt(n, d) if type(n) ~= "number" then return "?" end return ("%." .. (d or 0) .. "f"):format(n) end

-- Waste: only watch the outlet port. Not clearing = every slot taken, or cyanite that has not dropped for STUCK_AFTER s.
-- Nothing is moved or voided here; Storage drains the port.
local function watchOutlet(u)
  u.outputCount, u.outputFull = nil, false
  local was = u.wasteStuck
  u.wasteStuck = false
  if u.output and not u.outputGone then
    local l = plantlib.listOf(u.output)
    if l then
      local n, used = 0, 0
      for _, it in pairs(l) do
        used = used + 1
        if plantlib.isWaste(it.name) then n = n + (it.count or 0) end
      end
      local ok, size = pcall(function() return peripheral.call(u.output, "size") end)
      u.outputCount = n
      u.outputFull = ok and type(size) == "number" and size > 0 and used >= size
      local now = os.clock()
      if n == 0 then u.wTrack = nil
      elseif not u.wTrack or n < u.wTrack.base then u.wTrack = { since = now, base = n }
      elseif now - u.wTrack.since >= E.STUCK_AFTER then u.wasteStuck = true end
      if u.outputFull and n > 0 then u.wasteStuck = true end
    end
  end
  if u.wasteStuck and not was then
    log(u.label .. ": waste not clearing (outlet holds " .. tostring(u.outputCount) .. " cyanite)")
    event(u.label, "waste outlet not emptying")
  end
  return (was or false) ~= u.wasteStuck
end

-- Storage's uranium count (nil when it isn't reporting or went quiet)
local function supply()
  if st.supply and os.clock() - st.supplyAt < 90 then return st.supply end
end

-- Check what a reactor needs
local function recheck(u, s)
  u.needs = needs.evaluate({ unit = u, status = s, plant = plant.found, driver = u.driver, supply = supply(), E = E })
end

local function tick()
  if env.refresh() then log("settings reloaded") end
  if plant:reloadIfEdited() then st.dirty = true end
  if (E.SETUP_WIZARD ~= "no") ~= plant.wizard then plant.wizard = E.SETUP_WIZARD ~= "no"; st.dirty = true end
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
      if s.answers then u.heardAt = now end
      if s.answers and s.stored and s.cap then sum.stored, sum.cap = sum.stored + s.stored, sum.cap + s.cap end
      if st.rechecked then recheck(u, s) end
      local on, off = plantlib.thresholds(u, E)
      if rods.expire(u, now) then log(u.label .. ": manual hold ended, back to Auto"); event(u.label, "back to Auto"); ui.say(u.label .. ": back to Auto", "good") end
      local lo, hi = rods.limits(u, E)
      if s.level then u.level = s.level end
      list[#list + 1] = { id = u.id, label = u.label, mode = u.hold and u.hold.mode or u.cfg.mode or "auto",
                          enabled = u.cfg.enabled ~= false, manage = u.cfg.manage ~= false and not u.awaiting, on = on, off = off, lo = lo, hi = hi,
                          manual = rods.manual(u, E), status = s.answers and s or nil }
    end
  end
  st.rechecked = false
  local sup = supply()
  if (sup ~= nil) ~= st.hadSupply or (sup or 0) > 0 ~= (st.hadSupplyN or false) then
    st.hadSupply, st.hadSupplyN = sup ~= nil, (sup or 0) > 0
    for _, u in ipairs(plant.units) do if u.kind == "reactor" then recheck(u, u.status) end end
  end
  sum.buf = sum.cap > 0 and sum.stored / sum.cap or nil

  -- plant history for the screen: net FE/t from the last minute of buffer, a buffer sample every 15 s
  if sum.cap > 0 then
    local ns = st.netS
    ns[#ns + 1] = { t = now, stored = sum.stored }
    while #ns > 1 and now - ns[2].t >= 60 do table.remove(ns, 1) end
    if now - st.lastHist >= 15 then
      st.lastHist = now
      st.hist[#st.hist + 1] = math.floor(sum.buf * 100 + 0.5)
      while #st.hist > 120 do table.remove(st.hist, 1) end
      local fs_ = 0
      for _, u in ipairs(plant.units) do if u.kind == "reactor" and u.status and u.status.fe then fs_ = fs_ + u.status.fe end end
      st.feS[#st.feS + 1] = fs_
      while #st.feS > 240 do table.remove(st.feS, 1) end
    end
  end

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
          event(u.label, ("%s, buffer %s%%"):format(d.active and "on" or "off", fmt((u.status.buf or 0) * 100)))
        else
          u.why = "can't switch (call failed)"
        end
      end
      -- control rods: the policy says where, oprods steps there, the driver sets them
      if E.RODS ~= "off" and d and d.level and u.driver:has("setAllControlRodLevels") and u.status.active ~= false then
        local lo, hi = rods.limits(u, E)
        local nl = rods.step(u, d.level, d.manual, now, E, lo, hi)
        if nl and u.driver:setOutput(100 - nl) then
          local from = u.level
          u.level, u.lastRod = nl, now
          u.levelWhy = d.manual and "manual" or (nl > (from or nl) and "buffer falling" or "buffer filling")
          u.levelAt = now
          if nl == d.level then
            log(("%s level %d%% (%s, buffer %s%%)"):format(u.label, nl, u.levelWhy, fmt((u.status.buf or 0) * 100)))
            if not d.manual then event(u.label, ("level %s to %d%% (%s)"):format(nl > (from or nl) and "raised" or "lowered", nl, u.levelWhy)) end
          end
        end
      end
      if watchOutlet(u) then recheck(u, u.status) end
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
  local units, tot = {}, { fe = 0, stored = 0, cap = 0, running = 0, reactors = 0, uranium = 0, waste = 0, supply = supply() }
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
      r.mode, r.enabled, r.why = u.hold and u.hold.mode or u.cfg.mode or "auto", u.cfg.enabled ~= false, u.why
      r.level, r.rodCount, r.rodLevels = s.level or u.level, s.rodCount, s.rodLevels
      r.levelWhy, r.levelAt, r.holdLeft = u.levelWhy, u.levelAt, rods.holdLeft(u, os.clock())
      local lo, hi = rods.limits(u, E)
      r.lo, r.hi, r.manage, r.awaiting = lo, hi, u.cfg.manage ~= false, u.awaiting or false
      r.portCount = #plant.found.port
      r.onBelow, r.offAbove = plantlib.thresholds(u, E)
      r.seen = u.heardAt and (os.clock() - u.heardAt) or nil
      r.wasteStuck, r.needs, r.outlet = u.wasteStuck or false, u.needs, u.outputCount
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
  local ns = st.netS
  if #ns >= 2 and ns[#ns].t - ns[1].t >= 20 then
    tot.net = (ns[#ns].stored - ns[1].stored) / ((ns[#ns].t - ns[1].t) * 20)
  end
  if #st.feS > 0 then
    local t = 0
    for _, v in ipairs(st.feS) do t = t + v end
    tot.avgHour = t / #st.feS
  end
  tot.hist, tot.events = st.hist, st.events
  return { type = "operator", id = os.getComputerID(), label = os.getComputerLabel() or "Operator", t = os.clock(),
           units = units, plant = tot }
end

-- First boot: say what was found -------------------------------------------------
local function report()
  local f = plant.found
  log("Operator started. Found: " .. #f.reactor .. " reactor, " .. #f.port .. " reactor port, "
    .. #f.turbine .. " turbine, " .. #f.storage .. " energy storage.")
  -- every peripheral on the (shared) cable with its type, so the port names and types can be confirmed
  for _, n in ipairs(peripheral.getNames()) do
    log("peripheral " .. n .. " : " .. table.concat({ peripheral.getType(n) }, ", "))
  end
  for _, u in ipairs(plant.units) do
    if u.kind == "reactor" then
      log(("%s = %s (%s driver); inlet port %s, outlet port %s"):format(u.label, u.id,
        u.driver and u.driver.kind or "none", tostring(u.input), tostring(u.output)))
    end
  end
end

-- Main loop ---------------------------------------------------------------------
term.clear(); term.setCursorPos(1, 1)
print("Operator starting. Reboot (hold Ctrl+R) to update. Type reset to give this computer a new role.")
plant:scan(); st.lastScan = os.clock()
report()
event("Operator", ("started, %d reactor%s found"):format(#plant.found.reactor, #plant.found.reactor == 1 and "" or "s"))

-- The computer's screen and each monitor touching a side
local views = { ui.view(term.current()) }
local SIDES = { "top", "bottom", "left", "right", "front", "back" }
local function syncViews()
  for i = #views, 2, -1 do
    if not peripheral.isPresent(views[i].side) then table.remove(views, i) end
  end
  for _, side in ipairs(SIDES) do
    if peripheral.isPresent(side) and peripheral.getType(side) == "monitor" then
      local have = false
      for i = 2, #views do if views[i].side == side then have = true end end
      if not have then views[#views + 1] = ui.view(peripheral.wrap(side), { side = side }) end
    end
  end
end
syncViews()

local timer = os.startTimer(0)
ctlHooks.kick = function() if timer then os.cancelTimer(timer) end; timer = os.startTimer(0.05) end
local function onEvent(ev, a, b, c3)
  if ev == "timer" and a == timer then
    local ok, err = pcall(tick)
    if not ok then log("tick failed: " .. tostring(err)) end
    st.rec = record()
    if netOn and os.clock() - st.lastSend >= E.STATUS_EVERY then
      st.lastSend = os.clock()
      rednet.broadcast(st.rec, PROTOCOL)
    end
    timer = os.startTimer(E.TICK)
  elseif ev == "rednet_message" and c3 == PROTOCOL and type(b) == "table" and b.type == "uranium" and tonumber(b.total) then
    st.supply, st.supplyAt = tonumber(b.total), os.clock()
  elseif ev == "rednet_message" and c3 == PROTOCOL and type(b) == "table" and b.type == "operator_cmd" then
    if b.mode then ctl.mode(b.unit, b.mode) end
    if tonumber(b.level) then ctl.hold(b.unit, tonumber(b.level)) end
  elseif ev == "peripheral" or ev == "peripheral_detach" then
    st.dirty = true
    syncViews()
  end
end

local ctx = { ctl = ctl, E = E }
ui.run(views, function(v)
  ctx.rec, ctx.now = st.rec, os.clock()
  local ok, err = pcall(screen.draw, v, ctx)
  if not ok then
    v:header("OPERATOR", { state = "error", color = "bad" })
    v:put(2, 4, tostring(err):sub(1, math.max(v.W - 2, 1)), "bad", "bg")
    if st.screenErr ~= tostring(err) then st.screenErr = tostring(err); log("screen failed: " .. st.screenErr) end
  end
end, { tick = 1, on_event = onEvent })
