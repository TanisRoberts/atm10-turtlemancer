-- weaver_base.lua  --  Weaver's basics: files, saved state, headings, what he may dig, status.
-- A part of weaver.lua (one shared environment: see there).

PROTOCOL   = "tanis-weaver"
STATE_FILE = "weaver.state"
CFG_FILE   = "weaver.cfg"
GAPS_FILE  = "weaver.gaps"       -- cells skipped for want of a block: { {x,y,z,name}, ... }
GAPLIST    = "weaver.gaplist"    -- the Architect's working area for filling gaps
SLOT_BLOCKS = 12                 -- slots a batch of blocks may use (1 = chunk controller, 3 spare for fuel)
STACK = 64
STATUS_EVERY = 3
DX = { [0] = 0, 1, 0, -1 }       -- heading 0 north (-z), 1 east, 2 south, 3 west
DZ = { [0] = -1, 0, 1, 0 }
HEAD = { north = 0, east = 1, south = 2, west = 3 }
HNAME = { [0] = "north", "east", "south", "west" }

-- Tunables (weaver.env, made on first boot; edits are picked up live)
ENV = require("envfile").new("weaver.env", "Weaver settings.", {
  { "FUEL_TARGET", 20000, "top the tank up to this at a dock visit" },
  { "FUEL_LOW", 3000, "ask storage for fuel when under this" },
  { "SUPPLY_WAIT", 30, "seconds to wait for what storage says it sent to arrive in the chest" },
})
ENV.load()

function readT(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  return type(t) == "table" and t or nil
end
function writeT(path, t)
  local f = fs.open(path, "w"); f.write(textutils.serialize(t)); f.close()
end

C = readT(CFG_FILE)               -- { dh = heading at the dock }
S = readT(STATE_FILE) or {}       -- see start(): n, arch, build, hash, total, layer, idx, work, x y z h, want ...
S.short = S.short or {}
S.skip = S.skip or {}
S.orderSeq = S.orderSeq or 0
S.supSeq = S.supSeq or 0
S.topY = S.topY or -1
function save() writeT(STATE_FILE, S) end

GAPS = readT(GAPS_FILE) or {}
function saveGaps() writeT(GAPS_FILE, GAPS) end

-- Blocks of the build are never dug (names of every cell he has held)
BUILD = {}
-- What he may clear out of his way: natural blocks only
NATURAL = {}
for _, n in ipairs({ "stone", "dirt", "grass_block", "coarse_dirt", "podzol", "mud", "sand", "red_sand", "gravel",
  "sandstone", "red_sandstone", "clay", "terracotta", "deepslate", "andesite", "granite", "diorite", "tuff",
  "netherrack", "snow", "snow_block", "short_grass", "tall_grass", "fern", "dead_bush", "cactus", "sugar_cane",
  "kelp", "seagrass", "vine", "rooted_dirt", "moss_block", "moss_carpet" }) do NATURAL["minecraft:" .. n] = true end
PROTECTED = { "turtle", "computer", "modem", "cable", "pipe", "chest", "barrel", "hopper", "ender", "drawer",
  "controller", "bedrock", "duct", "conduit" }
function canDig(name)
  name = tostring(name)
  for _, p in ipairs(PROTECTED) do if name:find(p, 1, true) then return false end end
  if BUILD[name] then return false end
  return NATURAL[name] == true or name:find("_leaves$") ~= nil
end

function fuelLevel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

function setStatus(st, msg)
  S.status, S.msg = st, msg
  term.clear(); term.setCursorPos(1, 1)
  print((os.getComputerLabel() or "Weaver") .. "  " .. tostring(st))
  if msg then print(msg) end
  if S.build then print(("%s  layer %s/%s  cell %s"):format(S.build, tostring(S.layer), tostring(S.total or "?"), tostring(S.idx))) end
  print(("At %d %d %d  fuel %s  gaps %d"):format(S.x or 0, S.y or 0, S.z or 0, tostring(fuelLevel()), #GAPS))
end
