-- smelter_lists.lua  --  smelter: the recipes list and one recipe's rule page (keep N stacks / smelt all / none,
-- smelt now, forget). Built from the UI kit. Part of computer/smelter/smelter.lua; the shared state S is passed in.

return function(S)
local FX, cfg, ui = S.FX, S.cfg, S.FX.kit
local fmtNum, forget, go, inputTotal, isInputOf, itemShort = S.fmtNum, S.forget, S.go, S.inputTotal, S.isInputOf, S.itemShort
local outCount, outMatches, perOf, pretty, queueSmelt, recipeFor = S.outCount, S.outMatches, S.perOf, S.pretty, S.queueSmelt, S.recipeFor
local ruleFor, say, setRule, sortedKeys = S.ruleFor, S.say, S.setRule, S.sortedKeys
local fit = ui.text.fit

---------------------------------------------------------------------------
-- Recipes: everything it knows. A gold stripe (a star on a narrow screen) marks what it learned.
---------------------------------------------------------------------------
local function drawRecipes(v, st)
  local keys = sortedKeys(S.book)
  local nLearned = 0
  for _, k in ipairs(keys) do if S.book[k].learned then nLearned = nLearned + 1 end end
  v:header("RECIPES", { state = v.wc == "narrow" and (#keys .. " known") or ("%d known, %d learned"):format(#keys, nLearned), color = "dim" })
  local plan = S.plan(v, {}, { back = true, pager = true })
  local hint = v.wc ~= "narrow" and v.H >= 14
  local rows = {}
  for _, k in ipairs(keys) do
    local r = S.book[k]
    local rule = ruleFor(k)
    local from = r.pattern and "any log" or (#r.inputs > 0 and pretty(r.inputs[1]) .. (#r.inputs > 1 and (" +" .. (#r.inputs - 1)) or "") or "?")
    local name = (k:gsub("_", " "))
    if v.wc == "narrow" then name = (r.learned and "*" or "") .. name
    elseif v.W >= 44 then name = fit(name, 16) .. (" "):rep(math.max(0, 17 - #name)) .. from .. " > " .. itemShort(r.out) end
    rows[#rows + 1] = { name = name, value = rule and (rule.all and "all" or ("keep " .. rule.stacks)) or nil,
      state = r.learned and "gold" or nil, id = k }
  end
  v:list(rows, { once = true, input = plan.input + (hint and 1 or 0), on = function(row) go(v, "rule", { key = row.id, back = "recipes" }) end })
  if hint then v:put(2, plan.bottom, "gold = learned. Tap one to set its rule.", "dim", "bg") end
  v:footer({ back = function() go(v, "home") end })
end

---------------------------------------------------------------------------
-- One recipe: its rule, smelt now, forget
---------------------------------------------------------------------------
local function drawRule(v, st)
  local name, r = recipeFor(st.key)
  local rule = ruleFor(name)
  local back = function() go(v, st.back or "home") end
  v:header((name:gsub("_", " ")), { state = r.learned and "learned" or (r.builtin and "built in" or "guessed"),
    color = r.learned and "good" or "dim" })
  if not st.edit then
    st.edit = { mode = rule and (rule.all and "all" or "keep") or "none", stacks = rule and rule.stacks or 4 }
  end
  local e = st.edit
  local nowMode = rule and (rule.all and "all" or "keep") or "none"
  local acts = { { label = "Save", style = "primary", id = "save", fn = function()
    local mode = e.mode ~= "none" and e.mode or nil
    setRule(name, mode, e.stacks)
    say(mode == "all" and ("Saved: smelt all " .. name) or mode == "keep" and ("Saved: keep %d stacks of %s"):format(e.stacks, name)
      or ("Saved: no rule for " .. name), S.K.lime)
    back()
  end } }
  if r.learned then
    acts[2] = { label = "Forget", id = "forget", confirm = true, style = "danger", fn = function()
      forget(name); say("Forgot what I learned about " .. name .. ".", S.K.orange); go(v, "recipes")
    end }
  end
  local plan = S.plan(v, acts, { back = true })
  local w, bottom = v.W - 2, plan.bottom
  local tight = bottom - 3 < 11

  -- What it is, as far as there is room above the controls
  local y, infoLast = 3, bottom - (tight and 6 or 9)
  local function line(k, val, tone)
    if y <= math.max(infoLast, 3) then v:kv(2, y, w, k, val, tone); y = y + 1 end
  end
  line("Makes", pretty(r.out))
  if r.pattern then line("From", r.modded and ("raw " .. name .. " (any mod)") or "any log") end
  for _, i in ipairs(r.inputs) do
    local per = perOf(r, i)
    line("From", pretty(i) .. (per > 1 and (" (" .. per .. " each)") or ""))
  end
  for _, ore in ipairs(sortedKeys(cfg.enrich)) do
    local en = cfg.enrich[ore]
    if type(en) == "table" and en.out and not en.dustBad and (isInputOf(r, en.out) or (FX.direct.kind(S.book, ore, en) == "direct" and outMatches(r, en.out))) then
      line("Factory", ("%s -> %d %s per %d"):format(pretty(ore), en.made, pretty(en.out), en.used), "good")
    end
  end
  line("In storage", ("%s made, %s to smelt"):format(fmtNum(outCount(r)), fmtNum(inputTotal(r))))

  -- The rule
  if not tight then y = y + 1 end
  y = v:section(2, y, w, "Rule")
  local _, sy = v:switch(2, y, {
    { id = "none", label = "No rule", short = "None" }, { id = "keep", label = "Keep N stacks", short = "Keep N" },
    { id = "all", label = "Smelt all", short = "All" } }, e.mode, function(id) e.mode = id end, { id = "rule-mode" })
  y = sy + 1
  if e.mode == "keep" then
    v:stepper(2, y, "Keep", e.stacks, { min = 1, max = 999, on = function(n) e.stacks = n end })
    y = y + (v.wc == "narrow" and 2 or 1)
  end
  local changed = e.mode ~= nowMode or (e.mode == "keep" and rule and rule.stacks ~= e.stacks)
  local nowText = rule and (rule.all and "smelt all" or ("keep " .. rule.stacks .. " stacks")) or "none"
  if y <= bottom then v:put(2, y, fit(("Now: %s%s"):format(nowText, changed and "  (tap Save)" or ""), w), changed and "gold" or "dim", "bg") end
  y = y + 1

  -- Smelt now
  if not tight then y = y + 1 end
  if y + 1 <= bottom then
    y = v:section(2, y, w, "Do it now")
    local all = inputTotal(r)
    local list = {}
    for _, n in ipairs({ 64, 256, 1024 }) do
      list[#list + 1] = { label = "Smelt " .. n, short = tostring(n), id = "smelt" .. n, fn = function()
        queueSmelt(name, n); say(("Queued %d %s."):format(n, name), S.K.lime)
      end }
    end
    list[#list + 1] = { label = "Smelt all " .. fmtNum(all), short = "All " .. fmtNum(all), id = "smeltall",
      enabled = all > 0, fn = function() queueSmelt(name, all); say(("Queued %d %s."):format(all, name), S.K.lime) end }
    v:buttons(2, y, list, {})
  end
  v:footer({ back = back }); plan.draw()
end

S.pages.recipes, S.pages.rule = drawRecipes, drawRule
end
