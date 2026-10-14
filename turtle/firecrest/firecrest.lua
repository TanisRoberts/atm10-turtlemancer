-- firecrest.lua  --  Nether miner: shaft + expanding squares, drinks lava for fuel (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Canary's cousin for the Nether. Needs: an ADVANCED mining turtle (diamond pickaxe) with an ender
-- modem on its other side, and ONE empty bucket in his inventory (he never lets go of it).
-- Dock: place him where his shaft should start, with ONE barrel next to him (a side or above). The
-- Nether Foreman's computer has that barrel on its wired cable as a Dock: it takes what he brings,
-- sends it home (output barrel -> ender chest) or keeps it in the Nether, and puts in what he asks
-- for (a bucket, fuel). Below him must be free to dig.
--
-- Orders come from the Nether Foreman (layers, rings, START, STOP + DOCK, reboot, retire, his junk
-- list and when to drink lava). His name (Firecrest-01) comes from the Nether Foreman the first time.
--
-- Fuel: an advanced turtle holds 100,000. Once he drops under 25% he scoops every lava source he
-- sees (in front, above, below) with his bucket and drinks it (1,000 each), and when he finds some
-- he drinks the whole pool around him (only the lava cells, on his own level, inside his rings),
-- until he's back over 75%. Then he leaves lava alone. Both numbers are set on the Nether Foreman.
-- No lava for a while and running low: he comes home and asks the dock for fuel.
--
-- Mining is Canary's: a shaft down from the dock to the chosen Y range, then expanding squares,
-- 3 levels per pass (walks the middle, digs ores above/below), ring by ring between the Foreman's
-- "from ring" and "to ring". Keep the rings inside your force-loaded chunks: an unloaded Firecrest
-- just stops until it loads again (he saves his position after every move and carries on).
-- Junk (netherrack, basalt ...) is thrown away underground; the Nether Foreman sends the list.
-- Hold Ctrl+T to stop the program (the turtle stays where it is).

local PROTOCOL     = "tanis-nether"
local STATE_FILE   = "firecrest.state"
local DEFAULT_R2   = 24     -- outer ring when the Foreman doesn't say (24 rings = 49x49, about 3x3 chunks)
local RING_CAP     = 100    -- furthest ring allowed (201x201): keep it inside the force-loaded chunks
local FUEL_RESERVE = 200    -- spare fuel kept on top of the trip home
local STATUS_EVERY = 3      -- seconds between status broadcasts
local NETHER_FLOOR = 5      -- lowest Y he mines (bedrock below)
local HUNGRY_AT    = 25     -- % of the tank: start drinking lava (the Foreman can change these)
local FULL_AT      = 75     -- % of the tank: stop drinking
local DRINK_STEPS  = 48     -- most cells he walks into while drinking one pool
local BUCKET, LAVA_BUCKET = "minecraft:bucket", "minecraft:lava_bucket"

-- Junk he may throw away underground. The Nether Foreman sends his real list; this is the fallback.
local DEFAULT_JUNK = { "netherrack", "blackstone", "basalt", "smooth_basalt", "soul_sand", "soul_soil",
  "magma_block", "gravel", "crimson_nylium", "warped_nylium", "nether_wart_block", "warped_wart_block",
  "cobblestone", "cobbled_deepslate", "polished_blackstone_bricks" }
local JUNK, KEEP = {}, {}
local function setJunk(list)
  local junk = {}
  for _, item in ipairs(list or DEFAULT_JUNK) do
    if type(item) == "string" and item ~= "" then
      if not item:find(":") then item = "minecraft:" .. item end
      junk[item] = true
    end
  end
  junk[BUCKET], junk[LAVA_BUCKET] = nil, nil   -- never junk
  JUNK = junk
end
setJunk(nil)

---------------------------------------------------------------------------
-- State (saved to disk after every move)
---------------------------------------------------------------------------
local S = {}
local function save()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize(S))
  f.close()
