-- oppower.lua  --  power use: what the grid draws and what the running reactors could make.
--   Energy detectors (AP 0.8 type `energy_detector`) sit on the reactor-room cable. Draw = their summed
--   getTransferRate() (FE/t), averaged over WINDOW seconds. Potential = what the running reactors would make at
--   full power: each one's FE/t scaled up from its current rod level (fe * 100 / level). A reactor with no reading
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
  return true
end

-- Full-power FE/t of one reactor from its status, or nil when it can't be told.
function M.unitPotential(u)
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
                detectors = #self.found }
  if M.tripped(self) then
    local b = self.plant.cfg.breaker
    rec.limit, rec.asked, rec.askedPct = self.cap or self.limit or math.floor(pot * (tonumber(self.E.THROTTLE_TO) or 90) / 100), b.asked, b.askedPct
    rec.askedFor = math.max(0, utc() - (b.at or utc()))
  end
  return rec
end

return M
