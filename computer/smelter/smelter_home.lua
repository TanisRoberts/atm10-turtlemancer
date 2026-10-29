-- smelter_home.lua  --  smelter: the home page: the furnace array as tiles (fastest first) and, beside them, the
-- trainer, factories, rules and one-off jobs. Built from the UI kit. Calm: only the smelting glyph on a cooking
-- tile moves (ui.beat 2). Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local FX, cfg, ui = S.FX, S.cfg, S.FX.kit
local fmtNum, go, inputTotal, outCount, pretty = S.fmtNum, S.go, S.inputTotal, S.outCount, S.pretty
local saveCfg, say, shortName, smeltQueue, spiOf = S.saveCfg, S.say, S.shortName, S.smeltQueue, S.spiOf
local storageFresh, tierOf, beat = S.storageFresh, S.tierOf, S.beat
local fit = ui.text.fit

local function itemShort(name)
  local s = pretty(name):gsub("^raw ", "")
  if s == "cobblestone" then return "cobble" end
  return (s:gsub("^cobbled ", "cob "))
end

function FX.facTone(i)
  local fs = FX.facs[i]
  if not fs then return "dim" end
  if fs.trial then return "gold" end
  if fs.why then return fs.why:find("missing", 1, true) and "bad" or "warn" end
  return "good"
end

