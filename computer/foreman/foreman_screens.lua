-- foreman_screens.lua  --  what the Overworld Foreman shows and takes typed, built only from the UI kit
-- (shared/ui*.lua, docs/design/foreman.md). Nothing here writes to a terminal.
--
-- Overview: a tile per miner (Canaries, Firecrests, Starlings) and buttons for all of them. Tap a tile to open the
-- miner: its status on the left, its layers and orders on the right (Info / Layers / Haul tabs on a compact
-- screen). Presets and the preset editor are pages of their own. Every view (the monitor and the computer's own
-- screen) keeps its own page.
--
--   P.screens = require("foreman_screens")      in the profile; shared/fm.lua calls it with the engine's environment F
-- It replaces the engine's draw, inputLoop and say (the MD and Nether Foremen keep the engine's own drawing code
-- until they move over). Data and orders stay in the engine: F.live, F.entry, F.order, F.pick, F.adjust ...
local ui = require("ui")
local slash = require("slash")

return function(F)
  local P = F.P
  local fit = ui.text.fit
  local FLEET_STALE = 30

  ---------------------------------------------------------------------------
  -- Per-view state
  ---------------------------------------------------------------------------
  local kviews = {}
  local states = {}   -- "term" | "monitor" -> { page = "overview"|"miner"|"presets"|"edit", id, tab, retired, edit, field }
  local function stateFor(v)
    local kind = v.side and "monitor" or "term"
    states[kind] = states[kind] or { page = "overview", tab = "status" }
    return states[kind]
  end
  local function termState() return states.term or stateFor({}) end

  ---------------------------------------------------------------------------
  -- Words and numbers
  ---------------------------------------------------------------------------
  local fmtNum, fmtAgo, pretty = F.fmtNum, F.fmtAgo, F.pretty
  local DIMS = F.DIMS

  local function nameOf(id)
    local d = F.entry(id)
    if d then return d.label or F.nameOf(d.num) end
    local l = F.live[id]
    return ((l and l.s.label) or "?") .. "?"
  end
  local function isStale(id)
    local l = F.live[id]
    return not l or os.clock() - l.seen > F.STALE
  end
  -- word and kit colour role for a miner's state
  local function stateOf(id)
    local d, l = F.entry(id), F.live[id]
    if d and d.retired then return "retired", "dim" end
    if not l then return "no signal", "dim" end
    if isStale(id) then return "lost", "dim" end
    local st = l.s.state
    local word = st == "mining" and "working" or tostring(st or "?")
    return word, ui.stateRole(word)
  end
  local function fuelFrac(s)
    if s and type(s.fuel) == "number" and type(s.fuelLimit) == "number" and s.fuelLimit > 0 then
      return s.fuel / s.fuelLimit
    end
  end
  local function posText(s)
    if not s or not s.pos then return "position unknown" end
    return ("%d %d %d"):format(s.pos.x, s.pos.y, s.pos.z)
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

  -- The engine's notices (built with colours) go to the kit's, in its tones
  local TONE = { [colours.lime] = "good", [colours.red] = "bad", [colours.orange] = "warn", [colours.yellow] = "warn",
                 [colours.purple] = "busy" }
  function F.say(text, colour) ui.say(text, colour == nil and "good" or TONE[colour] or "plain") end
  local say = F.say

  ---------------------------------------------------------------------------
  -- The header: how the dimension Foremen and storage are doing
  ---------------------------------------------------------------------------
  local function hubState()
    local kinds = {}
    for k in pairs(F.fleets or {}) do kinds[#kinds + 1] = k end
    table.sort(kinds)
    for _, k in ipairs(kinds) do
      local f = F.fleets[k]
      local short = f.m.short or k
      if os.clock() - f.seen > FLEET_STALE then return short .. " not heard", "warn" end
      if f.m.full then return short .. " output full", "warn" end
    end
    if #kinds == 0 then return "waiting", "warn" end
    return "ok", "good"
  end
  local function overviewHeader(v, st, nActive)
    local word, role = hubState()
    local storage = F.storageSeen and os.clock() - F.storageSeen < FLEET_STALE and "ok" or "?"
    v:header(st.retired and "FOREMAN retired" or P.title, { state = word, color = role,
      right = ("%d %s  storage %s"):format(nActive, nActive == 1 and P.unit or P.birds, storage) })
  end

  ---------------------------------------------------------------------------
  -- Navigation
  ---------------------------------------------------------------------------
  local function go(v, st, page, id)
    st.page, st.id = page, id or st.id
    v.page, v.sel = 1, nil
  end
  local function openMiner(v, st, id)
    if not F.entry(id) then
      local l = F.live[id]
      say(((l and l.s.label) or "It") .. ": old program. Hold Ctrl+R on it to update.", "warn")
      return
    end
    st.tab = nil
    go(v, st, "miner", id)
  end
  local function openEdit(st, idx, name)
    local p = idx and F.presetList()[idx] or { name = name or "", minY = -59, maxY = -48, r1 = 0, r2 = F.DEF_R2 }
    st.edit = { idx = idx, minY = p.minY, maxY = p.maxY, r1 = p.r1, r2 = p.r2, autofocus = p.name == "",
                f = ui.field({ hint = "name", max = F.NAME_MAX, text = p.name }) }
    st.page = "edit"
  end

  ---------------------------------------------------------------------------
  -- Overview
  ---------------------------------------------------------------------------
  local function tileFields(id)
    local l = F.live[id]
    local s = l and l.s
    local d = F.entry(id)
    local word, role = stateOf(id)
    local f = { name = nameOf(id), state = word, color = role, fuel = fuelFrac(s) }
    if f.fuel == nil then f.fuelText = "-" end
    if isStale(id) then
      f.stale = l and fmtAgo(math.floor(os.clock() - l.seen)) or "yet"
    elseif not d then
      f.activity = "No number: old program?"
    else
      f.activity = tostring(s.msg ~= "" and s.msg or F.rangeText(d.minY, d.maxY))
    end
    if s then
      f.numbers = ("Cargo %s/16   Y %s"):format(tostring(s.slots or "?"), tostring(s.y or "?"))
    end
    if l then
      f.seen = "seen " .. fmtAgo(math.floor(os.clock() - l.seen)) .. " ago"
      if s.dim and s.dim ~= "overworld" then f.seen = f.seen .. "  " .. (DIMS[s.dim] or s.dim) end
    end
    return f
  end

  local function drawOverview(v, st)
    local ids = F.digIds(st.retired)
    local active, retiredN = 0, 0
    for _, id in ipairs(F.allIds()) do if F.entry(id).retired then retiredN = retiredN + 1 else active = active + 1 end end
    if F.radioOK == false and not (ui.notice and ui.notice.tone == "bad") then
      ui.say(("No ender modem on me: %s can't hear me"):format(P.birds), "bad")
    end
    local typed = not v.side
    overviewHeader(v, st, active)
    if #ids == 0 then
      if st.retired then
        v:put(2, 4, fit(("No retired %s."):format(P.birds), v.W - 2), "dim", "bg")
      else
        local lines = P.emptyText or { ("No %s yet."):format(P.birds) }
        v:spinner_line(2, 4, v.W < 30 and ("Waiting for a " .. P.one) or ("Waiting for the first " .. P.one))
        local y = 6
        for _, line in ipairs(wrap(table.concat(lines, " "), v.W - 2)) do
          if y < v.H - 3 then v:put(2, y, line, "dim", "bg"); y = y + 1 end
        end
      end
    else
      v:tiles(ids, { grow = true, input = typed and 2 or true, on = function(id) openMiner(v, st, id) end,
                     render = tileFields })
    end
    local by = v.H - (typed and 2 or 1)
    if st.retired then
      v:search(st.field, { hint = "/ = commands", commands = F.commands })
      v:footer({ back = function() st.retired = false; v.page = 1 end })
      return
    end
    local list = {
      { label = "Presets", fn = function() F.ui.pset = nil; go(v, st, "presets") end },
      { label = "Reboot all", short = "Boot", fn = function()
        for _, id in ipairs(F.digIds(false)) do if F.entry(id) then F.requestReboot(id) end end
        say(("Reboot sent to every %s."):format(P.unit), "busy")
      end },
      { label = "Dock all", short = "Dock", confirm = true, style = "danger", fn = function()
        for _, id in ipairs(F.digIds(false)) do F.order(id, "dock") end
        say(("Sent every %s home."):format(P.unit), "warn")
      end },
    }
    if retiredN > 0 and v.W >= 56 then
      list[#list + 1] = { label = "Retired (" .. retiredN .. ")", fn = function() st.retired = true; v.page = 1 end }
    end
    v:buttons(2, by, list)
    if typed then v:search(st.field, { hint = "/ = commands (/help)", commands = F.commands }) end
    v:footer({})
  end

  ---------------------------------------------------------------------------
  -- One miner
  ---------------------------------------------------------------------------
  local function drawStatus(v, id, x, y, w, maxY)
    local d, l = F.entry(id), F.live[id]
    local s = l and l.s
    local function row(label, value, tone)
      if y <= maxY then v:kv(x, y, w, label, value, tone) end
      y = y + 1
    end
    if y <= maxY then
      v:put(x, y, fit(s and s.msg or (d.retired and "Retired" or "Waiting to hear from it"), w), "dim", "bg")
    end
    y = y + 1
    if s and (s.far or s.offPath or s.dockNote) then
      if s.dockNote and y <= maxY then v:alert(x, y, w, s.dockNote); y = y + 1 end
      if s.far and y <= maxY then v:alert(x, y, w, "Moved far from his dock: see his own screen."); y = y + 1
      elseif s.offPath and y <= maxY then v:alert(x, y, w, "Moved by hand. Goes home by a tunnel."); y = y + 1 end
    end
    y = y + 1
    if y <= maxY then
      local f = s and s.fuel
      v:bar(x, y, w, "Fuel", fuelFrac(s), { text = type(f) == "number" and fmtNum(f) or "-" })
    end
    y = y + 1
    if y <= maxY then
      local n = s and tonumber(s.slots)
      v:bar(x, y, w, "Cargo", n and n / 16 or nil, { kind = "cap", text = s and (tostring(s.slots or "?") .. "/16") or "-" })
    end
    y = y + 2
    row("Layer", s and s.layer and s.layers and (math.min(s.layer, s.layers) .. "/" .. s.layers) or "-")
    row("Chunk", s and s.chunk and s.chunks and ("%d of %d, ring %s"):format(s.chunk, s.chunks, tostring(s.ring)) or "-")
    row("Range", s and s.minY and (s.minY .. ".." .. s.maxY) or "-")
    row("At", posText(s))
    row(s and s.dim and (DIMS[s.dim] or s.dim) or "?", s and s.facing and ("facing " .. s.facing) or "", "dim")
    local hm = s and s.home
    row("Dock", hm and ("%d %d %d"):format(hm.x, hm.y, hm.z) or "-")
    local gear, warn = "-", false
    if s then
      local bits = {}
      if s.chunky then bits[#bits + 1] = "loader" end
      if s.box == "ok" then bits[#bits + 1] = "box" elseif s.box == "full" then bits[#bits + 1] = "box FULL"; warn = true end
      gear = #bits > 0 and table.concat(bits, " + ") or "none"
      if s.chunkyNote then gear, warn = s.chunkyNote, true end
    end
    row("Gear", gear, warn and "warn" or nil)
    if F.ownerLine then row("Foreman", F.ownerLine(id)) end
    row("Computer", "#" .. id, "dim")
    return y
  end

  local function drawHaul(v, id, x, y, w, maxY)
    local l = F.live[id]
    local haul = l and l.s.haul or {}
    y = v:section(x, y, w, "Last haul")
    if #haul == 0 then v:put(x, y, "Nothing yet", "bar", "bg") end
    for _, e in ipairs(haul) do
      if y > maxY then break end
      y = v:kv(x, y, w, pretty(e[1]), fmtNum(e[2]), "info")
    end
  end

  -- The layers: the presets as a column of pills, Min/Max Y and the rings, and the orders
  local function drawLayers(v, st, id, x, y, w, maxY)
    local d, l = F.entry(id), F.live[id]
    local s = l and l.s
    local presets = F.presetsOf(id)
    y = v:section(x, y, w, "Layers")
    v:buttons(x + w - 6, y - 1, { { label = "Edit", fn = function()
      F.ui.pset = (not F.reg[id]) and d._kind or nil
      go(v, st, "presets")
    end } })
    local narrow = v.wc == "narrow"
    -- Rows below the presets, at least: the four steppers (two rows each on a narrow screen), the hint, the buttons
    local minimal = (narrow and 8 or 4) + 1 + (narrow and 3 or 2)
    local free = maxY - y + 1
    local rows = math.max(1, math.min(#presets, free - minimal))
    local spare = free - minimal - rows
    local function gap() if spare >= 1 then spare = spare - 1; return 1 end return 0 end
    local pages = math.max(1, math.ceil(#presets / rows))
    v.pages = pages
    v.page = math.max(1, math.min(v.page or 1, pages))
    if #presets == 0 then v:put(x, y, "No presets: tap Edit", "dim", "bg"); y = y + 1 end
    for i = 1, rows do
      local p = presets[(v.page - 1) * rows + i]
      if not p then break end
      local r = p.minY .. ".." .. p.maxY
      local lab = p.name
      if w - 2 >= #p.name + #r + 2 then lab = p.name .. (" "):rep(w - 2 - #p.name - #r) .. r end
      lab = lab .. (" "):rep(w - 2 - #lab)
      v:buttons(x, y, { { label = fit(lab, w - 2), style = F.isSelected(d, p) and "on" or "idle",
        id = "preset:" .. i, fn = function() F.pick(id, p.minY, p.maxY, p.r1, p.r2) end } }, { maxx = x + w - 1 })
      y = y + 1
    end
    y = y + gap()
    local small = w < 34
    local function step(label, key, lo, hi)
      local _, last = v:stepper(x, y, label, d[key], { min = lo, max = hi, id = "step:" .. key, small = small,
        on = function(n) F.adjust(id, d, key, n - d[key]) end })
      y = last + 1
    end
    step(small and "Min Y " or "Min Y    ", "pMin", F.Y_MIN, F.Y_MAX)
    step(small and "Max Y " or "Max Y    ", "pMax", F.Y_MIN, F.Y_MAX)
    step(small and "Ring>=" or "From ring", "pR1", 0, F.RING_CAP)
    step(small and "Ring<=" or "To ring  ", "pR2", 0, F.RING_CAP)
    local hint, tone = ("%d chunks, %dx%d"):format(F.chunkCount(d.pR1, d.pR2), F.sq(d.pR2), F.sq(d.pR2)), "dim"
    if d.pR1 > 0 then hint = hint .. (" minus %dx%d"):format(F.sq(d.pR1 - 1), F.sq(d.pR1 - 1)) end
    if d.pR2 > 1 and s and not s.chunky then hint, tone = "Past ring 1: needs a chunk controller", "warn" end
    if s and s.seq ~= d.seq then hint, tone = "Sending...", "gold"
    elseif s and s.offPath then hint, tone = "START/DOCK: send it home", "warn"
    elseif d.want == "run" and (d.minY ~= d.pMin or d.maxY ~= d.pMax or d.r1 ~= d.pR1 or d.r2 ~= d.pR2) then
      hint, tone = "START to switch", "warn"
    end
    v:put(x, y, fit(hint, w), tone, "bg")
    y = y + 1 + gap()
    local label = nameOf(id)
    local tight = w < 27   -- three pills in a row need 27 cells
    local _, last = v:buttons(x, y, {
      { label = "START", style = "primary", fn = function() F.order(id, "run"); say(label .. ": START sent.", "good") end },
      { label = "STOP + DOCK", short = "STOP", fn = function() F.order(id, "dock"); say(label .. ": heading home.", "warn") end },
    }, { maxx = x + w - 1 })
    v:buttons(x, last + 1 + gap(), {
      { label = tight and "Boot" or "Reboot", confirm = true, busy = d.reboot ~= nil, fn = function()
        F.requestReboot(id); say(label .. ": reboot sent.", "busy") end },
      { label = tight and "Dock" or "Re-dock", busy = d.redock ~= nil, fn = function()
        F.requestRedock(id); say(label .. ": re-dock sent.", "busy") end },
      { label = "Retire", confirm = true, style = "danger", fn = function()
        F.retire(id); go(v, st, "overview")
        say(label .. " retired for good.", "warn")
      end },
    }, { maxx = x + w - 1 })
  end

  local TABS_WIDE = { { id = "status", label = "Status" }, { id = "haul", label = "Haul" } }
  local TABS_COMPACT = { { id = "info", label = "Info" }, { id = "layers", label = "Layers", short = "Lay" },
                         { id = "haul", label = "Haul" } }

  local function drawMiner(v, st)
    local id = st.id
    local d, l = F.entry(id), F.live[id]
    if not d then st.page = "overview"; return drawOverview(v, st) end
    local typed = not v.side
    local W, bottom = v.W, v.H - 1 - (typed and 1 or 0)
    local word, role = stateOf(id)
    local wide = W >= 44
    local retired = d.retired
    v:header(nameOf(id), { state = word, color = role,
      right = l and ("seen " .. fmtAgo(math.floor(os.clock() - l.seen)) .. " ago") or "never heard" })
    local tabs = wide and TABS_WIDE or TABS_COMPACT
    if retired and not wide then tabs = { TABS_COMPACT[1], TABS_COMPACT[3] } end
    local tab = st.tab
    local ok = false
    for _, t in ipairs(tabs) do if t.id == tab then ok = true end end
    if not ok then tab = tabs[1].id; st.tab = tab end
    if tab == "haul" then
      drawHaul(v, id, 2, 3, W - 2, bottom)
    elseif wide then
      local lw = math.floor((W - 3) / 2)
      drawStatus(v, id, 2, 3, lw, bottom)
      if not retired then drawLayers(v, st, id, lw + 3, 3, W - lw - 3, bottom) end
    elseif tab == "layers" then
      drawLayers(v, st, id, 2, 3, W - 2, bottom)
    else
      drawStatus(v, id, 2, 3, W - 2, bottom)
    end
    if typed then v:search(st.field, { hint = "/ = commands (/help)", commands = F.commands }) end
    v:footer({ back = function() go(v, st, "overview") end, tabs = tabs, tab = tab,
               on_tab = function(t) st.tab = t end })
  end

  ---------------------------------------------------------------------------
  -- Presets and the editor
  ---------------------------------------------------------------------------
  local function ringShort(p) return "r" .. p.r1 .. "-" .. p.r2 end

  local function drawPresets(v, st)
    local list = F.presetList()
    local typed = not v.side
    local setName = F.presetSetName and F.presetSetName()
    v:header(F.nextPresetSet and ("PRESETS of " .. setName) or "PRESETS",
      { right = ("%d preset%s"):format(#list, #list == 1 and "" or "s") })
    local function selected()
      local idx = v.sel
      if not idx or not list[idx] then say("Tap a preset first.", "warn"); return end
      return idx
    end
    local btns = {
      { label = "+ New", style = "primary", fn = function() openEdit(st, nil) end },
      { label = "Edit", fn = function() local i = selected(); if i then openEdit(st, i) end end },
      { label = "Duplicate", short = "Dup", fn = function()
        local i = selected()
        if not i then return end
        local p, name = list[i], list[i].name .. " 2"
        local n = 2
        while F.findPreset(name) and F.presetList()[F.findPreset(name)].name:lower() == name:lower() do
          n = n + 1; name = p.name .. " " .. n
        end
        table.insert(list, i + 1, { name = name:sub(1, F.NAME_MAX), minY = p.minY, maxY = p.maxY, r1 = p.r1, r2 = p.r2 })
        F.presetsChanged(); v.sel = i + 1
        say("Copied " .. p.name .. ".", "good")
      end },
      { label = "Up", fn = function() local i = selected(); if i and i > 1 then F.movePreset(i, -1); v.sel = i - 1 end end },
      { label = "Down", short = "Dn", fn = function()
        local i = selected(); if i and i < #list then F.movePreset(i, 1); v.sel = i + 1 end end },
    }
    if F.nextPresetSet then
      btns[#btns + 1] = { label = "Of: " .. setName, fn = function() F.nextPresetSet(); v.sel, v.page = nil, 1 end }
    end
    v:buttons(2, 3, btns)
    local rows = {}
    for i, p in ipairs(list) do
      rows[i] = { name = p.name, value = ("%d..%d  %s"):format(p.minY, p.maxY, ringShort(p)), idx = i }
    end
    if #rows == 0 then v:put(2, 6, "No presets yet: + New", "dim", "bg")
    else v:list(rows, { top = 5, input = typed, on = function(row) openEdit(st, row.idx) end }) end
    if typed then v:search(st.field, { hint = "/ = commands (/help)", commands = F.commands }) end
    v:footer({ back = function() go(v, st, "overview") end })
  end

  local function drawEdit(v, st)
    local e = st.edit
    if not e then st.page = "presets"; return drawPresets(v, st) end
    v:header(e.idx and "EDIT PRESET" or "NEW PRESET")
    if e.autofocus and not v.side then v.focus = "field:Name"; e.autofocus = nil end   -- a blank one: type the name at once
    local roomy = v.H > 16
    local y = 3
    v:field(2, y, "Name", math.min(F.NAME_MAX + 2, v.W - 10), e.f)
    y = y + (roomy and 2 or 1)
    local function step(label, key, lo, hi)
      local _, last = v:stepper(2, y, label, e[key], { min = lo, max = hi, id = "edit:" .. key,
        on = function(n) e[key] = n end })
      y = last + 1
    end
    step("Min Y    ", "minY", F.Y_MIN, F.Y_MAX)
    step("Max Y    ", "maxY", F.Y_MIN, F.Y_MAX)
    if roomy then y = y + 1 end
    step("From ring", "r1", 0, F.RING_CAP)
    step("To ring  ", "r2", 0, F.RING_CAP)
    if roomy then y = y + 1 end
    local passes = math.max(1, math.ceil((e.maxY - e.minY + 1) / 3))
    local text = ("%d pass%s of 3 levels, %s"):format(passes, passes == 1 and "" or "es", F.ringText(e.r1, e.r2))
    text = text .. "." .. (e.r2 > 1 and " Past ring 1 needs a chunk loader." or "")
    for _, line in ipairs(wrap(text, v.W - 2)) do
      if y < v.H - 3 then v:put(2, y, fit(line, v.W - 2), "dim", "bg"); y = y + 1 end
    end
    y = math.min(y + (roomy and 1 or 0), v.H - 3)
    local list = {
      { label = "Save", style = "primary", fn = function()
        local old = F.ui.edit
        local name = e.f.text:gsub("^%s+", ""):gsub("%s+$", "")
        F.ui.edit = { idx = e.idx, name = name, minY = e.minY, maxY = e.maxY, r1 = e.r1, r2 = e.r2 }
        F.savePreset()
        local failed = F.ui.edit
        F.ui.edit = old
        if failed then say(failed.err or "Can't save that", "bad") else st.edit, st.page = nil, "presets" end
      end },
      { label = "Cancel", fn = function() st.edit, st.page = nil, "presets" end },
    }
    if e.idx then
      list[#list + 1] = { label = "Delete", confirm = true, style = "danger", fn = function()
        F.deletePreset(e.idx); st.edit, st.page = nil, "presets"
      end }
    end
    v:buttons(2, y, list)
    if not v.side then v:search(st.field, { hint = "/ = commands (/help)", commands = F.commands }) end
    v:footer({ back = function() st.edit, st.page = nil, "presets" end })
  end

  ---------------------------------------------------------------------------
  -- Typed commands (computer only)
  ---------------------------------------------------------------------------
  local cmds = slash.new()
  local function alias(name, ...) for _, a in ipairs({ ... }) do cmds.byName[a] = cmds.byName[name] end end
  local function home()
    local st, v = termState(), kviews[1]
    st.page, st.edit, st.retired = "overview", nil, false
    if v then v.page, v.sel = 1, nil end
  end
  -- miners a name, number or "all" picks out
  local function pickMiners(word, includeRetired)
    local a, out = word:lower(), {}
    for _, id in ipairs(F.allIds()) do
      local d = F.entry(id)
      if d and (includeRetired or not d.retired) then
        local lbl = (d.label or F.nameOf(d.num)):lower()
        if a == "all" or lbl == a or tonumber(a) == d.num or lbl:find(a, 1, true) then out[#out + 1] = id end
      end
    end
    return out
  end
  cmds:add({ name = "presets", help = "edit the layer presets", max = 0, run = function()
    local st = termState(); F.ui.pset = nil; st.page, st.edit = "presets", nil; return true end })
  alias("presets", "preset", "settings", "p")
  cmds:add({ name = "home", help = "back to the overview", max = 0, run = function() home(); return true end })
  alias("home", "back", "overview")
  cmds:add({ name = "retired", help = "list the retired " .. P.birds, max = 0, run = function()
    local st = termState(); home(); st.retired = true; return true end })
  cmds:add({ name = "new", args = "[name]", help = "add a preset", run = function(a) openEdit(termState(), nil, a.raw); return true end })
  alias("new", "add")
  cmds:add({ name = "edit", args = "<name>", help = "edit a preset", min = 1, run = function(a)
    local idx = F.findPreset(a.raw)
    if not idx then return false, "No preset called " .. a.raw end
    openEdit(termState(), idx); return true
  end })
  cmds:add({ name = "delete", args = "<name>", help = "delete a preset", min = 1,
    run = function(a)
      local idx = F.findPreset(a.raw)
      if not idx then return false, "No preset called " .. a.raw end
      openEdit(termState(), idx)
      return true, "Tap Delete, then Sure?, to delete " .. F.presetList()[idx].name, "warn"
    end })
  alias("delete", "remove", "del")
  cmds:add({ name = "reboot", args = "<" .. P.one .. "|all>", help = "reboot one or all", min = 1,
    run = function(a)
      local hits = pickMiners(a.raw)
      if #hits == 0 then return false, ("No %s matches %s"):format(P.one, a.raw) end
      if a.raw:lower() ~= "all" and #hits > 1 then return false, ("%s matches %d %s: be more exact"):format(a.raw, #hits, P.birds) end
      for _, id in ipairs(hits) do F.requestReboot(id) end
      return true, #hits == 1 and (nameOf(hits[1]) .. ": reboot sent.") or ("Reboot sent to %d %s."):format(#hits, P.birds), "busy"
    end })
  alias("reboot", "restart")
  cmds:add({ name = "redock", args = "<" .. P.one .. "|all>", help = "re-dock one or all", min = 1,
    run = function(a)
      local hits = pickMiners(a.raw)
      if #hits == 0 then return false, ("No %s matches %s"):format(P.one, a.raw) end
      for _, id in ipairs(hits) do F.requestRedock(id) end
      return true, ("Re-dock sent to %d: each sets his dock up where he stands."):format(#hits), "busy"
    end })
  cmds:add({ name = "help", args = "[command]", help = "every command", max = 1, run = function(a)
    local c = a.words[1] and cmds.byName[a.words[1]:lower():gsub("^/", "")]
    if a.words[1] and not c then return false, "No command " .. a.words[1] end
    if c then return true, cmds:usage(c) .. ": " .. c.help, "plain" end
    local st = termState(); home(); st.page = "help"
    return true
  end })
  F.commands = cmds:commands()
  F.cmds = cmds

  ---------------------------------------------------------------------------
  -- Drawing, monitors and the event loop
  ---------------------------------------------------------------------------
  local function drawHelp(v, st)
    local rows = {}
    for _, c in ipairs(cmds.list) do
      rows[#rows + 1] = { key = "/" .. c.name .. (c.args and (" " .. c.args) or ""), value = c.help }
    end
    rows[#rows + 1] = { blank = true }
    rows[#rows + 1] = { text = "Type / on the computer for the list; Tab completes.", tone = "dim" }
    v:report({ title = "COMMANDS", back = function() go(v, st, "overview") end, rows = rows })
    if not v.side then v:search(st.field, { hint = "/ = commands (/help)", commands = F.commands }) end
  end

  local function draw(v)
    local st = stateFor(v)
    st.field = st.field or ui.field({ hint = "/ = commands", on_commit = function(text)
      st.field.text = ""
      if text ~= "" then cmds:exec(text) end
    end })
    if st.page == "miner" then drawMiner(v, st)
    elseif st.page == "presets" then drawPresets(v, st)
    elseif st.page == "edit" then drawEdit(v, st)
    elseif st.page == "help" then drawHelp(v, st)
    else drawOverview(v, st) end
  end

  local function syncMonitor()
    local m, side = F.findMonitor()
    if kviews[2] and kviews[2].side == side then kviews[2].t = m or kviews[2].t; kviews[2]:measure(); return end
    kviews[2] = m and ui.view(m, { side = side }) or nil
  end

  -- The engine asks for a redraw after every radio message and state change: wake the loop (it throttles)
  function F.draw() os.queueEvent("fm_draw") end

  function F.inputLoop()
    kviews[1] = ui.view(term.current())
    syncMonitor()
    ui.run(kviews, draw, { tick = 1, on_event = function(e)
      if e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then syncMonitor() end
    end })
  end
end
