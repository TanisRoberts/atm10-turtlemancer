-- smelter_train.lua  --  smelter: the training furnace, "Find it" and the factory-dust check
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local FX, K, SMELT_FUELS, TRAIN_TIMEOUT, allFurnaces, call = S.FX, S.K, S.SMELT_FUELS, S.TRAIN_TIMEOUT, S.allFurnaces, S.call
local cfg, isInputOf, learn, pretty, readOne, recipeFor = S.cfg, S.isInputOf, S.learn, S.pretty, S.readOne, S.recipeFor
local redraw, ruleFor, saveCfg, sendBatch, shortName, sortedKeys = S.redraw, S.ruleFor, S.saveCfg, S.sendBatch, S.shortName, S.sortedKeys
local storageFresh = S.storageFresh

---------------------------------------------------------------------------
-- Training furnace
---------------------------------------------------------------------------
S.train = { state = "idle" }   -- idle | starting | fuelling | cooking | learned | failed
S.trainSlots = {}              -- the trainer's slots as last read
S.trainSeen = false            -- could we read it last time
local lastGiveBack = -100

local function bestFuel(have)
  for _, f in ipairs(SMELT_FUELS) do if (have[f] or 0) > 0 then return f end end
end

local function trainFail(text)
  S.train.state, S.train.reason, S.train.endedAt = "failed", text, os.clock()
  S.train.giveBack = true
  if S.train.auto then
    -- A factory dust that won't smelt: that ore stays in the furnaces
    for ore, e in pairs(cfg.enrich) do
      if type(e) == "table" and e.out == S.train.input then e.dustBad = true end
    end
    FX.dustQueue[S.train.input] = nil
    saveCfg()
    FX.notify(pretty(S.train.input) .. " doesn't smelt: its ore stays in the furnaces", K.orange)
  end
  redraw()
end

local function startTraining()
  if not cfg.trainer then return false, "Pick a training furnace first." end
  local s = S.trainSlots
  if not s.inp then return false, "Put the raw item in the trainer's TOP slot first." end
  S.train = { state = "starting", input = s.inp.name, startCount = s.inp.count, startedAt = os.clock() }
  FX.ts.sync(cfg, saveCfg, S.train)
  redraw()
  return true
end

