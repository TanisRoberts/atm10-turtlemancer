-- oppolicy.lua  --  who runs, decided apart from the drivers.
-- A policy looks at the whole plant and returns { [unitId] = { active = true|false|nil, why = "..." } };
-- nil = leave it as it is (inside the hysteresis band, or nothing readable). Add a policy (e.g. "stagger": one
-- reactor at low demand, the next when the first can't keep up) and name it POLICY= in operator.env; the loop and
-- the drivers stay as they are.
--   plant  = { stored, cap, buf }         summed over every reactor that answers
--   units  = list of { id, label, mode, enabled, on, off, status }   (on/off are fractions 0..1)
local P = {}

-- One unit, by its own buffer: on below `on`, off above `off`. Manual mode and disabled win. Fuel never matters.
local function one(u)
  if not u.enabled then return { active = false, why = "disabled" } end
  if u.mode == "on" then return { active = true, why = "manual on" } end
  if u.mode == "off" then return { active = false, why = "manual off" } end
  local b = u.status and u.status.buf
  if b == nil then return nil end
  if b < u.on then return { active = true, why = "buffer low" } end
  if b > u.off then return { active = false, why = "buffer full" } end
  return nil
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
