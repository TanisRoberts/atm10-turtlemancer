-- opscreen.lua  --  the Operator's screens, built on the UI kit (design: docs/design/operator.md).
-- S.draw(view, ctx) draws one frame on one view (the computer's screen or a monitor). ctx = { rec, now, ctl, E }:
-- rec is the status record (units + plant), ctl the controls (opctl.lua). Each view keeps its own page in v.op.
--   overview   Power Grid column (totals) and a tile per reactor; narrower screens a strip and shorter tiles
--   reactor    tabs Power (rods, level, run switch, buffer), Needs (the checklist), Set (thresholds and limits)
--   wall       everything at once on a big monitor (opwall.lua)
local ui = require("ui")
local D = require("opdraw")
local floor, max, min = math.floor, math.max, math.min

local S = { D = D }

-- Data -------------------------------------------------------------------------------------------------
local function reactorsOf(rec)
  local out = {}
  for _, u in ipairs(rec.units or {}) do if u.kind == "reactor" then out[#out + 1] = u end end
  return out
end
S.reactorsOf = reactorsOf

-- ok / missing / unknown counts (rows a reactor does not need are left out)
function S.counts(r)
  local ok, miss, unk = 0, 0, 0
  for _, n in ipairs(r.needs or {}) do
    if n.state == "ok" then ok = ok + 1 elseif n.state == "missing" then miss = miss + 1
    elseif n.state == "unknown" then unk = unk + 1 end
  end
  return ok, miss, unk
end

local function heard(r) return r.present and r.answers and (r.seen or 0) < 30 end
S.heard = heard

-- word, stripe colour role, glyph state, word colour role
function S.state(r)
  if not heard(r) then return "not heard", "bar", "stale", "dim" end
  local _, miss = S.counts(r)
  local stripe = miss > 0 and "warn" or (r.active and "good" or "idle")
  return r.active and "running" or "idle", stripe, r.active and "running" or "idle", r.active and "good" or "idle"
end

local function cap(s) return (tostring(s):gsub("^%l", string.upper)) end

-- What a reactor waits for: the first missing thing, or why it is off, or "All good". text, tone.
function S.waits(r)
  if not r.present then return "Not on the cable", "bad" end
  if not r.answers then return "Not answering", "warn" end
  for _, n in ipairs(r.needs or {}) do
    if n.state == "missing" then return cap(n.why ~= "" and n.why or n.title), "warn" end
  end
  if r.manage == false then return "Left alone (Run it: NO)", "dim" end
  if r.mode == "off" then return "Off by hand", "idle" end
  if not r.active and r.buf and r.buf > (r.offAbove or 0.9) then
    return ("Off: buffer above %d%%"):format(floor((r.offAbove or 0.9) * 100 + 0.5)), "idle"
  end
  return "All good", "good"
end

function S.totals(rec, R)
  local p = rec.plant or {}
  local t = { fe = p.fe, buf = p.buf, net = p.net, n = #R, on = 0, problems = 0, supply = p.supply,
              avgHour = p.avgHour, wasteFull = 0 }
  local lvl, nl, fuel, nf, hot = 0, 0, 0, 0, nil
  for _, r in ipairs(R) do
    if r.active then t.on = t.on + 1; if r.level then lvl, nl = lvl + r.level, nl + 1 end end
    local _, miss = S.counts(r)
    if miss > 0 then t.problems = t.problems + 1 end
    if r.wasteStuck then t.wasteFull = t.wasteFull + 1 end
    if r.fuel and r.fuelMax and r.fuelMax > 0 then fuel, nf = fuel + r.fuel / r.fuelMax, nf + 1 end
    if r.casing and (not hot or r.casing > hot) then hot = r.casing end
  end
  t.level = nl > 0 and lvl / nl or nil
  t.fuel = nf > 0 and fuel / nf or nil
  t.hot = hot
  return t
end

local function fuelText(r)
  local f = r.fuel and r.fuelMax and r.fuelMax > 0 and (r.fuel / r.fuelMax) or nil
  return f and D.pct(f) or "?"
end

-- Small pieces ---------------------------------------------------------------------------------------------
local function stripe(v, x, y, role)
  if v.colour then v:put(x, y, " ", "fg", role) else v:put(x, y, role == "bar" and "?" or "|", "fg", "bg") end
end

local function opState(v)
  v.op = v.op or { tab = "power", all = false }
  return v.op
end

local function tell(msg) if msg then ui.say(msg, "warn") end end

-- A tile: `rows` = 5 (stripe, name and state, what it waits for, buffer, power, fuel) or 2 (name and state, buffer).
function S.tile(v, x, y, w, r, o)
  o = o or {}
  local rows = o.rows or 5
  local word, role, gstate, wtone = S.state(r)
  local dead = word == "not heard"
  for i = 0, rows - 1 do stripe(v, x, y + i, role) end
  local tx, tw = x + 2, w - 2
  local wx = x + w - #word
  v:put(wx, y, word, wtone, "bg")
  if wx - 2 > tx + 4 then v:glyph(wx - 2, y, gstate) end
  v:put(tx, y, D.fit(r.label, wx - 3 - tx), dead and "dim" or "fg", "bg")
  local yb = rows == 5 and 2 or 1
  if rows == 5 then
    local text, tone = S.waits(r)
    v:put(tx, y + 1, D.fit(text, tw), dead and "dim" or tone, "bg")
  end
  D.barRow(v, tx, y + yb, tw, "Buffer", dead and nil or r.buf, dead and "dim" or nil)
  if rows == 5 then
    local pw = tw < 26 and "pwr" or "power"
    v:put(tx, y + 3, D.fit(("%s FE/t  %s %s"):format(D.num(r.fe or 0), pw, r.level and (floor(r.level) .. "%") or "?"), tw),
      dead and "dim" or "fg", "bg")
    local seen = r.seen and ("seen " .. D.age(r.seen) .. (tw >= 26 and " ago" or "")) or "not seen"
    v:put(tx, y + 4, D.fit(("fuel %s  %s"):format(fuelText(r), seen), tw), "dim", "bg")
  end
  if o.on then
    local b = v:_box({ x, y, x + w - 1, y + rows - 1 }, nil, { fn = function() o.on(r) end, id = "tile:" .. r.label, focus = true })
    if o.sel then b.sel = true end
  end
end

-- Rows of the Power Grid, as { key, value, tone } (totals only, over every reactor)
local function gridRows(t)
  local rows = {
    { "Reactors on", ("%d/%d"):format(t.on, t.n) },
    { "Avg level", t.level and (floor(t.level + 0.5) .. "%") or "-" },
    { "Fuel", t.fuel and D.pct(t.fuel) or "?" },
    { "Supply", t.supply and (D.num(t.supply) .. " ingots") or "unknown", t.supply == nil and "warn" or nil },
    { "Hottest casing", t.hot and (floor(t.hot + 0.5) .. "C") or "?" },
  }
  return rows
end

local function netText(t)
  if not t.net then return "-" end
  return (t.net >= 0 and "+" or "-") .. D.num(math.abs(t.net)) .. "/t"
end

-- The Power Grid column: x, y0 (header row), w, last row it may use.
function S.grid(v, x, y0, w, last, rec, t)
  v:boardHeader(x, y0, w, "POWER GRID")
  local y = y0 + 1
  v:put(x + 1, y, "Output", "dim", "bg")
  v:put(x + 1, y + 1, D.fit(D.num(t.fe or 0) .. " FE/t", w - 2), "fg", "bg")
  y = y + 3
  v:kv(x + 1, y, w - 2, "Buffer", D.pct(t.buf))
  D.track(v, x + 1, y + 1, w - 2, t.buf, "good")
  y = y + 3
  v:kv(x + 1, y, w - 2, "Net", netText(t))
  y = y + 2
  local rows = gridRows(t)
  for i, row in ipairs(rows) do
    if y > last - 2 then break end
    v:kv(x + 1, y, w - 2, row[1], row[2], row[3])
    y = y + 1
    if i == 1 then y = y end
  end
  local foot = last
  if t.problems > 0 then
    v:put(x + 1, foot, D.fit(t.problems .. " needs fixing", w - 2), "warn", "bg")
  else
    v:put(x + 1, foot, "All good", "good", "bg")
  end
end

local function openReactor(v, r, tab)
  local o = opState(v)
  o.page, o.rid, o.tab, o.detail = "reactor", r.label, tab or "power", nil
  v.page = 1
end
S.openReactor = openReactor

-- Overview --------------------------------------------------------------------------------------------------
local function otherUnits(rec)
  local out = {}
  for _, u in ipairs(rec.units or {}) do if u.kind ~= "reactor" then out[#out + 1] = u end end
  return out
end

local function pageSlice(v, list, per)
  v.pages = max(1, math.ceil(#list / per))
  v.page = max(1, min(v.page or 1, v.pages))
  local out = {}
  for i = (v.page - 1) * per + 1, min(#list, v.page * per) do out[#out + 1] = list[i] end
  return out
end

local function summary(t)
  return ("%d reactor%s  %d problem%s"):format(t.n, t.n == 1 and "" or "s", t.problems, t.problems == 1 and "" or "s")
end

local function plantWord(t)
  if t.problems > 0 then return "waiting", "warn" end
  if t.on > 0 then return "running", "good" end
  return "idle", "idle"
end

local function overview(v, ctx, R, t)
  local rec, W, H = ctx.rec, v.W, v.H
  local word, tone = plantWord(t)
  v:header("OPERATOR", { state = word, color = tone, right = summary(t) })
  local open = function(r) openReactor(v, r, "power") end
  if W >= 50 then
    local gw = 17
    S.grid(v, 1, 3, gw, H - 2, rec, t)
    for y = 3, H - 1 do v:put(gw + 1, y, " ", "fg", "bar") end
    v:boardHeader(gw + 2, 3, W - gw - 1, "REACTORS")
    local tx = gw + 3
    local tw = min(33, W - tx)
    local per = max(1, floor((H - 1 - 4 + 1) / 6))
    local y = 4
    for _, r in ipairs(pageSlice(v, R, per)) do
      S.tile(v, tx, y, tw, r, { rows = 5, on = open })
      y = y + 6
    end
    if v.page == v.pages then
      for _, u in ipairs(otherUnits(rec)) do
        if y <= H - 1 then v:put(tx, y, D.fit(("%s (%s)%s"):format(u.label, u.kind, u.present and "" or " OFFLINE"), tw), "dim", "bg"); y = y + 1 end
      end
    end
  elseif W >= 36 then
    v:put(2, 3, D.fit(("Grid  %s FE/t  buf %s  %d/%d on"):format(D.num(t.fe or 0), D.pct(t.buf), t.on, t.n), W - 2), "fg", "bg")
    local per = max(1, floor((H - 6 + 1) / 3))
    local y = 4
    for _, r in ipairs(pageSlice(v, R, per)) do
      S.tile(v, 2, y, W - 2, r, { rows = 2, on = open })
      y = y + 3
    end
    local foot = t.problems > 0 and (t.problems .. " needs fixing") or "All good"
    v:put(2, max(y, min(H - 3, y)), foot, t.problems > 0 and "warn" or "good", "bg")
  else
    v:put(2, 3, D.fit(("%s FE/t  buffer %s"):format(D.num(t.fe or 0), D.pct(t.buf)), W - 2), "fg", "bg")
    v:put(2, 4, D.fit(("%d of %d on"):format(t.on, t.n), W - 2), "fg", "bg")
    if t.problems > 0 then v:put(2 + #("%d of %d on"):format(t.on, t.n) + 2, 4, D.fit(t.problems .. " needs fixing", W - 16), "warn", "bg") end
    local per = max(1, floor((H - 1 - 6 + 1) / 6))
    local y = 6
    for _, r in ipairs(pageSlice(v, R, per)) do
      S.tile(v, 2, y, W - 2, r, { rows = 5, on = open })
      y = y + 6
    end
  end
  v:footer({ back = function() ui.say("This is the top page. Hold Ctrl+T to stop the Operator.", "fg") end })
end

-- Reactor pages ------------------------------------------------------------------------------------------------
local TABS = { { id = "power", label = "Power", short = "Pwr" }, { id = "needs", label = "Needs", short = "Need" },
               { id = "set", label = "Set", short = "Set" } }

-- The two lines under the level: { label, value at the right edge (or nil), second line }
local function autoLines(r, now)
  if r.manage == false then return "Left alone", nil, "(Set: Run it)" end
  if r.holdLeft then return "Manual Hold:", D.clock(r.holdLeft), "tap AUTO to return now" end
  if r.mode == "on" then return "Forced on", nil, "" end
  if r.mode == "off" then return "Forced off", nil, "" end
  if not r.active then return ("Off until under %d%%"):format(floor((r.onBelow or 0.3) * 100 + 0.5)), nil, "" end
  if r.levelAt and r.levelWhy then return "Auto set:", D.age(now - r.levelAt), r.levelWhy end
  return "Auto: following buffer", nil, ""
end

function S.autoText(r, now)
  local a, b, c = autoLines(r, now)
  return a .. (b and (" " .. b) or "") .. ((c ~= "") and (" " .. c) or "")
end

-- Draw those lines at x, y (value flush right at x + w - 1)
local function autoDraw(v, x, y, w, r, now)
  local a, b, c = autoLines(r, now)
  if b then v:kv(x, y, w, a, b) else v:put(x, y, D.fit(a, w), "dim", "bg") end
  v:put(x, y + 1, D.fit(c, w), "dim", "bg")
end

local function stepFns(ctx, r)
  if r.mode == "off" or r.manage == false then return nil, nil end
  local ctl = ctx.ctl
  return function() tell(ctl.step(r.label, -5)) end, function() tell(ctl.step(r.label, 5)) end
end

local function runSwitch(v, ctx, x, y, r)
  return v:switch(x, y, { { id = "auto", label = "AUTO" }, { id = "on", label = "ON" }, { id = "off", label = "OFF" } },
    r.mode or "auto", function(id) ctx.ctl.mode(r.label, id); v.page = 1 end, { id = "run:" .. r.label })
end

local function levelText(r) return r.level and (floor(r.level + 0.5) .. "%") or "?" end

S.fuelPct = fuelText

local function inletText(r)
  return r.uranium and (fuelText(r) .. "  " .. D.num(r.uranium) .. " in inlet") or fuelText(r)
end

local function powerTab(v, ctx, r)
  local W, H, now = v.W, v.H, ctx.now
  local running = r.active and true or false
  local dec, inc = stepFns(ctx, r)
  local rods = r.rodLevels
  if not rods and r.level and r.rodCount then
    rods = {}
    for i = 1, r.rodCount do rods[i] = r.level end
  end
  D.section(v, 2, 3, W - 2, "POWER LEVEL")
  if W >= 50 and H >= 17 then
    local rh = min(max(H - 12, 3), 14)
    local rw = 3
    local width, caption = D.rods(v, 3, 4, rods, rw, rh, running)
    local sx = 3 + width + 5
    v:kv(sx, 4, W - 1 - sx, "Output", D.num(r.fe or 0) .. " FE/t")
    v:put(sx, 6, "Level", "fg", "bg")
    D.pair(v, sx + 7, 6, levelText(r), dec, inc, "lvl", 5)
    autoDraw(v, sx, 7, W - sx, r, now)
    v:put(sx, 10, "Run", "fg", "bg")
    runSwitch(v, ctx, sx + 5, 10, r)
    v:put(2, 4 + rh, D.fit(caption, W - 2), "dim", "bg")
    local y = D.section(v, 2, 5 + rh, W - 2, "BUFFER")
    y = D.buffer(v, 2, y, W - 2, r.buf, r.onBelow or 0.3, r.offAbove or 0.9, "Buffer")
    y = D.section(v, 2, y + 1, W - 2, "REACTOR")
    v:kv(2, y, W - 2, "Fuel", inletText(r))
    v:kv(2, y + 1, W - 2, "Temperature", ("fuel %sC  casing %sC"):format(D.num(r.fuelTemp), D.num(r.casing)))
  elseif W >= 31 then
    local rh = min(max(H - 9, 3), 10)
    local width = D.rods(v, 3, 4, rods, 2, rh, running)
    local sx = 3 + width + 3
    v:kv(sx, 4, W - 1 - sx, "Out", D.num(r.fe or 0) .. " FE/t")
    v:put(sx, 5, "Level", "fg", "bg")
    D.pair(v, sx + 6, 5, levelText(r), dec, inc, "lvl", 4)
    if r.holdLeft then v:kv(sx, 6, W - sx, "Manual Hold:", D.clock(r.holdLeft))
    elseif r.levelWhy and r.active and r.mode == "auto" then v:kv(sx, 6, W - sx, "Auto:", (r.levelWhy:gsub("^buffer ", "")))
    else v:put(sx, 6, D.fit((autoLines(r, now)), W - sx), "dim", "bg") end
    v:put(sx, 7, "Run", "fg", "bg")
    runSwitch(v, ctx, sx + 4, 7, r)
    local y = D.buffer(v, 2, 4 + rh, W - 2, r.buf, r.onBelow or 0.3, r.offAbove or 0.9, "Buffer")
    v:kv(2, y, W - 2, "Fuel", inletText(r))
    v:kv(2, y + 1, W - 2, "Temp", ("fuel %sC  casing %sC"):format(D.num(r.fuelTemp), D.num(r.casing)))
  else
    local width = D.rods(v, 3, 4, rods, 2, 5, running)
    local sx = 3 + width + 2
    v:put(sx, 4, "Level", "fg", "bg")
    v:put(sx, 5, levelText(r), "fg", "bg")
    v:put(sx, 7, r.holdLeft and "Hold" or "Auto", "dim", "bg")
    v:put(sx, 8, D.fit(r.holdLeft and D.clock(r.holdLeft) or (r.levelWhy and r.levelWhy:gsub("^buffer ", "") or ""), W - sx), "dim", "bg")
    D.pair(v, 2, 9, levelText(r), dec, inc, "lvl", 5)
    v:put(2, 10, "Run", "fg", "bg")
    runSwitch(v, ctx, 6, 10, r)
    v:kv(2, 11, W - 2, "Out", D.num(r.fe or 0) .. " FE/t")
    local y = D.buffer(v, 2, 12, W - 2, r.buf, r.onBelow or 0.3, r.offAbove or 0.9, "Buffer")
    v:kv(2, y + 1, W - 2, "Fuel", fuelText(r))
    v:kv(2, y + 2, W - 2, "Temp", ("%sC / %sC"):format(D.num(r.fuelTemp), D.num(r.casing)))
  end
end

local ICON = { ok = { "+", "good" }, missing = { "!", "bad" }, unknown = { "?", "warn" }, na = { "-", "dim" } }

local function wrap(text, w)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if #line + #word + (line == "" and 0 or 1) > w and line ~= "" then lines[#lines + 1] = line; line = word
    else line = line == "" and word or (line .. " " .. word) end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end
S.wrap = wrap

-- The needs checklist from row y, x..x+w-1, at most `room` rows; pages when it does not fit. Returns the next row.
-- A row that is not ok says "1 warning" / "1 problem" at the right (a narrow screen gives it a second line with the
-- reason instead). A tap on such a row calls o.open(need), which shows the reason in full and the way to fix it.
function S.needsList(v, x, y, w, room, r, o)
  o = o or {}
  local narrow = w < 30
  local items = {}
  for _, n in ipairs(r.needs or {}) do
    local bad = n.state ~= "ok" and n.state ~= "na"
    local value = n.why ~= "" and n.why or nil
    if bad then value = n.state == "missing" and "1 problem" or "1 warning" end
    local lines = { { text = n.title, value = (not narrow) and value or nil } }
    if narrow and bad then
      for _, l in ipairs(wrap(n.why, w - 5)) do lines[#lines + 1] = { text = l, sub = true } end
    end
    items[#items + 1] = { n = n, lines = lines }
  end
  -- pages of whole items
  local pages, cur, used = { {} }, 1, 0
  for _, it in ipairs(items) do
    if used + #it.lines > room and used > 0 then pages[#pages + 1] = {}; cur = cur + 1; used = 0 end
    pages[cur][#pages[cur] + 1] = it
    used = used + #it.lines
  end
  v.pages = #pages
  v.page = max(1, min(v.page or 1, #pages))
  for _, it in ipairs(pages[v.page]) do
    local n = it.n
    local icon = ICON[n.state] or ICON.unknown
    local tone = (n.state == "missing" and "bad") or (n.state == "unknown" and "warn") or nil
    for i, l in ipairs(it.lines) do
      if l.sub then
        v:put(x + 4, y, D.fit(l.text, w - 4), tone or "dim", "bg")
      else
        v:put(x, y, icon[1], icon[2], "bg")
        local vtxt = l.value and D.fit(l.value, max(w - #l.text - 5, 4)) or ""
        v:put(x + 2, y, D.fit(l.text, w - 2 - (#vtxt > 0 and #vtxt + 1 or 0)), tone or (n.state == "na" and "dim" or "fg"), "bg")
        if #vtxt > 0 then v:put(x + w - #vtxt, y, vtxt, (n.state == "ok" and "dim") or tone or "dim", "bg") end
        if (n.state ~= "ok" and n.state ~= "na") or n.ignored then
          v:_box({ x, y, x + w - 1, y }, nil, { fn = function() if o.open then o.open(n) end end,
            id = "need:" .. n.key, focus = true })
        end
      end
      y = y + 1
    end
  end
  return y
end

local function needsTab(v, ctx, r)
  local W, H = v.W, v.H
  local ok, miss, unk = S.counts(r)
  local o = opState(v)
  local label = W < 30 and ("NEEDS %d ok %d ! %d ?"):format(ok, miss, unk)
    or ("NEEDS  %d ok  %d missing  %d unknown"):format(ok, miss, unk)
  if miss == 0 and unk == 0 then label = "NEEDS  " end
  D.section(v, 2, 3, W - 2, label)
  if miss == 0 and unk == 0 then v:put(2 + #label, 3, "all good", "good", "bg") end
  S.needsList(v, 2, 4, W - 2, H - 4, r, { open = function(n) o.page, o.need, v.page = "need", n.key, 1 end })
end

-- The Set tab, as a list of rows so a short screen can page it.
local function setRows(v, ctx, r)
  local o = opState(v)
  local ctl = ctx.ctl
  local unit = ctl.reactors(r.label)[1]
  local rows = {}
  local function add(row) rows[#rows + 1] = row end
  local function stepper(label, key, suffix)
    add({ kind = "step", label = label, key = key, suffix = suffix or "%" })
  end
  add({ kind = "apply" }); add({ kind = "blank" })
  add({ kind = "section", text = "SWITCHING" })
  stepper("ON below", "onBelow"); stepper("OFF above", "offAbove")
  add({ kind = "blank" })
  add({ kind = "section", text = "LEVEL" })
  stepper("Lowest", "levelMin"); stepper("Highest", "levelMax"); stepper("Back to Auto after", "holdMin", " min")
  add({ kind = "blank" })
  add({ kind = "section", text = "REACTOR" })
  add({ kind = "run" }); add({ kind = "reset" })
  return rows, unit
end

local function setTab(v, ctx, r)
  local W, H = v.W, v.H
  local o = opState(v)
  local ctl = ctx.ctl
  local rows, unit = setRows(v, ctx, r)
  local room = H - 3
  local narrow = W < 36
  -- page the rows (a stepper takes two rows on a narrow screen)
  local function height(row) return (narrow and row.kind == "step") and 2 or 1 end
  local pages, cur, used = { {} }, 1, 0
  for _, row in ipairs(rows) do
    local h = height(row)
    if used + h > room then pages[#pages + 1] = {}; cur = cur + 1; used = 0 end
    if not (used == 0 and row.kind == "blank" and cur > 1) then
      pages[cur][#pages[cur] + 1] = row
      used = used + h
    end
  end
  v.pages = #pages
  v.page = max(1, min(v.page or 1, #pages))
  local y = 3
  local tx = W >= 50 and (W - 26) or (W - 15)       -- a gap before the default / local status at the right
  for _, row in ipairs(pages[v.page]) do
    if row.kind == "blank" then y = y + 1
    elseif row.kind == "section" then y = D.section(v, 2, y, W - 2, row.text)
    elseif row.kind == "apply" then
      v:put(2, y, "Applies to", "dim", "bg")
      v:switch(13, y, { { id = "this", label = "This reactor", short = "This" }, { id = "all", label = "All reactors", short = "All" } },
        o.all and "all" or "this", function(id) o.all = id == "all" end, { id = "apply" })
      y = y + 1
    elseif row.kind == "step" then
      local val, src = ctl.value(unit, row.key)
      local shown = row.key == "holdMin" and (floor(val) .. "") or (floor(val) .. "%")
      local text = row.key == "holdMin" and (floor(val) .. " min") or shown
      local tag = o.all and "" or (src == "unit" and "local" or "default")
      if W < 50 and src == "unit" and not o.all then text = text .. "*" end
      local lx = 2
      local py = y
      if narrow then v:put(lx, y, row.label, "fg", "bg"); py = y + 1; lx = 2 end
      if not narrow then v:put(lx, y, D.fit(row.label, tx - 3), "fg", "bg") end
      local px = narrow and 2 or tx
      D.pair(v, px, py, text, function() tell(ctl.change(r.label, o.all, row.key, -1)) end,
        function() tell(ctl.change(r.label, o.all, row.key, 1)) end, "set:" .. row.key, W >= 50 and 7 or 6)
      if W >= 50 and tag ~= "" then v:put(W - #tag, y, tag, src == "unit" and "gold" or "dim", "bg") end
      y = py + 1
    elseif row.kind == "run" then
      v:put(2, y, "Run it", "fg", "bg")
      v:switch(9, y, { { id = "yes", label = "YES" }, { id = "no", label = "NO" } }, r.manage == false and "no" or "yes",
        function(id) ctl.manage(r.label, id == "yes") end, { id = "manage" })
      if W >= 40 then v:put(24, y, "NO = leave it alone", "dim", "bg") end
      y = y + 1
    elseif row.kind == "reset" then
      v:buttons(2, y, { { label = "Reset to defaults", short = "Reset", confirm = true, id = "reset",
        fn = function() ctl.reset(r.label); ui.say(r.label .. ": back to the defaults", "good") end } })
      y = y + 1
    end
  end
end

local function reactorPage(v, ctx, r)
  local o = opState(v)
  local word, _, _, wtone = S.state(r)
  local _, miss, unk = S.counts(r)
  local shown = word
  if miss > 0 and heard(r) then shown, wtone = "waiting", "warn" end
  local size = (r.rodCount and (r.rodCount .. " rods") or "") .. " " .. (r.driver or "")
  v:header(r.label, { state = shown, color = wtone, right = (size:gsub("^%s+", "")) })
  local tab = o.tab or "power"
  if tab == "power" then powerTab(v, ctx, r)
  elseif tab == "needs" then needsTab(v, ctx, r)
  else setTab(v, ctx, r) end
  local tabs = {}
  for _, t in ipairs(TABS) do
    tabs[#tabs + 1] = { id = t.id, label = t.label, short = t.short, star = (t.id == "needs" and (miss > 0 or unk > 0)) or nil }
  end
  v:footer({ back = function() o.page = "overview"; v.page = 1 end, tabs = tabs, tab = tab,
             on_tab = function(id) o.tab = id; o.detail = nil end })
end

-- A need's own page: the reason in full and how to fix it -----------------------------------------------------------
local ROLE = { fuelIn = "input", fuel = "input", wasteOut = "output", wasteTo = "output" }
local ROLE_NAME = { input = "inlet", output = "outlet" }

local function findNeed(r, key)
  for _, n in ipairs(r.needs or {}) do if n.key == key then return n end end
end

local function needPage(v, ctx, r)
  local W, H = v.W, v.H
  local o = opState(v)
  local n = findNeed(r, o.need)
  local ctl = ctx.ctl
  local function back() o.page, o.tab, v.page = "reactor", "needs", 1 end
  if not n then back(); return reactorPage(v, ctx, r) end
  local word, tone = "warning", "warn"
  if n.state == "missing" then word, tone = "problem", "bad" elseif n.state == "na" then word, tone = "ignored", "dim" elseif n.state == "ok" then word, tone = "ok", "good" end
  v:header(r.label, { state = word, color = tone })
  local y = D.section(v, 2, 3, W - 2, n.title)
  for _, l in ipairs(wrap(n.ignored and n.was or n.why, W - 4)) do
    v:put(3, y, l, n.ignored and "dim" or tone, "bg"); y = y + 1
  end
  if n.ignored then v:put(3, y, "You chose to ignore this.", "dim", "bg"); y = y + 1 end
  y = y + 1
  local role = ROLE[n.key]
  local unit = ctl.reactors(r.label)[1]
  if role and unit then
    local cur = unit.cfg[role]
    y = D.section(v, 2, y, W - 2, "FIX")
    v:kv(2, y, W - 2, "Its " .. ROLE_NAME[role] .. " port", cur or "auto-detect", cur and "fg" or "dim")
    y = y + 1
    v:buttons(2, y, {
      { label = "Manually assign", short = "Assign", fn = function()
          o.page, o.role, v.page = "assign", role, 1
          o.search = ui.field{ hint = "type to narrow the list", max = 30 }
        end },
      { label = "Clear", enabled = cur ~= nil, fn = function() ctl.assign(r.label, role, nil); ui.say("Back to auto-detect", "good") end },
    })
    y = y + 2
  end
  y = D.section(v, 2, y, W - 2, "IGNORE")
  if n.ignored then
    for _, l in ipairs(wrap("It counts again if you stop ignoring it.", W - 4)) do v:put(3, y, l, "dim", "bg"); y = y + 1 end
    v:buttons(2, y, { { label = "Stop ignoring", short = "Stop", fn = function() ctl.ignore(r.label, n.key, false) end } })
  else
    for _, l in ipairs(wrap("For something that can't be fixed, like a power tap that can't go on the cable.", W - 4)) do
      v:put(3, y, l, "dim", "bg"); y = y + 1
    end
    v:buttons(2, y, { { label = "Ignore this", short = "Ignore", fn = function() ctl.ignore(r.label, n.key, true) end } })
  end
  v:footer({ back = back })
end

-- Pick a device on the cable for a reactor's inlet or outlet
local function assignPage(v, ctx, r)
  local W, H = v.W, v.H
  local o = opState(v)
  local ctl = ctx.ctl
  local role = o.role or "input"
  local function back() o.page, v.page = "need", 1 end
  o.search = o.search or ui.field{ hint = "type to narrow the list", max = 30 }
  local f = o.search
  v:header("ASSIGN " .. ROLE_NAME[role]:upper(), { state = r.label, color = "dim" })
  local want = f.text:lower()
  local rows = {}
  for _, c in ipairs(ctl.candidates()) do
    if want == "" or c.name:lower():find(want, 1, true) or c.type:lower():find(want, 1, true) then
      rows[#rows + 1] = { name = c.name .. (c.taken and ("  (" .. c.taken .. ")") or ""), value = c.type,
        state = c.port and "info" or "bar", id = c.name }
    end
  end
  v:list(rows, { input = not v.side, on = function(row)
    local note = ctl.assign(r.label, role, row.id)
    ui.say(row.id .. " is now " .. r.label .. "'s " .. ROLE_NAME[role] .. (note and ("; " .. note) or ""), "good")
    back()
  end })
  if #rows == 0 then v:put(3, 4, "Nothing matches.", "dim", "bg") end
  v:footer({ back = back })
  if not v.side then v:search(f, { hint = "type to narrow, tap a device twice to pick it" }) end
end

-- Entry ---------------------------------------------------------------------------------------------------------
function S.draw(v, ctx)
  v.pages = 1
  local rec = ctx.rec
  local o = opState(v)
  if not rec then
    v:header("OPERATOR", { state = "waiting", color = "warn" })
    v:put(2, 4, "Starting...", "dim", "bg")
    return
  end
  local R = reactorsOf(rec)
  local t = S.totals(rec, R)
  if v.W >= 120 and v.H >= 50 then return require("opwall")(S).draw(v, ctx, R, t) end
  if o.page == nil then
    o.page = (#R == 1 and v.W < 50) and "reactor" or "overview"
    o.rid = R[1] and R[1].label
  end
  local r
  if o.page == "reactor" or o.page == "need" or o.page == "assign" then
    for _, x in ipairs(R) do if x.label == o.rid then r = x end end
    if not r then o.page = "overview" end
  end
  if o.page == "reactor" then reactorPage(v, ctx, r)
  elseif o.page == "need" then needPage(v, ctx, r)
  elseif o.page == "assign" then assignPage(v, ctx, r)
  else overview(v, ctx, R, t) end
end

return S
