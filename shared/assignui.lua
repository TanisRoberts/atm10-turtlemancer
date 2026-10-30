-- assignui.lua  --  the "/assign" screen, shared by storage and the Nether Foreman. Loaded with dofile().
-- Built only from the UI kit (shared/ui*.lua, docs/systems/ui.md); design: docs/design/storage.md.
--
-- Which inventory on the wired cable does what. List -> tap one to edit (job, nickname, delete);
-- + Add -> pick by network name (typing narrows the list down) or by dropping one item in.
-- Everything that isn't on the list is left to the program (storage: it's storage).
-- It runs its own kit loop on the computer's own screen and returns when Done/Back is pressed.
--
-- The program hands over its jobs and data with A.run(o):
--   o.title         "ASSIGNED STORAGE"
--   o.types         { { key, label, short, tag, col, about }, ... }  (col: a colour; shown as its kit role)
--   o.typeOf(n)     -> job key or nil          o.assign(n, key) -> the inventory it bumped (single jobs)
--   o.unassign(n)   o.names = { [network name] = nickname } (edited in place)
--   o.inventories() -> every inventory name    o.candidate(n) -> may be offered under + Add
--   o.auto(n)       -> job key for an unassigned inventory the program treats as having a job anyway
--                      (storage: drawers found by name). Listed with "(by name)", can't be deleted.
--   o.single(key)   -> the inventory holding a one-only job (for the "Replaces X" warning)
--   o.defaultKey(n) -> the job a new pick starts on
--   o.warn(e, d)    -> optional extra warning line (e = edit state, d = { text, count, missing })
--   o.problem()     -> optional warning for the list page ("No OUTPUT yet ...")
--   o.extra         -> optional extra setting for one job: { key, init(n) -> state, show(state) -> label, text,
--                      click(n, state) [on a cleared plain screen when plain = true, for typed input],
--                      plain = true/false, save(n, state) }
--   o.depots        -> optional "keep this container filled with one thing" jobs, a list of
--                      { key, kind = "Depot", title = "DEPOT", about, what = "item",
--                        tank = true/false (its containers are tanks, not inventories),
--                        items(n) -> { { name, label, count }, ... } offered under "pick the item",
--                        get(n) -> id or nil,  set(n, id) }. With them, + Add asks which kind (or "Other job")
--                      first, and a depot goes container -> item -> summary.
--   o.rules         -> storage's depot rules engine (storage_rules.lua) for the rule pages (assignrules.lua).
--                      A depot with `rule = true` holds a rule instead of one item: getRule(n), setRule(n, rule, priority).
--   o.describe(n)   -> optional { text, count, size } for a container that has no item list (a tank)
--   o.hold()/o.release()  pause / resume the program's own moving while "Find it" watches
--   o.beforeSave()  wait until the program's worker is idle;  o.afterSave()  save + rescan
--   o.itemTotals()  -> { [inventory] = item count }
--   o.call(n, method, ...)   peripheral.call wrapped in pcall
--   o.emptyText     shown when nothing is assigned
--   o.view          optional kit view of the computer's screen to draw on (the caller keeps it afterwards);
--                   without it a view is made and its palette put back at the end.

local ui = require("ui")
local fit = ui.text.fit

local A = {}

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
-- Network names keep their end (the number is what tells barrels apart): "..storage_controller_0"
local function cutName(n, width)
  local text = shortName(n)
  if #text <= width then return text end
  if width <= 2 then return text:sub(-width) end
  return ".." .. text:sub(-(width - 2))
end
A.shortName, A.cut, A.prettyName, A.fmt = shortName, fit, prettyName, fmt

local ROLE = { [colours.lime] = "good", [colours.orange] = "warn", [colours.cyan] = "info", [colours.red] = "bad",
  [colours.yellow] = "gold", [colours.lightBlue] = "idle", [colours.blue] = "water", [colours.purple] = "busy",
  [colours.magenta] = "mark", [colours.pink] = "soft", [colours.brown] = "soil", [colours.green] = "good2",
  [colours.white] = "fg", [colours.lightGrey] = "dim", [colours.grey] = "bar" }

