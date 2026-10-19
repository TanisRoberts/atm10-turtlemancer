-- lumberjack.lua  --  Woodpecker, the tree farmer (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: a turtle with a diamond axe and a wireless or ender modem. GPS towers make him unlosable
--        (optional: without them he finds his way from his map, like before).
-- Zone:  mark the edge of the tree farm with slabs on the ground (any slab). Woodpecker walks on the
--        ground inside it. Start him inside the zone, next to his dock barrel.
-- Dock:  a barrel storage knows as a dock (/dock on storage, or the coal marker in /setup).
--        Storage takes his logs and keeps the barrel stocked with fuel. For saplings, give the dock
--        Keeps on the storage computer (/assign, pick his dock, e.g. "oak_sapling 64"): he tops
--        himself up to KEEP_SAPLINGS of each from it at every dock visit.
--
-- What he does:
--   * maps the zone (walks it until he hits slabs) and picks the tree grid that fits the most trees,
--     with walking lanes between them (a tree every SPACING blocks). Re-maps keep the same grid.
--   * every EVERY minutes: walks the lanes, chops every grown tree (and the leaves next to the trunk,
--     which drops saplings), plants saplings where trees should be, picks up drops
--   * the leaves he doesn't cut rot over the next few minutes and scatter saplings round the stump;
--     dropped items vanish after 5 minutes, so he sweeps round every stump SWEEPS times, SWEEP_GAP
--     seconds apart, sucking up every block near it (lanes, tree spots, the border). Spots left bare
--     for want of a sapling get planted as soon as a sweep turns some up.
--   * unloads at the dock (keeps KEEP_SAPLINGS saplings), refuels, tops his saplings up from the dock;
--     unloads mid-round if full; runs home once a round to restock if he runs out of saplings
-- Control: the Farmhand computer, chat (island woodpecker rounds|survey|stop|go|found), or here:
--   lumberjack rounds | survey (new map from where he stands) | stop | go | found
-- Settings: woodpecker.env (edit live, or from the Farmhand).

local B = dofile("farmbot.lua")
local S
local key, unkey, DX, DZ = B.key, B.unkey, B.DX, B.DZ

local ZONE_VERSION = 2

local DEFAULTS = {
  { "EVERY", 20, "Minutes between rounds (20 = one Minecraft day).", remote = true, min = 1 },
  { "KEEP_SAPLINGS", 64, "Saplings of each kind he carries (64 = a full stack); spares go to storage, and he tops up from his dock's Keeps.", remote = true, min = 0, max = 640 },
  { "RESURVEY_EVERY", 12, "Re-map the zone every this many rounds; the tree grid stays put (0 = never).", remote = true, min = 0 },
  { "SPACING", 3, "A tree every this many blocks. Only used for a brand-new map.", min = 2, max = 6 },
  { "FUEL_TARGET", 4000, "Fuel he tops up to at the dock.", min = 200 },
  { "FUEL_LOW", 200, "Below this he won't start a round until he's refuelled.", min = 50 },
  { "MAX_REACH", 32, "How far the zone may reach from his start; further means the slab border has a gap.", min = 4 },
  { "SURVEY_RETRY", 5, "Minutes between tries when mapping the zone fails.", min = 1 },
  { "SWEEPS", 2, "Times he sweeps round each chopped tree for the saplings its rotting leaves drop (0 = never).", remote = true, min = 0, max = 5 },
  { "SWEEP_GAP", 100, "Seconds between those sweeps. Leaves rot within a few minutes; drops vanish after 5.", min = 30, max = 150 },
  { "SWEEP_REACH", 2, "How far round a stump he sweeps, in blocks (2 for oak/birch; 3 for spruce, jungle, dark oak).", min = 1, max = 5 },
}

---------------------------------------------------------------------------
-- What's what
---------------------------------------------------------------------------
local SOFT = { "grass", "fern", "flower", "dandelion", "poppy", "tulip", "orchid", "allium", "bluet", "daisy",
  "lily", "bush", "snow", "vine", "dead_bush", "mushroom" }
local function isSoft(n)
  n = tostring(n)
  if n:find("grass_block") then return false end
  for _, s in ipairs(SOFT) do if n:find(s) then return true end end
  return false
end
local function isLog(n) n = tostring(n); return n:find("_log") ~= nil or n:find("_stem") ~= nil or n:find("_wood") ~= nil end
local function isSapling(n) return tostring(n):find("sapling") ~= nil or tostring(n):find("propagule") ~= nil end
local function isLeaves(n) return tostring(n):find("leaves") ~= nil end
local function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = tostring(d.name); return n:find("barrel") or n:find("chest")
end
local function plantable(n)
  n = tostring(n)
  return n:find("dirt") or n:find("grass_block") or n:find("podzol") or n:find("moss_block") or n:find("mud") or n:find("mycelium")
end
local function saplingFor(logName)
  local wood = tostring(logName):match("^(.-)_log$") or tostring(logName):match("^(.-)_wood$")
  return wood and (wood .. "_sapling") or nil
end
local function selectSapling(prefer)
  local any
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and isSapling(d.name) then
      if prefer and d.name == prefer then turtle.select(s); return true end
      any = any or s
    end
  end
  if any then turtle.select(any); return true end
  return false
end

B.onBlocked = function(kind, ok, d, op)
  if ok and op.dig and (isSoft(d.name) or isLeaves(d.name)) then op.dig(); return "retry" end
  if ok then return "fail" end
end

---------------------------------------------------------------------------
-- The map: cells ["x,z"] = lane / spot (a tree goes here) / tree (wild, chopped once) /
-- offtree (was wild, now a lane) / border / blocked / dock
---------------------------------------------------------------------------
local function walkableKind(c) return c == "lane" or c == "offtree" end
local function walkable(k) return walkableKind(B.Z.cells[k]) or k == B.Z.home end

-- Every drop in the block ahead (each suck takes one dropped item stack). Counts saplings found.
local picked = 0
local function suckAll()
  local before = B.countWhere(isSapling)
  local any = false
  for _ = 1, 16 do if turtle.suck() then any = true else break end end
  if any then picked = picked + math.max(0, B.countWhere(isSapling) - before) end
  return any
end

local dirty   -- while sweeping: cells still to suck up ["x,z"] = true

local chop   -- defined below
local function clearStray()
  -- Lanes should be empty: a sapling or tree standing in one (planted by mistake, or wild) goes
  local ok, d = turtle.inspect()
  if not ok then return end
  if isSapling(d.name) then turtle.dig()
  elseif isLog(d.name) then chop() end
end

local function goTo(goalPred)
  return B.goTo(goalPred, walkable, function(k)
    suckAll()
    if dirty then dirty[k] = nil end
    local here = key(S.x, S.z)
    clearStray()
    if key(S.x, S.z) ~= here then return false end     -- chopping moved him: plan again
    return true
  end)
end

local function goHome()
  if S.y > 0 then
    while S.y > 0 do turtle.digDown(); if not B.move("d") then break end end
  end
  local home = B.Z.home or key(0, 0)
  if key(S.x, S.z) == home then return true end
  if not goTo(function(k) return k == home end) then
    B.tempBlocked = {}
    if not goTo(function(k) return k == home end) then error("Can't find my way home", 0) end
  end
  return true
end

local function survey(fresh)
  B.setStatus("surveying", "Mapping the zone")
  local old = (not fresh) and B.Z or nil
  local anchor = old and old.anchor
  if fresh then S.x, S.y, S.z, S.h = 0, 0, 0, 0; B.save() end
  B.core.fuel.refuelFromInventory(2000)
  if B.fuel() < 300 then
    error(("Only %d fuel. Put some coal in me and say: island %s survey"):format(B.fuel(), B.NAME:lower()), 0)
  end
  if fresh then
    local c, ax, ay, az = B.findCompass()
    anchor = c and { x = ax, y = ay, z = az, f = c } or nil
  end
  local startK = key(S.x, S.z)
  local cells = { [startK] = "lane" }
  local ground = {}
  local okDown, dDown = turtle.inspectDown()
  ground[startK] = okDown and plantable(dDown.name) and true or false
  local dockDir
  local count = 1
  local gap = false
  local docksSeen = {}
  local maxReach = B.E.MAX_REACH

  local function look(h)
    B.face(h)
    return turtle.inspect()
  end

  if fresh then
    for h = 0, 3 do
      local ok, d = look(h)
      if isContainer(ok, d) then dockDir = h; cells[key(S.x + DX[h], S.z + DZ[h])] = "dock"; break end
    end
  else
    dockDir = old.dockDir
    if type(dockDir) == "number" then cells[key(S.x + DX[dockDir], S.z + DZ[dockDir])] = "dock" end
  end

  local function visit()
    for h = 0, 3 do
      local nx, nz = S.x + DX[h], S.z + DZ[h]
      local k = key(nx, nz)
      if cells[k] == nil then
        local sx, sz = unkey(startK)
        if math.abs(nx - sx) > maxReach or math.abs(nz - sz) > maxReach then gap = true; return end
        local ok, d = look(h)
        local n = ok and tostring(d.name) or "minecraft:air"
        if ok and n:find("slab") then
          cells[k] = "border"
        elseif ok and isContainer(ok, d) then
          cells[k] = "dock"
          docksSeen[#docksSeen + 1] = { from = key(S.x, S.z), dir = h }
        elseif ok and (isLog(n) or isSapling(n)) then
          cells[k] = "tree"; ground[k] = true; count = count + 1
        elseif ok and not isSoft(n) and not isLeaves(n) then
          cells[k] = "blocked"
        else
          if ok then turtle.dig() end
          if B.move("f") then
            cells[k] = "lane"; count = count + 1
            local ok2, d2 = turtle.inspectDown()
            ground[k] = ok2 and plantable(d2.name) and true or false
            visit()
            B.face((h + 2) % 4)        -- always walk back, even after finding a gap
            local back, why = B.move("f")
            if not back then
              error(("Couldn't get back to %d,%d during the survey (%s)"):format(S.x + DX[S.h], S.z + DZ[S.h], tostring(why)), 0)
            end
            if gap then return end
          else
            cells[k] = "blocked"
          end
        end
      end
    end
  end
  visit()
  B.face(0)
  if gap then error("The slab border has a gap (zone runs past " .. maxReach .. " blocks). Fix it and survey again.", 0) end

  local home = startK
  if fresh then
    if not dockDir then
      for _, h in ipairs({ "up", "down" }) do
        local ok, d
        if h == "up" then ok, d = turtle.inspectUp() else ok, d = turtle.inspectDown() end
        if isContainer(ok, d) then dockDir = h; break end
      end
    end
    if not dockDir and #docksSeen > 0 then home, dockDir = docksSeen[1].from, docksSeen[1].dir end
    if not dockDir then error("No dock barrel next to my starting spot or in the border.", 0) end
  else
    home = old.home
  end

  -- The tree grid: a re-map keeps the old one (trees are planted on it); a new map picks the offset
  -- that fits the most trees, each with a lane next to it
  local spacing = (old and old.spacing) or B.E.SPACING
  local function fitsGrid(k, kind, ox, oz)
    local x, z = unkey(k)
    if not ((kind == "lane" or kind == "tree") and ground[k] and x % spacing == ox and z % spacing == oz and k ~= home and k ~= startK) then
      return false
    end
    for h = 0, 3 do if cells[key(x + DX[h], z + DZ[h])] == "lane" then return true end end
    return false
  end
  local bestOx, bestOz = old and old.ox, old and old.oz
  if bestOx == nil and old and old.spots and old.spots[1] then
    -- A map from the old program: its grid is wherever its tree spots are
    local x, z = unkey(old.spots[1])
    bestOx, bestOz = x % spacing, z % spacing
  end
  if bestOx == nil then
    local best = -1
    for ox = 0, spacing - 1 do
      for oz = 0, spacing - 1 do
        local n = 0
        for k, kind in pairs(cells) do if fitsGrid(k, kind, ox, oz) then n = n + 1 end end
        if n > best then best, bestOx, bestOz = n, ox, oz end
      end
    end
  end
  local spots = {}
  for k, kind in pairs(cells) do if fitsGrid(k, kind, bestOx, bestOz) then spots[#spots + 1] = k end end
  table.sort(spots)
  for _, k in ipairs(spots) do cells[k] = "spot" end
  B.Z = { cells = cells, spots = spots, dockDir = dockDir, count = count, home = home, anchor = anchor,
          ox = bestOx, oz = bestOz, spacing = spacing, v = ZONE_VERSION, seen = old and old.seen or nil }
  B.saveZone()
  B.setStatus("docked", ("Zone mapped: %d blocks, room for %d trees"):format(count, #spots))
end

---------------------------------------------------------------------------
-- Trees
---------------------------------------------------------------------------
local function digLeavesAround()
  for _ = 1, 4 do
    local ok, d = turtle.inspect()
    if ok and (isLeaves(d.name) or isLog(d.name)) then turtle.dig() end
    B.turnRight()
  end
end

-- Facing a grown trunk from a lane: chop it all, come back to the lane
function chop()
  local ok, d = turtle.inspect()
  local logName = d and d.name
  turtle.dig()
  if not B.move("f") then return logName end
  local climbed = 0
  while true do
    local okUp, up = turtle.inspectUp()
    if okUp and (isLog(up.name) or isLeaves(up.name)) then
      digLeavesAround()
      turtle.digUp()
      if not B.move("u") then break end
      climbed = climbed + 1
    else break end
  end
  digLeavesAround()
  for _ = 1, climbed do
    while not B.move("d") do turtle.digDown() end
  end
  if not B.move("b") then              -- something behind (leaves, a mob): turn round and push through
    B.turnRight(); B.turnRight(); B.move("f"); B.turnRight(); B.turnRight()
  end
  return logName
end

local function plant(prefer)
  local ok, d = turtle.inspect()
  if ok and isSapling(d.name) then return "growing" end
  if ok and isSoft(d.name) then turtle.dig() end
  if not selectSapling(prefer) then turtle.select(1); return "nosapling" end
  local placed = turtle.place()
  turtle.select(1)
  return placed and "planted" or "failed"
end

local function dock()
  return B.dock({
    keep = function(name, already) if isSapling(name) then return B.E.KEEP_SAPLINGS - already end return 0 end,
    want = function(name, have) if isSapling(name) then return B.E.KEEP_SAPLINGS - have end return 0 end,
  })
end

---------------------------------------------------------------------------
-- Sweeping: suck up every block within SWEEP_REACH of the given stumps. Lanes get sucked as he
-- walks into them; tree spots, wild trees and the border get sucked by turning to face them from a
-- lane next door. Never faces the dock (suck would empty it) or blocked cells.
---------------------------------------------------------------------------
local function sweepable(k)
  local c = B.Z.cells[k]
  return c ~= nil and c ~= "dock" and c ~= "blocked"
end
local function sweep(stumps)
  local reach = B.E.SWEEP_REACH or 2
  dirty = {}
  for _, k in ipairs(stumps) do
    local cx, cz = unkey(k)
    for dx = -reach, reach do
      for dz = -reach, reach do
        local nk = key(cx + dx, cz + dz)
        if sweepable(nk) then dirty[nk] = true end
      end
    end
  end
  local function touches(k)
    local x, z = unkey(k)
    for h = 0, 3 do if dirty[key(x + DX[h], z + DZ[h])] then return true end end
    return false
  end
  local ok, err = pcall(function()
    while next(dirty) do
      B.abortIfNeeded()
      if B.fuel() < 100 then return end
      if B.freeSlots() < 2 then goHome(); dock(); B.setStatus("working", "Picking up saplings") end
      dirty[key(S.x, S.z)] = nil         -- can't suck the block he's in (he sucked it walking in)
      if next(dirty) == nil then return end
      if not goTo(touches) then return end   -- the rest is out of reach
      dirty[key(S.x, S.z)] = nil
      local h0 = S.h
      for _, d in ipairs({ 0, 1, 3, 2 }) do  -- ahead, right, left, behind: fewest turns
        local h = (h0 + d) % 4
        local nk = key(S.x + DX[h], S.z + DZ[h])
        if dirty[nk] then B.face(h); suckAll(); dirty[nk] = nil end
      end
    end
  end)
  dirty = nil
  if not ok then error(err, 0) end
end

local function rounds()
  local Z = B.Z
  B.setStatus("working", "Doing my rounds")
  picked = 0
  local chopped, planted, restocked, lowFuel = 0, 0, false, false
  local todo, total = {}, 0
  for _, k in ipairs(Z.spots) do todo[k] = true; total = total + 1 end
  for k, c in pairs(Z.cells) do if c == "tree" then todo[k] = "off"; total = total + 1 end end
  local done = 0
  -- What's on each tree spot, for the Farmhand's map (h chopped + replanted, g sapling, e empty)
  Z.seen = Z.seen or {}
  local seen = Z.seen
  local function mark(k, st) if seen[k] ~= st then seen[k] = st; B.touchMap() end end
  local unplanted = {}   -- spots left bare for want of a sapling: planted once a sweep turns some up
  local gap = (B.E.SWEEP_GAP or 100) * 1000
  -- Chopped trees still to sweep round: { k, left (sweeps), at (epoch ms) }. Kept in the state file,
  -- so a restart mid-round (world closed, reboot) still sweeps round the trees it had just chopped.
  local stumps = {}
  for _, s in ipairs(S.stumps or {}) do
    if type(s) == "table" and s.k and B.now() - (s.at or 0) < gap then stumps[#stumps + 1] = s end
  end
  S.stumps = stumps
  -- Out of saplings mid-round: one trip home to top up from the dock, then carry on
  local function outOfSaplings(target)
    if restocked then unplanted[target] = true; return false end
    restocked = true
    B.setStatus("working", "Out of saplings: fetching more from the dock")
    goHome(); dock()
    B.setStatus("working", "Doing my rounds")
    if B.countWhere(isSapling) == 0 then unplanted[target] = true; return false end   -- the dock had none either
    todo[target] = true                -- come back and plant it
    return true
  end
  -- Sweep round every stump whose next sweep is due
  local function sweepDue()
    local t, due = B.now(), {}
    for i = #stumps, 1, -1 do
      local s = stumps[i]
      if t >= s.at then
        due[#due + 1] = s.k
        s.left, s.swept = s.left - 1, true
        if s.left <= 0 then table.remove(stumps, i) end
      end
    end
    if #due == 0 then return end
    B.setStatus("working", ("Picking up saplings round %d stump%s"):format(#due, #due == 1 and "" or "s"))
    sweep(due)
    local after = B.now()
    for _, s in ipairs(stumps) do if s.swept then s.at, s.swept = after + gap, nil end end   -- next one a gap from now
    B.save()
    if B.fuel() < 100 then lowFuel = true end
    B.setStatus("working", "Doing my rounds")
    -- Saplings turned up: the bare spots get planted now
    if next(unplanted) and B.countWhere(isSapling) > 0 then
      for k in pairs(unplanted) do if not todo[k] then todo[k] = true; total = total + 1 end end
      unplanted = {}
    end
  end
  local function plantedOrBare(target, r)
    if r == "planted" then planted = planted + 1
    elseif r == "nosapling" and outOfSaplings(target) then done = done - 1 end
  end

  while not lowFuel do
    B.abortIfNeeded()
    sweepDue()
    if lowFuel then break end
    if next(todo) then
      if B.freeSlots() < 2 then goHome(); dock(); B.setStatus("working", "Doing my rounds") end
      local target
      local p = B.path(key(S.x, S.z), function(k)
        local x, z = unkey(k)
        for h = 0, 3 do
          local nk = key(x + DX[h], z + DZ[h])
          if todo[nk] then target = nk; return true end
        end
        return false
      end, walkable)
      if not p then
        for k in pairs(todo) do todo[k] = nil end     -- none of the rest can be reached
      else
        local stand = p[#p] or key(S.x, S.z)
        if not goTo(function(k) return k == stand end) then
          todo[target] = nil
        else
          local tx, tz = unkey(target)
          local h = B.dirTo(tx, tz)
          if h then B.face(h) end
          local ok, d = turtle.inspect()
          local kind = todo[target]
          todo[target] = nil
          if h and ok and isLog(d.name) then
            local logName = chop()
            chopped = chopped + 1
            if (B.E.SWEEPS or 0) > 0 then
              stumps[#stumps + 1] = { k = target, left = B.E.SWEEPS, at = B.now() + gap }
              B.save()
            end
            if kind == "off" then
              Z.cells[target] = "offtree"; seen[target] = nil; B.saveZone()  -- becomes a lane
            else
              local r = plant(saplingFor(logName))
              mark(target, r == "planted" and "h" or (r == "growing" and "g") or "e")
              plantedOrBare(target, r)
            end
          elseif h and kind ~= "off" and not (ok and isSapling(d.name)) then
            local r = plant()
            mark(target, (r == "planted" or r == "growing") and "g" or "e")
            plantedOrBare(target, r)
          elseif h and kind ~= "off" then
            mark(target, "g")                -- a sapling already growing there
          end
          if B.fuel() < 100 then lowFuel = true end
        end
        done = done + 1
        S.progress = ("%d/%d"):format(done, total)
      end
    elseif #stumps > 0 then
      -- Every tree seen to: wait (where he is) for the next sweep to come due
      local nextAt = math.huge
      for _, s in ipairs(stumps) do nextAt = math.min(nextAt, s.at) end
      local wait = math.ceil((nextAt - B.now()) / 1000)
      if wait > 0 then
        B.setStatus("working", ("Waiting %d s for the leaves to drop their saplings"):format(wait))
        for _ = 1, wait do B.abortIfNeeded(); os.sleep(1) end
      end
    else
      break
    end
  end
  S.progress, S.stumps = nil, nil
  S.lastRound = { chopped = chopped, planted = planted, picked = picked, at = B.now() }
  B.saveZone()
  local summary = ("Round done: chopped %d, planted %d, picked up %d saplings"):format(chopped, planted, picked)
  local bare = 0
  for _ in pairs(unplanted) do bare = bare + 1 end
  return summary, bare > 0 and ("Out of saplings (%d spots bare). Chopped %d, planted %d"):format(bare, chopped, planted) or nil
end

---------------------------------------------------------------------------
-- Finding his way without GPS: what he sees on each side must fit the map
---------------------------------------------------------------------------
local function sense() local ok, d = turtle.inspect(); return { ok = ok, d = d } end
local function fits(kind, seen)
  if kind == nil then return true end
  local ok, d = seen.ok, seen.d
  local n = ok and tostring(d.name) or "minecraft:air"
  local slab, box = ok and n:find("slab") ~= nil, isContainer(ok, d)
  if kind == "border" then return slab end
  if kind == "dock" then return box end
  if slab or box then return false end
  if kind == "blocked" then return ok and not isSoft(n) and not isLeaves(n) and not isLog(n) and not isSapling(n) end
  local treeish = ok and (isLog(n) or isSapling(n))
  if kind == "lane" or kind == "offtree" then return not treeish end   -- lanes are kept clear of trees
  return not ok or treeish or isSoft(n) or isLeaves(n)                  -- spot / tree: a tree, a sapling or nothing
end

local function recoverNoGps(why)
  local cands = {}
  if why == "found" then
    local seen = {}
    for _, k in ipairs({ B.Z.home or "0,0", "0,0" }) do
      if not seen[k] then
        seen[k] = true
        local x, z = unkey(k)
        for h = 0, 3 do cands[#cands + 1] = { x, z, h } end
      end
    end
  else
    local hs = type(S.turning) == "table" and S.turning or { S.h, (S.h + 1) % 4, (S.h + 3) % 4 }
    for _, h in ipairs(hs) do cands[#cands + 1] = { S.x, S.z, h } end
  end
  local m = B.orient(cands, { sense = sense, fits = fits, passable = walkableKind })
  if m then S.x, S.y, S.z, S.h = m[1], 0, m[2], m[3]; return true end
  return false
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
B.extraStatus = function()
  local Z = B.Z
  return { spots = Z and #Z.spots or 0, cells = Z and Z.count or 0, progress = S.progress,
           saplings = B.countWhere(isSapling) }
end

-- Map page: lanes, tree spots (with what's on them) and wild trees still to be chopped
B.mapCell = function(k, kind)
  if kind == "lane" or kind == "offtree" then return "." end
  if kind == "spot" then return "+", B.Z.seen and B.Z.seen[k] end
  if kind == "tree" then return "!" end
end

local R = {
  zoneVersion = ZONE_VERSION,
  boot = function()
    -- Restarted halfway up a tree? Finish the trunk above, then climb down.
    if S.y > 0 then
      while true do
        local ok, d = turtle.inspectUp()
        if ok and isLog(d.name) then turtle.digUp(); if not B.move("u") then break end else break end
      end
      while S.y > 0 do turtle.digDown(); if not B.move("d") then break end end
    end
  end,
  okAt = function(lx, ly, lz)
    -- Anywhere inside the zone at ground level (mid-chop he stands in a tree's own spot)
    local c = B.Z.cells[key(lx, lz)]
    return ly == 0 and c ~= nil and c ~= "border" and c ~= "blocked" and c ~= "dock"
  end,
  recoverNoGps = recoverNoGps,
  survey = survey,
  rounds = rounds,
  goHome = goHome,
  dock = dock,
}

local args = { ... }
B.run({ name = "Woodpecker", role = "lumberjack", prog = "lumberjack",
        env = { file = "woodpecker.env", title = "Woodpecker (lumberjack)", defaults = DEFAULTS },
        state = "lumberjack.state", zone = "lumberjack.zone",
        onLoad = function(st)
          S = st
          -- Oct 2026: the old default was 32; a full stack is the new one (only if it was never changed)
          if not S.keep64 then
            if B.E.KEEP_SAPLINGS == 32 then B.setEnv("KEEP_SAPLINGS", 64) end
            S.keep64 = true
          end
        end },
      R, args)
