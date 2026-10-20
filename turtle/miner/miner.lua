-- miner.lua  --  shaft + expanding-square mining turtle (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- One program for every miner. Who he is depends on the dimension he's set up in:
--   The Mining Dimension (allthemodium:mining), the Overworld, anything else: a CANARY (Canary-04).
--     Orders from the MD Foreman. ONE dock barrel: he empties his haul into it and asks for fuel (lava
--     buckets); nobody answering, he takes whatever fuel is in it. Empty buckets go back in.
--   The Nether: a FIRECREST (Firecrest-01). Orders from the Nether Foreman. Advanced turtle, ONE dock
--     barrel (a Dock on the Nether Foreman's cable: it empties it and puts in what he asks for), and
--     ONE empty bucket he never lets go of: under 25% fuel he scoops and drinks every lava source he
--     sees (1,000 each), whole pools at a time, until he's over 75% (both set on the Nether Foreman).
--     Junk (netherrack, basalt ...) is thrown away underground; the Nether Foreman sends the list.
--   The End: a STARLING (Starling-05). Orders from the Foreman. Dock: the DUMP barrel on one side and
--     the FUEL barrel on another (or above), both filled/emptied by hand (storage can't reach the End).
-- Carried to another dock or dimension, he offers to set up there (keeping his number); he never
-- tunnels to a dock far away (docs/systems/miner.md).
-- Needs: a mining turtle (diamond pickaxe) with an ender modem on its other side. Below the dock must
-- be free to dig. His number comes from his Foreman the first time he starts and is kept for good.
--
-- Position: he knows his dock's X/Y/Z, the way he faced and the dimension, and reports his exact
-- position. With GPS towers (the "GPS host" role, 4 of them) he also checks himself against GPS:
-- if he was carried somewhere he notices, works out which way he faces, and waits for an order;
-- then he digs down, tunnels to his shaft and comes up it. Without GPS he counts his moves.
--
-- What he does, once you press START on the Foreman (CHUNK BY CHUNK, "CBC"):
--   * his area is chunk rings around his dock's chunk, set on the Foreman: ring 0 = that chunk,
--     ring 1 = the 8 around it (3x3 chunks), ring 5 = 11x11 chunks ...
--   * digs a shaft straight down from the dock to the chosen Y range, then works ONE CHUNK at a time,
--     every level of it, before moving on: down through the levels in one chunk, up in the next.
--     Each level is a snake over the chunk's 16x16, 3 levels per pass: he walks the middle one and
--     digs the block above/below only if it's an ore
--   * with a chunk controller (Advanced Peripherals) in his bag he keeps his own chunk loaded: he
--     swaps it onto his modem's side for a moment in every new chunk (and every 45 s), so only the
--     chunk he's in is force-loaded. Without one: keep his area loaded (or stay near it)
--   * with a shulker box in his bag (any kind; Sophisticated Storage ones upgrade to huge) he puts
--     his ore in it when his slots run out, and only comes home when the box is full too
--   * comes home through the shaft when full or low on fuel, unloads (and unpacks the box), refuels,
--     goes back to the same chunk, level and block
--   * saves his position after every move, so he resumes after chunk unloads / restarts
--   * never digs another turtle (waits for it), or a cable, pipe, modem, computer, barrel, hopper,
--     ender chest or storage block (goes under or over it), so storage can run right through his area
--   * a chest (dungeon, fortress, bastion, stronghold...) in his way gets emptied BEFORE he digs it,
--     and one just above or below his tunnel gets emptied and left standing. Loot always comes home.
--     Too full to take it all: he goes home, unloads and comes back for the rest
-- Hold Ctrl+T to stop the program (the turtle stays where it is).
-- REBOOT from the Foreman: he finishes the block he's on (never mid-move or mid-turn), reboots,
-- pulls the latest files and carries on exactly where he was.

local core = dofile("turtlecore.lua")   -- fuel, dock, GPS (docs/systems/turtle.md)

local STATE_FILE   = "miner.state"
local STATUS_EVERY = 3      -- seconds between status broadcasts

-- Who I am, by dimension (see the top). r2 = outer CHUNK ring when the Foreman doesn't say (ring 0 =
-- the dock's chunk, ring 3 = 7x7 chunks), reserve = spare fuel kept on top of the trip home,
-- floor = lowest Y a level may reach.
local MODES = {
  canary    = { name = "Canary",    protocol = "tanis-miner",  boss = "the MD Foreman", oneDock = true,
                r2 = 3, reserve = 150, floor = -64 },
  firecrest = { name = "Firecrest", protocol = "tanis-nether", boss = "the Nether Foreman", nether = true, oneDock = true,
                r2 = 1, reserve = 200, floor = 5 },
  starling  = { name = "Starling",  protocol = "tanis-miner",  boss = "the Foreman", isEnd = true,
                r2 = 3, reserve = 60,  floor = 0 },   -- the End: void under Y 0
}
local RING_CAP = 16   -- furthest chunk ring (33x33 chunks)
local function modeFor(dim)
  local d = tostring(dim or ""):lower():gsub("^minecraft:", "")
  if d == "the_nether" or d == "nether" then return "firecrest" end
  if d == "the_end" or d == "end" then return "starling" end
  return "canary"
end
-- Set by setMode() once the dimension is known (canary until then)
local MODE, MODE_KEY = MODES.canary, "canary"
local PROTOCOL, DEFAULT_R2, FUEL_RESERVE = "tanis-miner", 3, 60

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
  PROTOCOL, DEFAULT_R2, FUEL_RESERVE = MODE.protocol, MODE.r2, MODE.reserve
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
local inArea -- inArea(x, z): inside my chunk area? (Mining plan section)
local stash -- stash(): put my ore in my shulker box (Shulker box section)
local refreshChunk = function() end -- keeps my chunk loaded if I carry a chunk controller (Chunk loader section)

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

-- Gear: things I carry for myself and never unload, stash or throw away
local function isBox(name) return type(name) == "string" and name:find("shulker_box", 1, true) ~= nil end
local function isGear(name) return name == core.chunk.ITEM or core.chunk.isModem(name) or isBox(name) end
local function freeSlot()
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then return s end end
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
  if isGear(d.name) then return true end
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
    if d and not JUNK[d.name] and not isGear(d.name) then
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
  local took, roomMade, stashed = 0, false, false
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
    elseif not stashed and stash then
      -- Into the shulker box with what I've got (it won't go where the chest is: up/down/behind)
      stashed = true
      if stash() then roomMade, stashed = false, false end
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
-- Chunk loader: core.chunk (shared/turtlecore_chunk.lua) swaps a chunk controller onto my modem's side in
-- every new chunk (and every 45 s), so only the chunk I'm in is force-loaded. No controller: keep my area
-- loaded (or stay near it).
---------------------------------------------------------------------------
local function haveChunky() return core.chunk.have() end
local function chunkKey()
  local x, _, z = absPos()
  if not x then return nil end
  return math.floor(x / 16) .. "," .. math.floor(z / 16)
end

refreshChunk = function(force)
  if not S.chunky then return end
  local before = core.chunk.swaps
  core.chunk.ensure(chunkKey(), force)
  S.chunkyNote = core.chunk.note
  if core.chunk.swaps ~= before then S.swaps = (S.swaps or 0) + 1 end
end

-- Boot: a swap that was cut short leaves the modem in my bag and the controller on. Put it back.
local function restoreRadio()
  if core.chunk.restore(S.swapSide) then print("Put my modem back on (a chunk swap was cut short).") end
  S.swapSide = nil
  save()
end

---------------------------------------------------------------------------
-- Shulker box: carried along as extra cargo space. Running out of slots, I put it down (above, below
-- or behind me), put my ore in, and dig it back up (it keeps what's in it). At the dock I unpack it.
-- Any shulker box works; Sophisticated Storage ones can be upgraded (bigger, stack upgrades).
---------------------------------------------------------------------------
local BOXPLACE = { f = turtle.place, u = turtle.placeUp, d = turtle.placeDown }
local BOXDROP  = { f = turtle.drop,  u = turtle.dropUp,  d = turtle.dropDown }
local BOXDIG   = { f = turtle.dig,   u = turtle.digUp,   d = turtle.digDown }
local BOXDET   = { f = turtle.detect, u = turtle.detectUp, d = turtle.detectDown }
local function boxSlot()
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and isBox(d.name) then return s end end
end
-- Things that stay in my slots: gear, and Firecrest's bucket
local function isKept(name)
  return isGear(name) or (MODE.nether and (name == BUCKET or name == LAVA_BUCKET))
end

-- Pick the box back up (also after a restart mid-stash: S.boxAt says where it is)
local function pickUpBox()
  local k = S.boxAt
  if not k then return true end
  if k == "f" and S.boxH then face(S.boxH) end
  local fs = freeSlot()
  if fs then turtle.select(fs) end
  local ok = BOXDIG[k]()
  turtle.select(1)
  if ok or not BOXDET[k]() then S.boxAt, S.boxH = nil, nil; save() end
  return S.boxAt == nil
end

stash = function()
  local bs = boxSlot()
  if not bs or S.boxFull then return false end
  local oh, k = S.h, nil
  if not BOXDET.u() then k = "u" elseif not BOXDET.d() then k = "d" end
  if not k then
    face((S.h + 2) % 4)                    -- the cell I just came from is open
    if not BOXDET.f() then k = "f" end
  end
  if not k then face(oh); return false end
  turtle.select(bs)
  if not BOXPLACE[k]() then turtle.select(1); face(oh); return false end
  S.boxAt, S.boxH = k, S.h; save()
  local full, moved = false, 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isKept(d.name) and isValuable(s) then
      turtle.select(s)
      while turtle.getItemCount(s) > 0 do
        if not BOXDROP[k]() then full = true; break end
      end
      moved = moved + 1
    end
  end
  pickUpBox()
  face(oh)
  if full then S.boxFull = true end
  S.boxStacks = (S.boxStacks or 0) + moved
  setStatus(S.status or "mining", full and "Shulker box full" or ("Put %d stacks in my shulker box"):format(moved))
  save()
  return moved > 0
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

local function waitCtrl(seconds)
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
local function dockChunk() return math.floor(S.home.x / 16), math.floor(S.home.z / 16) end
local function chunkList()
  local cx, cz = dockChunk()
  local out = {}
  for k = S.r1 or 0, S.r2 or DEFAULT_R2 do
    for _, c in ipairs(ringCells(k)) do out[#out + 1] = { cx + c[1], cz + c[2], ring = k } end
  end
  return out
end
-- World X/Z -> my dock-relative x/z
local function relOf(ax, az) return rot(ax - S.home.x, az - S.home.z, 4 - S.facing) end
-- The 16x16 of chunk (cx, cz) as a snake; reversed on even passes so each pass starts where the last ended
local function snake(cx, cz, reversed)
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

local function fuelToStart()
  local layers = layerList()
  local y = layers[1] or S.dockY
  return 2 * (S.dockY - y) + 64 * ((S.chunkRing or 0) + 1) + 500
end

local function toLevel(cy)
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

local function mineChunks()
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

-- Anything in my slots that isn't gear (or Firecrest's bucket)?
local function cargoLeft()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isKept(d.name) then return true end
  end
  return false
end

-- Empty my shulker box at the dock: put it down below me (the top of my shaft), take a bagful out,
-- unload it with unload(), repeat. False if the barrel wouldn't take it all (the box then stays put
-- until the next try).
local function unpackBox(unload)
  if not S.boxAt then
    local bs = boxSlot()
    if not bs then return true end
    if BOXDET.d() then return true end       -- no room below (never mined): nothing was stashed anyway
    turtle.select(bs)
    if not BOXPLACE.d() then turtle.select(1); return true end
    S.boxAt, S.boxH = "d", nil; save()
  end
  setStatus("docked", "Unpacking my shulker box")
  while true do
    local got = false
    while true do
      local fs = freeSlot()
      if not fs then break end
      turtle.select(fs)
      if turtle.suckDown() then got = true else break end
    end
    turtle.select(1)
    if not unload() then return false end
    if not got then break end
  end
  pickUpBox()
  S.boxFull, S.boxStacks = nil, 0
  save()
  return true
end

-- Two barrels (Starling): DUMP barrel and FUEL barrel
local function dockServiceTwo()
  setStatus("docked", "Unloading")
  gpsFixHome()
  loadJunk()            -- pick up any edits to junk.txt
  valuableCache = {}
  local haul = {}
  local function unload()
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and not isKept(d.name) then
        turtle.select(s)
        if not JUNK[d.name] then haul[d.name] = (haul[d.name] or 0) + d.count end
        local tries = 0
        while turtle.getItemCount(s) > 0 do
          if not dropTo(S.dumpDir) then
            tries = tries + 1
            setStatus("waiting", "Dump barrel full, waiting")
            os.sleep(3)
            if tries > 10 then return false end -- give up for now; the main loop waits at the dock
          end
        end
      end
    end
    return true
  end
  local ok = unload() and unpackBox(unload)
  if next(haul) then
    S.lastHaul = haul
    S.totals = S.totals or {}
    for n, c in pairs(haul) do S.totals[n] = (S.totals[n] or 0) + c end
  end
  S.ores = 0
  if not ok or cargoLeft() then face(0); save(); return false end -- couldn't unload everything
  S.loot = nil          -- the loot's in storage now
  maybeLinkBarrels() -- before refuelling, while the fuel barrel still has something in it

  -- Refuel from the fuel barrel, taking only what fits in the tank
  local limit = fuelLimit()
  if limit ~= math.huge then
    setStatus("docked", "Refuelling")
    local fs = freeSlot() or 1
    turtle.select(fs)
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
          if n > 0 then turtle.refuel(math.min(n, turtle.getItemCount(fs))) end
        end
      end
      if turtle.getItemCount(fs) > 0 then
        if turtle.refuel(0) then dropTo(S.fuelDir); returned = true -- leftover fuel goes back
        else dropTo(S.dumpDir) end                                -- empty buckets etc. to storage
      end
      if returned then break end
    end
  end
  turtle.select(1)
  face(0)
  save()
  return not cargoLeft() -- false if the dump barrel wouldn't take everything
end

---------------------------------------------------------------------------
-- One dock barrel (Canary, Firecrest). He empties everything into it (except his gear, and Firecrest's
-- bucket); his Foreman takes it away. If he needs fuel (or Firecrest a bucket) he asks, the Foreman puts
-- it in the barrel, he takes it. Nobody answering: he takes whatever fuel is in the barrel himself.
---------------------------------------------------------------------------
local dockReply = nil   -- latest dock_ready for me (set by the network loop)
local ASK_FOR = 10      -- seconds to wait for the Foreman's dock_ready

local function askDock(needBucket, wantFuel)
  if not rednet.isOpen() then return nil end
  local me, seq = os.getComputerID(), os.epoch("utc")
  dockReply = nil
  local deadline, nextSend = os.clock() + ASK_FOR, 0
  while os.clock() < deadline do
    if os.clock() >= nextSend then
      rednet.broadcast({ type = "dock_req", id = me, seq = seq, bucket = needBucket, fuel = wantFuel }, PROTOCOL)
      nextSend = os.clock() + 3
    end
    if dockReply and dockReply.seq == seq then return dockReply end
    os.sleep(0.5)
  end
end

-- Empty everything into the dock but my gear (and Firecrest's one bucket). False if the barrel wouldn't take it all.
local function unloadAll()
  local keepSlot = MODE.nether and (findSlot(BUCKET) or findSlot(LAVA_BUCKET)) or nil
  local haul = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      local keep = (s == keepSlot) and 1 or 0
      if isGear(d.name) then keep = d.count end
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
    local d = turtle.getItemDetail(s)
    if d and not isGear(d.name) and d.count > ((s == keepSlot) and 1 or 0) then return false end
  end
  return true
end

-- Take what the Foreman put in the dock: burn the fuel (as much as fits), keep Firecrest's bucket, hand
-- the rest back (empty buckets, spare coal) for the Foreman's stock.
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

local function dockServiceOne(needStart)
  setStatus("docked", "Unloading")
  gpsFixHome()
  if not MODE.nether then loadJunk() end   -- pick up any edits to junk.txt
  valuableCache = {}
  drinkHeld()
  if MODE.nether then dumpJunk(true) end   -- junk picked up on the way home goes down the shaft, not into the dock
  S.ores = 0
  if not (unloadAll() and unpackBox(unloadAll)) then face(0); save(); return false end
  S.loot = nil     -- the loot's with the Foreman now

  local limit = fuelLimit()
  local needBucket = MODE.nether and bucketState() == "none"
  local target = limit ~= math.huge and math.floor(limit * (S.fullAt or FULL_AT) / 100) or 0
  local wantFuel = 0
  -- Only before heading out (needStart given): while he just sits docked he doesn't pester the dock.
  -- Firecrest asks when he's short or hungry (he drinks lava underground); a Canary tops up whenever a
  -- lava bucket's worth is missing.
  local short = needStart and fuel() < needStart
  if MODE.nether then short = short or (needStart and hungry())
  else short = short or (needStart and fuel() <= target - 1000) end
  if needStart and limit ~= math.huge and short then
    wantFuel = math.max(needStart or 0, target) - fuel()
  end
  if needStart and (needBucket or wantFuel > 0) then
    setStatus("docked", needBucket and "Asking the dock for a bucket" or "Asking the dock for fuel")
    local r = askDock(needBucket, wantFuel)
    if r then
      takeSupplies()
      S.dockNote = r.note
    else
      S.dockNote = ("%s didn't answer"):format((MODE.boss:gsub("^t", "T")))
      if wantFuel > 0 then
        -- Fuel put in by hand: take it myself (empty buckets go back in)
        setStatus("docked", "Taking fuel from my dock")
        face(S.dockDir)
        core.fuel.refuelFromDock(S.dockDir, math.max(needStart or 0, target))
      end
    end
  elseif needStart then
    S.dockNote = nil
  end
  face(0)
  save()
  return true
end

-- needStart: fuel needed to head out (one dock: asks for it; two barrels: just refuels)
local function dockService(needStart)
  S.chunky = haveChunky() or nil   -- picked one up (or lost it) since last time?
  if S.dockDir then return dockServiceOne(needStart) end
  return dockServiceTwo()
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

local function askChoice(prompt, options, default)
  while true do
    for i, o in ipairs(options) do print(("  %d) %s"):format(i, o)) end
    write(prompt)
    local a = read()
    if a == "" and default then return default end
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

local DIM_CHOICES = { "allthemodium:mining", "overworld", "the_nether", "the_end" }
local function askDimension()
  local d = askChoice("Dimension [1]: ", { "Mining", "Overworld", "Nether", "End", "Other" }, 1)
  if d == 5 then write("Its name: "); return read() end
  return DIM_CHOICES[d]
end

-- Containers next to me (the four sides and above), as dock directions. Turns all the way round.
local function barrelsAround()
  local found = {}
  for _ = 0, 3 do
    if isContainer(turtle.inspect()) then found[#found + 1] = S.h end
    turnRight()
  end
  if isContainer(turtle.inspectUp()) then found[#found + 1] = "up" end
  return found
end

-- What a moved miner keeps when he sets up again at a new dock (same bird only: a new bird gets a new number)
local KEEP_ON_MOVE = { "num", "totals", "lastHaul", "chests", "capped", "junk", "hungryAt", "fullAt", "rebootDone",
  "lavaFuel", "lavaScoops", "seq", "chunksDone" }

-- First-time setup, or again at a new dock (keep = the old state: number and label stay)
local function setupDock(keep)
  term.clear(); term.setCursorPos(1, 1)
  title(keep and "SETTING UP AT MY NEW DOCK" or "MINER SETUP")
  S = { x = 0, y = 0, z = 0, h = 0, want = "dock", seq = nil, cbc = true }
  print("Which dimension am I in?")
  S.dim = askDimension()
  setMode()
  if keep and modeFor(keep.dim) == MODE_KEY then
    for _, k in ipairs(KEEP_ON_MOVE) do S[k] = keep[k] end
  end
  term.clear(); term.setCursorPos(1, 1)
  title(("I'M A %s HERE"):format(MODE.name:upper()))
  print("I'm sitting on top of my future shaft.")
  if MODE.oneDock then
    print("I need ONE barrel next to me (a side")
    print("or above): my dock, a Dock on")
    print(("%s's cable."):format(MODE.boss))
    if MODE.nether then print("And one empty bucket in my inventory, for lava.") end
  else
    print("I need two barrels next to me (sides or above):")
    print(" - DUMP barrel (empty)")
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
    local found = barrelsAround()
    if MODE.oneDock then
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
  if haveChunky() then print("Chunk controller: I'll keep my chunk loaded.")
  else print("No chunk controller: keep my area loaded.") end
  if boxSlot() then print("Shulker box: extra room for ore.") end
  save()
  if S.num then
    print(("Setup done. I'm still %s."):format(os.getComputerLabel() or ("number " .. S.num)))
    print(("Press START on %s."):format(MODE.boss))
  else
    print(("Setup done. %s gives me a"):format((MODE.boss:gsub("^t", "T"))))
    print("number; pick my layers and press")
    print("START there.")
  end
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
  S.step = 1   -- redo this level of this chunk from its start
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

-- Far from my dock: outside my chunk area (plus one ring), or above the dock (another dock, or another
-- dimension: the Mining Dimension's pads keep X/Z, its surface is at Y 253).
local function farFrom(x, y, z)
  if y > S.home.y + 2 then return true end
  local cx, cz = dockChunk()
  local r = (S.r2 or DEFAULT_R2) + 1
  return math.abs(math.floor(x / 16) - cx) > r or math.abs(math.floor(z / 16) - cz) > r
end

-- Check my counted position against GPS. If I've been carried off nearby, re-learn where I am and
-- which way I face, then wait for an order before going anywhere. Carried far: see movedFlow.
local function checkPosition()
  if not (S.home and S.facing) then return end
  local x, y, z = locate()
  if not x then return end
  local ex, ey, ez = absPos()
  local moved = x ~= ex or y ~= ey or z ~= ez
  if moved and farFrom(x, y, z) then
    S.far, S.farPos = true, { x = x, y = y, z = z }
    save()
    return
  end
  if moved then
    setFromAbs(x, y, z)
    S.lost, S.offPath, S.heldSeq = true, true, S.seq
  end
  S.far, S.farPos = nil, nil
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

local DIM_NAMES = { ["allthemodium:mining"] = "Mining", overworld = "Overworld", the_nether = "Nether", the_end = "End" }

-- Carried far from my dock: never tunnel there. With a barrel next to me I offer to set up here (keeping
-- my number and label); otherwise (or if Tanis says no) I wait to be carried back.
local function movedFlow()
  local x, y, z = locate()
  if x and not farFrom(x, y, z) then          -- carried back near my dock: the usual way home
    S.far, S.farPos = nil, nil
    checkPosition()
    return
  end
  if x then S.farPos = { x = x, y = y, z = z } end
  local here = x and (x .. "," .. y .. "," .. z)
  if here and here ~= S.farDeclined and #barrelsAround() > 0 then
    setStatus("waiting", "Moved to a new dock: confirm on my screen to set up here")
    term.clear(); term.setCursorPos(1, 1)
    title("I'VE BEEN MOVED")
    print(("My dock was at %d %d %d (%s)."):format(S.home.x, S.home.y, S.home.z, DIM_NAMES[S.dim] or tostring(S.dim or "?")))
    print(("I'm at %d %d %d, next to a barrel."):format(x, y, z))
    print("Set up here as my new dock?")
    print(("I stay %s."):format(os.getComputerLabel() or MODE.name))
    if askChoice("> ", { "Yes, set up here", "No, I'll carry you back" }) == 1 then
      setupDock(S)
      fixLabel()
      setStatus("docked", "Set up at my new dock. Waiting for START")
      return
    end
    S.farDeclined = here
    save()
  end
  setStatus("waiting", ("Moved far from my dock. Carry me back to %d %d %d"):format(S.home.x, S.home.y, S.home.z))
  waitCtrl(10)
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
      setStatus("waiting", S.dockDir and ("Dock barrel full. Is %s running?"):format(MODE.boss)
        or "Dump barrel full: empty it")
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
        MODE.nether and ": lava buckets in a stock barrel" or S.dockDir and ": lava buckets in my dock" or ""))
      waitCtrl(15)
      return
    end
  end
  setStatus("mining", "")
  local ok, err = pcall(mineChunks)
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
    if S.far then
      movedFlow()
    elseif S.lost and gpsSeen then
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
    pos = S.far and S.farPos or (px and { x = px, y = py, z = pz }) or nil, far = S.far, dim = S.dim, home = S.home,
    facing = S.facing and COMPASS[(S.facing + (S.h or 0)) % 4], gps = gpsSeen,
    offPath = S.offPath, retired = S.retired, state = S.status, msg = S.msg, seq = S.seq,
    kind = MODE_KEY, bird = MODE.name, chests = S.chests or 0,
    fuel = f, fuelLimit = l, slots = used,
    y = S.dockY and (S.dockY + (S.y or 0)), x = S.x, z = S.z,
    layer = S.layerIdx, layers = S.layerCount, ring = S.chunkRing, minRing = S.r1 or 0, maxRing = S.r2 or DEFAULT_R2,
    cbc = true, chunk = S.ci, chunks = S.chunkCount, chunksDone = S.chunksDone, cell = S.step,
    chunky = S.chunky == true, chunkyNote = S.chunkyNote, swaps = S.swaps,
    box = boxSlot() and (S.boxFull and "full" or "ok") or "none", boxStacks = S.boxStacks,
    minY = S.minY, maxY = S.maxY, want = S.want, rebootDone = S.rebootDone, done = S.done, ores = S.ores, haul = haul,
  }
  m.dockNote, m.oneDock = S.dockNote, S.dockDir ~= nil
  if MODE.nether then
    m.hungry, m.hungryAt, m.fullAt = S.hungry == true, S.hungryAt or HUNGRY_AT, S.fullAt or FULL_AT
    m.bucket, m.lavaFuel, m.lavaScoops = bucketState(), S.lavaFuel or 0, S.lavaScoops or 0
  elseif not S.dockDir then
    m.barrelsLinked, m.linkNote = S.barrelsLinked, S.linkNote
  end
  return m
end

-- Orders only from my own Foreman: cmd.kind names the bird it's for. On tanis-miner (Canaries and Starlings) an
-- order for a Canary must say so, so an old Overworld Foreman can't order the MD's Canaries about.
local function cmdForMe(msg)
  if msg.kind ~= nil then return msg.kind == MODE_KEY end
  return MODE_KEY ~= "canary"
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
    elseif type(msg) == "table" and msg.type == "cmd" and msg.to == me and cmdForMe(msg) then
      ctrl = msg
      if MODE.nether and type(msg.junk) == "table" then
        S.junk = msg.junk; setJunk(S.junk); valuableCache = {}
      end
      local hA, fA = tonumber(msg.hungryAt), tonumber(msg.fullAt)
      if MODE.nether and hA and fA and hA >= 1 and fA <= 99 and hA < fA then S.hungryAt, S.fullAt = hA, fA
      elseif not MODE.nether and fA and fA >= 10 and fA <= 99 then S.fullAt = fA end
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
-- Chunk by chunk since Oct 2026: progress from the old ring miner means nothing now. Start the
-- Foreman's order afresh (forgetting its seq makes the next order count as new).
if not S.cbc then
  S.cbc, S.ci, S.cl, S.step, S.k, S.probedLayer, S.r1, S.r2, S.seq = true, 1, 1, 1, nil, nil, nil, nil, nil
  save()
end
restoreRadio()
pickUpBox()
S.chunky = haveChunky() or nil
save()
if S.chunky then
  print("Chunk controller on board: I keep my own chunk loaded.")
  refreshChunk(true)   -- claim this chunk straight away (after a server restart AP restores it anyway)
end
fixLabel()
print(("I'm a %s (%s)."):format(MODE.name, tostring(S.dim or "overworld")))
setStatus("docked", "Starting")
parallel.waitForAny(mainLoop, netLoop)
