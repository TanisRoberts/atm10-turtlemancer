-- plan2place: the placement planner for plan v2 (docs/systems/weaver.md s.4). Pure functions, Lua 5.2, no globals.
-- Loaded with require("plan2place"); plan2 loads it when it builds a plan.
--
--   place.classify(plan)         decides for every cell how the Weaver places it and writes plan.marks (the #M lines),
--                                plan.ulist and plan.info.stats / ureasons. Called once, by plan2.build.
--   place.layer(plan, y, rot)    the ordered cell list of layer y for a build turned rot (0/90/180/270, clockwise from
--                                above) -> { entry... }. The Architect calls this and sends the list; a test calls it too.
--   entry = { x, y, z,           plan coords turned by rot, about the plan's origin (the Architect adds the site origin;
--                                same turn as weaverplan.toWorld). A fill entry has the y of the cell it fills (y-1).
--             px, pz, p,         the unturned x, z and the palette index
--             name, state,       block name and its state with facing/axis turned
--             how,               nil (default: hover above, turn to `turn`, placeDown) | "F" | "T" | "2" | "U" | "B"
--             d,                 F: heading to place with (towards the wall for a wall torch). T: the side `d` of the
--                                block under (B) the Weaver goes down. B: the same d. Compass letters "N","E","S","W"
--             turn,              the letter the Weaver faces before placing (nil: any)
--             item, n }          what to put in the hand (a wall torch is a torch) and how many placements (double slab: 2)
--   how: F = stand in the cell behind (cell - d), face d, place.  T = this top-half stair/slab goes down first (air under
--   it); the entry "B" right after it fills the block under it (cell y-1) from side d: go down the column B+d, face
--   away from d, place forward.  2 = placeDown twice.  U = could not be done as asked, placed the default way.
--   Marks in the file: "F<d>", "T<d>", "2", "U". Heading letters: N = -z, E = +x, S = +z, W = -x.
--
-- Order inside a layer: nearest neighbour (as weaverplan does), among the cells whose constraints are met:
--   F<d> at c       c before the cell it stands in (c - d); a wall torch's wall, or the block a sideways log clicks (c + d), before c
--   T<d> at S       S before the cell (B + d, y) on the Weaver's way down; B is not in layer y-1, it follows S in layer y

local M = {}

local O = require("plan2order")
local LET, IDX, FACE, FIDX, DX, DZ = O.LET, O.IDX, O.FACE, O.FIDX, O.DX, O.DZ
local kinds, seq = O.kinds, O.seq

