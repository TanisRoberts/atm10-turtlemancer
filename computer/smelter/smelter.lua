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
---------------------------------------------------------------------------
local cfg = { trainer = nil, paused = false, learned = {}, speed = {} }
local function loadCfg()
  if fs.exists(CONFIG) then
    local f = fs.open(CONFIG, "r"); local t = textutils.unserialize(f.readAll() or ""); f.close()
    if type(t) == "table" then
      for k, v in pairs(t) do cfg[k] = v end
    end
  end
  if type(cfg.learned) ~= "table" then cfg.learned = {} end
  if type(cfg.speed) ~= "table" then cfg.speed = {} end
end
local function saveCfg()
  local f = fs.open(CONFIG .. ".new", "w"); f.write(textutils.serialize(cfg)); f.close()
  if fs.exists(CONFIG) then fs.delete(CONFIG) end
  fs.move(CONFIG .. ".new", CONFIG)
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
  local function give(input, amount, job)
    local left = amount
    while left > 0 do
      local best, bestT
      for _, f in ipairs(slots) do
        if (f.name == nil or f.name == input) and (f.count <= TOPUP_AT or f.add > 0) then
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

  if not cfg.paused and not picking then
    -- One-off jobs first, oldest first
    local i = 1
    while i <= #smeltQueue do
      local job = smeltQueue[i]
      if job.left <= 0 then table.remove(smeltQueue, i)
      else
        local input, n = inputFor(job.r, have)
        if input and n > 0 then give(input, math.min(job.left, n), job) end
        i = i + 1
      end
    end
    -- Then the standing rules, in smelt.txt order
    for _, rule in ipairs(smeltRules) do
      local r = rule.r
      local input, n = inputFor(r, have)
      if input and n > 0 then
        if rule.all then
          give(input, n)
        else
          local made = outCount(r)
          for name, c in pairs(cooked) do if outMatches(r, name) then made = made + c end end
          for name, c in pairs(busy) do if isInputOf(r, name) then made = made + c * perOf(r, name) end end
          local want = rule.stacks * 64 - made
          if want > 0 then give(input, math.min(n, math.ceil(want / perOf(r, input)))) end
        end
      end
    end
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
    if not results then smeltNote = "Storage didn't answer"; return end
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
  redraw()
end

local function startTraining()
  if not cfg.trainer then return false, "Pick a training furnace first." end
  local s = trainSlots
  if not s.inp then return false, "Put the raw item in the trainer's TOP slot first." end
  train = { state = "starting", input = s.inp.name, startCount = s.inp.count, startedAt = os.clock() }
  redraw()
  return true
end

local function trainStep()
  if not cfg.trainer then trainSlots, trainSeen = {}, false; return end
  local s = readOne(cfg.trainer)
  if not s then trainSlots, trainSeen = {}, false; return end
  trainSlots, trainSeen = s, true

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

local function smeltStatus()
  local lines = {}
  lines[#lines + 1] = ("%d furnace(s). %s"):format(#array, smeltNote ~= "" and smeltNote or "Idle")
  local tl = trainLine()
  if tl then lines[#lines + 1] = tl end
  for _, j in ipairs(smeltQueue) do
    if j.left > 0 then lines[#lines + 1] = ("Queued: %d %s"):format(j.left, j.name) end
  end
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
    local k = (frame + idx * 3) % 4 + 1
    at(x, y, active and FLAME_CH[k] or " ", active and FLAME_FG[k] or t[5], t[4])
    local txt = active and (itemShort(s.inp.name)) or "idle"
    local cnt = active and tostring(s.inp.count) or ""
    at(x + 1, y, pad(" " .. txt, w - 1 - #cnt), active and K.white or K.grey)
    if #cnt > 0 then at(x + w - #cnt, y, cnt, K.lightGrey) end
  else
    at(x, y, pad(" " .. label, w), t[5], t[4])
    if active then
      local k = (frame + idx * 3) % 4 + 1
      at(x + w - 1, y, FLAME_CH[k], FLAME_FG[k], t[4])
    end
    -- Line 2: what's in it
    local txt = active and itemShort(s.inp.name) or (s and "idle" or "can't see it")
    at(x, y + 1, pad(" " .. txt, w), active and K.white or K.grey)
    if th >= 3 then
      -- Line 3: flames + how many left, and finished items waiting (+N)
      local row = y + 2
      at(x, row, (" "):rep(w))
      if active then
        for c = 0, 1 do
          local k = (nz(idx, c, frame) % 4) + 1
          at(x + 1 + c, row, FLAME_CH[k], FLAME_FG[k])
        end
        at(x + 4, row, "x" .. s.inp.count, K.lightGrey)
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
        else drawHome(w, h) end
        if v.kind == "term" then drawCmdLine(w, h) end
      end)
      v.hits = hits
      v.err = not ok and err or nil
      if not ok and v.kind == "monitor" then mon, monSide = findMonitor() end
    end
  end
end

local function animating()
  for _, v in ipairs(views) do
    if v.ui.page == "train" or v.ui.page == "pick" then return true end
  end
  return activeCount > 0 or (cfg.trainer and trainSlots.inp ~= nil) or cmdLine ~= nil
end

---------------------------------------------------------------------------
-- Terminal commands (type anywhere on the computer's own screen)
---------------------------------------------------------------------------
local HELP = "smelt <item> <n> | train | recipes | rule <item> | trainer | pause | run | reload | home"
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
        note = trainLine() or smeltNote, lines = smeltStatus(), furnaces = #array, lastCmd = lastCmd }, BASE)
      lastSend = os.clock()
    end
  end
end

local function uiLoop()
  draw()
  local timer = os.startTimer(FRAME)
  while true do
    local e, a, b, c = os.pullEvent()
    local v, x, y
    if e == "timer" and a == timer then
      frame = frame + 1
      draw()
      timer = os.startTimer(animating() and FRAME or 1)
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
        if ui.page ~= "home" then go(ui.page == "pick" and "train" or "home") end
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
parallel.waitForAny(workLoop, trainLoop, netLoop, uiLoop)