---------------------------------------------------------------------------
-- The furnace tile: tier band on top (the smelting glyph on its end while it cooks), the item, how many are left
-- and the finished ones waiting (+N). The kit has no furnace tile of its own; this one is built from its drawing calls.
---------------------------------------------------------------------------
local function drawTile(v, fz, idx, x, y, w, th)
  local s = S.fstate[fz]
  local t = tierOf(fz)
  local active = s and s.inp
  local spi, measured = spiOf(fz)
  if th == 1 then
    v:put(x, y, " ", "fg", t[4])
    if active then v:glyph(x, y, "smelting", { bg = t[4] }) end
    local cnt = active and tostring(s.inp.count) or ""
    v:put(x + 2, y, fit(active and itemShort(s.inp.name) or "idle", w - 3 - #cnt), active and "fg" or "dim", "bg")
    if #cnt > 0 then v:put(x + w - #cnt, y, cnt, "dim", "bg") end
  else
    local label = t[2]
    if #label > w - 2 then label = t[6] end
    v:fill(x, y, w, t[4])
    v:put(x + 1, y, fit(label, w - 2), t[5], t[4])
    if active then v:glyph(x + w - 1, y, "smelting", { bg = t[4] }) end
    v:put(x + 1, y + 1, fit(active and itemShort(s.inp.name) or (s and "idle" or "can't see it"), w - 1), active and "fg" or "dim", "bg")
    if th >= 3 then
      v:put(x + 1, y + 2, active and ("x" .. s.inp.count) or "--", "dim", "bg")
      if s and s.out then
        local o = "+" .. s.out.count
        v:put(x + w - #o, y + 2, o, "good", "bg")
      elseif not active then
        local sp = ("%.1fs"):format(spi)
        if #sp + 4 <= w then v:put(x + w - #sp, y + 2, sp, measured and "dim" or "bar", "bg") end
      end
    end
  end
  v:_box({ x, y, x + w - 1, y + th - 1 }, nil, { id = "furnace:" .. idx, fn = function()
    local sp, m = spiOf(fz)
    local what = (s and s.inp) and (s.inp.count .. " " .. pretty(s.inp.name)) or "empty"
    ui.say(("%s: %s. %.2fs per item (%s)"):format(shortName(fz), what, sp, m and "measured" or "tier"))
  end })
end

-- Fit the array into the box: 3-line tiles (a blank row between rows if there's room), then 2, then 1-line rows.
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
  return 1, cols, tw, math.max(1, gh), 1
end

---------------------------------------------------------------------------
-- The right column: a card is a section label and its lines, and the whole card opens its page
---------------------------------------------------------------------------
local function trainerCard(v, x, y, w)
  y = v:section(x, y, w, "TRAINER")
  local line, tone = "", "dim"
  if not cfg.trainer then line = "not set: tap TRAIN"
  elseif not S.trainSeen then line, tone = "can't see it!", "warn"
  else
    local stt = S.train.state
    if stt == "starting" or stt == "fuelling" or stt == "cooking" then
      line, tone = "learning " .. itemShort(S.train.input) .. ("..."):sub(1, ui.anim == "full" and beat(v, 4) % 4 or 3), "gold"
    elseif stt == "learned" and os.clock() - (S.train.endedAt or 0) < 60 then
      line, tone = "learned " .. itemShort(S.train.out), "good"
    elseif S.trainSlots.inp then
      line = ("%d %s: tap TRAIN"):format(S.trainSlots.inp.count, itemShort(S.trainSlots.inp.name))
      tone = (ui.anim ~= "full" or beat(v, 4) % 4 < 2) and "gold" or "fg"
    else line = "ready" end
  end
  v:put(x, y, fit(line, w), tone, "bg")
  v:_box({ x, y - 1, x + w - 1, y }, nil, { id = "card:trainer", fn = function() go(v, "train") end })
  return y + 2
end

local function factoryCard(v, x, y, w, maxY)
  y = v:section(x, y, w, "FACTORIES")
  local open = function() go(v, "factories") end
  if #cfg.factories == 0 then
    v:put(x, y, fit("none: tap to add", w), "bar", "bg")
    v:_box({ x, y - 1, x + w - 1, y }, nil, { id = "card:factories", fn = open })
    return y + 2
  end
  for i in ipairs(cfg.factories) do
    if y > maxY then break end
    v:kv(x, y, w, "F" .. i, FX.factoryLine(i), FX.facTone(i))
    v:_box({ x, y, x + w - 1, y }, nil, { id = "factory:" .. i, fn = function() go(v, "factories", { fac = i }) end })
    y = y + 1
  end
  return y + 1
end

local function ruleTag(rule)
  if rule.all then
    local n = inputTotal(rule.r)
    return n > 0 and ("all, " .. fmtNum(n) .. " in") or "all", n > 0 and "warn" or "good"
  end
  local have, want = outCount(rule.r), rule.stacks * 64
  return ("%s/%s"):format(fmtNum(have), fmtNum(want)), have >= want and "good" or "warn"
end

local function rulesCard(v, x, y, w, maxY)
  y = v:section(x, y, w, "RULES")
  if #S.smeltRules == 0 then v:put(x, y, fit("none yet", w), "bar", "bg"); y = y + 1 end
  for i, rule in ipairs(S.smeltRules) do
    if y > maxY then break end
    if y == maxY and i < #S.smeltRules then
      v:put(x, y, fit(("+%d more: Recipes"):format(#S.smeltRules - i + 1), w), "bar", "bg")
      v:_box({ x, y, x + w - 1, y }, nil, { id = "rules:more", fn = function() go(v, "recipes") end })
      return y + 1
    end
    local tag, tone = ruleTag(rule)
    v:kv(x, y, w, (rule.name:gsub("_", " ")), tag, tone)
    v:_box({ x, y, x + w - 1, y }, nil, { id = "rule:" .. rule.name, fn = function() go(v, "rule", { key = rule.name }) end })
    y = y + 1
  end
  return y
end

local function queueCard(v, x, y, w, maxY)
  local any = false
  for _, j in ipairs(smeltQueue) do if j.left > 0 then any = true end end
  if not any or y + 1 > maxY then return y end
  y = v:section(x, y + 1, w, "ONE-OFF JOBS")
  for _, j in ipairs(smeltQueue) do
    if y > maxY then break end
    if j.left > 0 then v:kv(x, y, w, (j.name:gsub("_", " ")), fmtNum(j.left) .. " left", "gold"); y = y + 1 end
  end
  return y
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function drawHome(v, st)
  local W = v.W
  local fresh = storageFresh()
  local state, tone = "ok", nil
  if cfg.paused then state, tone = "paused", "warn" elseif not fresh then state = "error" end
  v:header("SMELTER", { state = state, color = tone,
    right = ("%d furnace%s  %d cooking"):format(#S.array, #S.array == 1 and "" or "s", S.activeCount) })
  local pcount = st.pages or 1
  local plan = S.plan(v, {
    { label = "TRAIN", short = "Train", id = "train", style = (cfg.trainer and S.trainSlots.inp and S.train.state == "idle") and "primary" or "idle",
      fn = function() go(v, "train") end },
    { label = "Recipes", short = "Rec", id = "recipes", fn = function() go(v, "recipes") end },
    { label = cfg.paused and "Run" or "Pause", id = "pause", style = cfg.paused and "primary" or "idle", fn = function()
        cfg.paused = not cfg.paused; saveCfg()
        say(cfg.paused and "Paused: nothing new goes in (finished items still come out)." or "Smelting again.", cfg.paused and S.K.orange or S.K.lime)
      end },
    { label = "Factories", short = "Fact", id = "factories", fn = function() go(v, "factories") end },
  }, { pager = pcount > 1 })
  local top, bottom = 3, plan.bottom
  if not fresh then v:alert(2, 3, W - 2, "Storage not heard: nothing new goes in.", "bad"); top = 4 end

  local side = W >= 44
  local rw = side and math.max(20, math.min(24, math.floor(W * 0.4))) or 0
  local dx = W - rw - 1                                    -- the divider column
  local gw = side and (dx - 3) or (W - 2)
  local gh = bottom - top + 1

  if #S.array == 0 then
    v:put(2, top + 1, fit("No furnaces on my cable.", gw), "fg", "bg")
    v:put(2, top + 2, fit("Put furnaces (any Iron Furnaces tier) on the", gw), "dim", "bg")
    v:put(2, top + 3, fit("storage cable with a wired modem each.", gw), "dim", "bg")
    v.pages = 1
  else
    local th, cols, tw, rows, step = gridLayout(#S.array, gw, gh)
    local per = cols * rows
    v.pages = math.max(1, math.ceil(#S.array / per))
    v.page = math.max(1, math.min(v.page, v.pages))
    for i = 1, per do
      local idx = (v.page - 1) * per + i
      local fz = S.array[idx]
      if not fz then break end
      local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
      drawTile(v, fz, idx, 2 + c * (tw + 1), top + r * step, tw, th)
    end
  end
  st.pages = v.pages

  if side then
    for yy = top, bottom do v:put(dx, yy, v.colour and "\149" or "|", "bar", "bg") end
    local x, w = dx + 2, W - dx - 2
    local y = trainerCard(v, x, top, w)
    y = factoryCard(v, x, y, w, math.min(bottom - 3, y + 3))
    local queueRows = 0
    for _, j in ipairs(smeltQueue) do if j.left > 0 then queueRows = queueRows + 1 end end
    y = rulesCard(v, x, y, w, bottom - (queueRows > 0 and math.min(queueRows + 2, 5) or 0))
    queueCard(v, x, y, w, bottom)
  end
  v:footer({})
  plan.draw()
end

S.pages.home = drawHome
S.itemShort = itemShort
end
