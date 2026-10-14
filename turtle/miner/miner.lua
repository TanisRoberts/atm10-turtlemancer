-- miner.lua  --  shaft + expanding-square mining turtle (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- One program for every miner. Who he is depends on the dimension he's set up in:
--   Overworld, mining dimension, anything else: a CANARY (Canary-04). Orders from the Foreman.
--     Dock: the DUMP barrel (a storage input) on one side and the FUEL barrel on another (or above).
--   The Nether: a FIRECREST (Firecrest-01). Orders from the Nether Foreman. Advanced turtle, ONE dock
--     barrel (a Dock on the Nether Foreman's cable: it empties it and puts in what he asks for), and
--     ONE empty bucket he never lets go of: under 25% fuel he scoops and drinks every lava source he
--     sees (1,000 each), whole pools at a time, until he's over 75% (both set on the Nether Foreman).
--     Junk (netherrack, basalt ...) is thrown away underground; the Nether Foreman sends the list.
--   The End: a STARLING (Starling-05). Works exactly like a Canary, with the Foreman.
-- Needs: a mining turtle (diamond pickaxe) with an ender modem on its other side. Below the dock must
-- be free to dig. His number comes from his Foreman the first time he starts and is kept for good.
--
-- Position: he knows his dock's X/Y/Z, the way he faced and the dimension, and reports his exact
-- position. With GPS towers (the "GPS host" role, 4 of them) he also checks himself against GPS:
-- if he was carried somewhere he notices, works out which way he faces, and waits for an order;
-- then he digs down, tunnels to his shaft and comes up it. Without GPS he counts his moves.
--
-- What he does, once you press START on the Foreman:
--   * digs a shaft straight down from the dock to the chosen Y range
--   * mines expanding squares around the shaft, 3 levels per pass, ring by ring between the
--     Foreman's "from ring" and "to ring" (ring 1 = 3x3, ring 50 = 101x101):
--     he walks the middle level and digs the block above/below only if it's an ore
--   * on each new level he first walks out from the shaft N/E/S/W through open tunnel (never digging)
--     until he meets a block, then starts at the ring after the shortest of the four, so a level
--     that's already mined out doesn't get walked ring by ring again
--   * drops 3 levels and repeats until the range is done
--   * comes home through the shaft when full or low on fuel, unloads, refuels, goes back
--   * saves his position after every move, so he resumes after chunk unloads / restarts
--   * never digs another turtle (waits for it), or a cable, pipe, modem, computer, barrel, hopper,
--     ender chest or storage block (goes under or over it), so storage can run right through his area
--   * a chest (dungeon, fortress, bastion, stronghold...) in his way gets emptied BEFORE he digs it,
--     and one just above or below his tunnel gets emptied and left standing. Loot always comes home.
--     Too full to take it all: he goes home, unloads and comes back for the rest
-- Hold Ctrl+T to stop the program (the turtle stays where it is).
-- REBOOT from the Foreman: he finishes the block he's on (never mid-move or mid-turn), reboots,
-- pulls the latest files and carries on exactly where he was.

local STATE_FILE   = "miner.state"
local STATUS_EVERY = 3      -- seconds between status broadcasts

-- Who I am, by dimension (see the top). r2 = outer ring when the Foreman doesn't say, cap = furthest
-- ring allowed, reserve = spare fuel kept on top of the trip home, floor = lowest Y a level may reach.
local MODES = {
  canary    = { name = "Canary",    protocol = "tanis-miner",  boss = "the Foreman",
                r2 = 50, cap = 150, reserve = 60,  floor = -64 },
  firecrest = { name = "Firecrest", protocol = "tanis-nether", boss = "the Nether Foreman", nether = true,
                r2 = 24, cap = 100, reserve = 200, floor = 5 },   -- 24 rings = 49x49, about 3x3 chunks
  starling  = { name = "Starling",  protocol = "tanis-miner",  boss = "the Foreman", isEnd = true,
                r2 = 50, cap = 150, reserve = 60,  floor = 0 },   -- the End: void under Y 0
}
local function modeFor(dim)
  local d = tostring(dim or ""):lower():gsub("^minecraft:", "")
  if d == "the_nether" or d == "nether" then return "firecrest" end
  if d == "the_end" or d == "end" then return "starling" end
  return "canary"
end
-- Set by setMode() once the dimension is known (canary until then)
local MODE, MODE_KEY = MODES.canary, "canary"
local PROTOCOL, DEFAULT_R2, RING_CAP, FUEL_RESERVE = "tanis-miner", 50, 150, 60

-- Firecrest's lava
local NETHER_FLOOR = 5      -- lowest Y he mines in the Nether (bedrock below)
local HUNGRY_AT    = 25     -- % of the tank: start drinking lava (the Nether Foreman can change these)
local FULL_AT      = 75     -- % of the tank: stop drinking
local DRINK_STEPS  = 48     -- most cells he walks into while drinking one pool
local BUCKET, LAVA_BUCKET = "minecraft:bucket", "minecraft:lava_bucket"

-- Canary/Starling: things that count as junk live in junk.txt (one item per line, # for comments).
-- Junk is carried home while storage still wants it (under its cap), up to 4 slots, else dumped.
-- Edit junk.txt any time: it's re-read every time he docks.
-- Firecrest: the Nether Foreman sends his junk list (DEFAULT_NETHER_JUNK until it does); junk.txt
-- isn't used in the Nether, and junk never comes home from there.
local JUNK_FILE = "junk.txt"
local DEFAULT_JUNK = [[
# Canary's junk list: blocks he may throw away underground.
# One item per line. "minecraft:" is optional. Lines starting with # are ignored.
# Junk still comes home (up to 4 slots) while storage has less than its cap of it.
# Ores, raw metals and gems always come home. Anything else (flint, dripstone...)
# gets thrown out when his bag is full, unless you add a "keep" line, e.g.:
#   keep flint
cobblestone
cobbled_deepslate
stone
deepslate
tuff
granite
diorite
andesite
calcite
dirt
gravel
sand
sandstone
netherrack
smooth_basalt
basalt
blackstone
mud
clay
]]
local DEFAULT_NETHER_JUNK = { "netherrack", "blackstone", "basalt", "smooth_basalt", "soul_sand", "soul_soil",
  "magma_block", "gravel", "crimson_nylium", "warped_nylium", "nether_wart_block", "warped_wart_block",
  "cobblestone", "cobbled_deepslate", "polished_blackstone_bricks" }
local JUNK, KEEP = {}, {}
local function loadJunk()
  if not fs.exists(JUNK_FILE) then
    local f = fs.open(JUNK_FILE, "w"); f.write(DEFAULT_JUNK); f.close()
  end
  local f = fs.open(JUNK_FILE, "r")
  local text = f.readAll(); f.close()
  local junk, keep = {}, {}
  for line in text:gmatch("[^\r\n]+") do
    local item = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
    local isKeep = false
    if item:lower():sub(1, 5) == "keep " then isKeep = true; item = item:sub(6):match("^%s*(.-)%s*$") end
    if item ~= "" then
      if not item:find(":") then item = "minecraft:" .. item end
      if isKeep then keep[item] = true else junk[item] = true end
    end
  end
  JUNK, KEEP = junk, keep
end
-- Firecrest: the list from the Nether Foreman
local function setJunk(list)
  local junk = {}
  for _, item in ipairs(list or DEFAULT_NETHER_JUNK) do
    if type(item) == "string" and item ~= "" then
      if not item:find(":") then item = "minecraft:" .. item end
      junk[item] = true
    end
  end
  junk[BUCKET], junk[LAVA_BUCKET] = nil, nil   -- never junk
  JUNK, KEEP = junk, {}
end

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

-- Pick Canary / Firecrest / Starling from the dimension, and load the right junk list
local function setMode()
  MODE_KEY = modeFor(S.dim)
  MODE = MODES[MODE_KEY]
  PROTOCOL, DEFAULT_R2, RING_CAP, FUEL_RESERVE = MODE.protocol, MODE.r2, MODE.cap, MODE.reserve
  if MODE.nether then setJunk(S.junk) else loadJunk() end
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

-- Blocks I never dig. ComputerCraft lets a turtle mine another turtle (it ends up as an item in
-- my bag), and a pickaxe happily breaks storage cables, so:
--   * another turtle in my way: I wait for it to move on (isTurtle)
--   * a cable, pipe, modem, computer, barrel, hopper, ender chest or storage block (anything
--     isProtected): it isn't going anywhere, so I go round it, one block under it (or over, if under
--     won't work), and never dig it. Barrels and hoppers are how Tanis's storage is wired (chests
--     don't take modems); the loot underground is in chests, which I empty and dig (isLootable).
local KEEP_MODS = { "computercraft:", "refinedstorage:", "pipez:", "laserio:", "integrateddynamics:",
  "integratedtunnels:", "xnet:", "prettypipes:", "modularrouters:", "functionalstorage:",
  "sophisticatedstorage:", "storagedrawers:", "enderstorage:" }
local KEEP_WORDS = { "cable", "pipe", "conduit", "transporter", "duct", "pressurized_tube", "conductor",
  "barrel", "hopper", "ender_chest" }
local function blockName(ok, d)
  if ok == true and type(d) == "table" and type(d.name) == "string" then return d.name end
end
local function isTurtle(ok, d)
  local n = blockName(ok, d)
  return n ~= nil and n:find("^computercraft:turtle") ~= nil
end
local function isProtected(ok, d)
  local n = blockName(ok, d)
  if not n then return false end
  for _, p in ipairs(KEEP_MODS) do if n:sub(1, #p) == p then return true end end
  -- AE2: everything placed (cables, buses, drives ...), but not meteorites or certus quartz
  if n:sub(1, 4) == "ae2:" and not (n:find("quartz") or n:find("sky_stone") or n:find("mysterious")) then return true end
  for _, w in ipairs(KEEP_WORDS) do if n:find(w, 1, true) then return true end end
  return false
end
local isMachine = isProtected -- old name

-- A chest, shulker box or any other inventory that isn't protected: empty it before digging it.
local PSIDE = { f = "front", u = "top", d = "bottom" }
local function isLootable(kind, ok, d)
  local n = blockName(ok, d)
  if not n or isProtected(ok, d) then return false end
  if n:find("chest", 1, true) or n:find("shulker_box", 1, true) then return true end
  if d.tags and (d.tags["c:chests"] or d.tags["c:shulker_boxes"]) then return true end
  local side = PSIDE[kind]
  if peripheral.hasType then return peripheral.hasType(side, "inventory") == true end
  local t = { peripheral.getType(side) }
  for _, x in ipairs(t) do if x == "inventory" then return true end end
  return false
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
    elseif allowDig and not isMachine(turtle.inspect()) and not isLootable("f", turtle.inspect())
      and turtle.dig() then moved = turtle.forward() end
    if moved then
      local x1, _, z1 = locate()
      local stuck = not turtle.back()
      if stuck and allowDig then
        -- Something fell in behind: turn round, clear it, step back, turn round again
        turtle.turnRight(); turtle.turnRight()
        if not isMachine(turtle.inspect()) and not isLootable("f", turtle.inspect()) then turtle.dig() end
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
local CABLE = "Cable in the way" -- move() refused: a protected block (isProtected) is there
local CHEST_FULL = "Chest in the way, I'm full" -- move() refused: a chest I couldn't empty all of
local lootAt -- lootAt(kind): empty the container on that side; false if I'm too full (Inventory section)

-- Move one block, digging/attacking whatever is in the way (never a turtle or cable: see isProtected).
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

-- A cable is right in front of me: pass under it (or over it) and come up 2 blocks further on,
-- at the same height. Never digs the cable. False if there's no way round.
local function hopCable()
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
local function climbCable(k)
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
local function goToXZ(tx, tz, onStep, zFirst, retried)
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

local function goY(ty)
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

local function atDock() return S.x == 0 and S.y == 0 and S.z == 0 end

-- Carried somewhere (S.offPath): don't walk through whatever is around. Dig down to Y 0
-- (well under the island and the sea floor; in the Nether a few blocks under the dock, above the
-- bedrock floor), tunnel to below the shaft, then come up it.
local function tunnelDepth()
  local y = math.min(S.y, -4)
  if S.home and MODE.nether then
    y = math.max(y, NETHER_FLOOR + 1 - S.home.y) -- stay above the bedrock floor
  elseif S.home then
    y = math.min(y, -S.home.y)
    y = math.max(y, (MODE.isEnd and 1 or -60) - S.home.y) -- above bedrock (the End: above the void)
  end
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
    if d and JUNK[d.name] and (all or capped[d.name]) and not (S.loot and S.loot[d.name]) then
      turtle.select(s); dropAway()
    end
  end
  turtle.select(1)
end

-- Valuable = an ore product worth a trip home. Everything else can be dumped to make room.
local VALUE_TAGS = { "c:ores", "c:raw_materials", "c:gems", "c:dusts", "c:nuggets", "c:ingots",
  "minecraft:coals", "c:coal" }
-- "computercraft:" = a turtle/computer picked up by an older Canary: always brought home, never dumped
local VALUE_NAMES = { "computercraft:", "cable", "raw_", "_ore", "diamond", "emerald", "lapis", "redstone", "coal", "quartz",
  "amethyst_shard", "ancient_debris", "netherite", "nugget", "ingot", "gem", "crystal", "dust", "gilded",
  "glowstone", "shroomlight" }
local valuableCache = {}
local function isValuable(slot)
  local d = turtle.getItemDetail(slot)
  if not d then return false end
  if S.loot and S.loot[d.name] then return true end -- out of a chest: always comes home
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

-- Every step: hungry? Then any lava next to him gets drunk, and a pool gets drunk dry. (Firecrest only:
-- Canaries and Starlings carry no bucket and leave lava alone.)
local function lookForLava()
  if not MODE.nether or not hungry() then return end
  drinkHeld()
  if not findSlot(BUCKET) then return end
  local got = false
  for _, k in ipairs({ "f", "u", "d" }) do
    if scoop(k) then got = true end
  end
  if got and hungry() then drinkPool() end
end

---------------------------------------------------------------------------
-- Chests: empty them before digging (a dug chest spills its loot on the floor, and I'd walk on)
---------------------------------------------------------------------------
local SUCK = { f = turtle.suck, u = turtle.suckUp, d = turtle.suckDown }
local function countsBySlot()
  local c = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    c[s] = d and { d.name, d.count } or false
  end
  return c
end

-- Take everything out of the container on that side. Everything taken that isn't on my junk list
-- is marked as loot (always comes home, never thrown away). True when it's empty; false if I filled up first (after making
-- room by throwing junk away).
lootAt = function(kind)
  local took, roomMade = 0, false
  turtle.select(1)
  while true do
    local before = countsBySlot()
    if SUCK[kind]() then
      took = took + 1
      S.loot = S.loot or {}
      for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        -- (junk out of a chest is still junk: netherrack in a fortress chest gets no free ride home)
        if d and not JUNK[d.name] and (not before[s] or before[s][1] ~= d.name or before[s][2] < d.count) then
          S.loot[d.name] = true
        end
      end
      S.lootItems = (S.lootItems or 0) + 1
      save()
    elseif emptySlots() > 0 then
      -- Room to spare and nothing came out: it's empty
      if took > 0 then
        S.chests = (S.chests or 0) + 1
        setStatus(S.status or "mining", ("Emptied a chest (%d stack%s)"):format(took, took == 1 and "" or "s"))
      end
      return true
    elseif not roomMade then
      makeRoom(); roomMade = true
    else
      setStatus(S.status or "mining", "Full, with a chest still to empty")
      return false
    end
  end
end

-- A chest just above or below my tunnel: empty it and leave it standing (only with room to spare)
local function lootUpDown()
  for _, k in ipairs({ "u", "d" }) do
    if emptySlots() > 2 and isLootable(k, OPS[k].inspect()) then lootAt(k) end
  end
end

local function checkUpDown()
  if isOre(turtle.inspectUp()) then turtle.digUp(); S.ores = (S.ores or 0) + 1 end
  if isOre(turtle.inspectDown()) then turtle.digDown(); S.ores = (S.ores or 0) + 1 end
  lootUpDown()
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
  dumpJunk(MODE.nether == true)   -- Firecrest: the Nether Foreman's junk is thrown away, never carried home
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
  while c + 1 >= S.minY and c - 1 >= MODE.floor do
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
-- through open space only (air: water, lava and anything else count as unmined), stop at the first
-- block (or at the outer ring), walk back.
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
      if okI and dI.name ~= "minecraft:air" and dI.name ~= "minecraft:cave_air" and dI.name ~= "minecraft:void_air" then break end
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
        local k = S.y > cy and "d" or "u"
        local ok, why = move(k)
        if not ok and why == CHEST_FULL and math.abs(cy - S.y) <= 1 then abort("full", "Full: a chest to finish emptying") end
        if not ok and (why == CABLE or why == CHEST_FULL) and math.abs(cy - S.y) > 1 then ok, why = climbCable(k) end
        if not ok then error("Shaft blocked at Y " .. (S.dockY + S.y) .. ": " .. tostring(why), 0) end
        lookForLava()   -- the Nether's shaft often goes through the lava sea
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
        local ok, why = goToXZ(cells[i][1], cells[i][2], checkUpDown)
        -- That cell is a chest and I'm full: home to unload, then back to this very cell for the rest
        if not ok and why == CHEST_FULL then abort("full", "Full: a chest to finish emptying") end
        if not ok and why ~= CABLE then blocked = true; break end -- a cable cell is just skipped
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

-- Tell storage which barrels are mine: with storage watching (sorting paused), take 1 item from
-- my fuel barrel and drop it in my dump barrel. Storage registers whichever barrels changed.
local function linkBarrels()
  if not (S.fuelDir and S.dumpDir) then return false, "No barrels found at setup" end
  if not rednet.isOpen() then
    local m = peripheral.find("modem", function(_, x) return x.isWireless() end)
    if not m then return false, "No ender modem" end
    rednet.open(peripheral.getName(m))
  end
  local me = os.getComputerID()
  local function waitFor(kind, seconds)
    local deadline = os.clock() + seconds
    while os.clock() < deadline do
      local _, m = rednet.receive(PROTOCOL, math.max(0.1, deadline - os.clock()))
      if type(m) == "table" and m.type == kind and m.id == me then return m end
    end
  end
  setStatus("docked", "Showing storage my barrels")
  rednet.broadcast({ type = "barrel_probe", step = "start", id = me }, PROTOCOL)
  if not waitFor("probe_ready", 10) then
    return false, "Storage didn't answer (needs a wireless/ender modem)"
  end
  for slot = 1, 16 do if turtle.getItemCount(slot) == 0 then turtle.select(slot); break end end
  local item
  if suckFrom(S.fuelDir, 1) then
    local d = turtle.getItemDetail()
    item = d and d.name
    dropTo(S.dumpDir)
  end
  face(0)
  rednet.broadcast({ type = "barrel_probe", step = "done", id = me, item = item }, PROTOCOL)
  local r = waitFor("probe_result", 25)
  turtle.select(1)
  if not r then return false, "Storage didn't confirm" end
  return r.ok == true, r.msg
end

local nextLinkTry = 0
local function maybeLinkBarrels()
  if S.barrelsLinked or os.clock() < nextLinkTry or not atDock() then return end
  if MODE.isEnd then S.linkNote = "In the End: storage can't reach my barrels"; return end
  local ok, msg = linkBarrels()
  S.barrelsLinked, S.linkNote = ok or nil, msg
  save()
  print((ok and "Barrels linked: " or "Barrel link failed: ") .. tostring(msg))
  if not ok then nextLinkTry = os.clock() + 120 end
end

---------------------------------------------------------------------------
-- Dock: unload, refuel
---------------------------------------------------------------------------
local function gpsFixHome()
  if not gpsSeen then return end
  local x, y, z = locate()
  local ex, ey, ez = absPos()
  if x and ex and (x ~= ex or y ~= ey or z ~= ez) then
    print(("GPS says %d %d %d, I counted %d %d %d. Trusting GPS."):format(x, y, z, ex, ey, ez))
    S.home = { x = x - (ex - S.home.x), y = y - (ey - S.home.y), z = z - (ez - S.home.z) }
    S.dockY = S.home.y
  end
end

-- Canary / Starling: DUMP barrel (storage input) and FUEL barrel
local function dockServiceCanary()
  setStatus("docked", "Unloading")
  gpsFixHome()
  loadJunk()            -- pick up any edits to junk.txt
  valuableCache = {}
  local haul = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      turtle.select(s)
      if not JUNK[d.name] then haul[d.name] = (haul[d.name] or 0) + d.count end
      local tries = 0
      while turtle.getItemCount(s) > 0 do
        if not dropTo(S.dumpDir) then
          tries = tries + 1
          setStatus("waiting", "Dump barrel full, waiting")
          os.sleep(3)
          if tries > 10 then break end -- give up for now; the main loop waits at the dock
        end
      end
    end
  end
  if next(haul) then
    S.lastHaul = haul
    S.totals = S.totals or {}
    for n, c in pairs(haul) do S.totals[n] = (S.totals[n] or 0) + c end
  end
  S.ores = 0
  if emptySlots() < 16 then face(0); save(); return false end -- couldn't unload everything
  S.loot = nil          -- the loot's in storage now
  maybeLinkBarrels() -- before refuelling, while the fuel barrel still has something in it

  -- Refuel from the fuel barrel, taking only what fits in the tank
  local limit = fuelLimit()
  if limit ~= math.huge then
    setStatus("docked", "Refuelling")
    turtle.select(1)
    for _ = 1, 40 do
      if fuel() >= limit - 80 then break end
      if not suckFrom(S.fuelDir) then break end
      local returned = false
      if turtle.refuel(0) then
        local before = fuel()
        turtle.refuel(1)
        local per = fuel() - before
        if per > 0 then
          local n = math.floor((limit - fuel()) / per)
          if n > 0 then turtle.refuel(math.min(n, turtle.getItemCount(1))) end
        end
      end
      if turtle.getItemCount(1) > 0 then
        if turtle.refuel(0) then dropTo(S.fuelDir); returned = true -- leftover fuel goes back
        else dropTo(S.dumpDir) end                                -- empty buckets etc. to storage
      end
      if returned then break end
    end
  end
  face(0)
  save()
  return emptySlots() == 16 -- false if the dump barrel wouldn't take everything
end

---------------------------------------------------------------------------
-- Firecrest's dock: one barrel. He empties everything into it (except his bucket); the Nether Foreman takes it
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

local function dockServiceNether(needStart)
  setStatus("docked", "Unloading")
  gpsFixHome()
  valuableCache = {}
  drinkHeld()
  dumpJunk(true)   -- junk picked up on the way home goes down the shaft, not into the dock
  S.ores = 0
  if not unloadAll() then face(0); save(); return false end
  S.loot = nil     -- the loot's with the Nether Foreman now

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

-- needStart: fuel needed to head out (Firecrest asks the dock for it; Canaries just refuel)
local function dockService(needStart)
  if MODE.nether then return dockServiceNether(needStart) end
  return dockServiceCanary()
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
  title("MINER SETUP")
  S = { x = 0, y = 0, z = 0, h = 0, want = "dock", seq = nil }
  print("Which dimension am I in?")
  S.dim = askDimension()
  setMode()
  term.clear(); term.setCursorPos(1, 1)
  title(("I'M A %s HERE"):format(MODE.name:upper()))
  print("I'm sitting on top of my future shaft.")
  if MODE.nether then
    print("I need ONE barrel next to me (a side")
    print("or above): my dock, a Dock on the")
    print("Nether Foreman's cable. And one empty")
    print("bucket in my inventory, for lava.")
  else
    print("I need two barrels next to me (sides or above):")
    print(" - DUMP barrel (a storage input, empty)")
    print(" - FUEL barrel (with some coal in it)")
  end
  print()
  local x, y, z = locate()
  if x then
    print(("GPS says I'm at %d %d %d."):format(x, y, z))
    S.home = { x = x, y = y, z = z }
    local c, _, stuck = compassByStep(false)
    S.facing = c
    if stuck then apply("f") end -- couldn't step back onto the dock; goHome fixes it later
    if S.facing then print("I'm facing " .. COMPASS[S.facing] .. ".") else S.facing = askFacing() end
  else
    print("No GPS towers heard. Type my position")
    print("(F3, the block I'm in):")
    local hx = askNumber("X: ")
    local hy = askNumber("Y: ")
    local hz = askNumber("Z: ")
    S.home = { x = hx, y = hy, z = hz }
    S.facing = askFacing()
  end
  S.dockY = S.home.y
  save()
  while true do
    local found = {}
    for _ = 0, 3 do
      if isContainer(turtle.inspect()) then found[#found + 1] = S.h end
      turnRight()
    end
    if isContainer(turtle.inspectUp()) then found[#found + 1] = "up" end
    if MODE.nether then
      face(0)
      if #found == 1 then
        S.dockDir = found[1]
        print(("Dock barrel: %s."):format(sideName(S.dockDir)))
        break
      end
      printError(#found == 0 and "No barrel next to me." or ("%d barrels here: I need just one."):format(#found))
      print("Fix that, then press Enter.")
    else
      local fuelDir, others = nil, {}
      turtle.select(1)
      for _, dir in ipairs(found) do
        if suckFrom(dir) then
          local isFuel = turtle.refuel(0)
          dropTo(dir)
          if isFuel and not fuelDir then fuelDir = dir else others[#others + 1] = dir end
        else
          others[#others + 1] = dir
        end
      end
      face(0)
      if fuelDir and #others >= 1 then
        S.fuelDir, S.dumpDir = fuelDir, others[1]
        print(("Fuel barrel: %s. Dump barrel: %s."):format(sideName(S.fuelDir), sideName(S.dumpDir)))
        break
      end
      printError(("Found %d barrel(s); fuel %s."):format(#found, fuelDir and "found" or "not found"))
      print("Put coal in the FUEL barrel, keep the DUMP barrel empty, then press Enter.")
    end
    read()
  end
  if MODE.nether and bucketState() == "none" then
    printError("No bucket on me: put an empty bucket")
    print("in me, or in a Nether stock barrel.")
  end
  save()
  print(("Setup done. %s gives me a"):format((MODE.boss:gsub("^t", "T"))))
  print("number; pick my layers and press")
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
  if S.dockDir then
    print(("Put me back on the dock with the barrel %s,"):format(sideName(S.dockDir)))
  else
    print(("Put me back on the dock with the dump barrel %s,"):format(sideName(S.dumpDir)))
  end
  print("then press Enter here.")
  read()
  S.x, S.y, S.z, S.h, S.lost = 0, 0, 0, 0, nil
  S.k, S.step = S.r1 or 1, 1
  save()
end

-- Older Canaries only knew their dock's Y. Fill in X/Z, facing and dimension once.
local function migrateHome()
  if S.home and S.facing then return end
  setStatus("waiting", "Working out where my dock is")
  local x, y, z = locate()
  if x and not S.lost then
    local c, turns, stuck = compassByStep(S.y <= -2)
    S.h = (S.h + turns) % 4
    if stuck then apply("f") end
    if c then
      S.facing = (c - S.h) % 4
      x, y, z = locate()
      if x then
        local ax, az = rot(S.x, S.z, S.facing)
        S.home = { x = x - ax, y = y - S.y, z = z - az }
        S.dockY = S.home.y
        S.dim = S.dim or "overworld"
        save()
        return
      end
    end
  end
  setStatus("waiting", "Type my dock's position on my screen (one time)")
  term.clear(); term.setCursorPos(1, 1)
  title("ONE-TIME: WHERE IS MY DOCK?")
  print(("My dock is at Y %d. I need its X and Z (F3 on the"):format(S.dockY))
  print("block I sit in when docked), and which way I face there.")
  local hx = askNumber("Dock X: ")
  local hz = askNumber("Dock Z: ")
  S.home = { x = hx, y = S.dockY, z = hz }
  S.facing = askFacing()
  print("Which dimension?")
  S.dim = askDimension()
  save()
  print("Thanks! Carrying on.")
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
      setStatus("waiting", MODE.nether and "Dock barrel full. Is the Nether Foreman running?"
        or "Dump barrel full. Is storage running?")
      waitCtrl(15)
      return
    end
    if MODE.nether and bucketState() == "none" then
      setStatus("waiting", "No bucket: put an empty bucket in a Nether stock barrel")
      waitCtrl(15)
      return
    end
    if fuel() < need then
      setStatus("waiting", ("Need %d fuel, have %d%s"):format(need, fuel(),
        MODE.nether and ": lava buckets in a stock barrel" or ""))
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
  migrateHome()
  setMode()
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
      if atDock() then dockService(); setStatus("retired", "Retired. Thanks for your service") end
      waitCtrl(30)
    elseif S.want ~= "run" or S.done then
      if not atDock() then setStatus("returning", "Heading home"); safeHome() end
      if atDock() then
        dockService()
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
  local m = {
    type = "status", id = os.getComputerID(), label = os.getComputerLabel(), num = S.num,
    pos = px and { x = px, y = py, z = pz } or nil, dim = S.dim, home = S.home,
    facing = S.facing and COMPASS[(S.facing + (S.h or 0)) % 4], gps = gpsSeen,
    offPath = S.offPath, retired = S.retired, state = S.status, msg = S.msg, seq = S.seq,
    kind = MODE_KEY, bird = MODE.name, chests = S.chests or 0,
    fuel = f, fuelLimit = l, slots = used,
    y = S.dockY and (S.dockY + (S.y or 0)), x = S.x, z = S.z,
    layer = S.layerIdx, layers = S.layerCount, ring = S.k, minRing = S.r1 or 1, maxRing = S.r2 or DEFAULT_R2,
    minY = S.minY, maxY = S.maxY, want = S.want, rebootDone = S.rebootDone, done = S.done, ores = S.ores, haul = haul,
  }
  if MODE.nether then
    m.hungry, m.hungryAt, m.fullAt = S.hungry == true, S.hungryAt or HUNGRY_AT, S.fullAt or FULL_AT
    m.bucket, m.lavaFuel, m.lavaScoops, m.dockNote = bucketState(), S.lavaFuel or 0, S.lavaScoops or 0, S.dockNote
  else
    m.barrelsLinked, m.linkNote = S.barrelsLinked, S.linkNote
  end
  return m
end

-- My number from a label like Canary-04 / Firecrest-01 (any bird: it's offered back after a reset)
local function labelNum()
  return tonumber(((os.getComputerLabel() or ""):match("^%a+%-(%d+)$")))
end
local function myLabel(num) return ("%s-%02d"):format(MODE.name, num) end

-- Name follows the dimension: a numbered miner whose label names another bird gets his own
local function fixLabel()
  if not S.num then return end
  local lbl = os.getComputerLabel()
  local bird, n = (lbl or ""):match("^(%a+)%-(%d+)$")
  if lbl and not bird then return end           -- a label Tanis typed himself: leave it
  if bird ~= MODE.name or tonumber(n) ~= S.num then os.setComputerLabel(myLabel(S.num)) end
end

local function netLoop()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then
    print(("No ender/wireless modem: no %s, no orders."):format((MODE.boss:gsub("^the ", ""))))
    return os.pullEvent("never")
  end
  rednet.open(peripheral.getName(modem))
  local me = os.getComputerID()
  local lastSend = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "assigned" and msg.id == me and not S.num and tonumber(msg.num) then
      S.num = tonumber(msg.num)
      -- An older Foreman only knows Canary-NN: my name comes from my dimension either way
      local lbl = type(msg.label) == "string" and msg.label or ""
      os.setComputerLabel(lbl:sub(1, #MODE.name + 1) == MODE.name .. "-" and lbl or myLabel(S.num))
      print(("%s named me %s."):format((MODE.boss:gsub("^t", "T")), os.getComputerLabel()))
      save()
    elseif type(msg) == "table" and msg.type == "dock_ready" and msg.id == me then
      dockReply = msg
    elseif type(msg) == "table" and msg.type == "cmd" and msg.to == me then
      ctrl = msg
      if MODE.nether and type(msg.junk) == "table" then
        S.junk = msg.junk; setJunk(S.junk); valuableCache = {}
      end
      local hA, fA = tonumber(msg.hungryAt), tonumber(msg.fullAt)
      if MODE.nether and hA and fA and hA >= 1 and fA <= 99 and hA < fA then S.hungryAt, S.fullAt = hA, fA end
      if type(msg.capped) == "table" then
        local set = {}
        for _, n in ipairs(msg.capped) do set[n] = true end
        S.capped = set
      end
    end
    if os.clock() - lastSend >= STATUS_EVERY then
      if not S.num then
        -- No number yet: ask the Foreman (a label like Canary-04 is offered back, e.g. after a reset)
        rednet.broadcast({ type = "register", id = me, want = labelNum(), label = os.getComputerLabel(),
          name = MODE.name }, PROTOCOL)
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
  local f = fs.open("startup.lua", "w"); f.write('shell.run("miner")\n'); f.close()
end
load()
if not S.dockY then setupDock() else recover() end
setMode()
fixLabel()
print(("I'm a %s (%s)."):format(MODE.name, tostring(S.dim or "overworld")))
setStatus("docked", "Starting")
parallel.waitForAny(mainLoop, netLoop)
