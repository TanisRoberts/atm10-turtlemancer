-- smelter_pass.lua  --  smelter: the smelting pass: reading the furnaces, fair shares, giving and serving work through storage
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local CHUNK, FUEL_VALUE, FX, K, SMELT_FUELS, TICK = S.CHUNK, S.FUEL_VALUE, S.FX, S.K, S.SMELT_FUELS, S.TICK
local TOPUP_AT, cfg, findFurnaces, isInputOf, learn, loadSmeltRules = S.TOPUP_AT, S.cfg, S.findFurnaces, S.isInputOf, S.learn, S.loadSmeltRules
local outCount, outMatches, perOf, pretty, readOne, recipeFor = S.outCount, S.outMatches, S.perOf, S.pretty, S.readOne, S.recipeFor
local saveCfg, sendBatch, shortName, smeltQueue, spiOf, storageFresh = S.saveCfg, S.sendBatch, S.shortName, S.smeltQueue, S.spiOf, S.storageFresh

---------------------------------------------------------------------------
-- One smelting pass: read the furnaces, measure them, plan the moves, have storage do them
---------------------------------------------------------------------------
local samples = {}           -- furnace -> { name, count, t, filled } from the last pass
local speedDirty, speedSaved = false, os.clock()
S.activeCount = 0

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
  if os.clock() - S.lastSmeltLoad > 30 then loadSmeltRules() end
  findFurnaces()
  local st = {}
  local busy, cooked = {}, {}
  S.activeCount = 0
  for _, fz in ipairs(S.array) do
    local s = readOne(fz)
    st[fz] = s
    if s then
      sampleSpeed(fz, s.inp)
      if s.inp then busy[s.inp.name] = (busy[s.inp.name] or 0) + s.inp.count; S.activeCount = S.activeCount + 1 end
      if s.out then cooked[s.out.name] = (cooked[s.out.name] or 0) + s.out.count end
    end
  end
  S.fstate = st
  if speedDirty and os.clock() - speedSaved > 60 then saveCfg(); speedDirty, speedSaved = false, os.clock() end
  for i in ipairs(cfg.factories) do FX.readFactory(i) end

  if #S.array == 0 then S.smeltNote = cfg.trainer and "Only the trainer on my cable" or "No furnaces on my cable network"; return end
  if not storageFresh() then S.smeltNote = "Waiting for the storage computer"; return end

  local have = {}
  for k, v in pairs(S.byName) do have[k] = v end
  local ops = {}

  -- 1. Finished items back into storage
  for _, fz in ipairs(S.array) do
    if st[fz] and st[fz].out then ops[#ops + 1] = { op = "store", fz = fz, slot = 3 } end
  end

  -- 2. Hand out work, 8 items at a time, each to the furnace that would finish it soonest
  local slots = {}
  for _, fz in ipairs(S.array) do
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
    if type(e) == "table" and e.out and FX.direct.kind(S.book, input, e) == "direct" then
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
      local direct = FX.direct.kind(S.book, o.input, o.e) == "direct"
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

  if not cfg.paused and not S.picking then
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
    for _, rule in ipairs(S.smeltRules) do
      rule.working = wantOf(rule) > 0 and hasInput(rule.r)
      if rule.working then working = working + 1 elseif not rule.all then FX.shortSince[rule.name] = nil end
    end
    capN = math.max(1, math.ceil(#slots / math.max(1, working)))
    for _, rule in ipairs(S.smeltRules) do
      if rule.working then capR = rule.r; serve(rule.r, wantOf(rule), nil, not rule.all and rule.name or nil) end
    end
    capFree = true
    for _, rule in ipairs(S.smeltRules) do
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
    if not results then S.smeltNote = "Storage didn't answer"; return end
  end
  -- Dusts I couldn't check in the trainer: learn them by name
  for dust, out in pairs(guesses) do
    if not FX.dustRecipe(dust) then learn(dust, out, 1); FX.notify("No trainer: guessing " .. pretty(dust) .. " smelts into " .. pretty(out), K.yellow) end
  end
  local queued = 0
  for _, j in ipairs(smeltQueue) do queued = queued + math.max(0, j.left) end
  if cfg.paused then S.smeltNote = "Paused"
  elseif S.activeCount > 0 then
    S.smeltNote = ("Smelting %d/%d%s"):format(S.activeCount, #S.array, queued > 0 and (", " .. queued .. " queued") or "")
  else
    S.smeltNote = queued > 0 and (queued .. " queued, waiting for input") or "Idle"
  end
end

S.smeltPass = smeltPass
end
