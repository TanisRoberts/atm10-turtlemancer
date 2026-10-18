-- assignui.lua  --  the "/assign" screen, shared by storage and the Nether Foreman. Loaded with dofile().
--
-- Which inventory on the wired cable does what. List -> click one to edit (job, nickname, delete);
-- + Add -> pick by network name (typing narrows the list down) or by dropping one item in.
-- Everything that isn't on the list is left to the program (storage: it's storage).
--
-- The program hands over its jobs and data with A.run(o):
--   o.title         "ASSIGNED STORAGE"
--   o.types         { { key, label, short, tag, col, about }, ... } (3 per row on the edit page)
--   o.typeOf(n)     -> job key or nil          o.assign(n, key) -> the inventory it bumped (single jobs)
--   o.unassign(n)   o.names = { [network name] = nickname } (edited in place)
--   o.inventories() -> every inventory name    o.candidate(n) -> may be offered under + Add
--   o.auto(n)       -> job key for an unassigned inventory the program treats as having a job anyway
--                      (storage: drawers found by name). Listed with "(by name)", can't be deleted.
--   o.single[key]   -> the inventory holding a one-only job (for the "Replaces X" warning)
--   o.defaultKey(n) -> the job a new pick starts on
--   o.warn(e, d)    -> optional extra warning line (e = edit state, d = { text, count, missing })
--   o.problem()     -> optional warning for the list page ("No OUTPUT yet ...")
--   o.extra         -> optional extra setting for one job: { key, init(n) -> state,
--                      show(state) -> label, text,  click(n, state, plain) [plain = a cleared
--                      screen for typed input is ready],  plain = true/false,  save(n, state) }
--   o.depots        -> optional "keep this container filled with one thing" jobs, a list of
--                      { key, kind = "Depot", title = "DEPOT", about, what = "item",
--                        tank = true/false (its containers are tanks, not inventories),
--                        items(n) -> { { name, label, count }, ... } offered under "pick the item",
--                        get(n) -> id or nil,  set(n, id) }. With them, + Add asks which kind (or
--                      "Other job") first, and a depot goes container -> item -> summary.
--   o.describe(n)   -> optional { text, count, size } for a container that has no item list (a tank)
--   o.hold()/o.release()  pause / resume the program's own moving while "Find it" watches
--   o.beforeSave()  wait until the program's worker is idle;  o.afterSave()  save + rescan
--   o.itemTotals()  -> { [inventory] = item count }
--   o.call(n, method, ...)   peripheral.call wrapped in pcall
--   o.emptyText     shown when nothing is assigned

local A = {}

local C = {
  bg = colours.black, bar = colours.grey, fg = colours.white, dim = colours.lightGrey,
  accent = colours.cyan, stripe = colours.grey, warn = colours.orange, good = colours.lime,
}
A.C = C

local function fmt(n)
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e4 then return ("%dk"):format(math.floor(n / 1e3)) end
  return tostring(n)
end
local function prettyName(id)
  local s = id:gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end
local function shortName(n) return (n:gsub("^minecraft:", "")) end
local function cut(text, n)
  if n <= 0 then return "" end
  if #text <= n then return text end
  if n <= 2 then return text:sub(1, n) end
  return text:sub(1, n - 2) .. ".."
end
-- Network names keep their end (the number is what tells barrels apart): "..storage_controller_0"
local function cutName(n, width)
  local text = shortName(n)
  if #text <= width then return text end
  return ".." .. text:sub(-(width - 2))
end
A.shortName, A.cut, A.prettyName, A.fmt = shortName, cut, prettyName, fmt

