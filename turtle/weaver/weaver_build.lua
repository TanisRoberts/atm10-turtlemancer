-- weaver_build.lua  --  the two layer lists he holds, placing one cell, gaps and finishing a layer.
-- A cell is { x, y, z, "minecraft:block", how } in dock coordinates; how = "2" for a double slab, nil otherwise.
-- He hovers one above the cell and places down. A part of weaver.lua.

LAYERS = {}   -- layer number -> cell list (also on disk as weaver.L<n>)
GCELLS = nil  -- the gap list from the Architect

function layerFile(k) return "weaver.L" .. k end
function getLayer(k)
  if LAYERS[k] then return LAYERS[k] end
  local t = readT(layerFile(k))
  if t then LAYERS[k] = t; for _, c in ipairs(t) do BUILD[c[4]] = true end end
  return t
end
function gapCells()
  if not GCELLS then GCELLS = readT(GAPLIST) end
  return GCELLS
end
function currentCells()
  if S.work == "gap" then return gapCells() end
  return getLayer(S.layer)
end

-- The cells he'll do next, in order: the rest of this list, then the layers he holds
function aheadCells()
  return coroutine.wrap(function()
    local cells = currentCells()
    for i = S.idx, #(cells or {}) do coroutine.yield(cells[i]) end
    local k = S.work == "layer" and S.layer + 1 or S.layer
    if S.work == "gap" then
      local l = getLayer(S.layer)
      for i = 1, #(l or {}) do coroutine.yield(l[i]) end
      k = S.layer + 1
    end
    while getLayer(k) do
      for _, c in ipairs(getLayer(k)) do coroutine.yield(c) end
      k = k + 1
    end
  end)
end

local function gapKey(c) return c[1] .. "," .. c[2] .. "," .. c[3] end
local function addGap(c)
  for _, g in ipairs(GAPS) do if g[1] == c[1] and g[2] == c[2] and g[3] == c[3] then return end end
  GAPS[#GAPS + 1] = { c[1], c[2], c[3], c[4] }; saveGaps()
end
local function delGap(c)
  for i, g in ipairs(GAPS) do
    if g[1] == c[1] and g[2] == c[2] and g[3] == c[3] then table.remove(GAPS, i); saveGaps(); return end
  end
end

-- Place one cell from above. "ok", "gap" (no block), "dry" (go to the dock for it) or "blocked", why
local function buildCell(c)
  local name, how = c[4], c[5]
  local need = how == "2" and 2 or 1
  if (counts()[name] or 0) < need then
    if S.short[name] or S.visitKey == (S.work .. ":" .. S.layer .. ":" .. S.idx) then S.short[name] = true; return "gap" end
    return "dry"
  end
  local ok, why = goTo(c[1], c[2] + 1, c[3])
  if not ok then return "blocked", why end
  local there, d = turtle.inspectDown()
  local reps = need
  if there then
    if d.name == name then
      if how ~= "2" or (d.state and d.state.type == "double") then return "ok" end
      reps = 1                              -- a single slab already stands: one more makes the double
    elseif canDig(d.name) then turtle.digDown(); dropJunk()
    else return "blocked", "Blocked by " .. tostring(d.name) end
  end
  for _ = 1, reps do
    local placed = false
    for _ = 1, 5 do
      local s = slotOf(name)
      if not s then return "dry" end
      turtle.select(s)
      if turtle.placeDown() then placed = true; break end
      turtle.attackDown(); os.sleep(0.2)
    end
    if not placed then turtle.select(1); return "blocked", "Can't place " .. name end
  end
  turtle.select(1)
  return "ok"
end

local function finishWork()
  if S.work == "layer" then
    local done = { layer = S.layer, skipped = S.skip, blocked = S.blocked }
    S.lastDone = done
    send({ type = "layer_done", layer = done.layer, skipped = done.skipped, blocked = done.blocked })
    LAYERS[S.layer] = nil
    if fs.exists(layerFile(S.layer)) then fs.delete(layerFile(S.layer)) end
    S.layer, S.idx, S.skip, S.blocked = S.layer + 1, 1, {}, {}
    S.work = fs.exists(GAPLIST) and "gap" or "layer"
  else
    send({ type = "gaps_filled", cells = S.filled or {} })
    S.filled = nil
    fs.delete(GAPLIST); GCELLS = nil
    S.work, S.idx = "layer", 1
  end
  save()
end

TRIES = 0
-- One cell of the work list (or the end of it). Returns false when he has to wait.
function buildStep()
  local cells = currentCells()
  if not cells then
    S.needLayer = S.layer
    if not atDock() then goHome() end
    setStatus("waiting", "Waiting for layer " .. S.layer .. " from the Architect")
    os.sleep(1)
    return false
  end
  S.needLayer = nil
  if S.idx > #cells then finishWork(); return true end
  if S.work == "layer" and S.layer > (S.total or math.huge) then return true end
  local c = cells[S.idx]
  if fuelLevel() < fuelHome() + 60 then
    dockVisit()
    if fuelLevel() < fuelHome() + 60 then setStatus("waiting", "Low on fuel: waiting for storage"); os.sleep(10) end
    return true
  end
  setStatus("building", ("%s at %d %d %d"):format(c[4], c[1], c[2], c[3]))
  local r, why = buildCell(c)
  if r == "dry" then dockVisit(); return true end
  if r == "blocked" then
    TRIES = TRIES + 1
    if TRIES < 4 then setStatus("blocked", tostring(why)); os.sleep(10); return true end
  end
  TRIES = 0
  if r == "ok" then
    if S.work == "layer" then S.topY = math.max(S.topY, c[2]) else
      delGap(c); S.filled = S.filled or {}; S.filled[#S.filled + 1] = { c[1], c[2], c[3], c[4] }
    end
  elseif r == "gap" then
    if S.work == "layer" then addGap(c); S.skip[#S.skip + 1] = { c[1], c[2], c[3], c[4] } end
  else
    if S.work == "layer" then S.blocked[#S.blocked + 1] = { c[1], c[2], c[3], c[4], tostring(why) } end
  end
  S.idx = S.idx + 1
  save()
  return true
end
