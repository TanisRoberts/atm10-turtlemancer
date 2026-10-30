-- neural_screens.lua  --  Neural lab: its screens, built only from the UI kit (docs/systems/ui.md, design:
-- docs/design/neural.md). The overview of columns, one page per column (training columns explain what to do next),
-- a report page for /status /list /pairs, and the typed commands (shared/slash.lua). Machine logic stays in
-- neural.lua, which hands over what the screen needs:
--   S.snap()  -> { L, P, cfg, E, problems, power, note, state ("running"|"paused"|"waiting"), dockMatrices,
--                  storageItems, furnatorFuel, matrixId }
--   S.lines(), S.stockText(p), S.accText(stats), S.shortName(id), S.pathOf(id)
--   S.setPaused(v), S.setForce(c, v), S.check(c), S.setRule(item, value), S.scan(), S.findMonitor() -> mon, name,
--   S.repickMonitor() (forget the saved monitor, reboot), S.handle(event...) (feeds shared/screens.lua)
-- Returns { run = fn, cmds = ... }: run() is the event loop (taps, keys, typed commands) and never returns.

local ui = require("ui")
local slash = require("slash")
local fit = ui.text.fit

return function(S)
local views = { ui.view(term.current()) }
local states = { term = { page = "home" }, monitor = { page = "home" } }
local function stateFor(v) return states[v.side and "monitor" or "term"] end
local function termView() return views[1] end

local function colNum(L, c)
  for i, x in ipairs(L.chambers) do if x == c then return i end end
  return 0
end
local function num(n)
  local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return s
end

---------------------------------------------------------------------------
-- A column's state word, its colour and the glyph the kit draws before it. The internal states are capitals;
-- the screen says them in lower case. Running moves, a wait is a still "o", a column that needs a person is a red "!".
---------------------------------------------------------------------------
local G = ui.glyphs
G.class["training"] = "working"
for _, w in ipairs({ "at target", "off", "paused", "wait power", "train wait" }) do G.still[w] = { "o", "warn" } end
for _, w in ipairs({ "learning", "checking" }) do G.still[w] = { "o", "info" } end
for _, w in ipairs({ "no model", "no fab", "no matrices", "no counts", "no dock", "dock full", "pick a drop", "no power",
                     "fab no power", "trained?", "stuck" }) do G.still[w] = { "!", "bad" } end

local function wordOf(p)
  local s = p.state or "?"
  if s == "RUNNING" then return "running", "good" end
  if s == "TRAINING" then return "training", "busy" end
  if s == "LEARNING" or s == "CHECKING" then return s:lower(), "info" end
  if p.blink then return s:lower(), "bad" end
  if s == "?" then return "?", "dim" end
  return s:lower(), "warn"
end
local STATE_TONE = { running = "good", paused = "warn", waiting = "gold" }

-- The most useful problem, in words (the tiles only have room for a state)
local PRIORITY = { "ops", "dock", "dockfull", "counts", "fuel", "matrices", "error" }
local function firstProblem(problems)
  for _, k in ipairs(PRIORITY) do if problems[k] then return problems[k] end end
  local keys = {}
  for k in pairs(problems) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys[1] and problems[keys[1]] or nil
end
local function clean(msg) return (msg:gsub("^Neural lab:? ?", "")) end

local function syncMonitor()
  local mon, name = S.findMonitor()
  if views[2] and views[2].side == name then views[2].t = mon or views[2].t; views[2]:measure(); return end
  views[2] = mon and ui.view(mon, { side = name }) or nil
end

local function wrap(text, w)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end

local function go(v, page, extra)
  local st = stateFor(v)
  for k in pairs(st) do st[k] = nil end
  st.page = page
  for k, val in pairs(extra or {}) do st[k] = val end
  v.page, v.sel, v.armed, v.focus = 1, nil, nil, nil
end

