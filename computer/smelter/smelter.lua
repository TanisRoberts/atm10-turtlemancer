-- smelter.lua  --  auto-smelting computer (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Hardware:
--   * A computer with a WIRED modem on the storage cable network (so it can see the furnaces)
--     and a WIRELESS or ENDER modem (to talk to the storage computer and the mainframe).
--   * Furnaces (incl. Iron Furnaces) on the storage cable network. Blast furnaces/smokers are ignored.
--   * Optional: a monitor for the status.
--
-- The smelter decides WHAT to smelt; the storage computer does every item move (it's the only
-- computer that touches storage), so the two never fight over the same barrels.
--
-- smelt.txt rules:  "stone 20"  keep 20 stacks of stone by smelting cobblestone
--                   "iron all"  smelt every bit of raw iron that comes in
-- One-off jobs:     type "smelt stone 400" here, or say "island smelt stone 400" in chat.
-- Commands here:    smelt <item> <amount> | status | reload | help

local SMELT_FILE = "smelt.txt"
local BASE       = "tanis-base"
local TICK       = 4       -- seconds between smelting passes
local REPLY_WAIT = 8       -- seconds to wait for storage to carry out a batch
local STALE      = 15      -- storage figures older than this aren't trusted

local DEFAULT_SMELT = [[
# Auto-smelting. One rule per line, # for comments. Edits are picked up within 30 seconds.
#   <item> <stacks>   keep that many stacks in storage, e.g.  stone 20
#   <item> all        smelt everything of it that comes in, e.g.  iron all
# Items: stone, smooth_stone, deepslate, glass, iron, gold, copper, charcoal, brick,
# terracotta, cracked_stone_bricks, smooth_sandstone, smooth_quartz, nether_brick,
# netherite_scrap, dried_kelp, green_dye, sponge, or any modded metal by name
# (e.g. "osmium all" smelts raw osmium into ingots).
]]
local RECIPES = {
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
}
RECIPES.iron_ingot, RECIPES.gold_ingot, RECIPES.copper_ingot = RECIPES.iron, RECIPES.gold, RECIPES.copper
local SMELT_FUELS = { "minecraft:charcoal", "minecraft:coal", "minecraft:coal_block", "minecraft:blaze_rod" }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local byName = {}            -- item totals in storage (from the storage computer's broadcast)
local storageId, storageSeen = nil, nil
local smeltRules, smeltQueue = {}, {}
local smeltNote = "Starting"
local furnaces = {}
local lastCmd = nil          -- seq of the last chat command taken, so the mainframe stops repeating it

local function call(name, method, ...)
  local ok, a, b = pcall(peripheral.call, name, method, ...)
  if ok then return a, b end
  return nil, a
end

-- Same rule as storage: furnaces and Iron Furnaces smelt; blast furnaces and smokers are left alone
local function isFurnace(n)
  return n:find("furnace") ~= nil and not n:find("blast") and not n:find("smoker")
end

local function findFurnaces()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if isFurnace(n) and peripheral.hasType(n, "inventory") then out[#out + 1] = n end
  end
  table.sort(out)
  furnaces = out
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
-- Find (or make up) the recipe for a name like "stone", "iron" or "osmium"
local function recipeFor(word)
  word = word:lower():gsub("^minecraft:", "")
  local r = RECIPES[word]
  if r then return word, r end
  -- Modded metals: raw_<x> -> <x>_ingot, in any mod
  return word, { out = ":" .. word .. "_ingot", modded = true, pattern = ":raw_" .. word .. "$" }
end

local function outCount(r)
  if not r.modded then return byName[r.out] or 0 end
  local c = 0
  for name, n in pairs(byName) do if name:find(r.out, 1, true) then c = c + n end end
  return c
end

-- Best input item in storage for a recipe (the one we have most of)
local function inputFor(r, have)
  have = have or byName
  local best, bestN = nil, 0
  if r.inputs then
    for _, name in ipairs(r.inputs) do
      if (have[name] or 0) > bestN then best, bestN = name, have[name] end
    end
  else
    for name, n in pairs(have) do
      if name:find(r.pattern) and n > bestN then best, bestN = name, n end
    end
  end
  return best, bestN
end

local lastSmeltLoad = -100
local function loadSmeltRules()
  if not fs.exists(SMELT_FILE) then
    local f = fs.open(SMELT_FILE, "w"); f.write(DEFAULT_SMELT); f.close()
  end
  local f = fs.open(SMELT_FILE, "r"); local text = f.readAll(); f.close()
  local rules = {}
  for line in text:gmatch("[^\r\n]+") do
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

local function queueSmelt(word, amount)
  local name, r = recipeFor(word)
  smeltQueue[#smeltQueue + 1] = { name = name, r = r, left = amount }
  return name
end

-- What's in the furnaces right now, by item name, so "keep N stacks" targets don't overshoot:
-- inputs waiting to cook, and finished items not yet back in storage.
local cooked = {}
local function inFurnaces()
  local t = {}
  cooked = {}
  for _, fz in ipairs(furnaces) do
    local d = call(fz, "getItemDetail", 1)
    if d then t[d.name] = (t[d.name] or 0) + d.count end
    local o = call(fz, "getItemDetail", 3)
    if o then cooked[o.name] = (cooked[o.name] or 0) + o.count end
  end
  return t
end

-- Pick the next thing to smelt: one-off jobs first, then "keep N stacks", then "all" rules.
-- `have` is this pass's working copy of the storage totals.
local function nextSmeltJob(busy, have)
  local i = 1
  while i <= #smeltQueue do
    local job = smeltQueue[i]
    if job.left <= 0 then table.remove(smeltQueue, i)
    else
      local input, n = inputFor(job.r, have)
      if input and n > 0 then return input, math.min(job.left, n, 64), job end
      i = i + 1
    end
  end
  for _, rule in ipairs(smeltRules) do
    local input, n = inputFor(rule.r, have)
    if input and n > 0 then
      if rule.all then
        return input, math.min(n, 64)
      else
        local want = rule.stacks * 64 - outCount(rule.r) - (busy[input] or 0) - (cooked[rule.r.out] or 0)
        if want > 0 then return input, math.min(want, n, 64) end
      end
    end
  end
end

local function smeltStatus()
  local lines = {}
  lines[#lines + 1] = ("%d furnace(s). %s"):format(#furnaces, smeltNote ~= "" and smeltNote or "Idle")
  for _, j in ipairs(smeltQueue) do
    if j.left > 0 then lines[#lines + 1] = ("Queued: %d %s"):format(j.left, j.name) end
  end
  for _, rule in ipairs(smeltRules) do
    if rule.all then
      local _, n = inputFor(rule.r)
      lines[#lines + 1] = ("Rule: all %s (%d waiting)"):format(rule.name, n or 0)
    else
      lines[#lines + 1] = ("Rule: keep %d stacks of %s (have %d)"):format(rule.stacks, rule.name, outCount(rule.r))
    end
  end
  return lines
end

---------------------------------------------------------------------------
-- One smelting pass: plan the moves, have storage do them
---------------------------------------------------------------------------
local inbox = {}             -- smelt_done replies from storage

local function storageFresh() return storageId and storageSeen and os.clock() - storageSeen < STALE end

local function sendBatch(ops)
  local id = os.epoch("utc")
  rednet.send(storageId, { type = "smelt_ops", id = id, ops = ops }, BASE)
  local t = os.clock() + REPLY_WAIT
  while os.clock() < t do
    for i, m in ipairs(inbox) do
      if m.id == id then table.remove(inbox, i); return m.results end
    end
    os.sleep(0.25)
  end
end

local function smeltPass()
  if os.clock() - lastSmeltLoad > 30 then loadSmeltRules() end
  findFurnaces()
  if #furnaces == 0 then smeltNote = "No furnaces on my cable network"; return end
  if not storageFresh() then smeltNote = "Waiting for the storage computer"; return end

  local have = {}
  for k, v in pairs(byName) do have[k] = v end
  local busy = inFurnaces()
  local ops, meta = {}, {}
  local active = 0
  for _, fz in ipairs(furnaces) do
    -- 1. Finished items back into storage
    if call(fz, "getItemDetail", 3) then ops[#ops + 1] = { op = "store", fz = fz, slot = 3 } end
    -- 2. Feed the input slot if it's empty
    local cur = call(fz, "getItemDetail", 1)
    if not cur then
      local input, n, job = nextSmeltJob(busy, have)
      if input then
        ops[#ops + 1] = { op = "fill", fz = fz, slot = 1, item = input, count = n }
        meta[#ops] = { job = job, planned = n }
        if job then job.left = job.left - n end     -- reserve it, so two furnaces don't both take it
        busy[input] = (busy[input] or 0) + n
        have[input] = (have[input] or 0) - n
        cur = { name = input, count = n }
      end
    end
    -- 3. Keep it fuelled while it has work (1 coal smelts 8 items)
    if cur then
      active = active + 1
      local fuelD = call(fz, "getItemDetail", 2)
      local fuelHave = fuelD and fuelD.count or 0
      local fuelWant = math.ceil(cur.count / 8)
      if fuelHave < fuelWant then
        for _, fuelName in ipairs(SMELT_FUELS) do
          if (have[fuelName] or 0) > 0 and (not fuelD or fuelD.name == fuelName) then
            local per = fuelName == "minecraft:coal_block" and 10 or 1
            local n = math.min(have[fuelName], math.max(1, math.ceil((fuelWant - fuelHave) / per)))
            ops[#ops + 1] = { op = "fill", fz = fz, slot = 2, item = fuelName, count = n }
            have[fuelName] = have[fuelName] - n
            break
          end
        end
      end
    end
  end

  if #ops > 0 then
    local results = sendBatch(ops)
    for i, m in pairs(meta) do       -- give back whatever storage couldn't actually move
      if m.job then m.job.left = m.job.left + m.planned - (results and tonumber(results[i]) or 0) end
    end
    if not results then
      smeltNote = "Storage didn't answer"
      return
    end
  end
  local queued = 0
  for _, j in ipairs(smeltQueue) do queued = queued + math.max(0, j.left) end
  smeltNote = active > 0 and ("Smelting %d/%d%s"):format(active, #furnaces, queued > 0 and (", " .. queued .. " queued") or "")
    or (queued > 0 and (queued .. " queued, waiting for input") or "Idle")
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local mon = peripheral.find("monitor")
local function draw()
  if not mon then return end
  mon.setTextScale(0.5)
  local w, h = mon.getSize()
  mon.setBackgroundColour(colours.black); mon.clear()
  mon.setCursorPos(1, 1); mon.setBackgroundColour(colours.grey); mon.clearLine()
  mon.setTextColour(colours.orange); mon.write(" SMELTER")
  mon.setBackgroundColour(colours.black)
  local lines = smeltStatus()
  for i, l in ipairs(lines) do
    if i + 2 > h then break end
    mon.setCursorPos(2, i + 2)
    mon.setTextColour(i == 1 and colours.white or colours.lightGrey)
    mon.write(l:sub(1, w - 2))
  end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function workLoop()
  while true do
    local ok, err = pcall(smeltPass)
    if not ok then smeltNote = "Error: " .. tostring(err) end
    draw()
    os.sleep(TICK)
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
        note = smeltNote, lines = smeltStatus(), furnaces = #furnaces, lastCmd = lastCmd }, BASE)
      lastSend = os.clock()
    end
  end
end

local function help()
  print("smelt <item> <amount>   queue a one-off job, e.g. smelt stone 400")
  print("status                  what's going on")
  print("reload                  re-read smelt.txt now")
  print("Standing rules live in smelt.txt (edit smelt.txt).")
end

local function terminalLoop()
  term.clear(); term.setCursorPos(1, 1)
  print("Smelter online.")
  help()
  while true do
    print()
    write("smelter> ")
    local q = read():lower()
    local item, amount = q:match("^%s*smelt%s+(%S+)%s+(%d+)")
    if item then
      print(("Queued %d %s."):format(tonumber(amount), queueSmelt(item, tonumber(amount))))
    elseif q:match("reload") then
      loadSmeltRules(); print(("Loaded %d rule(s)."):format(#smeltRules))
    elseif q:match("status") or q == "" then
      for _, l in ipairs(smeltStatus()) do print(l) end
      if not storageFresh() then printError("Not hearing from the storage computer.") end
    else
      help()
    end
  end
end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then
  printError("I need a wireless or ender modem to talk to the storage computer.")
  return
end
rednet.open(peripheral.getName(modem))
loadSmeltRules()
findFurnaces()
parallel.waitForAny(workLoop, netLoop, terminalLoop)