local function runBatched(fns, size)
  size = size or 32
  for i = 1, #fns, size do
    parallel.waitForAll(table.unpack(fns, i, math.min(i + size - 1, #fns)))
  end
end

function A.run(o)
  local w, h = term.getSize()
  local st = { page = "list", filter = "", pg = 1 }
  local hits, desc = {}, {}
  local TYPE_BY = {}
  for _, t in ipairs(o.types) do TYPE_BY[t.key] = t end
  local call = o.call
  local names = o.names
  local DEPOT_BY, hasDepots = {}, false
  for _, d in ipairs(o.depots or {}) do DEPOT_BY[d.key] = d; hasDepots = true end
  local function isTank(n)
    for _, d in pairs(DEPOT_BY) do if d.tank and d.owns and d.owns(n) then return true end end
    return false
  end
  local function typesFor(n)   -- a tank can only be a fluid depot, and nothing else can
    local out = {}
    local tank = isTank(n)
    for _, t in ipairs(o.types) do
      local d = DEPOT_BY[t.key]
      if (d and d.tank or false) == tank or (not d and not tank) then out[#out + 1] = t end
    end
    return out
  end
  local function curDepot() return DEPOT_BY[st.itemBack == "edit" and st.edit and st.edit.key or st.depotFlow] end

  -- What's in each inventory, for the lists (cached while the screen is open)
  local function describe(list)
    local fns = {}
    for _, n in ipairs(list) do
      if not desc[n] then
        fns[#fns + 1] = function()
          local custom = o.describe and peripheral.isPresent(n) and o.describe(n)
          if custom then desc[n] = custom; return end
          local items = peripheral.isPresent(n) and call(n, "list")
          if not items then desc[n] = { missing = true, text = "not on the cable", count = 0 }; return end
          local size = call(n, "size") or 0
          local totals, kinds, count, top = {}, 0, 0, nil
          for _, it in pairs(items) do
            if not totals[it.name] then kinds = kinds + 1; totals[it.name] = 0 end
            totals[it.name] = totals[it.name] + it.count
            count = count + it.count
          end
          for name, c in pairs(totals) do if not top or c > totals[top] then top = name end end
          desc[n] = { count = count, size = size, text = top
            and (fmt(totals[top]) .. " " .. prettyName(top) .. (kinds > 1 and (" +" .. (kinds - 1) .. " more") or ""))
            or ("empty, " .. size .. " slots") }
        end
      end
    end
    runBatched(fns)
  end

  -- Every inventory with a job, in job order (assigned ones, then ones the program treats as such)
  local function assigned()
    local all = o.inventories()
    local byKey = {}
    for _, n in ipairs(all) do
      local key, auto = o.typeOf(n), false
      if not key and o.auto then key = o.auto(n); auto = key ~= nil end
      if key then byKey[key] = byKey[key] or {}; table.insert(byKey[key], { name = n, key = key, auto = auto }) end
    end
    -- Assigned but not on the cable right now: still listed (shown as missing)
    for _, n in ipairs(o.assignedNames()) do
      if not peripheral.isPresent(n) then
        local key = o.typeOf(n)
        if key then byKey[key] = byKey[key] or {}; table.insert(byKey[key], { name = n, key = key }) end
      end
    end
    local out = {}
    for _, t in ipairs(o.types) do
      local list = byKey[t.key] or {}
      table.sort(list, function(a, b)
        if a.auto ~= b.auto then return not a.auto end
        return a.name < b.name
      end)
      for _, r in ipairs(list) do out[#out + 1] = r end
    end
    return out
  end

  local function unassigned()
    local out = {}
    for _, n in ipairs(o.inventories()) do
      if not o.typeOf(n) and o.candidate(n) and (not hasDepots or isTank(n) == (st.depotFlow and DEPOT_BY[st.depotFlow].tank or false)) then
        out[#out + 1] = n
      end
    end
    return out
  end

  local function matches(n)
    if st.filter == "" then return true end
    local q, d = st.filter:lower(), desc[n]
    return n:lower():find(q, 1, true) ~= nil or (names[n] or ""):lower():find(q, 1, true) ~= nil
      or (d ~= nil and d.text:lower():find(q, 1, true) ~= nil)
  end

  -- Drawing
  local function put(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    term.setBackgroundColour(bg or C.bg)
    term.setTextColour(fg or C.fg)
    term.write(text)
  end
  local function btn(x, y, label, active, fn, colour)
    put(x, y, " " .. label .. " ", active and colours.black or C.fg, active and (colour or C.accent) or C.bar)
    hits[#hits + 1] = { x1 = x, x2 = x + #label + 1, y = y, fn = fn }
    return x + #label + 3
  end
  local function region(x1, x2, y, fn) hits[#hits + 1] = { x1 = x1, x2 = x2, y = y, fn = fn } end
  local function titleBar(left, right)
    term.setCursorPos(1, 1); term.setBackgroundColour(C.bar); term.clearLine()
    put(1, 1, left, C.accent, C.bar)
    if right then put(math.max(#left + 2, w - #right + 1), 1, right, C.dim, C.bar) end
  end
  local function say(msg, col) st.note, st.noteCol, st.noteUntil = msg, col or C.good, os.clock() + 5 end
  local function line2(default, col)
    if st.note and os.clock() < st.noteUntil then put(2, 2, cut(st.note, w - 2), st.noteCol)
    else put(2, 2, cut(default, w - 2), col or C.dim) end
  end
  local function searchBar()
    term.setCursorPos(1, h); term.setBackgroundColour(C.bar); term.clearLine()
    put(1, h, " Search: ", C.dim, C.bar)
    local room = w - 13
    local shownText = #st.filter > room and st.filter:sub(-room) or st.filter
    put(10, h, shownText, C.fg, C.bar)
    if st.filter ~= "" then
      put(w - 2, h, " x ", C.dim, C.bar)
      region(w - 2, w, h, function() st.filter, st.pg = "", 1 end)
    end
    term.setCursorPos(10 + #shownText, h); term.setTextColour(C.fg); term.setCursorBlink(true)
  end
  local function pager(y, total, rows)
    local pages = math.max(1, math.ceil(total / rows))
    st.pg = math.min(math.max(st.pg, 1), pages)
    if pages > 1 then
      local label = ("%d/%d"):format(st.pg, pages)
      local px = w - #label - 11
      btn(px, y, "<", st.pg > 1, function() st.pg = st.pg - 1 end)
      put(px + 4, y, label, C.dim)
      btn(w - 4, y, ">", st.pg < pages, function() st.pg = st.pg + 1 end)
    end
  end

  local function openEdit(n, isNew)
    desc[n] = nil   -- fresh look at what's in it (an item may just have been dropped in)
    describe({ n })
    local key = o.typeOf(n)
    local autoKey = not key and o.auto and o.auto(n) or nil
    st.edit = { name = n, orig = key, auto = autoKey ~= nil, autoKey = autoKey, nick = names[n] or "", isNew = isNew,
      key = key or autoKey or o.defaultKey(n) }
    if o.extra then st.edit.extra = o.extra.init(n) end
    if DEPOT_BY[key] then st.edit.depot = DEPOT_BY[key].get(n) end
    st.page, st.note = "edit", nil
  end

  -- Wait for one inventory to gain exactly one item (the one you drop in). The program holds off
  -- its own moving meanwhile.
  local function findByItem()
    o.hold()
    local function screen(lines, col)
      term.setCursorBlink(false)
      term.setBackgroundColour(C.bg); term.clear()
      titleBar(" " .. o.title, "find it ")
      for i, l in ipairs(lines) do put(2, 2 + i, cut(l, w - 2), i == 1 and (col or C.fg) or C.dim) end
      put(2, h, "Backspace or click: cancel", C.dim)
    end
    local before, found, gone = o.itemTotals(), nil, os.clock() + 60
    local note = nil
    while os.clock() < gone and not found do
      screen({ note or "Drop ONE item into the barrel you mean.",
        "Nothing gets moved while I watch every inventory.",
        ("Waiting... %ds"):format(math.ceil(gone - os.clock())) }, note and C.warn or C.fg)
      local t, cancel = os.startTimer(1), false
      while true do
        local e, a = os.pullEvent()
        if e == "timer" and a == t then break end
        if (e == "key" and a == keys.backspace) or e == "mouse_click" then cancel = true; break end
      end
      if cancel then break end
      local after = o.itemTotals()
      local one = {}
      for n, c in pairs(after) do if c - (before[n] or 0) == 1 then one[#one + 1] = n end end
      if #one == 1 then found = one[1]
      elseif #one > 1 then note = "Two gained one item. Try again, just one."; before = after
      else before = after end   -- a hopper filling something else doesn't count
    end
    o.release()
    return found
  end

  local function backToList(msg, col)
    if msg then say(msg, col) end
    desc = {}
    st.page, st.edit, st.filter, st.pg = "list", nil, "", 1
  end

  local function save()
    local e = st.edit
    local dp = DEPOT_BY[e.key]
    if dp and not e.depot then
      st.itemBack, st.depotName, st.filter, st.pg, st.page = "edit", e.name, "", 1, "item"
      return
    end
    o.beforeSave()
    local bumped
    if e.key ~= e.orig then bumped = o.assign(e.name, e.key) end
    if bumped == e.name then bumped = nil end
    if o.extra and e.key == o.extra.key then o.extra.save(e.name, e.extra) end
    if dp then dp.set(e.name, e.depot) end
    names[e.name] = e.nick ~= "" and e.nick or nil
    o.afterSave()
    backToList(("Saved: %s = %s%s"):format(shortName(e.name), TYPE_BY[e.key].label,
      bumped and (" (" .. shortName(bumped) .. " freed)") or "."))
  end

  local function delete()
    local e = st.edit
    o.beforeSave()
    o.unassign(e.name)
    names[e.name] = nil
    o.afterSave()
    backToList(shortName(e.name) .. " has no job now.", C.warn)
  end

  -- Pages
  local function drawList()
    local all = assigned()
    local list = {}
    for _, r in ipairs(all) do list[#list + 1] = r.name end
    describe(list)
    local shown = {}
    for _, r in ipairs(all) do if matches(r.name) then shown[#shown + 1] = r end end
    st.shown = shown
    titleBar(" " .. o.title, ("%d set "):format(#all))
    local problem = o.problem and o.problem()
    if problem and not (st.note and os.clock() < st.noteUntil) then line2(problem, C.warn)
    else line2(#shown == 1 and st.filter ~= "" and "Enter edits it." or (o.hint or "Click one to change it.")) end
    local nw = math.max(10, math.floor((w - 10) / 2))
    put(2, 3, "Job", C.dim); put(10, 3, "Network name", C.dim); put(11 + nw, 3, "Nickname / in it", C.dim)
    local top, rows = 4, math.max(1, h - 5)
    pager(h - 1, #shown, rows)
    if #shown == 0 then
      put(2, top, cut(#all == 0 and (o.emptyText or "Nothing assigned yet. + Add") or "Nothing matches.", w - 2), C.dim)
    end
    for i = 1, rows do
      local r = shown[(st.pg - 1) * rows + i]
      if not r then break end
      local y, t, d = top + i - 1, TYPE_BY[r.key], desc[r.name] or { text = "" }
      local bg = i % 2 == 0 and C.stripe or C.bg
      term.setCursorPos(1, y); term.setBackgroundColour(bg); term.clearLine()
      put(2, y, t.tag, t.col, bg)
      put(10, y, cutName(r.name, nw), C.fg, bg)
      local info, col = d.text, C.dim
      if d.missing then info, col = "missing", C.warn
      elseif names[r.name] then info, col = names[r.name], C.fg
      elseif r.auto then info = "(by name) " .. info end
      put(11 + nw, y, cut(info, w - 11 - nw), col, bg)
      local name = r.name
      region(1, w, y, function() openEdit(name, false) end)
    end
    local x = btn(2, h - 1, "+ Add", true, function()
      st.page, st.filter, st.pg, st.note, st.depotFlow = hasDepots and "kind" or "pick", "", 1, nil, false
    end)
    btn(x, h - 1, "Done", false, function() st.done = true end)
    searchBar()
  end

  -- A container was picked under + Add: a depot goes on to pick its item, anything else to the job page
  local function chosen(n)
    if st.depotFlow then
      st.depotName, st.itemBack, st.filter, st.pg, st.page = n, "pick", "", 1, "item"
    else
      openEdit(n, true)
    end
  end

  local function drawKind()
    titleBar(" ADD", "what kind? ")
    line2("A depot keeps a container filled with one thing.")
    local y = 4
    for _, d in ipairs(o.depots) do
      put(2, y, d.kind, C.fg); put(16, y, cut(d.about, w - 16), C.dim)
      local key = d.key
      btn(2, y + 1, d.kind, true, function() st.depotFlow, st.page, st.filter, st.pg = key, "pick", "", 1 end, colours.lightBlue)
      y = y + 3
    end
    put(2, y, "Other", C.fg); put(16, y, "input, output, dock, fuel, drawers...", C.dim)
    btn(2, y + 1, "Other job", false, function() st.depotFlow, st.page, st.filter, st.pg = false, "pick", "", 1 end)
    btn(2, h - 1, "Back", false, function() st.page = "list" end)
  end

  local function drawItem()
    local dp = curDepot()
    local cands = dp.items(st.depotName)
    local shown = {}
    local q = st.filter:lower()
    for _, it in ipairs(cands) do
      if q == "" or it.name:lower():find(q, 1, true) or (it.label or ""):lower():find(q, 1, true) then
        shown[#shown + 1] = it
      end
    end
    st.shown = shown
    local flow = st.itemBack == "pick"
    titleBar(flow and (" ADD " .. dp.title) or (" " .. dp.title .. " " .. dp.what:upper()), flow and "step 2 of 3 " or nil)
    if #shown == 1 and st.filter ~= "" then line2("Enter (or click) picks " .. (shown[1].label or prettyName(shown[1].name)), C.good)
    else line2("Which " .. dp.what .. " should " .. cut(shortName(st.depotName), w - 32) .. " hold? Type to narrow it down.") end
    local top, rows = 3, math.max(1, h - 4)
    pager(h - 1, #shown, rows)
    if #shown == 0 then put(2, top, cut("Nothing matches. None of that " .. dp.what .. " is around.", w - 2), C.dim) end
    for i = 1, rows do
      local it = shown[(st.pg - 1) * rows + i]
      if not it then break end
      local y = top + i - 1
      local only = #shown == 1 and st.filter ~= ""
      local bg = only and C.accent or (i % 2 == 0 and C.stripe or C.bg)
      term.setCursorPos(1, y); term.setBackgroundColour(bg); term.clearLine()
      local label = it.label or prettyName(it.name)
      put(2, y, cut(label, w - 12), only and colours.black or C.fg, bg)
      local cnt = fmt(it.count or 0)
      put(w - #cnt, y, cnt, only and colours.black or C.dim, bg)
      region(1, w, y, function()
        if st.itemBack == "edit" and st.edit then
          st.edit.depot, st.page = it.name, "edit"
        else
          openEdit(st.depotName, true)
          st.edit.key, st.edit.depot, st.edit.flow = dp.key, it.name, true
        end
        st.filter, st.pg = "", 1
      end)
    end
    btn(2, h - 1, "Back", false, function()
      st.page, st.filter, st.pg = st.itemBack == "edit" and "edit" or "pick", "", 1
    end)
    searchBar()
  end

  local function drawPick()
    local cands = unassigned()
    describe(cands)
    local shown = {}
    for _, n in ipairs(cands) do if matches(n) then shown[#shown + 1] = n end end
    st.shown = shown
    titleBar(st.depotFlow and (" ADD " .. DEPOT_BY[st.depotFlow].title) or " ADD", st.depotFlow and "step 1 of 3 " or "step 1 of 2 ")
    if #shown == 1 and st.filter ~= "" then line2("Enter (or click) picks " .. shortName(shown[1]), C.good)
    else line2("Type part of its name to narrow it down, or:") end
    btn(2, 3, "Find it: drop one item in", false, function()
      local n = findByItem()
      if not n then say("Didn't see an item go in. Try again?", C.warn)
      elseif o.typeOf(n) then st.depotFlow = false; openEdit(n, false); say("That one has a job already: here it is.", C.warn)
      else chosen(n) end
    end)
    local top, rows = 4, math.max(1, h - 5)
    pager(h - 1, #shown, rows)
    if #shown == 0 then
      put(2, top, cut(#cands == 0 and "Every inventory on the cable has a job already." or "Nothing without a job matches.", w - 2), C.dim)
    end
    local nw = math.max(10, math.floor((w - 4) / 2))
    for i = 1, rows do
      local n = shown[(st.pg - 1) * rows + i]
      if not n then break end
      local y, d = top + i - 1, desc[n] or { text = "" }
      local only = #shown == 1 and st.filter ~= ""
      local bg = only and C.accent or (i % 2 == 0 and C.stripe or C.bg)
      term.setCursorPos(1, y); term.setBackgroundColour(bg); term.clearLine()
      put(2, y, cutName(n, nw), only and colours.black or C.fg, bg)
      put(3 + nw, y, cut(names[n] or d.text, w - 3 - nw), only and colours.black or C.dim, bg)
      region(1, w, y, function() chosen(n) end)
    end
    btn(2, h - 1, "Back", false, function()
      st.page, st.filter, st.pg = hasDepots and "kind" or "list", "", 1
    end)
    searchBar()
  end

  local function drawEdit()
    local e = st.edit
    local t = TYPE_BY[e.key]
    local d = desc[e.name] or { text = "?" }
    titleBar(e.isNew and (e.flow and (" ADD " .. DEPOT_BY[e.key].title) or " ADD") or " EDIT",
      e.isNew and (e.flow and "step 3 of 3 " or "step 2 of 2 ") or nil)
    line2(e.isNew and "Pick its job, then Save." or e.auto and "Found by its name. Give it a job, or Ignore it."
      or "Change its job or nickname, or Delete it.")
    put(2, 3, "Name", C.dim);     put(12, 3, cut(e.name, w - 12), C.fg)
    put(2, 4, "In it", C.dim);    put(12, 4, cut(d.text, w - 12), d.missing and C.warn or C.fg)
    put(2, 5, "Nickname", C.dim)
    local fw = w - 12
    local shownNick = #e.nick > fw - 1 and e.nick:sub(-(fw - 1)) or e.nick
    if e.focus then
      put(12, 5, shownNick .. (" "):rep(fw - #shownNick), colours.black, colours.white)
    else
      local txt = cut(e.nick ~= "" and e.nick or "click to name it (optional)", fw)
      put(12, 5, txt .. (" "):rep(fw - #txt), e.nick ~= "" and C.fg or C.dim, C.bar)
    end
    region(12, w, 5, function() e.focus = true end)
    put(2, 7, "Job", C.dim)
    local per = 3
    local bw = math.floor((w - 1) / per) - 1
    local types = typesFor(e.name)
    local ok = false
    for _, ty in ipairs(types) do if ty.key == e.key then ok = true end end
    if not ok then e.key = types[1].key end
    t = TYPE_BY[e.key]
    for i, ty in ipairs(types) do
      local col, row = (i - 1) % per, math.floor((i - 1) / per)
      local x, y = 2 + col * (bw + 1), 8 + row
      local label = #ty.label <= bw - 1 and ty.label or ty.short
      local sel = ty.key == e.key
      local pad = bw - #label
      put(x, y, cut((" "):rep(math.floor(pad / 2)) .. label .. (" "):rep(pad - math.floor(pad / 2)), bw),
        sel and colours.black or C.fg, sel and ty.col or C.bar)
      local key = ty.key
      region(x, x + bw - 1, y, function() e.key = key; e.delArm = false end)
    end
    local y = 8 + math.ceil(#types / per) + 1
    -- About the chosen job, wrapped over two lines
    local about, lines = t.about, {}
    while #about > 0 and #lines < 2 do
      local piece = about
      if #piece > w - 2 then
        local cutAt = piece:sub(1, w - 2):match("^.*() ") or (w - 2)
        piece = about:sub(1, cutAt - 1)
      end
      lines[#lines + 1] = piece
      about = about:sub(#piece + 1):gsub("^ +", "")
    end
    for i, l in ipairs(lines) do put(2, y + i - 1, l, t.col) end
    y = y + 2
    -- What saving this will do
    local warn
    local holder = o.single and o.single(e.key)
    if holder and holder ~= e.name then
      warn = ("Replaces %s; that one has no job then."):format(shortName(holder))
    elseif e.auto and e.key == e.autoKey then
      warn = "Already does this, found by its name."
    elseif o.warn then
      warn = o.warn(e, d)
    end
    if warn and y < h - 1 then put(2, y, cut(warn, w - 2), C.warn); y = y + 1 end
    if DEPOT_BY[e.key] and y < h - 1 then
      local dp = DEPOT_BY[e.key]
      local x = btn(2, y, e.depot and "Change" or ("Pick " .. dp.what), false, function()
        st.itemBack, st.depotName, st.filter, st.pg, st.page = "edit", e.name, "", 1, "item"
      end)
      put(x, y, cut(e.depot and ("Keeps " .. prettyName(e.depot)) or ("Which " .. dp.what .. " should it hold?"), w - x), e.depot and C.fg or C.warn)
      y = y + 1
    end
    if o.extra and e.key == o.extra.key and y < h - 1 then
      local label, text = o.extra.show(e.extra)
      local x = btn(2, y, label, false, function() e.extraClick = true end)
      put(x, y, cut(text or "", w - x), C.dim)
    end
    -- Buttons
    local x = btn(2, h - 1, "Save", true, save, colours.lime)
    x = btn(x, h - 1, "Cancel", false, function() st.page, st.edit = e.isNew and "pick" or "list", nil end)
    if e.orig then
      btn(x, h - 1, e.delArm and "Sure? Delete" or "Delete", e.delArm, function()
        if e.delArm then delete() else e.delArm = true end
      end, colours.red)
    end
    put(2, h, cut(e.focus and "Typing the nickname. Enter: done" or "Enter: save   Tab: nickname   Backspace: back", w - 2), C.dim)
    if e.focus then
      term.setCursorPos(12 + #shownNick, 5); term.setTextColour(colours.black); term.setCursorBlink(true)
    end
  end

  describe(unassigned())   -- one read of everything up front: searching by contents works straight away
  while not st.done do
    w, h = term.getSize()
    hits = {}
    term.setCursorBlink(false)
    term.setBackgroundColour(C.bg); term.setTextColour(C.fg); term.clear()
    if st.page == "list" then drawList() elseif st.page == "pick" then drawPick()
    elseif st.page == "kind" then drawKind() elseif st.page == "item" then drawItem() else drawEdit() end
    local redraw = false
    while not redraw do
      local ev, a, b, c = os.pullEvent()
      redraw = true
      local e = st.edit
      if ev == "mouse_click" then
        if e then e.focus = false end
        for _, r in ipairs(hits) do
          if c == r.y and b >= r.x1 and b <= r.x2 then r.fn(); break end
        end
      elseif ev == "mouse_scroll" then
        st.pg = st.pg + a
      elseif ev == "char" or ev == "paste" then
        local text = ev == "paste" and a:gsub("[\r\n]", "") or a
        if st.page == "edit" then
          if e.focus then e.nick = (e.nick .. text):sub(1, 24) else redraw = false end
        else
          st.filter, st.pg = st.filter .. text, 1
        end
      elseif ev == "key" then
        if a == keys.backspace then
          if st.page == "edit" then
            if e.focus then e.nick = e.nick:sub(1, -2)
            else st.page, st.edit = e.isNew and "pick" or "list", nil end
          elseif st.filter ~= "" then st.filter, st.pg = st.filter:sub(1, -2), 1
          elseif st.page == "item" then st.page = st.itemBack == "edit" and "edit" or "pick"
          elseif st.page == "pick" then st.page = hasDepots and "kind" or "list"
          elseif st.page == "kind" then st.page = "list" end
        elseif a == keys.delete and st.page ~= "edit" then
          st.filter, st.pg = "", 1
        elseif a == keys.enter or a == keys.numPadEnter then
          if st.page == "edit" then
            if e.focus then e.focus = false else save() end
          elseif st.page == "item" and st.shown and #st.shown == 1 and st.filter ~= "" then
            local it, dp = st.shown[1], curDepot()
            if st.itemBack == "edit" and st.edit then st.edit.depot, st.page = it.name, "edit"
            else
              openEdit(st.depotName, true)
              st.edit.key, st.edit.depot, st.edit.flow = dp.key, it.name, true
            end
            st.filter, st.pg = "", 1
          elseif st.shown and #st.shown == 1 and st.filter ~= "" and st.page ~= "kind" then
            local only = st.shown[1]
            local n = type(only) == "table" and only.name or only
            if st.page == "pick" then chosen(n) else openEdit(n, false) end
          else redraw = false end
        elseif a == keys.tab and st.page == "edit" then
          e.focus = not e.focus
        elseif a == keys.up or a == keys.pageUp then st.pg = st.pg - 1
        elseif a == keys.down or a == keys.pageDown then st.pg = st.pg + 1
        else redraw = false end
      elseif ev == "term_resize" then
        redraw = true
      else
        redraw = false
      end
      if st.edit and st.edit.extraClick then
        st.edit.extraClick = false
        if o.extra.plain then   -- a typed setting: plain screen for a moment
          term.setCursorBlink(false)
          term.setBackgroundColour(colours.black); term.setTextColour(colours.white)
          term.clear(); term.setCursorPos(1, 1)
        end
        o.extra.click(st.edit.name, st.edit.extra)
      end
    end
  end
  term.setCursorBlink(false)
end

return A
