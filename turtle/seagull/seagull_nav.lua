-- seagull_nav.lua  --  Seagull's way round things: a 3D picture of the blocks near him (from every Geo Scanner
-- result) and an A* search through it. Straight-line flying (seagull.lua's hop) stays the normal way; when a hop is
-- blocked (a cliff, a ledge over him, a cave roof, a tree) seagull.lua asks this for a path to a spot further on and
-- walks it, re-scanning and planning again when something unexpected is in the way. docs/systems/cartographer.md.
--   local nav = dofile("seagull_nav.lua")()
--   nav.observe(blocks, ox, oy, oz, r)          every scan (block offsets as the scanner gives them)
--   nav.go(goal, io) -> true | false, why        walk to goal = { x, y, z } (or as near as it says in why)
--   nav.covered(x, y, z)                         true when a known solid block is above that cell (a roof, a ledge)
--   nav.escape(io) -> true | false, why          from under a roof to open sky (known cells, then exploring)
-- io = { pos = fn -> {x,y,z}, move = fn(dir) -> ok, why  (dir 0-3 compass, "up", "down"), scan = fn -> ok,
--        maxY = n, onStep = fn | nil, margin = n | nil (search box round start and goal, default 10) }

return function()
  local N = {}
  local solid = {}            -- ["x,y,z"] = true: a block he can't fly through
  local colMax = {}           -- ["x,z"] = highest known solid y in that column (for "is something above this cell?")
  local boxes = {}            -- the last few scanned cubes { x, y, z, r }: inside one, a cell that isn't solid is air
  local MAX_BOXES = 12
  local DX = { [0] = 0, 1, 0, -1 }
  local DZ = { [0] = -1, 0, 1, 0 }

  local function key(x, y, z) return x .. "," .. y .. "," .. z end
  N.key = key

  -- Air, water and lava are what he can fly through (turtles move through fluids). Everything else is a wall,
  -- grass tufts and flowers too: that keeps him off the ground.
  local function passable(name)
    return name == "minecraft:air" or name == "minecraft:cave_air" or name == "minecraft:void_air"
      or name:find("water") ~= nil or name:find("lava") ~= nil or name:find("computercraft:turtle") ~= nil
  end

  function N.observe(blocks, ox, oy, oz, r)
    -- Everything inside the scanned cube is now known: clear it, then mark what is there
    for dx = -r, r do
      for dz = -r, r do
        for dy = -r, r do solid[key(ox + dx, oy + dy, oz + dz)] = nil end
        local ck = (ox + dx) .. "," .. (oz + dz)
        if colMax[ck] and colMax[ck] <= oy + r then colMax[ck] = nil end   -- a solid above the cube stays
      end
    end
    for _, b in ipairs(blocks or {}) do
      if type(b) == "table" and type(b.name) == "string" and not passable(b.name) then
        local x, y, z = math.floor(b.x + 0.5), math.floor(b.y + 0.5), math.floor(b.z + 0.5)
        if not (x == 0 and y == 0 and z == 0) then
          solid[key(ox + x, oy + y, oz + z)] = true
          local ck = (ox + x) .. "," .. (oz + z)
          if not colMax[ck] or oy + y > colMax[ck] then colMax[ck] = oy + y end
        end
      end
    end
    table.insert(boxes, 1, { x = ox, y = oy, z = oz, r = r })
    while #boxes > MAX_BOXES do table.remove(boxes) end
    -- Forget walls far from the newest scan (memory stays small on a long flight)
    local n = 0
    for k in pairs(solid) do
      n = n + 1
      if n > 20000 then break end
    end
    if n > 20000 then
      for k in pairs(solid) do
        local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
        if math.abs(x - ox) > 40 or math.abs(z - oz) > 40 or math.abs(y - oy) > 40 then solid[k] = nil end
      end
      for k in pairs(colMax) do
        local x, z = k:match("^(-?%d+),(-?%d+)$")
        if math.abs(x - ox) > 40 or math.abs(z - oz) > 40 then colMax[k] = nil end
      end
      -- Wide (radius 16) scans can still leave a lot: keep only what is near the newest one
      local m = 0
      for _ in pairs(solid) do m = m + 1 end
      if m > 40000 then
        for k in pairs(solid) do
          local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
          if math.abs(x - ox) > 24 or math.abs(z - oz) > 24 or math.abs(y - oy) > 24 then solid[k] = nil end
        end
      end
    end
  end

  function N.isSolid(x, y, z) return solid[key(x, y, z)] == true end
  function N.markSolid(x, y, z)
    solid[key(x, y, z)] = true
    local ck = x .. "," .. z
    if not colMax[ck] or y > colMax[ck] then colMax[ck] = y end
  end
  -- Something solid is known above this cell: a cave roof, an overhang. Only the scanned cubes tell.
  function N.covered(x, y, z)
    local m = colMax[x .. "," .. z]
    return m ~= nil and m > y
  end
  function N.known(x, y, z)
    for _, b in ipairs(boxes) do
      if math.abs(x - b.x) <= b.r and math.abs(y - b.y) <= b.r and math.abs(z - b.z) <= b.r then return true end
    end
    return false
  end

  ---------------------------------------------------------------------------
  -- A*: 6 directions, every move costs 1 fuel. A cell nobody has scanned costs 3, so he goes through known air
  -- when he can. Search stays inside a box round start and goal.
  ---------------------------------------------------------------------------
  local function heapPush(h, node)
    h[#h + 1] = node
    local i = #h
    while i > 1 do
      local p = math.floor(i / 2)
      if h[p].f <= h[i].f then break end
      h[p], h[i] = h[i], h[p]; i = p
    end
  end
  local function heapPop(h)
    local top = h[1]
    local last = table.remove(h)
    if #h > 0 then
      h[1] = last
      local i = 1
      while true do
        local l, r, s = i * 2, i * 2 + 1, i
        if l <= #h and h[l].f < h[s].f then s = l end
        if r <= #h and h[r].f < h[s].f then s = r end
        if s == i then break end
        h[s], h[i] = h[i], h[s]; i = s
      end
    end
    return top
  end

  local STEPS = { { 1, 0, 0, 1 }, { -1, 0, 0, 3 }, { 0, 0, 1, 2 }, { 0, 0, -1, 0 }, { 0, 1, 0, "up" }, { 0, -1, 0, "down" } }

  -- Returns a list of { x, y, z, dir } steps from start (not included) to goal, or nil
  function N.path(s, g, o)
    o = o or {}
    local margin = o.margin or 10
    local x0, x1 = math.min(s.x, g.x) - margin, math.max(s.x, g.x) + margin
    local z0, z1 = math.min(s.z, g.z) - margin, math.max(s.z, g.z) + margin
    local y0 = math.max(o.minY or -60, math.min(s.y, g.y) - margin)
    local y1 = math.min(o.maxY or 320, math.max(s.y, g.y) + margin + 8)
    local limit = o.limit or 30000
    local function h(x, y, z) return math.abs(x - g.x) + math.abs(y - g.y) + math.abs(z - g.z) end
    local open, best, from = {}, {}, {}
    local sk = key(s.x, s.y, s.z)
    best[sk] = 0
    heapPush(open, { x = s.x, y = s.y, z = s.z, g = 0, f = h(s.x, s.y, s.z), k = sk })
    local n = 0
    while #open > 0 do
      local c = heapPop(open)
      if c.x == g.x and c.y == g.y and c.z == g.z then
        local out, k = {}, c.k
        while from[k] do
          local f = from[k]
          table.insert(out, 1, { x = f.x, y = f.y, z = f.z, dir = f.dir })
          k = f.prev
        end
        return out
      end
      if c.g == best[c.k] then
        n = n + 1
        if n > limit then return nil end
        for _, st in ipairs(STEPS) do
          local x, y, z = c.x + st[1], c.y + st[2], c.z + st[3]
          if x >= x0 and x <= x1 and z >= z0 and z <= z1 and y >= y0 and y <= y1 then
            local k = key(x, y, z)
            if not solid[k] then
              local cost = c.g + (N.known(x, y, z) and 1 or 3) + (N.covered(x, y, z) and 12 or 0)   -- go over, not under
              if not best[k] or cost < best[k] then
                best[k] = cost
                from[k] = { x = x, y = y, z = z, dir = st[4], prev = c.k }
                heapPush(open, { x = x, y = y, z = z, g = cost, f = cost + h(x, y, z), k = k })
              end
            end
          end
        end
      end
    end
    return nil
  end

  -- Walk to goal: plan, follow, and on a surprise (a block the scans missed, a mob) mark it, scan and plan again.
  function N.go(goal, io)
    local tries, lastScan, rounds = 0, nil, 0
    while true do
      rounds = rounds + 1
      if rounds > 200 then return false, "stuck" end
      local p = io.pos()
      if p.x == goal.x and p.y == goal.y and p.z == goal.z then return true end
      if solid[key(goal.x, goal.y, goal.z)] then return false, "goal blocked" end
      if io.scan and (not lastScan or math.abs(p.x - lastScan.x) + math.abs(p.y - lastScan.y) + math.abs(p.z - lastScan.z) >= 4) then
        io.scan(); lastScan = { x = p.x, y = p.y, z = p.z }
      end
      local path = N.path(p, goal, { maxY = io.maxY, minY = io.minY, margin = io.margin })
      if not path then return false, "no way" end
      local surprised, rescan = false, false
      for _, st in ipairs(path) do
        local ok, why = io.move(st.dir)
        if not ok then
          why = tostring(why or "")
          if why:lower():find("loaded") then return false, "unloaded" end
          if why:lower():find("fuel") then return false, "fuel" end
          solid[key(st.x, st.y, st.z)] = true
          surprised = true
          break
        end
        if io.onStep then io.onStep() end
        -- moved well away from the last scan: look again and plan from what is really there
        local q = io.pos()
        if io.scan and lastScan and math.abs(q.x - lastScan.x) + math.abs(q.y - lastScan.y) + math.abs(q.z - lastScan.z) >= 6 then
          rescan = true
          break
        end
      end
      if surprised then
        tries = tries + 1
        if tries > 12 then return false, "stuck" end
      end
    end
  end

  ---------------------------------------------------------------------------
  -- Out from under a roof. Nearest known cell with open sky above it (a clear column of 6 in the last scans);
  -- if there is none, the nearest edge of what he has scanned (up is cheap), go there, scan, again.
  ---------------------------------------------------------------------------
  local function search(s, pred)
    local open, best, n = {}, { [key(s.x, s.y, s.z)] = 0 }, 0
    heapPush(open, { x = s.x, y = s.y, z = s.z, f = 0 })
    while #open > 0 do
      local c = heapPop(open)
      local ck = key(c.x, c.y, c.z)
      if c.f == best[ck] then
        if pred(c.x, c.y, c.z) then return c end
        n = n + 1
        if n > 8000 then return nil end
        for _, st in ipairs(STEPS) do
          local x, y, z = c.x + st[1], c.y + st[2], c.z + st[3]
          local k = key(x, y, z)
          if not solid[k] and N.known(x, y, z) then
            local cost = c.f + (st[2] > 0 and 0.7 or st[2] < 0 and 1.4 or 1)
            if not best[k] or cost < best[k] then
              best[k] = cost
              heapPush(open, { x = x, y = y, z = z, f = cost })
            end
          end
        end
      end
    end
    return nil
  end

  function N.escape(io, rounds)
    local visited = {}
    local function sky(x, y, z) return N.known(x, y + 6, z) and not N.covered(x, y, z) end
    local function edge(x, y, z)
      if visited[key(x, y, z)] then return false end
      for _, st in ipairs(STEPS) do
        local x2, y2, z2 = x + st[1], y + st[2], z + st[3]
        if not solid[key(x2, y2, z2)] and not N.known(x2, y2, z2) then return true end
      end
      return false
    end
    for _ = 1, rounds or 40 do
      local p = io.pos()
      if sky(p.x, p.y, p.z) then return true end
      local g = search(p, sky)
      if not g then
        g = search(p, edge)
        if not g then return false, "no way out" end
        visited[key(g.x, g.y, g.z)] = true
      end
      local ok, why = N.go({ x = g.x, y = g.y, z = g.z }, io)
      if not ok and (why == "unloaded" or why == "fuel") then return false, why end
      if io.scan then io.scan() end
    end
    return false, "stuck"
  end

  N.DX, N.DZ = DX, DZ
  return N
end
