-- smelter_facui.lua  --  smelter: the Factories page (a card per factory, the ORES list of what they learned) and the
-- add-a-factory wizard. Built from the UI kit. The footer buttons are one list and the ORES list is a kit list
-- whose rows take a tap, so an `+ Item` button and a pick page can be added next to them. Part of
-- computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local FX, cfg, ui = S.FX, S.cfg, S.FX.kit
local fmtNum, go, itemShort, isInputOf, pretty, say, shortName = S.fmtNum, S.go, S.itemShort, S.isInputOf, S.pretty, S.say, S.shortName
local fit = ui.text.fit

local ORE_TONE = { direct = "good", ["via dust"] = "good", ["checking dust"] = "gold", queued = "dim" }
local function oreTone(state) return ORE_TONE[state] or (state:find("^trying") and "gold") or "warn" end

-- One factory: three rows (state and power, the machine and its process count, the barrels), or one row on a
-- small screen. A tap selects it (Remove then names it); the stripe is the state colour, gold when selected.
local function drawCard(v, st, i, x, y, w, rows)
  local f, fs = cfg.factories[i], FX.facs[i] or {}
  local tone = st.fac == i and "gold" or FX.facTone(i)
  local gone = fs.why and fs.why:find("missing", 1, true)
  local power = fs.energy and ("%d%% power"):format(math.floor(fs.energy * 100 + 0.5)) or ""
  for r = 0, rows - 1 do
    if v.colour then v:put(x, y + r, " ", "fg", tone) else v:put(x, y + r, "|", "fg", "bg") end
  end
  local tx, tw = x + 2, w - 2
  if rows == 1 then
    v:put(tx, y, fit("F" .. i .. " " .. FX.factoryLine(i), tw - #power - 1), FX.facTone(i), "bg")
    v:put(tx + tw - #power, y, power, "dim", "bg")
  else
    v:put(tx, y, fit(FX.factoryName(i) .. ": " .. FX.factoryLine(i), tw - #power - 1), FX.facTone(i), "bg")
    v:put(tx + tw - #power, y, power, "dim", "bg")
    v:kv(tx + 2, y + 1, tw - 2, shortName(f.machine), gone and "not on the cable" or (fs.procs and (fs.procs .. " processes") or ""), gone and "bad" or "dim")
    v:put(tx + 2, y + 2, fit(("feed %s -> out %s"):format(shortName(f.feed), shortName(f.out)), tw - 2), "dim", "bg")
  end
  v:_box({ x, y, x + w - 1, y + rows - 1 }, nil, { id = "fac:" .. i, fn = function() st.fac = (st.fac ~= i) and i or nil; v.armed = nil; v.sel = nil; st.lastSel = nil end })
end

local function drawFactories(v, st)
  local W, H = v.W, v.H
  v:header("FACTORIES", { state = ("%d set up"):format(#cfg.factories), color = "dim" })
  if st.fac and not cfg.factories[st.fac] then st.fac = nil end
  -- What the factories have learned about ores (and what was added by hand)
  local list = FX.enrichList()
  local oreRows = {}
  for _, o in ipairs(list) do
    local e = o.e
    local extra = FX.direct.isExtra(cfg.enrichExtra or {}, o.ore)
    local name = (extra and "+" or " ") .. itemShort(o.ore)
    if W >= 44 and e.out then name = name .. " -> " .. e.made .. " " .. itemShort(e.out) .. " per " .. e.used end
    oreRows[#oreRows + 1] = { name = name, value = o.state, tone = oreTone(o.state), id = o.ore, extra = extra, learned = cfg.enrich[o.ore] ~= nil }
  end
  if v.sel ~= st.lastSel then                                -- picking an ore row lets go of a factory card
    if v.sel then st.fac = nil end
    st.lastSel = v.sel
  end
  local ore = v.sel and oreRows[v.sel]
  local acts = { { label = "+ Add", id = "add", style = "primary", fn = function() go(v, "fadd", { step = "machine" }) end },
    { label = "+ Item", id = "item", style = "primary", fn = function() go(v, "fitem", { filter = "smeltable" }) end } }
  if ore then
    acts[#acts + 1] = { label = "Retry", id = "retry", enabled = ore.learned, fn = function()
      FX.enrichForget(ore.id); say(pretty(ore.id) .. " gets tried again.", S.K.lime)
    end }
    if ore.extra then
      acts[#acts + 1] = { label = "Remove", id = "oreremove", confirm = true, style = "danger", fn = function()
        FX.enrichRemove(ore.id); v.sel = nil; st.lastSel = nil
        say(pretty(ore.id) .. " is off the factory list.", S.K.orange)
      end }
    end
  end
  if st.fac then
    acts[#acts + 1] = { label = "Remove F" .. st.fac, short = "Del F" .. st.fac, id = "remove", confirm = true, style = "danger", fn = function()
      FX.removeFactory(st.fac)
      say("Factory removed. Storage stops treating its barrels specially in a few seconds.", S.K.orange)
      st.fac = nil
    end }
  end
  local plan = S.plan(v, acts, { back = true, pager = true })
  local w, bottom = W - 2, plan.bottom
  local y = 3
  if #cfg.factories == 0 then
    y = S.text(v, 2, 4, w, bottom, "No factories yet.", "fg")
    if #oreRows == 0 then y = S.text(v, 2, y + 1, w, bottom, "A factory setup: a FEED barrel on the cable with a hopper upgrade pushing into the factory's Input face, the factory with a wired modem on it, and auto-eject into an OUT barrel on the cable. Tap + Add and pick the three.", "dim") end
  end
  local rows = (H >= 19 and W >= 44) and 3 or 1
  for i = 1, #cfg.factories do
    if y + rows - 1 > bottom - 4 and i > 1 then break end        -- leave the ORES list a few rows
    drawCard(v, st, i, 2, y, w, rows)
    y = y + rows + (rows > 1 and 1 or 0)
  end

  if #oreRows > 0 and y + 1 <= bottom then
    local hint = H >= 19 and W >= 51
    y = v:section(2, y + (rows > 1 and 0 or 1), w, "Ores")
    v:list(oreRows, { top = y, input = plan.input + (hint and 1 or 0) })
    if hint then v:put(2, bottom, " + = added by hand. Tap one for Retry / Remove.", "dim", "bg") end
  end
  v:footer({ back = function() go(v, "home") end }); plan.draw()
end

---------------------------------------------------------------------------
-- Add a factory: three steps (the machine, its feed barrel, its out barrel), each a list of what is left on the cable
---------------------------------------------------------------------------
local HINT = {
  machine = "Pick the factory (wired modem on it, ring red):",
  feed = "Pick its FEED barrel (hopper upgrade into the factory):",
  out = "Pick its OUT barrel (the factory ejects into it):",
}
local function drawAdd(v, st)
  local step = st.step or "machine"
  local n = step == "machine" and 1 or (step == "feed" and 2 or 3)
  v:header("ADD A FACTORY", { state = ("step %d/3"):format(n), color = "dim" })
  local back = function() go(v, "factories") end
  local plan = S.plan(v, {}, { back = true, pager = true })
  local chosen = {}
  if st.pickM then chosen[st.pickM] = true end
  if st.pickF then chosen[st.pickF] = true end
  local names = step == "machine" and FX.machineCandidates() or FX.barrelCandidates(chosen)
  local top = 3 + #S.wrap(HINT[step], v.W - 2)
  S.text(v, 2, 3, v.W - 2, plan.bottom, HINT[step], "dim")
  local done = {}
  if st.pickM then done[#done + 1] = "factory " .. shortName(st.pickM) end
  if st.pickF then done[#done + 1] = "feed " .. shortName(st.pickF) end
  local keep = #done > 0 and 1 or 0
  if keep == 1 then v:put(2, plan.bottom, fit(table.concat(done, ", "), v.W - 2), "bar", "bg") end
  local rows = {}
  for _, name in ipairs(names) do rows[#rows + 1] = { name = shortName(name), id = name } end
  v:list(rows, { once = true, top = top, input = plan.input + keep, on = function(row)
    local name = row.id
    if step == "machine" then go(v, "fadd", { step = "feed", pickM = name })
    elseif step == "feed" then go(v, "fadd", { step = "out", pickM = st.pickM, pickF = name })
    else
      local i = FX.addFactory(st.pickM, st.pickF, name)
      say(("%s added: feed %s -> out %s"):format(FX.factoryName(i), shortName(st.pickF), shortName(name)), S.K.lime)
      go(v, "factories", { fac = i })
    end
  end })
  if #rows == 0 then
    v:put(2, top, fit(step == "machine" and "No factory on my cable: put a wired modem on it, right-click it." or "No barrels left on my cable.", v.W - 2), "warn", "bg")
  end
  v:footer({ back = back })
end


---------------------------------------------------------------------------
-- Pick an item to try: storage's items (what the furnaces cook, or all), most first. Tap one, then Try it.
---------------------------------------------------------------------------
local function drawItem(v, st)
  local filter = st.filter or "smeltable"
  v:header("ADD AN ITEM", { state = filter, color = "dim" })
  local on = {}
  for _, o in ipairs(FX.enrichList()) do on[o.ore] = true end
  local counts = {}
  for name, n in pairs(S.byName) do counts[name] = n end
  for _, name in ipairs(cfg.enrichExtra or {}) do counts[name] = counts[name] or 0 end
  local items = {}
  for name, n in pairs(counts) do
    local ok = filter == "all" or on[name] or FX.trialable(name)
    if not ok then for _, r in pairs(S.book) do if isInputOf(r, name) then ok = true; break end end end
    if ok then items[#items + 1] = { name = name, n = n } end
  end
  table.sort(items, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  local rows = {}
  for _, it in ipairs(items) do
    rows[#rows + 1] = { name = pretty(it.name), value = on[it.name] and "already on" or fmtNum(it.n), tone = on[it.name] and "dim" or "fg", id = it.name, on = on[it.name] }
  end
  local try = { label = "Try it", id = "try", style = "primary", enabled = false, fn = function()
    local row = rows[v.sel or 0]
    if not row or row.on then return end
    FX.enrichAdd(row.id)
    say(pretty(row.id) .. " queued for a factory trial", S.K.lime)
    go(v, "factories")
  end }
  local acts = { try,
    { label = "Smeltable", id = "smeltable", style = filter == "smeltable" and "on" or "idle", fn = function() st.filter = "smeltable"; v.sel, v.page = nil, 1 end },
    { label = "All", id = "all", style = filter == "all" and "on" or "idle", fn = function() st.filter = "all"; v.sel, v.page = nil, 1 end } }
  local plan = S.plan(v, acts, { back = true, pager = true })
  local w, y = v.W - 2, 3
  if v.W >= 51 and v.H >= 19 then
    y = S.text(v, 2, 3, w, plan.bottom - 3, "Pick an item to try in the factory. The trial learns what one makes; nothing is hard-coded.", "dim") + 1
  end
  local hint = v.W >= 51 and v.H >= 13
  v:list(rows, { top = y, input = plan.input + (hint and 1 or 0) })
  local row = v.sel and rows[v.sel]
  try.enabled = row ~= nil and not row.on
  if hint then v:put(2, plan.bottom, "Tap one, then Try it. Smeltable = the furnaces cook it.", "dim", "bg") end
  v:footer({ back = function() go(v, "factories") end }); plan.draw()
end

S.pages.factories, S.pages.fadd, S.pages.fitem = drawFactories, drawAdd, drawItem
end
