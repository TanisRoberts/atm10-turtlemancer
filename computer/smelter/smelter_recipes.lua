-- smelter_recipes.lua  --  smelter: the recipe book (built in + learned), smelt.txt rules, learn and forget
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local SMELT_FILE, cfg, has, saveCfg, shortName, smeltQueue = S.SMELT_FILE, S.cfg, S.has, S.saveCfg, S.shortName, S.smeltQueue
local sortedKeys = S.sortedKeys

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

local function buildBook()
  S.book = {}
  for _, k in ipairs(sortedKeys(BUILTIN)) do
    local r = BUILTIN[k]
    local inputs = {}
    for _, i in ipairs(r.inputs or {}) do inputs[#inputs + 1] = i end
    S.book[k] = { key = k, out = r.out, inputs = inputs, pattern = r.pattern, per = {}, builtin = true }
  end
  for _, k in ipairs(sortedKeys(cfg.learned)) do
    local l = cfg.learned[k]
    if type(l) == "table" and type(l.out) == "string" then
      local host
      for _, bk in ipairs(sortedKeys(S.book)) do if S.book[bk].out == l.out then host = S.book[bk]; break end end
      if not host then
        host = { key = k, out = l.out, inputs = {}, per = {} }
        S.book[k] = host
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
  if S.book[word] then return word, S.book[word] end
  local keys = sortedKeys(S.book)
  local tries = { word, word .. "_ingot", "raw_" .. word, "cooked_" .. word }
  for _, t in ipairs(tries) do
    for _, k in ipairs(keys) do
      local r = S.book[k]
      if r.out == t or shortName(r.out) == t then return k, r end
    end
    for _, k in ipairs(keys) do
      for _, i in ipairs(S.book[k].inputs) do
        if i == t or shortName(i) == t then return k, S.book[k] end
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
  if not r.modded then return S.byName[r.out] or 0 end
  local c = 0
  for name, n in pairs(S.byName) do if outMatches(r, name) then c = c + n end end
  return c
end

-- Best input item in storage for a recipe (the one we have most of)
local function inputFor(r, have)
  have = have or S.byName
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
  for name, c in pairs(S.byName) do if isInputOf(r, name) then n = n + c end end
  return n
end

---------------------------------------------------------------------------
-- Rules (smelt.txt)
---------------------------------------------------------------------------
S.lastSmeltLoad = -100
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
  S.smeltRules = rules
  S.lastSmeltLoad = os.clock()
end

local function ruleFor(key)
  for _, rule in ipairs(S.smeltRules) do if rule.name == key then return rule end end
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
  for _, k in ipairs(sortedKeys(S.book)) do
    local r = S.book[k]
    if r.out == out and isInputOf(r, input) and perOf(r, input) == per then return k, true end
  end
  local key
  for _, k in ipairs(sortedKeys(cfg.learned)) do if cfg.learned[k].out == out then key = k; break end end
  if not key then
    for _, k in ipairs(sortedKeys(S.book)) do if S.book[k].out == out then key = k; break end end
  end
  if not key then
    local base = shortName(out)
    key = base
    local n = 2
    while S.book[key] or cfg.learned[key] do key = base .. "_" .. n; n = n + 1 end
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
  local r = S.book[key]
  if not r then return end
  for _, k in ipairs(sortedKeys(cfg.learned)) do
    if cfg.learned[k].out == r.out then cfg.learned[k] = nil end
  end
  saveCfg()
  buildBook()
  if not S.book[key] and ruleFor(key) then setRule(key, nil) end
  loadSmeltRules()
end

---------------------------------------------------------------------------
-- Talking to storage
---------------------------------------------------------------------------

S.forget, S.inputTotal, S.isInputOf, S.learn, S.loadSmeltRules, S.outCount = forget, inputTotal, isInputOf, learn, loadSmeltRules, outCount
S.outMatches, S.perOf, S.queueSmelt, S.recipeFor, S.ruleFor, S.setRule = outMatches, perOf, queueSmelt, recipeFor, ruleFor, setRule
S.buildBook = buildBook
end
