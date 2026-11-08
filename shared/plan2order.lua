-- plan2order: the part of the placement planner (plan2place) that orders one layer's cells. Pure Lua 5.2, no globals.
-- Loaded by plan2place with require("plan2order"). Constraints and entries: see plan2place.lua.
--
--   order.seq(plan, y) -> items, forced     items = { kind = "cell"|"fill", x, z, y, p, m } in building order;
--                                           forced = cells whose constraints formed a loop (classify turns them into U)
--   order.kinds(plan) -> { [paletteIndex] = { kind = "stair"|"slab"|"torch"|"gate"|"chest"|"axis"|nil, facing (0..3),
--                          half, type, axis, plain, item, name, state } }

local M = {}

local LET = { [0] = "N", "E", "S", "W" }
local IDX = { N = 0, E = 1, S = 2, W = 3 }
local FACE = { [0] = "north", "east", "south", "west" }
local FIDX = { north = 0, east = 1, south = 2, west = 3 }
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }

-- what kind of block each palette entry is
local function kinds(plan)
  if plan._k then return plan._k end
  local K = {}
  for i, e in ipairs(plan.info.palette) do
    local id = e.name:match("^[^:]*:(.*)$") or e.name
    local st = e.state or {}
    local k = { name = e.name, state = e.state, plain = next(st) == nil, facing = FIDX[st.facing], half = st.half, type = st.type, axis = st.axis }
    if id:find("_stairs$") then k.kind = "stair"
    elseif id:find("_slab$") then k.kind = "slab"
    elseif id:find("wall_torch$") then k.kind = "torch"; k.item = (e.name:gsub("wall_torch$", "torch"))
    elseif id:find("_fence_gate$") then k.kind = "gate"
    elseif id:find("chest$") then k.kind = "chest"
    elseif st.axis then k.kind = "axis" end
    K[i] = k
  end
  plan._k = K
  return K
end

-- ---------------------------------------------------------------- one layer's order
-- Returns items { kind = "cell"|"fill", x, z, y, p, m } in building order, and the cells that had to be forced
-- (their constraints formed a loop).
local function seq(plan, y)
  local sx, sz = plan.info.size.x, plan.info.size.z
  local marksY = plan.marks[y] or {}
  local marksUp = plan.marks[y + 1] or {}
  local nodes, at = {}, {}
  for z = 0, sz - 1 do
    for x = 0, sx - 1 do
      local p = plan.get(x, y, z)
      if p then
        local up = marksUp[z * sx + x]
        if not (up and up:sub(1, 1) == "T") then   -- the block under a top-half stair/slab is filled in layer y+1
          local n = { x = x, z = z, p = p, m = marksY[z * sx + x], idx = #nodes + 1 }
          nodes[n.idx] = n
          at[z * sx + x] = n
        end
      end
    end
  end
  local K = kinds(plan)
  local succ, pc = {}, {}
  local function nodeAt(x, z)
    if x < 0 or z < 0 or x >= sx or z >= sz then return nil end
    return at[z * sx + x]
  end
  local function edge(a, b)
    if a and b and a ~= b then
      local s = succ[a.idx]
      if not s then s = {}; succ[a.idx] = s end
      s[#s + 1] = b.idx
      pc[b.idx] = (pc[b.idx] or 0) + 1
    end
  end
  for _, n in ipairs(nodes) do
    if n.m then
      local h, d = n.m:sub(1, 1), IDX[n.m:sub(2, 2)]
      if h == "F" and d then
        edge(n, nodeAt(n.x - DX[d], n.z - DZ[d]))
        local kind = K[n.p].kind
        if kind == "torch" or kind == "axis" then edge(nodeAt(n.x + DX[d], n.z + DZ[d]), n) end
      elseif h == "T" and d then
        edge(n, nodeAt(n.x + DX[d], n.z + DZ[d]))
        if y > 0 then n.fill = { kind = "fill", x = n.x, z = n.z, y = y - 1, p = plan.get(n.x, y - 1, n.z), m = "B" .. n.m:sub(2, 2) } end
      end
    end
  end

  local grid = {}
  local nready = 0
  local function ready(n) grid[n.x * 65536 + n.z] = n; nready = nready + 1 end
  for _, n in ipairs(nodes) do if (pc[n.idx] or 0) == 0 then ready(n) end end

  local function nearest(cx, cz)
    local best
    if cx then
      for r = 1, 4 do
        local bd = math.huge
        for dx = -r, r do
          for dz = -r, r do
            if math.max(math.abs(dx), math.abs(dz)) == r then
              local n = grid[(cx + dx) * 65536 + cz + dz]
              if n then
                local dist = math.abs(dx) + math.abs(dz)
                if dist < bd or (dist == bd and n.idx < best.idx) then bd, best = dist, n end
              end
            end
          end
        end
        if best then return best end
      end
    end
    local bd = math.huge
    for _, n in pairs(grid) do
      local dist = cx and (math.abs(n.x - cx) + math.abs(n.z - cz)) or 0
      if dist < bd or (dist == bd and n.idx < best.idx) then bd, best = dist, n end
    end
    return best
  end

  local out, forced = {}, {}
  local left, cx, cz, tick = #nodes, nil, nil, 0
  while left > 0 do
    local pick
    if nready == 0 then                      -- a loop of constraints: break it at a marked cell
      for _, n in ipairs(nodes) do if not n.done and n.m then pick = n; break end end
      if not pick then for _, n in ipairs(nodes) do if not n.done then pick = n; break end end end
      forced[#forced + 1] = { x = pick.x, y = y, z = pick.z, m = pick.m }
    else
      pick = nearest(cx, cz)
      grid[pick.x * 65536 + pick.z] = nil
      nready = nready - 1
    end
    pick.done = true
    left = left - 1
    cx, cz = pick.x, pick.z
    out[#out + 1] = { kind = "cell", x = pick.x, z = pick.z, y = y, p = pick.p, m = pick.m }
    if pick.fill then out[#out + 1] = pick.fill end
    for _, s in ipairs(succ[pick.idx] or {}) do
      pc[s] = pc[s] - 1
      if pc[s] == 0 and not nodes[s].done then ready(nodes[s]) end
    end
    tick = tick + 1
    if tick % 2000 == 0 and plan.yield then plan.yield() end
  end
  return out, forced
end


M.LET, M.IDX, M.FACE, M.FIDX, M.DX, M.DZ = LET, IDX, FACE, FIDX, DX, DZ
M.kinds, M.seq = kinds, seq
return M