---------------------------------------------------------------------------
-- Buttons on the footer row, left of the pager: what fits, widest list first
---------------------------------------------------------------------------
local function footerButtons(v, lists, pager)
  local maxx = v.W - 1 - (pager and 12 or 0)
  local pill = v.colour and 2 or 4
  local pick = lists[#lists]
  for _, list in ipairs(lists) do
    local total = 1
    for _, b in ipairs(list) do total = total + #b.label + pill + 1 end
    if total + 1 <= maxx then pick = list; break end
  end
  v:buttons(2, v.H, pick, { maxx = maxx })
end

---------------------------------------------------------------------------
-- The overview
---------------------------------------------------------------------------
local function checkable(p) return p.mob and (p.f or not p.training) end

local function checkAll(snap)
  local n = 0
  for _, c in ipairs(snap.L.chambers) do
    local p = snap.P[c]
    if p and checkable(p) then S.check(c); n = n + 1 end
  end
  ui.say(n > 0 and ("Checking %d column%s."):format(n, n == 1 and "" or "s") or "No column to check.", n > 0 and "good" or "warn")
end

local function home(v, st, snap)
  local L, P, cfg = snap.L, snap.P, snap.cfg
  local inp = v.side and 0 or 1
  local last = v.H - 1 - inp
  local pw = snap.power
  local pwText = pw.pct and ("power %d%%"):format(pw.pct) or "power ?"
  if pw.lowSim and pw.lowSim < (snap.E.FUEL_BELOW or 30) and (not pw.pct or pw.lowSim < pw.pct) then
    pwText = ("sim #%d %d%%"):format(colNum(L, pw.lowSimName), pw.lowSim)   -- one chamber is starving: say which
  end
  local right = ("%s  matrices %d"):format(pwText, snap.dockMatrices)
  v:header("Neural lab", { state = snap.state, color = STATE_TONE[snap.state], right = right })

  local prob = firstProblem(snap.problems)
  local reserve = inp + (prob and 1 or 0) + ((v.H >= 20 and #L.chambers > 0) and 1 or 0)
  local items = {}
  for i, c in ipairs(L.chambers) do items[i] = { i = i, c = c, p = P[c] or {} } end

  local pages = 1
  if #items > 0 then
    -- CHECK sits in each 5-row tile. It is registered before the tiles so a tap on it wins over the tile under it.
    local cols, tw, th, rows, np = ui.layout.tiles(v.W, v.H - reserve, #items)
    pages = np
    local per = cols * rows
    local page = math.max(1, math.min(v.page or 1, np))
    if th == 5 then
      for k = 1, per do
        local it = items[(page - 1) * per + k]
        if not it then break end
        if checkable(it.p) then
          local x = 2 + ((k - 1) % cols) * (tw + 1) + tw - (v.colour and 7 or 9)
          local y = 3 + math.floor((k - 1) / cols) * (th + 1) + 3
          v:buttons(x, y, { { label = "CHECK", id = "check:" .. it.i, style = "primary", fn = function() S.check(it.c) end } })
        end
      end
    end
    local y = v:tiles(items, { input = reserve, on = function(it) go(v, "col", { col = it.c }) end,
      render = function(it)
        local word, tone = wordOf(it.p)
        local runs = (cfg.stats[it.c] or {}).runs or 0
        return { name = ("#%d %s"):format(it.i, it.p.mob or "empty"), state = word, color = tone,
                 activity = S.stockText(it.p), numbers = it.p.training and ("runs %d"):format(runs) or S.accText(cfg.stats[it.c]) }
      end })
    if y > last then y = y - 1 end                            -- the gap row under the last tiles is free
    local function line(text, tone, alert)
      if y > last then return end
      if alert then v:alert(2, y, v.W - 2, text, tone) else v:put(2, y, fit(text, v.W - 2), tone, "bg") end
      y = y + 1
    end
    if prob then line(clean(prob), "bad", true) end
    if v.H >= 20 then line(snap.note, next(snap.problems) and "gold" or "dim") end
  else
    v:alert(2, 3, v.W - 2, "No chambers on the cable yet.", "warn")
    if prob then v:alert(2, 4, v.W - 2, clean(prob), "bad") end
    v.pages = 1
  end

  v:footer({ pages = pages })
  local pauseBtn = { label = cfg.paused and "Run" or "Pause", id = "pause", style = cfg.paused and "primary" or "idle",
                     fn = function() S.setPaused(not cfg.paused) end }
  footerButtons(v, {
    { pauseBtn, { label = "Check all", id = "checkall", fn = function() checkAll(snap) end } },
    { pauseBtn, { label = "Check", id = "checkall", fn = function() checkAll(snap) end } },
    { pauseBtn } }, pages > 1)
end

---------------------------------------------------------------------------
-- One column
---------------------------------------------------------------------------
local function columnPage(v, st, snap)
  local L, P, cfg = snap.L, snap.P, snap.cfg
  local c = st.col
  local p = P[c]
  if not p then go(v, "home"); return home(v, stateFor(v), snap) end
  local i = colNum(L, c)
  local W = v.W
  local word, tone = wordOf(p)
  v:header(("#%d %s"):format(i, p.mob or "empty"), { state = word, color = tone, right = "column " .. i })
  local last = v.H - 1 - (v.side and 0 or 1)
  local g = v.H >= 20 and 1 or 0                              -- a blank row between blocks, if there is room

  local probs = {}
  for k, msg in pairs(snap.problems) do
    if k:match("^[^:]+:(.*)$") == c then probs[#probs + 1] = (msg:gsub("^Neural lab column %d+ %b(): ", "")) end
  end
  table.sort(probs)
  local lim = last - math.min(#probs, 3)

  local y = 3
  local function text(t, tn)
    for _, l in ipairs(wrap(t, W - 2)) do
      if y <= lim then v:put(2, y, fit(l, W - 2), tn or "fg", "bg"); y = y + 1 end
    end
  end

  if p.training then
    text("Training: levels the model", "busy")
    text("Then switch the chamber to Inference (its screen) when it is Self Aware.", "dim")
    text(("Keeps %d matrices spare."):format(math.floor(snap.E.TRAIN_KEEP or 64)), "dim")
    if not p.f then y = y + g; text("No fab yet: set it to Training and I will feed it.") end
  elseif not p.f then
    text("No fab yet.")
    text("Set the chamber to Training and I will feed it to level up.", "dim")
  end
  if p.f then
    text(p.item and ("Fab makes: " .. S.shortName(p.item)) or "Fab makes: not seen yet")
    if p.switched and os.clock() - p.switched.at < 120 then text(("Switched from %s."):format(S.shortName(p.switched.from)), "info") end
    text("Pick it in the fab's own screen.", "dim")
  end
  y = y + g

  if p.item and y <= lim then
    local cap = p.cap or 0
    local frac = cap > 0 and math.min(1, (p.stock or 0) / cap) or 0
    v:bar(2, y, W - 2, "Stock", frac, { kind = "progress",
      text = ("%s / %s"):format(p.stock and tostring(p.stock) or "?", cap == 0 and "off" or tostring(cap)) })
    y = y + 1
    if y <= lim then
      local x, row = v:stepper(2, y, "Target", cap, { min = 0, step = cap >= 256 and 64 or 16, id = "target",
        on = function(n) S.setRule(p.item, n) end })
      if cap == 0 and x + 5 < W then v:put(x + 2, row, "off", "dim", "bg") end
      y = row + 1 + g
    end
  end

  if y <= lim then
    v:put(2, y, "Mode", "fg", "bg")
    local cur = cfg.force[c] or "auto"
    local lx, ly = v:switch(8, y, { { id = "auto", label = "AUTO" }, { id = "on", label = "ON" }, { id = "off", label = "OFF" } },
      cur, function(id) S.setForce(c, id ~= "auto" and id or nil) end, { id = "mode" })
    if checkable(p) then
      local bw = (v.colour and 2 or 4) + 5
      if lx + 3 + bw - 1 > W - 1 then ly = ly + 1; lx = 1 end
      v:buttons(lx + 2, ly, { { label = "CHECK", id = "check", style = "primary", fn = function() S.check(c) end } })
    end
    y = ly + 1 + g
  end

  local st2 = snap.cfg.stats[c] or {}
  text(("Runs %s, preds %s, %s"):format(num(st2.runs or 0), num(st2.preds or 0), S.accText(st2)), "dim")
  text(("Made %s, banked %d, in fab %d"):format(num(st2.made or 0), p.bank or 0, p.fin or 0), "dim")
  text(("Matrices %d, C %d%% F %d%%"):format(p.matrices or 0,
    (p.cCap or 0) > 0 and math.floor(p.cEnergy / p.cCap * 100) or 0, (p.fCap or 0) > 0 and math.floor(p.fEnergy / p.fCap * 100) or 0), "dim")
  y = y + g
  text(S.pathOf(c), "bar")
  text(p.f and S.pathOf(p.f) or "no fab paired", "bar")
  text(p.l and ("lamp: " .. S.pathOf(p.l)) or "no lamp", "bar")

  y = lim + 1
  for k, msg in ipairs(probs) do
    if k > 3 then break end
    v:alert(2, y, W - 2, msg, "bad"); y = y + 1
  end
  v:footer({ back = function() go(v, "home") end })
end

---------------------------------------------------------------------------
-- Reports for /status /list /pairs
---------------------------------------------------------------------------
local function report(v, st, snap)
  local rows = {}
  for _, r in ipairs(st.rows) do rows[#rows + 1] = r end
  if st.page == "status" then
    for _, msg in pairs(snap.problems) do rows[#rows + 1] = { alert = clean(msg), tone = "bad" } end
  end
  v:report{ title = st.title, state = snap.state, color = STATE_TONE[snap.state], rows = rows,
            back = function() go(v, "home") end }
end

local function openReport(page, title, rows)
  local v = termView()
  go(v, "report", { rows = rows, title = title })
  stateFor(v).page = page == "status" and "status" or "report"
end

---------------------------------------------------------------------------
-- Typed commands (on the computer's own screen, with or without the slash)
---------------------------------------------------------------------------
local cmds = slash.new()
local function column(a, i)
  local n, why = a:int(i)
  if not n then return nil, why end
  local snap = S.snap()
  local c = snap.L.chambers[n]
  if not c then return nil, ("No column %d."):format(n) end
  return c, n
end

cmds:add({ name = "status", help = "what is going on", max = 0, run = function()
  local rows = {}
  for _, l in ipairs(S.lines()) do rows[#rows + 1] = { text = l } end
  openReport("status", "Status", rows)
  return true, "Status", "plain"
end })
cmds:add({ name = "list", help = "what I found on my cable", max = 0, run = function()
  S.scan()
  local L = S.snap().L
  local rows = {}
  local function group(title, list)
    rows[#rows + 1] = { section = title }
    if #list == 0 then rows[#rows + 1] = { text = "none", tone = "dim" } end
    for _, n in ipairs(list) do rows[#rows + 1] = { text = n } end
  end
  group("Chambers", L.chambers); group("Fabs", L.fabs); group("Lamps", L.lamps); group("Furnators", L.furnators)
  group("Power", #L.cells > 0 and L.cells or { "none (using the machines' own)" })
  group("Drops to", { L.direct and ("storage's input chest " .. tostring(L.out)) or tostring(L.dock or "no dock") })
  if L.dockNote then rows[#rows + 1] = { alert = L.dockNote, tone = "warn" } end
  openReport("list", "On my cable", rows)
  return true, "On my cable", "plain"
end })
cmds:add({ name = "pairs", help = "which fab and lamp go with each chamber", max = 0, run = function()
  local snap = S.snap()
  local rows = {}
  for i, c in ipairs(snap.L.chambers) do
    local lk = snap.cfg.links[c] or {}
    rows[#rows + 1] = { section = ("#%d %s"):format(i, S.pathOf(c)) }
    rows[#rows + 1] = { key = "fab", value = lk.f and S.pathOf(lk.f) or "none" }
    rows[#rows + 1] = { key = "lamp", value = lk.l and S.pathOf(lk.l) or "none" }
  end
  rows[#rows + 1] = { blank = true }
  rows[#rows + 1] = { text = "Wrong? PAIRS= in neural.env, e.g. PAIRS=3:5:2", tone = "dim" }
  openReport("pairs", "Pairs", rows)
  return true, "Pairs", "plain"
end })
cmds:add({ name = "column", args = "<n>", min = 1, max = 1, help = "open one column's page", run = function(a)
  local c, n = column(a, 1)
  if not c then return false, n end
  go(termView(), "col", { col = c })
  return true, ("Column %d."):format(n), "plain"
end })
cmds:add({ name = "home", help = "back to the overview", max = 0, run = function() go(termView(), "home"); return true, "Overview" end })
cmds:add({ name = "check", args = "<n>", min = 1, max = 1,
  help = "send one prediction through column n's fab (no fab: one matrix, to see if it is on Training)", run = function(a)
    local c, n = column(a, 1)
    if not c then return false, n end
    S.check(c)
    return true, ("Checking column %d."):format(n)
  end })
for _, mode in ipairs({ "on", "off" }) do
  cmds:add({ name = mode, args = "<n>", min = 1, max = 1, help = "force column n " .. mode, run = function(a)
    local c, n = column(a, 1)
    if not c then return false, n end
    S.setForce(c, mode)
    return true, ("Column %d forced %s."):format(n, mode), mode == "off" and "warn" or "good"
  end })
end
cmds:add({ name = "auto", args = "<n>", min = 1, max = 1, help = "column n back on its target", run = function(a)
  local c, n = column(a, 1)
  if not c then return false, n end
  S.setForce(c, nil)
  return true, ("Column %d back on its target."):format(n)
end })
cmds:add({ name = "target", args = "<n> <count>", min = 2, max = 2, help = "how many of column n's item to keep (0 = off)", run = function(a)
  local c, n = column(a, 1)
  if not c then return false, n end
  local count, why = a:int(2)
  if not count or count < 0 then return false, why or "the count can't be negative" end
  local p = S.snap().P[c]
  if not p or not p.item then return false, ("Column %d has not shown what its fab makes yet."):format(n) end
  S.setRule(p.item, count)
  return true, ("Column %d keeps %s."):format(n, count == 0 and "nothing (off)" or tostring(count))
end })
cmds:add({ name = "monitors", help = "pick the monitor again (reboots)", max = 0, run = function()
  if not S.repickMonitor then return false, "No monitor to pick here." end
  S.repickMonitor()
end })
cmds:add({ name = "pause", help = "stop the lab (machines keep their contents)", max = 0,
  run = function() S.setPaused(true); return true, "Paused.", "warn" end })
cmds:add({ name = "stop", help = "same as /pause", max = 0, run = function() S.setPaused(true); return true, "Paused.", "warn" end })
for _, n in ipairs({ "resume", "go", "run" }) do
  cmds:add({ name = n, help = "carry on", max = 0, run = function() S.setPaused(false); return true, "Running." end })
end

local field
field = ui.field{ hint = "type a command, / lists them", max = 60,
  on_commit = function(t) field.text = ""; if not t:match("^%s*$") then cmds:exec(t) end end }

---------------------------------------------------------------------------
-- The loop
---------------------------------------------------------------------------
local PAGES = { home = home, col = columnPage, report = report, status = report }
local lastErr
local function draw(v)
  local st = stateFor(v)
  local snap = S.snap()
  local ok, err = pcall(PAGES[st.page] or home, v, st, snap)
  if not ok and err ~= lastErr then lastErr = err; ui.say("Screen error: " .. tostring(err), "bad") end
  if not v.side then v:search(field, { commands = cmds:commands() }) end
end

local function run()
  ui.loadAnim("neural.env")
  syncMonitor()
  ui.run(views, draw, { tick = 1, on_event = function(e, ...)
    if S.handle then S.handle(e, ...) end
    if e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      syncMonitor()
      if e ~= "monitor_resize" then os.queueEvent("neural_work") end   -- a new column (or a removed one): pick it up now
    end
  end })
end

return { run = run, cmds = cmds, views = views }
end