end
local function load()
  if not fs.exists(STATE_FILE) then return end
  local f = fs.open(STATE_FILE, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  if type(t) == "table" then S = t end
end

local ctrl = nil -- latest command from the panel (set by the network loop)

local function fuel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end
local function fuelLimit()
  local l = turtle.getFuelLimit()
  return l == "unlimited" and math.huge or l
end

local lastShown = ""
local function setStatus(st, msg)
  S.status, S.msg = st, msg or ""
  local line = st .. (S.msg ~= "" and (": " .. S.msg) or "")
  if line ~= lastShown then
    lastShown = line
    print(("[%s] %s"):format(textutils.formatTime(os.time(), true), line))
    if S.dockY then save() end
  end
end

---------------------------------------------------------------------------
-- Where am I: S.x/y/z are relative to the dock (heading 0 = the way it faced at setup).
-- S.home = the dock's world X/Y/Z, S.facing = compass direction of heading 0 (0 N, 1 E, 2 S, 3 W).
---------------------------------------------------------------------------
local COMPASS = { [0] = "north", "east", "south", "west" }

-- Rotate a flat offset by f quarter turns clockwise (north -> east)
local function rot(x, z, f)
  for _ = 1, f % 4 do x, z = -z, x end
  return x, z
end

local function absPos()
  if not (S.home and S.facing) then return nil end
  local ax, az = rot(S.x, S.z, S.facing)
  return S.home.x + ax, S.home.y + S.y, S.home.z + az
end

local function setFromAbs(x, y, z)
  local rx, rz = rot(x - S.home.x, z - S.home.z, 4 - S.facing)
  S.x, S.y, S.z = rx, y - S.home.y, rz
end

local gpsSeen = false
local function locate()
  if not gps then return nil end
  local ok, x, y, z = pcall(gps.locate, 2)
  if ok and x then
    gpsSeen = true
    return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
  end
end

local function dirOf(dx, dz)
  if dz < 0 then return 0 elseif dx > 0 then return 1 elseif dz > 0 then return 2 elseif dx < 0 then return 3 end
end

-- Is this block a turtle or computer? ComputerCraft lets a turtle mine another turtle (it ends up
-- as an item in the canary's bag), so another Canary crossing my tunnel or shaft is never dug:
-- I wait for it to move on instead.
local function isMachine(ok, d)
  return ok == true and type(d) == "table" and type(d.name) == "string" and d.name:find("^computercraft:") ~= nil
end

-- Which way am I facing? Step one block (turning to find a free side), ask GPS, step back.
-- allowDig: may dig the block in front (only underground).
-- Returns the compass direction it now faces (or nil), how many right turns it made looking, and
-- true if it couldn't step back (it's then one block further on, in the direction it faces).
local function compassByStep(allowDig)
  local x0, _, z0 = locate()
  if not x0 then return nil, 0 end
  for turns = 0, 3 do
    local moved = false
    if not turtle.detect() then moved = turtle.forward()
    elseif allowDig and not isMachine(turtle.inspect()) and turtle.dig() then moved = turtle.forward() end
    if moved then
      local x1, _, z1 = locate()
      local stuck = not turtle.back()
      if stuck and allowDig then
        -- Something fell in behind: turn round, clear it, step back, turn round again
        turtle.turnRight(); turtle.turnRight()
        if not isMachine(turtle.inspect()) then turtle.dig() end
        stuck = not turtle.forward()
        turtle.turnRight(); turtle.turnRight()
      end
      if x1 and (x1 ~= x0 or z1 ~= z0) then return dirOf(x1 - x0, z1 - z0), turns, stuck end
      return nil, turns, stuck
    end
    turtle.turnRight()
  end
  return nil, 4
end

---------------------------------------------------------------------------
-- Movement (position is relative to the dock: x/z flat, y up; heading 0 = facing at setup)
---------------------------------------------------------------------------
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }

local function apply(kind)
  if kind == "f" then S.x, S.z = S.x + DX[S.h], S.z + DZ[S.h]
  elseif kind == "u" then S.y = S.y + 1
  else S.y = S.y - 1 end
end

local OPS = {
  f = { move = turtle.forward, dig = turtle.dig,     detect = turtle.detect,     inspect = turtle.inspect,     attack = turtle.attack },
  u = { move = turtle.up,      dig = turtle.digUp,   detect = turtle.detectUp,   inspect = turtle.inspectUp,   attack = turtle.attackUp },
  d = { move = turtle.down,    dig = turtle.digDown, detect = turtle.detectDown, inspect = turtle.inspectDown, attack = turtle.attackDown },
}

local TURTLE_WAIT = 120 -- seconds to wait for another turtle to get out of my way before giving up

-- Move one block, digging/attacking whatever is in the way (never another turtle: see isMachine).
-- The fuel level before the move is saved, so after a crash we can tell if the move happened.
local function move(kind)
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
      return true
    end
    S.pending = nil
    if op.detect() and isMachine(op.inspect()) then
      -- Another turtle (or a computer) is in the way: let it pass, don't dig it
      if not waitUntil then
        waitUntil = os.clock() + TURTLE_WAIT
        was, wasMsg = S.status, S.msg
        setStatus("waiting", "Another turtle in my way, letting it pass")
      end
      if os.clock() >= waitUntil then unwait(); save(); return false, "Another turtle in the way" end
      tries = tries - 1 -- waiting doesn't use up the dig attempts
      os.sleep(1)
    elseif op.detect() then
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

local function turnRight()
  S.turning = true; save()
  turtle.turnRight()
  S.h = (S.h + 1) % 4; S.turning = nil; save()
end
local function turnLeft()
  S.turning = true; save()
  turtle.turnLeft()
  S.h = (S.h + 3) % 4; S.turning = nil; save()
end
local function face(h)
  local d = (h - S.h) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end

-- Walk to (tx, tz) on the current level, x first (or z first), calling onStep after each block.
local function goToXZ(tx, tz, onStep, zFirst)
  local function walkX()
    while S.x ~= tx do
      face(tx > S.x and 1 or 3)
      local ok, why = move("f"); if not ok then return false, why end
      if onStep then onStep() end
    end
    return true
  end
  local function walkZ()
    while S.z ~= tz do
      face(tz > S.z and 2 or 0)
      local ok, why = move("f"); if not ok then return false, why end
      if onStep then onStep() end
    end
    return true
  end
  local a, b = walkX, walkZ
  if zFirst then a, b = walkZ, walkX end
  local ok, why = a(); if not ok then return false, why end
  return b()
