-- oprods.lua  --  control rod stepping and manual holds, apart from the policy (which says where to) and the driver
-- (which sets the rods). "Level" is the power setting in percent, 100 = full power = rods out: rod insertion is
-- 100 - level.
local R = {}

-- Lowest and highest level for a unit: its own settings in operator.cfg, else the plant-wide ones.
function R.limits(u, E)
  local c = u.cfg or {}
  local lo = tonumber(c.levelMin) or tonumber(E.LEVEL_MIN) or 10
  local hi = tonumber(c.levelMax) or tonumber(E.LEVEL_MAX) or 100
  lo = math.max(0, math.min(100, lo)); hi = math.max(lo, math.min(100, hi))
  return lo, hi
end

-- The level a person holds: a manual hold (expires) or `level` in operator.cfg / MANUAL_LEVEL in operator.env
-- (stays until removed; 0 = off).
function R.manual(u, E)
  if u.hold then return u.hold.level end
  local m = tonumber((u.cfg or {}).level) or tonumber(E.MANUAL_LEVEL)
  if m and m > 0 then return m end
end

-- A person set a level or a mode. A level takes over from Auto: ON, that level, and back to Auto after HOLD_MIN minutes.
function R.hold(u, level, now, E)
  u.hold = { mode = "on", level = level, untilT = now + (tonumber(E.HOLD_MIN) or 10) * 60 }
end

function R.holdLeft(u, now) return u.hold and math.max(0, math.floor(u.hold.untilT - now)) or nil end

-- true once when a hold has run out
function R.expire(u, now)
  if u.hold and now >= u.hold.untilT then u.hold = nil; return true end
  return false
end

-- The next level to set (or nil to leave the rods): a manual level at once; Auto by at most ROD_STEP every ROD_EVERY
-- seconds, and not at all inside LEVEL_BAND of the target (so it doesn't hunt) unless the target is a limit.
function R.step(u, target, manual, now, E, lo, hi)
  local cur = u.level
  if cur == nil then return target end
  if cur == target then return nil end
  if manual then return target end
  local diff = math.abs(target - cur)
  if diff < (tonumber(E.LEVEL_BAND) or 5) and target ~= lo and target ~= hi then return nil end
  if now - (u.lastRod or -1e9) < (tonumber(E.ROD_EVERY) or 5) then return nil end
  local d = math.min(tonumber(E.ROD_STEP) or 10, diff)
  return cur + (target > cur and d or -d)
end

return R
