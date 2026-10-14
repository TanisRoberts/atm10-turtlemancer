-- farmbot.lua  --  the engine under every farm turtle (Partridge, Woodpecker). Loaded with dofile().
--
-- What it gives a farm turtle:
--   * <name>.env settings, made on first run, edited live (same rules as the other .env files)
--   * saved state (atomic writes) and dead-reckoned moves in the farm's own frame
--   * GPS anchoring: the farm frame is pinned to world coordinates, so after a restart (even one
--     mid-turn) he asks GPS where he is and which way he faces instead of getting lost. Without GPS
--     he works it out from his map, like before.
--   * the radio: status every few seconds on "tanis-farm" (the mainframe board and the Farmhand both
--     read it), orders from chat (via the mainframe) and from the Farmhand, live setting changes,
--     remote reboots
--   * the main loop: map, rounds on a timer, dock, re-map every few rounds, retry a failed map
-- The turtle program supplies the farming itself (see R in B.run).

local B = {}

local PROTOCOL = "tanis-farm"
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local COMPASS = { [0] = "north", "east", "south", "west" }
B.DX, B.DZ, B.COMPASS, B.PROTOCOL = DX, DZ, COMPASS, PROTOCOL

function B.key(x, z) return x .. "," .. z end
function B.unkey(k)
  local x, z = tostring(k):match("^(%-?%d+),(%-?%d+)$")
  return tonumber(x), tonumber(z)
end
local key, unkey = B.key, B.unkey

local function now() return os.epoch("utc") end
B.now = now

---------------------------------------------------------------------------
-- Files
---------------------------------------------------------------------------
function B.readT(p)
  for _, path in ipairs({ p, p .. ".new" }) do
    if fs.exists(path) then
      local f = fs.open(path, "r"); local t = textutils.unserialize(f.readAll() or ""); f.close()
      if type(t) == "table" then return t end
    end
  end
end
function B.writeT(p, t)
  local f = fs.open(p .. ".new", "w"); f.write(textutils.serialize(t)); f.close()
  if fs.exists(p) then fs.delete(p) end
  fs.move(p .. ".new", p)
end

---------------------------------------------------------------------------
-- Settings (.env)
---------------------------------------------------------------------------
B.E = {}
local envFile, envTitle, envDefaults, envStamp
local function stampOf(path)
  if not fs.exists(path) or not fs.attributes then return nil end
  local ok, a = pcall(fs.attributes, path)
  return ok and a and (tostring(a.modified) .. ":" .. tostring(a.size)) or nil
