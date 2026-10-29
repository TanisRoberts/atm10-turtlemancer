-- smelter_home.lua  --  smelter: screens: home (furnace tiles, rules, queue) and the factories pages
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local FLAME_CH, FLAME_FG, FX, K, at, cfg = S.FLAME_CH, S.FLAME_FG, S.FX, S.K, S.at, S.cfg
local fmtNum, go, header, hit, inputTotal, lr = S.fmtNum, S.go, S.header, S.hit, S.inputTotal, S.lr
local outCount, pad, pretty, saveCfg, say, shortName = S.outCount, S.pad, S.pretty, S.saveCfg, S.say, S.shortName
local smallButton, smeltQueue, spiOf, storageFresh, tierOf, wrap = S.smallButton, S.smeltQueue, S.spiOf, S.storageFresh, S.tierOf, S.wrap

---------------------------------------------------------------------------
-- Home: the furnace array as tiles (fastest first), the trainer, rules and the queue
---------------------------------------------------------------------------
local function itemShort(name)
  local s = pretty(name):gsub("^raw ", "")
  if s == "cobblestone" then return "cobble" end
  return (s:gsub("^cobbled ", "cob "))
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
    local sel = S.ui.sel == i
    local bg = sel and K.grey or K.black
    local fs = FX.facs[i] or {}
    local right = fs.energy and ("%d%% power"):format(math.floor(fs.energy * 100 + 0.5)) or ""
    lr(2, y, w - 2, FX.factoryName(i) .. ": " .. FX.factoryLine(i), right, FX.facColour(i), K.lightGrey, bg)
    lr(2, y + 1, w - 2, "  " .. shortName(f.machine), fs.procs and (fs.procs .. " processes") or nil, K.lightGrey, K.grey, bg)
    lr(2, y + 2, w - 2, ("  feed %s -> out %s"):format(shortName(f.feed), shortName(f.out)), nil, K.grey, K.grey, bg)
    hit(1, y, w, y + 2, function() S.ui.sel = (S.ui.sel == i) and nil or i; S.ui.confirm = nil end)
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
  if S.cmdLine then return end
  local x = 2
  x = smallButton(x, h, "+ Add", K.lime, function() go("fadd", { step = "machine", pickM = nil, pickF = nil }) end)
  if S.ui.sel and cfg.factories[S.ui.sel] then
    if S.ui.confirm == "remove" then
      x = smallButton(x, h, "Sure? Remove F" .. S.ui.sel, K.red, function()
        FX.removeFactory(S.ui.sel)
        say("Factory removed. Storage stops treating its barrels specially in a few seconds.", K.orange)
        S.ui.sel, S.ui.confirm = nil, nil
      end, K.white)
    else
      x = smallButton(x, h, "Remove F" .. S.ui.sel, K.grey, function() S.ui.confirm = "remove" end, K.white)
    end
  end
  smallButton(w - 7, h, "Back", K.grey, function() go("home") end, K.white)
end

