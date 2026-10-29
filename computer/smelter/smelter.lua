-- smelter.lua  --  the auto-smelting computer (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Hardware:
--   * A computer with a WIRED modem on the storage cable network (so it can see the furnaces).
--     It talks to the storage computer over the same cable; storage passes its news on to the
--     mainframe. A wireless/ender modem as well is fine but not needed.
--   * Furnaces (vanilla + every Iron Furnaces tier) on the storage cable. Blast furnaces/smokers are ignored.
--   * Optional: an advanced monitor touching the computer (tuned for 3 wide x 2 tall = 57x24).
--     The computer's own screen shows the same thing (click with the mouse, type commands).
--
-- The smelter decides WHAT to smelt and WHERE; the storage computer does every item move (it's the
-- only computer that touches storage), so the two never fight over the same barrels.
--
-- Which furnace: the fastest one that would finish the batch soonest. Iron Furnaces tiers are
-- ranked by their cook time (netherite before diamond before iron before a plain furnace), and
-- each furnace's real speed is measured as it works (speed augments, changed configs), so the best
-- furnaces get the work first and the slow ones only join in when there's plenty to go round.
--
-- Rules (smelt.txt, or tap a rule / a recipe on the screen):
--   "stone 20"  keep 20 stacks of stone          "iron all"  smelt every bit of raw iron that comes in
-- One-off jobs: "smelt stone 400" typed here, the rule page's Smelt now buttons, or chat "island smelt stone 400".
--
-- TRAINING: assign one furnace (somewhere out of the way, on the storage cable) as the trainer. It's
-- never part of the smelting array. Put a raw item in its top slot, tap TRAIN: the smelter fuels it,
-- waits for the first one to cook, and learns "this goes in, that comes out". Then pick a rule for it
-- (keep N stacks / smelt all / just learn it). Leftovers and the cooked item go back to storage.
-- Learned recipes live in smelter.cfg; the Recipes page lists everything it knows.
--
-- FACTORIES (ore doubling, Oct 2026): a Mekanism enriching factory (or chamber) set up as
--   feed barrel (on the cable, with a hopper upgrade pushing into one of the factory's Input faces)
--   -> factory (wired modem on it, so I can read it) -> auto-eject into an out barrel (on the cable).
-- Add one on the Factories page (or: factory add <machine> <feed> <out>). Storage fills the feed
-- barrel, treats the out barrel like an input chest, and never stores anything in either.
-- Raw ore with a factory route goes to the factories (whole batches: what a drip trial used, per process) instead of the
-- furnaces, and its dust is smelted. A new ore is tried once with a drip trial (drip.lua): one item at a
-- time until a process starts, eject off so I can read what comes out, eject back on. The dust is then checked in
-- the training furnace (it has to smelt into the same thing), and from then on that ore is enriched.
-- If every factory is down (gone, no power, stuck) for 5 minutes, ore goes to the furnaces again.

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

local DEFAULT_SMELT = [[
# Auto-smelting. One rule per line, # for comments. Edits are picked up within 30 seconds.
# The smelter screen writes this file too (tap a rule, or a recipe on the Recipes page).
#   <item> <stacks>   keep that many stacks in storage, e.g.  stone 20
#   <item> all        smelt everything of it that comes in, e.g.  iron all
# Items: anything on the Recipes page (built in, or taught with the training furnace), or any
# modded metal by name (e.g. "osmium all" smelts raw osmium into ingots).
]]

-- Built in. Anything else: teach it with the training furnace.
local BUILTIN = {
  stone              = { out = "minecraft:stone",              inputs = { "minecraft:cobblestone" } },
  smooth_stone       = { out = "minecraft:smooth_stone",       inputs = { "minecraft:stone" } },
  deepslate          = { out = "minecraft:deepslate",          inputs = { "minecraft:cobbled_deepslate" } },
  glass              = { out = "minecraft:glass",              inputs = { "minecraft:sand", "minecraft:red_sand" } },
  iron               = { out = "minecraft:iron_ingot",         inputs = { "minecraft:raw_iron" } },
  gold               = { out = "minecraft:gold_ingot",         inputs = { "minecraft:raw_gold" } },
  copper             = { out = "minecraft:copper_ingot",       inputs = { "minecraft:raw_copper" } },
  charcoal           = { out = "minecraft:charcoal",           pattern = "_log$" },
  brick              = { out = "minecraft:brick",              inputs = { "minecraft:clay_ball" } },
  terracotta         = { out = "minecraft:terracotta",         inputs = { "minecraft:clay" } },
  cracked_stone_bricks = { out = "minecraft:cracked_stone_bricks", inputs = { "minecraft:stone_bricks" } },
  smooth_sandstone   = { out = "minecraft:smooth_sandstone",   inputs = { "minecraft:sandstone" } },
  smooth_quartz      = { out = "minecraft:smooth_quartz",      inputs = { "minecraft:quartz_block" } },
  nether_brick       = { out = "minecraft:nether_brick",       inputs = { "minecraft:netherrack" } },
  netherite_scrap    = { out = "minecraft:netherite_scrap",    inputs = { "minecraft:ancient_debris" } },
  dried_kelp         = { out = "minecraft:dried_kelp",         inputs = { "minecraft:kelp" } },
  green_dye          = { out = "minecraft:green_dye",          inputs = { "minecraft:cactus" } },
  sponge             = { out = "minecraft:sponge",             inputs = { "minecraft:wet_sponge" } },
  plastic            = { out = "industrialforegoing:plastic",  inputs = { "industrialforegoing:dryrubber" } },
}
local ALIASES = { iron_ingot = "iron", gold_ingot = "gold", copper_ingot = "copper" }

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
local byName = {}            -- item totals in storage (from the storage computer's broadcast)
local storageId, storageSeen = nil, nil
local smeltRules, smeltQueue = {}, {}
local smeltNote = "Starting"
local array = {}             -- the smelting furnaces, fastest first (never the trainer)
local fstate = {}            -- furnace -> { inp, fuel, out } as last read
local lastCmd = nil          -- seq of the last chat command taken, so the mainframe stops repeating it
local picking = nil          -- "Find it" for the trainer: { untilT, before = { [fz] = count } }
local book = {}              -- recipe key -> { key, out, inputs, pattern, per, builtin, learned }

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
  array = out
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

local function buildBook()
  book = {}
  for _, k in ipairs(sortedKeys(BUILTIN)) do
    local r = BUILTIN[k]
    local inputs = {}
    for _, i in ipairs(r.inputs or {}) do inputs[#inputs + 1] = i end
    book[k] = { key = k, out = r.out, inputs = inputs, pattern = r.pattern, per = {}, builtin = true }
  end
  for _, k in ipairs(sortedKeys(cfg.learned)) do
    local l = cfg.learned[k]
    if type(l) == "table" and type(l.out) == "string" then
      local host
      for _, bk in ipairs(sortedKeys(book)) do if book[bk].out == l.out then host = book[bk]; break end end
      if not host then
        host = { key = k, out = l.out, inputs = {}, per = {} }
        book[k] = host
      end
      host.learned = true
      host.learnedAt = math.max(host.learnedAt or 0, l.at or 0)
      for _, i in ipairs(l.inputs or {}) do
        if not has(host.inputs, i) then host.inputs[#host.inputs + 1] = i end
        host.per[i] = (l.per or {})[i] or 1
      end
    end
  end
end

local function isInputOf(r, name)
  if has(r.inputs, name) then return true end
  return r.pattern ~= nil and name:find(r.pattern) ~= nil
end
local function perOf(r, input) return (r.per and r.per[input]) or 1 end

-- Find (or make up) the recipe for a word like "stone", "iron", "tin", "beef" or "raw_tin"
local function recipeFor(word)
  word = tostring(word):lower():gsub("^minecraft:", "")
  word = ALIASES[word] or word
  if book[word] then return word, book[word] end
  local keys = sortedKeys(book)
  local tries = { word, word .. "_ingot", "raw_" .. word, "cooked_" .. word }
  for _, t in ipairs(tries) do
    for _, k in ipairs(keys) do
      local r = book[k]
      if r.out == t or shortName(r.out) == t then return k, r end
    end
    for _, k in ipairs(keys) do
      for _, i in ipairs(book[k].inputs) do
        if i == t or shortName(i) == t then return k, book[k] end
      end
    end
  end
  -- Modded metals: raw_<x> -> <x>_ingot, in any mod
  return word, { key = word, out = ":" .. word .. "_ingot", modded = true, pattern = ":raw_" .. word .. "$", inputs = {}, per = {} }
end

local function outMatches(r, name)
  if r.modded then return name:find(r.out, 1, true) ~= nil end
  return name == r.out
end
local function outCount(r)
  if not r.modded then return byName[r.out] or 0 end
  local c = 0
  for name, n in pairs(byName) do if outMatches(r, name) then c = c + n end end
  return c
end

-- Best input item in storage for a recipe (the one we have most of)
local function inputFor(r, have)
  have = have or byName
  local best, bestN = nil, 0
  for _, name in ipairs(r.inputs) do
    if (have[name] or 0) > bestN then best, bestN = name, have[name] end
  end
  if r.pattern then
    for name, n in pairs(have) do
      if name:find(r.pattern) and n > bestN then best, bestN = name, n end
    end
  end
  return best, bestN
end
local function inputTotal(r)
  local n = 0
  for name, c in pairs(byName) do if isInputOf(r, name) then n = n + c end end
  return n
end

---------------------------------------------------------------------------
-- Rules (smelt.txt)
---------------------------------------------------------------------------
local lastSmeltLoad = -100
local function readSmeltFile()
  if not fs.exists(SMELT_FILE) then
    local f = fs.open(SMELT_FILE, "w"); f.write(DEFAULT_SMELT); f.close()
  end
  local f = fs.open(SMELT_FILE, "r"); local text = f.readAll() or ""; f.close()
  return text
end

local function loadSmeltRules()
  local rules = {}
  for line in readSmeltFile():gmatch("[^\r\n]+") do
    local word, amount = line:gsub("#.*", ""):match("^%s*(%S+)%s+(%S+)%s*$")
    if word then
      local name, r = recipeFor(word)
      if amount:lower() == "all" then rules[#rules + 1] = { name = name, r = r, all = true }
      elseif tonumber(amount) then rules[#rules + 1] = { name = name, r = r, stacks = tonumber(amount) } end
    end
  end
  smeltRules = rules
  lastSmeltLoad = os.clock()
end

local function ruleFor(key)
  for _, rule in ipairs(smeltRules) do if rule.name == key then return rule end end
end

-- Write one recipe's rule into smelt.txt (mode "keep" / "all", or nil = no rule). Comments stay.
local function setRule(key, mode, stacks)
  local text = readSmeltFile()
  local out, done = {}, false
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local word = line:gsub("#.*", ""):match("^%s*(%S+)%s+%S+%s*$")
    if word and recipeFor(word) == key then
      if mode and not done then
        out[#out + 1] = mode == "all" and (key .. " all") or (key .. " " .. math.floor(stacks))
        done = true
      end
    else
      out[#out + 1] = line
    end
  end
  while #out > 0 and out[#out]:match("^%s*$") do out[#out] = nil end
  if mode and not done then out[#out + 1] = mode == "all" and (key .. " all") or (key .. " " .. math.floor(stacks)) end
  local f = fs.open(SMELT_FILE, "w"); f.write(table.concat(out, "\n") .. "\n"); f.close()
  loadSmeltRules()
end

local function queueSmelt(word, amount)
  local name, r = recipeFor(word)
  smeltQueue[#smeltQueue + 1] = { name = name, r = r, left = amount, total = amount }
  return name
end

-- Teach the book a recipe. Returns its key and whether it was already known.
local function learn(input, out, per)
  for _, k in ipairs(sortedKeys(book)) do
    local r = book[k]
    if r.out == out and isInputOf(r, input) and perOf(r, input) == per then return k, true end
  end
  local key
  for _, k in ipairs(sortedKeys(cfg.learned)) do if cfg.learned[k].out == out then key = k; break end end
  if not key then
    for _, k in ipairs(sortedKeys(book)) do if book[k].out == out then key = k; break end end
  end
  if not key then
    local base = shortName(out)
    key = base
    local n = 2
    while book[key] or cfg.learned[key] do key = base .. "_" .. n; n = n + 1 end
  end
  local l = cfg.learned[key]
  if not l then l = { out = out, inputs = {}, per = {} }; cfg.learned[key] = l end
  if not has(l.inputs, input) then l.inputs[#l.inputs + 1] = input end
  l.per[input] = per
  l.at = os.epoch("utc")
  saveCfg()
  buildBook()
  loadSmeltRules()
  return key, false
end

local function forget(key)
  local r = book[key]
  if not r then return end
  for _, k in ipairs(sortedKeys(cfg.learned)) do
    if cfg.learned[k].out == r.out then cfg.learned[k] = nil end
  end
  saveCfg()
  buildBook()
  if not book[key] and ruleFor(key) then setRule(key, nil) end
  loadSmeltRules()
end

---------------------------------------------------------------------------
-- Talking to storage
---------------------------------------------------------------------------
local inbox = {}             -- smelt_done replies from storage
local batchN = 0

local function storageFresh() return storageId and storageSeen and os.clock() - storageSeen < STALE end

local function sendBatch(ops)
  batchN = batchN + 1
  local id = os.epoch("utc") * 100 + batchN % 100
  rednet.send(storageId, { type = "smelt_ops", id = id, ops = ops }, BASE)
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

---------------------------------------------------------------------------
-- Factories: Mekanism enriching factories fed through a barrel (see the top of the file)
--   Mekanism machines are read-only over the cable (CC asks for their slots with no side, and
--   Mekanism makes that read-only), so items go in through the feed barrel's hopper upgrade and come
--   out by auto-eject into the out barrel. I only read them (getInput/getOutput) and set eject.
---------------------------------------------------------------------------
FX.facs = {}              -- factory index -> what I last read (see FX.readFactory)
FX.dustQueue = {}         -- dust -> output it should smelt into: waiting for the trainer to check it
FX.autoTried = {}         -- dust -> when I last put one in the trainer to check it
FX.leftoverSince = {}     -- ore -> since when there's been less than a batch of it
FX.trialCool = {}         -- ore -> when a try gave nothing (don't try again for a while)
FX.shortSince = {}        -- keep-N recipe -> since when it's been short (counts lag a few seconds,
                             -- so ore only goes out for a shortfall that lasts)

-- Could this be a factory? Mekanism machines answer getInput/getOutput/getRecipeProgress
function FX.factoryLike(n)
  if peripheral.hasType(n, "inventory") then return false end
  local ok, m = pcall(peripheral.getMethods, n)
  if not ok or type(m) ~= "table" then return false end
  local h = {}
  for _, x in ipairs(m) do h[x] = true end
  return (h.getInput and h.getOutput and h.getRecipeProgress) and true or false
end

-- Raw ore or an ore block: worth trying in a factory
function FX.isOreish(name)
  return (name:find(":raw_[%w_]+$") ~= nil and not name:find("_block$")) or name:find("_ore$") ~= nil
    or name:find(":ancient_debris$") ~= nil
end

-- Worth a factory trial: an ore, or something added by hand (enrich add)
function FX.trialable(name)
  return FX.isOreish(name) or FX.direct.isExtra(cfg.enrichExtra, name)
end

function FX.factoryName(i) return "Factory " .. i end
-- One batch for every process: what a drip trial used x the factory's processes. (Entries learned
-- before the drip trial count a whole batch of 3 per process.)
function FX.procsOf(i) return (FX.facs[i] and FX.facs[i].procs) or 3 end
function FX.unitOf(i, ore)
  local e = ore and cfg.enrich[ore]
  local used = (type(e) == "table" and e.drip and e.used) or 3
  return math.max(1, used) * FX.procsOf(i)
end

function FX.readItem(it, into)
  if type(it) == "table" and it.name and it.name ~= "minecraft:air" and (it.count or 0) > 0 then
    into[it.name] = (into[it.name] or 0) + it.count
    return it.count
  end
  return 0
end

-- Read one factory: its inputs/outputs, its feed barrel, power; works out whether it's up
function FX.readFactory(i)
  local f = cfg.factories[i]
  local s = FX.facs[i]
  if not s or s.machine ~= f.machine then s = { machine = f.machine, lastMove = os.clock() }; FX.facs[i] = s end
  local why
  if not peripheral.isPresent(f.machine) then
    s.unseenSince = s.unseenSince or os.clock()
    why = os.clock() - s.unseenSince >= FX.MISSING_AFTER and "factory missing, re-add it" or "can't see the factory"
    if why ~= "can't see the factory" and not s.missingNoted then
      s.missingNoted = true
      local cand = FX.machineCandidates()[1]
      local text = ("%s: %s is gone: factory missing, re-add it%s"):format(FX.factoryName(i), shortName(f.machine),
        cand and (" (found " .. cand .. ": factory add " .. cand .. " " .. f.feed .. " " .. f.out .. ")") or "")
      print(text)
      FX.notify(("%s missing: re-add it (factory add <machine> <feed> <out>)"):format(FX.factoryName(i)), K.orange)
    end
    if s.trial then s.trial = nil end                 -- its settings are restored once it's back
  elseif not peripheral.isPresent(f.feed) then why = "can't see its feed barrel"
  elseif not peripheral.isPresent(f.out) then why = "can't see its out barrel" end
  if why ~= "factory missing, re-add it" and why ~= "can't see the factory" then s.unseenSince, s.missingNoted = nil, nil end
  s.ins, s.outs, s.feed, s.feedSlots = {}, {}, {}, {}
  s.insTotal, s.outsTotal, s.feedTotal = 0, 0, 0
  if not why then
    if not s.procs then
      local n = 0
      for p = 0, 15 do
        if call(f.machine, "getInput", p) == nil then break end
        n = p + 1
      end
      s.procs = math.max(1, n)
    end
    for p = 0, s.procs - 1 do
      s.insTotal = s.insTotal + FX.readItem(call(f.machine, "getInput", p), s.ins)
      s.outsTotal = s.outsTotal + FX.readItem(call(f.machine, "getOutput", p), s.outs)
    end
    local l = call(f.feed, "list")
    if type(l) == "table" then
      for slot, it in pairs(l) do
        s.feedSlots[slot] = it
        s.feed[it.name] = (s.feed[it.name] or 0) + it.count
        s.feedTotal = s.feedTotal + it.count
      end
    end
    -- The out barrel: dust waiting for storage, and dust storage just took (not in its count yet)
    local ol = call(f.out, "list")
    local outB = {}
    if type(ol) == "table" then for _, it in pairs(ol) do outB[it.name] = (outB[it.name] or 0) + it.count end end
    s.drained = s.drained or {}
    if s.drainedAt and storageSeen and storageSeen > s.drainedAt + 0.5 then s.drained, s.drainedAt = {}, nil end
    for name, c in pairs(s.outBarrel or {}) do
      local now = outB[name] or 0
      if now < c then s.drained[name] = (s.drained[name] or 0) + (c - now); s.drainedAt = os.clock() end
    end
    s.outBarrel = outB
    s.energy = tonumber((call(f.machine, "getEnergyFilledPercentage")))
    if not s.trial and cfg.trialSaved and cfg.trialSaved[f.machine] then FX.restoreSettings(f.machine) end
    local empty = s.feedTotal + s.insTotal + s.outsTotal == 0
    if empty then s.idleSince = s.idleSince or os.clock() else s.idleSince = nil end
    if s.energy and s.energy <= 0 then why = "no power" end
    -- Auto-eject has to be on (except while I'm reading a new ore's dust)
    if not s.trial and os.clock() - (s.ejectCheck or -100) > 30 then
      s.ejectCheck = os.clock()
      if call(f.machine, "isEjecting", "ITEM") == false then
        call(f.machine, "setEjecting", "ITEM", true)
        s.ejectNote = call(f.machine, "isEjecting", "ITEM") == false and "turn on auto-eject (Side Config)" or nil
      else
        s.ejectNote = nil
      end
    end
    -- Something waiting and nothing moving for a while = stuck
    local total = s.feedTotal + s.insTotal
    if total ~= s.lastTotal or total == 0 then s.lastMove = os.clock() end
    s.lastTotal = total
    if not why and total > 0 and os.clock() - s.lastMove > FX.STUCK_AFTER then why = "stuck: nothing's moving" end
    if not why and s.ejectNote then why = s.ejectNote end
  end
  s.why = why
  if why then s.downSince = s.downSince or os.clock() else s.downSince = nil end
  s.ok = why == nil
  return s
end

-- Do the factories still count? (some factory up, or not down for long)
function FX.factoriesHold()
  for i in ipairs(cfg.factories) do
    local s = FX.facs[i]
    if not s or not s.downSince or os.clock() - s.downSince < FX.FALLBACK_AFTER then return true end
  end
  return false
end

function FX.minUnit(ore)
  local u
  for i in ipairs(cfg.factories) do u = math.min(u or 1e9, FX.unitOf(i, ore)) end
  return u or 9
end

function FX.trialFor(ore)
  for i in ipairs(cfg.factories) do
    if FX.facs[i] and FX.facs[i].trial and FX.facs[i].trial.input == ore then return i end
  end
end

-- How many of a recipe's output one of this ore makes by way of a factory (0 = no route)
function FX.enrichPer(r, ore)
  local e = cfg.enrich[ore]
  if type(e) ~= "table" or not e.out or e.dustBad then return 0 end
  if FX.direct.kind(book, ore, e) == "direct" then
    return outMatches(r, e.out) and isInputOf(r, ore) and e.made / math.max(1, e.used) or 0
  end
  if not isInputOf(r, e.out) then return 0 end
  return (e.made / math.max(1, e.used)) * perOf(r, e.out)
end

-- Output on its way in the factories (feed barrels, inputs, dust not ejected yet), for keep-N rules
function FX.pendingFor(r)
  local n = 0
  for i in ipairs(cfg.factories) do
    local s = FX.facs[i]
    if s and s.feed then
      for name, c in pairs(s.feed) do n = n + c * FX.enrichPer(r, name) end
      for name, c in pairs(s.ins) do n = n + c * FX.enrichPer(r, name) end
      for name, c in pairs(s.outs) do if isInputOf(r, name) then n = n + c * perOf(r, name) end end
      for name, c in pairs(s.outs) do if outMatches(r, name) then n = n + c end end          -- a direct product
      for name, c in pairs(s.outBarrel or {}) do if isInputOf(r, name) then n = n + c * perOf(r, name) end end
      for name, c in pairs(s.outBarrel or {}) do if outMatches(r, name) then n = n + c end end
      for name, c in pairs(s.drained or {}) do if isInputOf(r, name) then n = n + c * perOf(r, name) end end
    end
  end
  return n
end

-- A dust that already smelts into something (any recipe has it as an input)
function FX.dustRecipe(dust)
  for _, k in ipairs(sortedKeys(book)) do
    if has(book[k].inputs, dust) then return book[k] end
  end
end

-- Lines for the screen and the status: every ore I know about
function FX.enrichList()
  local out = {}
  for _, ore in ipairs(sortedKeys(cfg.enrich)) do
    local e = cfg.enrich[ore]
    local state
    if e.no then state = "refused"
    elseif e.dustBad then state = "dust won't smelt"
    elseif FX.direct.kind(book, ore, e) == "direct" then state = "direct"
    elseif FX.dustRecipe(e.out) then state = "via dust"
    else state = "checking dust" end
    out[#out + 1] = { ore = ore, e = e, state = state }
  end
  return out
end

---------------------------------------------------------------------------
-- One smelting pass: read the furnaces, measure them, plan the moves, have storage do them
---------------------------------------------------------------------------
local samples = {}           -- furnace -> { name, count, t, filled } from the last pass
local speedDirty, speedSaved = false, os.clock()
local activeCount = 0

local function sampleSpeed(fz, cur)
  local now = os.clock()
  local p = samples[fz]
  if p and cur and not p.filled and p.name == cur.name and cur.count <= p.count and cur.count > 0 then
    -- It had input for the whole gap, so it was cooking the whole time
    local sp = cfg.speed[fz] or { t = 0, n = 0 }
    sp.t, sp.n = sp.t + (now - p.t), sp.n + (p.count - cur.count)
    if sp.t > 900 then sp.t, sp.n = sp.t / 2, sp.n / 2 end    -- recent work counts most
    cfg.speed[fz] = sp
    speedDirty = true
  end
  samples[fz] = cur and { name = cur.name, count = cur.count, t = now } or nil
end

local function smeltPass()
  if os.clock() - lastSmeltLoad > 30 then loadSmeltRules() end
  findFurnaces()
  local st = {}
  local busy, cooked = {}, {}
  activeCount = 0
  for _, fz in ipairs(array) do
    local s = readOne(fz)
    st[fz] = s
    if s then
      sampleSpeed(fz, s.inp)
      if s.inp then busy[s.inp.name] = (busy[s.inp.name] or 0) + s.inp.count; activeCount = activeCount + 1 end
      if s.out then cooked[s.out.name] = (cooked[s.out.name] or 0) + s.out.count end
    end
  end
  fstate = st
  if speedDirty and os.clock() - speedSaved > 60 then saveCfg(); speedDirty, speedSaved = false, os.clock() end
  for i in ipairs(cfg.factories) do FX.readFactory(i) end

  if #array == 0 then smeltNote = cfg.trainer and "Only the trainer on my cable" or "No furnaces on my cable network"; return end
  if not storageFresh() then smeltNote = "Waiting for the storage computer"; return end

  local have = {}
  for k, v in pairs(byName) do have[k] = v end
  local ops = {}

  -- 1. Finished items back into storage
  for _, fz in ipairs(array) do
    if st[fz] and st[fz].out then ops[#ops + 1] = { op = "store", fz = fz, slot = 3 } end
  end

  -- 2. Hand out work, 8 items at a time, each to the furnace that would finish it soonest
  local slots = {}
  for _, fz in ipairs(array) do
    local s = st[fz]
    if s then
      slots[#slots + 1] = { fz = fz, name = s.inp and s.inp.name, count = s.inp and s.inp.count or 0,
                            spi = spiOf(fz), add = 0, jobs = {} }
    end
  end
  -- Fair shares: while capR is set, that recipe may hold at most capN furnaces (empty ones up to
  -- capN, top-ups only while it isn't over), so one rule with lots of input can't take them all.
  -- capFree: empty ones are free for anyone (the second round), top-ups are still capped
  local capR, capN, capFree
  local function held(r)
    local n = 0
    for _, f in ipairs(slots) do if f.name and isInputOf(r, f.name) then n = n + 1 end end
    return n
  end
  local function give(input, amount, job)
    local left = amount
    while left > 0 do
      local best, bestT
      local h = capR and held(capR)
      for _, f in ipairs(slots) do
        if (f.name == nil or f.name == input) and (f.count <= TOPUP_AT or f.add > 0)
           and (not h or h < capN or (f.name == nil and capFree) or (f.name ~= nil and h <= capN)) then
          local room = 64 - f.count - f.add
          if room > 0 then
            local t = (f.count + f.add + math.min(CHUNK, left, room)) * f.spi
            if not bestT or t < bestT - 1e-9 then best, bestT = f, t end
          end
        end
      end
      if not best then break end
      local chunk = math.min(CHUNK, left, 64 - best.count - best.add)
      best.name, best.add = input, best.add + chunk
      best.jobs[#best.jobs + 1] = { job = job, n = chunk }
      left = left - chunk
    end
    local given = amount - left
    if given > 0 then
      have[input] = (have[input] or 0) - given
      busy[input] = (busy[input] or 0) + given
      if job then job.left = job.left - given end
    end
  end

  -- 3. The factories: how much each can take this pass (whole batches; none while it's trying an ore)
  local facRoom = {}
  for i in ipairs(cfg.factories) do
    local fs = FX.facs[i]
    local held = fs and fs.reserved                   -- kept clear for a drip trial that's waiting for it
    if fs then fs.reserved = nil end
    if fs and fs.ok and not fs.trial and not held then
      facRoom[i] = math.max(0, FX.FACTORY_BUFFER * 3 * FX.procsOf(i) - fs.feedTotal - fs.insTotal)
    end
  end
  local feeds = {}           -- { i, item, n, job, trial }
  local guesses = {}         -- dust -> output: learn after the pass (no trainer to check it)

  -- Send ore to the factories with the most room; rounds up to whole batches if there's enough ore
  local function feedFactories(ore, amount, job, roundUp)
    local left = math.min(have[ore] or 0, amount)
    local taken = 0
    while left > 0 do
      local best, bestRoom
      for i, room in pairs(facRoom) do
        if room > 0 and (not bestRoom or room > bestRoom or (room == bestRoom and i < best)) then best, bestRoom = i, room end
      end
      if not best then break end
      local unit = FX.unitOf(best, ore)
      local n = math.min(bestRoom, (roundUp and math.ceil(left / unit) or math.floor(left / unit)) * unit)
      n = math.floor(math.min(n, (have[ore] or 0) - taken) / unit) * unit
      if n <= 0 then break end
      feeds[#feeds + 1] = { i = best, item = ore, n = n, job = job }
      FX.facs[best].lastFeed = os.clock()
      facRoom[best] = bestRoom - n
      taken = taken + n
      left = left - n
    end
    if taken > 0 then
      have[ore] = (have[ore] or 0) - taken
      if job then job.left = job.left - taken end
    end
    return taken
  end

  -- Try a new ore in a factory: a drip trial (see drip.lua) on a factory that's empty and idle, with
  -- eject and auto-sort off so its dust stays where I can read it. Only one item goes in now.
  local function startTrial(ore, probe)
    if not probe and FX.trialCool[ore] and os.clock() - FX.trialCool[ore] < 600 then return nil end
    local best, idle
    for i in ipairs(cfg.factories) do
      local fs = FX.facs[i]
      if fs and fs.ok and not fs.trial and (not probe or not probe.i or probe.i == i) then
        local isIdle = (fs.idleSince and os.clock() - fs.idleSince >= FX.IDLE_FOR and os.clock() - (fs.lastFeed or -1e9) > FX.IDLE_FOR * 2) and true or false
        if not best or (isIdle and not idle) or (isIdle == idle and fs.feedTotal + fs.insTotal < FX.facs[best].feedTotal + FX.facs[best].insTotal) then
          best, idle = i, isIdle
        end
      end
    end
    if not best then
      -- Busy trying something else: wait for it (unless no factory is up)
      for i in ipairs(cfg.factories) do if FX.facs[i] and FX.facs[i].ok then return "hold" end end
      return nil
    end
    if (have[ore] or 0) < 1 then return nil end
    for _, f in ipairs(feeds) do if f.i == best then return "hold" end end   -- already fed this pass
    if not idle then FX.facs[best].reserved = true; return "hold" end      -- let it empty, route nothing more to it
    local t = FX.beginTrial(best, ore, probe and { probe = true } or nil)
    FX.facs[best].lastFeed = os.clock()
    t.want, t.pending, t.pendingAt = false, true, os.clock()
    feeds[#feeds + 1] = { i = best, item = ore, n = 1, trial = true }
    facRoom[best] = nil
    have[ore] = have[ore] - 1
    return "hold"
  end

  -- The next drip of a running trial, one item at a time
  local function dripFeeds()
    for i in ipairs(cfg.factories) do
      local fs = FX.facs[i]
      local t = fs and fs.trial
      if t and t.want and not t.pending then
        if (have[t.input] or 0) < 1 then
          FX.endTrial(i, "Trial of " .. pretty(t.input) .. " called off: none left in storage.", K.orange)
        else
          t.want, t.pending, t.pendingAt = false, true, os.clock()
          fs.lastFeed = os.clock()
          feeds[#feeds + 1] = { i = i, item = t.input, n = 1, trial = true }
          have[t.input] = have[t.input] - 1
        end
      end
    end
  end

  -- Where does this input go? "factory" (+ its route), "hold" (wait: a factory is trying it, or its
  -- dust is being checked) or nil (the furnaces, as always)
  local function enrichState(r, input)
    if #cfg.factories == 0 or not FX.factoriesHold() then return nil end
    local e = cfg.enrich[input]
    if type(e) == "table" and (e.no or e.dustBad) then return nil end
    if type(e) == "table" and e.out and FX.direct.kind(book, input, e) == "direct" then
      -- The factory makes what the furnace would: only that recipe takes it, and no dust check is waited on
      if not (outMatches(r, e.out) and isInputOf(r, input)) then return nil end
      local n = have[input] or 0
      if n > 0 and n < FX.minUnit(input) then
        FX.leftoverSince[input] = FX.leftoverSince[input] or os.clock()
        if os.clock() - FX.leftoverSince[input] > FX.LEFTOVER_WAIT then return nil end
      else
        FX.leftoverSince[input] = nil
      end
      return "factory", e
    end
    if type(e) == "table" and e.out then
      if isInputOf(r, e.out) then
        local n = have[input] or 0
        if n > 0 and n < FX.minUnit(input) then
          FX.leftoverSince[input] = FX.leftoverSince[input] or os.clock()
          if os.clock() - FX.leftoverSince[input] > FX.LEFTOVER_WAIT then return nil end
        else
          FX.leftoverSince[input] = nil
        end
        return "factory", e
      end
      -- Its dust isn't known to make this yet
      local other = FX.dustRecipe(e.out)
      if other and outMatches(r, other.out) then return "factory", e end
      if other then return nil end                         -- the dust smelts into something else
      if cfg.trainer then FX.dustQueue[e.out] = r.out; return "hold" end
      -- No trainer to check it: go by the names (aluminum_dust / dust_iron -> aluminum_ingot / iron_ingot)
      local metal = shortName(e.out):gsub("_dust$", ""):gsub("^dust_", "")
      local made = shortName(r.out):gsub("_ingot$", ""):gsub("^ingot_", "")
      if metal == made then guesses[e.out] = r.out; return "hold" end
      return nil
    end
    if FX.trialable(input) then
      if FX.trialFor(input) then return "hold" end
      return startTrial(input)
    end
    return nil
  end

  -- Hand a recipe's work out: what the furnaces can take straight away (incl. dust) to the furnaces,
  -- ore with a factory route to the factories. amount = output items wanted (rules) or input items
  -- (jobs: job.left).
  local function serve(r, amount, job, keepKey, furnaceOnly)
    local inputs = {}
    for name, n in pairs(have) do if n > 0 and isInputOf(r, name) then inputs[#inputs + 1] = name end end
    table.sort(inputs, function(a, b)
      if have[a] ~= have[b] then return have[a] > have[b] end
      return a < b
    end)
    local ores = {}
    for _, input in ipairs(inputs) do
      local how, e = enrichState(r, input)
      if furnaceOnly and how == "factory" then how = "skip" end
      if how == "factory" then
        ores[#ores + 1] = { input = input, e = e }
      elseif how == nil and amount > 0 and (have[input] or 0) > 0 then
        local per = job and 1 or perOf(r, input)
        local before = have[input]
        give(input, math.min(before, math.ceil(amount / per)), job)
        amount = amount - (before - have[input]) * per
        -- What's left of it waits for furnace room: it's still coming, so no ore gets sent for it
        if not job then amount = amount - have[input] * per end
      end
    end
    if furnaceOnly then return end
    if keepKey then
      -- Keep-N: only for a shortfall that lasts (two passes; a part batch, 10 s)
      if amount <= 0 then FX.shortSince[keepKey] = nil; return end
      FX.shortSince[keepKey] = FX.shortSince[keepKey] or os.clock()
      if os.clock() - FX.shortSince[keepKey] < TICK + 1 then return end
    end
    for _, o in ipairs(ores) do
      if amount <= 0 then break end
      local ratio = o.e.made / math.max(1, o.e.used)
      local direct = FX.direct.kind(book, o.input, o.e) == "direct"
      local per = job and 1 or ratio * (direct and 1 or perOf(r, o.e.out))
      local want = math.ceil(amount / per)
      local roundUp = keepKey and os.clock() - FX.shortSince[keepKey] >= 10
      local taken = feedFactories(o.input, want, job, roundUp)
      amount = amount - taken * per
      -- A job's last few (less than a batch) go straight to the furnaces
      if job and taken < want and (have[o.input] or 0) > 0 then
        local before = have[o.input]
        give(o.input, math.min(before, want - taken), job)
        amount = amount - (before - have[o.input])
      end
      if job and taken > 0 and not direct then
        job.follow = job.follow or {}
        job.follow[o.e.out] = (job.follow[o.e.out] or 0) + math.floor(taken * ratio)
        job.followAt = os.clock()
      end
    end
  end

  if not cfg.paused and not picking then
    -- One-off jobs first, oldest first
    local i = 1
    while i <= #smeltQueue do
      local job = smeltQueue[i]
      local _, jr = recipeFor(job.name)       -- the recipe may have grown since (a dust learned)
      job.r = jr
      -- Dust coming back from the factories for this job goes to the furnaces as it arrives
      local following = false
      for dust, n in pairs(job.follow or {}) do
        if n > 0 then
          following = true
          if (have[dust] or 0) > 0 then
            local before = have[dust]
            give(dust, math.min(n, before))
            job.follow[dust] = n - (before - have[dust])
          end
        end
      end
      if job.followAt and os.clock() - job.followAt > 900 then following = false end
      if job.left <= 0 and not following then table.remove(smeltQueue, i)
      else
        if job.left > 0 then serve(job.r, job.left, job) end
        i = i + 1
      end
    end
    -- Then the standing rules, in smelt.txt order: first each rule with work up to its fair share
    -- of the furnaces, then the furnaces still free go to whichever rule can use them
    local function wantOf(rule)
      local r = rule.r
      if rule.all then return math.huge end
      local made = outCount(r)
      for name, c in pairs(cooked) do if outMatches(r, name) then made = made + c end end
      for name, c in pairs(busy) do if isInputOf(r, name) then made = made + c * perOf(r, name) end end
      return rule.stacks * 64 - made - FX.pendingFor(r)
    end
    local function hasInput(r)
      for name, n in pairs(have) do if n > 0 and isInputOf(r, name) then return true end end
    end
    local working = 0
    for _, job in ipairs(smeltQueue) do if job.left > 0 then working = working + 1 end end
    for _, rule in ipairs(smeltRules) do
      rule.working = wantOf(rule) > 0 and hasInput(rule.r)
      if rule.working then working = working + 1 elseif not rule.all then FX.shortSince[rule.name] = nil end
    end
    capN = math.max(1, math.ceil(#slots / math.max(1, working)))
    for _, rule in ipairs(smeltRules) do
      if rule.working then capR = rule.r; serve(rule.r, wantOf(rule), nil, not rule.all and rule.name or nil) end
    end
    capFree = true
    for _, rule in ipairs(smeltRules) do
      if rule.working then capR = rule.r; serve(rule.r, wantOf(rule), nil, nil, true) end
    end
    capR = nil
  end

  -- Feed barrels: things that shouldn't be there (an ore it refused, a forgotten route) go back
  for i, f in ipairs(cfg.factories) do
    local fs = FX.facs[i]
    if fs and fs.feedSlots then
      for slot, it in pairs(fs.feedSlots) do
        local e = cfg.enrich[it.name]
        local wanted = (fs.trial and fs.trial.input == it.name) or (type(e) == "table" and e.out and not e.no and not e.dustBad)
        if not wanted then ops[#ops + 1] = { op = "store", fz = f.feed, slot = slot } end
      end
    end
  end
  local feedAt = {}
  if FX.probeReq then
    local pr = FX.probeReq
    if not FX.probeActive() and os.clock() - pr.since > 120 then
      FX.probeReq = nil
      FX.probeSay("Probe called off: no free factory, or none of " .. pretty(pr.item) .. " in storage.", K.orange)
    elseif startTrial(pr.item, pr) == "hold" and FX.probeActive() then
      FX.probeReq = nil
    end
  end
  dripFeeds()
  for _, fd in ipairs(feeds) do
    ops[#ops + 1] = { op = "fill", fz = cfg.factories[fd.i].feed, item = fd.item, count = math.min(64, fd.n) }
    feedAt[#ops] = fd
  end

  local meta = {}
  for _, f in ipairs(slots) do
    if f.add > 0 then
      ops[#ops + 1] = { op = "fill", fz = f.fz, slot = 1, item = f.name, count = f.add }
      meta[#ops] = f
      if samples[f.fz] then samples[f.fz].filled = true end
    end
    -- 3. Fuel for what it has (1 coal = 8 items)
    local total = f.count + f.add
    if total > 0 then
      local fuelD = st[f.fz].fuel
      local fuelHave = fuelD and fuelD.count or 0
      local need = total - fuelHave * (fuelD and FUEL_VALUE[fuelD.name] or 8)
      if need > 0 then
        for _, fuelName in ipairs(SMELT_FUELS) do
          if (have[fuelName] or 0) > 0 and (not fuelD or fuelD.name == fuelName) then
            local n = math.min(have[fuelName], 64 - fuelHave, math.max(1, math.ceil(need / FUEL_VALUE[fuelName])))
            if n > 0 then
              ops[#ops + 1] = { op = "fill", fz = f.fz, slot = 2, item = fuelName, count = n }
              have[fuelName] = have[fuelName] - n
            end
            break
          end
        end
      end
    end
  end

  if #ops > 0 then
    local results = sendBatch(ops)
    -- Give back to the jobs whatever storage couldn't actually move
    for i, f in pairs(meta) do
      local short = f.add - (results and tonumber(results[i]) or 0)
      for j = #f.jobs, 1, -1 do
        if short <= 0 then break end
        local b = f.jobs[j]
        local back = math.min(short, b.n)
        if b.job then b.job.left = b.job.left + back end
        short = short - back
      end
    end
    for i, fd in pairs(feedAt) do
      local moved = results and tonumber(results[i]) or 0
      local short = fd.n - moved
      if fd.trial then
        local fs = FX.facs[fd.i]
        if fs and fs.trial then FX.drip.sent(fs.trial, moved) end
      elseif short > 0 and fd.job then
        fd.job.left = fd.job.left + short
        for dust, n in pairs(fd.job.follow or {}) do
          local e = cfg.enrich[fd.item]
          if type(e) == "table" and e.out == dust then fd.job.follow[dust] = math.max(0, n - math.floor(short * e.made / math.max(1, e.used))) end
        end
      end
    end
    if not results then smeltNote = "Storage didn't answer"; return end
  end
  -- Dusts I couldn't check in the trainer: learn them by name
  for dust, out in pairs(guesses) do
    if not FX.dustRecipe(dust) then learn(dust, out, 1); FX.notify("No trainer: guessing " .. pretty(dust) .. " smelts into " .. pretty(out), K.yellow) end
  end
  local queued = 0
  for _, j in ipairs(smeltQueue) do queued = queued + math.max(0, j.left) end
  if cfg.paused then smeltNote = "Paused"
  elseif activeCount > 0 then
    smeltNote = ("Smelting %d/%d%s"):format(activeCount, #array, queued > 0 and (", " .. queued .. " queued") or "")
  else
    smeltNote = queued > 0 and (queued .. " queued, waiting for input") or "Idle"
  end
end

---------------------------------------------------------------------------
-- Training furnace
---------------------------------------------------------------------------
local train = { state = "idle" }   -- idle | starting | fuelling | cooking | learned | failed
local trainSlots = {}              -- the trainer's slots as last read
local trainSeen = false            -- could we read it last time
local lastGiveBack = -100

local function bestFuel(have)
  for _, f in ipairs(SMELT_FUELS) do if (have[f] or 0) > 0 then return f end end
end

local function trainFail(text)
  train.state, train.reason, train.endedAt = "failed", text, os.clock()
  train.giveBack = true
  if train.auto then
    -- A factory dust that won't smelt: that ore stays in the furnaces
    for ore, e in pairs(cfg.enrich) do
      if type(e) == "table" and e.out == train.input then e.dustBad = true end
    end
    FX.dustQueue[train.input] = nil
    saveCfg()
    FX.notify(pretty(train.input) .. " doesn't smelt: its ore stays in the furnaces", K.orange)
  end
  redraw()
end

local function startTraining()
  if not cfg.trainer then return false, "Pick a training furnace first." end
  local s = trainSlots
  if not s.inp then return false, "Put the raw item in the trainer's TOP slot first." end
  train = { state = "starting", input = s.inp.name, startCount = s.inp.count, startedAt = os.clock() }
  FX.ts.sync(cfg, saveCfg, train)
  redraw()
  return true
end

local function trainStep()
  if not cfg.trainer then trainSlots, trainSeen = {}, false; return end
  local s = readOne(cfg.trainer)
  if not s then trainSlots, trainSeen = {}, false; return end
  trainSlots, trainSeen = s, true
  FX.ts.sync(cfg, saveCfg, train)

  -- After a training: put the leftovers and the cooked item back in storage
  if train.giveBack then
    local backIn = s.inp and s.inp.name == train.input
    if not backIn and not s.out then train.giveBack = false
    elseif storageFresh() and os.clock() - lastGiveBack > 2 then
      lastGiveBack = os.clock()
      local ops = {}
      if backIn then ops[#ops + 1] = { op = "store", fz = cfg.trainer, slot = 1 } end
      if s.out then ops[#ops + 1] = { op = "store", fz = cfg.trainer, slot = 3 } end
      sendBatch(ops)
    end
  end

  -- A furnace just picked from the list may still hold work from the array: empty it
  if train.clear then
    if not s.inp and not s.out then train.clear = nil
    elseif storageFresh() and os.clock() - lastGiveBack > 2 then
      lastGiveBack = os.clock()
      local ops = {}
      if s.inp then ops[#ops + 1] = { op = "store", fz = cfg.trainer, slot = 1 } end
      if s.out then ops[#ops + 1] = { op = "store", fz = cfg.trainer, slot = 3 } end
      sendBatch(ops)
    end
    return
  end

  -- A new item after a failed try: start fresh
  if train.state == "failed" and not train.giveBack and s.inp then train = { state = "idle", seen = train.seen } end

  local stt = train.state
  if stt == "starting" then
    if not s.inp or s.inp.name ~= train.input then return trainFail("The item was taken out before it cooked.") end
    if s.out then
      -- Something from before is in the output slot: empty it first, so what comes out is new
      if not storageFresh() then train.note = "Waiting for storage to empty its output slot"; return end
      train.note = "Emptying its output slot"
      sendBatch({ { op = "store", fz = cfg.trainer, slot = 3 } })
      return
    end
    train.startCount = s.inp.count
    train.state, train.note = "fuelling", nil
    stt = "fuelling"
  end
  if stt == "fuelling" then
    if not s.inp or s.inp.name ~= train.input then return trainFail("The item was taken out before it cooked.") end
    if s.fuel then
      train.state, train.fuelAt, train.note = "cooking", os.clock(), nil
      stt = "cooking"
    else
      local f = storageFresh() and bestFuel(byName)
      if not f then
        train.note = storageFresh() and "No coal or charcoal in storage: put some fuel in its bottom slot"
          or "Waiting for storage (or put fuel in its bottom slot)"
        return
      end
      train.note = "Fuelling it"
      sendBatch({ { op = "fill", fz = cfg.trainer, slot = 2, item = f, count = 1 } })
      return
    end
  end
  if stt == "cooking" then
    if s.out then
      local left = (s.inp and s.inp.name == train.input) and s.inp.count or 0
      local used = train.startCount - left
      local per = used > 0 and math.max(1, math.floor(s.out.count / used + 0.5)) or s.out.count
      train.out, train.per = s.out.name, per
      train.key, train.known = learn(train.input, s.out.name, per)
      if train.auto then
        FX.dustQueue[train.input] = nil
        -- The ore it came from joins the same recipe (so "aluminum all" covers both), if it isn't in one yet
        for ore, e in pairs(cfg.enrich) do
          if type(e) == "table" and e.out == train.input and book[train.key] and not isInputOf(book[train.key], ore) then
            local _, hostR = recipeFor(shortName(ore))
            if hostR.modded or not isInputOf(hostR, ore) then learn(ore, s.out.name, 1) end
          end
        end
        FX.notify(("Checked: %s smelts into %s. Enriching from now on."):format(pretty(train.input), pretty(s.out.name)), K.lime)
        train = { state = "idle", giveBack = true, input = train.input, seen = true, endedAt = os.clock() }
        redraw()
        return
      end
      local rule = ruleFor(train.key)
      train.mode = rule and (rule.all and "all" or "keep") or nil
      train.stacks = rule and rule.stacks or 4
      train.state, train.endedAt, train.giveBack = "learned", os.clock(), true
      redraw()
    elseif not s.inp or s.inp.name ~= train.input then
      trainFail("The item was taken out before it cooked.")
    elseif os.clock() - train.fuelAt > TRAIN_TIMEOUT then
      trainFail(("Nothing came out in %d s: %s doesn't smelt in a furnace."):format(TRAIN_TIMEOUT, pretty(train.input)))
    end
  end
end

-- The factory's own switches: which method names this machine has for auto-sort
function FX.sortMethod(machine, prefix)
  for _, m in ipairs(peripheral.getMethods(machine) or {}) do
    if prefix == "get" and (m == "isAutoSort" or m == "isAutoSortEnabled") then return m end
    if prefix == "set" and m == "setAutoSort" then return m end
  end
end

-- Put eject and auto-sort back as they were before a trial (kept in smelter.cfg while it runs, so a
-- reboot or a cancel can't leave the factory with eject off)
function FX.restoreSettings(machine)
  local saved = cfg.trialSaved and cfg.trialSaved[machine]
  if not saved then return end
  if not peripheral.isPresent(machine) then return end
  call(machine, "setEjecting", "ITEM", saved.eject ~= false)
  local set = FX.sortMethod(machine, "set")
  if set and saved.sort ~= nil then call(machine, set, saved.sort) end
  cfg.trialSaved[machine] = nil
  if next(cfg.trialSaved) == nil then cfg.trialSaved = nil end
  saveCfg()
end

-- Everything the drip trial needs to know about a factory right now
function FX.snapshot(i, t)
  local fs, f = FX.facs[i], cfg.factories[i]
  local snap = { feedN = 0, inN = 0, outs = {}, progress = 0, procs = {} }
  local l = call(f.feed, "list")
  if type(l) == "table" then
    for _, it in pairs(l) do if it.name == t.input then snap.feedN = snap.feedN + it.count end end
  end
  for p = 0, (fs.procs or 3) - 1 do
    local a = call(f.machine, "getInput", p)
    local o = call(f.machine, "getOutput", p)
    local prog = tonumber((call(f.machine, "getRecipeProgress", p))) or 0
    if type(a) == "table" and a.name == t.input then snap.inN = snap.inN + (a.count or 0) end
    FX.readItem(o, snap.outs)
    snap.progress = math.max(snap.progress, prog)
    snap.procs[#snap.procs + 1] = { input = type(a) == "table" and a.count or "?", output = type(o) == "table" and o.count or "?", progress = prog }
  end
  snap.outs[t.input] = nil
  if not t.ejectOff then
    -- Eject wouldn't turn off: count what lands in the out barrel instead (storage leaves that
    -- barrel alone while I try an ore: "hold" in my broadcast)
    local ol = call(f.out, "list")
    local cur = {}
    if type(ol) == "table" then for _, it in pairs(ol) do cur[it.name] = (cur[it.name] or 0) + it.count end end
    t.outBase = t.outBase or cur
    for name, c in pairs(cur) do
      local d = c - (t.outBase[name] or 0)
      if d > 0 then snap.outs[name] = (snap.outs[name] or 0) + d end
    end
  end
  snap.ticks = tonumber((call(f.machine, "getTicksRequired")))
  snap.powered = not (fs.energy and fs.energy <= 0)
  return snap
end

-- A drip trial on factory i: eject and auto-sort off, the original settings saved first
function FX.beginTrial(i, ore, opts)
  local f, fs = cfg.factories[i], FX.facs[i]
  local t = FX.drip.begin(ore, opts)
  cfg.trialSaved = cfg.trialSaved or {}
  if not cfg.trialSaved[f.machine] then
    local get = FX.sortMethod(f.machine, "get")
    local sort = get and call(f.machine, get)
    if sort == nil then sort = true end               -- can't read it: auto-sort is on in the real setup
    cfg.trialSaved[f.machine] = { eject = call(f.machine, "isEjecting", "ITEM") ~= false, sort = sort, at = os.epoch("utc") }
    saveCfg()
  end
  call(f.machine, "setEjecting", "ITEM", false)
  local set = FX.sortMethod(f.machine, "set")
  if set then call(f.machine, set, false) end
  t.ejectOff = call(f.machine, "isEjecting", "ITEM") == false
  t.t0 = os.clock()
  fs.trial = t
  return t
end

-- Call a trial off (verdict done, cancel, lost): settings back, the factory free again
function FX.endTrial(i, text, col)
  local f, fs = cfg.factories[i], FX.facs[i]
  if fs then fs.trial = nil end
  if f then FX.restoreSettings(f.machine) end
  if text then FX.notify(text, col); print(text) end
  redraw()
end

-- What's sitting in a factory (for the alert when a trial is called off)
function FX.contents(i)
  local fs = FX.facs[i]
  local parts = {}
  for _, tbl in ipairs({ fs.ins or {}, fs.outs or {}, fs.feed or {} }) do
    for name, c in pairs(tbl) do parts[#parts + 1] = c .. " " .. pretty(name) end
  end
  return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

-- A new ore in a factory, a drip at a time: did a process start, and what came out? (every half second)
function FX.trialStep()
  FX.drip.useProgress = cfg.dripProgress == true
  for i, f in ipairs(cfg.factories) do
    local fs = FX.facs[i]
    local t = fs and fs.trial
    if t then
      local now = os.clock()
      t.lastStep = t.lastStep or now
      local dt = now - t.lastStep
      t.lastStep = now
      if t.pending and now - t.pendingAt > 30 then
        -- The pass that was sending the item never finished (it failed half way): call it off
        FX.endTrial(i)
      else
        local snap = FX.snapshot(i, t)
        if t.probe then FX.probeSample(i, t, snap) end
        local v = FX.drip.step(t, snap, dt)
        if v then FX.trialVerdict(i, t, v) end
      end
    end
  end
end

function FX.trialVerdict(i, t, v)
  local name = FX.factoryName(i)
  local ore = pretty(t.input)
  if t.probe then return FX.probeEnd(i, t, v) end
  if v.kind == "learned" then
    cfg.enrich[t.input] = FX.drip.result(t, v.product, v.made, FX.direct.furnaceRecipe(book, t.input, v.product) ~= nil)
    saveCfg()
    FX.endTrial(i, ("Factory: %d %s -> %d %s (%d to start)"):format(t.n, ore, v.made, pretty(v.product), t.n), K.lime)
  elseif v.kind == "refused" then
    cfg.enrich[t.input] = { no = true, at = os.epoch("utc") }
    saveCfg()
    FX.endTrial(i, v.feedN > 0 and (ore .. " doesn't go in " .. name .. ": it stays in the furnaces.")
      or ("1 " .. ore .. " is stuck in " .. name .. "'s hopper: pull it out by hand. It stays in the furnaces."), K.orange)
  elseif v.kind == "capped" then
    FX.trialCool[t.input] = os.clock()
    FX.endTrial(i, ("Dripped %d %s into %s and nothing started: trial called off. It holds %s."):format(t.added, ore, name, FX.contents(i)), K.orange)
  elseif v.kind == "lost" then
    FX.endTrial(i, "Trial of " .. ore .. " called off: storage couldn't deliver it.", K.orange)
  else
    FX.trialCool[t.input] = os.clock()
    FX.endTrial(i, "Tried " .. ore .. " in " .. name .. ": nothing came out. Trying again later.", K.orange)
  end
end

-- The probe: a drip trial that writes down every sample (and learns nothing), for Tanis and for #60
FX.PROBE_LOG = "probe.log"
FX.probeReq = nil          -- { item, i, since } until a factory is free to run it
FX.probeLog = {}
function FX.probeSay(text, col)
  FX.probeLog[#FX.probeLog + 1] = text
  print(text)
  if col then FX.notify(text, col) end
end

function FX.probeSample(i, t, snap)
  local now = os.clock()
  if t.lastSample and now - t.lastSample < 0.5 then return end
  t.lastSample = now
  t.probeT0 = t.probeT0 or now
  FX.probeLog[#FX.probeLog + 1] = FX.drip.sampleLine(now - t.probeT0, snap, snap.procs)
end

function FX.probeEnd(i, t, v)
  local f = cfg.factories[i]
  local what = v.kind == "learned" and ("%d %s -> %d %s (not saved)"):format(t.n, pretty(t.input), v.made, pretty(v.product))
    or ("ended: " .. v.kind)
  FX.probeSay("Probe " .. what)
  FX.probeSay(("detector: %s; items dripped: %d"):format(FX.drip.useProgress and "getRecipeProgress" or "wait one operation", t.added))
  FX.endTrial(i)
  local fh = fs.open(FX.PROBE_LOG, "w")
  fh.write(table.concat(FX.probeLog, "\n") .. "\n")
  fh.close()
  FX.notify("Probe done: " .. what .. ". Log in " .. FX.PROBE_LOG, K.lime)
  if http and shell then
    print("Uploading " .. FX.PROBE_LOG .. " to pastebin...")
    if not pcall(shell.run, "pastebin", "put", FX.PROBE_LOG) then print("Upload failed: run  pastebin put " .. FX.PROBE_LOG) end
  else
    print("Run  pastebin put " .. FX.PROBE_LOG .. "  to share it.")
  end
end

function FX.probeStart(item, which)
  if FX.probeReq or FX.probeActive() then return "A probe is already running." end
  if #cfg.factories == 0 then
    local m = FX.machineCandidates()[1]
    return "No factory set up yet: factory add " .. (m or "<machine>") .. " sophisticatedstorage:barrel_65 sophisticatedstorage:barrel_63"
  end
  if which and not cfg.factories[which] then return "No factory " .. which .. "." end
  FX.probeReq = { item = item or "minecraft:ancient_debris", i = which, since = os.clock() }
  FX.probeLog = {}
  FX.probeSay(("== probe %s  %s  computer %d"):format(os.date("%Y-%m-%d %H:%M"), pretty(FX.probeReq.item), os.getComputerID()))
  return "Probe starting: it waits for a free factory and pauses the smelter's use of it."
end

function FX.probeActive()
  for i in ipairs(cfg.factories) do if FX.facs[i] and FX.facs[i].trial and FX.facs[i].trial.probe then return i end end
end

-- Factory dust that isn't known to smelt yet: put one in the idle trainer and train it
function FX.autoTrainStep()
  if not cfg.trainer or not trainSeen or train.state ~= "idle" or train.giveBack or train.clear then return end
  if train.autoNext then
    if trainSlots.inp and trainSlots.inp.name == train.autoNext then
      local dust = train.autoNext
      local ok = startTraining()
      if ok then train.auto = true end
      if not ok then train.autoNext = nil end
      return dust
    end
    if os.clock() - (FX.autoTried[train.autoNext] or 0) > 15 then train.autoNext = nil end
    return
  end
  if trainSlots.inp or trainSlots.out or not storageFresh() then return end
  for _, dust in ipairs(sortedKeys(FX.dustQueue)) do
    if FX.dustRecipe(dust) then FX.dustQueue[dust] = nil
    elseif (byName[dust] or 0) > 0 and os.clock() - (FX.autoTried[dust] or -1e9) > 300 then
      FX.autoTried[dust] = os.clock()
      local res = sendBatch({ { op = "fill", fz = cfg.trainer, slot = 1, item = dust, count = 1 } })
      if res and (tonumber(res[1]) or 0) > 0 then train.autoNext = dust; train.seen = true end
      return
    end
  end
end

-- "Find it": the furnace whose top slot gains an item (the array is paused meanwhile)
local function pickStep()
  if not picking then return end
  if os.clock() > picking.untilT then picking = nil; return "timeout" end
  for _, fz in ipairs(allFurnaces()) do
    local d = call(fz, "getItemDetail", 1)
    local n = d and d.count or 0
    local before = picking.before[fz]
    if before == nil then picking.before[fz] = n
    elseif n > before then
      picking = nil
      return fz
    end
  end
end

---------------------------------------------------------------------------
-- Status for chat and the mainframe board
---------------------------------------------------------------------------
local function trainLine()
  if not cfg.trainer then return nil end
  local stt = train.state
  if stt == "starting" or stt == "fuelling" or stt == "cooking" then return "Training: " .. pretty(train.input) end
  if stt == "learned" and os.clock() - (train.endedAt or 0) < 60 then
    return ("Learned: %s -> %s"):format(pretty(train.input), pretty(train.out))
  end
  return nil
end

-- One line about a factory: what it's doing, or why it's down
FX.factoryLine = function(i)
  local fs = FX.facs[i]
  if not fs then return "starting" end
  if fs.trial and fs.trial.probe then return "probe: " .. pretty(fs.trial.input) .. ", " .. fs.trial.added .. " dripped" end
  if fs.trial then return "trying " .. pretty(fs.trial.input) .. ": " .. fs.trial.added .. " dripped" end
  if fs.why then
    local down = fs.downSince and os.clock() - fs.downSince or 0
    return fs.why .. (down >= FX.FALLBACK_AFTER and " (ore to furnaces)" or "")
  end
  local q = (fs.feedTotal or 0) + (fs.insTotal or 0)
  if q == 0 then return "ready" end
  local name
  for k in pairs(fs.ins) do name = k end
  for k in pairs(fs.feed) do name = name or k end
  return ("%d %s"):format(q, name and pretty(name):gsub("^raw ", "") or "ore")
end

-- For storage: the feed barrels (never storage, I fill them) and out barrels (emptied like inputs)
function FX.factoryBarrels()
  local out = {}
  for i, f in ipairs(cfg.factories) do
    local t = FX.facs[i] and FX.facs[i].trial
    out[#out + 1] = { feed = f.feed, out = f.out, machine = f.machine, hold = (t and not t.ejectOff) and true or nil }
  end
  return out
end

local function smeltStatus()
  local lines = {}
  lines[#lines + 1] = ("%d furnace(s). %s"):format(#array, smeltNote ~= "" and smeltNote or "Idle")
  local tl = trainLine()
  if tl then lines[#lines + 1] = tl end
  for _, j in ipairs(smeltQueue) do
    if j.left > 0 then lines[#lines + 1] = ("Queued: %d %s"):format(j.left, j.name) end
  end
  for i in ipairs(cfg.factories) do lines[#lines + 1] = FX.factoryName(i) .. ": " .. FX.factoryLine(i) end
  for _, rule in ipairs(smeltRules) do
    if rule.all then
      lines[#lines + 1] = ("Rule: all %s (%d waiting)"):format(rule.name, inputTotal(rule.r))
    else
      lines[#lines + 1] = ("Rule: keep %d stacks of %s (have %d)"):format(rule.stacks, rule.name, outCount(rule.r))
    end
  end
  return lines
end

---------------------------------------------------------------------------
-- Screens: the monitor (touching a side) and the computer's own terminal share one design,
-- each with its own page.
---------------------------------------------------------------------------
local function newUi() return { page = "home", scroll = 1, notice = nil, confirm = nil } end
local function findMonitor()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then return peripheral.wrap(side), side end
  end
end
local mon, monSide = findMonitor()
local views = {
  { dev = function() return mon end, kind = "monitor", hits = {}, ui = newUi() },
  { dev = function() return term end, kind = "term", hits = {}, ui = newUi() },
}
local ui = views[2].ui
local frame = 0
local cmdLine = nil          -- what's being typed on the terminal (nil = not typing)

local d, hits
local HEX = "0123456789abcdef"
local BLIT = {}
for i = 0, 15 do BLIT[2 ^ i] = HEX:sub(i + 1, i + 1) end

local function at(x, y, text, fg, bg)
  d.setCursorPos(x, y)
  d.setBackgroundColour(bg or K.black)
  d.setTextColour(fg or K.white)
  d.write(text)
end
local function pad(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s > w then return s:sub(1, w) end
  return s .. (" "):rep(w - #s)
end
local function centre(s, w)
  s = tostring(s):sub(1, w)
  local l = math.floor((w - #s) / 2)
  return (" "):rep(l) .. s .. (" "):rep(w - #s - l)
end
local function lr(x, y, w, left, right, fgL, fgR, bg)
  left = tostring(left)
  if right then
    right = tostring(right):sub(1, w)
    local room = w - #right - 1
    if #left > room then left = room > 0 and left:sub(1, room) or "" end
  end
  at(x, y, pad(left, w), fgL or K.lightGrey, bg)
  if right then at(x + w - #right, y, right, fgR or K.white, bg) end
end
local function bar(x, y, w, frac, colour)
  if w <= 0 then return end
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  at(x, y, (" "):rep(w), K.white, K.grey)
  if n > 0 then at(x, y, (" "):rep(n), K.white, colour) end
end
local function hit(x1, y1, x2, y2, fn) hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn } end
local function button(x, y, w, rows, label, bg, fn, fg)
  for r = 0, rows - 1 do at(x, y + r, (" "):rep(w), K.black, bg) end
  label = label:sub(1, w)
  at(x + math.floor((w - #label) / 2), y + math.floor(rows / 2), label, fg or K.black, bg)
  hit(x, y, x + w - 1, y + rows - 1, fn)
end
local function smallButton(x, y, label, bg, fn, fg)
  at(x, y, " " .. label .. " ", fg or K.black, bg)
  hit(x, y, x + #label + 1, y, fn)
  return x + #label + 3
end
local function header(w, title, right, rightCol)
  at(1, 1, (" "):rep(w), K.cyan, K.grey)
  at(2, 1, title, K.cyan, K.grey)
  if right and #right + #title + 4 < w then at(w - #right, 1, right, rightCol or K.lightGrey, K.grey) end
  if ui.notice and os.clock() < ui.notice.untilT then at(2, 2, pad(ui.notice.text, w - 2), ui.notice.colour) end
end
local function say(text, colour, only)
  for _, v in ipairs(views) do
    if not only or v.ui == only then v.ui.notice = { text = text, colour = colour or K.lime, untilT = os.clock() + 6 } end
  end
end
FX.notify = function(text, colour) say(text, colour) end
local function wrap(text, w)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end
local function go(page, extra)
  ui.page, ui.confirm, ui.scroll = page, nil, 1
  for k, v in pairs(extra or {}) do ui[k] = v end
end

-- Little helpers for the animations: a cheap repeatable "random" number
local function nz(a, b, c) return (a * 73 + b * 151 + (c or 0) * 37 + a * b * 7) % 97 end
local FLAME_FG = { K.red, K.orange, K.yellow, K.orange }
local FLAME_CH = { "\30", "^", "\30", "'" }

---------------------------------------------------------------------------
-- Home: the furnace array as tiles (fastest first), the trainer, rules and the queue
---------------------------------------------------------------------------
local function itemShort(name)
  local s = pretty(name):gsub("^raw ", "")
  if s == "cobblestone" then return "cobble" end
  return (s:gsub("^cobbled ", "cob "))
end

---------------------------------------------------------------------------
-- Factories: the setups (feed barrel -> factory -> out barrel) and the ores they've learned
---------------------------------------------------------------------------
-- A peripheral by name: exact, any case, or the end of it ("barrel_65")
function FX.findPeripheral(word)
  if not word then return nil end
  if peripheral.isPresent(word) then return word end
  local lw = word:lower()
  local tail
  for _, n in ipairs(peripheral.getNames()) do
    if n:lower() == lw then return n end
    if n:lower():sub(-#lw - 1) == ":" .. lw or n:lower():sub(-#lw - 1) == "_" .. lw or n:lower():sub(-#lw) == lw then
      tail = tail and false or n          -- only if it's the one match
    end
  end
  return tail or nil
end

function FX.usedByFactory(n)
  for i, f in ipairs(cfg.factories) do
    if f.machine == n or f.feed == n or f.out == n then return i end
  end
end

function FX.addFactory(machine, feed, out)
  cfg.factories[#cfg.factories + 1] = { machine = machine, feed = feed, out = out }
  saveCfg()
  return #cfg.factories
end

function FX.removeFactory(i)
  local fs = FX.facs[i]
  local f = cfg.factories[i]
  if fs and fs.trial and f then FX.endTrial(i) end
  if f then FX.restoreSettings(f.machine) end
  table.remove(cfg.factories, i)
  table.remove(FX.facs, i)
  saveCfg()
end

-- Barrel names with the newest (highest number) first: the one you just placed is near the top
function FX.numLast(n) return tonumber(n:match("(%d+)$")) or -1 end
function FX.barrelCandidates(skip)
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "inventory") and not isFurnace(n) and n ~= cfg.trainer and not FX.usedByFactory(n)
       and not (skip and skip[n]) and not FX.factoryLike(n) then
      out[#out + 1] = n
    end
  end
  table.sort(out, function(a, b)
    local na, nb = FX.numLast(a), FX.numLast(b)
    if na ~= nb then return na > nb end
    return a < b
  end)
  return out
end
function FX.machineCandidates()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if not FX.usedByFactory(n) and FX.factoryLike(n) then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

function FX.facColour(i)
  local fs = FX.facs[i]
  if not fs then return K.grey end
  if fs.trial then return K.yellow end
  if fs.why then return K.orange end
  return K.lime
end

function FX.drawFactoryCard(x, y, w, maxY)
  at(x, y, pad("FACTORIES", w), K.cyan)
  hit(x, y, x + w - 1, y, function() go("factories") end)
  y = y + 1
  if #cfg.factories == 0 then
    at(x, y, pad("none: tap to add", w), K.grey)
    hit(x, y, x + w - 1, y, function() go("factories") end)
    return y + 2
  end
  for i in ipairs(cfg.factories) do
    if y > maxY then break end
    lr(x, y, w, "F" .. i, FX.factoryLine(i), K.white, FX.facColour(i))
    hit(x, y, x + w - 1, y, function() go("factories", { sel = i }) end)
    y = y + 1
  end
  return y + 1
end

function FX.drawFactories(w, h)
  header(w, "< FACTORIES", ("%d set up"):format(#cfg.factories))
  hit(1, 1, 13, 1, function() go("home") end)
  local y = 3
  local bottom = h - 2
  if #cfg.factories == 0 then
    local lines = {
      { "No factories yet.", K.white },
      { "A factory setup: a FEED barrel on the cable with a hopper upgrade pushing into the factory's Input face, the factory with a wired modem on it, and auto-eject into an OUT barrel on the cable. Tap + Add and pick the three.", K.lightGrey },
    }
    for _, l in ipairs(lines) do
      for _, t in ipairs(wrap(l[1], w - 4)) do if y <= bottom then at(3, y, t, l[2]); y = y + 1 end end
      y = y + 1
    end
  end
  for i, f in ipairs(cfg.factories) do
    if y + 2 > bottom then break end
    local sel = ui.sel == i
    local bg = sel and K.grey or K.black
    local fs = FX.facs[i] or {}
    local right = fs.energy and ("%d%% power"):format(math.floor(fs.energy * 100 + 0.5)) or ""
    lr(2, y, w - 2, FX.factoryName(i) .. ": " .. FX.factoryLine(i), right, FX.facColour(i), K.lightGrey, bg)
    lr(2, y + 1, w - 2, "  " .. shortName(f.machine), fs.procs and (fs.procs .. " processes") or nil, K.lightGrey, K.grey, bg)
    lr(2, y + 2, w - 2, ("  feed %s -> out %s"):format(shortName(f.feed), shortName(f.out)), nil, K.grey, K.grey, bg)
    hit(1, y, w, y + 2, function() ui.sel = (ui.sel == i) and nil or i; ui.confirm = nil end)
    y = y + 4
  end
  -- What it's learned about ores
  local list = FX.enrichList()
  if #list > 0 and y < bottom then
    at(2, y, pad("ORES", w - 2), K.cyan)
    y = y + 1
    for _, o in ipairs(list) do
      if y > bottom then break end
      local e = o.e
      local left = itemShort(o.ore) .. (e.out and (" -> " .. e.made .. " " .. itemShort(e.out) .. " per " .. e.used) or "")
      local col = (o.state == "direct" or o.state == "via dust") and K.lime or (o.state == "checking dust" and K.yellow or K.orange)
      lr(2, y, w - 2, left, o.state, K.white, col)
      y = y + 1
    end
  end
  -- Footer
  at(1, h, (" "):rep(w))
  if cmdLine then return end
  local x = 2
  x = smallButton(x, h, "+ Add", K.lime, function() go("fadd", { step = "machine", pickM = nil, pickF = nil }) end)
  if ui.sel and cfg.factories[ui.sel] then
    if ui.confirm == "remove" then
      x = smallButton(x, h, "Sure? Remove F" .. ui.sel, K.red, function()
        FX.removeFactory(ui.sel)
        say("Factory removed. Storage stops treating its barrels specially in a few seconds.", K.orange)
        ui.sel, ui.confirm = nil, nil
      end, K.white)
    else
      x = smallButton(x, h, "Remove F" .. ui.sel, K.grey, function() ui.confirm = "remove" end, K.white)
    end
  end
  smallButton(w - 7, h, "Back", K.grey, function() go("home") end, K.white)
end

function FX.drawFactoryAdd(w, h)
  local step = ui.step or "machine"
  local n = step == "machine" and 1 or (step == "feed" and 2 or 3)
  header(w, "< ADD A FACTORY", ("step %d/3"):format(n))
  hit(1, 1, 16, 1, function() go("factories") end)
  local hints = {
    machine = "Pick the factory (wired modem on it, ring red):",
    feed = "Pick its FEED barrel (hopper upgrade into the factory):",
    out = "Pick its OUT barrel (the factory ejects into it):",
  }
  at(2, 3, pad(hints[step], w - 2), K.lightGrey)
  local chosen = {}
  if ui.pickM then chosen[ui.pickM] = true end
  if ui.pickF then chosen[ui.pickF] = true end
  local list = step == "machine" and FX.machineCandidates() or FX.barrelCandidates(chosen)
  local top, bottom = 4, h - 2
  local done = {}
  if ui.pickM then done[#done + 1] = "factory " .. shortName(ui.pickM) end
  if ui.pickF then done[#done + 1] = "feed " .. shortName(ui.pickF) end
  if #done > 0 then at(2, h - 1, pad(table.concat(done, ", "), w - 2), K.grey) end
  local per = bottom - top
  local pages = math.max(1, math.ceil(#list / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))
  local y = top
  for k = 1, per do
    local name = list[(ui.scroll - 1) * per + k]
    if not name then break end
    lr(2, y, w - 2, name, nil, K.white)
    hit(1, y, w, y, function()
      if step == "machine" then ui.pickM, ui.step, ui.scroll = name, "feed", 1
      elseif step == "feed" then ui.pickF, ui.step, ui.scroll = name, "out", 1
      else
        local i = FX.addFactory(ui.pickM, ui.pickF, name)
        say(("%s added: feed %s -> out %s"):format(FX.factoryName(i), shortName(ui.pickF), shortName(name)), K.lime)
        go("factories", { sel = i })
      end
    end)
    y = y + 1
  end
  if #list == 0 then
    at(2, y, step == "machine" and "No factory on my cable: put a wired modem on it, right-click it." or "No barrels left on my cable.", K.orange)
  end
  at(1, h, (" "):rep(w))
  if cmdLine then return end
  local x = 2
  if pages > 1 then
    x = smallButton(x, h, "<", ui.scroll > 1 and K.cyan or K.grey, function() ui.scroll = math.max(1, ui.scroll - 1) end)
    at(x, h, ("%d/%d"):format(ui.scroll, pages), K.lightGrey); x = x + #("%d/%d"):format(ui.scroll, pages) + 1
    x = smallButton(x, h, ">", ui.scroll < pages and K.cyan or K.grey, function() ui.scroll = math.min(pages, ui.scroll + 1) end)
  end
  smallButton(w - 9, h, "Cancel", K.grey, function() go("factories") end, K.white)
end

local function drawTile(fz, idx, x, y, w, th)
  local s = fstate[fz]
  local t = tierOf(fz)
  local active = s and s.inp
  local spi, measured = spiOf(fz)
  -- Line 1: the tier band (+ a flame flickering on the end while it cooks)
  local label = t[2]
  if #label > w - 2 then label = t[6] end
  if #label > w - 2 then label = label:sub(1, w - 2) end
  if th == 1 then
    -- One line: colour chip, item, count
    local k = math.floor(frame / 2) % 4 + 1                 -- one beat for every tile (2 a second)
    at(x, y, active and FLAME_CH[k] or " ", active and FLAME_FG[k] or t[5], t[4])
    local txt = active and (itemShort(s.inp.name)) or "idle"
    local cnt = active and tostring(s.inp.count) or ""
    at(x + 1, y, pad(" " .. txt, w - 1 - #cnt), active and K.white or K.grey)
    if #cnt > 0 then at(x + w - #cnt, y, cnt, K.lightGrey) end
  else
    at(x, y, pad(" " .. label, w), t[5], t[4])
    if active then
      local k = math.floor(frame / 2) % 4 + 1
      at(x + w - 1, y, FLAME_CH[k], FLAME_FG[k], t[4])
    end
    -- Line 2: what's in it
    local txt = active and itemShort(s.inp.name) or (s and "idle" or "can't see it")
    at(x, y + 1, pad(" " .. txt, w), active and K.white or K.grey)
    if th >= 3 then
      -- Line 3: how many left, and finished items waiting (+N). Nothing moves here.
      local row = y + 2
      at(x, row, (" "):rep(w))
      if active then
        at(x + 1, row, "x" .. s.inp.count, K.lightGrey)
      else
        at(x + 1, row, "--", K.grey)
      end
      if s and s.out then
        local o = "+" .. s.out.count
        at(x + w - #o, row, o, K.lime)
      elseif not active then
        local sp = ("%.1fs"):format(spi)
        if #sp + 4 <= w then at(x + w - #sp, row, sp, measured and K.lightGrey or K.grey) end
      end
    end
  end
  hit(x, y, x + w - 1, y + th - 1, function()
    local sp, m = spiOf(fz)
    local what = (s and s.inp) and (s.inp.count .. " " .. pretty(s.inp.name)) or "empty"
    say(("%s: %s. %.2fs per item (%s)"):format(shortName(fz), what, sp, m and "measured" or "tier"), K.white)
  end)
end

-- Fit the array into the box: 3-line tiles (a blank row between rows if there's room), then 2,
-- then 1-line rows, then pages. The tier band on top of each tile keeps them apart.
local function gridLayout(n, gw, gh)
  local cols = math.max(1, math.floor((gw + 1) / 9))
  local tw = math.floor((gw - (cols - 1)) / cols)
  for _, th in ipairs({ 3, 2 }) do
    for _, gap in ipairs({ 1, 0 }) do
      local rows = math.floor((gh + gap) / (th + gap))
      if rows * cols >= n then return th, cols, tw, rows, th + gap end
    end
  end
  cols = math.max(1, math.floor((gw + 1) / 13))
  tw = math.floor((gw - (cols - 1)) / cols)
  return 1, cols, tw, gh, 1
end

local function drawTrainerCard(x, y, w)
  at(x, y, pad("TRAINER", w), K.cyan)
  local line, col = "", K.lightGrey
  if not cfg.trainer then line, col = "not set: tap TRAIN", K.grey
  elseif not trainSeen then line, col = "can't see it!", K.orange
  else
    local stt = train.state
    if stt == "starting" or stt == "fuelling" or stt == "cooking" then
      local dots = ("..."):sub(1, frame % 4)
      line, col = "learning " .. itemShort(train.input) .. dots, K.yellow
    elseif stt == "learned" and os.clock() - (train.endedAt or 0) < 60 then
      line, col = "learned " .. itemShort(train.out), K.lime
    elseif trainSlots.inp then
      line, col = ("%d %s: tap TRAIN"):format(trainSlots.inp.count, itemShort(trainSlots.inp.name)), (frame % 4 < 2) and K.yellow or K.white
    else
      line, col = "ready", K.lightGrey
    end
  end
  at(x, y + 1, pad(line, w), col)
  hit(x, y, x + w - 1, y + 1, function() go("train") end)
  return y + 3
end

local function ruleTag(rule)
  if rule.all then
    local n = inputTotal(rule.r)
    return n > 0 and ("all, " .. fmtNum(n) .. " in") or "all", n > 0 and K.orange or K.lime
  end
  local have, want = outCount(rule.r), rule.stacks * 64
  return ("%s/%s"):format(fmtNum(have), fmtNum(want)), have >= want and K.lime or K.orange
end

local function drawRules(x, y, w, maxY)
  at(x, y, pad("RULES", w), K.cyan)
  y = y + 1
  if #smeltRules == 0 then
    at(x, y, pad("none yet", w), K.grey); y = y + 1
  end
  for i, rule in ipairs(smeltRules) do
    if y > maxY then break end
    if y == maxY and i < #smeltRules then
      at(x, y, pad(("+%d more: Recipes"):format(#smeltRules - i + 1), w), K.grey)
      hit(x, y, x + w - 1, y, function() go("recipes") end)
      y = y + 1
      break
    end
    local tag, col = ruleTag(rule)
    lr(x, y, w, rule.name:gsub("_", " "), tag, K.white, col)
    hit(x, y, x + w - 1, y, function() go("rule", { key = rule.name, edit = nil }) end)
    y = y + 1
  end
  return y
end

local function drawQueue(x, y, w, maxY)
  local any = false
  for _, j in ipairs(smeltQueue) do if j.left > 0 then any = true end end
  if not any or y + 1 > maxY then return y end
  y = y + 1
  at(x, y, pad("ONE-OFF JOBS", w), K.cyan)
  y = y + 1
  for _, j in ipairs(smeltQueue) do
    if y > maxY then break end
    if j.left > 0 then
      lr(x, y, w, j.name:gsub("_", " "), fmtNum(j.left) .. " left", K.white, K.yellow)
      y = y + 1
    end
  end
  return y
end

local function drawHome(w, h)
  local right
  if cfg.paused then right = "PAUSED"
  elseif not storageFresh() then right = "no storage!"
  else right = ("%d furnace%s  %d cooking"):format(#array, #array == 1 and "" or "s", activeCount) end
  header(w, "SMELTER", right, (cfg.paused or not storageFresh()) and K.orange or K.lightGrey)

  local side = w >= 44
  local rw = side and math.max(18, math.min(22, math.floor(w * 0.32))) or 0
  local gw = side and (w - rw - 3) or (w - 2)
  local top, bottom = 3, h - 2
  local gh = bottom - top + 1

  -- The array
  if #array == 0 then
    local lines = { "No furnaces on my cable.", "Put furnaces (any Iron Furnaces tier) on the",
                    "storage cable with a wired modem each." }
    for i, l in ipairs(lines) do if top + i <= bottom then at(2, top + i, pad(l, gw), i == 1 and K.white or K.lightGrey) end end
  else
    local th, cols, tw, rows, step = gridLayout(#array, gw, gh)
    local per = cols * rows
    local pages = math.max(1, math.ceil(#array / per))
    ui.scroll = math.max(1, math.min(ui.scroll, pages))
    ui.pages = pages
    for i = 1, per do
      local idx = (ui.scroll - 1) * per + i
      local fz = array[idx]
      if not fz then break end
      local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
      drawTile(fz, idx, 2 + c * (tw + 1), top + r * step, tw, th)
    end
  end

  -- Right column: trainer, rules, one-off jobs
  if side then
    local x = w - rw
    for yy = top, bottom do at(x - 2, yy, " ", K.grey, K.black) end
    for yy = top, bottom do at(x - 1, yy, "\149", K.grey) end
    local y = drawTrainerCard(x, top, rw)
    y = FX.drawFactoryCard(x, y, rw, math.min(bottom - 3, y + 3))
    local queueRows = 0
    for _, j in ipairs(smeltQueue) do if j.left > 0 then queueRows = queueRows + 1 end end
    local ruleMax = bottom - (queueRows > 0 and math.min(queueRows + 2, 5) or 0)
    y = drawRules(x, y, rw, ruleMax)
    drawQueue(x, y, rw, bottom)
  end

  -- Footer
  local fy = h
  at(1, fy, (" "):rep(w))
  if cmdLine then return end
  local x = 2
  local trainCol = (cfg.trainer and trainSlots.inp and train.state == "idle") and ((frame % 4 < 2) and K.yellow or K.lime) or K.lime
  x = smallButton(x, fy, "TRAIN", trainCol, function() go("train") end)
  x = smallButton(x, fy, "Recipes", K.cyan, function() go("recipes") end)
  x = smallButton(x, fy, cfg.paused and "Run" or "Pause", cfg.paused and K.lime or K.orange, function()
    cfg.paused = not cfg.paused; saveCfg()
    say(cfg.paused and "Paused: nothing new goes in (finished items still come out)." or "Smelting again.", cfg.paused and K.orange or K.lime)
  end)
  x = smallButton(x, fy, "Factories", K.lightBlue, function() go("factories") end)
  local pages = ui.pages or 1
  if pages > 1 then
    local label = ("%d/%d"):format(ui.scroll, pages)
    local px = w - #label - 9
    if px > x then
      smallButton(px, fy, "<", ui.scroll > 1 and K.cyan or K.grey, function() ui.scroll = math.max(1, ui.scroll - 1) end)
      at(px + 4, fy, label, K.lightGrey)
      smallButton(w - 3, fy, ">", ui.scroll < pages and K.cyan or K.grey, function() ui.scroll = math.min(pages, ui.scroll + 1) end)
    end
  end
end

---------------------------------------------------------------------------
-- Training page: a furnace that comes alive
---------------------------------------------------------------------------
-- The furnace: stone body, dark mouth, fire inside when lit (dies down when done), smoke above
local function drawFurnaceArt(x, y, fw, fh, heat)
  local mh = math.max(2, math.floor(fh / 3))
  local my = fh - 1 - mh            -- first mouth row (one row of stone under it)
  for r = 0, fh - 1 do
    local txt, fg, bg = {}, {}, {}
    for c = 0, fw - 1 do
      local ch, f, b = " ", K.white, K.lightGrey
      local edge = r == 0 or r == fh - 1 or c == 0 or c == fw - 1
      if edge then b = K.grey
      elseif nz(r, c) % 6 == 0 then b = K.grey end
      if r == 1 and c >= math.floor(fw / 2) - 2 and c <= math.floor(fw / 2) + 1 then b = K.black end   -- the top slot
      if r >= my and r < my + mh and c >= 2 and c <= fw - 3 then
        b = K.black
        if heat > 0 then
          -- flames: each column flickers to its own height, hotter at the bottom
          local depth = my + mh - 1 - r               -- 0 = bottom row of the mouth
          local hgt = (nz(c, frame) % (mh + 1)) * heat
          if depth < hgt then
            local k = depth == 0 and 3 or ((nz(c, r, frame) % 2 == 0) and 2 or 1)
            b = ({ K.red, K.orange, K.yellow })[k]
            ch, f = (nz(r, c, frame) % 3 == 0) and "\30" or " ", K.yellow
          elseif depth == 0 then
            b = K.red
          end
        end
      end
      txt[#txt + 1], fg[#fg + 1], bg[#bg + 1] = ch, BLIT[f], BLIT[b]
    end
    d.setCursorPos(x, y + r)
    d.blit(table.concat(txt), table.concat(fg), table.concat(bg))
  end
  -- Smoke rising off the top while it burns
  if heat > 0 then
    for k = 0, 2 do
      local life = (frame + k * 3) % 6
      local sy = y - 1 - math.floor(life / 2)
      local sx = x + math.floor(fw / 2) - 1 + (nz(k, math.floor((frame + k * 3) / 6)) % 3) - 1 + ((life >= 4) and 1 or 0)
      if sy >= 3 then at(sx, sy, life < 2 and "o" or (life < 4 and "." or "'"), life < 3 and K.lightGrey or K.grey) end
    end
  end
end

local function card(x, y, w, h, title, titleBg, lines)
  at(x, y, centre(title, w), K.black, titleBg)
  for r = 1, h - 1 do
    local l = lines[r]
    local text, col = "", K.lightGrey
    if type(l) == "table" then text, col = l[1], l[2] elseif l then text = l end
    at(x + 1, y + r, centre(text, w - 2), col, K.black)
  end
  -- side rails
  for r = 1, h - 1 do
    at(x, y + r, " ", K.black, K.grey)
    at(x + w - 1, y + r, " ", K.black, K.grey)
  end
  at(x, y + h, (" "):rep(w), K.black, K.grey)
end

local function itemLines(name, count, w)
  local out = {}
  for _, l in ipairs(wrap(pretty(name), w - 2)) do out[#out + 1] = { l, K.white } end
  while #out > 3 do table.remove(out) end
  if count then out[#out + 1] = { "x" .. count, K.lightGrey } end
  return out
end

local function drawArrow(x, y, aw, moving)
  for i = 0, aw - 1 do
    local lit = moving and ((frame - i) % aw == 0)
    at(x + i, y, (i == aw - 1) and "\16" or "-", lit and K.yellow or (moving and K.grey or K.grey))
  end
end

local function drawRuleChoice(x, y, w, rows, key, mode, stacks, onPick)
  -- [-] [ KEEP 4 STACKS ] [+]  [ SMELT ALL ]  [ JUST LEARN ]
  local keepW = math.max(13, math.min(17, w - 36))
  local allW, noneW = 11, 12
  local gap = math.max(1, math.floor((w - (3 + 1 + keepW + 1 + 3 + allW + noneW)) / 2))
  local bx = x
  button(bx, y, 3, rows, "-", K.grey, function() train.stacks = math.max(1, (train.stacks or 4) - 1); ui.pickMode = "keep" end, K.white)
  bx = bx + 4
  local sel = ui.pickMode or mode
  button(bx, y, keepW, rows, ("KEEP %d STACK%s"):format(stacks, stacks == 1 and "" or "S"),
    sel == "keep" and K.lime or K.lightGrey, function() onPick("keep") end)
  bx = bx + keepW + 1
  button(bx, y, 3, rows, "+", K.grey, function() train.stacks = math.min(999, (train.stacks or 4) + 1); ui.pickMode = "keep" end, K.white)
  bx = bx + 3 + gap
  button(bx, y, allW, rows, "SMELT ALL", sel == "all" and K.lime or K.lightGrey, function() onPick("all") end)
  bx = bx + allW + gap
  button(bx, y, noneW, rows, "JUST LEARN", K.grey, function() onPick(nil) end, K.white)
end

local function drawTrain(w, h)
  header(w, "< TRAINING", cfg.trainer and shortName(cfg.trainer) or nil)
  hit(1, 1, 12, 1, function() go("home") end)
  local big = h >= 22
  local bottomRows = big and 3 or 1
  local fy = h

  if not cfg.trainer then
    local lines = {
      { "No training furnace yet.", K.white },
      { "Put a furnace (any kind) somewhere out of the way, on the storage cable with a wired modem. It's only ever used for training, never for the smelting array.", K.lightGrey },
    }
    local y = 4
    for _, l in ipairs(lines) do
      for _, t in ipairs(wrap(l[1], w - 4)) do at(3, y, t, l[2]); y = y + 1 end
      y = y + 1
    end
    button(3, y + 1, math.min(26, w - 4), bottomRows, "PICK THE TRAINER", K.lime, function() go("pick") end)
    at(1, fy, (" "):rep(w))
    smallButton(w - 7, fy, "Back", K.grey, function() go("home") end, K.white)
    return
  end

  local stt = train.state
  local cooking = stt == "starting" or stt == "fuelling" or stt == "cooking"
  local doneAgo = train.endedAt and (os.clock() - train.endedAt) or 999
  local heat = cooking and 1 or ((stt == "learned" and doneAgo < 3) and 0.5 or 0)

  -- Scene: [IN card] -> [furnace] -> [OUT card]
  local fw = big and 16 or 14
  local fh = big and 9 or 7
  local cw = math.max(10, math.min(15, math.floor((w - fw - 10) / 2)))
  local aw = math.max(3, math.floor((w - fw - 2 * cw - 4) / 2))
  local total = cw * 2 + aw * 2 + fw + 2
  local sx = math.max(2, math.floor((w - total) / 2) + 1)
  local smokeRows = big and 3 or 2
  local sy = 3 + smokeRows
  local fx = sx + cw + aw + 1
  local cardY = sy + math.floor((fh - 5) / 2)

  -- IN
  local inLines
  local inName = (cooking or stt == "learned" or stt == "failed") and train.input or (trainSlots.inp and trainSlots.inp.name)
  if inName then
    local cnt = (trainSlots.inp and trainSlots.inp.name == inName) and trainSlots.inp.count or nil
    inLines = itemLines(inName, cnt, cw)
  else
    inLines = { { "empty", K.grey }, { "drop it in", K.grey }, { "the top", K.grey } }
  end
  local inReady = stt == "idle" and trainSlots.inp
  card(sx, cardY, cw, 5, "PUT IN", inReady and ((frame % 4 < 2) and K.yellow or K.white) or K.lightGrey, inLines)
  drawArrow(sx + cw + 1, cardY + 2, aw - 1, cooking)

  drawFurnaceArt(fx, sy, fw, fh, heat)

  drawArrow(fx + fw + 1, cardY + 2, aw - 1, stt == "cooking")
  -- OUT
  local ox = fx + fw + aw + 1
  if stt == "learned" then
    card(ox, cardY, cw, 5, "COMES OUT", K.lime, itemLines(train.out, train.per > 1 and (train.per .. " each") or "1 each", cw))
    if doneAgo < 6 then          -- sparkles round the new recipe
      for k = 0, 9 do
        local px = ox - 1 + nz(k, frame) % (cw + 2)
        local py = cardY - 1 + nz(frame, k) % 7
        local ch = ({ "*", "+", "." })[nz(k, k, frame) % 3 + 1]
        if py >= 3 and py < h - 3 and (px < ox or px >= ox + cw or py < cardY or py > cardY + 5) then
          at(px, py, ch, (k + frame) % 2 == 0 and K.yellow or K.white)
        end
      end
    end
  elseif stt == "failed" then
    card(ox, cardY, cw, 5, "COMES OUT", K.red, { { "nothing", K.orange }, { "X", K.red } })
  else
    local q = cooking and ((frame % 4 < 2) and K.yellow or K.white) or K.grey
    card(ox, cardY, cw, 5, "COMES OUT", K.lightGrey, { "", { "?", q } })
  end

  -- What's happening, under the scene
  local y = sy + fh + 1
  local function text(t, col)
    for _, l in ipairs(wrap(t, w - 4)) do if y < h - bottomRows - 1 then at(3, y, pad(l, w - 4), col); y = y + 1 end end
  end
  if not trainSeen then
    text("I can't see the training furnace (" .. cfg.trainer .. "). Is its modem on (red ring)?", K.orange)
  elseif cooking then
    local steps = {
      { "Output slot clear", stt ~= "starting" },
      { "Fuel in", stt == "cooking" },
      { "First one cooked", false },
    }
    local sxp = 3
    for _, s in ipairs(steps) do
      local mark = s[2] and "\4 " or ("\7 ")
      local t = mark .. s[1]
      at(sxp, y, t, s[2] and K.lime or K.grey)
      sxp = sxp + #t + 3
    end
    y = y + 1
    if stt == "cooking" then
      local el = os.clock() - (train.fuelAt or os.clock())
      local label = ("%ds"):format(math.floor(el))
      bar(3, y, w - 6 - #label - 1, el / TRAIN_TIMEOUT, el > TRAIN_TIMEOUT * 0.6 and K.orange or K.yellow)
      at(w - 2 - #label, y, label, K.lightGrey)
      y = y + 1
      text(("Cooking one %s... (I give up after %ds)"):format(pretty(train.input), TRAIN_TIMEOUT), K.lightGrey)
    else
      text(train.note or "Getting it ready...", K.lightGrey)
    end
  elseif stt == "learned" then
    local how = train.per > 1 and (" (" .. train.per .. " each)") or ""
    text((train.known and "Already knew this one: " or "Learned: ") .. pretty(train.input) .. " -> " .. pretty(train.out) .. how, K.lime)
    text(("What should I do with %s?"):format(pretty(train.out)), K.white)
    local by = h - bottomRows - 1 - (big and 0 or 0)
    drawRuleChoice(3, by, w - 4, bottomRows, train.key, train.mode, train.stacks or 4, function(mode)
      if mode then setRule(train.key, mode, train.stacks or 4) end
      say(mode == "all" and ("Rule saved: smelt all " .. train.key) or mode == "keep" and
        ("Rule saved: keep %d stacks of %s"):format(train.stacks or 4, train.key) or ("Learned " .. train.key .. ", no rule."), K.lime)
      train = { state = "idle", giveBack = train.giveBack, input = train.input, seen = true }
      ui.pickMode = nil
      go("home")
    end)
  elseif stt == "failed" then
    text(train.reason or "That didn't work.", K.orange)
    text("It goes back into storage.", K.lightGrey)
  elseif trainSlots.inp then
    text(("Ready: %d %s in the top slot."):format(trainSlots.inp.count, pretty(trainSlots.inp.name)), K.white)
    text("Tap TRAIN and I'll fuel it and watch what comes out.", K.lightGrey)
  else
    text("Put the raw item in the trainer's TOP slot, then tap TRAIN.", K.white)
    text("One is enough. Leftovers go back into storage.", K.lightGrey)
  end

  -- Big buttons (not while choosing a rule)
  if stt ~= "learned" then
    local by = h - bottomRows - 1
    if cooking then
      button(3, by, 14, bottomRows, "CANCEL", K.grey, function()
        train = { state = "idle", giveBack = true, input = train.input, seen = true }
        say("Training cancelled: it goes back into storage.", K.orange)
      end, K.white)
    else
      local ready = trainSlots.inp ~= nil
      local col = ready and ((frame % 4 < 2) and K.lime or K.yellow) or K.grey
      button(3, by, 14, bottomRows, stt == "failed" and "TRY AGAIN" or "TRAIN", col, function()
        local ok, why = startTraining()
        if not ok then say(why, K.orange) end
      end, ready and K.black or K.lightGrey)
    end
  end

  at(1, fy, (" "):rep(w))
  if cmdLine then return end
  local x = 2
  x = smallButton(x, fy, "Change trainer", K.grey, function() go("pick") end, K.white)
  x = smallButton(x, fy, "Recipes", K.cyan, function() go("recipes") end)
  smallButton(w - 7, fy, "Back", K.grey, function() go("home") end, K.white)
end

---------------------------------------------------------------------------
-- Pick the trainer
---------------------------------------------------------------------------
local function drawPick(w, h)
  header(w, "< PICK THE TRAINER", picking and "watching..." or nil, K.yellow)
  hit(1, 1, 20, 1, function() picking = nil; go("train") end)
  local top, bottom = 3, h - 2
  if picking then
    local left = math.max(0, math.ceil(picking.untilT - os.clock()))
    local spin = ({ "|", "/", "-", "\\" })[frame % 4 + 1]
    local lines = {
      { spin .. " Drop any item into the TOP slot of the furnace you want.", K.white },
      { "The smelting array is paused while I watch.", K.lightGrey },
      { ("%d s left"):format(left), K.yellow },
    }
    local y = top + 2
    for _, l in ipairs(lines) do
      for _, t in ipairs(wrap(l[1], w - 4)) do at(3, y, t, l[2]); y = y + 1 end
    end
    bar(3, y + 1, w - 6, left / FIND_TIME, K.yellow)
    button(3, bottom - 2, 14, 3 <= (bottom - y - 2) and 3 or 1, "STOP", K.grey, function() picking = nil end, K.white)
    at(1, h, (" "):rep(w))
    return
  end
  local list = allFurnaces()
  at(2, top, pad(w >= 56 and "Tap one to make it the trainer (it leaves the array):" or "Tap one to make it the trainer:", w - 2), K.lightGrey)
  local y = top + 1
  local per = bottom - y + 1
  local pages = math.max(1, math.ceil(#list / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))
  for i = 1, per do
    local fz = list[(ui.scroll - 1) * per + i]
    if not fz then break end
    local t = tierOf(fz)
    local s = fz == cfg.trainer and trainSlots or fstate[fz] or {}
    local what = s.inp and (s.inp.count .. " " .. itemShort(s.inp.name)) or "empty"
    at(2, y, pad(" " .. t[2], 13), t[5], t[4])
    lr(16, y, w - 16, shortName(fz), fz == cfg.trainer and "TRAINER" or what, fz == cfg.trainer and K.lime or K.white,
      fz == cfg.trainer and K.lime or K.grey)
    hit(1, y, w, y, function()
      local was = fstate[fz]
      cfg.trainer = fz; saveCfg(); findFurnaces()
      train = { state = "idle", clear = (was and (was.inp or was.out)) and true or nil, seen = true }
      say(shortName(fz) .. " is the trainer now." .. (train.clear and " Emptying its old smelting first." or " It's out of the smelting array."), K.lime)
      go("train")
    end)
    y = y + 1
  end
  if #list == 0 then at(2, y, "No furnaces on my cable.", K.orange) end
  at(1, h, (" "):rep(w))
  if cmdLine then return end
  local x = 2
  x = smallButton(x, h, "Find it", K.yellow, function()
    picking = { untilT = os.clock() + FIND_TIME, before = {} }
  end)
  if cfg.trainer then
    x = smallButton(x, h, "No trainer", K.grey, function()
      say(shortName(cfg.trainer) .. " is back in the smelting array.", K.orange)
      cfg.trainer = nil; saveCfg(); train = { state = "idle" }; go("home")
    end, K.white)
  end
  if pages > 1 then
    x = smallButton(x, h, "<", K.cyan, function() ui.scroll = math.max(1, ui.scroll - 1) end)
    x = smallButton(x, h, ">", K.cyan, function() ui.scroll = math.min(pages, ui.scroll + 1) end)
  end
  smallButton(w - 7, h, "Back", K.grey, function() go("train") end, K.white)
end

---------------------------------------------------------------------------
-- Recipes: everything it knows
---------------------------------------------------------------------------
local function drawRecipes(w, h)
  local keys = sortedKeys(book)
  local nLearned = 0
  for _, k in ipairs(keys) do if book[k].learned then nLearned = nLearned + 1 end end
  header(w, "< RECIPES", ("%d known, %d learned"):format(#keys, nLearned))
  hit(1, 1, 11, 1, function() go("home") end)
  local top, bottom = 3, h - 1
  local cols = (w >= 90) and 2 or 1
  local cw = math.floor((w - 1) / cols)
  local per = (bottom - top + 1) * cols
  local pages = math.max(1, math.ceil(#keys / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))
  for i = 1, per do
    local k = keys[(ui.scroll - 1) * per + i]
    if not k then break end
    local r = book[k]
    local c, row = math.floor((i - 1) / (bottom - top + 1)), (i - 1) % (bottom - top + 1)
    local x, y = 2 + c * cw, top + row
    local bg = row % 2 == 1 and K.black or K.black
    local rule = ruleFor(k)
    local tag = rule and (rule.all and "all" or ("keep " .. rule.stacks)) or ""
    local from = r.pattern and "any log" or (#r.inputs > 0 and pretty(r.inputs[1]) .. (#r.inputs > 1 and (" +" .. (#r.inputs - 1)) or "") or "?")
    local nameW = math.min(18, math.floor(cw * 0.34))
    at(x, y, pad(k:gsub("_", " "), nameW), r.learned and K.yellow or K.white, bg)
    lr(x + nameW + 1, y, cw - nameW - 2, from .. " \26 " .. itemShort(r.out), tag, K.lightGrey, K.lime, bg)
    hit(x, y, x + cw - 2, y, function() go("rule", { key = k, edit = nil }) end)
  end
  at(1, h, (" "):rep(w))
  if cmdLine then return end
  local x = 2
  at(x, h, "yellow = learned", K.yellow); x = x + 18
  if pages > 1 then
    local label = ("%d/%d"):format(ui.scroll, pages)
    local px = w - #label - 17
    smallButton(px, h, "<", ui.scroll > 1 and K.cyan or K.grey, function() ui.scroll = math.max(1, ui.scroll - 1) end)
    at(px + 4, h, label, K.lightGrey)
    smallButton(px + 5 + #label, h, ">", ui.scroll < pages and K.cyan or K.grey, function() ui.scroll = math.min(pages, ui.scroll + 1) end)
  end
  smallButton(w - 7, h, "Back", K.grey, function() go("home") end, K.white)
end

---------------------------------------------------------------------------
-- One recipe: its rule (keep N stacks / smelt all / none), smelt now, forget
---------------------------------------------------------------------------
local function drawRule(w, h)
  local key = ui.key
  local name, r = recipeFor(key)
  header(w, "< " .. name:gsub("_", " "):upper(), r.learned and "learned" or (r.builtin and "built in" or "guessed: modded metal"))
  hit(1, 1, #name + 4, 1, function() go(ui.back or "home") end)
  local rule = ruleFor(name)
  if not ui.edit then
    ui.edit = { mode = rule and (rule.all and "all" or "keep") or nil, stacks = rule and rule.stacks or 4 }
  end
  local e = ui.edit
  local y = 3
  local function line(l, rv, cl, cr)
    if y < h - 1 then lr(3, y, w - 4, l, rv, cl or K.lightGrey, cr or K.white) end
    y = y + 1
  end
  line("Makes", pretty(r.out))
  if r.pattern then line("From", r.modded and ("raw " .. name .. " (any mod)") or "any log") end
  for _, i in ipairs(r.inputs) do
    local per = perOf(r, i)
    line("From", pretty(i) .. (per > 1 and (" (" .. per .. " each)") or ""))
  end
  for _, ore in ipairs(sortedKeys(cfg.enrich)) do
    local e = cfg.enrich[ore]
    if type(e) == "table" and e.out and not e.dustBad and (isInputOf(r, e.out) or (FX.direct.kind(book, ore, e) == "direct" and outMatches(r, e.out))) then
      line("Factory", ("%s -> %d %s per %d"):format(pretty(ore), e.made, pretty(e.out), e.used), K.lightGrey, K.lime)
    end
  end
  line("In storage", ("%s made, %s to smelt"):format(fmtNum(outCount(r)), fmtNum(inputTotal(r))))
  y = y + 1

  -- Rule
  if y < h - 1 then at(3, y, "RULE", K.cyan) end
  y = y + 1
  local rows = h >= 22 and 3 or 1
  local bx = 3
  button(bx, y, 3, rows, "-", K.grey, function() e.mode = "keep"; e.stacks = math.max(1, e.stacks - 1) end, K.white)
  bx = bx + 4
  button(bx, y, 15, rows, ("KEEP %d STACK%s"):format(e.stacks, e.stacks == 1 and "" or "S"), e.mode == "keep" and K.lime or K.lightGrey,
    function() e.mode = "keep" end)
  bx = bx + 16
  button(bx, y, 3, rows, "+", K.grey, function() e.mode = "keep"; e.stacks = math.min(999, e.stacks + 1) end, K.white)
  bx = bx + 4
  if bx + 11 <= w then
    button(bx, y, 11, rows, "SMELT ALL", e.mode == "all" and K.lime or K.lightGrey, function() e.mode = "all" end)
    bx = bx + 12
  end
  if bx + 9 <= w then
    button(bx, y, 9, rows, "NO RULE", e.mode == nil and K.orange or K.lightGrey, function() e.mode = nil end)
  end
  y = y + rows
  if y < h - 1 then
    local now = rule and (rule.all and "smelt all" or ("keep " .. rule.stacks .. " stacks")) or "none"
    local changed = (e.mode ~= (rule and (rule.all and "all" or "keep") or nil)) or (e.mode == "keep" and rule and rule.stacks ~= e.stacks)
    at(3, y, pad(("Now: %s%s"):format(now, changed and "   (tap SAVE)" or ""), w - 4), changed and K.yellow or K.grey)
  end
  y = y + 2

  -- Smelt now
  if y + rows <= h - 1 then
    at(3, y, "SMELT NOW", K.cyan)
    y = y + 1
    local x = 3
    for _, n in ipairs({ 64, 256, 1024 }) do
      button(x, y, 8, rows, tostring(n), K.lightGrey, function()
        queueSmelt(name, n); say(("Queued %d %s."):format(n, name), K.lime)
      end)
      x = x + 9
    end
    local all = inputTotal(r)
    button(x, y, 12, rows, "ALL " .. fmtNum(all), all > 0 and K.lightGrey or K.grey, function()
      if all > 0 then queueSmelt(name, all); say(("Queued %d %s."):format(all, name), K.lime) end
    end)
  end

  -- Footer: Save / Forget / Back
  at(1, h, (" "):rep(w))
  if cmdLine then return end
  local x = 2
  x = smallButton(x, h, "SAVE", K.lime, function()
    setRule(name, e.mode, e.stacks)
    say(e.mode == "all" and ("Saved: smelt all " .. name) or e.mode == "keep" and ("Saved: keep %d stacks of %s"):format(e.stacks, name)
      or ("Saved: no rule for " .. name), K.lime)
    go(ui.back or "home")
  end)
  if r.learned then
    if ui.confirm == "forget" then
      x = smallButton(x, h, "Sure? Forget", K.red, function()
        forget(name); say("Forgot what I learned about " .. name .. ".", K.orange); go("recipes")
      end, K.white)
    else
      x = smallButton(x, h, "Forget", K.grey, function() ui.confirm = "forget" end, K.white)
    end
  end
  smallButton(w - 7, h, "Back", K.grey, function() go(ui.back or "home") end, K.white)
end

---------------------------------------------------------------------------
-- Draw everything
---------------------------------------------------------------------------
local function drawCmdLine(w, h)
  if not cmdLine then return end
  at(1, h, (" "):rep(w), K.white, K.grey)
  local shown = cmdLine
  if #shown > w - 4 then shown = shown:sub(-(w - 4)) end
  at(1, h, "> " .. shown, K.white, K.grey)
  at(3 + #shown, h, (frame % 4 < 2) and "_" or " ", K.yellow, K.grey)
end

local function draw()
  frame = FX.kit.anim == "off" and 0 or FX.kit.beat(4)      -- the kit's shared beat (4 a second)
  for _, v in ipairs(views) do
    d = v.dev()
    if d then
      hits = {}
      ui = v.ui
      local ok, err = pcall(function()
        if v.kind == "monitor" then d.setTextScale(TEXT_SCALE) end
        local w, h = d.getSize()
        if not w then return end
        d.setBackgroundColour(K.black); d.clear()
        if ui.page == "train" then drawTrain(w, h)
        elseif ui.page == "pick" then drawPick(w, h)
        elseif ui.page == "recipes" then drawRecipes(w, h)
        elseif ui.page == "rule" then drawRule(w, h)
        elseif ui.page == "factories" then FX.drawFactories(w, h)
        elseif ui.page == "fadd" then FX.drawFactoryAdd(w, h)
        else drawHome(w, h) end
        if v.kind == "term" then drawCmdLine(w, h) end
      end)
      v.hits = hits
      v.err = not ok and err or nil
      if not ok and v.kind == "monitor" then mon, monSide = findMonitor() end
    end
  end
end

-- Seconds until the screen next needs drawing without an event: the next beat while something moves (the
-- Train and Pick pages and the trainer card at 4 a second, cooking tiles at 2), else 1.
local function nextDraw()
  if FX.kit.anim == "off" then return 1 end
  local fast = cmdLine ~= nil or (cfg.trainer and trainSlots.inp ~= nil)
  for _, v in ipairs(views) do
    if v.ui.page == "train" or v.ui.page == "pick" then fast = true end
  end
  if fast then return math.max(FX.kit.nextBeat(4) - os.clock(), 0.05) end
  if activeCount > 0 then return math.max(FX.kit.nextBeat(2) - os.clock(), 0.05) end
  return 1
end

---------------------------------------------------------------------------
-- Terminal commands (type anywhere on the computer's own screen)
---------------------------------------------------------------------------
local HELP = "smelt <item> <n> | train | recipes | rule <item> | trainer | factories | factory add <machine> <feed> <out> | probe [item] [factory] | probe stop | factory remove <n> | enrich add <item> | enrich forget <ore> | pause | run | home"
local function runCommand(line)
  ui = views[2].ui
  local q = line:lower():gsub("^%s*/", ""):gsub("^%s+", ""):gsub("%s+$", "")
  local item, amount = q:match("^smelt%s+(%S+)%s+(%d+)$")
  if item then
    say(("Queued %d %s."):format(tonumber(amount), queueSmelt(item, tonumber(amount))), K.lime, ui)
  elseif q == "train" then go("train")
  elseif q == "trainer" or q == "pick" then go("pick")
  elseif q == "recipes" then go("recipes")
  elseif q:match("^rule%s+%S+$") then go("rule", { key = recipeFor(q:match("^rule%s+(%S+)$")), edit = nil })
  elseif q == "pause" then cfg.paused = true; saveCfg(); say("Paused.", K.orange)
  elseif q == "run" or q == "resume" or q == "go" then cfg.paused = false; saveCfg(); say("Smelting again.")
  elseif q == "reload" then loadSmeltRules(); say(("Loaded %d rule(s) from smelt.txt."):format(#smeltRules), K.lime, ui)
  elseif q == "home" or q == "" then go("home")
  elseif q == "factories" or q == "factory" then go("factories")
  elseif q == "probe stop" then
    local i = FX.probeActive()
    FX.probeReq = nil
    if i then FX.probeEnd(i, FX.facs[i].trial, { kind = "stopped" }) end
    say("Probe stopped.", K.orange, ui)
  elseif q:match("^probe") then
    local item, which = nil, nil
    for w in q:gmatch("%S+") do
      if w:match("^%d+$") then which = tonumber(w)
      elseif w ~= "probe" then item = w:find(":") and w or ("minecraft:" .. w:gsub("^minecraft:", "")) end
    end
    say(FX.probeStart(item, which), K.white, ui)
  elseif q:match("^factory%s+add") then
    local m, fd, o = line:match("[Aa][Dd][Dd]%s+(%S+)%s+(%S+)%s+(%S+)")
    local pm, pf, po = FX.findPeripheral(m), FX.findPeripheral(fd), FX.findPeripheral(o)
    if not (m and fd and o) then say("factory add <machine> <feed barrel> <out barrel>", K.white, ui)
    elseif not pm or not FX.factoryLike(pm) then say("No factory called " .. m .. " on my cable.", K.orange, ui)
    elseif not pf or not peripheral.hasType(pf, "inventory") then say("No barrel called " .. fd .. " on my cable.", K.orange, ui)
    elseif not po or not peripheral.hasType(po, "inventory") or po == pf then say("No (other) barrel called " .. o .. " on my cable.", K.orange, ui)
    elseif FX.usedByFactory(pm) or FX.usedByFactory(pf) or FX.usedByFactory(po) then say("One of those is already in a factory setup.", K.orange, ui)
    else
      local i = FX.addFactory(pm, pf, po)
      say(("%s added: feed %s -> out %s"):format(FX.factoryName(i), shortName(pf), shortName(po)), K.lime, ui)
      go("factories", { sel = i })
    end
  elseif q:match("^factory%s+remove%s+%d+$") then
    local i = tonumber(q:match("(%d+)$"))
    if cfg.factories[i] then FX.removeFactory(i); say("Factory " .. i .. " removed.", K.orange, ui)
    else say("No factory " .. i .. ".", K.orange, ui) end
  elseif q:match("^enrich%s+forget%s+%S+$") then
    local word = q:match("(%S+)$")
    local gone = 0
    for _, ore in ipairs(FX.direct.match(word, sortedKeys(cfg.enrich))) do
      cfg.enrich[ore] = nil; FX.trialCool[ore] = nil; gone = gone + 1
    end
    saveCfg()
    say(gone > 0 and ("Forgot what the factories learned about " .. word .. ": it gets tried again.") or ("Nothing learned about " .. word .. "."), K.lime, ui)
  elseif q:match("^enrich%s+add%s+%S+$") then
    local word = q:match("(%S+)$")
    local names = {}
    for name in pairs(byName) do names[#names + 1] = name end
    for _, name in ipairs(cfg.enrichExtra) do names[#names + 1] = name end
    table.sort(names)
    local found = FX.direct.match(word, names)
    if #found == 0 and word:find(":", 1, true) then found = { word } end
    if #found == 0 then say("No '" .. word .. "' in storage. Use the full id (mod:item) if there is none yet.", K.orange, ui)
    elseif #found > 1 then
      local short = {}
      for i = 1, math.min(#found, 4) do short[i] = shortName(found[i]) end
      say("Which one? " .. table.concat(short, ", "), K.orange, ui)
    else
      local item = found[1]
      if FX.direct.addExtra(cfg.enrichExtra, item) then
        saveCfg()
        say(pretty(item) .. " will be tried in a factory.", K.lime, ui)
      else say(pretty(item) .. " is on the list already.", K.white, ui) end
    end
  elseif q == "status" then
    local st = smeltStatus()
    say(table.concat(st, " | "), K.white, ui)
  else say(HELP, K.white, ui) end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function workLoop()
  while true do
    local ok, err = pcall(smeltPass)
    if not ok then smeltNote = "Error: " .. tostring(err) end
    redraw()
    os.sleep(TICK)
  end
end

local function trainLoop()
  while true do
    local ok, err = pcall(trainStep)
    if not ok then train.note = "Error: " .. tostring(err) end
    local ok2, err2 = pcall(FX.trialStep)
    if not ok2 then smeltNote = "Factory error: " .. tostring(err2) end
    local ok3, err3 = pcall(FX.autoTrainStep)
    if not ok3 then train.note = "Error: " .. tostring(err3) end
    -- An item dropped into an idle trainer: bring the training page up on the monitor
    if train.state == "idle" and trainSlots.inp and not train.seen then
      train.seen = true
      if views[1].ui.page == "home" then views[1].ui.page = "train" end
      redraw()
    elseif not trainSlots.inp then train.seen = nil end
    if picking then
      local found = pickStep()
      if found == "timeout" then say("Nothing was dropped in. Try again, or tap it in the list.", K.orange)
      elseif found then
        cfg.trainer = found; saveCfg(); findFurnaces()
        train = { state = "idle", seen = true }
        say(shortName(found) .. " is the trainer now. Tap TRAIN to learn what you dropped in.", K.lime)
        for _, v in ipairs(views) do if v.ui.page == "pick" then v.ui.page = "train" end end
      end
      redraw()
      os.sleep(1)
    else
      os.sleep(0.5)
    end
  end
end

local function netLoop()
  local lastSend = -100
  while true do
    local from, msg = rednet.receive(BASE, 1)
    if type(msg) == "table" then
      if msg.type == "storage" then
        storageId, storageSeen = from, os.clock()
        if type(msg.items) == "table" then byName = msg.items end
      elseif msg.type == "smelt_done" then
        inbox[#inbox + 1] = msg
      elseif msg.type == "smelt_cmd" and msg.seq ~= lastCmd then
        lastCmd = msg.seq
        if msg.item and tonumber(msg.amount) then queueSmelt(tostring(msg.item), tonumber(msg.amount)) end
        lastSend = -100
      end
    end
    if os.clock() - lastSend >= 3 then
      rednet.broadcast({ type = "smelter", id = os.getComputerID(), label = os.getComputerLabel(),
        state = cfg.paused and "paused" or "ok", paused = cfg.paused or false, training = trainLine(),
        note = trainLine() or smeltNote, lines = smeltStatus(), furnaces = #array, lastCmd = lastCmd,
        factories = FX.factoryBarrels() }, BASE)
      lastSend = os.clock()
    end
  end
end

local function uiLoop()
  FX.kit.loadAnim("smelter.env")
  draw()
  local timer = os.startTimer(FRAME)
  while true do
    local e, a, b, c = os.pullEvent()
    local v, x, y
    if e == "timer" and a == timer then
      draw()
      timer = os.startTimer(nextDraw())
    elseif e == "smelter_draw" then
      draw()
    elseif e == "monitor_touch" and a == monSide then v, x, y = views[1], b, c
    elseif e == "mouse_click" then v, x, y = views[2], b, c
    elseif e == "mouse_scroll" then
      local u = views[2].ui
      u.scroll = math.max(1, (u.scroll or 1) + a)
      draw()
    elseif e == "char" then
      cmdLine = (cmdLine or "") .. a
      draw()
    elseif e == "paste" then
      cmdLine = (cmdLine or "") .. a
      draw()
    elseif e == "key" then
      if cmdLine then
        if a == keys.enter or a == keys.numPadEnter then
          local l = cmdLine; cmdLine = nil; runCommand(l); draw()
        elseif a == keys.backspace then
          cmdLine = #cmdLine > 0 and cmdLine:sub(1, -2) or nil; draw()
        end
      elseif a == keys.backspace then
        ui = views[2].ui
        if ui.page ~= "home" then go(ui.page == "pick" and "train" or (ui.page == "fadd" and "factories" or "home")) end
        draw()
      elseif a == keys.enter or a == keys.numPadEnter then
        ui = views[2].ui
        if ui.page == "train" and train.state ~= "learned" then
          local ok, why = startTraining()
          if not ok then say(why, K.orange, ui) end
        end
        draw()
      end
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      mon, monSide = findMonitor(); draw()
    end
    if v then
      ui = v.ui
      for _, r in ipairs(v.hits) do
        if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then r.fn(x, y); break end
      end
      draw()
    end
  end
end

-- Talk on every modem: the wired one reaches storage over the cable, a wireless one (if any) the mainframe too
local opened = 0
peripheral.find("modem", function(name) rednet.open(name); opened = opened + 1; return false end)
if opened == 0 then
  printError("I need a modem: a wired modem on the storage cable is enough.")
  return
end
loadCfg()
buildBook()
loadSmeltRules()
findFurnaces()
do
  local t = FX.ts.recover(cfg)
  if t then
    train = t
    FX.notify(("Restarted mid-training: %s goes back into storage, nothing learned from that run."):format(pretty(t.input or "?")), K.orange)
  end
  if FX.cfgNote then saveCfg(); FX.notify(FX.cfgNote, K.orange) end
end
parallel.waitForAny(workLoop, trainLoop, netLoop, uiLoop)
