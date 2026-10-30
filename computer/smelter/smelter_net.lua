-- smelter_net.lua  --  smelter: status for chat and the mainframe, terminal commands, and the background loops
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local BASE, FX, K, TICK, cfg, findFurnaces = S.BASE, S.FX, S.K, S.TICK, S.cfg, S.findFurnaces
local inbox, inputTotal, loadSmeltRules, outCount, pickStep = S.inbox, S.inputTotal, S.loadSmeltRules, S.outCount, S.pickStep
local pretty, queueSmelt, recipeFor, redraw, saveCfg, say = S.pretty, S.queueSmelt, S.recipeFor, S.redraw, S.saveCfg, S.say
local shortName, smeltPass, smeltQueue, sortedKeys, trainLine, trainStep = S.shortName, S.smeltPass, S.smeltQueue, S.sortedKeys, S.trainLine, S.trainStep

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
-- Typed commands (on the computer's own screen, with or without the slash; /help lists them), shared/slash.lua
---------------------------------------------------------------------------
local slash = require("slash")
local cmds = slash.new()
local function T() return S.termView() end                   -- the typed commands act on the computer's own screen
local function page(name, extra) return function() S.go(T(), name, extra); return true end end

cmds:add({ name = "smelt", args = "<item> <n>", min = 2, max = 2, help = "queue a one-off job",
  run = function(a)
    local n, why = a:int(2)
    if not n then return false, why end
    return true, ("Queued %d %s."):format(n, queueSmelt(a.words[1]:lower(), n))
  end })
cmds:add({ name = "train", help = "open the training page", max = 0, run = page("train") })
cmds:add({ name = "trainer", help = "pick the training furnace", max = 0, run = page("pick") })
cmds:add({ name = "pick", help = "same as /trainer", max = 0, run = page("pick") })
cmds:add({ name = "recipes", help = "everything it knows", max = 0, run = page("recipes") })
cmds:add({ name = "rule", args = "<item>", min = 1, max = 1, help = "open one recipe's rule",
  run = function(a) S.go(T(), "rule", { key = recipeFor(a.words[1]:lower()) }); return true end })
cmds:add({ name = "factories", help = "the factories page", max = 0, run = page("factories") })
cmds:add({ name = "home", help = "back to the furnaces", max = 0, run = page("home") })
cmds:add({ name = "pause", help = "stop sending new work in", max = 0,
  run = function() cfg.paused = true; saveCfg(); return true, "Paused.", "warn" end })
for _, n in ipairs({ "run", "resume", "go" }) do
  cmds:add({ name = n, help = "smelt again", max = 0,
    run = function() cfg.paused = false; saveCfg(); return true, "Smelting again." end })
end
cmds:add({ name = "reload", help = "read smelt.txt again", max = 0,
  run = function() loadSmeltRules(); return true, ("Loaded %d rule(s) from smelt.txt."):format(#S.smeltRules) end })
cmds:add({ name = "status", help = "what it is doing, in one line", max = 0,
  run = function() return true, table.concat(smeltStatus(), " | "), "plain" end })

cmds:add({ name = "factory", args = "add <machine> <feed> <out> | remove <n>", min = 1, max = 4, help = "set up or remove a factory",
  run = function(a)
    if a:is(1, "add") then
      local m, fd, o = a.words[2], a.words[3], a.words[4]
      if not (m and fd and o) then return false end
      local pm, pf, po = FX.findPeripheral(m), FX.findPeripheral(fd), FX.findPeripheral(o)
      if not pm or not FX.factoryLike(pm) then return false, "No factory called " .. m .. " on my cable." end
      if not pf or not peripheral.hasType(pf, "inventory") then return false, "No barrel called " .. fd .. " on my cable." end
      if not po or not peripheral.hasType(po, "inventory") or po == pf then return false, "No (other) barrel called " .. o .. " on my cable." end
      if FX.usedByFactory(pm) or FX.usedByFactory(pf) or FX.usedByFactory(po) then return false, "One of those is already in a factory setup." end
      local i = FX.addFactory(pm, pf, po)
      S.go(T(), "factories", { fac = i })
      return true, ("%s added: feed %s -> out %s"):format(FX.factoryName(i), shortName(pf), shortName(po))
    elseif a:is(1, "remove") and a.n == 2 then
      local i, why = a:int(2)
      if not i then return false, why end
      if not cfg.factories[i] then return false, "No factory " .. i .. "." end
      FX.removeFactory(i)
      return true, "Factory " .. i .. " removed.", "warn"
    end
    return false
  end })

cmds:add({ name = "probe", args = "[item] [factory] | stop", max = 2, help = "log what a factory does, one item at a time",
  run = function(a)
    if a:is(1, "stop") then
      local i = FX.probeActive()
      FX.probeReq = nil
      if i then FX.probeEnd(i, FX.facs[i].trial, { kind = "stopped" }) end
      return true, "Probe stopped.", "warn"
    end
    local item, which
    for _, w in ipairs(a.words) do
      w = w:lower()
      if w:match("^%d+$") then which = tonumber(w)
      else item = w:find(":") and w or ("minecraft:" .. w:gsub("^minecraft:", "")) end
    end
    return true, FX.probeStart(item, which), "plain"
  end })

cmds:add({ name = "enrich", args = "add <item> | forget <ore> | remove <item>", min = 2, max = 2, help = "pick what the factories try",
  run = function(a)
    local word = a.words[2]:lower()
    if a:is(1, "forget") then
      local gone = 0
      for _, ore in ipairs(FX.direct.match(word, sortedKeys(cfg.enrich))) do
        FX.enrichForget(ore); gone = gone + 1
      end
      if gone > 0 then return true, "Forgot what the factories learned about " .. word .. ": it gets tried again." end
      return true, "Nothing learned about " .. word .. ".", "warn"
    elseif a:is(1, "remove") then
      local found = FX.direct.match(word, cfg.enrichExtra)
      if #found == 0 then return true, "No '" .. word .. "' was added by hand.", "warn" end
      if #found > 1 then return false, "Which one? " .. table.concat(found, ", ") end
      FX.enrichRemove(found[1])
      return true, pretty(found[1]) .. " is off the factory list."
    elseif a:is(1, "add") then
      local names = {}
      for name in pairs(S.byName) do names[#names + 1] = name end
      for _, name in ipairs(cfg.enrichExtra) do names[#names + 1] = name end
      table.sort(names)
      local found = FX.direct.match(word, names)
      if #found == 0 and word:find(":", 1, true) then found = { word } end
      if #found == 0 then return false, "No '" .. word .. "' in storage. Use the full id (mod:item) if there is none yet." end
      if #found > 1 then
        local short = {}
        for i = 1, math.min(#found, 4) do short[i] = shortName(found[i]) end
        return false, "Which one? " .. table.concat(short, ", ")
      end
      if FX.enrichAdd(found[1]) then return true, pretty(found[1]) .. " will be tried in a factory." end
      return true, pretty(found[1]) .. " is on the list already.", "plain"
    end
    return false
  end })

cmds:add({ name = "monitors", help = "pick the smelter monitor again (reboots)", max = 0,
  run = function() S.repickMonitor(); return true end })

S.cmds = cmds

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
      if S.monView() and S.states.monitor.page == "home" then S.go(S.monView(), "train") end
      redraw()
    elseif not S.trainSlots.inp then S.train.seen = nil end
    if S.picking then
      local found = pickStep()
      if found == "timeout" then say("Nothing was dropped in. Try again, or tap it in the list.", K.orange)
      elseif found then
        cfg.trainer = found; saveCfg(); findFurnaces()
        S.train = { state = "idle", seen = true }
        say(shortName(found) .. " is the trainer now. Tap TRAIN to learn what you dropped in.", K.lime)
        for _, v in ipairs(S.views) do if S.stateFor(v).page == "pick" then S.go(v, "train") end end
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

S.workLoop, S.trainLoop, S.netLoop = workLoop, trainLoop, netLoop
end
