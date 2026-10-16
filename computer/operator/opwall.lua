-- opwall.lua  --  the Operator on a big monitor (164x81 and the like): everything at once. Power Grid at the left,
-- up to three whole reactor panels across, then the plant buffer chart and the recent events. More than three
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

  local function left(v, ctx, R, t)
    local H = v.H
    v:boardHeader(1, 3, LEFT, "POWER GRID")
    local x, w = 2, LEFT - 2
    v:put(x, 4, "OUTPUT", "dim", "bg")
    v:put(x, 5, D.num(t.fe or 0) .. " FE/t", "fg", "bg")
    v:put(x + w - #(t.n .. " reactors") + (t.n == 1 and 1 or 0), 5, t.n .. (t.n == 1 and " reactor" or " reactors"), "dim", "bg")
    v:put(x, 7, "BUFFER", "dim", "bg")
    v:put(x + w - #D.pct(t.buf), 7, D.pct(t.buf), "fg", "bg")
    D.track(v, x, 8, w, t.buf, "good")
    local r1 = R[1] or {}
    local on, off = r1.onBelow or 0.3, r1.offAbove or 0.9
    local onx, offx = x + floor(on * w), x + floor(off * w)
    v:put(onx, 9, "^on " .. floor(on * 100 + 0.5) .. "%", "dim", "bg")
    v:put(min(offx, x + w - 8), 9, "^off " .. floor(off * 100 + 0.5) .. "%", "dim", "bg")
    local y = D.section(v, x, 11, w, "PLANT")
    local rows = {
      { "Net", t.net and ((t.net >= 0 and "+" or "-") .. D.num(math.abs(t.net)) .. " FE/t") or "-" },
      { "Reactors on", ("%d of %d"):format(t.on, t.n) },
      { "Average level", t.level and (floor(t.level + 0.5) .. "%") or "-" },
      { "Fuel", t.fuel and D.pct(t.fuel) or "?" },
      { "Supply (Storage)", t.supply and (D.num(t.supply) .. " ingots") or "unknown", t.supply == nil and "warn" or nil },
      { "Hottest casing", t.hot and (floor(t.hot + 0.5) .. "C") or "?" },
      { "Waste outlets", t.wasteFull > 0 and (t.wasteFull .. " full") or "clear", t.wasteFull > 0 and "bad" or nil },
    }
    if t.avgHour then rows[#rows + 1] = { "Output last hour", D.num(t.avgHour) .. " avg" } end
    y = rowsFor(v, x, y, w, rows)
    y = D.section(v, x, y + 1, w, "NEEDS ATTENTION")
    local list = alerts(R)
    if #list == 0 then v:put(x, y, "All good", "good", "bg"); y = y + 1 end
    for _, a in ipairs(list) do
      for _, line in ipairs(S.wrap(a.text, w - 2)) do
        if y <= H - 4 then v:alert(x, y, w, line, a.tone) end
        y = y + 1
      end
    end
    if t.problems > 0 then v:put(x, H - 2, t.problems .. " needs fixing", "warn", "bg") end
    for yy = 3, H - 1 do v:put(LEFT + 1, yy, " ", "fg", "bar") end
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
    y = y + 15
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
    y = D.section(v, cx, y + 2, cw, "BUFFER")
    y = D.buffer(v, cx, y, cw, r.buf, r.onBelow or 0.3, r.offAbove or 0.9, "Buffer")
    y = D.section(v, cx, y + 1, cw, "READINGS")
    y = rowsFor(v, cx, y, cw, {
      { "Output", D.num(r.fe or 0) .. " FE/t" },
      { "Fuel", r.uranium and (S.fuelPct(r) .. "  " .. D.num(r.uranium) .. " in inlet") or S.fuelPct(r) },
      { "Fuel temperature", D.num(r.fuelTemp) .. "C" },
      { "Casing temperature", D.num(r.casing) .. "C" },
      { "Waste outlet", r.wasteStuck and "full" or (r.outlet and r.outlet > 0 and (r.outlet .. " waiting") or "empty"), r.wasteStuck and "bad" or nil },
    })
    local ok, miss, unk = S.counts(r)
    y = D.section(v, cx, y + 1, cw, ("NEEDS  %d ok  %d !  %d ?"):format(ok, miss, unk))
    y = S.needsList(v, cx, y, cw, 40, r, { open = function(n)
      ui.say(n.title .. ": " .. (n.was or n.why), n.state == "missing" and "bad" or "warn")
    end })
    for yy = y0, y - 1 do
      if v.colour then v:put(x, yy, " ", "fg", role) else v:put(x, yy, "|", "fg", "bg") end
    end
    return y
  end

  local function chart(v, ctx, rec, R, x, y, w, room)
    local p = rec.plant or {}
    local hist, events = p.hist or {}, p.events or {}
    local wantEvents = #events > 0
    local evRows = wantEvents and (1 + min(#events, 8)) or 0
    local ch = min(14, room - evRows - 4)
    if #hist >= 2 and ch >= 4 then
      y = D.section(v, x + 1, y, w - 2, "PLANT BUFFER, LAST 30 MINUTES")
      local px, pw = x + 6, w - 8
      local r1 = R[1] or {}
      local on, off = r1.onBelow or 0.3, r1.offAbove or 0.9
      local rowOn = max(1, min(ch, ch - floor(on * ch + 0.5) + 1))
      local rowOff = max(1, min(ch, ch - floor(off * ch + 0.5) + 1))
      local n = #hist
      for row = 1, ch do
        local cells = {}
        for c = 1, pw do
          local idx = n - floor((pw - c) * 120 / pw)
          local fillH = idx >= 1 and idx <= n and floor(hist[idx] / 100 * ch + 0.5) or 0
          if (ch - row + 1) <= fillH then cells[c] = { " ", "fg", "good" }
          elseif row == rowOn or row == rowOff then cells[c] = { ".", "dim", "bg" }
          else cells[c] = { " ", "fg", "bg" } end
        end
        v:cells(px, y + row - 1, cells)
      end
      v:put(x + 1, y, "100%", "dim", "bg")
      v:put(x + 1, y + rowOff - 1, floor(off * 100 + 0.5) .. "%", "dim", "bg")
      v:put(x + 1, y + rowOn - 1, floor(on * 100 + 0.5) .. "%", "dim", "bg")
      v:put(x + 3, y + ch - 1, "0%", "dim", "bg")
      y = y + ch
      v:put(px, y, "-30 min", "dim", "bg")
      v:put(px + floor(pw / 2) - 3, y, "-15 min", "dim", "bg")
      v:put(px + pw - 3, y, "now", "dim", "bg")
      y = y + 2
    end
    if wantEvents and y + evRows <= v.H - 2 then
      y = D.section(v, x + 1, y, w - 2, "RECENT")
      for i = 1, min(#events, 8) do
        local e = events[i]
        v:put(x + 1, y, e.at or "", "dim", "bg")
        v:put(x + 8, y, D.fit(e.who or "", 10), "fg", "bg")
        v:put(x + 19, y, D.fit(e.text or "", w - 20), "fg", "bg")
        y = y + 1
      end
    end
  end

  function M.draw(v, ctx, R, t)
    local rec, W, H = ctx.rec, v.W, v.H
    local word, tone = "idle", "idle"
    if t.problems > 0 then word, tone = "waiting", "warn" elseif t.on > 0 then word, tone = "running", "good" end
    v:header("OPERATOR", { state = word, color = tone, right = ("%d reactor%s  %d problem%s"):format(t.n, t.n == 1 and "" or "s",
      t.problems, t.problems == 1 and "" or "s") })
    left(v, ctx, R, t)
    local x0 = LEFT + 2
    v:boardHeader(LEFT + 2, 3, W - LEFT - 1, "REACTORS")
    local endY = 4
    if #R <= 3 then
      local pw = floor((W - LEFT - 2) / 3)
      for i, r in ipairs(R) do endY = max(endY, panel(v, ctx, r, x0 + (i - 1) * pw, 4, pw - 1)) end
    else
      local cols = max(1, floor((W - x0) / 35))
      for i, r in ipairs(R) do
        local col, row = (i - 1) % cols, floor((i - 1) / cols)
        local y = 4 + row * 6
        if y + 5 < H - 20 then
          S.tile(v, x0 + col * 35, y, 33, r, { rows = 5 })
          endY = max(endY, y + 6)
        end
      end
    end
    chart(v, ctx, rec, R, x0 - 1, endY + 1, W - x0 + 2, H - endY - 3)
    v:footer({ back = function() ui.say("This is the top page. Hold Ctrl+T to stop the Operator.", "fg") end })
  end

  return M
end
