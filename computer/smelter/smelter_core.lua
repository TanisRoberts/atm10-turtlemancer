-- smelter_core.lua  --  smelter: constants, the saved config, shared state and small helpers (furnace names, tiers, storage link)
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local SMELT_FILE    = "smelt.txt"
local CONFIG        = "smelter.cfg"
local BASE          = "tanis-base"
local TICK          = 4       -- seconds between smelting passes
local REPLY_WAIT    = 8       -- seconds to wait for storage to carry out a batch
local STALE         = 15      -- storage figures older than this aren't trusted
local TEXT_SCALE    = 0.5
local FRAME         = 0.25    -- animation frame time
local TRAIN_TIMEOUT = 40      -- seconds with fuel in and nothing cooked = it doesn't smelt
local FIND_TIME     = 60      -- seconds "Find it" waits for an item to be dropped in
local CHUNK         = 8       -- work is handed out 8 items (one coal) at a time
local TOPUP_AT      = 32      -- a busy furnace gets more of the same once it's down to this
-- The factory code keeps its names in one table: CC's Lua (Cobalt) counts a file's top-level
-- locals together with each function's, and stops at 200
local FX = {}
FX.FACTORY_BUFFER = 3     -- batches per process kept queued at a factory (feed barrel + its inputs)
FX.direct = require("direct") -- direct or via dust, and the hand-added list (computer/smelter/direct.lua)
FX.ts = require("trainsafe") -- config save/load that survives a power cut, training recovery (computer/smelter/trainsafe.lua)
FX.drip = require("drip") -- the drip trial's decisions (computer/smelter/drip.lua)
FX.kit = require("ui")    -- the UI kit's motion: ui.beat, ui.anim (ANIM=full|calm|off in smelter.env)
FX.FALLBACK_AFTER = 300   -- seconds every factory can be down before ore goes to the furnaces again
FX.STUCK_AFTER    = 120   -- seconds with ore waiting and nothing moving = that factory is stuck
FX.MISSING_AFTER  = 10    -- seconds a factory can be unseen before the screen says "factory missing, re-add it"
FX.IDLE_FOR       = 3     -- seconds a factory has to be empty before a drip trial may start on it
FX.LEFTOVER_WAIT  = 600   -- an odd few ore (less than a batch) go to the furnaces after this long

local K = colours

-- Fuel, best first, and how many items one of it smelts
local SMELT_FUELS = { "minecraft:charcoal", "minecraft:coal", "minecraft:coal_block", "minecraft:blaze_rod" }
local FUEL_VALUE  = { ["minecraft:charcoal"] = 8, ["minecraft:coal"] = 8, ["minecraft:coal_block"] = 80,
                      ["minecraft:blaze_rod"] = 12 }

-- Furnace tiers (Iron Furnaces default cook times, ticks per item; vanilla = 200).
-- Iron Furnaces burn fuel at the same rate per item as a plain furnace, so 1 coal = 8 items everywhere.
--   { name starts with, label, ticks, band colour, text colour, short label }
local TIERS = {
  { "unobtainium",  "UNOBTAINIUM",  1,   K.magenta,   K.white, "UNOBTN" },
  { "vibranium",    "VIBRANIUM",    3,   K.green,     K.white, "VIBRAN" },
  { "allthemodium", "ALLTHEMODIUM", 5,   K.yellow,    K.black, "ATM" },
  { "netherite",    "NETHERITE",    5,   K.brown,     K.white, "NETHER" },
  { "obsidian",     "OBSIDIAN",     20,  K.purple,    K.white, "OBSIDN" },
  { "rainbow",      "RAINBOW",      20,  K.red,       K.white, "RAINBW" },
  { "million",      "MILLION",      20,  K.red,       K.white, "MILLON" },
  { "emerald",      "EMERALD",      40,  K.lime,      K.black, "EMERLD" },
  { "crystal",      "CRYSTAL",      40,  K.pink,      K.black, "CRYSTL" },
  { "diamond",      "DIAMOND",      80,  K.lightBlue, K.black, "DIAMND" },
  { "gold",         "GOLD",         120, K.yellow,    K.black, "GOLD" },
  { "silver",       "SILVER",       140, K.white,     K.black, "SILVER" },
  { "iron",         "IRON",         160, K.lightGrey, K.black, "IRON" },
  { "copper",       "COPPER",       180, K.orange,    K.black, "COPPER" },
}
local STONE_TIER = { "furnace", "FURNACE", 200, K.grey, K.white, "STONE" }

