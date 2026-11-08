-- architect_plan.lua  --  the build: dropped file -> plan, layers as cell lists in dock coordinates, the bill, the gap list.
-- A part of architect.lua. Plan format: docs/systems/weaver.md sections 3-4.

P = nil          -- the loaded build: { plan, file, ys = {plan y per layer}, cnt, items, ext, total, blocks }
LC = {}          -- layer k -> { key, cells } (raw, ordered, in dock coordinates)

local floor = math.floor

local function yielder()
  local last = now()
  return function()
    if now() - last >= 1 then sleep(0); last = now() end
    R.read.step = (R.read.step or 0) + 1
  end
end

function safeName(name)
  return (tostring(name):gsub("[^%w%-_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")):sub(1, 40)
end

-- Layers are the plan layers that have blocks, numbered from 1. cnt: blocks, items: what they need, ext: x/z extent.
function setPlan(plan, file)
  local info = plan.info
  local sx = info.size.x
  local p = { plan = plan, file = file, ys = {}, cnt = {}, items = {}, ext = {}, blocks = 0, byLayer = {} }
  for y = 0, info.size.y - 1 do
    local c, it = 0, {}
    local x0, x1, z0, z1 = 1e9, -1, 1e9, -1
    for idx, pi in pairs(plan.grid[y] or {}) do
      c = c + 1
      local e = info.palette[pi]
      local item = e.name:gsub("wall_torch$", "torch")
      it[item] = (it[item] or 0) + ((e.state and e.state.type == "double") and 2 or 1)
      local x, z = idx % sx, floor(idx / sx)
      if x < x0 then x0 = x end
      if x > x1 then x1 = x end
      if z < z0 then z0 = z end
      if z > z1 then z1 = z end
    end
    if c > 0 then
      local k = #p.ys + 1
      p.ys[k], p.cnt[k], p.items[k], p.ext[k] = y, c, it, { x0, x1, z0, z1 }
      p.byLayer[y] = k
      p.blocks = p.blocks + c
    end
  end
  p.total = #p.ys
  P, LC = p, {}
  return p
end

function loadBuild()
  if not S.file or not fs.exists(S.file) then return false end
  local plan, err = plan2.load(S.file)
  if not plan or not plan.hashOK then return false, err or "the saved build is damaged" end
  setPlan(plan, S.file)
  return true
end

