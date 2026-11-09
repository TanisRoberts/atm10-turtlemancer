-- weaver_move.lua  --  moving by dead reckoning from the dock (dock = 0,0,0), one move at a time, with the
-- position saved before every move so a reboot or chunk unload loses nothing. Keeps his chunk loaded (core.chunk).
-- A part of weaver.lua.

OPS = {
  f = { move = function() return turtle.forward() end, inspect = function() return turtle.inspect() end,
        dig = function() return turtle.dig() end, attack = function() return turtle.attack() end },
  u = { move = function() return turtle.up() end, inspect = function() return turtle.inspectUp() end,
        dig = function() return turtle.digUp() end, attack = function() return turtle.attackUp() end },
  d = { move = function() return turtle.down() end, inspect = function() return turtle.inspectDown() end,
        dig = function() return turtle.digDown() end, attack = function() return turtle.attackDown() end },
}

function apply(kind)
  if kind == "f" then S.x, S.z = S.x + DX[S.h], S.z + DZ[S.h]
  elseif kind == "u" then S.y = S.y + 1
  else S.y = S.y - 1 end
end

function keepChunk(force)
  if not S.x then return end
  core.chunk.ensure(math.floor(S.x / 16) .. "," .. math.floor(S.z / 16), force)
end

function orderWaiting() return NEWORDER end

-- The target is in a chunk that isn't loaded: wait there. true once moved, false if an order arrives, nil to give up.
local function waitForChunk(kind, op)
  local was, wasMsg = S.status, S.msg
  setStatus("waiting", "Chunk isn't loaded: waiting for it")
  while true do
    keepChunk(true)
    os.sleep(5)
    if orderWaiting() then setStatus(was, wasMsg); return false end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }; save()
    local ok, why = op.move()
    if ok then apply(kind); S.pending = nil; save(); setStatus(was, wasMsg); keepChunk(); return true end
    S.pending = nil
    if not tostring(why):find("loaded world") then setStatus(was, wasMsg); return nil end
  end
end

-- One block of movement, clearing natural blocks. false, why if something he must not dig is in the way.
function move(kind)
  local op = OPS[kind]
  for _ = 1, 40 do
    keepChunk()                                     -- also while stuck retrying: only swaps when due
    if turtle.getFuelLevel() == 0 then return false, "Out of fuel" end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }; save()
    local moved, why = op.move()
    if moved then apply(kind); GP.moves = GP.moves + 1; S.pending = nil; save(); keepChunk(); return true end
    S.pending = nil
    why = tostring(why)
    if why:find("loaded world") then
      local r = waitForChunk(kind, op)
      if r == true then return true elseif r == false then return false, "Order changed" end
    elseif why:find("protected area") or why:find("world border") or why:find("leave the world")
        or why:find("Too high") or why:find("Too low") then
      save(); return false, "Blocked: " .. why
    end
    local ok, d = op.inspect()
    if ok and d.name ~= "minecraft:water" and d.name ~= "minecraft:lava" then
      if not canDig(d.name) then save(); return false, "Blocked by " .. tostring(d.name) end
      op.dig(); dropJunk()
    else
      op.attack()
    end
  end
  save()
  return false, "Stuck"
end

-- A turn is saved before it is made, with what was ahead of him, so a reboot in the middle can be sorted out
local function turn(cmd, step)
  local seen, d = turtle.inspect()
  S.turning = { from = S.h, to = (S.h + step) % 4, ahead = seen and d.name or false }
  save(); cmd(); S.h = S.turning.to; S.turning = nil; save()
end
function turnRight() turn(turtle.turnRight, 1) end
function turnLeft()  turn(turtle.turnLeft, 3) end
function face(h)
  local d = (h - S.h) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end

local function walkX(tx)
  while S.x ~= tx do
    face(tx > S.x and 1 or 3)
    local ok, why = move("f"); if not ok then return false, why end
  end
  return true
end
local function walkZ(tz)
  while S.z ~= tz do
    face(tz > S.z and 2 or 0)
    local ok, why = move("f"); if not ok then return false, why end
  end
  return true
end
function goY(ty)
  while S.y ~= ty do
    local ok, why = move(S.y < ty and "u" or "d"); if not ok then return false, why end
  end
  return true
end

-- To a point: level hops stay level (a layer is flat); otherwise up over everything built, across, down.
-- Blocked sideways: climb a block and try again.
function goTo(tx, ty, tz)
  local ok, why
  if S.y ~= ty then ok, why = goY(math.max(S.y, ty, S.topY + 1)); if not ok then return false, why end end
  for _ = 1, 24 do
    ok, why = walkX(tx)
    if ok then ok, why = walkZ(tz) end
    if ok then return goY(ty) end
    local up, w2 = move("u"); if not up then return false, w2 end
  end
  return false, "Too many obstacles"
end

function atDock() return S.x == 0 and S.y == 0 and S.z == 0 end

-- Further from the dock than he can believe his own position? (an old or foreign save, a lost fix)
FAR_FROM_DOCK = 200
function farFromDock() return not GP.trust and math.abs(S.x or 0) > FAR_FROM_DOCK or math.abs(S.z or 0) > FAR_FROM_DOCK end

-- Idle or stopped, off the dock: go home only if the position can be trusted and someone (an Architect or a
-- build) gave him a reason. Otherwise stay put; too far away means lost.
function idleHome()
  if atDock() then return end
  if farFromDock() then
    S.lost = true; save(); return
  end
  if S.arch or S.build then goHome() end
end

-- Home: the retry-forever version; errors out only on a state he can't fix
function goHome()
  gpsSync(false)                       -- right position before the trip
  local ok, why = goTo(0, 0, 0)
  if not ok then return false, why end
  face(C.dh)
  return true
end

-- Fuel needed for the trip home from here, with a margin
function fuelHome()
  local alt = math.max(S.y, S.topY + 1)
  return math.abs(S.x) + math.abs(S.z) + (alt - S.y) + alt + 80
end

-- Boot: work out whether a move or turn was cut short
function recoverMove()
  if type(S.turning) == "table" then
    -- Did the turn happen? Only the block ahead can tell: a different one means yes, the same means unknown
    local seen, d = turtle.inspect()
    if (seen and d.name or false) ~= S.turning.ahead then S.h = S.turning.to else S.lost = true end
  elseif S.turning then S.lost = true end
  S.turning = nil
  if S.pending then
    local f = turtle.getFuelLevel()
    if type(f) == "number" and type(S.pending.fuel) == "number" then
      if f < S.pending.fuel then apply(S.pending.kind) end
    else
      S.lost = true
    end
    S.pending = nil
  end
end
