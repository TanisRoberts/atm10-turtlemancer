-- miner_lava.lua  --  Firecrest's lava: one bucket, hunger, scooping and drinking whole pools.
-- A part of miner.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Lava: the bucket, hunger and drinking
---------------------------------------------------------------------------
function findSlot(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s, d.count end
  end
end
function bucketState()
  if findSlot(BUCKET) then return "empty" end
  if findSlot(LAVA_BUCKET) then return "lava" end
  return "none"
end

-- Under hungryAt % he's hungry until he's back over fullAt % (so one patch of lava fills him up)
function hungry()
  local lim = fuelLimit()
  if lim == math.huge or lim <= 0 then return false end
  local f = fuel() / lim * 100
  if f < (S.hungryAt or HUNGRY_AT) then S.hungry = true
  elseif f >= (S.fullAt or FULL_AT) then S.hungry = nil end
  return S.hungry == true
end

-- Drink every lava bucket he holds (the empty bucket stays with him)
function drinkHeld()
  local s = findSlot(LAVA_BUCKET)
  while s do
    if fuelLimit() - fuel() < 1000 then break end
    local before = fuel()
    if core.fuel.burnSlot(s, fuelLimit()) < 1 then break end
    S.lavaFuel = (S.lavaFuel or 0) + (fuel() - before)
    S.lavaScoops = (S.lavaScoops or 0) + 1
    s = findSlot(LAVA_BUCKET)
  end
  turtle.select(1)
end

PLACE = { f = turtle.place, u = turtle.placeUp, d = turtle.placeDown }
INSPECT = { f = turtle.inspect, u = turtle.inspectUp, d = turtle.inspectDown }
function isLavaSource(ok, d)
  if not ok or type(d) ~= "table" or d.name ~= "minecraft:lava" then return false end
  return not (d.state and tonumber(d.state.level) and tonumber(d.state.level) ~= 0)
end

-- Scoop the lava source on that side and drink it. True if he got some.
function scoop(kind)
  if not isLavaSource(INSPECT[kind]()) then return false end
  local s = findSlot(BUCKET)
  if not s then return false end
  turtle.select(s)
  PLACE[kind]()
  turtle.select(1)
  if not findSlot(LAVA_BUCKET) then return false end
  drinkHeld()
  return true
end


-- Found lava while hungry: drink the whole pool. Walks only into cells he has just scooped, on his
-- own level and inside his rings, and comes back out the way he went in.
function drinkPool()
  local oh, prevSt, prevMsg = S.h, S.status, S.msg
  local seen, steps = { [S.x .. "," .. S.z] = true }, 0
  setStatus(prevSt or "mining", "Drinking a lava pool")
  local function explore()
    scoop("u"); scoop("d")
    local open = {}
    for _ = 1, 4 do
      if not hungry() then break end
      if scoop("f") then
        local nx, nz = S.x + DX[S.h], S.z + DZ[S.h]
        if not seen[nx .. "," .. nz] and inArea(nx, nz) then open[#open + 1] = S.h end
      end
      turnRight()
    end
    for _, h in ipairs(open) do
      if not hungry() or steps >= DRINK_STEPS then return end
      local nx, nz = S.x + DX[h], S.z + DZ[h]
      if not seen[nx .. "," .. nz] then
        seen[nx .. "," .. nz] = true
        face(h)
        if move("f") then
          steps = steps + 1
          explore()
          face((h + 2) % 4)
          local ok, why = move("f")
          if not ok then error("Can't get back out of a lava pool: " .. tostring(why), 0) end
        end
      end
    end
  end
  explore()
  face(oh)
  setStatus(prevSt or "mining", prevMsg)
end

-- Every step: hungry? Then any lava next to him gets drunk, and a pool gets drunk dry. (Firecrest only:
-- Canaries and Starlings carry no bucket and leave lava alone.)
function lookForLava()
  if not MODE.nether or not hungry() then return end
  drinkHeld()
  if not findSlot(BUCKET) then return end
  local got = false
  for _, k in ipairs({ "f", "u", "d" }) do
    if scoop(k) then got = true end
  end
  if got and hungry() then drinkPool() end
end

