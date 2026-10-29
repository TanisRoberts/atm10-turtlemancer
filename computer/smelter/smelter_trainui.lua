-- smelter_trainui.lua  --  smelter: screens: train, find-the-trainer, recipes and rule pages
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local BLIT, FIND_TIME, FX, K, TRAIN_TIMEOUT, allFurnaces = S.BLIT, S.FIND_TIME, S.FX, S.K, S.TRAIN_TIMEOUT, S.allFurnaces
local at, bar, button, centre, cfg, findFurnaces = S.at, S.bar, S.button, S.centre, S.cfg, S.findFurnaces
local fmtNum, forget, go, header, hit, inputTotal = S.fmtNum, S.forget, S.go, S.header, S.hit, S.inputTotal
local isInputOf, itemShort, lr, nz, outCount, outMatches = S.isInputOf, S.itemShort, S.lr, S.nz, S.outCount, S.outMatches
local pad, perOf, pretty, queueSmelt, recipeFor, ruleFor = S.pad, S.perOf, S.pretty, S.queueSmelt, S.recipeFor, S.ruleFor
local saveCfg, say, setRule, shortName, smallButton, sortedKeys = S.saveCfg, S.say, S.setRule, S.shortName, S.smallButton, S.sortedKeys
local startTraining, tierOf, wrap = S.startTraining, S.tierOf, S.wrap

