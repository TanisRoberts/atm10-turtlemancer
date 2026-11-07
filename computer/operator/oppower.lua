-- oppower.lua  --  power use: what the grid draws and what the running reactors could make.
--   Energy detectors (AP 0.8 type `energy_detector`) sit on the reactor-room cable. Draw = their summed
--   getTransferRate() (FE/t), averaged over WINDOW seconds. Potential = what the running reactors would make at
--   full power: a calibrated reactor's saved maxOutput (opcal.lua), else its FE/t scaled up from its current rod level
--   (fe * 100 / level; flagged `estimated`). A reactor with no reading
--   yet (just switched on) or idling (Auto, full buffer) uses the figure remembered from its last run; disabled or
--   manual-off reactors count for nothing. pct = draw / potential.
-- Breaker (issue #121): draw above SURGE_MAX % of potential for SURGE_FOR seconds in a row trips it. Tripped, every
--   detector is capped (setTransferRateLimit) at THROTTLE_TO % of potential, re-applied as potential changes, so the
--   batteries upstream can recharge. It never lifts by itself: M.reset (button, /reset, operator_cmd power=reset) does.
--   Never trips while potential is 0. The state is saved in operator.cfg (`breaker`), so a reboot keeps it tripped.
--   Not tripped, the detectors are kept at getMaxTransferRate() (also at boot, in case a limit was left on).
-- Detectors are labelled like units (Detector-1, ...): numbers handed out once, kept in operator.cfg, never reused.
local M = {}
local WINDOW = 5
local AVG_WINDOW = 600         -- seconds of draw averaged into avg10 (#135)
local AVG_STEP = 5             -- one long-window sample every this many seconds
local PEAK_KEEP = 24 * 3600    -- the peak is the highest smoothed draw within this many seconds
local PEAK_SAVE = 30           -- a new peak is written to operator.cfg at most this often (seconds)
local TYPE = "energy_detector"

local function call(p, m, ...)
  local f = p and p[m]
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok and type(a) == "number" then return a end
end

local NOLIMIT = 2147483647     -- fallback when a detector can't tell its own maximum

function M.new(plant, E, hooks)
  return setmetatable({ plant = plant, E = E or {}, hooks = hooks or {}, samples = {}, seenAt = nil, found = {} }, { __index = M })
end

local function utc() return os.epoch("utc") / 1000 end

-- The detectors on the cable (by type, sorted by name); gives new ones a label.
function M.scan(self)
  local names, found = peripheral.getNames(), {}
  table.sort(names)
  local cfg, dirty = self.plant.cfg, false
  cfg.detectors = type(cfg.detectors) == "table" and cfg.detectors or {}
  for _, n in ipairs(names) do
    if peripheral.getType(n) == TYPE then
      local d = cfg.detectors[n]
      if not d then
        cfg.nextNum.detector = (cfg.nextNum.detector or 0) + 1
        d = { num = cfg.nextNum.detector, label = "Detector-" .. cfg.nextNum.detector }
        cfg.detectors[n] = d; dirty = true
        self.plant.log(("New energy detector %s: peripheral %s"):format(d.label, n))
      end
      found[#found + 1] = { id = n, label = d.label }
    end
  end
  self.found = found
  if dirty then self.plant:save() end
end

-- One reading: sums every detector that answers. Returns true if any did.
function M.sample(self, now)
  local sum, limit, got = 0, nil, false
  for _, d in ipairs(self.found) do
    local p = peripheral.wrap(d.id)
    local rate = call(p, "getTransferRate")
    if rate then
      got = true; sum = sum + rate
      local l = call(p, "getTransferRateLimit")
      if l then limit = (limit or 0) + l end
    end
  end
  if not got then return false end
  local s = self.samples
  s[#s + 1] = { t = now, v = sum }
  while #s > 1 and now - s[1].t > WINDOW do table.remove(s, 1) end
  self.seenAt, self.limit = now, limit
  M.track(self, now)
  return true
end

-- The long view of the draw (#135): avg10 = the smoothed draw averaged over the last AVG_WINDOW seconds;
-- peak = the highest smoothed draw in the last 24 h with when (utc seconds), kept in operator.cfg (`peak`) so a
-- restart keeps it. `mins` holds one maximum per minute (this run only) to find the next-highest when a peak expires.
function M.track(self, now)
  local dr = 0
  for _, x in ipairs(self.samples) do dr = dr + x.v end
  dr = dr / #self.samples
  local L = self.long or {}
  self.long = L
  if not L[#L] or now - L[#L].t >= AVG_STEP then L[#L + 1] = { t = now, v = dr } end
  while #L > 0 and now - L[1].t > AVG_WINDOW do table.remove(L, 1) end
  local at = utc()
  local cfg = self.plant.cfg
  self.mins = self.mins or {}
  local m = self.mins
  local slot = math.floor(at / 60)
  if not m[#m] or m[#m].slot ~= slot then m[#m + 1] = { slot = slot, v = dr } elseif dr > m[#m].v then m[#m].v = dr end
  while #m > 0 and m[1].slot < slot - PEAK_KEEP / 60 do table.remove(m, 1) end
  local pk = type(cfg.peak) == "table" and tonumber(cfg.peak.v) and cfg.peak or nil
  if pk and at - (tonumber(pk.at) or 0) > PEAK_KEEP then
    pk = nil                                          -- expired: the best of what this run saw in the last 24 h
    for _, x in ipairs(m) do
      if not pk or x.v >= pk.v then pk = { v = x.v, at = x.slot * 60 } end
    end
    cfg.peak = pk; self.peakDirty = true
  end
  if not pk or dr >= pk.v then
    pk = { v = dr, at = at }
    cfg.peak = pk; self.peakDirty = true
  end
  if self.peakDirty and now - (self.peakSaved or -1e9) >= PEAK_SAVE then
    self.peakDirty, self.peakSaved = false, now
    self.plant:save()
  end
end

-- avg10 in FE/t and the seconds of data behind it (nil with none)
function M.average(self, now)
  local L = self.long
  if not L or #L == 0 then return nil end
  local t = 0
  for _, x in ipairs(L) do t = t + x.v end
  return t / #L, now - L[1].t
end

-- Full-power FE/t of one reactor from its status, or nil when it can't be told.
-- A calibrated reactor counts at its saved `maxOutput` (opcal.lua), running, idling or after a reboot. While it is being
-- calibrated its figure is frozen at what it was, so the climbing output can't move the breaker's cap.
function M.unitPotential(u)
  if u.cal then return u.cal.pot end
  local mx = tonumber((u.cfg or {}).maxOutput)
  if mx and mx > 0 then return mx end
  local s = u.status or {}
  if s.active and s.fe and s.fe > 0 then
    local lv = s.level
    if lv == nil then u.potential = s.fe
    elseif lv > 0 then u.potential = s.fe * 100 / lv end
  end
  return u.potential
end

-- Disabled or manually forced off: such a reactor makes nothing, so it adds nothing to the potential.
-- (One that Auto merely idles on a full buffer still counts at its last full-power figure.)
function M.switchedOff(u)
  local cfg = u.cfg or {}
  return cfg.enabled == false or (u.hold and u.hold.mode or cfg.mode) == "off"
end

-- What the running reactors would make at full power (FE/t).
function M.potential(units)
  local pot = 0
  for _, u in ipairs(units) do
    if u.kind == "reactor" and u.present and u.status and u.status.answers and not M.switchedOff(u) then pot = pot + (M.unitPotential(u) or 0) end
  end
  return pot
end

-- true when a reactor that counts towards the potential has no calibrated figure (so the potential is a guess)
function M.estimated(units)
  for _, u in ipairs(units) do
    if u.kind == "reactor" and u.present and u.status and u.status.answers and not M.switchedOff(u)
       and not ((tonumber((u.cfg or {}).maxOutput) or 0) > 0) then return true end
  end
  return false
end

function M.tripped(self)
  local b = self.plant.cfg.breaker
  return type(b) == "table" and b.tripped == true
end

local function draw(self)
  if #self.samples == 0 then return nil end
  local t = 0
  for _, x in ipairs(self.samples) do t = t + x.v end
  return t / #self.samples
end

-- Every detector's limit to `want(d)` (a number), when it isn't already there. Returns the total limit now in force.
local function applyLimit(self, want)
  local total = 0
  for _, d in ipairs(self.found) do
    local p = peripheral.wrap(d.id)
    if p then
      local w = want(p)
      local cur = call(p, "getTransferRateLimit")
      if cur ~= w and type(p.setTransferRateLimit) == "function" then pcall(p.setTransferRateLimit, w); cur = w end
      total = total + (cur or w)
    end
  end
  return total
end

local function noLimit(p) return call(p, "getMaxTransferRate") or NOLIMIT end

-- One control pass (call after sample). `units` = plant.units.
function M.guard(self, units, now)
  if #self.found == 0 then return end
  local E, cfg = self.E, self.plant.cfg
  local pot, dr = M.potential(units), draw(self)
  if M.tripped(self) then
    local cap = math.floor(pot * (tonumber(E.THROTTLE_TO) or 90) / 100)
    if pot > 0 and cap > 0 then
      self.cap = cap
      applyLimit(self, function() return math.max(1, math.floor(cap / #self.found)) end)
    end
    return
  end
  self.cap = nil
  applyLimit(self, noLimit)
  local max = tonumber(E.SURGE_MAX) or 150
  if pot > 0 and dr and dr > pot * max / 100 then
    self.overSince = self.overSince or now
    if now - self.overSince >= (tonumber(E.SURGE_FOR) or 10) then
      local pct = dr / pot * 100
      cfg.breaker = { tripped = true, asked = dr, askedPct = pct, at = utc() }
      self.plant:save()
      self.overSince = nil
      local cap = math.floor(pot * (tonumber(E.THROTTLE_TO) or 90) / 100)
      self.cap = cap
      applyLimit(self, function() return math.max(1, math.floor(cap / #self.found)) end)
      local msg = ("Power breaker tripped: the grid drew %d FE/t (%d%% of %d) for %d s. Capped at %d FE/t."):format(
        math.floor(dr + 0.5), math.floor(pct + 0.5), math.floor(pot + 0.5), tonumber(E.SURGE_FOR) or 10, cap)
      self.plant.log(msg)
      if self.hooks.event then self.hooks.event("Power", "breaker tripped at " .. math.floor(pct + 0.5) .. "%") end
    end
  else
    self.overSince = nil
  end
end

-- Lift the cap. Returns true when it was tripped.
function M.reset(self)
  local was = M.tripped(self)
  self.plant.cfg.breaker = nil
  self.overSince, self.cap = nil, nil
  if was then
    self.plant:save()
    applyLimit(self, noLimit)
    self.plant.log("Power breaker reset: the detector limit is back to its maximum.")
    if self.hooks.event then self.hooks.event("Power", "breaker reset") end
  end
  return was
end

-- The `power` record for the status: { draw, potential, pct, limit, seen }, or nil with no detector on the cable.
function M.record(self, units, now)
  if #self.found == 0 then return nil end
  local dr = draw(self)
  local pot = M.potential(units)
  local pct = dr and pot > 0 and (dr / pot * 100) or nil
  local rec = { draw = dr, potential = pot, pct = pct, seen = self.seenAt and (now - self.seenAt) or nil,
                detectors = #self.found, estimated = M.estimated(units) or nil }
  local avg, span = M.average(self, now)
  if avg then
    rec.avg10, rec.avgSpan = avg, span
    rec.avg10Pct = pot > 0 and (avg / pot * 100) or nil
  end
  local pk = self.plant.cfg.peak
  if type(pk) == "table" and tonumber(pk.v) then
    rec.peak, rec.peakAt = pk.v, pk.at
    rec.peakPct = pot > 0 and (pk.v / pot * 100) or nil
  end
  if M.tripped(self) then
    local b = self.plant.cfg.breaker
    rec.limit, rec.asked, rec.askedPct = self.cap or self.limit or math.floor(pot * (tonumber(self.E.THROTTLE_TO) or 90) / 100), b.asked, b.askedPct
    rec.askedFor = math.max(0, utc() - (b.at or utc()))
  end
  return rec
end

return M
