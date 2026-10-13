-- riggerplan.lua  --  plan-file maths shared by Rigger (the builder) and the Architect (his screen).
--
-- Both sides must agree exactly on the order Rigger builds a layer in, so the Architect can tell
-- which blocks of the current layer are done just from Rigger's cell number. That order lives here.
--
-- Plan file format (e.g. mossy.plan):
--   #info <serialized table>    name, palette, layers, ybase, topY, minX..maxZ, blocks, bill
--   #ext                         then lines "x,z,ch": the edge columns (walls down to the seabed)
--   #L <n>                       then lines "z|x0|<count><char>...": layer n, run-length rows
--                                ("." = nothing there)

local RP = {}

function RP.load(path)
  local f = fs.open(path, "r")
  if not f then error("Plan file not found: " .. tostring(path), 0) end
  local plan = { ext = {}, layers = {} }
  local section, cur
  while true do
    local line = f.readLine()
    if not line then break end
    if line:sub(1, 6) == "#info " then
      plan.info = textutils.unserialize(line:sub(7))
    elseif line == "#ext" then
      section = "ext"
    elseif line:sub(1, 3) == "#L " then
      section = "L"; cur = {}
      plan.layers[tonumber(line:sub(4))] = cur
    elseif line ~= "" then
      if section == "ext" then
        local x, z, ch = line:match("^(%-?%d+),(%-?%d+),(%a)$")
        plan.ext[#plan.ext + 1] = { tonumber(x), tonumber(z), ch }
      elseif section == "L" then
        local z, x0, rle = line:match("^(%-?%d+)|(%-?%d+)|(.+)$")
        cur[#cur + 1] = { tonumber(z), tonumber(x0), rle }
      end
    end
  end
  f.close()
  if not plan.info then error("Not a plan file: " .. path, 0) end
  return plan
end

-- Plan x/z -> world x/z/y for a site { cx, cz, sea, rot } (rot: clockwise steps of 90, from above)
function RP.toWorld(site, px, py, pz)
  local r = (site.rot or 0) % 360
  local x, z = px, pz
  if r == 90 then x, z = -pz, px elseif r == 180 then x, z = -px, -pz elseif r == 270 then x, z = pz, -px end
  return site.cx + x, site.sea + py, site.cz + z
end

-- Always go to the nearest unbuilt cell (follows the island's outline instead of zig-zagging
-- across the hollow middle). Deterministic, so a restart (and the Architect) get the same order.
local function nearestOrder(cells)
  if #cells < 3 then return cells end
  local grid = {}
  local function k(x, z) return x * 65536 + z end
  for i, c in ipairs(cells) do grid[k(c[1], c[2])] = i end
  local used, out = {}, {}
  local cur = 1
  for _ = 1, #cells do
    used[cur] = true
    out[#out + 1] = cells[cur]
    grid[k(cells[cur][1], cells[cur][2])] = nil
    local cx, cz = cells[cur][1], cells[cur][2]
    local best
    for r = 1, 4 do                       -- look in growing rings first (fast path)
      local bd = math.huge
      for dx = -r, r do
        for dz = -r, r do
          if math.max(math.abs(dx), math.abs(dz)) == r then
            local j = grid[k(cx + dx, cz + dz)]
            if j then
              local d = math.abs(dx) + math.abs(dz)
              if d < bd or (d == bd and j < best) then bd, best = d, j end
            end
          end
        end
      end
      if best then break end
    end
    if not best then                      -- nothing close: scan everything left
      local bd = math.huge
      for j, c in ipairs(cells) do
        if not used[j] then
          local d = math.abs(c[1] - cx) + math.abs(c[2] - cz)
          if d < bd then bd, best = d, j end
        end
      end
    end
    if not best then break end
    cur = best
  end
  return out
end
RP.nearestOrder = nearestOrder

-- A layer's run-length rows -> its cells { px, pz, ch } in Rigger's building order
function RP.orderRows(rows)
  local cells = {}
  for ri, row in ipairs(rows or {}) do
    local z, x, rowCells = row[1], row[2], {}
    for countStr, ch in row[3]:gmatch("(%d+)(.)") do
      local count = tonumber(countStr)
      if ch ~= "." then
        for i = 0, count - 1 do rowCells[#rowCells + 1] = { x + i, z, ch } end
      end
      x = x + count
    end
    if ri % 2 == 0 then
      for i = #rowCells, 1, -1 do cells[#cells + 1] = rowCells[i] end
    else
      for _, c in ipairs(rowCells) do cells[#cells + 1] = c end
    end
  end
  return nearestOrder(cells)
end

-- World box of the plan footprint at the site (no padding)
function RP.bounds(info, site)
  local b = { x1 = math.huge, x2 = -math.huge, z1 = math.huge, z2 = -math.huge }
  for _, x in ipairs({ info.minX, info.maxX }) do
    for _, z in ipairs({ info.minZ, info.maxZ }) do
      local wx, _, wz = RP.toWorld(site, x, 0, z)
      b.x1 = math.min(b.x1, wx); b.x2 = math.max(b.x2, wx)
      b.z1 = math.min(b.z1, wz); b.z2 = math.max(b.z2, wz)
    end
  end
  b.y1 = site.sea + info.ybase
  b.y2 = site.sea + info.topY
  return b
end

-- Per layer: world x and z extents of what's in it (for the Architect's side view)
function RP.profile(plan, site)
  local out = {}
  for n = 1, plan.info.layers do
    local x1, x2, z1, z2 = math.huge, -math.huge, math.huge, -math.huge
    for _, row in ipairs(plan.layers[n] or {}) do
      local x = row[2]
      for countStr, ch in row[3]:gmatch("(%d+)(.)") do
        local count = tonumber(countStr)
        if ch ~= "." then
          x1 = math.min(x1, x); x2 = math.max(x2, x + count - 1)
          z1 = math.min(z1, row[1]); z2 = math.max(z2, row[1])
        end
        x = x + count
      end
    end
    if x1 <= x2 then
      local ax, _, az = RP.toWorld(site, x1, 0, z1)
      local bx, _, bz = RP.toWorld(site, x2, 0, z2)
      out[n] = { math.min(ax, bx), math.max(ax, bx), math.min(az, bz), math.max(az, bz) }
    else
      out[n] = false
    end
  end
  return out
end

return RP