-- A dropped file: .litematic (converted) or .plan2. Runs in its own coroutine (the screen keeps going).
function readFile(name, bytes)
  R.read = { name = name, size = #bytes, step = 0 }
  local plan, rep, err
  if name:lower():match("%.plan2$") then
    plan, err = plan2.parse(bytes)
    if plan and not plan.hashOK then plan, err = nil, "that .plan2 is damaged (hash does not match)" end
  elseif name:lower():match("%.litematic$") then
    plan, rep = plan2.fromLitematic(bytes, { name = name:gsub("%.[^.]*$", ""), yield = yielder() })
    if not plan then err = rep; rep = nil end
  else
    err = "that is not a .litematic or .plan2 file"
  end
  if not plan then
    R.read = { name = name, err = tostring(err) }
    addLog("build file refused: " .. tostring(err))
    return
  end
  local info = plan.info
  local text = plan2.text(plan)                    -- sets info.hash
  info.name = (info.name and info.name ~= "") and info.name or name:gsub("%.[^.]*$", "")
  text = plan2.text(plan)
  R.read.report = rep
  -- a replacement Architect: the file must be the Weaver's build
  if R.relink and R.relink.state and R.relink.state.hash and R.relink.state.hash ~= info.hash then
    R.read = { name = name, err = ("That is not %s (hash differs)"):format(R.relink.state.build or "his build") }
    return
  end
  if not fs.exists(BUILDS) then fs.makeDir(BUILDS) end
  local file = BUILDS .. "/" .. safeName(info.name) .. ".plan2"
  local f = fs.open(file, "w")
  if not f then R.read = { name = name, err = "cannot write " .. file .. " (disk full?)" }; return end
  f.write(text); f.close()
  setPlan(plan, file)
  local keep = S.hash == info.hash
  S.file, S.name, S.hash = file, info.name, info.hash
  if not keep then S.site, S.started, S.gaps, S.held, R.acked, R.out = S.site, false, {}, {}, {}, nil end
  if R.relink and R.relink.state then S.site = S.site or R.relink.site end
  save()
  R.read = { name = name, done = true, report = rep }
  addLog("loaded " .. info.name .. ", " .. comma(info.blocks) .. " blocks")
end

---------------------------------------------------------------------------
-- The site: where the dock and the build's south-west corner are, and the turn
---------------------------------------------------------------------------
function rotSteps(rot) return floor(((rot or 0) % 360) / 90) end
-- E-W and N-S size of the footprint after turning
function footprint(rot)
  local sz = P.plan.info.size
  if rotSteps(rot) % 2 == 1 then return sz.z, sz.x end
  return sz.x, sz.z
end
-- turned plan x/z of the footprint's west edge and south edge (the planner turns about the plan origin)
local function edges(rot)
  local sz = P.plan.info.size
  local s = rotSteps(rot)
  if s == 0 then return 0, sz.z - 1 elseif s == 1 then return -(sz.z - 1), sz.x - 1
  elseif s == 2 then return -(sz.x - 1), 0 else return 0, 0 end
end

function siteOK(site) return site and site.dx and site.dy and site.dz and site.cx and site.cy and site.cz and site.dh end
function siteKey() local s = S.site; return siteOK(s) and table.concat({ s.dx, s.dy, s.dz, s.cx, s.cy, s.cz, s.rot or 0 }, ",") or "" end
-- world X Z of a dock-relative cell
function worldOf(x, z) return S.site.dx + x, S.site.dz + z end
function dockInside(site)
  local ew, ns = footprint(site.rot)
  return site.dx >= site.cx and site.dx < site.cx + ew and site.dz <= site.cz and site.dz > site.cz - ns
end

-- Layer k as the Weaver wants it: ordered entries { x, y, z, name, how=, d=, turn=, item=, n=, state= } in dock coordinates.
function layerCells(k)
  local c = LC[k]
  if c and c.key == siteKey() then return c.cells end
  local y = P.ys[k]
  if not y or not siteOK(S.site) then return {} end
  local s = S.site
  local mx, mz = edges(s.rot)
  local ox, oy, oz = s.cx - mx - s.dx, s.cy - s.dy, s.cz - mz - s.dz
  local out = {}
  for _, e in ipairs(plan2place.layer(P.plan, y, s.rot)) do
    out[#out + 1] = { e.x + ox, e.y + oy, e.z + oz, e.name, how = e.how, d = e.d, turn = e.turn, item = e.item, n = e.n, state = e.state }
  end
  local n = 0
  for _ in pairs(LC) do n = n + 1 end
  if n >= 4 then LC = {} end
  LC[k] = { key = siteKey(), cells = out }
  return out
end

-- gaps: the lowest gap in each column; cells above it wait (held) until it is filled
local function colKey(c) return c[1] .. "," .. c[3] end
function gapColumns()
  local cols = {}
  for _, g in ipairs(S.gaps) do
    local k = colKey(g)
    if not cols[k] or g[2] < cols[k] then cols[k] = g[2] end
  end
  return cols
end
-- what to send for layer k: its cells, minus those above a gap (they go to S.held)
function layerToSend(k)
  local cells, cols = layerCells(k), gapColumns()
  if not next(cols) then return cells end
  local out = {}
  for _, c in ipairs(cells) do
    local gy = cols[colKey(c)]
    if gy and c[2] > gy then
      local dup
      for _, h in ipairs(S.held) do if h[1] == c[1] and h[2] == c[2] and h[3] == c[3] then dup = true end end
      if not dup then S.held[#S.held + 1] = c end
    else
      out[#out + 1] = c
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Bill, progress, estimate
---------------------------------------------------------------------------
function cellItem(c) return c.item or (c[4]:gsub("wall_torch$", "torch")) end

-- layers done, and cells done in the one he is on
function progress()
  local st = R.status
  local layer = st and st.layer or 1
  local idx = st and st.idx or 1
  if finished() then return P.blocks, P.total end
  if not P then return 0, 0 end
  local done = 0
  for k = 1, math.min(layer - 1, P.total) do done = done + P.cnt[k] end
  if st and st.work == "layer" and layer <= P.total then done = done + math.max(idx - 1, 0) end
  return math.min(done, P.blocks), layer
end

-- items still to place: the whole build, minus what is in, plus the gaps and held cells
function billLeft()
  local left = {}
  if not P then return left end
  local st = R.status
  local layer = st and st.layer or 1
  for k = layer, P.total do
    for item, n in pairs(P.items[k]) do left[item] = (left[item] or 0) + n end
  end
  if finished() then left = {} end
  if st and st.work == "layer" and layer <= P.total then
    for i, c in ipairs(layerCells(layer)) do
      if i >= (st.idx or 1) then break end
      local it = cellItem(c)
      left[it] = (left[it] or 0) - (c.n or 1)
    end
  end
  for _, list in ipairs({ S.gaps, S.held }) do
    for _, c in ipairs(list) do local it = cellItem(c); left[it] = (left[it] or 0) + (c.n or 1) end
  end
  for it, n in pairs(left) do if n <= 0 then left[it] = nil end end
  return left
end

function estimate()
  local b = P and P.blocks or 0
  return floor(b * 2.0), floor(b * 2.3)           -- seconds, fuel (about, from the island build)
end
