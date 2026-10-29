-- smelter_factory.lua  --  smelter: Mekanism factories: routing, the drip trial, probe, adding and removing setups
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local FX, K, call, cfg, has, isFurnace = S.FX, S.K, S.call, S.cfg, S.has, S.isFurnace
local isInputOf, outMatches, perOf, pretty, redraw, saveCfg = S.isInputOf, S.outMatches, S.perOf, S.pretty, S.redraw, S.saveCfg
local shortName, sortedKeys = S.shortName, S.sortedKeys


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
      FX.print(text)
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
    if s.drainedAt and S.storageSeen and S.storageSeen > s.drainedAt + 0.5 then s.drained, s.drainedAt = {}, nil end
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
  if FX.direct.kind(S.book, ore, e) == "direct" then
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
  for _, k in ipairs(sortedKeys(S.book)) do
    if has(S.book[k].inputs, dust) then return S.book[k] end
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
    elseif FX.direct.kind(S.book, ore, e) == "direct" then state = "direct"
    elseif FX.dustRecipe(e.out) then state = "via dust"
    else state = "checking dust" end
    out[#out + 1] = { ore = ore, e = e, state = state }
  end
  return out
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
  if text then FX.notify(text, col); FX.print(text) end
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
    cfg.enrich[t.input] = FX.drip.result(t, v.product, v.made, FX.direct.furnaceRecipe(S.book, t.input, v.product) ~= nil)
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
  FX.print(text)
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
    FX.print("Uploading " .. FX.PROBE_LOG .. " to pastebin...")
    if not pcall(shell.run, "pastebin", "put", FX.PROBE_LOG) then FX.print("Upload failed: run  pastebin put " .. FX.PROBE_LOG) end
    FX.print("")
  else
    FX.print("Run  pastebin put " .. FX.PROBE_LOG .. "  to share it.")
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
end