---------------------------------------------------------------------------
-- Saved settings: smelter.cfg
--   trainer = network name of the training furnace (never part of the array)
--   paused  = true: nothing new goes into the furnaces (finished items still come out)
--   learned = { [key] = { out, inputs = { name... }, per = { [input] = outputs per input }, at } }
--   speed   = { [furnace] = { t = seconds busy, n = items cooked } }  (measured)
--   factories = { { machine, feed, out }, ... }  (enriching factories, see the top)
--   enrich  = { [ore] = { out = dust, used = ore in, made = dust out, drip = true, at } or { no = true, at }
--               (direct = the product is what the furnace makes from it too: no dust check;
--               dustBad = its dust didn't smelt; drip = used counts ore for ONE process, learned by a drip trial)
--   trialSaved = { [machine] = { eject, sort, at } }  only while a drip trial runs: the factory's settings to
--               put back (also after a reboot)
--   dripProgress = true: a drip trial tells "a process started" by getRecipeProgress, not by waiting an operation
---------------------------------------------------------------------------
local cfg = { trainer = nil, paused = false, learned = {}, speed = {}, factories = {}, enrich = {} }
local function loadCfg()
  local t, from, bad = FX.ts.load(CONFIG)
  if t then for k, v in pairs(t) do cfg[k] = v end end
  FX.cfgNote = bad and "smelter.cfg was unreadable: kept as smelter.cfg.bad" or from and ("smelter.cfg restored from " .. from) or nil
  if type(cfg.learned) ~= "table" then cfg.learned = {} end
  if type(cfg.speed) ~= "table" then cfg.speed = {} end
  if type(cfg.factories) ~= "table" then cfg.factories = {} end
  if type(cfg.enrich) ~= "table" then cfg.enrich = {} end
  if type(cfg.enrichExtra) ~= "table" then cfg.enrichExtra = {} end
end
local function saveCfg()
  FX.ts.save(CONFIG, cfg)
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
S.byName = {}            -- item totals in storage (from the storage computer's broadcast)
S.storageId, S.storageSeen = nil, nil
local smeltQueue
S.smeltRules, smeltQueue = {}, {}
S.smeltNote = "Starting"
S.array = {}             -- the smelting furnaces, fastest first (never the trainer)
S.fstate = {}            -- furnace -> { inp, fuel, out } as last read
S.lastCmd = nil          -- seq of the last chat command taken, so the mainframe stops repeating it
S.picking = nil          -- "Find it" for the trainer: { untilT, before = { [fz] = count } }
S.book = {}              -- recipe key -> { key, out, inputs, pattern, per, builtin, learned }

local function call(name, method, ...)
  local ok, a, b = pcall(peripheral.call, name, method, ...)
  if ok then return a, b end
  return nil, a
end

local function shortName(id) return (tostring(id):gsub("^[^:]*:", "")) end
local function pretty(id) return (shortName(id):gsub("_", " ")) end
local function fmtNum(n)
  n = math.floor(n or 0)
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e4 then return ("%dk"):format(math.floor(n / 1e3)) end
  local s = tostring(n)
  return n >= 1000 and (s:sub(1, -4) .. "," .. s:sub(-3)) or s
end

-- Same rule as storage: furnaces and Iron Furnaces smelt; blast furnaces and smokers are left alone
local function isFurnace(n)
  return n:find("furnace") ~= nil and not n:find("blast") and not n:find("smoker")
end

local function tierOf(n)
  local path = shortName(n)
  for _, t in ipairs(TIERS) do if path:sub(1, #t[1]) == t[1] then return t end end
  return STONE_TIER
end

-- Seconds per item: measured once it has cooked enough, else the tier's default
local function spiOf(fz)
  local sp = cfg.speed[fz]
  if sp and sp.n >= 24 and sp.t > 0 then return sp.t / sp.n, true end
  return tierOf(fz)[3] / 20, false
end

-- furnace_2 before furnace_10
local function natLess(a, b)
  local pa, na = a:match("^(.-)(%d*)$")
  local pb, nb = b:match("^(.-)(%d*)$")
  if pa ~= pb then return pa < pb end
  return (tonumber(na) or -1) < (tonumber(nb) or -1)
end

-- Every furnace on the cable, fastest tier first
local function allFurnaces()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if isFurnace(n) and peripheral.hasType(n, "inventory") then out[#out + 1] = n end
  end
  table.sort(out, function(a, b)
    local ta, tb = tierOf(a)[3], tierOf(b)[3]
    if ta ~= tb then return ta < tb end
    return natLess(a, b)
  end)
  return out
end

local function findFurnaces()
  local out = {}
  for _, n in ipairs(allFurnaces()) do if n ~= cfg.trainer then out[#out + 1] = n end end
  table.sort(out, function(a, b)
    local sa, sb = spiOf(a), spiOf(b)
    if math.abs(sa - sb) > 1e-6 then return sa < sb end
    return natLess(a, b)
  end)
  S.array = out
end

local function readOne(fz)
  local l = call(fz, "list")
  if type(l) ~= "table" then return nil end
  return { inp = l[1], fuel = l[2], out = l[3] }
end

---------------------------------------------------------------------------
-- Recipe book: built in + learned (learned inputs join a recipe with the same output)
---------------------------------------------------------------------------
local function sortedKeys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end

local inbox = {}             -- smelt_done replies from storage
local batchN = 0

local function storageFresh() return S.storageId and S.storageSeen and os.clock() - S.storageSeen < STALE end

local function sendBatch(ops)
  batchN = batchN + 1
  local id = os.epoch("utc") * 100 + batchN % 100
  rednet.send(S.storageId, { type = "smelt_ops", id = id, ops = ops }, BASE)
  local t = os.clock() + REPLY_WAIT
  while os.clock() < t do
    for i, m in ipairs(inbox) do
      if m.id == id then table.remove(inbox, i); return m.results end
    end
    os.sleep(0.25)
  end
end

local function redraw() os.queueEvent("smelter_draw") end
FX.notify = function() end   -- set once the screens exist: a notice on both screens

S.BASE, S.CHUNK, S.FIND_TIME, S.FRAME, S.FUEL_VALUE, S.FX = BASE, CHUNK, FIND_TIME, FRAME, FUEL_VALUE, FX
S.K, S.SMELT_FILE, S.SMELT_FUELS, S.TEXT_SCALE, S.TICK, S.TOPUP_AT = K, SMELT_FILE, SMELT_FUELS, TEXT_SCALE, TICK, TOPUP_AT
S.TRAIN_TIMEOUT, S.allFurnaces, S.call, S.cfg, S.findFurnaces, S.fmtNum = TRAIN_TIMEOUT, allFurnaces, call, cfg, findFurnaces, fmtNum
S.has, S.inbox, S.isFurnace, S.pretty, S.readOne, S.redraw = has, inbox, isFurnace, pretty, readOne, redraw
S.saveCfg, S.sendBatch, S.shortName, S.smeltQueue, S.sortedKeys, S.spiOf = saveCfg, sendBatch, shortName, smeltQueue, sortedKeys, spiOf
S.storageFresh, S.tierOf, S.loadCfg = storageFresh, tierOf, loadCfg
end