end

local function goY(ty)
  while S.y ~= ty do
    local ok, why = move(S.y < ty and "u" or "d")
    if not ok then return false, why end
  end
  return true
end

local function atDock() return S.x == 0 and S.y == 0 and S.z == 0 end

-- Carried somewhere (S.offPath): don't walk through whatever is around. Dig down
-- (a few blocks under the dock, above the bedrock floor), tunnel to below the shaft, come up it.
local function tunnelDepth()
  local y = math.min(S.y, -4)
  if S.home then y = math.max(y, NETHER_FLOOR + 1 - S.home.y) end -- stay above the bedrock floor
  return y
end

local function goHome()
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

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------
local function emptySlots()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end
  return n
end

local function dropAway()
  if not turtle.detectDown() then return turtle.dropDown() end
  if not turtle.detectUp() then return turtle.dropUp() end
  return turtle.drop()
end

-- Dump junk that storage already has plenty of (or all junk, if `all`)
local function dumpJunk(all)
  local capped = S.capped or {}
  if not all and not next(capped) then return end
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and JUNK[d.name] and (all or capped[d.name]) then
      turtle.select(s); dropAway()
    end
  end
  turtle.select(1)
end

-- Valuable = an ore product worth a trip home. Everything else can be dumped to make room.
local VALUE_TAGS = { "c:ores", "c:raw_materials", "c:gems", "c:dusts", "c:nuggets", "c:ingots",
  "minecraft:coals", "c:coal" }
-- "computercraft:" = a turtle/computer picked up by an older Canary: always brought home, never dumped
local VALUE_NAMES = { "computercraft:", "raw_", "_ore", "diamond", "emerald", "lapis", "redstone", "coal", "quartz",
  "amethyst_shard", "ancient_debris", "netherite", "nugget", "ingot", "gem", "crystal", "dust", "gilded",
  "glowstone", "shroomlight" }
local valuableCache = {}
local function isValuable(slot)
  local d = turtle.getItemDetail(slot)
  if not d then return false end
  local v = valuableCache[d.name]
  if v ~= nil then return v end
  if KEEP[d.name] or d.name == BUCKET or d.name == LAVA_BUCKET then valuableCache[d.name] = true; return true end
  v = false
  local full = turtle.getItemDetail(slot, true)
  for _, t in ipairs(VALUE_TAGS) do if full and full.tags and full.tags[t] then v = true end end
  if not v and not JUNK[d.name] then
    for _, p in ipairs(VALUE_NAMES) do if d.name:find(p, 1, true) then v = true; break end end
  end
  valuableCache[d.name] = v
  return v
end

