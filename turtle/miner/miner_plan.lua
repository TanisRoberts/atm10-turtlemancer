-- miner_plan.lua  --  orders from his Foreman (start, stop, reboot, the checks before every block) and the
-- mining plan: chunk by chunk, level by level. A part of miner.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Commands from the panel
---------------------------------------------------------------------------
function applyCtrl()
  if not ctrl or ctrl.seq == nil then return end
  if (ctrl.retired == true) ~= (S.retired == true) then S.retired = ctrl.retired == true or nil; save() end
  if ctrl.seq == S.seq then return end
  S.seq = ctrl.seq
  if ctrl.want == "run" then
    -- Chunk rings (c1/c2: 0 = the dock's chunk). An older Foreman only sends block rings: convert.
    local c1, c2 = tonumber(ctrl.c1), tonumber(ctrl.c2)
    if not c2 then c1, c2 = 0, math.floor(((tonumber(ctrl.r2) or 48) + 8) / 16) end
    local r1 = math.max(0, math.min(RING_CAP, math.floor(c1 or 0)))
    local r2 = math.max(r1, math.min(RING_CAP, math.floor(c2)))
    local changed = ctrl.minY ~= S.minY or ctrl.maxY ~= S.maxY or r1 ~= S.r1 or r2 ~= S.r2
    if changed or S.done then
      S.ci, S.cl, S.step, S.done = 1, 1, 1, false
      if changed and S.want == "run" then S.regionChanged = true end
    end
    S.minY, S.maxY, S.r1, S.r2, S.want = ctrl.minY, ctrl.maxY, r1, r2, "run"
  else
    S.want = "dock"
  end
  save()
end

function abort(reason, msg) error({ abort = reason, msg = msg }, 0) end

-- Reboot asked for by the Foreman (ctrl.reboot = a fresh token per press). Only called at safe
-- points: between blocks or while idle, so nothing is half-done and the state on disk is exact.
-- The token is saved first, so the same request never reboots it twice.
function maybeReboot()
  if not (ctrl and ctrl.reboot and ctrl.reboot ~= S.rebootDone) then return end
  S.rebootDone = ctrl.reboot
  setStatus("rebooting", "Rebooting, back in a moment")
  save()
  os.sleep(STATUS_EVERY + 0.5) -- let the network loop tell the Foreman
  os.reboot()
end

-- Called before every block of mining
function checkpoint()
  applyCtrl()
  maybeReboot()
  if S.want ~= "run" then abort("stop", "Stop requested") end
  if S.regionChanged then S.regionChanged = nil; abort("region") end
  refreshChunk()
  dumpJunk(MODE.nether == true)   -- Firecrest: the Nether Foreman's junk is thrown away, never carried home
  -- Nearly full: into the shulker box with the ore (if I have one with room)
  if emptySlots() <= 2 and boxSlot() and not S.boxFull then
    makeRoom()
    if emptySlots() <= 3 then stash() end
  end
  if emptySlots() <= 1 then
    makeRoom()
    if emptySlots() <= 1 then
      abort("full", ("Full of ore (%d%% of stacks)"):format(math.floor(cargoFraction() * 100)))
    end
  end
  local need = math.abs(S.x) + math.abs(S.z) + math.abs(S.y) + FUEL_RESERVE
  if fuel() < need then
    burnInventoryFuel(need + 400)
    if fuel() < need then abort("fuel", "Low on fuel") end
  end
end

function waitCtrl(seconds)
  local t = os.clock() + seconds
  while os.clock() < t do
    if ctrl and ctrl.seq ~= S.seq then return end
    maybeReboot()
    refreshChunk()
    os.sleep(1)
  end
end

---------------------------------------------------------------------------
-- Mining plan
---------------------------------------------------------------------------
-- Layer centres (absolute Y). Each pass covers centre-1 .. centre+1.
function layerList()
  local out = {}
  if not S.minY or not S.maxY then return out end
  local c = math.min(S.maxY - 1, S.dockY - 3)
  while c + 1 >= S.minY and c - 1 >= MODE.floor do
    out[#out + 1] = c
    c = c - 3
  end
  return out
end

function ringCells(k)
  if k == 0 then return { { 0, 0 } } end
  local c = {}
  for z = -k, k do c[#c + 1] = { k, z } end
  for x = k - 1, -k, -1 do c[#c + 1] = { x, k } end
  for z = k - 1, -k, -1 do c[#c + 1] = { -k, z } end
  for x = -k + 1, k - 1 do c[#c + 1] = { x, -k } end
  return c
end

-- Chunk by chunk (CBC). The area is chunk rings around my dock's chunk (ring 0 = that chunk, ring 1 =
-- the 8 round it ...). I finish one chunk, every level, before the next: down through the levels in
-- one chunk, up through them in the next, so I never climb back for nothing. Each level is a snake
-- over the chunk's 16x16, walking the middle of 3 levels and digging ores above/below.
function dockChunk() return math.floor(S.home.x / 16), math.floor(S.home.z / 16) end
function chunkList()
  local cx, cz = dockChunk()
  local out = {}
  for k = S.r1 or 0, S.r2 or DEFAULT_R2 do
    for _, c in ipairs(ringCells(k)) do out[#out + 1] = { cx + c[1], cz + c[2], ring = k } end
  end
  return out
end
-- World X/Z -> my dock-relative x/z
function relOf(ax, az) return rot(ax - S.home.x, az - S.home.z, 4 - S.facing) end
-- The 16x16 of chunk (cx, cz) as a snake; reversed on even passes so each pass starts where the last ended
function snake(cx, cz, reversed)
  local cells = {}
  for r = 0, 15 do
    for i = 0, 15 do
      local x = (r % 2 == 0) and i or (15 - i)
      cells[#cells + 1] = { cx * 16 + x, cz * 16 + r }
    end
  end
  if reversed then
    local rev = {}
    for i = #cells, 1, -1 do rev[#rev + 1] = cells[i] end
    cells = rev
  end
  return cells
end
-- Inside my whole area? (Firecrest's lava pools stay inside it)
inArea = function(x, z)
  local ax, az = rot(x, z, S.facing)
  local cx, cz = dockChunk()
  local r = S.r2 or DEFAULT_R2
  return math.abs(math.floor((S.home.x + ax) / 16) - cx) <= r and math.abs(math.floor((S.home.z + az) / 16) - cz) <= r
end

function fuelToStart()
  local layers = layerList()
  local y = layers[1] or S.dockY
  return 2 * (S.dockY - y) + 64 * ((S.chunkRing or 0) + 1) + 500
end

function toLevel(cy)
  if S.y == cy then return end
  while S.y ~= cy do
    checkpoint()
    local k = S.y > cy and "d" or "u"
    local ok, why = move(k)
    if not ok and why == CHEST_FULL and math.abs(cy - S.y) <= 1 then abort("full", "Full: a chest to finish emptying") end
    if not ok and (why == CABLE or why == CHEST_FULL) and math.abs(cy - S.y) > 1 then ok, why = climbCable(k) end
    if not ok then error("Blocked at Y " .. (S.dockY + S.y) .. ": " .. tostring(why), 0) end
    lookForLava()   -- the Nether's shaft often goes through the lava sea
  end
end

function mineChunks()
  local layers = layerList()
  local chunks = chunkList()
  S.layerCount, S.chunkCount = #layers, #chunks
  if #layers == 0 then
    S.done = true; save()
    setStatus("error", "Range must be below the dock")
    return
  end
  for ci = S.ci or 1, #chunks do
    S.ci = ci
    local ch = chunks[ci]
    S.chunkRing = ch.ring
    for cl = S.cl or 1, #layers do
      S.cl = cl
      local li = (ci % 2 == 1) and cl or (#layers + 1 - cl)   -- down in odd chunks, up in even ones
      S.layerIdx, S.layerY = cl, layers[li]
      setStatus("mining", ("Chunk %d of %d, Y %d"):format(ci, #chunks, layers[li]))
      -- From the dock: down my shaft first; elsewhere straight up/down where I am
      toLevel(layers[li] - S.dockY)
      local cells = snake(ch[1], ch[2], cl % 2 == 0)
      for i = S.step or 1, #cells do
        S.step = i
        checkpoint()
        local rx, rz = relOf(cells[i][1], cells[i][2])
        local ok, why = goToXZ(rx, rz, checkUpDown)
        -- That cell is a chest and I'm full: home to unload, then back to this very cell for the rest
        if not ok and why == CHEST_FULL then abort("full", "Full: a chest to finish emptying") end
        -- Anything else (a cable cell, bedrock, unbreakable): skip that cell and carry on from here
      end
      S.step = 1
      save()
    end
    S.cl = 1
    S.chunksDone = (S.chunksDone or 0) + 1
    save()
  end
  S.done = true
  save()
end

