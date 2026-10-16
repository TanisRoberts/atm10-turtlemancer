-- oppolicy.lua  --  who runs, decided apart from the drivers.
-- A policy looks at the whole plant and returns { [unitId] = { active = true|false|nil, why = "..." } };
-- nil = leave it as it is (inside the hysteresis band, or nothing readable). Add a policy (e.g. "stagger": one
-- reactor at low demand, the next when the first can't keep up) and name it POLICY= in operator.env; the loop and
-- the drivers stay as they are.
--   plant  = { stored, cap, buf }         summed over every reactor that answers
--   units  = list of { id, label, mode, enabled, on, off, lo, hi, manual, status }
--            (on/off are fractions 0..1; lo/hi the lowest and highest power level in percent; manual = a level to hold)
-- A decision may also carry  level  (the power level wanted, 100 - rod insertion, for a reactor that is or will be
-- running), levelWhy and manual = true. The loop steps the rods toward it; the policy only says where to.
local P = {}

-- The level a running reactor should sit at: full power at the ON threshold and below, lowest at the OFF threshold,
-- in a straight line between. A level that is a function of the buffer settles by itself; nothing hunts.
local function levelFor(u)
  local lo, hi = u.lo or 0, u.hi or 100
  if type(u.manual) == "number" then return math.max(lo, math.min(hi, u.manual)), true end
  local b = u.status and u.status.buf
  if b == nil then return nil end
  local f = (b - u.on) / math.max(u.off - u.on, 0.01)
  f = math.max(0, math.min(1, f))
  return math.floor(hi - f * (hi - lo) + 0.5), false
end

-- One unit, by its own buffer: on below `on`, off above `off`. Manual mode and disabled win. Fuel never matters.
local function one(u)
  if u.manage == false then return nil end          -- "Run it: NO": leave the reactor alone
  if not u.enabled then return { active = false, why = "disabled" } end
  local d
  if u.mode == "on" then d = { active = true, why = "manual on" }
  elseif u.mode == "off" then return { active = false, why = "manual off" }
  else
    local b = u.status and u.status.buf
    if b == nil then return nil end
    if b < u.on then d = { active = true, why = "buffer low" }
    elseif b > u.off then return { active = false, why = "buffer full" }
    else d = {} end
  end
  local running = d.active
  if running == nil then running = u.status and u.status.active end
  if running then d.level, d.manual = levelFor(u) end
  if next(d) == nil then return nil end
  return d
end

-- Day one: every reactor follows the same thresholds on its own buffer.
function P.follow(plant, units)
  local out = {}
  for _, u in ipairs(units) do out[u.id] = one(u) end
  return out
end

P.default = "follow"
function P.get(name) return P[name] or P[P.default] end

return P
