-- assignrules.lua  --  the depot rule pages of "/assign": the rule form, the Item / Tag / Mod pick list,
-- "Something like this", and the Holds / Priority / Matches / Overlaps rows on the edit page.
-- Loaded by assignui.lua with dofile() when the program gives it a rules engine (o.rules, storage_rules.lua).
-- docs/design/storage.md, "Depot rules".

return function(X)
  local o, st, C = X.o, X.st, X.C
  local put, btn, region, cut, fmt = X.put, X.btn, X.region, X.cut, X.fmt
  local R = o.rules
  local M = {}

  local FIELDS = { { "item", "Item" }, { "tag", "Tag" }, { "mod", "Mod" } }

  function M.hasRule(r)
    return r ~= nil and (r.item ~= nil or r.tag ~= nil or r.mod ~= nil or r.enchanted ~= nil)
  end

  local function ticked(l, v)
    for _, x in ipairs(l or {}) do if x == v then return true end end
    return false
  end

  -- Values joined with ", ", cut to fit `width` with "+N" for the ones left out: "relics, artifacts, +1"
  local function joined(l, width)
    for k = #l, 1, -1 do
      local t = table.concat(l, ", ", 1, k) .. (k < #l and (", +" .. (#l - k)) or "")
      if #t <= width then return t end
    end
    return cut(l[1], width)
  end

  local function nameOf(n) return X.names[n] or X.shortName(n) end

  -- Open the rule form for the depot being edited
  function M.open()
    local e = st.edit
    e.rule = e.rule or {}
    st.page, st.filter, st.pg = "rule", "", 1
  end

  -- Back from the form: to the container list while adding, else to the edit page
  function M.back()
    local e = st.edit
    st.page, st.filter, st.pg = e.isNew and "pick" or "edit", "", 1
    if e.isNew then st.edit = nil end
  end

  local function previewRows(y, res, rows, w)
    for i = 1, math.min(rows, #res.list) do
      local it = res.list[i]
      local bg = i % 2 == 1 and C.stripe or C.bg
      term.setCursorPos(1, y + i - 1); term.setBackgroundColour(bg); term.clearLine()
      put(3, y + i - 1, cut(it.label or X.prettyName(it.name), w - 10), C.fg, bg)
      local c = fmt(it.count)
      put(w - #c, y + i - 1, c, C.dim, bg)
    end
    if #res.list > rows then put(2, y + rows, ("... %d more"):format(#res.list - rows), C.dim) end
  end

  -- Step 2: the rule form
  function M.drawForm()
    local w, h = X.size()
    local e = st.edit
    local dp = X.depotOf(e.key)
    local r = e.rule
    X.titleBar(e.isNew and (" ADD " .. dp.title) or (" " .. dp.title .. " RULE"), e.isNew and "step 2 of 3 " or nil)
    X.line2("What goes in " .. cut(nameOf(e.name), w - 32) .. "? Set any of these.")
    for i, f in ipairs(FIELDS) do
      local y, key = 3 + i, f[1]
      put(2, y, f[2], C.dim)
      local txt = r[key] and joined(r[key], w - 14) or "any"
      put(13, y, txt .. (" "):rep(w - 13 - #txt), r[key] and C.fg or C.dim, C.bar)
      region(13, w, y, function() st.rfield, st.page, st.filter, st.pg = key, "rpick", "", 1 end)
    end
    put(2, 7, "Enchanted", C.dim)
    local x = 13
    for _, v in ipairs({ { "Any", nil }, { "Yes", true }, { "No", false } }) do
      local val = v[2]
      x = btn(x, 7, v[1], r.enchanted == val, function() r.enchanted = val end)
    end
    local has = M.hasRule(r)
    if has then
      local res = R.preview(r, e.name)
      put(2, 9, cut(("Matches now: %d kinds, %s items"):format(res.kinds, fmt(res.items)), w - 2), C.fg)
      previewRows(10, res, math.max(1, math.min(5, h - 17)), w)
    else
      put(2, 9, "Set at least one of these to see what it takes.", C.dim)
    end
    local bx = 2
    if has then
      bx = btn(bx, h - 1, "Next", true, function() st.page = "edit" end, colours.lime)
    else
      put(bx, h - 1, " Next ", C.dim, C.bar); bx = bx + 7
    end
    bx = btn(bx, h - 1, "Something like this", false, function() M.watch() end)
    btn(bx, h - 1, "Back", false, M.back)
  end

  -- The Item / Tag / Mod pick list
  function M.drawPick()
    local w, h = X.size()
    local e = st.edit
    local f = st.rfield
    local dp = X.depotOf(e.key)
    local title = f == "item" and "ITEM" or f == "tag" and "TAG" or "MOD"
    local rows_ = e.rule[f] or {}
    X.titleBar(" DEPOT " .. title, (#rows_ > 0 and ("%d ticked "):format(#rows_) or "tap to tick "))
    local q = st.filter:lower()
    local shown = {}
    local function add(label, right, value)
      if q == "" or label:lower():find(q, 1, true) then
        shown[#shown + 1] = { label = label, right = right, value = value, pick = function()
          local l = e.rule[f] or {}
          if ticked(l, value) then
            for i, x in ipairs(l) do if x == value then table.remove(l, i); break end end
          else
            l[#l + 1] = value
          end
          e.rule[f] = #l > 0 and l or nil
        end }
      end
    end
    if f == "item" then
      for _, it in ipairs(dp.items(e.name)) do add(it.label or X.prettyName(it.name), fmt(it.count or 0), it.name) end
    elseif f == "tag" then
      for _, t in ipairs(R.tags()) do add(t.tag, ("%d kinds  %s"):format(t.kinds, fmt(t.items)), t.tag) end
    else
      for _, m in ipairs(R.mods()) do add(m.mod, ("%d kinds  %s"):format(m.kinds, fmt(m.items)), m.mod) end
    end
    st.shown = shown
    if #shown == 1 and st.filter ~= "" then X.line2("Enter (or click) ticks " .. shown[1].label, C.good)
    elseif f == "item" then X.line2("Items in storage, variants merged. Type to narrow it down.")
    else X.line2(title:sub(1, 1) .. title:sub(2):lower() .. "s on items in storage. Type to narrow it down.") end
    local top, rows = 3, math.max(1, h - 4)
    X.pager(h - 1, #shown, rows)
    if #shown == 0 then put(2, top, "Nothing matches.", C.dim) end
    for i = 1, rows do
      local it = shown[(st.pg - 1) * rows + i]
      if not it then break end
      local y = top + i - 1
      local only = #shown == 1 and st.filter ~= ""
      local on = ticked(e.rule[f], it.value)
      local bg = (on or only) and C.accent or (i % 2 == 0 and C.stripe or C.bg)
      local dark = on or only
      term.setCursorPos(1, y); term.setBackgroundColour(bg); term.clearLine()
      put(2, y, cut(it.label, w - #it.right - 3), dark and colours.black or C.fg, bg)
      put(w - #it.right, y, it.right, dark and colours.black or C.dim, bg)
      region(1, w, y, it.pick)
    end
    local x = btn(2, h - 1, "Done", true, function() st.page, st.filter, st.pg = "rule", "", 1 end, colours.lime)
    x = btn(x, h - 1, "Any", e.rule[f] == nil, function()
      e.rule[f] = nil; st.page, st.filter, st.pg = "rule", "", 1
    end)
    X.searchBar()
  end

  -- Drop one item into the depot and read what is true about it
  function M.watch()
    local e = st.edit
    local before = {}
    for s, it in pairs(X.call(e.name, "list") or {}) do before[s] = it end
    local n = X.findByItem()
    if n ~= e.name then
      X.say(n and "Drop it into the depot itself." or "Didn't see an item go in. Try again?", C.warn)
      return
    end
    local slot
    for s, it in pairs(X.call(n, "list") or {}) do
      local b = before[s]
      if not b or b.name ~= it.name or it.count > b.count then slot = s end
    end
    local d = slot and X.call(n, "getItemDetail", slot)
    if not d then X.say("Couldn't read that item.", C.warn); return end
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
    st.page, st.filter, st.pg = "rlike", "", 1
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
    local w, h = X.size()
    local e, l = st.edit, st.like
    X.titleBar(" SOMETHING LIKE THIS")
    put(2, 2, cut("Example: " .. l.label, w - 2), C.fg)
    put(2, 3, "Tick what counts. Those lines fill in the form.", C.dim)
    local y = 5
    local function row(label, value, count, ticked, toggle)
      btn(2, y, ticked and "x" or " ", ticked, toggle)
      put(7, y, cut(label, 14), C.fg)
      local c = fmt(count)
      put(22, y, cut(value, w - 24 - #c), C.fg)
      put(w - #c, y, c, C.dim)
      y = y + 1
    end
    row("This item", l.label, R.count({ item = l.name }).items, l.ticks.item, function() l.ticks.item = not l.ticks.item or nil end)
    row("Enchanted", l.enchanted and "yes" or "no", R.count({ enchanted = l.enchanted }).items, l.ticks.enchanted,
      function() l.ticks.enchanted = not l.ticks.enchanted or nil end)
    for i = 1, math.min(#l.tags, math.max(1, math.min(5, h - 15))) do
      local t = l.tags[i]
      row("Tag", t.tag, t.items, l.ticks.tags[t.tag], function()
        l.ticks.tags[t.tag] = not l.ticks.tags[t.tag] or nil
      end)
    end
    row("Mod", l.mod, R.count({ mod = l.mod }).items, l.ticks.mod, function() l.ticks.mod = not l.ticks.mod or nil end)
    put(2, y + 1, cut("Several tags can be ticked: any one of them matches.", w - 2), C.dim)
    local r = likeRule()
    if M.hasRule(r) then
      local res = R.preview(r, e.name)
      put(2, y + 3, cut(("Matches now: %d kinds, %s items"):format(res.kinds, fmt(res.items)), w - 2), C.fg)
    else
      put(2, y + 3, "Tick at least one line.", C.dim)
    end
    local x = 2
    if M.hasRule(r) then
      x = btn(x, h - 1, "Use these", true, function()
        e.rule = likeRule(); st.page = "rule"
      end, colours.lime)
    else
      put(x, h - 1, " Use these ", C.dim, C.bar); x = x + 12
    end
    x = btn(x, h - 1, "Other example", false, function() M.watch() end)
    btn(x, h - 1, "Back", false, function() st.page = "rule" end)
  end

  -- Enter on the pick list picks the only match
  function M.enter()
    if st.page == "rpick" and st.shown and #st.shown == 1 and st.filter ~= "" then
      st.shown[1].pick()
      return true
    end
    if st.page == "rule" and M.hasRule(st.edit.rule) then st.page = "edit"; return true end
    return false
  end

  -- Holds / Priority / Matches / Overlaps on the edit page. Returns the next free row.
  function M.editRows(e, y)
    local w, h = X.size()
    local r = e.rule
    if not M.hasRule(r) then
      local x = btn(2, y, "Set rule", false, M.open)
      put(x, y, "What should it hold?", C.warn)
      return y + 1
    end
    put(2, y, "Holds", C.dim)
    local holds = cut(R.describe(r), w - 12)
    put(12, y, holds .. (" "):rep(w - 12 - #holds), C.fg, C.bar)
    region(12, w, y, M.open)
    y = y + 1
    if y >= h - 1 then return y end
    put(2, y, "Priority", C.dim)
    local p = e.prio or ""
    local shownP = e.focus == "prio" and p or (p == "" and "0" or p)
    put(12, y, shownP .. (" "):rep(6 - #shownP), e.focus == "prio" and colours.black or C.fg, e.focus == "prio" and colours.white or C.bar)
    put(19, y, cut("higher wins a tie, 0 to 9999", w - 19), C.dim)
    region(12, 17, y, function() e.focus = "prio" end)
    e.prioY = y
    y = y + 1
    if y >= h - 1 then return y end
    local res = R.preview(r, e.name)
    put(2, y, cut(("Matches   %d kinds, %s items in storage now"):format(res.kinds, fmt(res.items)), w - 2), C.fg)
    y = y + 1
    local lost = {}
    for n, kinds in pairs(res.lost) do lost[#lost + 1] = { n = n, kinds = kinds } end
    table.sort(lost, function(a, b) return a.n < b.n end)
    for i = 1, math.min(2, #lost) do
      if y >= h - 1 then break end
      local last = i == 2 and #lost > 2
      local text = ("%s wins %d %s%s"):format(nameOf(lost[i].n), lost[i].kinds, lost[i].kinds == 1 and "kind" or "kinds",
        last and (" (+%d more depots)"):format(#lost - 2) or "")
      put(2, y, "Overlaps", C.dim); put(12, y, cut(text, w - 12), C.warn)
      y = y + 1
    end
    return y
  end

  return M
end