-- ---------------------------------------------------------------- classify
function M.classify(plan)
  local info = plan.info
  local sx, sy, sz = info.size.x, info.size.y, info.size.z
  local K = kinds(plan)
  local get = plan.get
  local marks, ulist = {}, {}
  plan.marks, plan.ulist = marks, ulist
  local function has(x, y, z) if y < 0 then return true end return get(x, y, z) ~= nil end   -- under layer 0 is the ground
  local function put(x, y, z, m)
    local t = marks[y]
    if not t then t = {}; marks[y] = t end
    t[z * sx + x] = m
  end
  local function U(x, y, z, why)
    put(x, y, z, "U")
    ulist[#ulist + 1] = { x = x, y = y, z = z, name = K[get(x, y, z)].name, why = why }
  end
  local function plainB(x, y, z)                          -- can the block under a stair/slab be placed from the side?
    local p = get(x, y, z)
    if not p or not K[p].plain then return false end
    for i = 0, 3 do                                       -- nothing next to it hangs on or clicks it
      local q = get(x + DX[i], y, z + DZ[i])
      if q and (K[q].kind == "torch" or (K[q].kind == "axis" and K[q].axis ~= "y")) then return false end
    end
    return true
  end
  local function tryT(x, y, z)
    if y == 0 then return nil, "top half on the ground" end
    if not plainB(x, y - 1, z) then return nil, "the block under it is not a plain block" end
    for pass = 1, 2 do
      for i = 0, 3 do
        local nx, nz = x + DX[i], z + DZ[i]
        if not has(nx, y - 1, nz) and (pass == 2 or not has(nx, y, nz)) then return LET[i] end
      end
    end
    return nil, "no free side to fill the block under it"
  end

  for y = 0, sy - 1 do
    for z = 0, sz - 1 do
      for x = 0, sx - 1 do
        local p = get(x, y, z)
        if p then
          local k = K[p]
          local under = has(x, y - 1, z)
          if k.kind == "stair" then
            if k.half == "top" then
              if under then
                local d, why = tryT(x, y, z)
                if d then put(x, y, z, "T" .. d) else U(x, y, z, why) end
              end
            elseif not under then
              put(x, y, z, "F" .. LET[k.facing or 0])
            end
          elseif k.kind == "slab" then
            if k.type == "double" then put(x, y, z, "2")
            elseif k.type == "top" then
              if under then
                local d, why = tryT(x, y, z)
                if d then put(x, y, z, "T" .. d) else U(x, y, z, why) end
              end
            elseif not under then                        -- bottom slab over air: stand in a free cell beside it
              local found
              for i = 0, 3 do
                if not has(x - DX[i], y, z - DZ[i]) then found = LET[i]; break end
              end
              if found then put(x, y, z, "F" .. found) else U(x, y, z, "no free side to stand on") end
            end
          elseif k.kind == "torch" then
            local wd = ((k.facing or 0) + 2) % 4             -- the wall is behind the torch's facing
            if y > 0 and not has(x + DX[wd], y, z + DZ[wd]) then U(x, y, z, "no wall to hang on")
            else put(x, y, z, "F" .. LET[wd]) end
          elseif k.kind == "axis" and k.axis ~= "y" then
            local plus = k.axis == "x" and 1 or 2             -- east or south
            if has(x + DX[plus], y, z + DZ[plus]) or (y > 0 and not has(x, y - 1, z)) then
              put(x, y, z, "F" .. LET[plus])
            else
              U(x, y, z, "nothing to click")
            end
          end
        end
      end
    end
    if plan.yield then plan.yield() end
  end

  -- loops among the constraints: from the top down (a layer's order depends on the marks of the layer above)
  for y = sy - 1, 0, -1 do
    for _ = 1, 8 do
      local _, forced = seq(plan, y)
      if #forced == 0 then break end
      for _, f in ipairs(forced) do
        if f.m and f.m ~= "U" then U(f.x, f.y, f.z, "placement order loops") end
      end
    end
  end

  local stats, reasons = { F = 0, T = 0, U = 0, ["2"] = 0 }, {}
  for _, t in pairs(marks) do
    for _, m in pairs(t) do
      local h = m:sub(1, 1)
      stats[h] = (stats[h] or 0) + 1
    end
  end
  for _, u in ipairs(ulist) do reasons[u.why] = (reasons[u.why] or 0) + 1 end
  info.stats, info.ureasons = stats, reasons
  return stats
end

-- ---------------------------------------------------------------- a layer for the Architect
local function turnFacing(i, steps) return (i + steps) % 4 end

function M.layer(plan, y, rot)
  rot = (rot or 0) % 360
  local steps = math.floor(rot / 90) % 4
  local K = kinds(plan)
  local items = seq(plan, y)
  local pal = plan.info.palette
  local out = {}
  for _, it in ipairs(items) do
    local k, e = K[it.p], pal[it.p]
    local h = it.m and it.m:sub(1, 1)
    local d = it.m and IDX[it.m:sub(2, 2)]
    local turn
    if it.kind == "fill" then
      h, turn = "B", d and (d + 2) % 4
    elseif h == "F" then
      turn = d
    elseif k.kind == "stair" or k.kind == "gate" then
      turn = k.facing
    elseif k.kind == "chest" then
      turn = k.facing and (k.facing + 2) % 4
    end
    if h == "2" or h == "T" and k.kind == "slab" then turn = nil end
    local state
    if e.state then
      state = {}
      for a, b in pairs(e.state) do state[a] = b end
      if state.facing then state.facing = FACE[turnFacing(FIDX[state.facing] or 0, steps)] end
      if (state.axis == "x" or state.axis == "z") and steps % 2 == 1 then state.axis = state.axis == "x" and "z" or "x" end
    end
    local x, z = it.x, it.z
    if steps == 1 then x, z = -it.z, it.x elseif steps == 2 then x, z = -it.x, -it.z elseif steps == 3 then x, z = it.z, -it.x end
    local item, per = e.name:gsub("wall_torch$", "torch"), 1
    if e.state and e.state.type == "double" then per = 2 end
    out[#out + 1] = {
      x = x, y = it.y, z = z, px = it.x, pz = it.z, p = it.p, name = e.name, state = state,
      how = h, d = d and LET[turnFacing(d, steps)] or nil, turn = turn and LET[turnFacing(turn, steps)] or nil,
      item = item, n = per,
    }
  end
  return out
end

return M
