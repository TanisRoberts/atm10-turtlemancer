-- smelter_trainui.lua  --  smelter: the training page (a furnace that comes alive) and the pick-the-trainer page.
-- Built from the UI kit. One thing happens at a time here, so the flames, smoke, sparkles and arrows may move, on
-- ui.beat(4) and only with ANIM=full. Part of computer/smelter/smelter.lua; the shared state S is passed in.

return function(S)
local FIND_TIME, FX, K, TRAIN_TIMEOUT, allFurnaces = S.FIND_TIME, S.FX, S.K, S.TRAIN_TIMEOUT, S.allFurnaces
local cfg, findFurnaces, go, itemShort, pretty = S.cfg, S.findFurnaces, S.go, S.itemShort, S.pretty
local saveCfg, say, setRule, shortName, startTraining, tierOf = S.saveCfg, S.say, S.setRule, S.shortName, S.startTraining, S.tierOf
local beat, text, wrap = S.beat, S.text, S.wrap
local ui = FX.kit
local fit = ui.text.fit

-- A cheap repeatable "random" number for the flames and sparkles
local function nz(a, b, c) return (a * 73 + b * 151 + (c or 0) * 37 + a * b * 7) % 97 end

---------------------------------------------------------------------------
-- The scene: stone furnace with a dark mouth, fire inside when lit, smoke above it
---------------------------------------------------------------------------
local FLAME = { "bad", "warn", "gold" }
local function drawFurnace(v, x, y, fw, fh, heat, b)
  local mh = math.max(2, math.floor(fh / 3))
  local my = fh - 1 - mh                                  -- first mouth row (one row of stone under it)
  for r = 0, fh - 1 do
    local cells = {}
    for c = 0, fw - 1 do
      local ch, fg, bg = " ", "fg", "dim"
      if r == 0 or r == fh - 1 or c == 0 or c == fw - 1 or nz(r, c) % 6 == 0 then bg = "bar" end
      if r == 1 and c >= math.floor(fw / 2) - 2 and c <= math.floor(fw / 2) + 1 then bg = "bg" end     -- the top slot
      if r >= my and r < my + mh and c >= 2 and c <= fw - 3 then
        bg = "bg"
        if heat > 0 then
          local depth = my + mh - 1 - r                   -- 0 = bottom row of the mouth
          local hgt = (nz(c, b) % (mh + 1)) * heat
          if depth < hgt then
            bg = FLAME[depth == 0 and 3 or ((nz(c, r, b) % 2 == 0) and 2 or 1)]
            if nz(r, c, b) % 3 == 0 then ch, fg = "\30", "gold" end
          elseif depth == 0 then bg = "bad" end
        end
      end
      cells[#cells + 1] = { ch, fg, bg }
    end
    v:cells(x, y + r, cells)
  end
  if heat > 0 and b > 0 then                              -- smoke rising off the top while it burns
    for k = 0, 2 do
      local life = (b + k * 3) % 6
      local sy = y - 1 - math.floor(life / 2)
      local sx = x + math.floor(fw / 2) - 1 + (nz(k, math.floor((b + k * 3) / 6)) % 3) - 1 + ((life >= 4) and 1 or 0)
      if sy >= 3 then v:put(sx, sy, life < 2 and "o" or (life < 4 and "." or "'"), life < 3 and "dim" or "bar", "bg") end
    end
  end
end

-- A card: coloured title, the lines centred, grey rails
local function card(v, x, y, w, h, title, titleBg, lines)
  v:put(x, y, (" "):rep(math.floor((w - #title) / 2)) .. title .. (" "):rep(math.ceil((w - #title) / 2)), "bg", titleBg)
  for r = 1, h - 1 do
    local l = lines[r]
    local str, tone = "", "dim"
    if type(l) == "table" then str, tone = l[1], l[2] elseif l then str = l end
    str = fit(str, w - 2)
    v:put(x, y + r, " ", "fg", "bar")
    v:put(x + 1, y + r, (" "):rep(math.floor((w - 2 - #str) / 2)) .. str .. (" "):rep(math.ceil((w - 2 - #str) / 2)), tone, "bg")
    v:put(x + w - 1, y + r, " ", "fg", "bar")
  end
  v:put(x, y + h, (" "):rep(w), "fg", "bar")
end
local function itemLines(name, count, w)
  local out = {}
  for _, l in ipairs(wrap(pretty(name), w - 2)) do out[#out + 1] = { l, "fg" } end
  while #out > 3 do table.remove(out) end
  if count then out[#out + 1] = { "x" .. count, "dim" } end
  return out
end
local function arrow(v, x, y, aw, moving, b)
  for i = 0, aw - 1 do
    local lit = moving and b > 0 and ((b - i) % aw == 0)
    v:put(x + i, y, (i == aw - 1) and ">" or "-", lit and "gold" or "bar", "bg")
  end
end

local STATE = { idle = "idle", starting = "working", fuelling = "working", cooking = "working", learned = "done", failed = "error" }

---------------------------------------------------------------------------
-- Training
---------------------------------------------------------------------------
local function drawTrain(v, st)
  local W, H = v.W, v.H
  local stt = S.train.state
  local cooking = stt == "starting" or stt == "fuelling" or stt == "cooking"
  v:header("TRAINING", { state = cfg.trainer and STATE[stt] or nil, right = cfg.trainer and shortName(cfg.trainer) or nil })
  local back = function() go(v, "home") end
  local plan = S.plan(v, {
    { label = "Change trainer", short = "Change", id = "change", fn = function() go(v, "pick") end },
    { label = "Recipes", short = "Rec", id = "recipes", fn = function() go(v, "recipes") end },
  }, { back = true })
  local last, w = plan.bottom, W - 2

  if not cfg.trainer then
    local y = text(v, 2, 4, w, last, "No training furnace yet.", "fg")
    y = text(v, 2, y + 1, w, last, "Put a furnace (any kind) somewhere out of the way, on the storage cable with a wired modem. It's only ever used for training, never for the smelting array.", "dim")
    v:buttons(2, math.min(y + 1, last), { { label = "PICK THE TRAINER", short = "PICK", style = "primary", id = "pick", fn = function() go(v, "pick") end } })
    v:footer({ back = back }); plan.draw()
    return
  end

  local b = beat(v, 4)
  local doneAgo = S.train.endedAt and (os.clock() - S.train.endedAt) or 999
  local heat = cooking and 1 or ((stt == "learned" and doneAgo < 3) and 0.5 or 0)

  -- What goes at the bottom: the controls, and under the scene the words
  local lines = {}                                        -- { text, tone }
  local function say2(t, tone) lines[#lines + 1] = { t, tone } end
  if not S.trainSeen then
    say2("I can't see the training furnace (" .. cfg.trainer .. "). Is its modem on (red ring)?", "warn")
  elseif cooking then
    say2(stt == "cooking" and ("Cooking one %s... (I give up after %ds)"):format(pretty(S.train.input), TRAIN_TIMEOUT)
      or (S.train.note or "Getting it ready..."), "dim")
  elseif stt == "learned" then
    local how = S.train.per > 1 and (" (" .. S.train.per .. " each)") or ""
    say2((S.train.known and "Already knew this one: " or "Learned: ") .. pretty(S.train.input) .. " -> " .. pretty(S.train.out) .. how, "good")
    say2(("What should I do with %s?"):format(pretty(S.train.out)), "fg")
  elseif stt == "failed" then
    say2(S.train.reason or "That didn't work.", "warn"); say2("It goes back into storage.", "dim")
  elseif S.trainSlots.inp then
    say2(("Ready: %d %s in the top slot."):format(S.trainSlots.inp.count, pretty(S.trainSlots.inp.name)), "fg")
    say2("Tap TRAIN and I'll fuel it and watch what comes out.", "dim")
  else
    say2("Put the raw item in the trainer's TOP slot, then tap TRAIN.", "fg")
    say2("One is enough. Leftovers go back into storage.", "dim")
  end
  local nText = 0
  for _, l in ipairs(lines) do nText = nText + #wrap(l[1], w) end
  local ctrl = cooking and 4 or (stt == "learned" and 4 or 1)         -- rows of bars / switch / buttons under the words
  if stt == "learned" and v.wc == "narrow" then ctrl = 6 end

  -- The scene, if there is room: IN card, furnace, OUT card. Narrow screens get the two items as lines instead.
  local avail = last - 3 + 1 - nText - ctrl - 1
  local cards = W >= 50
  local fh = avail >= 12 and 9 or 7
  local smoke = fh == 9 and 3 or 2
  local y = 3
  local inName = (cooking or stt == "learned" or stt == "failed") and S.train.input or (S.trainSlots.inp and S.trainSlots.inp.name)
  if avail >= smoke + fh + (cards and 0 or 2) then
    local fw = (fh == 9) and 16 or 14
    if cards then
      local cw = math.max(10, math.min(15, math.floor((W - fw - 10) / 2)))
      local aw = math.max(3, math.floor((W - fw - 2 * cw - 4) / 2))
      local total = cw * 2 + aw * 2 + fw + 2
      local sx = math.max(2, math.floor((W - total) / 2) + 1)
      local fx, cardY = sx + cw + aw + 1, y + smoke + math.floor((fh - 5) / 2)
      local inLines
      if inName then
        inLines = itemLines(inName, (S.trainSlots.inp and S.trainSlots.inp.name == inName) and S.trainSlots.inp.count or nil, cw)
      else inLines = { { "empty", "bar" }, { "drop it in", "bar" }, { "the top", "bar" } } end
      local inReady = stt == "idle" and S.trainSlots.inp
      card(v, sx, cardY, cw, 5, "PUT IN", inReady and ((b == 0 or b % 4 < 2) and "gold" or "fg") or "dim", inLines)
      arrow(v, sx + cw + 1, cardY + 2, aw - 1, cooking, b)
      drawFurnace(v, fx, y + smoke, fw, fh, heat, b)
      arrow(v, fx + fw + 1, cardY + 2, aw - 1, stt == "cooking", b)
      local ox = fx + fw + aw + 1
      if stt == "learned" then
        card(v, ox, cardY, cw, 5, "COMES OUT", "good", itemLines(S.train.out, S.train.per > 1 and (S.train.per .. " each") or "1 each", cw))
        if doneAgo < 6 and b > 0 then                      -- sparkles round the new recipe
          for k = 0, 9 do
            local px, py = ox - 1 + nz(k, b) % (cw + 2), cardY - 1 + nz(b, k) % 7
            if py >= 3 and py < last and (px < ox or px >= ox + cw or py < cardY or py > cardY + 5) then
              v:put(px, py, ({ "*", "+", "." })[nz(k, k, b) % 3 + 1], (k + b) % 2 == 0 and "gold" or "fg", "bg")
            end
          end
        end
      elseif stt == "failed" then
        card(v, ox, cardY, cw, 5, "COMES OUT", "bad", { { "nothing", "warn" }, { "X", "bad" } })
      else
        card(v, ox, cardY, cw, 5, "COMES OUT", "dim", { "", { "?", cooking and ((b % 4 < 2) and "gold" or "fg") or "bar" } })
      end
    else
      drawFurnace(v, math.max(2, math.floor((W - fw) / 2) + 1), y + smoke, fw, fh, heat, b)
    end
    y = y + smoke + fh + 1
  end
  if not cards then
    if y + 1 <= last - nText - ctrl then
      v:kv(2, y, w, "Put in", inName and pretty(inName) or "empty", inName and "fg" or "dim")
      v:kv(2, y + 1, w, "Comes out", stt == "learned" and pretty(S.train.out) or "?", stt == "learned" and "good" or "dim")
      y = y + 2
    end
  end

  -- The words
  for _, l in ipairs(lines) do y = text(v, 2, y, w, last - ctrl, l[1], l[2]) end
  y = math.max(y, last - ctrl + 1)

  -- The controls
  if cooking then
    local steps = { { "Output slot clear", stt ~= "starting" }, { "Fuel in", stt == "cooking" }, { "First one cooked", false } }
    local sx = 2
    for _, s in ipairs(steps) do
      local t = (s[2] and "\4 " or "\7 ") .. s[1]
      if sx + #t <= W then v:put(sx, y, t, s[2] and "good" or "bar", "bg") end
      sx = sx + #t + 3
    end
    y = y + 1
    if stt == "cooking" then
      local el = os.clock() - (S.train.fuelAt or os.clock())
      v:bar(2, y, w, "Cooking", math.min(1, el / TRAIN_TIMEOUT), { kind = "progress", text = ("%ds"):format(math.floor(el)) })
    end
    v:buttons(2, y + 1, { { label = "CANCEL", id = "cancel", confirm = true, fn = function()
      S.train = { state = "idle", giveBack = true, input = S.train.input, seen = true }
      say("Training cancelled: it goes back into storage.", K.orange)
    end } })
  elseif stt == "learned" then
    st.mode = st.mode or S.train.mode or "none"
    S.train.stacks = S.train.stacks or 4
    local _, ry = v:switch(2, y, {
      { id = "none", label = "No rule", short = "None" }, { id = "keep", label = "Keep N stacks", short = "Keep N" },
      { id = "all", label = "Smelt all", short = "All" } }, st.mode, function(id) st.mode = id end, { id = "rule-mode" })
    y = ry + 1
    if st.mode == "keep" then
      v:stepper(2, y, "Keep stacks", S.train.stacks, { min = 1, max = 999, on = function(n) S.train.stacks = n end })
      y = y + (v.wc == "narrow" and 2 or 1)
    end
    local function finish(mode)
      if mode then setRule(S.train.key, mode, S.train.stacks) end
      say(mode == "all" and ("Rule saved: smelt all " .. S.train.key) or mode == "keep" and
        ("Rule saved: keep %d stacks of %s"):format(S.train.stacks, S.train.key) or ("Learned " .. S.train.key .. ", no rule."), K.lime)
      S.train = { state = "idle", giveBack = S.train.giveBack, input = S.train.input, seen = true }
      go(v, "home")
    end
    v:buttons(2, math.min(y, last), {
      { label = "Save", style = "primary", id = "save-rule", fn = function() finish(st.mode ~= "none" and st.mode or nil) end },
      { label = "Just learn it", short = "Learn", id = "just-learn", fn = function() finish(nil) end } })
  else
    local ready = S.trainSlots.inp ~= nil
    v:buttons(2, math.min(y, last), { { label = stt == "failed" and "TRY AGAIN" or "TRAIN", id = "train",
      style = ready and "primary" or "disabled", fn = function()
        local ok, why = startTraining()
        if not ok then say(why, K.orange) end
      end } })
  end
  v:footer({ back = back }); plan.draw()
end

---------------------------------------------------------------------------
-- Pick the trainer: tap a furnace, or drop one item into the top slot of the one you mean ("Find it")
---------------------------------------------------------------------------
local function drawPick(v, st)
  local W = v.W
  v:header("PICK THE TRAINER", { state = S.picking and "waiting" or nil, right = S.picking and "watching..." or nil })
  local back = function() S.picking = nil; go(v, "train") end
  local acts = {}
  if S.picking then
    acts[1] = { label = "STOP", id = "stop", fn = function() S.picking = nil end }
  else
    acts[1] = { label = "Find it", id = "find", style = "primary", fn = function() S.picking = { untilT = os.clock() + FIND_TIME, before = {} } end }
    if cfg.trainer then
      acts[2] = { label = "No trainer", short = "None", id = "none", confirm = true, fn = function()
        say(shortName(cfg.trainer) .. " is back in the smelting array.", K.orange)
        cfg.trainer = nil; saveCfg(); S.train = { state = "idle" }; go(v, "home")
      end }
    end
  end
  local plan = S.plan(v, acts, { back = true, pager = not S.picking })
  if S.picking then
    local left = math.max(0, math.ceil(S.picking.untilT - os.clock()))
    local y = 4
    v:spinner_line(2, y, "Drop any item into the TOP slot of the furnace you want."); y = y + 1
    y = text(v, 2, y, W - 2, plan.bottom, "The smelting array is paused while I watch.", "dim")
    v:bar(2, y + 1, W - 2, "Left", left / FIND_TIME, { kind = "progress", text = left .. " s" })
    v:footer({ back = back }); plan.draw()
    return
  end
  local rows = {}
  for _, fz in ipairs(allFurnaces()) do
    local t = tierOf(fz)
    local s = fz == cfg.trainer and S.trainSlots or S.fstate[fz] or {}
    local what = s.inp and (s.inp.count .. " " .. itemShort(s.inp.name)) or "empty"
    rows[#rows + 1] = { name = shortName(fz), value = fz == cfg.trainer and "TRAINER" or what, tone = fz == cfg.trainer and "good" or nil,
      state = t[4], id = fz }
  end
  v:put(2, 3, fit(W >= 56 and "Tap one to make it the trainer (it leaves the array):" or "Tap one to make it the trainer:", W - 2), "dim", "bg")
  v:list(rows, { once = true, top = 4, input = plan.input, on = function(row)
    local fz = row.id
    local was = S.fstate[fz]
    cfg.trainer = fz; saveCfg(); findFurnaces()
    S.train = { state = "idle", clear = (was and (was.inp or was.out)) and true or nil, seen = true }
    say(shortName(fz) .. " is the trainer now." .. (S.train.clear and " Emptying its old smelting first." or " It's out of the smelting array."), K.lime)
    go(v, "train")
  end })
  if #rows == 0 then v:put(2, 4, "No furnaces on my cable.", "warn", "bg") end
  v:footer({ back = back }); plan.draw()
end

S.pages.train, S.pages.pick = drawTrain, drawPick
end