-- When slots run out: dump everything that isn't valuable, except up to KEEP_JUNK_SLOTS of
-- junk that storage still wants (under its 20-stack cap), fullest stacks first.
local KEEP_JUNK_SLOTS = 4
local function makeRoom()
  local capped, keep = S.capped or {}, {}
  local wanted = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and JUNK[d.name] and not capped[d.name] then wanted[#wanted + 1] = { s = s, n = d.count } end
  end
  table.sort(wanted, function(a, b) return a.n > b.n end)
  for i = 1, math.min(KEEP_JUNK_SLOTS, #wanted) do keep[wanted[i].s] = true end
  for s = 1, 16 do
    if turtle.getItemCount(s) > 0 and not keep[s] and not isValuable(s) then
      turtle.select(s); dropAway()
    end
  end
  turtle.select(1)
end

local function cargoFraction()
  local used, room = 0, 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      used = used + d.count
      room = room + d.count + turtle.getItemSpace(s)
    end
  end
  return room > 0 and used / room or 0
end

local function burnInventoryFuel(target)
  for s = 1, 16 do
    if fuel() >= target then break end
    local d = turtle.getItemDetail(s)
    if d and not JUNK[d.name] then
      turtle.select(s)
      if turtle.refuel(0) then turtle.refuel() end
    end
  end
  turtle.select(1)
end

local function dropTo(dir, n)
  if dir == "up" then return turtle.dropUp(n) end
  face(dir); return turtle.drop(n)
end
local function suckFrom(dir, n)
  if dir == "up" then return turtle.suckUp(n) end
  face(dir); return turtle.suck(n)
end

local function isOre(ok, d)
  if not ok or type(d) ~= "table" then return false end
  if d.tags and (d.tags["c:ores"] or d.tags["forge:ores"]) then return true end
  local n = d.name or ""
  return n:find("_ore$") ~= nil or n:find(":ore_") ~= nil or n == "minecraft:ancient_debris"
    or n == "minecraft:gilded_blackstone"
end

---------------------------------------------------------------------------
-- Lava: the bucket, hunger and drinking
---------------------------------------------------------------------------
local function findSlot(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s, d.count end
  end
end
local function bucketState()
  if findSlot(BUCKET) then return "empty" end
  if findSlot(LAVA_BUCKET) then return "lava" end
  return "none"
end

-- Under hungryAt % he's hungry until he's back over fullAt % (so one patch of lava fills him up)
local function hungry()
  local lim = fuelLimit()
  if lim == math.huge or lim <= 0 then return false end
  local f = fuel() / lim * 100
  if f < (S.hungryAt or HUNGRY_AT) then S.hungry = true
  elseif f >= (S.fullAt or FULL_AT) then S.hungry = nil end
  return S.hungry == true
end

-- Drink every lava bucket he holds (the empty bucket stays with him)
local function drinkHeld()
  local s = findSlot(LAVA_BUCKET)
  while s do
    if fuelLimit() - fuel() < 1000 then break end
    turtle.select(s)
    local before = fuel()
    if not turtle.refuel() then break end
    S.lavaFuel = (S.lavaFuel or 0) + (fuel() - before)
    S.lavaScoops = (S.lavaScoops or 0) + 1
    s = findSlot(LAVA_BUCKET)
  end
  turtle.select(1)
end

local PLACE   = { f = turtle.place, u = turtle.placeUp, d = turtle.placeDown }
local INSPECT = { f = turtle.inspect, u = turtle.inspectUp, d = turtle.inspectDown }
local function isLavaSource(ok, d)
  if not ok or type(d) ~= "table" or d.name ~= "minecraft:lava" then return false end
  return not (d.state and tonumber(d.state.level) and tonumber(d.state.level) ~= 0)
end

-- Scoop the lava source on that side and drink it. True if he got some.
local function scoop(kind)
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

local function inRings(x, z)
  local r = S.r2 or DEFAULT_R2
  return math.abs(x) <= r and math.abs(z) <= r
end

-- Found lava while hungry: drink the whole pool. Walks only into cells he has just scooped, on his
-- own level and inside his rings, and comes back out the way he went in.
local function drinkPool()
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
        if not seen[nx .. "," .. nz] and inRings(nx, nz) then open[#open + 1] = S.h end
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

-- Every step: hungry? Then any lava next to him gets drunk, and a pool gets drunk dry.
local function lookForLava()
  if not hungry() then return end
  drinkHeld()
  if not findSlot(BUCKET) then return end
  local got = false
  for _, k in ipairs({ "f", "u", "d" }) do
    if scoop(k) then got = true end
  end
  if got and hungry() then drinkPool() end
end

local function checkUpDown()
  if isOre(turtle.inspectUp()) then turtle.digUp(); S.ores = (S.ores or 0) + 1 end
  if isOre(turtle.inspectDown()) then turtle.digDown(); S.ores = (S.ores or 0) + 1 end
  lookForLava()
end

---------------------------------------------------------------------------
-- Commands from the panel
---------------------------------------------------------------------------
local function applyCtrl()
  if not ctrl or ctrl.seq == nil then return end
  if (ctrl.retired == true) ~= (S.retired == true) then S.retired = ctrl.retired == true or nil; save() end
  if ctrl.seq == S.seq then return end
  S.seq = ctrl.seq
  if ctrl.want == "run" then
    local r1 = math.max(1, math.min(RING_CAP, math.floor(tonumber(ctrl.r1) or 1)))
    local r2 = math.max(r1, math.min(RING_CAP, math.floor(tonumber(ctrl.r2) or DEFAULT_R2)))
    local changed = ctrl.minY ~= S.minY or ctrl.maxY ~= S.maxY or r1 ~= (S.r1 or 1) or r2 ~= (S.r2 or DEFAULT_R2)
    if changed or S.done then
      S.layerIdx, S.k, S.step, S.done, S.probedLayer = 1, r1, 1, false, nil
      if changed and S.want == "run" then S.regionChanged = true end
    end
    S.minY, S.maxY, S.r1, S.r2, S.want = ctrl.minY, ctrl.maxY, r1, r2, "run"
  else
    S.want = "dock"
  end
  save()
end

local function abort(reason, msg) error({ abort = reason, msg = msg }, 0) end

-- Reboot asked for by the Foreman (ctrl.reboot = a fresh token per press). Only called at safe
-- points: between blocks or while idle, so nothing is half-done and the state on disk is exact.
-- The token is saved first, so the same request never reboots it twice.
local function maybeReboot()
  if not (ctrl and ctrl.reboot and ctrl.reboot ~= S.rebootDone) then return end
  S.rebootDone = ctrl.reboot
  setStatus("rebooting", "Rebooting, back in a moment")
  save()
  os.sleep(STATUS_EVERY + 0.5) -- let the network loop tell the Foreman
  os.reboot()
end

-- Called before every block of mining
local function checkpoint()
  applyCtrl()
  maybeReboot()
  if S.want ~= "run" then abort("stop", "Stop requested") end
  if S.regionChanged then S.regionChanged = nil; abort("region") end
  dumpJunk(true)   -- the Nether Foreman's junk list: thrown away, never carried home
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

local function waitCtrl(seconds)
  local t = os.clock() + seconds
  while os.clock() < t do
    if ctrl and ctrl.seq ~= S.seq then return end
    maybeReboot()
    os.sleep(1)
  end
end

---------------------------------------------------------------------------
-- Mining plan
---------------------------------------------------------------------------
-- Layer centres (absolute Y). Each pass covers centre-1 .. centre+1.
local function layerList()
  local out = {}
  if not S.minY or not S.maxY then return out end
  local c = math.min(S.maxY - 1, S.dockY - 3)
  while c + 1 >= S.minY and c - 1 >= NETHER_FLOOR do
    out[#out + 1] = c
    c = c - 3
  end
  return out
end

local function ringCells(k)
  local c = {}
  for z = -k, k do c[#c + 1] = { k, z } end
  for x = k - 1, -k, -1 do c[#c + 1] = { x, k } end
  for z = k - 1, -k, -1 do c[#c + 1] = { -k, z } end
  for x = -k + 1, k - 1 do c[#c + 1] = { x, -k } end
  return c
end

local function fuelToStart()
  local layers = layerList()
  local y = layers[S.layerIdx or 1] or layers[1] or S.dockY
  return 2 * (S.dockY - y) + 4 * (S.k or 1) + 500
end

-- A fresh level: how far out is it already mined? From the shaft, walk each way (N, E, S, W)
-- through open space only (air: lava and anything else counts as unmined), stop at the first block
-- (or at the outer ring), walk back.
-- After the first direction, the others only go as far as the shortest so far.
-- Returns the shortest open run: rings 1..n are already open in every direction.
local function probeMined(r2)
  if S.x ~= 0 or S.z ~= 0 then
    local ok, why = goToXZ(0, 0)
    if not ok then error("Can't reach the shaft: " .. tostring(why), 0) end
  end
  local best = r2
  for h = 0, 3 do
    if best == 0 then break end
    face(h)
    local n = 0
    while n < best do
      checkpoint()
      local okI, dI = turtle.inspect()
      if okI and dI.name ~= "minecraft:air" and dI.name ~= "minecraft:cave_air" then break end
      if turtle.detect() or not move("f") then break end
      n = n + 1
    end
    best = math.min(best, n)
    if S.x ~= 0 or S.z ~= 0 then
      local ok, why = goToXZ(0, 0)
      if not ok then error("Can't get back to the shaft: " .. tostring(why), 0) end
    end
  end
  return best
end

local function mineRegion()
  local layers = layerList()
  S.layerCount = #layers
  if #layers == 0 then
    S.done = true; save()
    setStatus("error", "Range must be below the dock")
    return
  end
  for li = S.layerIdx or 1, #layers do
    S.layerIdx, S.layerY = li, layers[li]
    local cy = layers[li] - S.dockY
    setStatus("mining", ("Y %d"):format(layers[li]))
    -- Travel to the layer via the shaft
    if S.y ~= cy then
      if S.x ~= 0 or S.z ~= 0 then
        local ok, why = goToXZ(0, 0)
        if not ok then error("Can't reach the shaft: " .. tostring(why), 0) end
      end
      while S.y ~= cy do
        checkpoint()
        local ok, why = move(S.y > cy and "d" or "u")
        if not ok then error("Shaft blocked at Y " .. (S.dockY + S.y) .. ": " .. tostring(why), 0) end
        lookForLava()   -- the shaft often goes through the lava sea
      end
    end
    -- Expanding squares
    local blocked = false
    local r1, r2 = S.r1 or 1, S.r2 or DEFAULT_R2
    -- New level (not resuming partway through it): skip the rings that are already mined out
    if S.probedLayer ~= li then
      if (S.k or r1) <= r1 and (S.step or 1) == 1 then
        setStatus("mining", ("Y %d: checking how far it's mined"):format(layers[li]))
        local open = probeMined(r2)
        if open >= r2 then
          S.probeNote = ("Y %d: mined out to ring %d, next level"):format(layers[li], r2)
        elseif open + 1 > r1 then
          S.probeNote = ("Y %d: mined to ring %d, starting at %d"):format(layers[li], open, open + 1)
        else
          S.probeNote = nil
        end
        S.k, S.step = math.max(r1, open + 1), 1
        if S.probeNote then setStatus("mining", S.probeNote) end
      end
      S.probedLayer = li
      save()
    end
    for k = math.max(S.k or r1, r1), r2 do
      S.k = k
      local cells = ringCells(k)
      for i = S.step or 1, #cells do
        S.step = i
        checkpoint()
        local ok = goToXZ(cells[i][1], cells[i][2], checkUpDown)
        if not ok then blocked = true; break end
      end
      if blocked then break end
      S.step = 1
    end
    if blocked then setStatus("mining", ("Hit unbreakable blocks at Y %d, next layer"):format(layers[li])) end
    S.k, S.step = S.r1 or 1, 1
    S.layerIdx = li + 1
    save()
  end
  S.done = true
  save()
end

---------------------------------------------------------------------------
-- Dock: one barrel. He empties everything into it (except his bucket); the Nether Foreman takes it
-- away. If he needs a bucket or fuel he asks, the Foreman puts it in the barrel, he takes it.
---------------------------------------------------------------------------
local dockReply = nil   -- latest dock_ready for me (set by the network loop)

local function askDock(needBucket, wantFuel)
  if not rednet.isOpen() then return nil end
  local me, seq = os.getComputerID(), os.epoch("utc")
  dockReply = nil
  local deadline, nextSend = os.clock() + 30, 0
  while os.clock() < deadline do
    if os.clock() >= nextSend then
      rednet.broadcast({ type = "dock_req", id = me, seq = seq, bucket = needBucket, fuel = wantFuel }, PROTOCOL)
      nextSend = os.clock() + 5
    end
    if dockReply and dockReply.seq == seq then return dockReply end
    os.sleep(0.5)
  end
end

-- Empty everything into the dock but one bucket. False if the barrel wouldn't take it all.
local function unloadAll()
  local keepSlot = findSlot(BUCKET) or findSlot(LAVA_BUCKET)
  local haul = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      local keep = (s == keepSlot) and 1 or 0
      if d.count > keep then
        turtle.select(s)
        if not JUNK[d.name] and d.name ~= BUCKET and d.name ~= LAVA_BUCKET then
          haul[d.name] = (haul[d.name] or 0) + d.count
        end
        local tries = 0
        while turtle.getItemCount(s) > keep do
          if not dropTo(S.dockDir, turtle.getItemCount(s) - keep) then
            tries = tries + 1
            setStatus("waiting", "Dock barrel full, waiting")
            os.sleep(3)
            if tries > 10 then break end -- give up for now; the main loop waits at the dock
          end
        end
      end
    end
  end
  turtle.select(1)
  if next(haul) then
    S.lastHaul = haul
    S.totals = S.totals or {}
    for n, c in pairs(haul) do S.totals[n] = (S.totals[n] or 0) + c end
  end
  for s = 1, 16 do
    local c = turtle.getItemCount(s)
    if c > ((s == keepSlot) and 1 or 0) then return false end
  end
  return true
end

-- Take what the Foreman put in the dock: burn the fuel (as much as fits), keep one bucket, hand
-- the rest back (spare buckets, leftover coal) for the Nether stock.
local function takeSupplies()
  for _ = 1, 16 do
    local free = nil
    for s = 1, 16 do if turtle.getItemCount(s) == 0 then free = s; break end end
    if not free then break end
    turtle.select(free)
    if not suckFrom(S.dockDir) then break end
  end
  drinkHeld()
  local limit = fuelLimit()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name ~= BUCKET and d.name ~= LAVA_BUCKET then
      turtle.select(s)
      if limit ~= math.huge and turtle.refuel(0) then
        local before = fuel()
        turtle.refuel(1)
        local per = fuel() - before
        if per > 0 then
          local n = math.floor((limit - fuel()) / per)
          if n > 0 then turtle.refuel(math.min(n, turtle.getItemCount(s))) end
        end
      end
    end
  end
  turtle.select(1)
  local ok = unloadAll()
  face(0)
  if rednet.isOpen() then rednet.broadcast({ type = "dock_done", id = os.getComputerID() }, PROTOCOL) end
  return ok
end

local function dockService(needStart)
  setStatus("docked", "Unloading")
  if gpsSeen then
    local x, y, z = locate()
    local ex, ey, ez = absPos()
    if x and ex and (x ~= ex or y ~= ey or z ~= ez) then
      print(("GPS says %d %d %d, I counted %d %d %d. Trusting GPS."):format(x, y, z, ex, ey, ez))
      S.home = { x = x - (ex - S.home.x), y = y - (ey - S.home.y), z = z - (ez - S.home.z) }
      S.dockY = S.home.y
    end
  end
  valuableCache = {}
  drinkHeld()
  dumpJunk(true)   -- junk picked up on the way home goes down the shaft, not into the dock
  S.ores = 0
  if not unloadAll() then face(0); save(); return false end

  local limit = fuelLimit()
  local needBucket = bucketState() == "none"
  local wantFuel = 0
  -- Only before heading out (needStart given): while he just sits docked he doesn't pester the dock
  if needStart and limit ~= math.huge and (fuel() < needStart or hungry()) then
    wantFuel = math.max(needStart or 0, math.floor(limit * (S.fullAt or FULL_AT) / 100)) - fuel()
  end
  if needStart and (needBucket or wantFuel > 0) then
    setStatus("docked", needBucket and "Asking the dock for a bucket" or "Asking the dock for fuel")
    local r = askDock(needBucket, wantFuel)
    if r then
      takeSupplies()
      S.dockNote = r.note
    else
      S.dockNote = "The Nether Foreman didn't answer"
    end
  elseif needStart then
    S.dockNote = nil
  end
  face(0)
  save()
  return true
end

---------------------------------------------------------------------------
-- First-time setup at the dock
---------------------------------------------------------------------------
local function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = d.name or ""
  return n:find("barrel") or n:find("chest") or (d.tags and (d.tags["c:barrels"] or d.tags["c:chests"]))
end

local function sideName(dir)
  if dir == "up" then return "above me" end
  return ({ [0] = "in front", "on my right", "behind me", "on my left" })[dir]
end

local function title(text)
  if term.isColour() then term.setTextColour(colours.cyan) end
  print(text)
  term.setTextColour(colours.white)
end

local function askNumber(prompt)
  while true do
    write(prompt)
    local n = tonumber(read())
    if n then return math.floor(n) end
    printError("A number, please.")
  end
end

local function askChoice(prompt, options)
  while true do
    for i, o in ipairs(options) do print(("  %d) %s"):format(i, o)) end
    write(prompt)
    local a = read()
    local n = tonumber(a)
    if n and options[n] then return n end
    for i, o in ipairs(options) do if a ~= "" and o:lower():sub(1, #a) == a:lower() then return i end end
    printError("Pick one of the numbers.")
  end
end

local function askFacing()
  print("Which way am I facing? (stand behind me, look the same")
  print("way, read 'Facing' on F3)")
  return askChoice("Facing: ", { "North", "East", "South", "West" }) - 1
end

local function askDimension()
  local d = askChoice("Dimension [1]: ", { "Overworld", "Nether", "End", "Other" })
  if d == 4 then write("Its name: "); return read() end
  return ({ "overworld", "the_nether", "the_end" })[d]
end

local function setupDock()
  term.clear(); term.setCursorPos(1, 1)
  title("FIRECREST SETUP")
  print("I sit on top of my future shaft.")
  print("I need ONE barrel next to me (a side")
  print("or above): my dock, a Dock on the")
  print("Nether Foreman's cable. And one empty")
  print("bucket in my inventory, for lava.")
  print()
  S = { x = 0, y = 0, z = 0, h = 0, want = "dock", seq = nil }
  local x, y, z = locate()
  if x then
    print(("GPS says I'm at %d %d %d."):format(x, y, z))
    S.home = { x = x, y = y, z = z }
    local c, _, stuck = compassByStep(false)
    S.facing = c
    if stuck then apply("f") end -- couldn't step back onto the dock; goHome fixes it later
    if S.facing then print("I'm facing " .. COMPASS[S.facing] .. ".") else S.facing = askFacing() end
  else
    print("No GPS here. Type my position")
    print("(F3, the block I'm in):")
    local hx = askNumber("X: ")
    local hy = askNumber("Y: ")
    local hz = askNumber("Z: ")
    S.home = { x = hx, y = hy, z = hz }
    S.facing = askFacing()
  end
  S.dockY = S.home.y
  S.dim = "the_nether"
  save()
  while true do
    local found = {}
    for _ = 0, 3 do
      if isContainer(turtle.inspect()) then found[#found + 1] = S.h end
      turnRight()
    end
    if isContainer(turtle.inspectUp()) then found[#found + 1] = "up" end
    face(0)
    if #found == 1 then
      S.dockDir = found[1]
      print(("Dock barrel: %s."):format(sideName(S.dockDir)))
      break
    end
    printError(#found == 0 and "No barrel next to me." or ("%d barrels here: I need just one."):format(#found))
    print("Fix that, then press Enter.")
    read()
  end
  if bucketState() == "none" then
    printError("No bucket on me: put an empty bucket")
    print("in me, or in a Nether stock barrel.")
  end
  save()
  print("Setup done. The Nether Foreman gives")
  print("me a number; pick my layers and press")
  print("START there.")
end

local function recover()
  if S.turning then S.lost = true; S.turning = nil end
  if S.pending then
    local f = turtle.getFuelLevel()
    if type(f) == "number" and type(S.pending.fuel) == "number" then
      if f < S.pending.fuel then apply(S.pending.kind) end
    else
      S.lost = true
    end
    S.pending = nil
  end
  save()
end

local function lostFlow()
  setStatus("lost", "Carry me back to the dock")
  print("I lost track of which way I'm facing (unloaded mid-turn).")
  print(("Put me back on the dock with the barrel %s,"):format(sideName(S.dockDir)))
  print("then press Enter here.")
  read()
  S.x, S.y, S.z, S.h, S.lost = 0, 0, 0, 0, nil
  S.k, S.step = S.r1 or 1, 1
  save()
end

-- Check my counted position against GPS. If I've been carried off, re-learn where I am and
-- which way I face, then wait for an order before going anywhere.
local function checkPosition()
  if not (S.home and S.facing) then return end
  local x, y, z = locate()
  if not x then return end
  local ex, ey, ez = absPos()
  local moved = x ~= ex or y ~= ey or z ~= ez
  if moved then
    setFromAbs(x, y, z)
    S.lost, S.offPath, S.heldSeq = true, true, S.seq
  end
  if S.lost then
    save()
    local c = compassByStep(not S.offPath and S.y <= -2)
    if c then
      S.h, S.lost = (c - S.facing) % 4, nil
      local x2, y2, z2 = locate()
      if x2 then setFromAbs(x2, y2, z2) end
    end
  end
  save()
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local function safeHome()
  local ok, err = pcall(goHome)
  if not ok then setStatus("error", tostring(err)); save() end
  return ok
end

local function runOnce()
  if atDock() then
    local need = fuelToStart()
    if not dockService(need) then
      setStatus("waiting", "Dock barrel full. Is the Nether Foreman running?")
      waitCtrl(15)
      return
    end
    if bucketState() == "none" then
      setStatus("waiting", "No bucket: put an empty bucket in a Nether stock barrel")
      waitCtrl(15)
      return
    end
    if fuel() < need then
      setStatus("waiting", ("Need %d fuel, have %d: lava buckets in a stock barrel"):format(need, fuel()))
      waitCtrl(15)
      return
    end
  end
  setStatus("mining", "")
  local ok, err = pcall(mineRegion)
  if ok then return end
  if type(err) == "table" and err.abort then
    if err.abort == "region" then return end
    setStatus("returning", err.msg or "")
    safeHome()
  else
    setStatus("error", tostring(err)); save()
    safeHome()
    waitCtrl(30)
  end
end

local function mainLoop()
  checkPosition()
  while true do
    applyCtrl()
    maybeReboot()
    if S.lost and gpsSeen then
      checkPosition()
      if S.lost then
        setStatus("lost", "Can't tell which way I face: no free side to step into")
        waitCtrl(30)
      end
    elseif S.lost then
      lostFlow()
    elseif S.offPath and S.seq == S.heldSeq then
      setStatus("waiting", "Moved by hand. START or DOCK on the Foreman to send me home")
      waitCtrl(10)
    elseif S.offPath then
      setStatus("returning", "Tunnelling back to my shaft")
      safeHome()
      if not atDock() then waitCtrl(30) end
    elseif S.retired then
      if not atDock() then setStatus("returning", "Retiring: heading home"); safeHome() end
      if atDock() then dockService(nil); setStatus("retired", "Retired. Thanks for your service") end
      waitCtrl(30)
    elseif S.want ~= "run" or S.done then
      if not atDock() then setStatus("returning", "Heading home"); safeHome() end
      if atDock() then
        dockService(nil)
        setStatus("docked", S.done and "Range finished. Pick a new one." or "Waiting for START")
      end
      waitCtrl(10)
    else
      runOnce()
    end
  end
end

---------------------------------------------------------------------------
-- Network: status out, commands in
---------------------------------------------------------------------------
local function statusMsg()
  local used = 16 - emptySlots()
  local haul = {}
  for n, c in pairs(S.lastHaul or {}) do haul[#haul + 1] = { n, c } end
  table.sort(haul, function(a, b) return a[2] > b[2] end)
  while #haul > 8 do table.remove(haul) end
  local f, l = turtle.getFuelLevel(), turtle.getFuelLimit()
  local px, py, pz = absPos()
  return {
    type = "status", id = os.getComputerID(), label = os.getComputerLabel(), num = S.num,
    pos = px and { x = px, y = py, z = pz } or nil, dim = S.dim, home = S.home,
    facing = S.facing and COMPASS[(S.facing + (S.h or 0)) % 4], gps = gpsSeen,
    offPath = S.offPath, retired = S.retired,
    state = S.status, msg = S.msg, seq = S.seq, kind = "firecrest",
    fuel = f, fuelLimit = l, slots = used,
    hungry = S.hungry == true, hungryAt = S.hungryAt or HUNGRY_AT, fullAt = S.fullAt or FULL_AT,
    bucket = bucketState(), lavaFuel = S.lavaFuel or 0, lavaScoops = S.lavaScoops or 0, dockNote = S.dockNote,
    y = S.dockY and (S.dockY + (S.y or 0)), x = S.x, z = S.z,
    layer = S.layerIdx, layers = S.layerCount, ring = S.k, minRing = S.r1 or 1, maxRing = S.r2 or DEFAULT_R2,
    minY = S.minY, maxY = S.maxY, want = S.want, rebootDone = S.rebootDone, done = S.done, ores = S.ores, haul = haul,
  }
end

local function labelNum()
  return tonumber(((os.getComputerLabel() or ""):match("^[Ff]irecrest%-(%d+)$")))
end

local function netLoop()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then
    print("No ender/wireless modem: no Nether Foreman, no orders.")
    return os.pullEvent("never")
  end
  rednet.open(peripheral.getName(modem))
  local me = os.getComputerID()
  local lastSend = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "assigned" and msg.id == me and not S.num and tonumber(msg.num) then
      S.num = tonumber(msg.num)
      os.setComputerLabel(msg.label or ("Firecrest-%02d"):format(S.num))
      print("The Nether Foreman named me " .. os.getComputerLabel() .. ".")
      save()
    elseif type(msg) == "table" and msg.type == "dock_ready" and msg.id == me then
      dockReply = msg
    elseif type(msg) == "table" and msg.type == "cmd" and msg.to == me then
      ctrl = msg
      if type(msg.junk) == "table" then
        S.junk = msg.junk; setJunk(S.junk); valuableCache = {}
      end
      local hA, fA = tonumber(msg.hungryAt), tonumber(msg.fullAt)
      if hA and fA and hA >= 1 and fA <= 99 and hA < fA then S.hungryAt, S.fullAt = hA, fA end
      if type(msg.capped) == "table" then
        local set = {}
        for _, n in ipairs(msg.capped) do set[n] = true end
        S.capped = set
      end
    end
    if os.clock() - lastSend >= STATUS_EVERY then
      if not S.num then
        -- No number yet: ask the Foreman (a label like Canary-04 is offered back, e.g. after a reset)
        rednet.broadcast({ type = "register", id = me, want = labelNum(), label = os.getComputerLabel() }, PROTOCOL)
      end
      rednet.broadcast(statusMsg(), PROTOCOL)
      lastSend = os.clock()
    end
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
if not fs.exists("startup.lua") then -- auto-resume after chunk reloads and restarts
  local f = fs.open("startup.lua", "w"); f.write('shell.run("firecrest")\n'); f.close()
end
load()
setJunk(S.junk)
if not S.dockY then setupDock() else recover() end
setStatus("docked", "Starting")
parallel.waitForAny(mainLoop, netLoop)
