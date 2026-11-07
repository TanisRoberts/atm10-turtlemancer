-- opwall.lua  --  the Operator on a big monitor (164x81 and the like): everything at once. Power Grid at the left,
-- up to three whole reactor panels across, the plant buffer chart on top, and the glance band (power use, Needs you,
-- recent events) below. More than three
-- reactors become tiles. The chart and the events need the buffer history and the event log in the status record;
-- without them that room is left empty. Design: docs/design/operator.md ("Wall 164x81").
local ui = require("ui")
local floor, max, min = math.floor, math.max, math.min

return function(S)
  local D = S.D
  local M = {}
  local LEFT = 38

  local function rowsFor(v, x, y, w, rows)
    for _, row in ipairs(rows) do
      v:kv(x, y, w, row[1], row[2], row[3])
      y = y + 1
    end
    return y
  end

  -- Alerts for the left column: one line group per problem, reactors with the same problem named together.
  local function alerts(R)
    local out, seen, order = {}, {}, {}
    for _, r in ipairs(R) do
      for _, n in ipairs(r.needs or {}) do
        if n.state == "missing" or n.state == "unknown" then
          local key = n.state .. "|" .. n.title .. "|" .. n.why
          if not seen[key] then seen[key] = { state = n.state, title = n.title, why = n.why, who = {} }; order[#order + 1] = key end
          table.insert(seen[key].who, r.label)
        end
      end
    end
    for _, key in ipairs(order) do
      local a = seen[key]
      local tail = a.state == "missing" and (a.title:lower() .. ": " .. a.why) or (a.title:lower() .. " unknown (" .. a.why .. ")")
      out[#out + 1] = { text = table.concat(a.who, ", ") .. ": " .. tail .. ".", tone = a.state == "missing" and "bad" or "warn" }
    end
    return out
  end

  -- Power Grid totals in the left column, rows 29 (header) to 57, a divider at LEFT + 1.
  local function left(v, ctx, R, t)
    v:boardHeader(1, 29, LEFT, "POWER GRID")
    local x, w = 2, LEFT - 2
    local rows = {
      { "Output", D.num(t.fe or 0) .. " FE/t" },
      { "Buffer", D.pct(t.buf) },
      { "Net", t.net and ((t.net >= 0 and "+" or "-") .. D.num(math.abs(t.net)) .. " FE/t") or "-" },
      { "Reactors on", ("%d of %d"):format(t.on, t.n) },
      { "Average level", t.level and (floor(t.level + 0.5) .. "%") or "-" },
      { "Fuel", t.fuel and D.pct(t.fuel) or "?" },
      { "Supply (Storage)", t.supply and (D.num(t.supply) .. " ingots") or "unknown", t.supply == nil and "warn" or nil },
      { "Hottest casing", t.hot and (floor(t.hot + 0.5) .. "C") or "?" },
      { "Waste outlets", t.wasteFull > 0 and (t.wasteFull .. " full") or "clear", t.wasteFull > 0 and "bad" or nil },
    }
    rowsFor(v, x, 31, w, rows)
    for yy = 30, 57 do v:put(LEFT + 1, yy, " ", "fg", "bar") end
  end

  -- One whole reactor in a column x..x+w-1 from row y. Returns the next free row.
  local function panel(v, ctx, r, x, y0, w)
    local o = v.op
    local now = ctx.now
    local word, role, gstate, wtone = S.state(r)
    local cx, cw = x + 2, w - 3
    local y = y0
    if r.awaiting then
      v:put(cx, y, D.fit(tostring(r.id and r.id:gsub("^BigReactors%-", "") or r.label), cw - 6), "fg", "bg")
      v:put(cx + cw - 5, y, "setup", "info", "bg")
      v:put(cx, y + 1, "New Reactor Awaiting Setup", "info", "bg")
      v:put(cx, y + 3, D.fit("Not switched until it is set up.", cw), "dim", "bg")
      v:put(cx, y + 4, D.fit("Finish it on the computer's screen.", cw), "dim", "bg")
      for yy = y0, y0 + 4 do v:put(x, yy, " ", "fg", "info") end
      return y0 + 5
    end
    v:put(cx, y, D.fit(r.label, cw - #word - 3), S.heard(r) and "fg" or "dim", "bg")
    v:put(cx + cw - #word, y, word, wtone, "bg")
    v:glyph(cx + cw - #word - 2, y, gstate)
    local text, tone = S.waits(r)
    v:put(cx, y + 1, D.fit(text, cw), tone, "bg")
    y = D.section(v, cx, y + 3, cw, "POWER LEVEL")
    local levels = r.rodLevels
    if not levels and r.level and r.rodCount then
      levels = {}
      for i = 1, r.rodCount do levels[i] = r.level end
    end
    local cols = min(levels and #levels or 5, 8)
    local rw = max(2, min(6, floor((cw + 1) / cols) - 1))
    D.rods(v, cx, y, levels, rw, 14, r.active)
    y = y + 14
    local al = S.autoText(r, now)
    v:put(cx, y, D.fit(al, cw), "dim", "bg")
    y = y + 1
    local dec, inc
    if r.mode ~= "off" and r.manage ~= false then
      dec = function() local m = ctx.ctl.step(r.label, -5); if m then ui.say(m, "warn") end end
      inc = function() local m = ctx.ctl.step(r.label, 5); if m then ui.say(m, "warn") end end
    end
    D.pair(v, cx, y, r.level and (floor(r.level + 0.5) .. "%") or "?", dec, inc, "lvl:" .. r.label, 5)
    v:switch(cx + 17, y, { { id = "auto", label = "AUTO" }, { id = "on", label = "ON" }, { id = "off", label = "OFF" } },
      r.mode or "auto", function(id) ctx.ctl.mode(r.label, id) end, { id = "run:" .. r.label })
    D.barRow(v, cx, y + 2, cw, "Buffer", r.buf)
    y = y + 3
    y = rowsFor(v, cx, y, cw, {
      { "Output", D.num(r.fe or 0) .. " FE/t" },
      { "Fuel", r.uranium and (S.fuelPct(r) .. "  " .. D.num(r.uranium) .. " in inlet") or S.fuelPct(r) },
      { "Fuel temperature", D.num(r.fuelTemp) .. "C" },
      { "Casing temperature", D.num(r.casing) .. "C" },
      { "Waste outlet", r.wasteStuck and "full" or (r.outlet and r.outlet > 0 and (r.outlet .. " waiting") or "empty"), r.wasteStuck and "bad" or nil },
    })
    for yy = y0, y - 1 do
      if v.colour then v:put(x, yy, " ", "fg", role) else v:put(x, yy, "|", "fg", "bg") end
    end
    return y
  end

  local function falling(t) return t.net ~= nil and t.net < 0 end

  -- Rows 3-26: the plant buffer chart across the whole width.
  local function chart(v, ctx, rec, R, t)
    local W = v.W
    local hist = (rec.plant or {}).hist or {}
    local now = hist[#hist] or (t.buf and t.buf * 100)
    local nowText = now and ("now " .. floor(now + 0.5) .. "%") or ""
    D.section(v, 2, 3, W - 2 - (#nowText > 0 and #nowText + 1 or 0), "PLANT BUFFER, LAST 30 MINUTES")
    if #nowText > 0 then v:put(W - #nowText, 3, nowText, falling(t) and "warn" or "fg", "bg") end
    local ch, y0 = 22, 4
    local px, pw = 7, W - 7
    local r1 = R[1] or {}
    local on, off = r1.onBelow or 0.3, r1.offAbove or 0.9
    local rowOn = max(1, min(ch, ch - floor(on * ch + 0.5) + 1))
    local rowOff = max(1, min(ch, ch - floor(off * ch + 0.5) + 1))
    local n = #hist
    for row = 1, ch do
      local cells = {}
      for c = 1, pw do
        local idx = n - floor((pw - c) * 120 / pw)
        local fillH = (idx >= 1 and idx <= n) and floor(hist[idx] / 100 * ch + 0.5) or 0
        if (ch - row + 1) <= fillH then cells[c] = { " ", "fg", c == pw and "fg" or "info" }
        elseif row == rowOff and c % 2 == 1 then cells[c] = { ".", "idle", "bg" }
        elseif row == rowOn and c % 2 == 1 then cells[c] = { ".", "warn", "bg" }
        else cells[c] = { " ", "fg", "bg" } end
      end
      v:cells(px, y0 + row - 1, cells)
    end
    v:put(2, y0, "100%", "dim", "bg")
    v:put(2, y0 + rowOff - 1, ("%3d%%"):format(floor(off * 100 + 0.5)), "idle", "bg")
    v:put(2, y0 + rowOn - 1, ("%3d%%"):format(floor(on * 100 + 0.5)), "warn", "bg")
    v:put(3, y0 + ch - 1, "0%", "dim", "bg")
    v:put(px, 26, "-30 min", "dim", "bg")
    v:put(px + floor(pw / 2) - 3, 26, "-15 min", "dim", "bg")
    v:put(W - 3, 26, "now", "dim", "bg")
  end

  local function rule(v, y) v:put(1, y, (v.colour and "\140" or "-"):rep(v.W), "bar", "bg") end

  -- Throttled: the detector's limit is set below its "no limit" default (#121).
  local function throttled(pw) return pw and pw.limit and pw.limit < 1e9 end

  -- Rows 59-79 left: POWER USE in block digits, then the figures and a note.
  local function powerUse(v, t, ctx)
    local pw = t.power
    local thr = throttled(pw)
    v:boardHeader(1, 59, 70, "POWER USE")
    if thr then
      local tag = "THROTTLED"
      v:put(70 - #tag, 59, tag, "bg", "bad")
    end
    local pct = pw and pw.draw and pw.pct
    if pw and pw.estimated and not thr then v:put(70 - 4, 59, "est.", "warn", "bg") end     -- a reactor is only estimated
    if not pw or not pw.draw then
      v:bigNumber(3, 61, "--", "dim", { px = 4, py = 2 })
      v:put(3, 72, "No energy detector on the cable", "dim", "bg")
      return
    end
    local tone = thr and "bad" or ((pct or 0) >= 100 and "warn" or "good")
    if pct then v:bigNumber(3, 61, floor(pct + 0.5) .. "%", tone, { px = 4, py = 2 }) end
    local draw, pot = D.num(pw.draw), D.num(pw.potential or 0)
    if thr then
      v:put(3, 72, "Throttled at " .. D.num(pw.limit) .. " FE/t", "bad", "bg")
      if pw.asked then
        local note = "Asked for " .. D.num(pw.asked) .. (pw.askedPct and (" (" .. floor(pw.askedPct + 0.5) .. "%)") or "") ..
          (pw.askedFor and (" for " .. D.age(pw.askedFor)) or "")
        v:put(3, 73, note, "bad", "bg")
      end
      if ctx and ctx.ctl then S.resetButton(v, ctx, 3, 75) end
    else
      v:put(3, 72, draw .. " of " .. pot .. " FE/t", "fg", "bg")
      if (pct or 0) >= 100 then
        v:put(3, 73, ("Over output, buffer %s %s"):format(D.pct(t.buf), falling(t) and "falling" or (t.net and t.net > 0 and "rising" or "steady")), "warn", "bg")
      else
        v:put(3, 73, "Buffer " .. D.pct(t.buf), "dim", "bg")
      end
      local at = S.avgText(pw)
      if at then v:put(3, 74, at, "dim", "bg") end
    end
  end

  -- Rows 59-63 right: Needs you; rows 65-79: Recent.
  local function glance(v, rec, R, t)
    local x, w = 74, v.W - 73
    local list = {}
    local pw = t.power
    if throttled(pw) then
      list[1] = { text = ("Power throttled: over %d%%. Add power."):format(pw.askedPct and floor(pw.askedPct / 50 + 0.5) * 50 or 150), tone = "bad", name = "Power" }
    end
    for _, a in ipairs(alerts(R)) do list[#list + 1] = { text = a.text, tone = a.tone, name = a.text:match("^[^:]+") } end
    local off = 0
    for _, r in ipairs(R) do if not r.active and r.mode ~= "off" then off = off + 1 end end
    local sum = ("%d reactor%s: %d on, %d off%s, all parts found"):format(t.n, t.n == 1 and "" or "s", t.on, t.n - t.on, off > 0 and " by Auto" or "")
    v:needsYou(x, 59, w, 4, list, { summary = sum })
    local events = (rec.plant or {}).events or {}
    D.section(v, x, 65, w, "RECENT")
    for i = 1, min(#events, 14) do
      local e = events[i]
      v:put(x, 65 + i, e.at or "", "dim", "bg")
      local who = D.fit(e.who or "", 10)
      v:put(x + 7, 65 + i, who, "fg", "bg")
      v:put(x + 9 + #who, 65 + i, D.fit(e.text or "", w - 10 - #who), "fg", "bg")
    end
  end

  function M.draw(v, ctx, R, t)
    local rec, W, H = ctx.rec, v.W, v.H
    local word, tone = "idle", "idle"
    if t.problems > 0 then word, tone = "waiting", "warn" elseif t.on > 0 then word, tone = "running", "good" end
    v:header("OPERATOR", { state = word, color = tone, right = ("%d reactor%s  %d on  %d problem%s"):format(t.n, t.n == 1 and "" or "s",
      t.on, t.problems, t.problems == 1 and "" or "s") })
    chart(v, ctx, rec, R, t)
    rule(v, 28)
    left(v, ctx, R, t)
    local x0 = LEFT + 3
    v:boardHeader(x0 - 1, 29, W - x0 + 2, "REACTORS")
    if #R <= 3 then
      for i, r in ipairs(R) do panel(v, ctx, r, x0 + (i - 1) * 42, 31, 41) end
    else
      local cols = max(1, floor((W - x0) / 35))
      for i, r in ipairs(R) do
        local col, row = (i - 1) % cols, floor((i - 1) / cols)
        local y = 31 + row * 6
        if y + 5 <= 56 then S.tile(v, x0 + col * 35, y, 33, r, { rows = 5 }) end
      end
    end
    rule(v, 58)
    powerUse(v, t, ctx)
    glance(v, rec, R, t)
    for yy = 59, H - 2 do v:put(72, yy, " ", "fg", "bar") end
    v:footer({ back = function() ui.say("This is the top page. Hold Ctrl+T to stop the Operator.", "fg") end })
  end

  return M
end
