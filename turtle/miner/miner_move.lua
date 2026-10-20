-- miner_move.lua  --  moving: one block at a time, never digging a turtle or a cable (he goes round it), and home.
-- A part of miner.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Movement (position is relative to the dock: x/z flat, y up; heading 0 = facing at setup)
---------------------------------------------------------------------------
DX = { [0] = 0, 1, 0, -1 }
DZ = { [0] = -1, 0, 1, 0 }

function apply(kind)
  if kind == "f" then S.x, S.z = S.x + DX[S.h], S.z + DZ[S.h]
  elseif kind == "u" then S.y = S.y + 1
  else S.y = S.y - 1 end
end

OPS = {
  f = { move = turtle.forward, dig = turtle.dig,     detect = turtle.detect,     inspect = turtle.inspect,     attack = turtle.attack },
  u = { move = turtle.up,      dig = turtle.digUp,   detect = turtle.detectUp,   inspect = turtle.inspectUp,   attack = turtle.attackUp },
  d = { move = turtle.down,    dig = turtle.digDown, detect = turtle.detectDown, inspect = turtle.inspectDown, attack = turtle.attackDown },
}

TURTLE_WAIT = 120 -- seconds to wait for another turtle to get out of my way before giving up
CABLE = "Cable in the way" -- move() refused: a protected block (isProtected) is there
CHEST_FULL = "Chest in the way, I'm full" -- move() refused: a chest I couldn't empty all of
-- Defined in the other parts: lootAt(kind) empties the container on that side (false if I'm too full),
-- inArea(x, z) says if a cell is in my chunk area, stash() puts my ore in my shulker box, refreshChunk() keeps
-- my chunk loaded if I carry a chunk controller.

-- Move one block, digging/attacking whatever is in the way (never a turtle or cable: see isProtected).
-- The fuel level before the move is saved, so after a crash we can tell if the move happened.
function move(kind)
  local op = OPS[kind]
  local tries, waitUntil, was, wasMsg = 0, nil, nil, nil
  local function unwait() if was then setStatus(was, wasMsg); was = nil end end
  while tries < 60 do
    tries = tries + 1
    if turtle.getFuelLevel() == 0 then unwait(); return false, "Out of fuel" end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }
    save()
    if op.move() then
      apply(kind)
      S.pending = nil
      save()
      unwait()
      refreshChunk()   -- a new chunk (or time's up): load it before anything else
      return true
    end
    S.pending = nil
    local okI, info = op.inspect()
    if op.detect() and isProtected(okI, info) and not isTurtle(okI, info) then
      -- A cable/pipe/modem/computer: never dig it, the caller goes round it
      unwait(); save(); return false, CABLE
    elseif op.detect() and isTurtle(okI, info) then
      -- Another turtle is in the way: let it pass, don't dig it
      if not waitUntil then
        waitUntil = os.clock() + TURTLE_WAIT
        was, wasMsg = S.status, S.msg
        setStatus("waiting", "Another turtle in my way, letting it pass")
      end
      if os.clock() >= waitUntil then unwait(); save(); return false, "Another turtle in the way" end
      tries = tries - 1 -- waiting doesn't use up the dig attempts
      refreshChunk()
      os.sleep(1)
    elseif op.detect() then
      -- A chest: take everything out first (a dug chest spills its loot on the floor)
      if isLootable(kind, okI, info) and not lootAt(kind) then unwait(); save(); return false, CHEST_FULL end
      local ok, why = op.dig()
      if not ok then
        why = tostring(why)
        if why:find("nbreakable") or why:find("ermission") or why:find("rotect") then unwait(); save(); return false, why end
        if why:lower():find("tool") then unwait(); save(); return false, "No pickaxe equipped" end
      end
    else
      op.attack() -- a mob, or falling sand/gravel mid-air
    end
  end
  unwait()
  save()
  return false, "Stuck"
end

function turnRight()
  S.turning = true; save()
  turtle.turnRight()
  S.h = (S.h + 1) % 4; S.turning = nil; save()
end
function turnLeft()
  S.turning = true; save()
  turtle.turnLeft()
  S.h = (S.h + 3) % 4; S.turning = nil; save()
end
function face(h)
  local d = (h - S.h) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end

-- A cable is right in front of me: pass under it (or over it) and come up 2 blocks further on,
-- at the same height. Never digs the cable. False if there's no way round.
function hopCable()
  for _, v in ipairs({ "d", "u" }) do
    local back = v == "d" and "u" or "d"
    if not isProtected(OPS[v].inspect()) and move(v) then
      if move("f") then
        if move("f") and move(back) then return true end
        return false, "Can't get round a cable"
      end
      move(back) -- the way under (over) is blocked too: back up and try the other side
    end
  end
  return false, "Can't get round a cable"
end

-- A cable is right above/below me (k = "u"/"d"): step to a free side, go 2 blocks up/down, step back.
function climbCable(k)
  for h = 0, 3 do
    face(h)
    if not isProtected(turtle.inspect()) and move("f") then
      if move(k) then
        if move(k) then
          face((h + 2) % 4)
          if move("f") then return true end
        end
        return false, "Can't get round a cable"
      end
      face((h + 2) % 4); move("f")
    end
  end
  return false, "Can't get round a cable"
end

-- Walk to (tx, tz) on the current level, x first (or z first), calling onStep after each block.
-- Cables on the way are hopped (never dug). If (tx, tz) IS a cable, returns false, CABLE (a chest I'm
-- too full to empty: CHEST_FULL; one on the way is hopped too and emptied another time).
function goToXZ(tx, tz, onStep, zFirst, retried)
  local function walk(axis, target, plus, minus)
    while S[axis] ~= target do
      face(target > S[axis] and plus or minus)
      local ok, why = move("f")
      if not ok and (why == CABLE or why == CHEST_FULL) then
        if math.abs(target - S[axis]) == 1 then return false, why end -- that cell is the cable/chest
        ok, why = hopCable()
      end
      if not ok then return false, why end
      if onStep then onStep() end
    end
    return true
  end
  local function walkX() return walk("x", tx, 1, 3) end
  local function walkZ() return walk("z", tz, 2, 0) end
  local a, b = walkX, walkZ
  if zFirst then a, b = walkZ, walkX end
  local ok, why = a()
  if ok then ok, why = b() end
  if not ok and (why == CABLE or why == CHEST_FULL) and not retried then
    -- A cable at a corner: try the other way round (the final cell itself can't be reached)
    return goToXZ(tx, tz, onStep, not zFirst, true)
  end
  return ok, why
end

function goY(ty)
  while S.y ~= ty do
    local k = S.y < ty and "u" or "d"
    local ok, why = move(k)
    if not ok and (why == CABLE or why == CHEST_FULL) then
      if math.abs(ty - S.y) == 1 then return false, why end
      ok, why = climbCable(k)
    end
    if not ok then return false, why end
  end
  return true
end

function atDock() return S.x == 0 and S.y == 0 and S.z == 0 end

-- Carried somewhere (S.offPath): don't walk through whatever is around. Dig down to Y 0
-- (well under the island and the sea floor; in the Nether a few blocks under the dock, above the
-- bedrock floor), tunnel to below the shaft, then come up it.
function tunnelDepth()
  local y = math.min(S.y, -4)
  if S.home and MODE.nether then
    y = math.max(y, NETHER_FLOOR + 1 - S.home.y) -- stay above the bedrock floor
  elseif S.home then
    y = math.min(y, -S.home.y)
    y = math.max(y, (MODE.isEnd and 1 or -60) - S.home.y) -- above bedrock (the End: above the void)
  end
  return y
end

function goHome()
  if S.offPath and (S.x ~= 0 or S.z ~= 0) then
    local ok, why = goY(tunnelDepth())
    if not ok then error("Can't dig down to tunnel home: " .. tostring(why), 0) end
  end
  if S.x ~= 0 or S.z ~= 0 then
    local ok = goToXZ(0, 0)
    if not ok then
      local ok2, why = goToXZ(0, 0, nil, true)
      if not ok2 then error("Can't reach the shaft: " .. tostring(why), 0) end
    end
  end
  local ok, why = goY(0)
  if not ok then error("Shaft blocked: " .. tostring(why), 0) end
  face(0)
  S.offPath = nil
  save()
end

