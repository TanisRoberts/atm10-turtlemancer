-- oppower.lua  --  power use: what the grid draws and what the running reactors could make.
--   Energy detectors (AP 0.8 type `energy_detector`) sit on the reactor-room cable. Draw = their summed
--   getTransferRate() (FE/t), averaged over WINDOW seconds. Potential = what the running reactors would make at
--   full power: each one's FE/t scaled up from its current rod level (fe * 100 / level). A reactor with no reading
--   yet (just switched on) or idling (Auto, full buffer) uses the figure remembered from its last run; disabled or
--   manual-off reactors count for nothing. pct = draw / potential.
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

function M.new(plant)
  return setmetatable({ plant = plant, samples = {}, seenAt = nil, found = {} }, { __index = M })
end

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

-- The `power` record for the status: { draw, potential, pct, limit, seen }, or nil with no detector on the cable.
function M.record(self, units, now)
  if #self.found == 0 then return nil end
  local draw
  if #self.samples > 0 then
    local t = 0
    for _, x in ipairs(self.samples) do t = t + x.v end
    draw = t / #self.samples
  end
  local pot = 0
  for _, u in ipairs(units) do
    if u.kind == "reactor" and u.present and u.status and u.status.answers and not M.switchedOff(u) then pot = pot + (M.unitPotential(u) or 0) end
  end
  local pct = draw and pot > 0 and (draw / pot * 100) or nil
  return { draw = draw, potential = pot, pct = pct, limit = self.limit, seen = self.seenAt and (now - self.seenAt) or nil,
           detectors = #self.found }
end

return M