function FX.drawFactoryAdd(w, h)
  local step = S.ui.step or "machine"
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
  if S.ui.pickM then chosen[S.ui.pickM] = true end
  if S.ui.pickF then chosen[S.ui.pickF] = true end
  local list = step == "machine" and FX.machineCandidates() or FX.barrelCandidates(chosen)
  local top, bottom = 4, h - 2
  local done = {}
  if S.ui.pickM then done[#done + 1] = "factory " .. shortName(S.ui.pickM) end
  if S.ui.pickF then done[#done + 1] = "feed " .. shortName(S.ui.pickF) end
  if #done > 0 then at(2, h - 1, pad(table.concat(done, ", "), w - 2), K.grey) end
  local per = bottom - top
  local pages = math.max(1, math.ceil(#list / per))
  S.ui.scroll = math.max(1, math.min(S.ui.scroll, pages))
  local y = top
  for k = 1, per do
    local name = list[(S.ui.scroll - 1) * per + k]
    if not name then break end
    lr(2, y, w - 2, name, nil, K.white)
    hit(1, y, w, y, function()
      if step == "machine" then S.ui.pickM, S.ui.step, S.ui.scroll = name, "feed", 1
      elseif step == "feed" then S.ui.pickF, S.ui.step, S.ui.scroll = name, "out", 1
      else
        local i = FX.addFactory(S.ui.pickM, S.ui.pickF, name)
        say(("%s added: feed %s -> out %s"):format(FX.factoryName(i), shortName(S.ui.pickF), shortName(name)), K.lime)
        go("factories", { sel = i })
      end
    end)
    y = y + 1
  end
  if #list == 0 then
    at(2, y, step == "machine" and "No factory on my cable: put a wired modem on it, right-click it." or "No barrels left on my cable.", K.orange)
  end
  at(1, h, (" "):rep(w))
  if S.cmdLine then return end
  local x = 2
  if pages > 1 then
    x = smallButton(x, h, "<", S.ui.scroll > 1 and K.cyan or K.grey, function() S.ui.scroll = math.max(1, S.ui.scroll - 1) end)
    at(x, h, ("%d/%d"):format(S.ui.scroll, pages), K.lightGrey); x = x + #("%d/%d"):format(S.ui.scroll, pages) + 1
    x = smallButton(x, h, ">", S.ui.scroll < pages and K.cyan or K.grey, function() S.ui.scroll = math.min(pages, S.ui.scroll + 1) end)
  end
  smallButton(w - 9, h, "Cancel", K.grey, function() go("factories") end, K.white)
end

local function drawTile(fz, idx, x, y, w, th)
  local s = S.fstate[fz]
  local t = tierOf(fz)
  local active = s and s.inp
  local spi, measured = spiOf(fz)
  -- Line 1: the tier band (+ a flame flickering on the end while it cooks)
  local label = t[2]
  if #label > w - 2 then label = t[6] end
  if #label > w - 2 then label = label:sub(1, w - 2) end
  if th == 1 then
    -- One line: colour chip, item, count
    local k = math.floor(S.frame / 2) % 4 + 1                 -- one beat for every tile (2 a second)
    at(x, y, active and FLAME_CH[k] or " ", active and FLAME_FG[k] or t[5], t[4])
    local txt = active and (itemShort(s.inp.name)) or "idle"
    local cnt = active and tostring(s.inp.count) or ""
    at(x + 1, y, pad(" " .. txt, w - 1 - #cnt), active and K.white or K.grey)
    if #cnt > 0 then at(x + w - #cnt, y, cnt, K.lightGrey) end
  else
    at(x, y, pad(" " .. label, w), t[5], t[4])
    if active then
      local k = math.floor(S.frame / 2) % 4 + 1
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
  elseif not S.trainSeen then line, col = "can't see it!", K.orange
  else
    local stt = S.train.state
    if stt == "starting" or stt == "fuelling" or stt == "cooking" then
      local dots = ("..."):sub(1, S.frame % 4)
      line, col = "learning " .. itemShort(S.train.input) .. dots, K.yellow
    elseif stt == "learned" and os.clock() - (S.train.endedAt or 0) < 60 then
      line, col = "learned " .. itemShort(S.train.out), K.lime
    elseif S.trainSlots.inp then
      line, col = ("%d %s: tap TRAIN"):format(S.trainSlots.inp.count, itemShort(S.trainSlots.inp.name)), (S.frame % 4 < 2) and K.yellow or K.white
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
  if #S.smeltRules == 0 then
    at(x, y, pad("none yet", w), K.grey); y = y + 1
  end
  for i, rule in ipairs(S.smeltRules) do
    if y > maxY then break end
    if y == maxY and i < #S.smeltRules then
      at(x, y, pad(("+%d more: Recipes"):format(#S.smeltRules - i + 1), w), K.grey)
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
  else right = ("%d furnace%s  %d cooking"):format(#S.array, #S.array == 1 and "" or "s", S.activeCount) end
  header(w, "SMELTER", right, (cfg.paused or not storageFresh()) and K.orange or K.lightGrey)

  local side = w >= 44
  local rw = side and math.max(18, math.min(22, math.floor(w * 0.32))) or 0
  local gw = side and (w - rw - 3) or (w - 2)
  local top, bottom = 3, h - 2
  local gh = bottom - top + 1

  -- The array
  if #S.array == 0 then
    local lines = { "No furnaces on my cable.", "Put furnaces (any Iron Furnaces tier) on the",
                    "storage cable with a wired modem each." }
    for i, l in ipairs(lines) do if top + i <= bottom then at(2, top + i, pad(l, gw), i == 1 and K.white or K.lightGrey) end end
  else
    local th, cols, tw, rows, step = gridLayout(#S.array, gw, gh)
    local per = cols * rows
    local pages = math.max(1, math.ceil(#S.array / per))
    S.ui.scroll = math.max(1, math.min(S.ui.scroll, pages))
    S.ui.pages = pages
    for i = 1, per do
      local idx = (S.ui.scroll - 1) * per + i
      local fz = S.array[idx]
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
  if S.cmdLine then return end
  local x = 2
  local trainCol = (cfg.trainer and S.trainSlots.inp and S.train.state == "idle") and ((S.frame % 4 < 2) and K.yellow or K.lime) or K.lime
  x = smallButton(x, fy, "TRAIN", trainCol, function() go("train") end)
  x = smallButton(x, fy, "Recipes", K.cyan, function() go("recipes") end)
  x = smallButton(x, fy, cfg.paused and "Run" or "Pause", cfg.paused and K.lime or K.orange, function()
    cfg.paused = not cfg.paused; saveCfg()
    say(cfg.paused and "Paused: nothing new goes in (finished items still come out)." or "Smelting again.", cfg.paused and K.orange or K.lime)
  end)
  x = smallButton(x, fy, "Factories", K.lightBlue, function() go("factories") end)
  local pages = S.ui.pages or 1
  if pages > 1 then
    local label = ("%d/%d"):format(S.ui.scroll, pages)
    local px = w - #label - 9
    if px > x then
      smallButton(px, fy, "<", S.ui.scroll > 1 and K.cyan or K.grey, function() S.ui.scroll = math.max(1, S.ui.scroll - 1) end)
      at(px + 4, fy, label, K.lightGrey)
      smallButton(w - 3, fy, ">", S.ui.scroll < pages and K.cyan or K.grey, function() S.ui.scroll = math.min(pages, S.ui.scroll + 1) end)
    end
  end
end

S.drawHome, S.itemShort = drawHome, itemShort
end