local function trainStep()
  if not cfg.trainer then S.trainSlots, S.trainSeen = {}, false; return end
  local s = readOne(cfg.trainer)
  if not s then S.trainSlots, S.trainSeen = {}, false; return end
  S.trainSlots, S.trainSeen = s, true
  FX.ts.sync(cfg, saveCfg, S.train)

  -- After a training: put the leftovers and the cooked item back in storage
  if S.train.giveBack then
    local backIn = s.inp and s.inp.name == S.train.input
    if not backIn and not s.out then S.train.giveBack = false
    elseif storageFresh() and os.clock() - lastGiveBack > 2 then
      lastGiveBack = os.clock()
      local ops = {}
      if backIn then ops[#ops + 1] = { op = "store", fz = cfg.trainer, slot = 1 } end
      if s.out then ops[#ops + 1] = { op = "store", fz = cfg.trainer, slot = 3 } end
      sendBatch(ops)
    end
  end

  -- A furnace just picked from the list may still hold work from the array: empty it
  if S.train.clear then
    if not s.inp and not s.out then S.train.clear = nil
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
  if S.train.state == "failed" and not S.train.giveBack and s.inp then S.train = { state = "idle", seen = S.train.seen } end

  local stt = S.train.state
  if stt == "starting" then
    if not s.inp or s.inp.name ~= S.train.input then return trainFail("The item was taken out before it cooked.") end
    if s.out then
      -- Something from before is in the output slot: empty it first, so what comes out is new
      if not storageFresh() then S.train.note = "Waiting for storage to empty its output slot"; return end
      S.train.note = "Emptying its output slot"
      sendBatch({ { op = "store", fz = cfg.trainer, slot = 3 } })
      return
    end
    S.train.startCount = s.inp.count
    S.train.state, S.train.note = "fuelling", nil
    stt = "fuelling"
  end
  if stt == "fuelling" then
    if not s.inp or s.inp.name ~= S.train.input then return trainFail("The item was taken out before it cooked.") end
    if s.fuel then
      S.train.state, S.train.fuelAt, S.train.note = "cooking", os.clock(), nil
      stt = "cooking"
    else
      local f = storageFresh() and bestFuel(S.byName)
      if not f then
        S.train.note = storageFresh() and "No coal or charcoal in storage: put some fuel in its bottom slot"
          or "Waiting for storage (or put fuel in its bottom slot)"
        return
      end
      S.train.note = "Fuelling it"
      sendBatch({ { op = "fill", fz = cfg.trainer, slot = 2, item = f, count = 1 } })
      return
    end
  end
  if stt == "cooking" then
    if s.out then
      local left = (s.inp and s.inp.name == S.train.input) and s.inp.count or 0
      local used = S.train.startCount - left
      local per = used > 0 and math.max(1, math.floor(s.out.count / used + 0.5)) or s.out.count
      S.train.out, S.train.per = s.out.name, per
      S.train.key, S.train.known = learn(S.train.input, s.out.name, per)
      if S.train.auto then
        FX.dustQueue[S.train.input] = nil
        -- The ore it came from joins the same recipe (so "aluminum all" covers both), if it isn't in one yet
        for ore, e in pairs(cfg.enrich) do
          if type(e) == "table" and e.out == S.train.input and S.book[S.train.key] and not isInputOf(S.book[S.train.key], ore) then
            local _, hostR = recipeFor(shortName(ore))
            if hostR.modded or not isInputOf(hostR, ore) then learn(ore, s.out.name, 1) end
          end
        end
        FX.notify(("Checked: %s smelts into %s. Enriching from now on."):format(pretty(S.train.input), pretty(s.out.name)), K.lime)
        S.train = { state = "idle", giveBack = true, input = S.train.input, seen = true, endedAt = os.clock() }
        redraw()
        return
      end
      local rule = ruleFor(S.train.key)
      S.train.mode = rule and (rule.all and "all" or "keep") or nil
      S.train.stacks = rule and rule.stacks or 4
      S.train.state, S.train.endedAt, S.train.giveBack = "learned", os.clock(), true
      redraw()
    elseif not s.inp or s.inp.name ~= S.train.input then
      trainFail("The item was taken out before it cooked.")
    elseif os.clock() - S.train.fuelAt > TRAIN_TIMEOUT then
      trainFail(("Nothing came out in %d s: %s doesn't smelt in a furnace."):format(TRAIN_TIMEOUT, pretty(S.train.input)))
    end
  end
end

-- Factory dust that isn't known to smelt yet: put one in the idle trainer and train it
function FX.autoTrainStep()
  if not cfg.trainer or not S.trainSeen or S.train.state ~= "idle" or S.train.giveBack or S.train.clear then return end
  if S.train.autoNext then
    if S.trainSlots.inp and S.trainSlots.inp.name == S.train.autoNext then
      local dust = S.train.autoNext
      local ok = startTraining()
      if ok then S.train.auto = true end
      if not ok then S.train.autoNext = nil end
      return dust
    end
    if os.clock() - (FX.autoTried[S.train.autoNext] or 0) > 15 then S.train.autoNext = nil end
    return
  end
  if S.trainSlots.inp or S.trainSlots.out or not storageFresh() then return end
  for _, dust in ipairs(sortedKeys(FX.dustQueue)) do
    if FX.dustRecipe(dust) then FX.dustQueue[dust] = nil
    elseif (S.byName[dust] or 0) > 0 and os.clock() - (FX.autoTried[dust] or -1e9) > 300 then
      FX.autoTried[dust] = os.clock()
      local res = sendBatch({ { op = "fill", fz = cfg.trainer, slot = 1, item = dust, count = 1 } })
      if res and (tonumber(res[1]) or 0) > 0 then S.train.autoNext = dust; S.train.seen = true end
      return
    end
  end
end

-- "Find it": the furnace whose top slot gains an item (the array is paused meanwhile)
local function pickStep()
  if not S.picking then return end
  if os.clock() > S.picking.untilT then S.picking = nil; return "timeout" end
  for _, fz in ipairs(allFurnaces()) do
    local d = call(fz, "getItemDetail", 1)
    local n = d and d.count or 0
    local before = S.picking.before[fz]
    if before == nil then S.picking.before[fz] = n
    elseif n > before then
      S.picking = nil
      return fz
    end
  end
end

---------------------------------------------------------------------------
-- Status for chat and the mainframe board
---------------------------------------------------------------------------
local function trainLine()
  if not cfg.trainer then return nil end
  local stt = S.train.state
  if stt == "starting" or stt == "fuelling" or stt == "cooking" then return "Training: " .. pretty(S.train.input) end
  if stt == "learned" and os.clock() - (S.train.endedAt or 0) < 60 then
    return ("Learned: %s -> %s"):format(pretty(S.train.input), pretty(S.train.out))
  end
  return nil
end

-- One line about a factory: what it's doing, or why it's down

S.pickStep, S.startTraining, S.trainLine, S.trainStep = pickStep, startTraining, trainLine, trainStep
end
