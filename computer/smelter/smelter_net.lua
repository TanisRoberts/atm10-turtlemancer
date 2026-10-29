-- smelter_net.lua  --  smelter: status for chat and the mainframe, terminal commands, and the background loops
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local BASE, FX, K, TICK, cfg, findFurnaces = S.BASE, S.FX, S.K, S.TICK, S.cfg, S.findFurnaces
local go, inbox, inputTotal, loadSmeltRules, outCount, pickStep = S.go, S.inbox, S.inputTotal, S.loadSmeltRules, S.outCount, S.pickStep
local pretty, queueSmelt, recipeFor, redraw, saveCfg, say = S.pretty, S.queueSmelt, S.recipeFor, S.redraw, S.saveCfg, S.say
local shortName, smeltPass, smeltQueue, sortedKeys, trainLine, trainStep = S.shortName, S.smeltPass, S.smeltQueue, S.sortedKeys, S.trainLine, S.trainStep
local views = S.views

local function smeltStatus()
  local lines = {}
  lines[#lines + 1] = ("%d furnace(s). %s"):format(#S.array, S.smeltNote ~= "" and S.smeltNote or "Idle")
  local tl = trainLine()
  if tl then lines[#lines + 1] = tl end
  for _, j in ipairs(smeltQueue) do
    if j.left > 0 then lines[#lines + 1] = ("Queued: %d %s"):format(j.left, j.name) end
  end
  for i in ipairs(cfg.factories) do lines[#lines + 1] = FX.factoryName(i) .. ": " .. FX.factoryLine(i) end
  for _, rule in ipairs(S.smeltRules) do
    if rule.all then
      lines[#lines + 1] = ("Rule: all %s (%d waiting)"):format(rule.name, inputTotal(rule.r))
    else
      lines[#lines + 1] = ("Rule: keep %d stacks of %s (have %d)"):format(rule.stacks, rule.name, outCount(rule.r))
    end
  end
  return lines
end

---------------------------------------------------------------------------
-- Terminal commands (type anywhere on the computer's own screen)
---------------------------------------------------------------------------
local HELP = "smelt <item> <n> | train | recipes | rule <item> | trainer | factories | factory add <machine> <feed> <out> | probe [item] [factory] | probe stop | factory remove <n> | enrich add <item> | enrich forget <ore> | pause | run | home"
local function runCommand(line)
  S.ui = views[2].ui
  local q = line:lower():gsub("^%s*/", ""):gsub("^%s+", ""):gsub("%s+$", "")
  local item, amount = q:match("^smelt%s+(%S+)%s+(%d+)$")
  if item then
    say(("Queued %d %s."):format(tonumber(amount), queueSmelt(item, tonumber(amount))), K.lime, S.ui)
  elseif q == "train" then go("train")
  elseif q == "trainer" or q == "pick" then go("pick")
  elseif q == "recipes" then go("recipes")
  elseif q:match("^rule%s+%S+$") then go("rule", { key = recipeFor(q:match("^rule%s+(%S+)$")), edit = nil })
  elseif q == "pause" then cfg.paused = true; saveCfg(); say("Paused.", K.orange)
  elseif q == "run" or q == "resume" or q == "go" then cfg.paused = false; saveCfg(); say("Smelting again.")
  elseif q == "reload" then loadSmeltRules(); say(("Loaded %d rule(s) from smelt.txt."):format(#S.smeltRules), K.lime, S.ui)
  elseif q == "home" or q == "" then go("home")
  elseif q == "factories" or q == "factory" then go("factories")
  elseif q == "probe stop" then
    local i = FX.probeActive()
    FX.probeReq = nil
    if i then FX.probeEnd(i, FX.facs[i].trial, { kind = "stopped" }) end
    say("Probe stopped.", K.orange, S.ui)
  elseif q:match("^probe") then
    local item, which = nil, nil
    for w in q:gmatch("%S+") do
      if w:match("^%d+$") then which = tonumber(w)
      elseif w ~= "probe" then item = w:find(":") and w or ("minecraft:" .. w:gsub("^minecraft:", "")) end
    end
    say(FX.probeStart(item, which), K.white, S.ui)
  elseif q:match("^factory%s+add") then
    local m, fd, o = line:match("[Aa][Dd][Dd]%s+(%S+)%s+(%S+)%s+(%S+)")
    local pm, pf, po = FX.findPeripheral(m), FX.findPeripheral(fd), FX.findPeripheral(o)
    if not (m and fd and o) then say("factory add <machine> <feed barrel> <out barrel>", K.white, S.ui)
    elseif not pm or not FX.factoryLike(pm) then say("No factory called " .. m .. " on my cable.", K.orange, S.ui)
    elseif not pf or not peripheral.hasType(pf, "inventory") then say("No barrel called " .. fd .. " on my cable.", K.orange, S.ui)
    elseif not po or not peripheral.hasType(po, "inventory") or po == pf then say("No (other) barrel called " .. o .. " on my cable.", K.orange, S.ui)
    elseif FX.usedByFactory(pm) or FX.usedByFactory(pf) or FX.usedByFactory(po) then say("One of those is already in a factory setup.", K.orange, S.ui)
    else
      local i = FX.addFactory(pm, pf, po)
      say(("%s added: feed %s -> out %s"):format(FX.factoryName(i), shortName(pf), shortName(po)), K.lime, S.ui)
      go("factories", { sel = i })
    end
  elseif q:match("^factory%s+remove%s+%d+$") then
    local i = tonumber(q:match("(%d+)$"))
    if cfg.factories[i] then FX.removeFactory(i); say("Factory " .. i .. " removed.", K.orange, S.ui)
    else say("No factory " .. i .. ".", K.orange, S.ui) end
  elseif q:match("^enrich%s+forget%s+%S+$") then
    local word = q:match("(%S+)$")
    local gone = 0
    for _, ore in ipairs(FX.direct.match(word, sortedKeys(cfg.enrich))) do
      cfg.enrich[ore] = nil; FX.trialCool[ore] = nil; gone = gone + 1
    end
    saveCfg()
    say(gone > 0 and ("Forgot what the factories learned about " .. word .. ": it gets tried again.") or ("Nothing learned about " .. word .. "."), K.lime, S.ui)
  elseif q:match("^enrich%s+add%s+%S+$") then
    local word = q:match("(%S+)$")
    local names = {}
    for name in pairs(S.byName) do names[#names + 1] = name end
    for _, name in ipairs(cfg.enrichExtra) do names[#names + 1] = name end
    table.sort(names)
    local found = FX.direct.match(word, names)
    if #found == 0 and word:find(":", 1, true) then found = { word } end
    if #found == 0 then say("No '" .. word .. "' in storage. Use the full id (mod:item) if there is none yet.", K.orange, S.ui)
    elseif #found > 1 then
      local short = {}
      for i = 1, math.min(#found, 4) do short[i] = shortName(found[i]) end
      say("Which one? " .. table.concat(short, ", "), K.orange, S.ui)
    else
      local item = found[1]
      if FX.direct.addExtra(cfg.enrichExtra, item) then
        saveCfg()
        say(pretty(item) .. " will be tried in a factory.", K.lime, S.ui)
      else say(pretty(item) .. " is on the list already.", K.white, S.ui) end
    end
  elseif q == "status" then
    local st = smeltStatus()
    say(table.concat(st, " | "), K.white, S.ui)
  else say(HELP, K.white, S.ui) end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function workLoop()
  while true do
    local ok, err = pcall(smeltPass)
    if not ok then S.smeltNote = "Error: " .. tostring(err) end
    redraw()
    os.sleep(TICK)
  end
end

local function trainLoop()
  while true do
    local ok, err = pcall(trainStep)
    if not ok then S.train.note = "Error: " .. tostring(err) end
    local ok2, err2 = pcall(FX.trialStep)
    if not ok2 then S.smeltNote = "Factory error: " .. tostring(err2) end
    local ok3, err3 = pcall(FX.autoTrainStep)
    if not ok3 then S.train.note = "Error: " .. tostring(err3) end
    -- An item dropped into an idle trainer: bring the training page up on the monitor
    if S.train.state == "idle" and S.trainSlots.inp and not S.train.seen then
      S.train.seen = true
      if views[1].ui.page == "home" then views[1].ui.page = "train" end
      redraw()
    elseif not S.trainSlots.inp then S.train.seen = nil end
    if S.picking then
      local found = pickStep()
      if found == "timeout" then say("Nothing was dropped in. Try again, or tap it in the list.", K.orange)
      elseif found then
        cfg.trainer = found; saveCfg(); findFurnaces()
        S.train = { state = "idle", seen = true }
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
        S.storageId, S.storageSeen = from, os.clock()
        if type(msg.items) == "table" then S.byName = msg.items end
      elseif msg.type == "smelt_done" then
        inbox[#inbox + 1] = msg
      elseif msg.type == "smelt_cmd" and msg.seq ~= S.lastCmd then
        S.lastCmd = msg.seq
        if msg.item and tonumber(msg.amount) then queueSmelt(tostring(msg.item), tonumber(msg.amount)) end
        lastSend = -100
      end
    end
    if os.clock() - lastSend >= 3 then
      rednet.broadcast({ type = "smelter", id = os.getComputerID(), label = os.getComputerLabel(),
        state = cfg.paused and "paused" or "ok", paused = cfg.paused or false, training = trainLine(),
        note = trainLine() or S.smeltNote, lines = smeltStatus(), furnaces = #S.array, lastCmd = S.lastCmd,
        factories = FX.factoryBarrels() }, BASE)
      lastSend = os.clock()
    end
  end
end

S.runCommand, S.workLoop, S.trainLoop, S.netLoop = runCommand, workLoop, trainLoop, netLoop
end
