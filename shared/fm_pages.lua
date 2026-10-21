-- fm_pages.lua  --  Foreman engine: the overview and one miner's page (status, last haul, layers and orders).
-- A part of fm.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
openAssign = nil -- defined with the commands (the /assign screen needs the computer's keyboard)

-- One line about the barrels, for the overview's second row (the Overworld Foreman: about the dimensions)
function barrelLine()
  if not P.barrels then return hubLine() end
  if #cfg.docks == 0 or #cfg.outputs == 0 then
    return "Barrels: tap Barrels (or /assign) to give them jobs", K.orange
  end
  if barrel.moveErr then return barrel.moveErr, K.red end
  if barrel.outFull and #cfg.overflows > 0 then
    return ("Output full: haul waits in Overflow (%d/%d slots)"):format(barrel.overflow.used, barrel.overflow.size), K.orange
  end
  if barrel.outFull then return "Output full: is the hopper into the ender chest flowing?", K.red end
  if barrel.factoryFull then return "Factory out full: no room in Stock for more lava", K.orange end
  if #cfg.stocks == 0 then
    return P.neverHome and "No Stock barrel: buckets wait in the docks and the factory"
      or "No Stock barrel: everything goes home, spare buckets too", K.orange
  end
  local parts = {}
  for _, f in ipairs({ { "minecraft:bucket", "buckets" }, { "minecraft:lava_bucket", "lava" } }) do
    parts[#parts + 1] = ("%d %s"):format(barrel.stock[f[1]] or 0, f[2])
  end
  local fuel = 0
  for _, f in ipairs(FUELS) do fuel = fuel + (barrel.stock[f[1]] or 0) * f[2] end
  local sent = 0
  for _, c in pairs(cfg.sent) do sent = sent + c end
  if #cfg.factoryOuts > 0 then
    return ("Stock %s. Factory %d lava.  Sent home %s"):format(table.concat(parts, ", "), barrel.factoryLava, fmtNum(sent)), K.lightGrey
  end
  return ("Stock %s, fuel %s.  Sent home %s"):format(table.concat(parts, ", "), fmtNum(fuel), fmtNum(sent)), K.lightGrey
end
-- The Overworld Foreman's second row (fm_remote.lua sets it)
function hubLine() return "", K.grey end
function drawOverview(w, h)
  local ids = digIds(ui.showRetired)
  if radioOK == false and not (ui.notice and os.clock() < ui.notice.untilT) then
    ui.notice = { text = ("No ender modem on me: %s can't hear me"):format(P.birds), colour = K.red, untilT = os.clock() + 1e9 }
  end
  local active, retiredN = 0, 0
  for _, id in ipairs(allIds()) do if entry(id).retired then retiredN = retiredN + 1 else active = active + 1 end end
  local outTxt = not P.barrels and "" or #cfg.outputs == 0 and "no output" or barrel.moveErr and "CAN'T MOVE"
    or barrel.outFull and "OUTPUT FULL"
    or ("out %d/%d free"):format(barrel.outFree, barrel.outSlots)
  header(w, ui.showRetired and (P.short .. "  retired") or P.title,
    ("%d %s  %s"):format(active, active == 1 and (P.unit or P.bird:lower()) or P.birds:lower(), outTxt))
  if not (ui.notice and os.clock() < ui.notice.untilT) then
    local line, col = barrelLine()
    at(2, 2, pad(line, w - 2), col)
  end

  local top, bottom = 3, h - 2
  local rowH = (h >= 16) and 3 or 1      -- a card is 2 lines + a gap, or 1 line on small screens
  local per = math.max(1, math.floor((bottom - top + 1) / rowH))
  local pages = math.max(1, math.ceil(#ids / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))

  if #ids == 0 then
    local lines = ui.showRetired and { ("No retired %s."):format(P.birds) } or P.emptyText or {
      ("No %s yet."):format(P.birds),
      ("Set up a turtle as a %s (startup.lua, pick %s):"):format(P.bird, P.bird),
      "it asks me for a number and shows up here.",
    }
    for i, l in ipairs(lines) do at(2, top + i, pad(l, w - 2), i == 1 and K.white or K.lightGrey) end
  end

  for i = 1, per do
    local id = ids[(ui.scroll - 1) * per + i]
    if not id then break end
    local l = live[id]
    local s = l and l.s
    local dd = entry(id) or { unknown = true, label = (s and s.label or "?") .. "?", num = 0 }
    local y = top + (i - 1) * rowH
    local name = dd.label or nameOf(dd.num)
    local st, colour = stateOf(id)
    local stale = not l or os.clock() - l.seen > STALE
    local bg = (rowH == 3) and K.black or (i % 2 == 0 and K.grey or K.black)
    at(1, y, (" "):rep(w), K.white, bg)
    at(2, y, pad(name, 12), stale and K.lightGrey or K.white, bg)   -- Firecrest-01 is 12 wide
    at(15, y, pad(st, 9), colour, bg)
    -- the numbers: depth, fuel, cargo
    local bits = {}
    if s then
      bits[#bits + 1] = "Y " .. tostring(s.y or "?")
      if type(s.fuel) == "number" and type(s.fuelLimit) == "number" and s.fuelLimit > 0 then
        bits[#bits + 1] = ("fuel %d%%"):format(math.floor(s.fuel / s.fuelLimit * 100))
      end
      bits[#bits + 1] = ("cargo %s/16"):format(tostring(s.slots or "?"))
    end
    local arrow = w >= 56
    local room = w - 25 - (arrow and 3 or 0)
    if room > 4 then at(25, y, pad(table.concat(bits, "  "), room), stale and K.grey or K.lightGrey, bg) end
    if arrow then at(w - 1, y, ">", K.cyan, bg) end
    if rowH == 3 then
      -- Line 2: what it's doing (or when it was last heard) on the left, where it is on the right
      local where = ""
      if s and s.pos then
        where = posText(s)
        if s.dim and s.dim ~= "overworld" then where = where .. " " .. (DIMS[s.dim] or s.dim) end
      end
      local left
      if dd.unknown then
        left = "No number: old program? Reboot it to update"
      elseif stale then
        left = l and ("not heard for " .. fmtAgo(math.floor(os.clock() - l.seen))) or "never heard from"
      elseif s and s.state == "mining" and s.layer and s.layers then
        left = ("%s, layer %s/%s"):format(rangeText(s.minY, s.maxY), s.layer, s.layers)
      else
        left = (s and s.msg ~= "" and s.msg) or rangeText(dd.minY, dd.maxY)
      end
      local roomL = w - 5 - #where - 2
      at(4, y + 1, pad(left, roomL), stale and K.grey or K.lightGrey)
      if #where > 0 then at(w - #where, y + 1, where, K.grey) end
    end
    if dd.unknown then
      hit(1, y, w, y + rowH - 1, function()
        say((s and s.label or "It") .. ": old program. Hold Ctrl+R on it to update.", K.orange)
      end)
    else
      hit(1, y, w, y + rowH - 1, function() ui.page, ui.id, ui.confirmRetire = "miner", id, nil end)
    end
  end

  -- Footer: dock everyone, show retired, pages
  local fy = h
  at(1, fy, (" "):rep(w))
  local x = 2
  if not ui.showRetired then
    x = smallButton(x, fy, "Dock all", K.red, function()
      for _, id in ipairs(digIds(false)) do order(id, "dock") end
      say(("Sent every %s home."):format(ONE), K.yellow)
    end)
  end
  if retiredN > 0 or ui.showRetired then
    x = smallButton(x, fy, ui.showRetired and "Back" or ("Retired " .. retiredN), K.grey,
      function() ui.showRetired = not ui.showRetired; ui.scroll = 1 end, K.white)
  end
  if not ui.showRetired then
    x = smallButton(x, fy, "Presets", K.lightBlue, function() ui.page, ui.lscroll = "presets", 1 end)
    if P.barrels then
      x = smallButton(x, fy, "Rules", K.yellow, function() ui.page, ui.kscroll = "rules", 1 end)
      x = smallButton(x, fy, "Barrels", K.cyan, function() openAssign() end)
    end
    if active > 0 and w >= 64 then
      x = smallButton(x, fy, "Reboot all", K.purple, function()
        for _, id in ipairs(digIds(false)) do if entry(id) then requestReboot(id) end end
        say(("Reboot sent to every %s: they finish the block they're on first."):format(ONE), K.purple)
      end, K.white)
    end
  end
  if pages > 1 then
    local label = ("%d/%d"):format(ui.scroll, pages)
    local px = w - #label - 9
    if px > x then
      smallButton(px, fy, "<", ui.scroll > 1 and K.cyan or K.grey, function() ui.scroll = ui.scroll - 1 end)
      at(px + 4, fy, label, K.lightGrey)
      smallButton(w - 3, fy, ">", ui.scroll < pages and K.cyan or K.grey, function() ui.scroll = ui.scroll + 1 end)
    end
  end
end

---------------------------------------------------------------------------
-- One miner
---------------------------------------------------------------------------
function drawStatus(id, x, y, w, maxY)
  local dd, l = entry(id), live[id]
  local s = l and l.s
  local st, colour = stateOf(id)
  local function line(fn) if y <= maxY then fn(); end y = y + 1 end
  line(function() at(x, y, pad(st, w), colour) end)
  line(function() at(x, y, pad(s and s.msg or (dd.retired and "Retired" or "Waiting to hear from it"), w), K.lightGrey) end)
  line(function() at(x, y, pad(l and ("Seen " .. fmtAgo(math.floor(os.clock() - l.seen)) .. " ago") or "Never heard", w), K.grey) end)
  y = y + 1
  local f, lim = s and s.fuel, s and s.fuelLimit
  local frac = (type(f) == "number" and type(lim) == "number" and lim > 0) and f / lim or 1
  line(function() lr(x, y, w, "Fuel", type(f) == "number" and fmtNum(f) or (f or "-")) end)
  line(function()
    bar(x, y, w, s and frac or 0, (s and s.hungry) and K.orange or K.lime)
    -- the drink-lava marks (a Canary's: the dock tops him up to fullAt)
    local marks = P.lava and { cfg.hungryAt, cfg.fullAt } or P.fuelTarget and { cfg.fullAt } or {}
    for _, p in ipairs(marks) do
      local mx = x + math.floor(p / 100 * w + 0.5)
      if mx >= x and mx < x + w then at(mx, y, "|", K.black, mx < x + math.floor(frac * w + 0.5) and ((s and s.hungry) and K.orange or K.lime) or K.grey) end
    end
  end)
  if P.lava then
    line(function()
      local txt = not s and "-" or s.hungry and ("drinking to " .. cfg.fullAt .. "%")
        or ("drinks under " .. cfg.hungryAt .. "%")
      lr(x, y, w, "Lava", txt, K.lightGrey, (s and s.hungry) and K.orange or K.lightGrey)
    end)
    line(function()
      local b = s and s.bucket
      local txt = b == "empty" and "empty, ready" or b == "lava" and "full of lava" or b == "none" and "NONE" or "-"
      lr(x, y, w, "Bucket", txt, K.lightGrey, b == "none" and K.red or K.lightGrey)
    end)
    line(function()
      lr(x, y, w, "Drunk", s and (fmtNum(s.lavaScoops or 0) .. " scoops") or "-", K.grey, K.grey)
    end)
  elseif P.fuelTarget then
    line(function() lr(x, y, w, "Top-up", ("to %d%% at the dock"):format(cfg.fullAt), K.lightGrey, K.lightGrey) end)
  end
  line(function()
    -- Chunk controller (keeps his own chunk loaded) and shulker box (extra room)
    local txt, warn = "-", false
    if s then
      local bits = {}
      if s.chunky then bits[#bits + 1] = "loader" end
      if s.box == "ok" then bits[#bits + 1] = "box" elseif s.box == "full" then bits[#bits + 1] = "box FULL"; warn = true end
      txt = #bits > 0 and table.concat(bits, " + ") or "none"
      if s.chunkyNote then txt, warn = s.chunkyNote, true end
    end
    lr(x, y, w, "Gear", txt, K.grey, warn and K.orange or K.grey)
  end)
  line(function() lr(x, y, w, "Cargo", s and ((s.slots or "?") .. "/16") or "-") end)
  line(function() bar(x, y, w, s and ((s.slots or 0) / 16) or 0, (s and (s.slots or 0) >= 14) and K.orange or K.lightBlue) end)
  line(function() lr(x, y, w, "Layer", s and s.layer and s.layers and (math.min(s.layer, s.layers) .. "/" .. s.layers) or "-") end)
  line(function()
    lr(x, y, w, "Chunk", s and s.chunk and s.chunks and ("%d of %d, ring %s"):format(s.chunk, s.chunks, tostring(s.ring)) or "-")
  end)
  line(function() lr(x, y, w, "Range", s and s.minY and (s.minY .. ".." .. s.maxY) or "-") end)
  y = y + 1
  line(function() lr(x, y, w, "At", posText(s), K.lightGrey, K.white) end)
  line(function()
    local dim = s and s.dim and (DIMS[s.dim] or s.dim) or "?"
    lr(x, y, w, dim, s and s.facing and ("facing " .. s.facing) or "", K.lightGrey, K.lightGrey)
  end)
  line(function()
    local hm = s and s.home
    lr(x, y, w, "Home", hm and ("%d, %d, %d"):format(hm.x, hm.y, hm.z) or "-", K.lightGrey, K.lightGrey)
  end)
  if P.barrels then
    line(function()
      local dock = dockOf(id)
      lr(x, y, w, "Dock", dock and (dock:gsub("^minecraft:", "") .. ((barrel.docks[dock] or 0) > 0 and (", " .. barrel.docks[dock] .. " in it") or ""))
        or "no dock barrel: /assign", K.grey, dock and K.grey or K.orange)
    end)
  elseif ownerLine then
    line(function() lr(x, y, w, "Foreman", ownerLine(id), K.grey, K.grey) end)
  end
  if s and s.dockNote then
    line(function() at(x, y, pad(s.dockNote, w), K.orange) end)
  end
  if s and s.far then
    line(function() at(x, y, pad("Moved far from his dock:", w), K.orange) end)
    line(function() at(x, y, pad("see his own screen.", w), K.orange) end)
  elseif s and s.offPath then
    line(function() at(x, y, pad("Moved by hand. Goes home", w), K.orange) end)
    line(function() at(x, y, pad("by a tunnel under the dock.", w), K.orange) end)
  end
  return y
end

function drawHaul(id, x, y, w, maxY)
  local l = live[id]
  if y > maxY then return end
  at(x, y, pad("LAST HAUL", w), K.grey)
  y = y + 1
  local haul = l and l.s.haul or {}
  if #haul == 0 and y <= maxY then at(x, y, pad("Nothing yet", w), K.grey) end
  for _, e in ipairs(haul) do
    if y > maxY then break end
    lr(x, y, w, pretty(e[1]), fmtNum(e[2]), K.white, K.cyan)
    y = y + 1
  end
end

function clampY(v) return math.max(Y_MIN, math.min(Y_MAX, v)) end
function clampR(v) return math.max(0, math.min(RING_CAP, v)) end

-- A miner's page: nudge the picked (not yet started) settings
function adjust(id, dd, key, delta)
  local t = { pMin = dd.pMin, pMax = dd.pMax, pR1 = dd.pR1, pR2 = dd.pR2 }
  if key == "pR1" or key == "pR2" then
    t[key] = clampR(t[key] + delta)
    if t.pR1 > t.pR2 then if key == "pR1" then t.pR2 = t.pR1 else t.pR1 = t.pR2 end end
  else
    t[key] = clampY(t[key] + delta)
    if t.pMin > t.pMax then if key == "pMin" then t.pMax = t.pMin else t.pMin = t.pMax end end
  end
  pick(id, t.pMin, t.pMax, t.pR1, t.pR2)
end

-- One "Label value  [-][+]" row; steps = { {label, delta}, ... }
function numRow(x, y, w, label, value, steps, fn, fieldFn, focused, buf)
  local bw = 0
  for _, s in ipairs(steps) do bw = bw + #s[1] + 3 end
  local vx = x + math.min(11, w - bw - 7)
  at(x, y, pad(label, w), K.white)
  if fieldFn then
    local txt = focused and (buf .. "_") or tostring(value)
    at(vx, y, pad(" " .. txt, 7), focused and K.black or K.white, focused and K.white or K.grey)
    hit(vx, y, vx + 6, y, fieldFn)
  else
    at(vx, y, tostring(value), K.white)
  end
  local bx = x + w - bw
  for _, s in ipairs(steps) do
    bx = smallButton(bx, y, s[1], K.grey, function() fn(s[2]) end, K.white) - 1
  end
end

function drawControls(id, x, y, w, maxY)
  local dd, l = entry(id), live[id]
  local s = l and l.s
  local yStep = { { "-", -1 }, { "+", 1 } }
  local rStep = { { "-", -1 }, { "+", 1 } }

  -- How tall can things be? Everything below the preset list needs `fixed` rows.
  local room = maxY - y + 1
  local function fixedRows(bh, gap) return 1 + 4 + 1 + bh + gap + bh + 1 + 1 end
  local bh, gap = 3, 1
  local presets = presetsOf(id)
  if room - fixedRows(3, 1) < math.min(#presets, 4) then bh, gap = 1, 0 end
  local listRows = math.max(1, room - fixedRows(bh, gap))

  at(x, y, pad("LAYERS", w), K.grey)
  if w >= 16 then
    smallButton(x + w - 6, y, "Edit", K.lightBlue, function() ui.page, ui.lscroll, ui.pset = "presets", 1, presetSetOf(id) end)
  end
  y = y + 1
  -- Preset list (paged if it doesn't fit)
  local n = #presets
  local per = (n > listRows) and math.max(1, listRows - 1) or listRows
  local pages = math.max(1, math.ceil(n / per))
  ui.pscroll = math.max(1, math.min(ui.pscroll or 1, pages))
  for i = 1, per do
    local p = presets[(ui.pscroll - 1) * per + i]
    if not p then break end
    local sel = isSelected(dd, p)
    local bg, fg = sel and K.cyan or K.black, sel and K.black or K.white
    at(x, y, (" "):rep(w), fg, bg)
    at(x + 1, y, p.name:sub(1, w - 2), fg, bg)
    if w >= 20 then
      local r = p.minY .. ".." .. p.maxY
      if w >= 30 then r = r .. "  c" .. (p.r1 > 0 and (p.r1 .. "-") or "") .. p.r2 end
      if #p.name + #r + 3 <= w then at(x + w - #r - 1, y, r, sel and K.black or K.lightGrey, bg) end
    end
    hit(x, y, x + w - 1, y, function() pick(id, p.minY, p.maxY, p.r1, p.r2) end)
    y = y + 1
  end
  if n == 0 then at(x, y, pad("No presets: tap Edit", w), K.grey); y = y + 1 end
  if pages > 1 then
    at(x, y, (" "):rep(w))
    smallButton(x, y, "<", ui.pscroll > 1 and K.cyan or K.grey, function() ui.pscroll = ui.pscroll - 1 end)
    at(x + 4, y, ("%d/%d"):format(ui.pscroll, pages), K.lightGrey)
    smallButton(x + w - 3, y, ">", ui.pscroll < pages and K.cyan or K.grey, function() ui.pscroll = ui.pscroll + 1 end)
    y = y + 1
  end
  -- Fine tuning
  numRow(x, y, w, "Min Y", dd.pMin, yStep, function(dv) adjust(id, dd, "pMin", dv) end); y = y + 1
  numRow(x, y, w, "Max Y", dd.pMax, yStep, function(dv) adjust(id, dd, "pMax", dv) end); y = y + 1
  numRow(x, y, w, w >= 26 and "From ring" or "Ring>", dd.pR1, rStep, function(dv) adjust(id, dd, "pR1", dv) end); y = y + 1
  numRow(x, y, w, w >= 26 and "To ring" or "Ring<", dd.pR2, rStep, function(dv) adjust(id, dd, "pR2", dv) end); y = y + 1
  local hint, hc = ("%d chunks, %dx%d"):format(chunkCount(dd.pR1, dd.pR2), sq(dd.pR2), sq(dd.pR2)), K.grey
  if dd.pR1 > 0 then hint = hint .. (" minus %dx%d"):format(sq(dd.pR1 - 1), sq(dd.pR1 - 1)) end
  -- A force-loaded dock keeps the 8 chunks round it running too; further out needs a chunk controller
  if dd.pR2 > 1 and s and not s.chunky then hint, hc = "Past ring 1: needs a chunk controller", K.orange end
  if s and s.seq ~= dd.seq then hint, hc = "Sending...", K.yellow
  elseif s and s.offPath then hint, hc = "START/DOCK: send it home", K.orange
  elseif dd.want == "run" and (dd.minY ~= dd.pMin or dd.maxY ~= dd.pMax or dd.r1 ~= dd.pR1 or dd.r2 ~= dd.pR2) then
    hint, hc = "START to switch", K.orange
  end
  at(x, y, pad(hint, w), hc)
  y = y + 1
  button(x, y, w, bh, "START", K.lime, function() order(id, "run"); say(dd.label .. ": START sent.") end)
  y = y + bh + gap
  button(x, y, w, bh, w >= 11 and "STOP + DOCK" or "STOP", K.red, function()
    order(id, "dock"); say(dd.label .. ": heading home.", K.yellow)
  end)
  y = y + bh + 1
  if y <= maxY then
    -- Reboot | Retire share the last row
    local rw = math.floor((w - 1) / 2)
    local pending = dd.reboot ~= nil
    button(x, y, rw, 1, pending and "Rebooting..." or "Reboot", pending and K.grey or K.purple, function()
      requestReboot(id); say(dd.label .. ": reboot sent. It finishes its block first.", K.purple)
    end, K.white)
    local rx, rw2 = x + rw + 1, w - rw - 1
    if ui.confirmRetire == id then
      button(rx, y, rw2, 1, "Tap to retire", K.orange, function()
        retire(id); ui.confirmRetire = nil; ui.page = "overview"
        say(dd.label .. " retired. Number " .. dd.num .. " won't be used again.", K.orange)
      end)
    else
      button(rx, y, rw2, 1, "Retire", K.grey, function() ui.confirmRetire = id end, K.white)
    end
  end
end
function drawMiner(w, h)
  local id = ui.id
  local dd = entry(id)
  if not dd then ui.page = "overview"; return drawOverview(w, h) end
  header(w, "< " .. (dd.label or nameOf(dd.num)), "computer #" .. id)
  hit(1, 1, math.min(w, 14), 1, function() ui.page, ui.confirmRetire = "overview", nil end)
  if w >= 44 then
    local cw = math.floor((w - 3) / 2)
    local y = drawStatus(id, 2, 3, cw, h)
    drawHaul(id, 2, y + 1, cw, h)
    if not dd.retired then drawControls(id, cw + 3, 3, w - cw - 3, h) end
  else
    local y = drawStatus(id, 1, 3, w, h)
    if not dd.retired then
      drawControls(id, 1, y + 1, w, h)
    else
      drawHaul(id, 1, y + 1, w, h)
    end
  end
  smallButton(w - 7, h, "Back", K.grey, function() ui.page, ui.confirmRetire = "overview", nil end, K.white)
end