local function runBatched(fns, size)
  size = size or 32
  for i = 1, #fns, size do
    parallel.waitForAll(table.unpack(fns, i, math.min(i + size - 1, #fns)))
  end
end

local WATCH_S = 30

-- Button row on the footer line, beside Back (and the pager): `list` is a v:buttons list. When it does not fit one
-- row the buttons go on the rows above and the content gets less room. `o`: back (a Back pill is drawn), pager (leave
-- room for it), input (rows used by a search bar under the content). Returns { bottom = last content row, draw = fn }
-- (call draw after v:footer).
local function plan(v, list, o)
  o = o or {}
  local inp = o.input or 0
  local base = v.H - 1 - inp
  local x0 = o.back and ((v.wc == "regular" or v.wc == "wide") and 10 or 5) or 2
  local maxx = v.W - 1 - (o.pager and 12 or 0)
  local p = { bottom = base }
  if #list == 0 then p.draw = function() end; return p end
  local function width(b)
    local n = #v:_label(b)
    if b.confirm then n = math.max(n, #(b.label or ""), 5) end
    return n + (v.colour and 2 or 4)
  end
  local total = -1
  for _, b in ipairs(list) do total = total + width(b) + 1 end
  if x0 + total - 1 <= maxx then
    p.draw = function() v:buttons(x0, v.H, list, { maxx = maxx }) end
    return p
  end
  local rows, cx = 1, 2
  for _, b in ipairs(list) do
    local w = width(b)
    if cx > 2 and cx + w - 1 > v.W - 1 then rows = rows + 1; cx = 2 end
    cx = cx + w + 1
  end
  local top = v.H - 1 - inp - (rows - 1)
  p.bottom = top - 1
  p.draw = function() v:buttons(2, top, list) end
  return p
end
A.plan = plan

local function wrapText(text, w, maxLines)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  while maxLines and #out > maxLines do out[#out] = nil end
  return out
end

function A.run(o)
  local v = o.view or ui.view(term.current())
  local ownView = o.view == nil
  local st = { page = "list", f = ui.field{ hint = "search by name or contents", max = 40 } }
  local desc = {}
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
  local RU
  local function ruleDepot(key) local d = DEPOT_BY[key]; return RU and d and d.rule and d or nil end
  local function curDepot() return DEPOT_BY[st.itemBack == "edit" and st.edit and st.edit.key or st.depotFlow] end
  local say = function(text, tone) ui.say(text, tone or "good") end

  -- Show a page: a fresh search box, first page of the list, nothing selected or focused
  local function go(page)
    st.page = page
    st.f.text = ""
    v.page, v.sel, v.focus, v.armed = 1, nil, nil, nil
  end

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
    local q = st.f.text:lower()
    if q == "" then return true end
    local d = desc[n]
    return n:lower():find(q, 1, true) ~= nil or (names[n] or ""):lower():find(q, 1, true) ~= nil
      or (d ~= nil and d.text:lower():find(q, 1, true) ~= nil)
  end

  local function openEdit(n, isNew)
    desc[n] = nil   -- fresh look at what's in it (an item may just have been dropped in)
    describe({ n })
    local key = o.typeOf(n)
    local autoKey = not key and o.auto and o.auto(n) or nil
    st.edit = { name = n, orig = key, auto = autoKey ~= nil, autoKey = autoKey, nick = names[n] or "", isNew = isNew,
      key = key or autoKey or o.defaultKey(n) }
    st.edit.nickF = ui.field{ hint = "optional", max = 24, text = st.edit.nick }
    if o.extra then st.edit.extra = o.extra.init(n) end
    if ruleDepot(key) then
      local r = DEPOT_BY[key].getRule(n) or {}
      local function copy(l) return l and { table.unpack(l) } end
      st.edit.rule = { item = copy(r.item), tag = copy(r.tag), mod = copy(r.mod), enchanted = r.enchanted }
      st.edit.prioF = ui.field{ max = 4, text = tostring(r.priority or 0) }
    elseif DEPOT_BY[key] then st.edit.depot = DEPOT_BY[key].get(n) end
    go("edit")
  end

  ---------------------------------------------------------------------------
  -- "Find it": drop one item in. The program holds off its own moving meanwhile. kind "inv": one inventory
  -- gains exactly one item; "box": a slot of one container gains an item. done(result) gets the name / slot or nil.
  ---------------------------------------------------------------------------
  local function startWatch(w)
    o.hold()
    w.stop = os.clock() + WATCH_S
    w.next = os.clock() + 1
    if w.kind == "inv" then w.before = o.itemTotals()
    else
      w.before = {}
      for s, it in pairs(call(w.box, "list") or {}) do w.before[s] = it end
    end
    st.watch, st.watchBack = w, st.page
    go("watch")
  end
  local function endWatch(result)
    local w = st.watch
    st.watch = nil
    o.release()
    go(st.watchBack)
    w.done(result)
  end
  local function pollWatch()
    local w = st.watch
    if not w or os.clock() < w.next - 0.05 then return end
    w.next = os.clock() + 1
    local found
    if w.kind == "inv" then
      local after = o.itemTotals()
      local one = {}
      for n, c in pairs(after) do if c - (w.before[n] or 0) == 1 then one[#one + 1] = n end end
      if #one == 1 then found = one[1]
      elseif #one > 1 then w.note = "Two gained one item. Try again, just one."; w.before = after
      else w.before = after end   -- a hopper filling something else doesn't count
    else
      for s, it in pairs(call(w.box, "list") or {}) do
        local b = w.before[s]
        if not b or b.name ~= it.name or it.count > b.count then found = s end
      end
    end
    if found then endWatch(found)
    elseif os.clock() >= w.stop then endWatch(nil) end
  end

  local function drawWatch()
    local w = st.watch
    v:header(w.title or "FIND IT", { state = "watching", color = "busy" })
    local y = v:spinner_line(2, 4, w.note or w.line1)
    local t = wrapText(w.line2, v.W - 4)
    for i, l in ipairs(t) do v:put(4, y + i - 1, l, "dim", "bg") end
    y = y + #t
    v:put(4, y, ("%d s left."):format(math.max(0, math.ceil(w.stop - os.clock()))), "dim", "bg")
    v:footer({ back = function() endWatch(nil) end })
  end

  -- A container was picked under + Add: a depot goes on to pick its item, anything else to the job page
  local function chosen(n)
    if st.depotFlow and ruleDepot(st.depotFlow) then
      openEdit(n, true)
      st.edit.key, st.edit.flow, st.edit.rule = st.depotFlow, true, {}
      st.edit.prioF = ui.field{ max = 4, text = "0" }
      RU.open()
    elseif st.depotFlow then
      st.depotName, st.itemBack = n, "pick"
      go("item")
    else
      openEdit(n, true)
    end
  end

  RU = o.rules and dofile("assignrules.lua")({
    o = o, st = st, ui = ui, v = v, names = names, call = call, go = go, plan = plan, wrapText = wrapText,
    say = say, fmt = fmt, prettyName = prettyName, shortName = shortName,
    startWatch = startWatch, depotOf = function(key) return DEPOT_BY[key] end,
  })

  local function backToList(msg, tone)
    if msg then say(msg, tone) end
    desc = {}
    st.edit = nil
    go("list")
  end

  local function save()
    local e = st.edit
    local dp = DEPOT_BY[e.key]
    if ruleDepot(e.key) then
      if not RU.hasRule(e.rule) then RU.open(); return end
    elseif dp and not e.depot then
      st.itemBack, st.depotName = "edit", e.name
      go("item")
      return
    end
    o.beforeSave()
    e.nick = e.nickF.text
    local bumped
    if e.key ~= e.orig then bumped = o.assign(e.name, e.key) end
    if bumped == e.name then bumped = nil end
    if o.extra and e.key == o.extra.key then o.extra.save(e.name, e.extra) end
    if ruleDepot(e.key) then dp.setRule(e.name, e.rule, tonumber(e.prioF.text) or 0)
    elseif dp then dp.set(e.name, e.depot) end
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
    backToList(shortName(e.name) .. " has no job now.", "warn")
  end

  ---------------------------------------------------------------------------
  -- Pages
  ---------------------------------------------------------------------------
  local function search(hint)
    st.f.hint = hint
    v:search(st.f, { hint = hint })
  end

  -- Name, job and nickname columns for a list row at this width
  local function columns(W)
    if W >= 57 then return 20, 14 end
    if W >= 51 then return 14, 9 end
    if W >= 39 then return 12, 6 end
    return 11, 6
  end

  local function drawList()
    local all = assigned()
    local list = {}
    for _, r in ipairs(all) do list[#list + 1] = r.name end
    describe(list)
    local shown = {}
    for _, r in ipairs(all) do if matches(r.name) then shown[#shown + 1] = r end end
    v:header(o.title, { state = (#all == 1 and "1 inventory" or ("%d inventories"):format(#all)), color = "dim" })
    local W = v.W
    local nw, jw = columns(W)
    local problem = o.problem and o.problem()
    local top = 3
    if problem then v:alert(2, 3, W - 2, problem, "warn"); top = 4
    elseif v.H >= 14 then v:put(2, 3, fit(o.hint or "Tap one to change it. The rest is storage.", W - 2), "dim", "bg"); top = 4 end
    if v.H >= 14 then
      v:put(v.wc == "narrow" and 2 or 3, top, fit("Network name", nw), "dim", "bg")
      v:put((v.wc == "narrow" and 2 or 3) + nw + 1, top, "Job", "dim", "bg")
      if W >= 39 then v:put((v.wc == "narrow" and 2 or 3) + nw + 1 + jw + 1, top, "Nickname / in it", "dim", "bg") end
      top = top + 1
    end
    local rows = {}
    for _, r in ipairs(shown) do
      local t, d = TYPE_BY[r.key], desc[r.name] or { text = "", count = 0 }
      local info = d.text
      if d.missing then info = "missing"
      elseif names[r.name] then info = names[r.name]
      elseif r.auto then info = "(by name) " .. info end
      local job = #t.label <= jw and t.label or t.short
      local line = fit(cutName(r.name, nw), nw)
      line = line .. (" "):rep(nw - #line + 1) .. fit(job, jw)
      if W >= 39 then line = line .. (" "):rep(jw - #job + 1) .. info end
      rows[#rows + 1] = { name = line, value = d.missing and "-" or fmt(d.count or 0), state = ROLE[t.col] or "info",
        tone = d.missing and "warn" or "info", id = r.name }
    end
    if #shown == 0 then
      v:put(2, top, fit(#all == 0 and (o.emptyText or "Nothing assigned yet. + Add") or "Nothing matches.", W - 2), "dim", "bg")
    end
    local pl = plan(v, { { label = "+ Add", style = "primary", id = "add", fn = function()
      st.depotFlow = false
      go(hasDepots and "kind" or "pick")
    end } }, { back = true, pager = true, input = 1 })
    v:list(rows, { top = top, input = v.H - 1 - pl.bottom, once = true,
      on = function(row) openEdit(row.id, false) end })
    v:footer({ back = function() ui.quit() end })
    pl.draw()
    search("search by name or contents")
  end

  local function drawKind()
    v:header("ADD", { state = "what kind?", color = "dim" })
    v:put(2, 3, fit("A depot keeps a container filled with one thing.", v.W - 2), "dim", "bg")
    local rows = {}
    for _, d in ipairs(o.depots) do
      rows[#rows + 1] = { name = d.kind .. (v.W >= 39 and ("  " .. d.about) or ""), id = d.key, state = "idle" }
    end
    rows[#rows + 1] = { name = "Other job" .. (v.W >= 39 and "  input, output, dock, fuel, drawers..." or ""), id = false }
    v:list(rows, { top = 5, once = true, on = function(row)
      st.depotFlow = row.id
      go("pick")
    end })
    v:footer({ back = function() go("list") end })
  end

  local function drawPick()
    local cands = unassigned()
    describe(cands)
    local shown = {}
    for _, n in ipairs(cands) do if matches(n) then shown[#shown + 1] = n end end
    local dp = st.depotFlow and DEPOT_BY[st.depotFlow]
    v:header(dp and ("ADD " .. dp.title) or "ADD AN INVENTORY", { state = dp and "step 1 of 3" or "step 1 of 2", color = "dim" })
    v:put(2, 3, fit("Type part of its name to narrow it down, or drop one item in.", v.W - 2), "dim", "bg")
    local nw = math.max(10, math.floor((v.W - 6) / 2))
    local rows = {}
    for _, n in ipairs(shown) do
      local d = desc[n] or { text = "" }
      rows[#rows + 1] = { name = fit(cutName(n, nw), nw) .. (" "):rep(nw - #cutName(n, nw) + 1) .. (names[n] or d.text), id = n }
    end
    if #shown == 0 then
      local msg
      if #cands == 0 and dp and dp.diagnose then
        v:put(2, 5, fit("No " .. dp.what .. " containers found. What the cable shows:", v.W - 2), "warn", "bg")
        for i, l in ipairs(dp.diagnose()) do
          if 5 + i >= v.H - 3 then break end
          v:put(2, 5 + i, fit(l, v.W - 2), "dim", "bg")
        end
      else
        msg = #cands == 0 and "Every inventory on the cable has a job already." or "Nothing without a job matches."
        v:put(2, 5, fit(msg, v.W - 2), "dim", "bg")
      end
    end
    local pl = plan(v, { { label = "Find it: drop one item in", short = "Find it", id = "find", fn = function()
      startWatch({ kind = "inv", title = "ADD AN INVENTORY",
        line1 = "Find it: drop ONE item into the barrel you mean.",
        line2 = "Nothing gets moved while I watch every inventory.",
        done = function(n)
          if not n then say("Didn't see an item go in. Try again?", "warn")
          elseif o.typeOf(n) then st.depotFlow = false; openEdit(n, false); say("That one has a job already: here it is.", "warn")
          else chosen(n) end
        end })
    end } }, { back = true, pager = true, input = 1 })
    v:list(rows, { top = 5, input = v.H - 1 - pl.bottom, once = true, on = function(row) chosen(row.id) end })
    v:footer({ back = function() go(hasDepots and "kind" or "list") end })
    pl.draw()
    search("type part of its name")
  end

  local function drawItem()
    local dp = curDepot()
    local q = st.f.text:lower()
    local shown = {}
    for _, it in ipairs(dp.items(st.depotName)) do
      if q == "" or it.name:lower():find(q, 1, true) or (it.label or ""):lower():find(q, 1, true) then
        shown[#shown + 1] = it
      end
    end
    local flow = st.itemBack == "pick"
    v:header(flow and ("ADD " .. dp.title) or (dp.title .. " " .. dp.what:upper()), { state = flow and "step 2 of 3" or nil, color = "dim" })
    v:put(2, 3, fit("Which " .. dp.what .. " should " .. shortName(st.depotName) .. " hold? Type to narrow it down.", v.W - 2), "dim", "bg")
    local rows = {}
    for _, it in ipairs(shown) do rows[#rows + 1] = { name = it.label or prettyName(it.name), value = fmt(it.count or 0), id = it.name } end
    if #shown == 0 then v:put(2, 5, fit("Nothing matches. None of that " .. dp.what .. " is around.", v.W - 2), "dim", "bg") end
    v:list(rows, { top = 4, input = true, once = true, on = function(row)
      if st.itemBack == "edit" and st.edit then
        st.edit.depot = row.id
        go("edit")
      else
        openEdit(st.depotName, true)
        st.edit.key, st.edit.depot, st.edit.flow = dp.key, row.id, true
      end
    end })
    v:footer({ back = function() go(st.itemBack == "edit" and "edit" or "pick") end })
    search("type to narrow it down")
  end

  local function drawEdit()
    local e = st.edit
    local d = desc[e.name] or { text = "?" }
    v:header(e.isNew and (e.flow and ("ADD " .. DEPOT_BY[e.key].title) or "ADD") or ("EDIT: " .. shortName(e.name)),
      { state = e.isNew and (e.flow and "step 3 of 3" or "step 2 of 2") or nil, color = "dim" })
    local types = typesFor(e.name)
    local ok = false
    for _, ty in ipairs(types) do if ty.key == e.key then ok = true end end
    if not ok then e.key = types[1].key end
    local t = TYPE_BY[e.key]
    local W = v.W
    local acts = { { label = "Save", style = "primary", id = "save", fn = save } }
    if e.orig then
      acts[2] = { label = "Delete", id = "delete", confirm = true, style = "danger", fn = delete }
    end
    local toForm = e.isNew and ruleDepot(e.key) and RU.hasRule(e.rule)
    local pl = plan(v, acts, { back = true })
    local bottom = pl.bottom
    local y = 3
    local function line(text, tone)
      if y <= bottom then v:put(2, y, fit(text, W - 2), tone or "dim", "bg"); y = y + 1 end
    end
    line(e.isNew and "Pick its job, then Save." or e.auto and "Found by its name. Give it a job, or Ignore it."
      or "Change its job or nickname, or Delete it.")
    if v.H >= 16 then
      v:kv(2, y, W - 2, "Name", e.name); y = y + 1
      v:kv(2, y, W - 2, "In it", d.text, d.missing and "warn" or nil); y = y + 1
    end
    y = y + (v.H >= 16 and 1 or 0)
    local opts = {}
    for _, ty in ipairs(types) do opts[#opts + 1] = { id = ty.key, label = ty.label, short = ty.short } end
    local _, last = v:switch(2, y, opts, e.key, function(id) e.key = id end, { id = "job", maxx = W - 1 })
    y = last + 1
    if y <= bottom and not ruleDepot(e.key) and v.H >= 20 then
      for _, l in ipairs(wrapText(t.about, W - 2, 2)) do line(l, ROLE[t.col]) end
    end
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
    if warn and y <= bottom then v:alert(2, y, W - 2, warn, "warn"); y = y + 1 end
    if ruleDepot(e.key) and y <= bottom then
      e.rule = e.rule or {}
      e.prioF = e.prioF or ui.field{ max = 4, text = "0" }
      y = RU.editRows(e, y, bottom)
    elseif DEPOT_BY[e.key] and y <= bottom then
      local dp = DEPOT_BY[e.key]
      local x = v:buttons(2, y, { { label = e.depot and "Change" or ("Pick " .. dp.what), id = "pickitem", fn = function()
        st.itemBack, st.depotName = "edit", e.name
        go("item")
      end } })
      v:put(x + 1, y, fit(e.depot and ("Keeps " .. prettyName(e.depot)) or ("Which " .. dp.what .. " should it hold?"), W - x - 1),
        e.depot and "fg" or "warn", "bg")
      y = y + 1
    end
    if o.extra and e.key == o.extra.key and y <= bottom then
      local label, text = o.extra.show(e.extra)
      local x = v:buttons(2, y, { { label = label, id = "extra", fn = function() e.extraClick = true end } })
      v:put(x + 1, y, fit(text or "", W - x - 1), "dim", "bg")
      y = y + 1
    end
    if y + (v.H >= 16 and 1 or 0) <= bottom then
      if v.H >= 16 then y = y + 1 end
      v:field(2, y, "Nickname", math.max(8, W - 12), e.nickF)
    end
    v:footer({ back = function()
      if toForm then RU.open() else if e.isNew then go("pick") else backToList() end end
    end })
    pl.draw()
  end

  ---------------------------------------------------------------------------
  -- The loop
  ---------------------------------------------------------------------------
  local PAGES = { list = drawList, kind = drawKind, pick = drawPick, item = drawItem, edit = drawEdit, watch = drawWatch }
  if RU then
    PAGES.rule, PAGES.rpick, PAGES.rlike = RU.drawForm, RU.drawPick, RU.drawLike
  end
  local lastErr
  local function draw(view)
    local ok, err = pcall(PAGES[st.page] or drawList)
    if not ok and err ~= lastErr then lastErr = err; ui.say("Screen error: " .. tostring(err), "bad") end
  end

  describe(unassigned())   -- one read of everything up front: searching by contents works straight away
  v:invalidate()
  -- A kit loop of our own. ui.quit() ends it (and any other kit loop running in parallel, which its owner restarts).
  local function onEvent(ev)
    pollWatch()
    local e = st.edit
    if e and e.extraClick then
      e.extraClick = false
      if o.extra.plain then   -- a typed setting: a plain screen for a moment
        term.setCursorBlink(false)
        term.setBackgroundColour(colours.black); term.setTextColour(colours.white)
        term.clear(); term.setCursorPos(1, 1)
      end
      o.extra.click(e.name, e.extra)
      v:invalidate()
    end
  end
  ui.run({ v }, draw, { tick = 1, on_event = onEvent })
  if st.watch then o.release() end
  if ownView then v:close() end
  v:invalidate()
end

return A
