-- assignrules.lua  --  the depot rule pages of "/assign": the rule form, the Item / Tag / Mod pick list,
-- "Something like this", and the Holds / Priority / Matches / Overlaps rows on the edit page.
-- Loaded by assignui.lua with dofile() when the program gives it a rules engine (o.rules, storage_rules.lua).
-- Built from the UI kit. docs/design/storage.md, "Depot rules".

return function(X)
  local o, st, ui, v = X.o, X.st, X.ui, X.v
  local fmt, go, plan = X.fmt, X.go, X.plan
  local fit = ui.text.fit
  local R = o.rules
  local M = {}

  local FIELDS = { { "item", "Item" }, { "tag", "Tag" }, { "mod", "Mod" } }

  function M.hasRule(r)
    return r ~= nil and (r.item ~= nil or r.tag ~= nil or r.mod ~= nil or r.enchanted ~= nil)
  end

  local function ticked(l, val)
    for _, x in ipairs(l or {}) do if x == val then return true end end
    return false
  end

  -- Values joined with ", ", cut to fit `width` with "+N" for the ones left out: "relics, artifacts, +1"
  local function joined(l, width)
    for k = #l, 1, -1 do
      local t = table.concat(l, ", ", 1, k) .. (k < #l and (", +" .. (#l - k)) or "")
      if #t <= width then return t end
    end
    return fit(l[1], width)
  end

  local function nameOf(n) return X.names[n] or X.shortName(n) end

  -- Open the rule form for the depot being edited
  function M.open()
    st.edit.rule = st.edit.rule or {}
    go("rule")
  end

  -- Back from the form: to the container list while adding, else to the edit page
  function M.back()
    local e = st.edit
    if e.isNew then st.edit = nil end
    go(e.isNew and "pick" or "edit")
  end

  local function previewRows(y, last, res)
    local n = math.min(#res.list, last - y + 1)
    if n < #res.list then n = math.max(n - 1, 0) end
    for i = 1, n do
      local it = res.list[i]
      v:put(3, y + i - 1, fit(it.label or X.prettyName(it.name), v.W - 11), "fg", "bg")
      local c = fmt(it.count)
      v:put(v.W - #c, y + i - 1, c, "info", "bg")
    end
    if n < #res.list and y + n <= last then
      v:put(3, y + n, ("... %d more"):format(#res.list - n), "dim", "bg")
    end
  end

  -- Step 2: the rule form
  function M.drawForm()
    local e = st.edit
    local dp = X.depotOf(e.key)
    local r = e.rule
    local W = v.W
    v:header(e.isNew and ("ADD " .. dp.title) or (dp.title .. " RULE"), { state = e.isNew and "step 2 of 3" or nil, color = "dim" })
    local has = M.hasRule(r)
    local pl = plan(v, {
      { label = "Next", style = "primary", id = "next", enabled = has, fn = function() go("edit") end },
      { label = "Something like this", short = "Like this", id = "like", fn = function() M.watch() end },
    }, { back = true })
    v:put(2, 3, fit("What goes in " .. nameOf(e.name) .. "? Set any of these.", W - 2), "dim", "bg")
    local y = 5
    local bw = math.max(6, W - 13)
    for _, f in ipairs(FIELDS) do
      v:put(2, y, f[2], "dim", "bg")
      local txt = r[f[1]] and joined(r[f[1]], bw - 2) or "any"
      v:buttons(13, y, { { label = txt .. (" "):rep(bw - 2 - #txt), id = "rf-" .. f[1], fn = function()
        st.rfield = f[1]
        go("rpick")
      end } })
      y = y + 1
    end
    v:put(2, y, "Enchanted", "dim", "bg")
    local cur = r.enchanted == nil and "any" or (r.enchanted and "yes" or "no")
    v:switch(13, y, { { id = "any", label = "Any" }, { id = "yes", label = "Yes" }, { id = "no", label = "No" } }, cur,
      function(id)
        if id == "yes" then r.enchanted = true elseif id == "no" then r.enchanted = false else r.enchanted = nil end
      end, { id = "ench", maxx = W - 1 })
    y = y + 2
    if has then
      local res = R.preview(r, e.name)
      v:put(2, y, fit(("Matches now: %d kinds, %s items"):format(res.kinds, fmt(res.items)), W - 2), "fg", "bg")
      previewRows(y + 1, pl.bottom, res)
    else
      v:put(2, y, fit("Set at least one of these to see what it takes.", W - 2), "dim", "bg")
    end
    v:footer({ back = M.back })
    pl.draw()
  end

  -- The Item / Tag / Mod pick list: tick as many as you like
  function M.drawPick()
    local e = st.edit
    local f = st.rfield
    local dp = X.depotOf(e.key)
    local title = f == "item" and "ITEM" or f == "tag" and "TAG" or "MOD"
    local picked = e.rule[f] or {}
    v:header("DEPOT " .. title, { state = #picked > 0 and ("%d ticked"):format(#picked) or "tap to tick", color = "dim" })
    local q = st.f.text:lower()
    local rows = {}
    local function add(label, right, value)
      if q == "" or label:lower():find(q, 1, true) then
        local on = ticked(e.rule[f], value)
        rows[#rows + 1] = { name = (on and "[x] " or "[ ] ") .. label, value = right, state = on and "info" or nil, id = value,
          tone = on and "info" or "dim" }
      end
    end
    if f == "item" then
      for _, it in ipairs(dp.items(e.name)) do add(it.label or X.prettyName(it.name), fmt(it.count or 0), it.name) end
    elseif f == "tag" then
      for _, t in ipairs(R.tags()) do add(t.tag, ("%d kinds  %s"):format(t.kinds, fmt(t.items)), t.tag) end
    else
      for _, m in ipairs(R.mods()) do add(m.mod, ("%d kinds  %s"):format(m.kinds, fmt(m.items)), m.mod) end
    end
    local what = f == "item" and "Items in storage, variants merged." or (title:sub(1, 1) .. title:sub(2):lower() .. "s on items in storage.")
    v:put(2, 3, fit(what .. " Type to narrow it down.", v.W - 2), "dim", "bg")
    local pl = plan(v, {
      { label = "Done", style = "primary", id = "done", fn = function() go("rule") end },
      { label = "Any", id = "any", fn = function() e.rule[f] = nil; go("rule") end },
    }, { back = true, pager = true, input = 1 })
    if #rows == 0 then v:put(2, 4, "Nothing matches.", "dim", "bg") end
    v:list(rows, { top = 4, input = v.H - 1 - pl.bottom, once = true, on = function(row)
      local l = e.rule[f] or {}
      if ticked(l, row.id) then
        for i, x in ipairs(l) do if x == row.id then table.remove(l, i); break end end
      else
        l[#l + 1] = row.id
      end
      e.rule[f] = #l > 0 and l or nil
    end })
    v:footer({ back = function() go("rule") end })
    pl.draw()
    v:search(st.f, { hint = "search" })
  end

  -- Drop one item into the depot and read what is true about it
  function M.watch()
    local e = st.edit
    X.startWatch({ kind = "box", box = e.name, title = "SOMETHING LIKE THIS",
      line1 = "Drop ONE item into " .. nameOf(e.name) .. ".",
      line2 = "Nothing gets moved while I watch it. The item stays in the depot.",
      done = function(slot)
        if not slot then X.say("Didn't see an item go in. Try again?", "warn"); return end
        local d = X.call(e.name, "getItemDetail", slot)
        if not d then X.say("Couldn't read that item.", "warn"); return end
        local i = R.fill({}, d)
        local tags = {}
        for t in pairs(i.tags) do
          tags[#tags + 1] = { tag = t, items = R.count({ tag = t }).items }
        end
        table.sort(tags, function(a, b)
          if a.items ~= b.items then return a.items > b.items end
          return a.tag < b.tag
        end)
        st.like = { name = d.name, label = d.displayName or X.prettyName(d.name), enchanted = i.enchanted,
          tags = tags, mod = R.modOf(d.name), ticks = { item = true, tags = {} } }
        go("rlike")
      end })
  end

  local function likeRule()
    local l = st.like
    local r = {}
    if l.ticks.item then r.item = { l.name } end
    if l.ticks.enchanted then r.enchanted = l.enchanted end
    if l.ticks.mod then r.mod = { l.mod } end
    for _, t in ipairs(l.tags) do
      if l.ticks.tags[t.tag] then r.tag = r.tag or {}; table.insert(r.tag, t.tag) end
    end
    return r
  end

  -- "Something like this": tick what counts about the example
  function M.drawLike()
    local e, l = st.edit, st.like
    local W = v.W
    v:header("SOMETHING LIKE THIS")
    local r = likeRule()
    local has = M.hasRule(r)
    local pl = plan(v, {
      { label = "Use these", style = "primary", id = "use", enabled = has, fn = function() e.rule = likeRule(); go("rule") end },
      { label = "Other example", short = "Other", id = "other", fn = function() M.watch() end },
    }, { back = true, pager = true })
    v:put(2, 3, fit("Example: " .. l.label, W - 2), "fg", "bg")
    local rows = {}
    local function row(label, value, count, on, toggle)
      rows[#rows + 1] = { name = (on and "[x] " or "[ ] ") .. label .. (" "):rep(math.max(1, 12 - #label)) .. value, value = fmt(count),
        state = on and "info" or nil, tone = on and "info" or "dim", toggle = toggle }
    end
    row("This item", l.label, R.count({ item = l.name }).items, l.ticks.item, function() l.ticks.item = not l.ticks.item or nil end)
    row("Enchanted", l.enchanted and "yes" or "no", R.count({ enchanted = l.enchanted }).items, l.ticks.enchanted,
      function() l.ticks.enchanted = not l.ticks.enchanted or nil end)
    for _, t in ipairs(l.tags) do
      row("Tag", t.tag, t.items, l.ticks.tags[t.tag], function() l.ticks.tags[t.tag] = not l.ticks.tags[t.tag] or nil end)
    end
    row("Mod", l.mod, R.count({ mod = l.mod }).items, l.ticks.mod, function() l.ticks.mod = not l.ticks.mod or nil end)
    local foot = has and (function()
      local res = R.preview(r, e.name)
      return ("Matches now: %d kinds, %s items"):format(res.kinds, fmt(res.items))
    end)() or "Tick at least one line."
    local last = pl.bottom - 1
    v:list(rows, { top = 4, input = v.H - 1 - last, once = true, on = function(row) row.toggle() end })
    v:put(2, last + 1, fit(foot, W - 2), has and "fg" or "dim", "bg")
    v:footer({ back = function() go("rule") end })
    pl.draw()
  end

  -- Holds / Priority / Matches / Overlaps on the edit page. Returns the next free row.
  function M.editRows(e, y, bottom)
    local W = v.W
    local r = e.rule
    if not M.hasRule(r) then
      local x = v:buttons(2, y, { { label = "Set rule", id = "setrule", fn = M.open } })
      v:put(x + 1, y, fit("What should it hold?", W - x - 1), "warn", "bg")
      return y + 1
    end
    v:put(2, y, "Holds", "dim", "bg")
    local holds = fit(R.describe(r), W - 12)
    v:buttons(10, y, { { label = holds .. (" "):rep(math.max(0, W - 12 - #holds)), id = "holds", fn = M.open } })
    y = y + 1
    if y > bottom then return y end
    e.prioF.text = e.prioF.text:gsub("%D", ""):sub(1, 4)   -- digits only
    v:field(2, y, "Priority", 6, e.prioF)
    v:put(19, y, fit("higher wins a tie, 0 to 9999", W - 19), "dim", "bg")
    y = y + 1
    if y > bottom then return y end
    local res = R.preview(r, e.name)
    v:kv(2, y, W - 2, "Matches", ("%d kinds, %s items in storage now"):format(res.kinds, fmt(res.items)))
    y = y + 1
    local lost = {}
    for n, kinds in pairs(res.lost) do lost[#lost + 1] = { n = n, kinds = kinds } end
    table.sort(lost, function(a, b) return a.n < b.n end)
    for i = 1, math.min(2, #lost) do
      if y > bottom then break end
      local last = i == 2 and #lost > 2
      local text = ("%s wins %d %s%s"):format(nameOf(lost[i].n), lost[i].kinds, lost[i].kinds == 1 and "kind" or "kinds",
        last and (" (+%d more depots)"):format(#lost - 2) or "")
      v:kv(2, y, W - 2, "Overlaps", text, "warn")
      y = y + 1
    end
    return y
  end

  return M
end
