-- lumberjack.lua  --  Tigger, the tree farmer (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: a turtle with a diamond axe and a wireless (or ender) modem.
-- Zone:  mark the edge of the tree farm with slabs on the ground (any slab). Tigger walks on
--        the ground inside it. Place him inside the zone, next to his dock barrel.
-- Dock:  a barrel next to him, on the storage network with 1 coal in it at /setup time.
--        Storage takes his logs and keeps the barrel stocked with fuel.
--
-- What he does:
--   * maps the zone (walks it until he hits slabs) and picks the tree grid that fits the most
--     trees, with walking lanes between them (a tree every 3rd block)
--   * once a Minecraft day: walks the lanes, chops every grown tree (and the leaves next to the
--     trunk, which drops saplings), plants saplings where trees should be, picks up drops
--   * unloads at the dock, keeps 32 saplings, refuels
-- Commands (chat: island tigger <cmd>, or here: lumberjack <cmd>):
--   rounds  go now     survey  re-map the zone     stop  stay docked     go  back on schedule

local PROTOCOL     = "tanis-farm"
local ROLE         = "lumberjack"
local STATE_FILE   = "lumberjack.state"
local ZONE_FILE    = "lumberjack.zone"
local ROUND_EVERY  = 1200    -- seconds between rounds (one Minecraft day)
local MAX_REACH    = 32      -- a zone bigger than this means the slab border has a gap
local SPACING      = 3       -- a tree every 3rd block: 2-block lanes keep light in and paths clear
local KEEP_SAPLINGS = 32
local FUEL_TARGET  = 4000

local args = { ... }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local function readT(p)
  if not fs.exists(p) then return nil end
  local f = fs.open(p, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  return type(t) == "table" and t or nil
end
local function writeT(p, t) local f = fs.open(p, "w"); f.write(textutils.serialize(t)); f.close() end

local S = readT(STATE_FILE) or {}
local Z = readT(ZONE_FILE)            -- { cells = {["x,z"] = kind}, spots = {"x,z", ...}, dockDir }
local function save() writeT(STATE_FILE, S) end

local NAME = os.getComputerLabel() or "Tigger"
local lastShown = ""
local function setStatus(st, msg)
  S.status, S.msg = st, msg or ""
  local line = st .. (S.msg ~= "" and (": " .. S.msg) or "")
  if line ~= lastShown then
    lastShown = line
    print(("[%s] %s"):format(textutils.formatTime(os.time(), true), line))
    save()
  end
end

---------------------------------------------------------------------------
-- Movement (relative to where he was set up: x/z flat, heading 0 = his facing at setup)
---------------------------------------------------------------------------
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local function key(x, z) return x .. "," .. z end
local function unkey(k) local x, z = k:match("^(%-?%d+),(%-?%d+)$"); return tonumber(x), tonumber(z) end

local function apply(kind)
  if kind == "f" then S.x, S.z = S.x + DX[S.h], S.z + DZ[S.h]
  elseif kind == "b" then S.x, S.z = S.x - DX[S.h], S.z - DZ[S.h]
  elseif kind == "u" then S.y = S.y + 1
  else S.y = S.y - 1 end
end

local OPS = {
  f = { move = turtle.forward, dig = turtle.dig,     inspect = turtle.inspect,     attack = turtle.attack },
  b = { move = turtle.back },
  u = { move = turtle.up,      dig = turtle.digUp,   inspect = turtle.inspectUp,   attack = turtle.attackUp },
  d = { move = turtle.down,    dig = turtle.digDown, inspect = turtle.inspectDown, attack = turtle.attackDown },
}

local SOFT = { "grass", "fern", "flower", "dandelion", "poppy", "tulip", "orchid", "allium", "bluet", "daisy",
  "lily", "bush", "snow", "vine", "dead_bush", "mushroom" }
local function isSoft(n)
  n = tostring(n)
  if n:find("grass_block") then return false end
  for _, s in ipairs(SOFT) do if n:find(s) then return true end end
  return false
end

-- One block of movement. Clears soft plants and leaves; waits out mobs/players.
local function move(kind)
  local op = OPS[kind]
  for _ = 1, 12 do
    if turtle.getFuelLevel() == 0 then return false, "Out of fuel" end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }
    save()
    if op.move() then apply(kind); S.pending = nil; save(); return true end
    S.pending = nil
    if op.inspect then
      local ok, d = op.inspect()
      if ok and (isSoft(d.name) or tostring(d.name):find("leaves")) then op.dig()
      elseif ok then save(); return false, "Blocked by " .. tostring(d.name)
      else op.attack(); os.sleep(0.5) end
    else
      os.sleep(0.5)
    end
  end
  save()
  return false, "Something keeps getting in the way"
end

-- S.turning records both headings, so a turtle unloaded mid-turn can work out which one is true
local function turnRight() S.turning = { S.h, (S.h + 1) % 4 }; save(); turtle.turnRight(); S.h = (S.h + 1) % 4; S.turning = nil; save() end
local function turnLeft()  S.turning = { S.h, (S.h + 3) % 4 }; save(); turtle.turnLeft();  S.h = (S.h + 3) % 4; S.turning = nil; save() end
local function face(h)
  local d = (h - S.h) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end
local function dirTo(x, z)
  for h = 0, 3 do if S.x + DX[h] == x and S.z + DZ[h] == z then return h end end
end

local function fuel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

---------------------------------------------------------------------------
-- Inventory helpers
---------------------------------------------------------------------------
local function isLog(n) n = tostring(n); return n:find("_log") ~= nil or n:find("_stem") ~= nil or n:find("_wood") ~= nil end
local function isSapling(n) return tostring(n):find("sapling") ~= nil or tostring(n):find("propagule") ~= nil end

local function countWhere(pred)
  local c = 0
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and pred(d.name) then c = c + d.count end end
  return c
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

local function saplingFor(logName)
  local wood = tostring(logName):match("^(.-)_log$") or tostring(logName):match("^(.-)_wood$")
  return wood and (wood .. "_sapling") or nil
end

---------------------------------------------------------------------------
-- Talking to the base
---------------------------------------------------------------------------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
local ctrl = nil
local function statusMsg()
  return { type = "status", role = ROLE, id = os.getComputerID(), label = NAME, state = S.status, msg = S.msg,
    fuel = turtle.getFuelLevel(), fuelLimit = turtle.getFuelLimit(), spots = Z and #Z.spots or 0,
    cells = Z and Z.count or 0, lastHaul = S.lastHaul, nextRound = S.nextRound and math.max(0, math.floor(S.nextRound - os.clock())),
    paused = S.paused, seq = S.seq, saplings = countWhere(isSapling) }
end

---------------------------------------------------------------------------
-- Survey: walk the zone until slabs, record what's where
---------------------------------------------------------------------------
local function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = tostring(d.name); return n:find("barrel") or n:find("chest")
end

local function plantable(n)
  n = tostring(n)
  return n:find("dirt") or n:find("grass_block") or n:find("podzol") or n:find("moss_block") or n:find("mud") or n:find("mycelium")
end

local function survey()
  setStatus("surveying", "Mapping the zone")
  -- A survey always starts fresh from where he stands: that spot becomes 0,0, facing "north"
  S.x, S.y, S.z, S.h = 0, 0, 0, 0
  save()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isSapling(d.name) and fuel() < 2000 then
      turtle.select(s)
      if turtle.refuel(0) then turtle.refuel() end
    end
  end
  turtle.select(1)
  if fuel() < 300 then
    error(("Only %d fuel. Give me some coal (put it in my inventory) and say: island %s survey"):format(fuel(), NAME:lower()), 0)
  end
  local cells = { [key(0, 0)] = "lane" }
  local ground = {}
  local okDown, dDown = turtle.inspectDown()
  ground[key(0, 0)] = okDown and plantable(dDown.name) and true or false
  local dockDir
  local count = 1
  local gap = false
  local docksSeen = {}

  local function look(h)
    face(h)
    local ok, d = turtle.inspect()
    return ok, d
  end

  -- Find the dock first, from the starting spot
  for h = 0, 3 do
    local ok, d = look(h)
    if isContainer(ok, d) then dockDir = h; cells[key(DX[h], DZ[h])] = "dock"; break end
  end

  local function visit()
    for h = 0, 3 do
      local nx, nz = S.x + DX[h], S.z + DZ[h]
      local k = key(nx, nz)
      if cells[k] == nil then
        if math.abs(nx) > MAX_REACH or math.abs(nz) > MAX_REACH then gap = true; return end
        local ok, d = look(h)
        local n = ok and tostring(d.name) or "minecraft:air"
        if ok and n:find("slab") then
          cells[k] = "border"
        elseif ok and isContainer(ok, d) then
          cells[k] = "dock"
          docksSeen[#docksSeen + 1] = { from = key(S.x, S.z), dir = h }
        elseif ok and (isLog(n) or isSapling(n)) then
          cells[k] = "tree"; ground[k] = true; count = count + 1
        elseif ok and not isSoft(n) and not n:find("leaves") then
          cells[k] = "blocked"
        else
          if ok then turtle.dig() end
          if move("f") then
            cells[k] = "lane"; count = count + 1
            local ok2, d2 = turtle.inspectDown()
            ground[k] = ok2 and plantable(d2.name) and true or false
            visit()
            face((h + 2) % 4)        -- always walk back, even after finding a gap
            local back, why = move("f")
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
  face(0)
  if gap then
    error("The slab border has a gap (zone runs past " .. MAX_REACH .. " blocks). Fix it and survey again.", 0)
  end
  if not dockDir then
    for _, h in ipairs({ "up", "down" }) do
      local ok, d
      if h == "up" then ok, d = turtle.inspectUp() else ok, d = turtle.inspectDown() end
      if isContainer(ok, d) then dockDir = h; break end
    end
  end
  local home = key(0, 0)
  if not dockDir and #docksSeen > 0 then home, dockDir = docksSeen[1].from, docksSeen[1].dir end
  if not dockDir then error("No dock barrel next to my starting spot or in the border.", 0) end

  -- Pick the grid offset that fits the most trees, each with a lane next to it
  local best, bestOx, bestOz = -1, 0, 0
  for ox = 0, SPACING - 1 do
    for oz = 0, SPACING - 1 do
      local n = 0
      for k, kind in pairs(cells) do
        local x, z = unkey(k)
        if (kind == "lane" or kind == "tree") and ground[k] and x % SPACING == ox and z % SPACING == oz and not (x == 0 and z == 0) and k ~= home then
          for h = 0, 3 do
            local nk = key(x + DX[h], z + DZ[h])
            if cells[nk] == "lane" then n = n + 1; break end
          end
        end
      end
      if n > best then best, bestOx, bestOz = n, ox, oz end
    end
  end
  local spots = {}
  for k, kind in pairs(cells) do
    local x, z = unkey(k)
    if (kind == "lane" or kind == "tree") and ground[k] and x % SPACING == bestOx and z % SPACING == bestOz and not (x == 0 and z == 0) and k ~= home then
      for h = 0, 3 do
        if cells[key(x + DX[h], z + DZ[h])] == "lane" then spots[#spots + 1] = k; break end
      end
    end
  end
  table.sort(spots)
  local spotSet = {}
  for _, k in ipairs(spots) do spotSet[k] = true; cells[k] = "spot" end
  -- Off-grid trees get chopped and not replanted: their cells become lanes afterwards
  Z = { cells = cells, spots = spots, dockDir = dockDir, count = count, home = home }
  writeT(ZONE_FILE, Z)
  setStatus("docked", ("Zone mapped: %d blocks, room for %d trees"):format(count, #spots))
end

---------------------------------------------------------------------------
-- Getting around inside the zone (shortest path over lanes)
---------------------------------------------------------------------------
local tempBlocked = {}
local function walkable(k)
  local c = Z.cells[k]
  return (c == "lane" or c == "offtree") and not tempBlocked[k]
end

local function path(fromK, goalPred)
  local prev, q, head = { [fromK] = false }, { fromK }, 1
  while head <= #q do
    local k = q[head]; head = head + 1
    if goalPred(k) then
      local out = {}
      while k ~= fromK do table.insert(out, 1, k); k = prev[k] end
      return out
    end
    local x, z = unkey(k)
    for h = 0, 3 do
      local nk = key(x + DX[h], z + DZ[h])
      if prev[nk] == nil and walkable(nk) then prev[nk] = k; q[#q + 1] = nk end
    end
  end
end

local function suckAhead() for _ = 1, 4 do if not turtle.suck() then break end end end

local chop   -- defined below
local function clearStray()
  -- Lanes should be empty: a sapling or tree standing in one (planted by mistake, or wild) gets removed
  local ok, d = turtle.inspect()
  if not ok then return end
  if isSapling(d.name) then turtle.dig()
  elseif isLog(d.name) then chop() end
end

local function goTo(goalPred)
  for _ = 1, 6 do
    local p = path(key(S.x, S.z), goalPred)
    if not p then return false end
    local ok = true
    for _, k in ipairs(p) do
      local x, z = unkey(k)
      face(dirTo(x, z))
      suckAhead()
      local here = key(S.x, S.z)
      clearStray()
      if key(S.x, S.z) ~= here then ok = false; break end   -- chopping moved him: plan again
      if not move("f") then tempBlocked[k] = true; ok = false; break end
    end
    if ok then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Working out where he is facing (after an unload mid-turn, or "lumberjack found")
---------------------------------------------------------------------------
-- What he sees on each side must fit what the map says is there.
local function fits(kind, ok, d)
  if kind == nil then return true end                                   -- never mapped: anything goes
  local n = ok and tostring(d.name) or "minecraft:air"
  local slab, box = ok and n:find("slab") ~= nil, isContainer(ok, d)
  if kind == "border" then return slab end
  if kind == "dock" then return box end
  if slab or box then return false end
  if kind == "blocked" then return ok and not isSoft(n) and not n:find("leaves") and not isLog(n) and not isSapling(n) end
  return true                                                           -- lane / spot / tree / offtree
end

-- Keeps only the candidates ({x, z, h}) that fit what he sees on all four sides.
-- Raw turns: four right turns bring him back to the heading he started with.
local function observe(cands)
  local seen = {}
  for r = 0, 3 do
    local ok, d = turtle.inspect()
    seen[r] = { ok, d }
    turtle.turnRight()
  end
  local out = {}
  for _, c in ipairs(cands) do
    local good = true
    for r = 0, 3 do
      local h = (c[3] + r) % 4
      if not fits(Z.cells[key(c[1] + DX[h], c[2] + DZ[h])], seen[r][1], seen[r][2]) then good = false; break end
    end
    if good then out[#out + 1] = c end
  end
  return out, seen
end

-- Works out which candidate is true. If the four sides don't settle it (open lanes all look alike),
-- he wanders a few steps along lanes, tracking every candidate, until only one still fits.
-- Returns the true {x, z, h} (his position now), or nil.
local function orient(cands)
  S.lost = true; save()             -- unloaded while working it out = ask for help
  local turnsInARow = 0
  for _ = 1, 40 do
    local seen
    cands, seen = observe(cands)
    if #cands <= 1 then break end
    local okF, dF = seen[0][1], seen[0][2]
    local clear = not okF or isSoft(dF.name) or tostring(dF.name):find("leaves")
    local allLanes = true
    for _, c in ipairs(cands) do
      local kind = Z.cells[key(c[1] + DX[c[3]], c[2] + DZ[c[3]])]
      if kind ~= "lane" and kind ~= "offtree" then allLanes = false; break end
    end
    if clear and allLanes and (not okF or turtle.dig()) and turtle.forward() then
      for _, c in ipairs(cands) do c[1], c[2] = c[1] + DX[c[3]], c[2] + DZ[c[3]] end
      turnsInARow = 0
    else
      if turnsInARow >= 8 then break end
      turtle.turnRight()
      for _, c in ipairs(cands) do c[3] = (c[3] + 1) % 4 end
      turnsInARow = turnsInARow + 1
    end
  end
  if #cands == 1 then return cands[1] end
end

local function goHome()
  local home = Z.home or key(0, 0)
  if key(S.x, S.z) == home then return true end
  if not goTo(function(k) return k == home end) then
    tempBlocked = {}
    if not goTo(function(k) return k == home end) then error("Can't find my way home", 0) end
  end
  return true
end

---------------------------------------------------------------------------
-- Trees
---------------------------------------------------------------------------
local function digLeavesAround()
  for _ = 1, 4 do
    local ok, d = turtle.inspect()
    if ok and (tostring(d.name):find("leaves") or isLog(d.name)) then turtle.dig() end
    turnRight()
  end
end

-- Facing a grown trunk from a lane: chop it all, come back to the lane
function chop()
  local ok, d = turtle.inspect()
  local logName = d and d.name
  turtle.dig()
  if not move("f") then return logName end
  local climbed = 0
  while true do
    local okUp, up = turtle.inspectUp()
    if okUp and (isLog(up.name) or tostring(up.name):find("leaves")) then
      digLeavesAround()
      turtle.digUp()
      if not move("u") then break end
      climbed = climbed + 1
    else break end
  end
  digLeavesAround()
  for _ = 1, climbed do
    while not move("d") do turtle.digDown() end
  end
  if not move("b") then              -- something behind (leaves, a mob): turn round and push through
    turnRight(); turnRight(); move("f"); turnRight(); turnRight()
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

local function abortIfNeeded()
  if ctrl and ctrl.seq ~= S.seq and (ctrl.want == "stop" or ctrl.want == "survey") then error({ abort = "cmd" }, 0) end
end

local function rounds()
  setStatus("working", "Doing my rounds")
  tempBlocked = {}
  local chopped, planted, noSapling = 0, 0, false
  -- Visit spots nearest-first
  local todo = {}
  for _, k in ipairs(Z.spots) do todo[k] = true end
  -- Off-grid trees found during the survey get chopped once
  for k, c in pairs(Z.cells) do if c == "tree" then todo[k] = "off" end end
  while next(todo) do
    abortIfNeeded()
    local target
    local p = path(key(S.x, S.z), function(k)
      local x, z = unkey(k)
      for h = 0, 3 do
        local nk = key(x + DX[h], z + DZ[h])
        if todo[nk] then target = nk; return true end
      end
      return false
    end)
    if not p then break end
    if not goTo(function(k) return k == (p[#p] or key(S.x, S.z)) end) then
      todo[target] = nil
    else
      local tx, tz = unkey(target)
      face(dirTo(tx, tz))
      local ok, d = turtle.inspect()
      local kind = todo[target]
      todo[target] = nil
      if ok and isLog(d.name) then
        local logName = chop()
        chopped = chopped + 1
        if kind == "off" then
          Z.cells[target] = "offtree"; writeT(ZONE_FILE, Z)  -- becomes a lane
        else
          local r = plant(saplingFor(logName))
          if r == "planted" then planted = planted + 1 elseif r == "nosapling" then noSapling = true end
        end
      elseif kind ~= "off" and not (ok and isSapling(d.name)) then
        local r = plant()
        if r == "planted" then planted = planted + 1 elseif r == "nosapling" then noSapling = true end
      end
      if fuel() < 100 then break end
    end
  end
  S.lastRound = { chopped = chopped, planted = planted }
  return chopped, planted, noSapling
end

---------------------------------------------------------------------------
-- Dock
---------------------------------------------------------------------------
local function faceDock() if Z.dockDir ~= "up" and Z.dockDir ~= "down" then face(Z.dockDir) end end
local function dropDock(n) if Z.dockDir == "up" then return turtle.dropUp(n) elseif Z.dockDir == "down" then return turtle.dropDown(n) end return turtle.drop(n) end
local function suckDock() if Z.dockDir == "up" then return turtle.suckUp() elseif Z.dockDir == "down" then return turtle.suckDown() end return turtle.suck() end

local DOCK_FUEL = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true, ["minecraft:blaze_rod"] = true }

-- Refuel from the dock BEFORE unloading, so he never grabs his own logs back.
-- Only real fuel is burned; if the dock is dry, he burns a few of his logs instead.
local function refuelFromDock()
  local limit = turtle.getFuelLimit()
  local target = math.min(FUEL_TARGET, limit == "unlimited" and 0 or limit)
  for _ = 1, 8 do
    if fuel() >= target then break end
    local free
    for s = 16, 1, -1 do if turtle.getItemCount(s) == 0 then free = s; break end end
    if not free then break end
    turtle.select(free)
    if not suckDock() then break end
    local d = turtle.getItemDetail(free)
    if d and DOCK_FUEL[d.name] then
      while fuel() < target and turtle.getItemCount(free) > 0 do turtle.refuel(1) end
      if turtle.getItemCount(free) > 0 then dropDock() end
    else
      dropDock(); break           -- not fuel (storage hasn't collected it yet): leave it
    end
  end
  if fuel() < 500 then
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and isLog(d.name) then
        turtle.select(s)
        while fuel() < 1000 and turtle.getItemCount(s) > 0 do turtle.refuel(1) end
      end
      if fuel() >= 1000 then break end
    end
  end
  turtle.select(1)
end

local function dock()
  setStatus("docked", "Unloading")
  faceDock()
  refuelFromDock()
  local haul = {}
  local saplingsKept = 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      turtle.select(s)
      if isSapling(d.name) and saplingsKept < KEEP_SAPLINGS then
        local keep = math.min(d.count, KEEP_SAPLINGS - saplingsKept)
        saplingsKept = saplingsKept + keep
        if d.count > keep then dropDock(d.count - keep) end
      else
        haul[d.name] = (haul[d.name] or 0) + d.count
        dropDock()
      end
    end
  end
  local list = {}
  for n, c in pairs(haul) do list[#list + 1] = { n, c } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  S.lastHaul = list
  turtle.select(1)
  face(0)
  save()
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function applyCtrl()
  if not ctrl or ctrl.seq == S.seq then return nil end
  S.seq = ctrl.seq
  save()
  return ctrl.want
end

local function mainLoop()
  -- Restarted halfway up a tree? Finish the trunk above, then climb down.
  if S.y > 0 then
    while true do
      local ok, d = turtle.inspectUp()
      if ok and isLog(d.name) then turtle.digUp(); if not move("u") then break end else break end
    end
    while S.y > 0 do turtle.digDown(); if not move("d") then break end end
  end
  if not Z then
    local ok, err = pcall(survey)
    if not ok then setStatus("error", tostring(err)); pcall(goHome) end
  end
  S.nextRound = S.nextRound or 0
  while true do
    local want = applyCtrl()
    if want == "survey" then
      pcall(goHome); face(0)
      local ok, err = pcall(survey)
      if not ok then setStatus("error", tostring(err)); pcall(goHome) end
    elseif want == "rounds" then S.nextRound = 0; S.paused = false
    elseif want == "stop" then S.paused = true
    elseif want == "go" then S.paused = false end

    if S.lost then
      setStatus("lost", "Put me on my home spot next to my dock (any facing), then type: lumberjack found")
      os.sleep(10)
    elseif Z and not S.paused and os.clock() >= S.nextRound then
      if fuel() < 200 then
        pcall(goHome)
        dock()
        if fuel() < 200 then setStatus("waiting", "Need fuel in my dock"); S.nextRound = os.clock() + 60 end
      end
      if fuel() >= 200 then
        local ok, a, b, c = pcall(rounds)
        if not ok and not (type(a) == "table" and a.abort) then setStatus("error", tostring(a)) end
        local okHome, err = pcall(goHome)
        if not okHome then S.lost = true; save() else dock() end
        S.nextRound = os.clock() + ROUND_EVERY
        if ok and okHome then
          if c then setStatus("waiting", ("Out of saplings. Chopped %d, planted %d"):format(a, b))
          else setStatus("docked", ("Round done: chopped %d, planted %d"):format(a, b)) end
        end
      end
    else
      if S.status ~= "waiting" and S.status ~= "error" then
        setStatus("docked", S.paused and "Paused. Say: island " .. NAME:lower() .. " go"
          or ("Next round in %d min"):format(math.max(0, math.ceil((S.nextRound - os.clock()) / 60))))
      end
      local t = os.clock() + 10
      while os.clock() < t and not (ctrl and ctrl.seq ~= S.seq) do os.sleep(1) end
      if Z and (S.status == "waiting" or S.status == "error") then S.status = "docked" end
    end
  end
end

local function netLoop()
  if not modem then return os.pullEvent("never") end
  rednet.open(peripheral.getName(modem))
  local last = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "cmd" and tostring(msg.target):lower() == NAME:lower() then ctrl = msg end
    if os.clock() - last >= 3 then rednet.broadcast(statusMsg(), PROTOCOL); last = os.clock() end
  end
end

-- Start-up
do
  -- startup.lua (the self-updater) normally starts us; only write a fallback if there's none
  if not fs.exists("startup.lua") then
    local f = fs.open("startup.lua", "w"); f.write('shell.run("lumberjack")\n'); f.close()
  end
end
if S.x == nil then S.x, S.y, S.z, S.h = 0, 0, 0, 0 end
if S.pending then
  local f = turtle.getFuelLevel()
  if type(f) == "number" and type(S.pending.fuel) == "number" then
    if f < S.pending.fuel then apply(S.pending.kind) end
  else S.lost = true end
  S.pending = nil
end
if S.turning and args[1] ~= "found" then
  local hs = type(S.turning) == "table" and S.turning or { S.h, (S.h + 1) % 4, (S.h + 3) % 4 }
  if S.y and S.y > 0 then
    -- Up a tree: climbing down doesn't depend on which way he faces
    while S.y > 0 do turtle.digDown(); if not move("d") then break end end
  end
  local cands = {}
  for _, h in ipairs(hs) do cands[#cands + 1] = { S.x, S.z, h } end
  local m = Z and S.y == 0 and orient(cands)
  if m then S.x, S.z, S.h, S.lost = m[1], m[2], m[3], nil else S.lost = true end
  S.turning = nil
end
if args[1] == "found" then
  -- Put back on his home spot next to the dock, facing any way: the dock tells him which way is which
  local cands, seenK = {}, {}
  for _, k in ipairs({ Z and Z.home or "0,0", "0,0" }) do
    if not seenK[k] then
      seenK[k] = true
      local x, z = unkey(k)
      for h = 0, 3 do cands[#cands + 1] = { x, z, h } end
    end
  end
  local m = Z and orient(cands)
  if m then S.x, S.y, S.z, S.h = m[1], 0, m[2], m[3]
  elseif Z then
    print("I can't tell which way I'm facing here. Put me on my home spot right next to my dock and try again.")
    return
  else S.x, S.y, S.z, S.h = 0, 0, 0, 0 end
  S.lost, S.turning, S.pending = nil, nil, nil
end
if args[1] == "survey" then Z = nil end
if args[1] == "rounds" then S.nextRound = 0; S.paused = false end
if args[1] == "stop" then S.paused = true end
if args[1] == "go" then S.paused = false end
S.nextRound = (args[1] == "rounds") and 0 or nil
save()
setStatus("docked", "Starting")
parallel.waitForAny(mainLoop, netLoop)