---------------------------------------------------------------------------
-- Training page: a furnace that comes alive
---------------------------------------------------------------------------
-- The furnace: stone body, dark mouth, fire inside when lit (dies down when done), smoke above
local function drawFurnaceArt(x, y, fw, fh, heat)
  local mh = math.max(2, math.floor(fh / 3))
  local my = fh - 1 - mh            -- first mouth row (one row of stone under it)
  for r = 0, fh - 1 do
    local txt, fg, bg = {}, {}, {}
    for c = 0, fw - 1 do
      local ch, f, b = " ", K.white, K.lightGrey
      local edge = r == 0 or r == fh - 1 or c == 0 or c == fw - 1
      if edge then b = K.grey
      elseif nz(r, c) % 6 == 0 then b = K.grey end
      if r == 1 and c >= math.floor(fw / 2) - 2 and c <= math.floor(fw / 2) + 1 then b = K.black end   -- the top slot
      if r >= my and r < my + mh and c >= 2 and c <= fw - 3 then
        b = K.black
        if heat > 0 then
          -- flames: each column flickers to its own height, hotter at the bottom
          local depth = my + mh - 1 - r               -- 0 = bottom row of the mouth
          local hgt = (nz(c, S.frame) % (mh + 1)) * heat
          if depth < hgt then
            local k = depth == 0 and 3 or ((nz(c, r, S.frame) % 2 == 0) and 2 or 1)
            b = ({ K.red, K.orange, K.yellow })[k]
            ch, f = (nz(r, c, S.frame) % 3 == 0) and "\30" or " ", K.yellow
          elseif depth == 0 then
            b = K.red
          end
        end
      end
      txt[#txt + 1], fg[#fg + 1], bg[#bg + 1] = ch, BLIT[f], BLIT[b]
    end
    S.d.setCursorPos(x, y + r)
    S.d.blit(table.concat(txt), table.concat(fg), table.concat(bg))
  end
  -- Smoke rising off the top while it burns
  if heat > 0 then
    for k = 0, 2 do
      local life = (S.frame + k * 3) % 6
      local sy = y - 1 - math.floor(life / 2)
      local sx = x + math.floor(fw / 2) - 1 + (nz(k, math.floor((S.frame + k * 3) / 6)) % 3) - 1 + ((life >= 4) and 1 or 0)
      if sy >= 3 then at(sx, sy, life < 2 and "o" or (life < 4 and "." or "'"), life < 3 and K.lightGrey or K.grey) end
    end
  end
end

local function card(x, y, w, h, title, titleBg, lines)
  at(x, y, centre(title, w), K.black, titleBg)
  for r = 1, h - 1 do
    local l = lines[r]
    local text, col = "", K.lightGrey
    if type(l) == "table" then text, col = l[1], l[2] elseif l then text = l end
    at(x + 1, y + r, centre(text, w - 2), col, K.black)
  end
  -- side rails
  for r = 1, h - 1 do
    at(x, y + r, " ", K.black, K.grey)
    at(x + w - 1, y + r, " ", K.black, K.grey)
  end
  at(x, y + h, (" "):rep(w), K.black, K.grey)
end

local function itemLines(name, count, w)
  local out = {}
  for _, l in ipairs(wrap(pretty(name), w - 2)) do out[#out + 1] = { l, K.white } end
  while #out > 3 do table.remove(out) end
  if count then out[#out + 1] = { "x" .. count, K.lightGrey } end
  return out
end

local function drawArrow(x, y, aw, moving)
  for i = 0, aw - 1 do
    local lit = moving and ((S.frame - i) % aw == 0)
    at(x + i, y, (i == aw - 1) and "\16" or "-", lit and K.yellow or (moving and K.grey or K.grey))
  end
end

local function drawRuleChoice(x, y, w, rows, key, mode, stacks, onPick)
  -- [-] [ KEEP 4 STACKS ] [+]  [ SMELT ALL ]  [ JUST LEARN ]
  local keepW = math.max(13, math.min(17, w - 36))
  local allW, noneW = 11, 12
  local gap = math.max(1, math.floor((w - (3 + 1 + keepW + 1 + 3 + allW + noneW)) / 2))
  local bx = x
  button(bx, y, 3, rows, "-", K.grey, function() S.train.stacks = math.max(1, (S.train.stacks or 4) - 1); S.ui.pickMode = "keep" end, K.white)
  bx = bx + 4
  local sel = S.ui.pickMode or mode
  button(bx, y, keepW, rows, ("KEEP %d STACK%s"):format(stacks, stacks == 1 and "" or "S"),
    sel == "keep" and K.lime or K.lightGrey, function() onPick("keep") end)
  bx = bx + keepW + 1
  button(bx, y, 3, rows, "+", K.grey, function() S.train.stacks = math.min(999, (S.train.stacks or 4) + 1); S.ui.pickMode = "keep" end, K.white)
  bx = bx + 3 + gap
  button(bx, y, allW, rows, "SMELT ALL", sel == "all" and K.lime or K.lightGrey, function() onPick("all") end)
  bx = bx + allW + gap
  button(bx, y, noneW, rows, "JUST LEARN", K.grey, function() onPick(nil) end, K.white)
end

local function drawTrain(w, h)
  header(w, "< TRAINING", cfg.trainer and shortName(cfg.trainer) or nil)
  hit(1, 1, 12, 1, function() go("home") end)
  local big = h >= 22
  local bottomRows = big and 3 or 1
  local fy = h

  if not cfg.trainer then
    local lines = {
      { "No training furnace yet.", K.white },
      { "Put a furnace (any kind) somewhere out of the way, on the storage cable with a wired modem. It's only ever used for training, never for the smelting array.", K.lightGrey },
    }
    local y = 4
    for _, l in ipairs(lines) do
      for _, t in ipairs(wrap(l[1], w - 4)) do at(3, y, t, l[2]); y = y + 1 end
      y = y + 1
    end
    button(3, y + 1, math.min(26, w - 4), bottomRows, "PICK THE TRAINER", K.lime, function() go("pick") end)
    at(1, fy, (" "):rep(w))
    smallButton(w - 7, fy, "Back", K.grey, function() go("home") end, K.white)
    return
  end

  local stt = S.train.state
  local cooking = stt == "starting" or stt == "fuelling" or stt == "cooking"
  local doneAgo = S.train.endedAt and (os.clock() - S.train.endedAt) or 999
  local heat = cooking and 1 or ((stt == "learned" and doneAgo < 3) and 0.5 or 0)

  -- Scene: [IN card] -> [furnace] -> [OUT card]
  local fw = big and 16 or 14
  local fh = big and 9 or 7
  local cw = math.max(10, math.min(15, math.floor((w - fw - 10) / 2)))
  local aw = math.max(3, math.floor((w - fw - 2 * cw - 4) / 2))
  local total = cw * 2 + aw * 2 + fw + 2
  local sx = math.max(2, math.floor((w - total) / 2) + 1)
  local smokeRows = big and 3 or 2
  local sy = 3 + smokeRows
  local fx = sx + cw + aw + 1
  local cardY = sy + math.floor((fh - 5) / 2)

  -- IN
  local inLines
  local inName = (cooking or stt == "learned" or stt == "failed") and S.train.input or (S.trainSlots.inp and S.trainSlots.inp.name)
  if inName then
    local cnt = (S.trainSlots.inp and S.trainSlots.inp.name == inName) and S.trainSlots.inp.count or nil
    inLines = itemLines(inName, cnt, cw)
  else
    inLines = { { "empty", K.grey }, { "drop it in", K.grey }, { "the top", K.grey } }
  end
  local inReady = stt == "idle" and S.trainSlots.inp
  card(sx, cardY, cw, 5, "PUT IN", inReady and ((S.frame % 4 < 2) and K.yellow or K.white) or K.lightGrey, inLines)
  drawArrow(sx + cw + 1, cardY + 2, aw - 1, cooking)

  drawFurnaceArt(fx, sy, fw, fh, heat)

  drawArrow(fx + fw + 1, cardY + 2, aw - 1, stt == "cooking")
  -- OUT
  local ox = fx + fw + aw + 1
  if stt == "learned" then
    card(ox, cardY, cw, 5, "COMES OUT", K.lime, itemLines(S.train.out, S.train.per > 1 and (S.train.per .. " each") or "1 each", cw))
    if doneAgo < 6 then          -- sparkles round the new recipe
      for k = 0, 9 do
        local px = ox - 1 + nz(k, S.frame) % (cw + 2)
        local py = cardY - 1 + nz(S.frame, k) % 7
        local ch = ({ "*", "+", "." })[nz(k, k, S.frame) % 3 + 1]
        if py >= 3 and py < h - 3 and (px < ox or px >= ox + cw or py < cardY or py > cardY + 5) then
          at(px, py, ch, (k + S.frame) % 2 == 0 and K.yellow or K.white)
        end
      end
    end
  elseif stt == "failed" then
    card(ox, cardY, cw, 5, "COMES OUT", K.red, { { "nothing", K.orange }, { "X", K.red } })
  else
    local q = cooking and ((S.frame % 4 < 2) and K.yellow or K.white) or K.grey
    card(ox, cardY, cw, 5, "COMES OUT", K.lightGrey, { "", { "?", q } })
  end

  -- What's happening, under the scene
  local y = sy + fh + 1
  local function text(t, col)
    for _, l in ipairs(wrap(t, w - 4)) do if y < h - bottomRows - 1 then at(3, y, pad(l, w - 4), col); y = y + 1 end end
  end
  if not S.trainSeen then
    text("I can't see the training furnace (" .. cfg.trainer .. "). Is its modem on (red ring)?", K.orange)
  elseif cooking then
    local steps = {
      { "Output slot clear", stt ~= "starting" },
      { "Fuel in", stt == "cooking" },
      { "First one cooked", false },
    }
    local sxp = 3
    for _, s in ipairs(steps) do
      local mark = s[2] and "\4 " or ("\7 ")
      local t = mark .. s[1]
      at(sxp, y, t, s[2] and K.lime or K.grey)
      sxp = sxp + #t + 3
    end
    y = y + 1
    if stt == "cooking" then
      local el = os.clock() - (S.train.fuelAt or os.clock())
      local label = ("%ds"):format(math.floor(el))
      bar(3, y, w - 6 - #label - 1, el / TRAIN_TIMEOUT, el > TRAIN_TIMEOUT * 0.6 and K.orange or K.yellow)
      at(w - 2 - #label, y, label, K.lightGrey)
      y = y + 1
      text(("Cooking one %s... (I give up after %ds)"):format(pretty(S.train.input), TRAIN_TIMEOUT), K.lightGrey)
    else
      text(S.train.note or "Getting it ready...", K.lightGrey)
    end
  elseif stt == "learned" then
    local how = S.train.per > 1 and (" (" .. S.train.per .. " each)") or ""
    text((S.train.known and "Already knew this one: " or "Learned: ") .. pretty(S.train.input) .. " -> " .. pretty(S.train.out) .. how, K.lime)
    text(("What should I do with %s?"):format(pretty(S.train.out)), K.white)
    local by = h - bottomRows - 1 - (big and 0 or 0)
    drawRuleChoice(3, by, w - 4, bottomRows, S.train.key, S.train.mode, S.train.stacks or 4, function(mode)
      if mode then setRule(S.train.key, mode, S.train.stacks or 4) end
      say(mode == "all" and ("Rule saved: smelt all " .. S.train.key) or mode == "keep" and
        ("Rule saved: keep %d stacks of %s"):format(S.train.stacks or 4, S.train.key) or ("Learned " .. S.train.key .. ", no rule."), K.lime)
      S.train = { state = "idle", giveBack = S.train.giveBack, input = S.train.input, seen = true }
      S.ui.pickMode = nil
      go("home")
    end)
  elseif stt == "failed" then
    text(S.train.reason or "That didn't work.", K.orange)
    text("It goes back into storage.", K.lightGrey)
  elseif S.trainSlots.inp then
    text(("Ready: %d %s in the top slot."):format(S.trainSlots.inp.count, pretty(S.trainSlots.inp.name)), K.white)
    text("Tap TRAIN and I'll fuel it and watch what comes out.", K.lightGrey)
  else
    text("Put the raw item in the trainer's TOP slot, then tap TRAIN.", K.white)
    text("One is enough. Leftovers go back into storage.", K.lightGrey)
  end

  -- Big buttons (not while choosing a rule)
  if stt ~= "learned" then
    local by = h - bottomRows - 1
    if cooking then
      button(3, by, 14, bottomRows, "CANCEL", K.grey, function()
        S.train = { state = "idle", giveBack = true, input = S.train.input, seen = true }
        say("Training cancelled: it goes back into storage.", K.orange)
      end, K.white)
    else
      local ready = S.trainSlots.inp ~= nil
      local col = ready and ((S.frame % 4 < 2) and K.lime or K.yellow) or K.grey
      button(3, by, 14, bottomRows, stt == "failed" and "TRY AGAIN" or "TRAIN", col, function()
        local ok, why = startTraining()
        if not ok then say(why, K.orange) end
      end, ready and K.black or K.lightGrey)
    end
  end

  at(1, fy, (" "):rep(w))
  if S.cmdLine then return end
  local x = 2
  x = smallButton(x, fy, "Change trainer", K.grey, function() go("pick") end, K.white)
  x = smallButton(x, fy, "Recipes", K.cyan, function() go("recipes") end)
  smallButton(w - 7, fy, "Back", K.grey, function() go("home") end, K.white)
end

---------------------------------------------------------------------------
-- Pick the trainer
---------------------------------------------------------------------------
local function drawPick(w, h)
  header(w, "< PICK THE TRAINER", S.picking and "watching..." or nil, K.yellow)
  hit(1, 1, 20, 1, function() S.picking = nil; go("train") end)
  local top, bottom = 3, h - 2
  if S.picking then
    local left = math.max(0, math.ceil(S.picking.untilT - os.clock()))
    local spin = ({ "|", "/", "-", "\\" })[S.frame % 4 + 1]
    local lines = {
      { spin .. " Drop any item into the TOP slot of the furnace you want.", K.white },
      { "The smelting array is paused while I watch.", K.lightGrey },
      { ("%d s left"):format(left), K.yellow },
    }
    local y = top + 2
    for _, l in ipairs(lines) do
      for _, t in ipairs(wrap(l[1], w - 4)) do at(3, y, t, l[2]); y = y + 1 end
    end
    bar(3, y + 1, w - 6, left / FIND_TIME, K.yellow)
    button(3, bottom - 2, 14, 3 <= (bottom - y - 2) and 3 or 1, "STOP", K.grey, function() S.picking = nil end, K.white)
    at(1, h, (" "):rep(w))
    return
  end
  local list = allFurnaces()
  at(2, top, pad(w >= 56 and "Tap one to make it the trainer (it leaves the array):" or "Tap one to make it the trainer:", w - 2), K.lightGrey)
  local y = top + 1
  local per = bottom - y + 1
  local pages = math.max(1, math.ceil(#list / per))
  S.ui.scroll = math.max(1, math.min(S.ui.scroll, pages))
  for i = 1, per do
    local fz = list[(S.ui.scroll - 1) * per + i]
    if not fz then break end
    local t = tierOf(fz)
    local s = fz == cfg.trainer and S.trainSlots or S.fstate[fz] or {}
    local what = s.inp and (s.inp.count .. " " .. itemShort(s.inp.name)) or "empty"
    at(2, y, pad(" " .. t[2], 13), t[5], t[4])
    lr(16, y, w - 16, shortName(fz), fz == cfg.trainer and "TRAINER" or what, fz == cfg.trainer and K.lime or K.white,
      fz == cfg.trainer and K.lime or K.grey)
    hit(1, y, w, y, function()
      local was = S.fstate[fz]
      cfg.trainer = fz; saveCfg(); findFurnaces()
      S.train = { state = "idle", clear = (was and (was.inp or was.out)) and true or nil, seen = true }
      say(shortName(fz) .. " is the trainer now." .. (S.train.clear and " Emptying its old smelting first." or " It's out of the smelting array."), K.lime)
      go("train")
    end)
    y = y + 1
  end
  if #list == 0 then at(2, y, "No furnaces on my cable.", K.orange) end
  at(1, h, (" "):rep(w))
  if S.cmdLine then return end
  local x = 2
  x = smallButton(x, h, "Find it", K.yellow, function()
    S.picking = { untilT = os.clock() + FIND_TIME, before = {} }
  end)
  if cfg.trainer then
    x = smallButton(x, h, "No trainer", K.grey, function()
      say(shortName(cfg.trainer) .. " is back in the smelting array.", K.orange)
      cfg.trainer = nil; saveCfg(); S.train = { state = "idle" }; go("home")
    end, K.white)
  end
  if pages > 1 then
    x = smallButton(x, h, "<", K.cyan, function() S.ui.scroll = math.max(1, S.ui.scroll - 1) end)
    x = smallButton(x, h, ">", K.cyan, function() S.ui.scroll = math.min(pages, S.ui.scroll + 1) end)
  end
  smallButton(w - 7, h, "Back", K.grey, function() go("train") end, K.white)
end

---------------------------------------------------------------------------
-- Recipes: everything it knows
---------------------------------------------------------------------------
local function drawRecipes(w, h)
  local keys = sortedKeys(S.book)
  local nLearned = 0
  for _, k in ipairs(keys) do if S.book[k].learned then nLearned = nLearned + 1 end end
  header(w, "< RECIPES", ("%d known, %d learned"):format(#keys, nLearned))
  hit(1, 1, 11, 1, function() go("home") end)
  local top, bottom = 3, h - 1
  local cols = (w >= 90) and 2 or 1
  local cw = math.floor((w - 1) / cols)
  local per = (bottom - top + 1) * cols
  local pages = math.max(1, math.ceil(#keys / per))
  S.ui.scroll = math.max(1, math.min(S.ui.scroll, pages))
  for i = 1, per do
    local k = keys[(S.ui.scroll - 1) * per + i]
    if not k then break end
    local r = S.book[k]
    local c, row = math.floor((i - 1) / (bottom - top + 1)), (i - 1) % (bottom - top + 1)
    local x, y = 2 + c * cw, top + row
    local bg = row % 2 == 1 and K.black or K.black
    local rule = ruleFor(k)
    local tag = rule and (rule.all and "all" or ("keep " .. rule.stacks)) or ""
    local from = r.pattern and "any log" or (#r.inputs > 0 and pretty(r.inputs[1]) .. (#r.inputs > 1 and (" +" .. (#r.inputs - 1)) or "") or "?")
    local nameW = math.min(18, math.floor(cw * 0.34))
    at(x, y, pad(k:gsub("_", " "), nameW), r.learned and K.yellow or K.white, bg)
    lr(x + nameW + 1, y, cw - nameW - 2, from .. " \26 " .. itemShort(r.out), tag, K.lightGrey, K.lime, bg)
    hit(x, y, x + cw - 2, y, function() go("rule", { key = k, edit = nil }) end)
  end
  at(1, h, (" "):rep(w))
  if S.cmdLine then return end
  local x = 2
  at(x, h, "yellow = learned", K.yellow); x = x + 18
  if pages > 1 then
    local label = ("%d/%d"):format(S.ui.scroll, pages)
    local px = w - #label - 17
    smallButton(px, h, "<", S.ui.scroll > 1 and K.cyan or K.grey, function() S.ui.scroll = math.max(1, S.ui.scroll - 1) end)
    at(px + 4, h, label, K.lightGrey)
    smallButton(px + 5 + #label, h, ">", S.ui.scroll < pages and K.cyan or K.grey, function() S.ui.scroll = math.min(pages, S.ui.scroll + 1) end)
  end
  smallButton(w - 7, h, "Back", K.grey, function() go("home") end, K.white)
end

---------------------------------------------------------------------------
-- One recipe: its rule (keep N stacks / smelt all / none), smelt now, forget
---------------------------------------------------------------------------
local function drawRule(w, h)
  local key = S.ui.key
  local name, r = recipeFor(key)
  header(w, "< " .. name:gsub("_", " "):upper(), r.learned and "learned" or (r.builtin and "built in" or "guessed: modded metal"))
  hit(1, 1, #name + 4, 1, function() go(S.ui.back or "home") end)
  local rule = ruleFor(name)
  if not S.ui.edit then
    S.ui.edit = { mode = rule and (rule.all and "all" or "keep") or nil, stacks = rule and rule.stacks or 4 }
  end
  local e = S.ui.edit
  local y = 3
  local function line(l, rv, cl, cr)
    if y < h - 1 then lr(3, y, w - 4, l, rv, cl or K.lightGrey, cr or K.white) end
    y = y + 1
  end
  line("Makes", pretty(r.out))
  if r.pattern then line("From", r.modded and ("raw " .. name .. " (any mod)") or "any log") end
  for _, i in ipairs(r.inputs) do
    local per = perOf(r, i)
    line("From", pretty(i) .. (per > 1 and (" (" .. per .. " each)") or ""))
  end
  for _, ore in ipairs(sortedKeys(cfg.enrich)) do
    local e = cfg.enrich[ore]
    if type(e) == "table" and e.out and not e.dustBad and (isInputOf(r, e.out) or (FX.direct.kind(S.book, ore, e) == "direct" and outMatches(r, e.out))) then
      line("Factory", ("%s -> %d %s per %d"):format(pretty(ore), e.made, pretty(e.out), e.used), K.lightGrey, K.lime)
    end
  end
  line("In storage", ("%s made, %s to smelt"):format(fmtNum(outCount(r)), fmtNum(inputTotal(r))))
  y = y + 1

  -- Rule
  if y < h - 1 then at(3, y, "RULE", K.cyan) end
  y = y + 1
  local rows = h >= 22 and 3 or 1
  local bx = 3
  button(bx, y, 3, rows, "-", K.grey, function() e.mode = "keep"; e.stacks = math.max(1, e.stacks - 1) end, K.white)
  bx = bx + 4
  button(bx, y, 15, rows, ("KEEP %d STACK%s"):format(e.stacks, e.stacks == 1 and "" or "S"), e.mode == "keep" and K.lime or K.lightGrey,
    function() e.mode = "keep" end)
  bx = bx + 16
  button(bx, y, 3, rows, "+", K.grey, function() e.mode = "keep"; e.stacks = math.min(999, e.stacks + 1) end, K.white)
  bx = bx + 4
  if bx + 11 <= w then
    button(bx, y, 11, rows, "SMELT ALL", e.mode == "all" and K.lime or K.lightGrey, function() e.mode = "all" end)
    bx = bx + 12
  end
  if bx + 9 <= w then
    button(bx, y, 9, rows, "NO RULE", e.mode == nil and K.orange or K.lightGrey, function() e.mode = nil end)
  end
  y = y + rows
  if y < h - 1 then
    local now = rule and (rule.all and "smelt all" or ("keep " .. rule.stacks .. " stacks")) or "none"
    local changed = (e.mode ~= (rule and (rule.all and "all" or "keep") or nil)) or (e.mode == "keep" and rule and rule.stacks ~= e.stacks)
    at(3, y, pad(("Now: %s%s"):format(now, changed and "   (tap SAVE)" or ""), w - 4), changed and K.yellow or K.grey)
  end
  y = y + 2

  -- Smelt now
  if y + rows <= h - 1 then
    at(3, y, "SMELT NOW", K.cyan)
    y = y + 1
    local x = 3
    for _, n in ipairs({ 64, 256, 1024 }) do
      button(x, y, 8, rows, tostring(n), K.lightGrey, function()
        queueSmelt(name, n); say(("Queued %d %s."):format(n, name), K.lime)
      end)
      x = x + 9
    end
    local all = inputTotal(r)
    button(x, y, 12, rows, "ALL " .. fmtNum(all), all > 0 and K.lightGrey or K.grey, function()
      if all > 0 then queueSmelt(name, all); say(("Queued %d %s."):format(all, name), K.lime) end
    end)
  end

  -- Footer: Save / Forget / Back
  at(1, h, (" "):rep(w))
  if S.cmdLine then return end
  local x = 2
  x = smallButton(x, h, "SAVE", K.lime, function()
    setRule(name, e.mode, e.stacks)
    say(e.mode == "all" and ("Saved: smelt all " .. name) or e.mode == "keep" and ("Saved: keep %d stacks of %s"):format(e.stacks, name)
      or ("Saved: no rule for " .. name), K.lime)
    go(S.ui.back or "home")
  end)
  if r.learned then
    if S.ui.confirm == "forget" then
      x = smallButton(x, h, "Sure? Forget", K.red, function()
        forget(name); say("Forgot what I learned about " .. name .. ".", K.orange); go("recipes")
      end, K.white)
    else
      x = smallButton(x, h, "Forget", K.grey, function() S.ui.confirm = "forget" end, K.white)
    end
  end
  smallButton(w - 7, h, "Back", K.grey, function() go(S.ui.back or "home") end, K.white)
end

S.drawPick, S.drawRecipes, S.drawRule, S.drawTrain = drawPick, drawRecipes, drawRule, drawTrain
end