end
local function readEnv()
  local vals = {}
  if fs.exists(envFile) then
    local f = fs.open(envFile, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then vals[k:upper()] = v end
    end
    f.close()
  end
  local missing = {}
  for _, d in ipairs(envDefaults) do
    if vals[d[1]] == nil then missing[#missing + 1] = d; vals[d[1]] = tostring(d[2]) end
  end
  if #missing > 0 then
    local new = not fs.exists(envFile)
    local f = fs.open(envFile, new and "w" or "a")
    if new then f.writeLine("# " .. envTitle .. " settings. Edit and save: picked up within a few seconds.") end
    for _, d in ipairs(missing) do
      f.writeLine(""); f.writeLine("# " .. d[3]); f.writeLine(d[1] .. "=" .. tostring(d[2]))
    end
    f.close()
  end
  for _, d in ipairs(envDefaults) do
    local v = vals[d[1]]
    if type(d[2]) == "number" then B.E[d[1]] = tonumber(v) or d[2] else B.E[d[1]] = v end
    if d.min and type(B.E[d[1]]) == "number" then B.E[d[1]] = math.max(d.min, B.E[d[1]]) end
    if d.max and type(B.E[d[1]]) == "number" then B.E[d[1]] = math.min(d.max, B.E[d[1]]) end
  end
  envStamp = stampOf(envFile)
end
function B.refreshEnv() if stampOf(envFile) ~= envStamp then readEnv() end end

-- Change one setting in the .env file (keeps comments and every other line)
function B.setEnv(k, v)
  k = tostring(k):upper()
  local known = false
  for _, d in ipairs(envDefaults) do if d[1] == k then known = true end end
  if not known then return false end
  local lines, done = {}, false
  if fs.exists(envFile) then
    local f = fs.open(envFile, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local lk = line:match("^%s*([%w_]+)%s*=")
      if lk and lk:upper() == k then line = k .. "=" .. tostring(v); done = true end
      lines[#lines + 1] = line
    end
    f.close()
  end
  if not done then lines[#lines + 1] = k .. "=" .. tostring(v) end
  local f = fs.open(envFile, "w")
  for _, l in ipairs(lines) do f.writeLine(l) end
  f.close()
  readEnv()
  return true
end

---------------------------------------------------------------------------
-- State and status
---------------------------------------------------------------------------
B.S = {}
B.Z = nil              -- the farm map (the turtle program fills it in)
local S
local stateFile, zoneFile
function B.save() B.writeT(stateFile, S) end
function B.saveZone() if B.Z then B.writeT(zoneFile, B.Z) end end

local lastShown = ""
function B.setStatus(st, msg)
  S.status, S.msg = st, msg or ""
  local line = st .. (S.msg ~= "" and (": " .. S.msg) or "")
  if line ~= lastShown then
    lastShown = line
    print(("[%s] %s"):format(textutils.formatTime(os.time(), true), line))
    B.save()
  end
end

---------------------------------------------------------------------------
-- Moving (farm frame: x/z flat, heading 0 = "north" of the farm; y 0 = his working height)
---------------------------------------------------------------------------
local function apply(kind)
  if kind == "f" then S.x, S.z = S.x + DX[S.h], S.z + DZ[S.h]
  elseif kind == "b" then S.x, S.z = S.x - DX[S.h], S.z - DZ[S.h]
  elseif kind == "u" then S.y = S.y + 1
  else S.y = S.y - 1 end
end
B.OPS = {
  f = { move = turtle.forward, dig = turtle.dig,     inspect = turtle.inspect,     attack = turtle.attack,     suck = turtle.suck },
  b = { move = turtle.back },
  u = { move = turtle.up,      dig = turtle.digUp,   inspect = turtle.inspectUp,   attack = turtle.attackUp,   suck = turtle.suckUp },
  d = { move = turtle.down,    dig = turtle.digDown, inspect = turtle.inspectDown, attack = turtle.attackDown, suck = turtle.suckDown },
}

-- B.onBlocked(kind, ok, data, op) is set by the turtle program: return "retry" after clearing the
-- way itself, "fail" to give up (a real block), or nil to wait and swing at whatever's in the way.
B.onBlocked = nil

function B.move(kind)
  local op = B.OPS[kind]
  for _ = 1, 12 do
    if turtle.getFuelLevel() == 0 then return false, "Out of fuel" end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }
    B.save()
    if op.move() then apply(kind); S.pending = nil; B.save(); return true end
    S.pending = nil
    local ok, d
    if op.inspect then ok, d = op.inspect() end
    local act = B.onBlocked and B.onBlocked(kind, ok, d, op)
    if act == "fail" then B.save(); return false, "Blocked by " .. tostring(d and d.name) end
    if act ~= "retry" then
      if op.attack then op.attack() end
      os.sleep(0.5)
    end
  end
  B.save()
  return false, "Something keeps getting in the way"
end

-- S.turning records both headings, so a restart mid-turn knows the two possibilities
function B.turnRight() S.turning = { S.h, (S.h + 1) % 4 }; B.save(); turtle.turnRight(); S.h = (S.h + 1) % 4; S.turning = nil; B.save() end
function B.turnLeft()  S.turning = { S.h, (S.h + 3) % 4 }; B.save(); turtle.turnLeft();  S.h = (S.h + 3) % 4; S.turning = nil; B.save() end
function B.face(h)
  local d = (h - S.h) % 4
  if d == 1 then B.turnRight() elseif d == 2 then B.turnRight(); B.turnRight() elseif d == 3 then B.turnLeft() end
end
function B.dirTo(x, z)
  for h = 0, 3 do if S.x + DX[h] == x and S.z + DZ[h] == z then return h end end
end
function B.fuel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end
function B.freeSlots()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end
  return n
end
function B.countWhere(pred)
  local c = 0
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and pred(d.name) then c = c + d.count end end
  return c
end

---------------------------------------------------------------------------
-- Paths over the map: passable(k) says which cells he can be in
---------------------------------------------------------------------------
B.tempBlocked = {}
function B.path(fromK, goalPred, passable)
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
      if prev[nk] == nil and passable(nk) and not B.tempBlocked[nk] then prev[nk] = k; q[#q + 1] = nk end
    end
  end
end

-- Walk/fly to the first cell matching goalPred. beforeStep(k) runs facing each next cell and may
-- return false to re-plan (e.g. he chopped something and moved).
function B.goTo(goalPred, passable, beforeStep)
  for _ = 1, 6 do
    local p = B.path(key(S.x, S.z), goalPred, passable)
    if not p then return false end
    local ok = true
    for _, k in ipairs(p) do
      local x, z = unkey(k)
      local h = B.dirTo(x, z)
      if not h then ok = false; break end
      B.face(h)
      if beforeStep and beforeStep(k) == false then ok = false; break end
      if not B.move("f") then B.tempBlocked[k] = true; ok = false; break end
    end
    if ok then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- GPS: the farm frame pinned to the world. Z.anchor = { x, y, z (world spot of farm 0,0,0), f
-- (compass direction of farm heading 0) }
---------------------------------------------------------------------------
B.gpsOk = nil
function B.locate(timeout)
  local ok, x, y, z = pcall(gps.locate, timeout or 2)
  if ok and x then
    B.gpsOk = true
    return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
  end
  B.gpsOk = false
end

local function rot(x, z, f)          -- turn a flat vector f quarter-turns clockwise
  for _ = 1, f % 4 do x, z = -z, x end
  return x, z
end
function B.toAbs(lx, ly, lz)
  local a = B.Z and B.Z.anchor
  if not a then return nil end
  local dx, dz = rot(lx, lz, a.f)
  return a.x + dx, a.y + ly, a.z + dz
end
function B.toLocal(ax, ay, az)
  local a = B.Z and B.Z.anchor
  if not a then return nil end
  local dx, dz = rot(ax - a.x, az - a.z, 4 - a.f)
  return dx, ay - a.y, dz
end

local function dirOf(dx, dz)
  if dz < 0 then return 0 elseif dx > 0 then return 1 elseif dz > 0 then return 2 elseif dx < 0 then return 3 end
end

-- Which compass way is he facing? Steps into a free block (turning if needed), asks GPS, steps back,
-- turns back. Raw moves: S isn't touched. Returns compass, x, y, z (where he is now) or nil.
function B.findCompass()
  local x0, y0, z0 = B.locate(3)
  if not x0 then return nil end
  for turns = 0, 3 do
    if not turtle.detect() and turtle.forward() then
      local x1, _, z1 = B.locate(3)
      for _ = 1, 5 do if turtle.back() then break end; os.sleep(0.5) end
      if x1 and (x1 ~= x0 or z1 ~= z0) then
        local c = dirOf(x1 - x0, z1 - z0)
        for _ = 1, turns do turtle.turnLeft() end
        local x2, y2, z2 = B.locate(3)
        return (c - turns) % 4, x2 or x0, y2 or y0, z2 or z0
      end
    end
    turtle.turnRight()
  end
  return nil         -- four full turns: back where he started
end

-- Pin the current map to the world, from a pose he trusts (S.x/y/z/h).
function B.learnAnchor()
  if not B.Z then return false end
  local c, ax, ay, az = B.findCompass()
  if not c then return false end
  local f = (c - S.h) % 4
  local dx, dz = rot(S.x, S.z, f)
  B.Z.anchor = { x = ax - dx, y = ay - S.y, z = az - dz, f = f }
  B.saveZone()
  return true
end

function B.absPos()
  if B.Z and B.Z.anchor and S.x then
    local x, y, z = B.toAbs(S.x, S.y, S.z)
    return { x = x, y = y, z = z }
  end
  return B.gpsPos
end
function B.compassName()
  if B.Z and B.Z.anchor and S.h then return COMPASS[(S.h + B.Z.anchor.f) % 4] end
end

-- After a restart (or "found"): use GPS to settle where he is and which way he faces.
-- okAt(lx, ly, lz) says whether a farm position is somewhere he can carry on from.
-- Returns "ok", "carried" (GPS says he's off his farm: message in B.carriedMsg) or nil (no GPS/anchor).
B.carriedMsg = nil
function B.gpsRecover(okAt, needHeading)
  if not (B.Z and B.Z.anchor) then return nil end
  local x, y, z = B.locate(3)
  if not x then return nil end
  local c
  if needHeading then
    c, x, y, z = B.findCompass()
    if not c then return nil end
  end
  local lx, ly, lz = B.toLocal(x, y, z)
  if not okAt(lx, ly, lz) then
    local hlx, hlz = B.unkey(B.Z.home or "0,0")
    local hx, hy, hz = B.toAbs(hlx, 0, hlz)
    B.carriedMsg = ("I'm at %d %d %d, off my farm. Put me back on my home spot (%d %d %d), then press Found"):format(
      x, y, z, hx, hy, hz)
    return "carried"
  end
  S.x, S.y, S.z = lx, ly, lz
  if c then S.h = (c - B.Z.anchor.f) % 4 end
  S.lost, S.turning, S.pending = nil, nil, nil
  B.save()
  return "ok"
end

-- No GPS: work out the true pose among candidates {x, z, h} by looking around and wandering along
-- passable cells. R.sense() looks at the cell ahead and returns what it saw (may step in and back),
-- R.fits(kind, seen) says whether that matches the map, R.passable(kind) where he may wander.
function B.orient(cands, R)
  S.lost = true; B.save()             -- unloaded while working it out = ask for help
  local turnsInARow = 0
  for _ = 1, 40 do
    local seen = {}
    for r = 0, 3 do seen[r] = R.sense(); turtle.turnRight() end
    local out = {}
    for _, c in ipairs(cands) do
      local good = true
      for r = 0, 3 do
        local h = (c[3] + r) % 4
        if not R.fits(B.Z.cells[key(c[1] + DX[h], c[2] + DZ[h])], seen[r]) then good = false; break end
      end
      if good then out[#out + 1] = c end
    end
    cands = out
    if #cands <= 1 then break end
    local allPass = true
    for _, c in ipairs(cands) do
      if not R.passable(B.Z.cells[key(c[1] + DX[c[3]], c[2] + DZ[c[3]])]) then allPass = false; break end
    end
    if allPass and not turtle.detect() and turtle.forward() then
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

---------------------------------------------------------------------------
-- Dock
---------------------------------------------------------------------------
local DOCK_FUEL = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true,
  ["minecraft:blaze_rod"] = true }
B.DOCK_FUEL = DOCK_FUEL

local function dockOps(dir)
  if dir == "up" then return turtle.dropUp, turtle.suckUp end
  if dir == "down" then return turtle.dropDown, turtle.suckDown end
  return turtle.drop, turtle.suck
end

local DOCK_SIDE = { up = "top", down = "bottom" }

-- What's in the dock barrel (a turtle can read the inventory next to it), or nil if it can't tell
local function dockList(dir)
  local side = DOCK_SIDE[dir] or "front"
  if not peripheral.hasType or not peripheral.hasType(side, "inventory") then return nil end
  local ok, l = pcall(peripheral.call, side, "list")
  return ok and type(l) == "table" and l or nil
end

local function holding(name, except)
  local n = 0
  for s = 1, 16 do
    if s ~= except then
      local d = turtle.getItemDetail(s)
      if d and d.name == name then n = n + d.count end
    end
  end
  return n
end

-- Take what he needs out of the dock: fuel up to the target, plus o.want(name, have) more of
-- anything he restocks from it (saplings, say). suck() always hands over the barrel's FIRST stack,
-- so things he doesn't want are held in spare slots and only put back at the end: dropping them
-- straight back would just get them sucked again (and used to stop him looking any further).
-- Returns { [name] = taken } for the restocked items.
local function rummage(drop, suck, dir, target, want)
  local got = {}
  local function fuelNeeded() return target > 0 and B.fuel() < target end
  local function wantsFromDock()
    if not want then return false end
    local l = dockList(dir)
    if not l then return true end              -- can't see in: have a look anyway
    for _, it in pairs(l) do if want(it.name, holding(it.name)) > 0 then return true end end
    return false
  end
  local function fuelInDock()
    local l = dockList(dir)
    if not l then return true end
    for _, it in pairs(l) do if DOCK_FUEL[it.name] then return true end end
    return false
  end
  local held = {}
  for _ = 1, 27 do
    local needFuel = fuelNeeded() and fuelInDock()
    if not needFuel and not wantsFromDock() then break end
    local free
    for s = 16, 1, -1 do if turtle.getItemCount(s) == 0 then free = s; break end end
    if not free then break end
    turtle.select(free)
    if not suck() then break end
    local d = turtle.getItemDetail(free)
    if d and DOCK_FUEL[d.name] and fuelNeeded() then
      while fuelNeeded() and turtle.getItemCount(free) > 0 do turtle.refuel(1) end
    end
    local count = turtle.getItemCount(free)
    if d and count > 0 then
      local keep = want and math.max(0, math.min(count, want(d.name, holding(d.name, free)))) or 0
      if keep > 0 then
        got[d.name] = (got[d.name] or 0) + keep
        if count > keep then drop(count - keep) end   -- he has enough now, so it won't be taken again
        if turtle.getItemCount(free) > keep then held[#held + 1] = free end   -- dock full: hand it back later
      else
        held[#held + 1] = free
      end
    end
  end
  for _, s in ipairs(held) do
    turtle.select(s)
    local d = turtle.getItemDetail(s)
    if d then
      local keep = want and math.max(0, math.min(d.count, want(d.name, holding(d.name, s)))) or 0
      if d.count > keep then drop(d.count - keep) end
    end
  end
  turtle.select(1)
  return got
end

-- Refuel first (so he never grabs his own produce back), then unload everything except what
-- o.keep(name, alreadyKept) says to keep. o.burnOwn(name): his own items he may burn if the dock is dry.
-- o.want(name, have): how many more of an item to take FROM the dock (restocking; storage keeps it
-- there through the dock's Keeps list on the storage computer). B.lastRestock = what he took.
function B.dock(o)
  B.setStatus("docked", "Unloading")
  local dir = B.Z.dockDir
  if dir ~= "up" and dir ~= "down" then B.face(dir) end
  local drop, suck = dockOps(dir)
  local limit = turtle.getFuelLimit()
  local target = math.min(B.E.FUEL_TARGET or 3000, limit == "unlimited" and 0 or limit)
  local restocked = rummage(drop, suck, dir, target, o.want)
  if B.fuel() < 500 and o.burnOwn then
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and o.burnOwn(d.name) then
        turtle.select(s)
        while B.fuel() < 1000 and turtle.getItemCount(s) > 0 and turtle.refuel(1) do end
      end
      if B.fuel() >= 1000 then break end
    end
  end
  local haul, kept = {}, {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      turtle.select(s)
      local keepN = math.max(0, math.min(d.count, (o.keep and o.keep(d.name, kept[d.name] or 0)) or 0))
      kept[d.name] = (kept[d.name] or 0) + keepN
      local give = d.count - keepN
      if give > 0 then
        local before = turtle.getItemCount(s)
        drop(give)
        local gone = before - turtle.getItemCount(s)
        if gone > 0 then haul[d.name] = (haul[d.name] or 0) + gone end
      end
    end
  end
  turtle.select(1)
  -- Second look now he has room (fuel or saplings may have been behind things he couldn't hold)
  for n, c in pairs(rummage(drop, suck, dir, target, o.want)) do restocked[n] = (restocked[n] or 0) + c end
  B.lastRestock = next(restocked) and restocked or nil
  local list = {}
  S.totals = S.totals or {}
  for n, c in pairs(haul) do
    list[#list + 1] = { n, c }
    S.totals[n] = (S.totals[n] or 0) + c
  end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  if #list > 0 then S.lastHaul = list end
  B.save()
  return list
end

---------------------------------------------------------------------------
-- Radio: status out, orders in
---------------------------------------------------------------------------
B.ctrl = nil           -- the newest order not yet acted on
B.rebootWanted = nil
B.NAME = nil
B.ROLE = nil
B.extraStatus = nil    -- function returning role-specific fields
B.gpsPos = nil

local function topTotals(n)
  local list = {}
  for name, c in pairs(S.totals or {}) do list[#list + 1] = { name, c } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  local out = {}
  for i = 1, math.min(n, #list) do out[i] = list[i] end
  return out
end

function B.statusMsg()
  local home
  if B.Z and B.Z.anchor then
    local hx, hz = unkey(B.Z.home or "0,0")
    local x, y, z = B.toAbs(hx, 0, hz)
    home = { x = x, y = y, z = z }
  end
  local m = {
    type = "status", role = B.ROLE, id = os.getComputerID(), label = B.NAME, state = S.status, msg = S.msg,
    fuel = turtle.getFuelLevel(), fuelLimit = turtle.getFuelLimit(), pos = B.absPos(), facing = B.compassName(),
    gps = B.gpsOk == true, anchored = B.Z ~= nil and B.Z.anchor ~= nil, home = home, mapped = B.Z ~= nil,
    paused = S.paused, seq = S.seq, setSeq = S.setSeq, rebootDone = S.rebootDone,
    nextRound = S.nextAt and math.max(0, math.floor((S.nextAt - now()) / 1000)) or nil,
    every = (B.E.EVERY or 10) * 60, rounds = S.rounds or 0, lastRound = S.lastRound, lastHaul = S.lastHaul,
    totals = topTotals(8), settings = {}, v = 2,
  }
  for _, d in ipairs(envDefaults) do if d.remote then m.settings[d[1]] = B.E[d[1]] end end
  if B.extraStatus then
    local ok, extra = pcall(B.extraStatus)
    if ok and type(extra) == "table" then for k, v in pairs(extra) do m[k] = v end end
  end
  return m
end

local function forMe(msg)
  if type(msg) ~= "table" or msg.type ~= "cmd" then return false end
  if msg.to ~= nil then return tonumber(msg.to) == os.getComputerID() end
  return tostring(msg.target):lower() == tostring(B.NAME):lower()
end

function B.netLoop()
  local opened = 0
  peripheral.find("modem", function(name) rednet.open(name); opened = opened + 1; return false end)
  if opened == 0 then return os.pullEvent("never") end
  local last = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if forMe(msg) then
      local seq = tonumber(msg.seq)
      -- Orders carry a time-stamp seq: only ever act on a newer one, so the mainframe and the Farmhand
      -- repeating their latest orders can't flip him back and forth
      if seq and msg.want and seq > (S.seq or 0) and (not B.ctrl or seq > (tonumber(B.ctrl.seq) or 0)) then
        B.ctrl = msg
      end
      if msg.reboot and msg.reboot ~= S.rebootDone then B.rebootWanted = msg.reboot end
      local setSeq = tonumber(msg.setSeq)
      if type(msg.set) == "table" and setSeq and setSeq > (S.setSeq or 0) then
        for k, v in pairs(msg.set) do B.setEnv(k, v) end
        S.setSeq = setSeq
        B.save()
      end
    end
    if os.clock() - last >= 3 then rednet.broadcast(B.statusMsg(), PROTOCOL); last = os.clock() end
  end
end

function B.gpsLoop()
  while true do
    if not (B.Z and B.Z.anchor) then
      local x, y, z = B.locate(1)
      if x then B.gpsPos = { x = x, y = y, z = z } end
    end
    os.sleep(10)
  end
end

-- An order newer than the last one acted on? (doesn't consume it)
function B.pendingWant()
  if B.ctrl and (tonumber(B.ctrl.seq) or 0) > (S.seq or 0) then return B.ctrl.want end
end
function B.takeOrder()
  local w = B.pendingWant()
  if not w then return nil end
  S.seq = tonumber(B.ctrl.seq)
  B.save()
  return w
end
-- For long jobs: throw out of a round when an order says stop/re-map/found, or a reboot is wanted
function B.abortIfNeeded()
  local w = B.pendingWant()
  if w == "stop" or w == "survey" or w == "found" or B.rebootWanted then error({ abort = w or "reboot" }, 0) end
end

function B.maybeReboot()
  if not B.rebootWanted or B.rebootWanted == S.rebootDone then return end
  S.rebootDone = B.rebootWanted
  B.setStatus("rebooting", "Rebooting to update")
  B.save()
  os.sleep(3.5)                        -- let the radio say so
  os.reboot()
end

---------------------------------------------------------------------------
-- The main loop
--   R.name, R.prog (program name), R.zoneVersion
--   R.boot()                    -- restarted mid-job: get back to a safe height
--   R.okAt(lx, ly, lz)          -- can he carry on from here (GPS check)?
--   R.recoverNoGps(kind)        -- kind "turn" (mid-turn) or "found": returns true if settled
--   R.survey(fresh)             -- builds B.Z (fresh = from where he stands, new frame)
--   R.rounds()                  -- one round; returns summary text, waitingText (or nil)
--   R.goHome()                  -- errors if he can't
--   R.dock()                    -- unload + refuel (calls B.dock)
---------------------------------------------------------------------------
local function trySurvey(R, fresh)
  local ok, err = pcall(R.survey, fresh)
  if not ok then
    B.setStatus("error", tostring(err))
    S.surveyFailedAt = now()
    if B.Z then pcall(R.goHome) end
    return false
  end
  S.surveyFailedAt, S.sinceSurvey = nil, 0
  -- A map with no anchor yet: pin it to the world now if GPS answers
  if B.Z and not B.Z.anchor then pcall(B.learnAnchor) end
  B.save()
  return true
end

local function remap(R)
  if not B.Z then return trySurvey(R, true) end
  B.setStatus("surveying", "Re-mapping the farm")
  local okH = pcall(R.goHome)
  if not okH then B.setStatus("error", "Can't get home to re-map"); return false end
  return trySurvey(R, false)
end

local function settle(R, why)
  -- GPS first: exact and quick
  local r = B.gpsRecover(R.okAt, true)
  if r == "ok" then return true end
  if r == "carried" then S.lost = true; B.save(); B.setStatus("lost", B.carriedMsg); return false end
  local ok = R.recoverNoGps(why)
  if ok then S.lost, S.turning = nil, nil; B.save() else S.lost = true; B.save() end
  return ok
end

-- At home: does GPS agree with where he thinks he is? If not, his reckoning slipped (a missed
-- move, a shove): settle again from GPS before anything else.
local function checkHome(R)
  if not (B.Z and B.Z.anchor) then return true end
  local x, y, z = B.locate(2)
  if not x then return true end
  local lx, ly, lz = B.toLocal(x, y, z)
  if lx == S.x and ly == S.y and lz == S.z then return true end
  B.setStatus("working", "Off my count: checking where I am")
  local ok = settle(R, "turn")
  if ok then pcall(R.goHome) end
  return ok
end

local function idle(seconds)
  local t = os.clock() + seconds
  while os.clock() < t and not B.pendingWant() and not B.rebootWanted do os.sleep(1) end
end

function B.mainLoop(R)
  R.boot()
  if not B.Z then trySurvey(R, true)
  elseif (B.Z.v or 1) < (R.zoneVersion or 1) then remap(R)
  elseif not B.Z.anchor and not S.lost then pcall(B.learnAnchor) end
  while true do
    B.refreshEnv()
    B.maybeReboot()
    local want = B.takeOrder()
    if want == "survey" then remap(R)
    elseif want == "rounds" then S.nextAt = 0; S.paused = false
    elseif want == "stop" then S.paused = true
    elseif want == "go" then S.paused = false
    elseif want == "found" then
      if settle(R, "found") then B.setStatus("docked", "Found my way, thanks") end
    end
    B.save()

    if S.lost then
      if S.status ~= "lost" then B.setStatus("lost", "Lost. Put me back on my home spot, then press Found") end
      idle(30)
      -- GPS may be back (or he's been carried home): try again quietly
      if S.lost and B.Z and B.Z.anchor then
        local r = B.gpsRecover(R.okAt, true)
        if r == "ok" then B.setStatus("docked", "Found my way again") end
      end
    elseif not B.Z then
      local retry = (B.E.SURVEY_RETRY or 5) * 60000
      if not S.paused and (not S.surveyFailedAt or now() - S.surveyFailedAt >= retry) then
        trySurvey(R, true)
      else
        idle(10)
      end
    elseif not S.paused and now() >= (S.nextAt or 0) then
      if B.fuel() < (B.E.FUEL_LOW or 150) then
        pcall(R.goHome); pcall(R.dock)
        if B.fuel() < (B.E.FUEL_LOW or 150) then
          B.setStatus("waiting", "Need fuel in my dock")
          S.nextAt = now() + 60000
        end
      end
      if B.fuel() >= (B.E.FUEL_LOW or 150) then
        B.tempBlocked = {}
        local ok, summary, waiting = pcall(R.rounds)
        local aborted = not ok and type(summary) == "table" and summary.abort
        if not ok and not aborted then B.setStatus("error", tostring(summary)) end
        local okHome, err = pcall(R.goHome)
        if okHome and not checkHome(R) then okHome, err = false, "Lost my count" end
        if okHome then pcall(R.dock)
        else
          B.setStatus("error", tostring(err))
          settle(R, "turn")
        end
        S.nextAt = now() + (B.E.EVERY or 10) * 60000
        if ok then
          S.rounds = (S.rounds or 0) + 1
          S.sinceSurvey = (S.sinceSurvey or 0) + 1
          local every = B.E.RESURVEY_EVERY or 0
          if okHome and every > 0 and S.sinceSurvey >= every then remap(R) end
          if S.status ~= "error" and S.status ~= "lost" then
            if waiting then B.setStatus("waiting", waiting) else B.setStatus("docked", summary) end
          end
        end
        B.save()
      end
    else
      if S.status ~= "waiting" and S.status ~= "error" or (S.nextAt and now() >= S.nextAt) then
        local mins = math.max(0, math.ceil(((S.nextAt or 0) - now()) / 60000))
        B.setStatus("docked", S.paused and "Paused (Go on the Farmhand, or: island " .. B.NAME:lower() .. " go)"
          or ("Next round in %d min"):format(mins))
      end
      idle(10)
    end
  end
end

-- Start everything. R as above; cfg = { name, role, prog, env = {file, title, defaults}, state, zone }
function B.run(cfg, R, args)
  B.NAME = os.getComputerLabel() or cfg.name
  B.ROLE = cfg.role
  envFile, envTitle, envDefaults = cfg.env.file, cfg.env.title, cfg.env.defaults
  stateFile, zoneFile = cfg.state, cfg.zone
  readEnv()
  B.S = B.readT(stateFile) or {}
  S = B.S
  if cfg.onLoad then cfg.onLoad(S) end
  B.Z = B.readT(zoneFile)
  if not fs.exists("startup.lua") then      -- the self-updater normally starts us
    local f = fs.open("startup.lua", "w"); f.write('shell.run("' .. cfg.prog .. '")\n'); f.close()
  end
  if S.x == nil then S.x, S.y, S.z, S.h = 0, 0, 0, 0 end
  -- Restarted mid-move: fuel tells whether the move happened
  if S.pending then
    local f = turtle.getFuelLevel()
    if type(f) == "number" and type(S.pending.fuel) == "number" then
      if f < S.pending.fuel then apply(S.pending.kind) end
      S.pending = nil
    end
  end
  args = args or {}
  if args[1] == "survey" then B.Z = nil; if fs.exists(zoneFile) then fs.delete(zoneFile) end; S.lost, S.turning, S.pending = nil, nil, nil; S.x, S.y, S.z, S.h = 0, 0, 0, 0 end
  if args[1] == "stop" then S.paused = true end
  if args[1] == "go" or args[1] == "rounds" then S.paused = false end
  if args[1] == "rounds" then S.nextAt = 0 end
  B.save()
  B.setStatus("docked", "Starting")
  local needs = (S.turning or S.pending or S.lost or args[1] == "found") and B.Z
  if needs then
    local why = (args[1] == "found") and "found" or "turn"
    R.boot()
    if settle(R, why) then B.setStatus("docked", "Back on track") end
  else
    S.turning, S.pending = nil, nil
    -- Not lost: still check GPS agrees (he may have been carried while unloaded)
    if B.Z and B.Z.anchor then
      local r = B.gpsRecover(R.okAt, false)
      if r == "carried" then S.lost = true; B.save(); B.setStatus("lost", B.carriedMsg) end
    end
  end
  parallel.waitForAny(function() B.mainLoop(R) end, B.netLoop, B.gpsLoop)
end

return B
