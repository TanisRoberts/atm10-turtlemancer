-- miner_base.lua  --  the miner's basics: who he is (by dimension), junk lists, his saved state, where he is
-- (dock-relative, GPS through the turtle core) and what he must never dig.
-- A part of miner.lua (one shared environment: see there).

STATE_FILE = "miner.state"
STATUS_EVERY = 3      -- seconds between status broadcasts

-- Who I am, by dimension (see the top). r2 = outer CHUNK ring when the Foreman doesn't say (ring 0 =
-- the dock's chunk, ring 3 = 7x7 chunks), reserve = spare fuel kept on top of the trip home,
-- floor = lowest Y a level may reach.
MODES = {
  canary    = { name = "Canary",    protocol = "tanis-miner",  boss = "the MD Foreman",
                r2 = 3, reserve = 150, floor = -64 },
  firecrest = { name = "Firecrest", protocol = "tanis-nether", boss = "the Nether Foreman", nether = true,
                r2 = 1, reserve = 200, floor = 5 },
  starling  = { name = "Starling",  protocol = "tanis-miner",  boss = "the Foreman", isEnd = true, selfServe = true,
                r2 = 3, reserve = 60,  floor = 0 },   -- the End: void under Y 0
}
RING_CAP = 16   -- furthest chunk ring (33x33 chunks)
function modeFor(dim)
  local d = tostring(dim or ""):lower():gsub("^minecraft:", "")
  if d == "the_nether" or d == "nether" then return "firecrest" end
  if d == "the_end" or d == "end" then return "starling" end
  return "canary"
end
-- Set by setMode() once the dimension is known (canary until then)
MODE, MODE_KEY = MODES.canary, "canary"
PROTOCOL, DEFAULT_R2, FUEL_RESERVE = "tanis-miner", 3, 60

-- Firecrest's lava
NETHER_FLOOR = 5      -- lowest Y he mines in the Nether (bedrock below)
HUNGRY_AT = 25     -- % of the tank: start drinking lava (the Nether Foreman can change these)
FULL_AT = 75     -- % of the tank: stop drinking
DRINK_STEPS = 48     -- most cells he walks into while drinking one pool
BUCKET, LAVA_BUCKET = "minecraft:bucket", "minecraft:lava_bucket"

-- Canary/Starling: things that count as junk live in junk.txt (one item per line, # for comments).
-- Junk is carried home while storage still wants it (under its cap), up to 4 slots, else dumped.
-- Edit junk.txt any time: it's re-read every time he docks.
-- Firecrest: the Nether Foreman sends his junk list (DEFAULT_NETHER_JUNK until it does); junk.txt
-- isn't used in the Nether, and junk never comes home from there.
JUNK_FILE = "junk.txt"
DEFAULT_JUNK = [[
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
DEFAULT_NETHER_JUNK = { "netherrack", "blackstone", "basalt", "smooth_basalt", "soul_sand", "soul_soil",
  "magma_block", "gravel", "crimson_nylium", "warped_nylium", "nether_wart_block", "warped_wart_block",
  "cobblestone", "cobbled_deepslate", "polished_blackstone_bricks" }
JUNK, KEEP = {}, {}
function loadJunk()
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
function setJunk(list)
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
S = {}
function save()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize(S))
  f.close()
end
function loadState()
  if not fs.exists(STATE_FILE) then return end
  local f = fs.open(STATE_FILE, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  if type(t) == "table" then S = t end
  -- A dimension typed by hand ("Mining Dimension") is the Mining Dimension
  if type(S.dim) == "string" and not S.dim:find(":") and S.dim:lower():find("mining") then S.dim = "allthemodium:mining" end
end
-- Does he know his dock barrel? (A save from the old two-barrel dock doesn't count: he sets up again.)
function knowsDock() return S.dockDir ~= nil end

-- Pick Canary / Firecrest / Starling from the dimension, and load the right junk list
function setMode()
  MODE_KEY = modeFor(S.dim)
  MODE = MODES[MODE_KEY]
  PROTOCOL, DEFAULT_R2, FUEL_RESERVE = MODE.protocol, MODE.r2, MODE.reserve
  if MODE.nether then setJunk(S.junk) else loadJunk() end
end

ctrl = nil -- latest command from the panel (set by the network loop)

function fuel() return core.fuel.level() end
function fuelLimit() return core.fuel.limit() end

lastShown = ""
function setStatus(st, msg)
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
COMPASS = { [0] = "north", "east", "south", "west" }

-- Rotate a flat offset by f quarter turns clockwise (north -> east)
function rot(x, z, f)
  for _ = 1, f % 4 do x, z = -z, x end
  return x, z
end

function absPos()
  if not (S.home and S.facing) then return nil end
  local ax, az = rot(S.x, S.z, S.facing)
  return S.home.x + ax, S.home.y + S.y, S.home.z + az
end

function setFromAbs(x, y, z)
  local rx, rz = rot(x - S.home.x, z - S.home.z, 4 - S.facing)
  S.x, S.y, S.z = rx, y - S.home.y, rz
end

gpsSeen = false
-- Where GPS says I am NOW (a stale fix from core.gps doesn't count), or nil
function locate()
  local ok, x, y, z, stale = core.gps.locate(2)
  if ok and not stale then
    gpsSeen = true
    return x, y, z
  end
end

function dirOf(dx, dz)
  if dz < 0 then return 0 elseif dx > 0 then return 1 elseif dz > 0 then return 2 elseif dx < 0 then return 3 end
end

-- Blocks I never dig. ComputerCraft lets a turtle mine another turtle (it ends up as an item in
-- my bag), and a pickaxe happily breaks storage cables, so:
--   * another turtle in my way: I wait for it to move on (isTurtle)
--   * a cable, pipe, modem, computer, barrel, hopper, ender chest or storage block (anything
--     isProtected): it isn't going anywhere, so I go round it, one block under it (or over, if under
--     won't work), and never dig it. Barrels and hoppers are how Tanis's storage is wired (chests
--     don't take modems); the loot underground is in chests, which I empty and dig (isLootable).
KEEP_MODS = { "computercraft:", "refinedstorage:", "pipez:", "laserio:", "integrateddynamics:",
  "integratedtunnels:", "xnet:", "prettypipes:", "modularrouters:", "functionalstorage:",
  "sophisticatedstorage:", "storagedrawers:", "enderstorage:" }
KEEP_WORDS = { "cable", "pipe", "conduit", "transporter", "duct", "pressurized_tube", "conductor",
  "barrel", "hopper", "ender_chest" }
function blockName(ok, d)
  if ok == true and type(d) == "table" and type(d.name) == "string" then return d.name end
end
function isTurtle(ok, d)
  local n = blockName(ok, d)
  return n ~= nil and n:find("^computercraft:turtle") ~= nil
end
function isProtected(ok, d)
  local n = blockName(ok, d)
  if not n then return false end
  for _, p in ipairs(KEEP_MODS) do if n:sub(1, #p) == p then return true end end
  -- AE2: everything placed (cables, buses, drives ...), but not meteorites or certus quartz
  if n:sub(1, 4) == "ae2:" and not (n:find("quartz") or n:find("sky_stone") or n:find("mysterious")) then return true end
  for _, w in ipairs(KEEP_WORDS) do if n:find(w, 1, true) then return true end end
  return false
end
isMachine = isProtected -- old name

-- A chest, shulker box or any other inventory that isn't protected: empty it before digging it.
PSIDE = { f = "front", u = "top", d = "bottom" }
function isLootable(kind, ok, d)
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
function compassByStep(allowDig)
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

