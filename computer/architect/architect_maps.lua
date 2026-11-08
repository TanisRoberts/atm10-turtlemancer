-- architect_maps.lua  --  the Map tab (one layer from above) and the Side tab. A part of architect.lua.

local floor, max, min = math.floor, math.max, math.min

---------------------------------------------------------------------------
-- Map: one layer from above, in world coordinates
---------------------------------------------------------------------------
function viewLayer()
  local st = R.status
  local cur = st and st.layer or 1
  return min(max(V.layer or cur, 1), max(P and P.total or 1, 1)), cur
end
function mapGrid(k, cur)
  local st = R.status
  local key = table.concat({ k, cur, st and st.idx or 0, st and st.work or "", siteKey(), #S.gaps, finished() and 1 or 0 }, ":")
  if V.grid and V.gridKey == key then return V.grid end
  local grid = { done = 0, todo = 0, gaps = 0 }
  local y = P.ys[k]
  local gapAt = {}
  for _, g in ipairs(S.gaps) do gapAt[g[1] .. "," .. g[3]] = g[2] end
  local past = k < cur or finished()
  local idx = (st and st.work == "layer" and k == cur) and (st.idx or 1) or (past and 1e9 or 0)
  for i, c in ipairs(layerCells(k)) do
    local wx, wz = worldOf(c[1], c[3])
    local role
    if gapAt[c[1] .. "," .. c[3]] and gapAt[c[1] .. "," .. c[3]] == c[2] then role = "mark"; grid.gaps = grid.gaps + 1
    elseif i < idx then role = "good"; grid.done = grid.done + 1
    elseif i == idx then role = "gold"; grid.todo = grid.todo + 1
    else role = "bar"; grid.todo = grid.todo + 1 end
    local old = grid[wx .. "," .. wz]
    if not old or role == "gold" or role == "bar" and old == "good" then grid[wx .. "," .. wz] = role end
  end
  V.grid, V.gridKey = grid, key
  return grid
end
function siteBounds(pad)
  local s = S.site
  local ew, ns = footprint(s.rot)
  local x1, x2, z1, z2 = s.cx, s.cx + ew - 1, s.cz - ns + 1, s.cz
  x1, x2, z1, z2 = min(x1, s.dx), max(x2, s.dx), min(z1, s.dz), max(z2, s.dz)
  return { x1 = x1 - pad, x2 = x2 + pad, z1 = z1 - pad, z2 = z2 + pad }
end
function drawMapBody(v, area, k, cur)
  local st = R.status
  local grid = mapGrid(k, cur)
  local s = S.site
  local wx, wz = worldOf(st and st.x or 0, st and st.z or 0)
  local b = siteBounds(3)
  v:map({ get = function(x, z)
            if x == s.dx and z == s.dz then return { "bg", "D", "the dock", "gold" } end
            local role = grid[x .. "," .. z]
            return role or "bg"
          end,
          at = { x = wx, z = wz, facing = "W", fg = "bg", bg = "info" }, bounds = b, area = area })
  return grid
end

function drawMap(v)
  headerFor(v)
  if not (P and siteOK(S.site)) then v:put(2, 4, "No build with a site yet. Type setup.", "warn", "bg"); return end
  local k, cur = viewLayer()
  local r = v:rect(true)
  local g = mapGrid(k, cur)
  v:put(2, 3, fit(("Layer %d/%d  Y %d  %d done, %d to do, %d gaps"):format(k, P.total, S.site.cy + P.ys[k], g.done, g.todo, g.gaps), v.W - 2), "fg", "bg")
  drawMapBody(v, { x1 = 1, y1 = 4, x2 = v.W, y2 = r.y2 }, k, cur)
end

---------------------------------------------------------------------------
-- Side: the build from the side, ground line at the bottom
---------------------------------------------------------------------------
function drawSide(v)
  headerFor(v)
  if not (P and siteOK(S.site)) then v:put(2, 4, "No build with a site yet. Type setup.", "warn", "bg"); return end
  local r = v:rect(true)
  local W = v.W
  local rows = r.y2 - 4
  local ew = footprint(S.site.rot)
  local cols = W - 8
  local st = R.status
  local cur = st and st.layer or 1
  local perRow = math.ceil(P.total / rows)
  local steps = rotSteps(S.site.rot)
  local sz = P.plan.info.size
  v:put(2, 3, fit(("%s from the side, %d layers"):format(S.name or "Build", P.total), W - 2), "fg", "bg")
  for row = 1, math.ceil(P.total / perRow) do
    local hi = P.total - (row - 1) * perRow
    local lo = max(hi - perRow + 1, 1)
    local x0, x1 = 1e9, -1
    for k = lo, hi do
      local e = P.ext[k]
      local a, b
      if steps == 0 then a, b = e[1], e[2] elseif steps == 2 then a, b = sz.x - 1 - e[2], sz.x - 1 - e[1]
      elseif steps == 1 then a, b = sz.z - 1 - e[4], sz.z - 1 - e[3] else a, b = e[3], e[4] end
      x0, x1 = min(x0, a), max(x1, b)
    end
    local role = (cur > hi) and "good" or (cur >= lo and "info" or "bar")
    if finished() then role = "good" end
    local c0, c1 = floor(x0 * cols / ew), max(floor((x1 + 1) * cols / ew) - 1, floor(x0 * cols / ew))
    local y = 3 + row
    v:put(2, y, ("%3d"):format(S.site.cy + P.ys[hi]), "dim", "bg")
    v:put(7 + c0, y, (" "):rep(c1 - c0 + 1), "fg", role)
  end
  local gy = 4 + math.ceil(P.total / perRow)
  v:put(7, gy, ("-"):rep(cols), "soil", "bg")
  v:put(2, gy, "ground", "dim", "bg")
end

