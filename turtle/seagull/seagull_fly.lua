-- seagull_fly.lua  --  how Seagull flies: over everything, never through. docs/systems/cartographer.md.
-- He only cares about the surface, so he steers from the heightmap (each column's top block), not a 3D picture.
--   * Height over a column: the highest known top within 2 blocks + 1 + CLEARANCE (CRUISE_Y or higher while
--     cruising). A column nobody has seen counts as nothing: it never lowers him.
--   * Down only onto ground a scan really saw (the top with air above it in the cube). A hole too deep to see never
--     pulls him down: the column is a "pit", kept (and saved by the host) so a reboot doesn't forget it.
--   * Blocked ahead: up, then forward. Up blocked (an overhang): back off one block, climb, try again. Never round
--     or under. He gives up only at MAX_Y.
--   * A scan that shows anything solid over him (a cave, an overhang): nothing is mapped, he goes straight up (back
--     out the way he came if up is blocked) until nothing is over him.
-- Loaded with dofile: `H` is the host (seagull.lua):
--   H.E, H.pos() -> {x,y,z}, H.heading() -> 0..3, H.up() / H.down() -> ok, H.step(h) -> ok, why (turn and move one
--   block), H.blockedWhy() -> text of the last failed step, H.detectDown() -> bool, H.fuel() -> n,
--   H.floorAt(x, z) -> lowest height allowed there (-math.huge when none), H.mapTop(x, z) -> top on the map or nil,
--   H.scan() -> ok, err, H.status() -> state, note, H.setStatus(state, note)

return function(H)
  local F = {}
  local E = H.E
  local DX = { [0] = 0, 1, 0, -1 }
  local DZ = { [0] = -1, 0, 1, 0 }
  local MAX_PITS = 30000
  local MAX_SEEN = 40000

  local seen, seenN = {}, 0     -- ["x,z"] = top a scan really saw this run (air above it in the cube)
  local pits, pitN = {}, 0      -- ["x,z"] = true: a hole too deep to see into; its map top is never a height
  local lastDir = nil           -- the way of his last step, so "the way he came" is the other one

  F.roofed = false              -- the last scan showed something solid over him
  F.lastSeen = 0                -- columns of the last scan's cube that had a block in them
  F.mostly = false              -- ... and that was most of the cube (a column without one is a hole, not far-off ground)
  F.pits = pits
  F.pitsDirty = false

  local function ck(x, z) return x .. "," .. z end
  local function pos() return H.pos() end

  ---------------------------------------------------------------------------
  -- What he knows (the host's absorb feeds these)
  ---------------------------------------------------------------------------
  function F.seeTop(x, z, y)
    local k = ck(x, z)
    if seen[k] == nil then seenN = seenN + 1 end
    seen[k] = y
    if pits[k] then pits[k] = nil; pitN = pitN - 1; F.pitsDirty = true end
  end

  function F.markPit(x, z)
    local k = ck(x, z)
    if pits[k] or pitN >= MAX_PITS then return end
    pits[k] = true; pitN = pitN + 1; F.pitsDirty = true
  end

  function F.setPits(t)
    pits, pitN = {}, 0
    for k, v in pairs(type(t) == "table" and t or {}) do
      if v == true and type(k) == "string" and pitN < MAX_PITS then pits[k] = true; pitN = pitN + 1 end
    end
    F.pits = pits
  end

  -- Forget the pits for which drop(x, z) is true (the region was handed over)
  function F.dropPits(drop)
    for k in pairs(pits) do
      local x, z = k:match("^(-?%d+),(-?%d+)$")
      if x and drop(tonumber(x), tonumber(z)) then pits[k] = nil; pitN = pitN - 1; F.pitsDirty = true end
    end
  end

  -- Called after every scan with how many columns had blocks; keeps memory small on a long flight
  function F.scanned(columns, mostly)
    F.lastSeen, F.mostly = columns, mostly == true
    if seenN > MAX_SEEN then
      local p = pos()
      for k in pairs(seen) do
        local x, z = k:match("^(-?%d+),(-?%d+)$")
        if math.abs(x - p.x) > 48 or math.abs(z - p.z) > 48 then seen[k] = nil; seenN = seenN - 1 end
      end
    end
  end

  function F.seenTop(x, z) return seen[ck(x, z)] end

  -- A known top at (x, z): one a scan saw, else the map's. Never a pit's.
  local function topAt(x, z)
    local k = ck(x, z)
    if pits[k] then return nil end
    return seen[k] or H.mapTop(x, z)
  end

  -- Highest known top within r blocks of (x, z)
  function F.groundNear(x, z, r)
    local best = nil
    for dx = -r, r do
      for dz = -r, r do
        local t = topAt(x + dx, z + dz)
        if t and (not best or t > best) then best = t end
      end
    end
    return best
  end

  -- The height he flies at over (x, z): nil when nothing round it is known
  function F.nominal(x, z)
    local g = F.groundNear(x, z, 2)
    return g and (g + 1 + E.CLEARANCE) or nil
  end

  ---------------------------------------------------------------------------
  -- Moving
  ---------------------------------------------------------------------------
  -- One block back the way he came (the way of his last step reversed, else the reverse of his facing)
  local function retreatDir()
    local d = lastDir or H.heading() or 0
    return (d + 2) % 4
  end

  -- Down onto ground he has seen: never below the top under him + 1 + CLEARANCE (nor the cruising floor)
  local function lower()
    local p = pos()
    if seen[ck(p.x, p.z)] == nil then return end
    local target = math.max(F.nominal(p.x, p.z) or -math.huge, H.floorAt(p.x, p.z))
    while pos().y > target and not H.detectDown() do
      if not H.down() then break end
    end
  end

  -- One block towards compass direction h. level = true: don't sink afterwards.
  -- Returns true, or false + "unloaded", "high", "stuck", "fuel"
  function F.hop(h, level)
    local p = pos()
    local nx, nz = p.x + DX[h], p.z + DZ[h]
    local need = math.max(F.nominal(nx, nz) or -math.huge, H.floorAt(nx, nz))
    if need > E.MAX_Y then return false, "high" end
    local backs = 0
    for _ = 1, 600 do
      if H.fuel() == 0 then return false, "fuel" end
      p = pos()
      if p.y < need then
        if not H.up() then
          -- something over him (an overhang): back off one block, climb there, try again
          if p.y >= E.MAX_Y then return false, "high" end
          backs = backs + 1
          if backs > 16 or not H.step((h + 2) % 4) then return false, "stuck" end
        end
      else
        local ok = H.step(h)
        if ok then
          lastDir = h
          if not level then lower() end
          return true
        end
        if tostring(H.blockedWhy() or ""):lower():find("loaded") then return false, "unloaded" end
        if p.y >= E.MAX_Y then return false, "high" end
        need = p.y + 1      -- blocked ahead: up, then forward
      end
    end
    return false, "stuck"
  end

  -- Sideways at this height to the nearest column a scan saw (within the last scan's cube)
  local function toSeenColumn()
    local p = pos()
    local best, bd = nil, math.huge
    for dx = -E.RADIUS, E.RADIUS do
      for dz = -E.RADIUS, E.RADIUS do
        local k = ck(p.x + dx, p.z + dz)
        local d = math.abs(dx) + math.abs(dz)
        if seen[k] ~= nil and d > 0 and d < bd then best, bd = { p.x + dx, p.z + dz }, d end
      end
    end
    if not best then return false end
    local guard = 0
    while (pos().x ~= best[1] or pos().z ~= best[2]) and guard < 40 do
      guard = guard + 1
      local q = pos()
      local h
      if math.abs(best[1] - q.x) >= math.abs(best[2] - q.z) then h = best[1] > q.x and 1 or 3
      else h = best[2] > q.z and 2 or 0 end
      local y0 = q.y
      local ok = F.hop(h, true)
      if not ok then return false end
      if pos().y < y0 then return false end
    end
    return pos().x == best[1] and pos().z == best[2]
  end

  ---------------------------------------------------------------------------
  -- Out from under a roof: straight up, and back out the way he came when up is blocked
  ---------------------------------------------------------------------------
  function F.openSky()
    if not F.roofed then return true end
    local p = pos()
    local st0, note0 = H.status()
    H.setStatus("error", ("Underground at %d %d %d, climbing out"):format(p.x, p.y, p.z))
    local dir, flips = retreatDir(), 0
    for _ = 1, 300 do
      local climbed, blocked = 0, false
      while climbed < math.max(1, E.RADIUS - 1) do
        if H.fuel() == 0 then return false, "Underground at " .. pos().x .. " " .. pos().y .. " " .. pos().z end
        if pos().y >= E.MAX_Y then break end
        if H.up() then climbed = climbed + 1 else blocked = true; break end
      end
      if blocked then
        -- an overhang or a tunnel roof: back off one block the way he came, then up again
        if not H.step(dir) then
          flips = flips + 1
          dir = (dir + 2) % 4
          if flips > 3 then
            local q = pos()
            H.setStatus("error", ("Underground at %d %d %d, no way out"):format(q.x, q.y, q.z))
            return false, "Underground at " .. q.x .. " " .. q.y .. " " .. q.z
          end
        end
      end
      local ok, err = H.scan()
      if not ok then return false, err end
      if not F.roofed then H.setStatus(st0, note0); return true end
    end
    local q = pos()
    return false, "Underground at " .. q.x .. " " .. q.y .. " " .. q.z
  end

  ---------------------------------------------------------------------------
  -- After a scan: up to the height wanted here; down only onto seen ground. drop = true (he has arrived): from
  -- cruise he drops straight down, scanning every RADIUS - 1; if the scan sees ground nearly all round him but not
  -- under him he is over a hole: sideways at that height to the nearest seen column first.
  ---------------------------------------------------------------------------
  function F.settle(drop)
    for _ = 1, 80 do
      local p = pos()
      local floor = H.floorAt(p.x, p.z)
      local nom = F.nominal(p.x, p.z)
      local target = math.max(nom or -math.huge, floor)
      -- up first
      if p.y < target and target <= E.MAX_Y then
        while pos().y < target and H.up() do end
        p = pos()
      end
      local step = math.max(1, E.RADIUS - 1)
      local moved = 0
      if seen[ck(p.x, p.z)] ~= nil then
        if p.y <= target then return true end
        local n = math.min(step, p.y - target)
        while moved < n and not H.detectDown() and H.down() do moved = moved + 1 end
        if moved == 0 then return true end        -- standing on something the scan doesn't count
      elseif not drop then
        return true                               -- on his way: he is where he flies, nothing to come down from
      elseif F.mostly then
        -- ground nearly all round him, none under him: a hole. Already at his flying height there? Then nothing to do.
        if nom and p.y <= target then return true end
        if not toSeenColumn() then return true end
        moved = 1
      else
        -- little in the cube: he is high over unseen ground. Straight down, a scan's worth at a time, but never
        -- below the height the map already gives for here.
        local stop = math.max(floor, nom or -math.huge)
        if p.y - 1 < stop or p.y <= -60 then return true end
        while moved < step and pos().y - 1 >= stop and not H.detectDown() and H.down() do moved = moved + 1 end
        if moved == 0 then return true end
      end
      local ok, err = H.scan()
      if not ok then return false, err end
      if F.roofed then
        ok, err = F.openSky()
        if not ok then return false, err end
      end
    end
    return true
  end

  return F
end
