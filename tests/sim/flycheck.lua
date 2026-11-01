-- flycheck.lua  --  the check every Seagull scenario runs with (#114): from what his Geo Scanner has returned, he is
-- never in a cell with a known solid block above it, and never lower than CLEARANCE below the highest known top within
-- 2 blocks of him (his flying height is that top + 1 + CLEARANCE, so one block of slack). Checked at every move that
-- is not straight up (climbing out is always allowed). A violation raises an error inside his program, which fails
-- the scenario with the place and what was known.
--
--   local check = require("sim.flycheck").watch(turtle, { clearance = 3, exempt = function(x, z) ... end })
--   scanner:scanBlocks(r) results go through check.observe(blocks, x, y, z, r)   (the scenario's geoScanner does)
--   check.off = true   to pause it (a scenario that puts him underground on purpose)
local M = {}

local function fluid(name) return name:find("water") ~= nil or name:find("lava") ~= nil end

function M.watch(t, o)
  o = o or {}
  local CL = o.clearance or 3
  local W = { moves = 0, off = false }
  local col, top = {}, {}        -- ["x,z"] = { [y] = name }, and the highest y (any block) in it

  function W.observe(blocks, ox, oy, oz, r)
    -- A scan taken under a roof is thrown away by the program (rule 5), so it is not "known" either
    for _, b in ipairs(blocks) do
      if b.x == 0 and b.z == 0 and b.y > 0 and b.name ~= "minecraft:air" and not fluid(b.name)
        and not b.name:find("computercraft:turtle") then return end
    end
    local touched = {}
    for dx = -r, r do
      for dz = -r, r do
        local k = (ox + dx) .. "," .. (oz + dz)
        local c = col[k]
        if c then for y = oy - r, oy + r do c[y] = nil end end
        touched[k] = true
      end
    end
    for _, b in ipairs(blocks) do
      if b.name ~= "minecraft:air" and not b.name:find("computercraft:turtle") then
        local k = (ox + b.x) .. "," .. (oz + b.z)
        col[k] = col[k] or {}
        col[k][oy + b.y] = b.name
      end
    end
    for k in pairs(touched) do
      local m = nil
      for y in pairs(col[k] or {}) do if not m or y > m then m = y end end
      top[k] = m
    end
  end

  t.body.onMove = function(dir)
    W.moves = W.moves + 1
    if W.off or dir == "up" then return end
    local b = t.body
    if o.exempt and o.exempt(b.x, b.z) then return end
    -- Climbing out from under a roof (rule 5) backs out the way he came, which is under the roof he just found
    if t.screen:text():find("Underground", 1, true) then return end
    local c = col[b.x .. "," .. b.z]
    if c then
      for y, name in pairs(c) do
        if y > b.y and not fluid(name) then
          error(("flycheck: at %d,%d,%d with a known %s above at y %d"):format(b.x, b.y, b.z, name, y), 0)
        end
      end
    end
    local best = nil
    for dx = -2, 2 do
      for dz = -2, 2 do
        local m = top[(b.x + dx) .. "," .. (b.z + dz)]
        if m and (not best or m > best) then best = m end
      end
    end
    if best and b.y < best + CL then
      error(("flycheck: at %d,%d,%d, %d below the flying height over a known top at y %d"):format(b.x, b.y, b.z, best + 1 + CL - b.y, best), 0)
    end
  end
  return W
end

return M
