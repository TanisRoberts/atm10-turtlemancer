-- opwizard.lua  --  the setup wizard for a new reactor (design: docs/design/operator.md, "Setup wizard", style A with Find it).
-- Four pages: what was found, the inlet, the outlet, check and name. On the inlet and outlet pages `Find it` watches the
-- ports while you drop one item into the right one by hand (the Operator only reads; it never moves items).
-- The state lives in the view: v.op.w = { step, input, output, name, find = { role, base, found } }.
local ui = require("ui")
local D = require("opdraw")
local floor, max, min = math.floor, math.max, math.min

return function(S)
  local M = {}

  local function newState(r) return { step = 1, name = r.label, search = nil, find = nil } end

  -- Open the wizard for a reactor on this view
  function M.open(v, r)
    local o = v.op
    o.page, o.rid, o.w, v.page = "wizard", r.label, newState(r), 1
  end

  local function steps(v) return v.W >= 40 and "step %d of 4" or "%d/4" end

  local function pills(v, labels)         -- right-aligned pills on the footer row; each { label, short, style, fn, enabled }
    local narrow = v.wc == "narrow"
    local total = 0
    for _, b in ipairs(labels) do total = total + #(narrow and b.short or b.label) + (v.colour and 2 or 4) + 1 end
    local list = {}
    for _, b in ipairs(labels) do list[#list + 1] = b end
    v:buttons(max(v.W - total, 2), v.H, list)
  end

  local function pageFound(v, ctx, r, w)
    local W = v.W
    local wide = W >= 40
    v:header("NEW REACTOR", { state = steps(v):format(1), color = "dim" })
    local y = D.section(v, 2, 3, W - 2, wide and "FOUND ON THE CABLE" or "FOUND")
    local cands = ctx.ctl.candidates(r.label)
    local ports = {}
    for _, c in ipairs(cands) do if c.port then ports[#ports + 1] = c.name end end
    local function row(k, val)
      v:put(2, y, "+", "good", "bg"); v:kv(4, y, W - 4, k, val); y = y + 1
    end
    row("Reactor", wide and tostring(r.id or r.label) or r.label)
    row("Control rods", r.rodCount and (r.rodCount .. " found") or "?")
    row("Access ports", #ports .. " found")
    if #ports > 0 then v:put(4, y, D.fit(table.concat(ports, "  "), W - 5), "dim", "bg") end
    y = y + 2
    if wide then
      v:put(2, y, "This reactor isn't set up yet. Until it is,", "fg", "bg")
      v:put(2, y + 1, "the Operator reads it but does not switch it.", "fg", "bg")
      y = y + 3
      y = D.section(v, 2, y, W - 2, "WHAT WE'LL ASK")
      for _, t in ipairs({ "1  Which port feeds fuel in", "2  Which port takes waste out", "3  A name, and the switching points" }) do
        v:put(3, y, t, "fg", "bg"); y = y + 1
      end
    else
      v:put(2, y, "Not set up yet.", "fg", "bg")
      v:put(2, y + 1, "Not switched until it is.", "fg", "bg")
      y = y + 3
      y = D.section(v, 2, y, W - 2, "WE'LL ASK")
      for _, t in ipairs({ "1 Fuel in port", "2 Waste out port", "3 Name, switching" }) do v:put(3, y, t, "fg", "bg"); y = y + 1 end
    end
    local o = v.op
    v:buttons(2, v.H, { { label = "Not now", fn = function() o.page, o.w = "overview", nil end } })
    v:buttons(W - 9, v.H, { { label = "Start >", short = "Start", style = "primary", fn = function() w.step, v.sel = 2, nil end } })
  end

  -- Step 2 (inlet) and 3 (outlet): the device list, with Find it
  local function pagePort(v, ctx, r, w, role)
    local W, H = v.W, v.H
    local o = v.op
    local step = role == "input" and 2 or 3
    v:header("NEW REACTOR", { state = steps(v):format(step), color = "dim" })
    v:put(2, 3, D.fit(role == "input" and (W >= 40 and "Which port feeds fuel IN?" or "Fuel IN port?") or (W >= 40 and "Which port takes waste OUT?" or "Waste OUT port?"), W - 2), "fg", "bg")
    if W >= 40 then
      v:put(2, 4, role == "input" and "Uranium goes in here. Storage fills it." or "Cyanite comes out here. Storage empties it.", "dim", "bg")
    end
    w.search = w.search or ui.field{ hint = "type to narrow the list", max = 30 }
    local want = w.search.text:lower()
    local rows = {}
    for _, c in ipairs(ctx.ctl.candidates(r.label)) do
      local mine = (role == "output" and c.name == w.input)
      if not mine and (want == "" or c.name:lower():find(want, 1, true) or (c.holds or c.type):lower():find(want, 1, true)) then
        local tag = (c.guess == role) and "  suggested" or ""
        local taken = c.taken and not c.taken:find(r.label, 1, true) and ("  (" .. c.taken .. ")") or ""
        rows[#rows + 1] = { name = c.name .. tag .. taken, value = c.holds or c.type, state = (c.guess == role) and "good" or "bar", id = c.name }
      end
    end
    local function pick(row) w[role] = row.id; w.search, w.step, v.sel, v.page = nil, step + 1, nil, 1 end
    v:list(rows, { input = not v.side, on = pick, top = W >= 40 and 6 or 5 })
    if #rows == 0 then v:put(3, W >= 40 and 6 or 5, "Nothing matches.", "dim", "bg") end
    v:footer({ back = function() w.step, w.search, v.sel = step - 1, nil, nil end })
    pills(v, {
      { label = "Find it", short = "Find", fn = function() w.find = { role = role, base = ctx.ctl.snapshot() }; w.search = nil end },
      { label = "Pick >", short = "Pick", style = "primary", enabled = v.sel ~= nil and rows[v.sel] ~= nil,
        fn = function() if v.sel and rows[v.sel] then pick(rows[v.sel]) end end },
    })
    if not v.side then v:search(w.search, { hint = "type to narrow, tap a device twice to pick it" }) end
  end

  -- "Find it": watch the devices while an item is dropped into the right one
  local function pageFind(v, ctx, r, w)
    local W, H = v.W, v.H
    local f = w.find
    local role = f.role
    local step = role == "input" and 2 or 3
    v:header("NEW REACTOR", { state = steps(v):format(step), color = "dim" })
    local what
    if role == "input" then
      what = W >= 40 and { "Drop ONE uranium ingot into the fuel inlet port.", "Put it in by hand. The Operator only watches." }
        or { "Drop ONE uranium", "ingot into the fuel", "inlet port." }
    else
      what = W >= 40 and { "Drop ONE item into the waste outlet port.", "Anything will do. Take it out again after." }
        or { "Drop ONE item into", "the waste outlet", "port. Take it out after." }
    end
    local y = 4
    for i, l in ipairs(what) do v:put(2, y, l, i == 1 and "fg" or "dim", "bg"); y = y + 1 end
    y = y + 1
    local now = ctx.ctl.snapshot()
    local names = {}
    for n in pairs(now) do names[#names + 1] = n end
    table.sort(names)
    if not f.found then
      for _, n in ipairs(names) do
        if (now[n] or 0) > (f.base[n] or 0) and not (role == "output" and n == w.input) and n ~= w.input then f.found = n; break end
      end
    end
    if #names == 0 then
      v:put(2, y, D.fit("Can't read what is in any port. Pick from the list.", W - 2), "warn", "bg")
    elseif f.found then
      v:put(2, y, "+", "good", "bg"); v:put(4, y, D.fit("Found: " .. f.found .. " now holds more", W - 4), "good", "bg")
    else
      v:spinner_line(2, y, ("Watching %d ports..."):format(#names))
    end
    y = y + 2
    for i, n in ipairs(names) do
      if y + i - 1 > H - 2 then break end
      local hit = f.found == n
      v:put(2, y + i - 1, D.fit(n, W - 12), hit and "fg" or "dim", "bg")
      local txt = hit and "found" or (now[n] .. " items")
      v:put(W - #txt - 1, y + i - 1, txt, hit and "good" or "dim", "bg")
    end
    if f.found then
      v:buttons(2, H, { { label = "Not it", fn = function() f.found, f.base = nil, ctx.ctl.snapshot() end } })
      pills(v, { { label = "That's it >", short = "Yes >", style = "primary", fn = function()
        w[role], w.step, w.find, w.search, v.sel = f.found, step + 1, nil, nil, nil
      end } })
    else
      v:footer({ back = function() w.find = nil end })
      pills(v, { { label = "Pick from list", short = "List", fn = function() w.find = nil end } })
    end
  end

  local function pageConfirm(v, ctx, r, w)
    local W, H = v.W, v.H
    v:header("NEW REACTOR", { state = steps(v):format(4), color = "dim" })
    local y = D.section(v, 2, 3, W - 2, "CHECK IT")
    w.nameField = w.nameField or ui.field{ text = w.name, hint = "name", max = 20 }
    w.name = w.nameField.text
    v:field(2, y, "Name", min(W - 8, 24), w.nameField)
    y = y + 2
    local cands = {}
    for _, c in ipairs(ctx.ctl.candidates(r.label)) do cands[c.name] = c end
    local function port(label, name)
      v:put(2, y, "+", "good", "bg")
      local c = cands[name]
      local val = name .. ((c and c.holds and W >= 40) and (" (" .. c.holds .. ")") or "")
      y = v:kv(4, y, W - 4, label, val)
    end
    port("Fuel inlet", w.input)
    port("Waste outlet", w.output)
    y = D.section(v, 2, y + 1, W - 2, "SWITCHING")
    y = v:kv(2, y, W - 2, "ON below", floor((r.onBelow or 0.3) * 100 + 0.5) .. "%")
    y = v:kv(2, y, W - 2, "OFF above", floor((r.offAbove or 0.9) * 100 + 0.5) .. "%")
    if W >= 40 then v:put(2, y + 1, "Change these any time on the Set tab.", "dim", "bg") end
    v:buttons(2, H, { { label = "Back", fn = function() w.step = 3 end } })
    v:buttons(W - 10, H, { { label = "Finish", style = "primary", fn = function()
      local msg = ctx.ctl.finishSetup(r.label, { input = w.input, output = w.output, name = w.nameField.text })
      if msg then ui.say(msg, "warn"); return end
      local o = v.op
      o.rid = (w.nameField.text ~= "" and w.nameField.text) or r.label
      o.page, o.w = "overview", nil
      ui.say((o.rid) .. " is set up", "good")
    end } })
  end

  function M.draw(v, ctx, r)
    local o = v.op
    o.w = o.w or newState(r)
    local w = o.w
    if w.step == 1 then pageFound(v, ctx, r, w)
    elseif w.step == 2 and w.find then pageFind(v, ctx, r, w)
    elseif w.step == 3 and w.find then pageFind(v, ctx, r, w)
    elseif w.step == 2 then pagePort(v, ctx, r, w, "input")
    elseif w.step == 3 then pagePort(v, ctx, r, w, "output")
    else pageConfirm(v, ctx, r, w) end
  end

  return M
end
