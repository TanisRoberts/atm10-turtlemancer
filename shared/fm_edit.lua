-- fm_edit.lua  --  Foreman engine: the presets list and editor, and the Rules page (keep, junk, lava / fuel).
-- A part of fm.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Presets: list + editor
---------------------------------------------------------------------------
function findPreset(name)
  name = (name or ""):lower()
  if name == "" then return nil end
  for i, p in ipairs(cfg.presets) do if p.name:lower() == name then return i end end
  local hitI, count = nil, 0
  for i, p in ipairs(cfg.presets) do
    if p.name:lower():sub(1, #name) == name then hitI, count = i, count + 1 end
  end
  if count == 1 then return hitI end
end

function openEditor(idx, name)
  local p = idx and cfg.presets[idx] or { name = name or "", minY = -59, maxY = -48, r1 = 0, r2 = DEF_R2 }
  ui.edit = { idx = idx, name = p.name, minY = p.minY, maxY = p.maxY, r1 = p.r1, r2 = p.r2,
              focus = (idx == nil and (name or "") == "") and "name" or nil, buf = "", err = nil, confirmDel = false }
  if ui.edit.focus == "name" then ui.edit.buf = "" end
  ui.page = "edit"
end

FIELDS = { "name", "minY", "maxY", "r1", "r2" }

-- Typing into a field ends when you press Enter/Tab or tap anything else
function commitFocus(e)
  if not e or not e.focus then return end
  local f, b = e.focus, e.buf
  if f == "name" then
    e.name = b:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, NAME_MAX)
  elseif b ~= "" and b ~= "-" then
    local v = math.floor(tonumber(b) or 0)
    if f == "minY" or f == "maxY" then e[f] = clampY(v) else e[f] = clampR(v) end
  end
  e.focus, e.buf = nil, ""
end

function startFocus(e, f)
  commitFocus(e)
  e.focus = f
  e.buf = (f == "name") and e.name or ""
end

function validate(e)
  if e.name == "" then return "Give it a name" end
  for i, p in ipairs(cfg.presets) do
    if i ~= e.idx and p.name:lower() == e.name:lower() then return "There's already a preset called " .. p.name end
  end
  if e.minY > e.maxY then return "Min Y is above Max Y" end
  if e.r1 > e.r2 then return "From ring is past To ring" end
end

function savePreset()
  local e = ui.edit
  commitFocus(e)
  local err = validate(e)
  if err then e.err = err; return end
  local new = { name = e.name, minY = e.minY, maxY = e.maxY, r1 = e.r1, r2 = e.r2 }
  if e.idx and cfg.presets[e.idx] then
    local old = cfg.presets[e.idx]
    -- Miners that had the old version picked (not started yet) get the new one picked instead
    for _, dd in pairs(reg) do
      if isSelected(dd, old) then dd.pMin, dd.pMax, dd.pR1, dd.pR2 = new.minY, new.maxY, new.r1, new.r2 end
    end
    cfg.presets[e.idx] = new
  else
    cfg.presets[#cfg.presets + 1] = new
  end
  saveCfg()
  if remoteChanged then remoteChanged() end
  ui.edit, ui.page = nil, "presets"
  say(("Saved %s: pick it on a%s %s's page."):format(new.name, P.bird:match("^[AEIOU]") and "n" or "", P.bird))
end

function deletePreset(idx)
  local p = cfg.presets[idx]
  if not p then return end
  table.remove(cfg.presets, idx)
  saveCfg()
  if remoteChanged then remoteChanged() end
  say(("Deleted %s. %s keep what they're running."):format(p.name, P.birds), K.orange)
end

function movePreset(idx, dir)
  local j = idx + dir
  if j < 1 or j > #cfg.presets then return end
  cfg.presets[idx], cfg.presets[j] = cfg.presets[j], cfg.presets[idx]
  saveCfg()
  if remoteChanged then remoteChanged() end
end

function drawPresets(w, h)
  header(w, "< PRESETS", ("%d preset%s"):format(#cfg.presets, #cfg.presets == 1 and "" or "s"))
  hit(1, 1, 12, 1, function() ui.page = "overview" end)
  local top, bottom = 3, h - 2
  local per = math.max(1, bottom - top + 1)
  local pages = math.max(1, math.ceil(#cfg.presets / per))
  ui.lscroll = math.max(1, math.min(ui.lscroll or 1, pages))
  if #cfg.presets == 0 then at(2, top, "No presets yet: + New", K.grey) end
  local arrows = w >= 40
  for i = 1, per do
    local idx = (ui.lscroll - 1) * per + i
    local p = cfg.presets[idx]
    if not p then break end
    local y = top + i - 1
    local bg = (i % 2 == 0) and K.grey or K.black
    at(1, y, (" "):rep(w), K.white, bg)
    at(2, y, pad(p.name, NAME_MAX), K.white, bg)
    local infoX = NAME_MAX + 4
    local infoW = w - infoX - (arrows and 7 or 1)
    local info = ("Y %d..%d  %s"):format(p.minY, p.maxY, ringText(p.r1, p.r2))
    if #info > infoW then info = ("Y %d..%d  rings %d-%d"):format(p.minY, p.maxY, p.r1, p.r2) end
    if infoW > 6 then at(infoX, y, pad(info, infoW), K.lightGrey, bg) end
    hit(1, y, w - (arrows and 7 or 0), y, function() openEditor(idx) end)
    if arrows then
      smallButton(w - 6, y, "^", idx > 1 and K.lightBlue or bg, function() movePreset(idx, -1) end)
      smallButton(w - 3, y, "v", idx < #cfg.presets and K.lightBlue or bg, function() movePreset(idx, 1) end)
    end
  end
  at(1, h, (" "):rep(w))
  local x = smallButton(2, h, "+ New", K.lime, function() openEditor(nil) end)
  x = smallButton(x, h, "Back", K.grey, function() ui.page = "overview" end, K.white)
  if pages > 1 then
    local label = ("%d/%d"):format(ui.lscroll, pages)
    local px = w - #label - 9
    if px > x then
      smallButton(px, h, "<", ui.lscroll > 1 and K.cyan or K.grey, function() ui.lscroll = ui.lscroll - 1 end)
      at(px + 4, h, label, K.lightGrey)
      smallButton(w - 3, h, ">", ui.lscroll < pages and K.cyan or K.grey, function() ui.lscroll = ui.lscroll + 1 end)
    end
  end
end

function drawEdit(w, h, kind)
  local e = ui.edit
  if not e then ui.page = "presets"; return drawPresets(w, h) end
  header(w, e.idx and ("< EDIT " .. (cfg.presets[e.idx] and cfg.presets[e.idx].name or "")) or "< NEW PRESET")
  hit(1, 1, 12, 1, function() ui.edit, ui.page = nil, "presets" end)
  local cw = math.min(w - 2, 46)
  local x, y = 2, 3
  -- Name
  local nf = e.focus == "name"
  at(x, y, "Name", K.white)
  local nx = x + 11
  local nw = math.min(NAME_MAX + 2, cw - 11)
  local ntxt = nf and (e.buf .. "_") or (e.name ~= "" and e.name or "tap to type")
  at(nx, y, pad(" " .. ntxt, nw), nf and K.black or (e.name ~= "" and K.white or K.lightGrey), nf and K.white or K.grey)
  hit(nx, y, nx + nw - 1, y, function()
    startFocus(e, "name")
    if kind == "monitor" then say("Type the name on the computer's keyboard", K.yellow) end
  end)
  y = y + 2
  local yS = cw >= 36 and { { "-5", -5 }, { "-1", -1 }, { "+1", 1 }, { "+5", 5 } } or { { "-", -1 }, { "+", 1 } }
  local rS = { { "-", -1 }, { "+", 1 } }
  local rows = {
    { "Min Y", "minY", yS }, { "Max Y", "maxY", yS }, { "From ring", "r1", rS }, { "To ring", "r2", rS },
  }
  for _, r in ipairs(rows) do
    local key = r[2]
    numRow(x, y, cw, r[1], e[key], r[3], function(dv)
      if key == "minY" or key == "maxY" then e[key] = clampY(e[key] + dv) else e[key] = clampR(e[key] + dv) end
      e.err = nil
    end, function()
      startFocus(e, key)
      if kind == "monitor" then say("Type the number on the computer's keyboard", K.yellow) end
    end, e.focus == key, e.buf)
    y = y + 1
  end
  y = y + 1
  -- What it means
  local passes = 0
  do local c = e.maxY - 1; while c + 1 >= e.minY and c >= Y_MIN do passes = passes + 1; c = c - 3 end end
  local info = {
    { ("Mines Y %d..%d: %d pass%s of 3 levels"):format(e.minY, e.maxY, passes, passes == 1 and "" or "es"), K.lightGrey },
    { e.r1 > 0 and ("%dx%d chunks, skipping the middle %dx%d"):format(sq(e.r2), sq(e.r2), sq(e.r1 - 1), sq(e.r1 - 1))
        or ("%dx%d chunks round the dock's chunk"):format(sq(e.r2), sq(e.r2)), K.lightGrey },
  }
  if e.r2 > 1 then info[#info + 1] = { "Past ring 1: needs a chunk controller", K.orange } end
  if e.err then info[#info + 1] = { e.err, K.red } end
  for _, l in ipairs(info) do
    if y <= h - 2 then at(x, y, pad(l[1], w - 2), l[2]) end
    y = y + 1
  end
  -- Buttons
  local by = h - 1
  local tall = h - 1 - y >= 3
  local bh = tall and 3 or 1
  by = h - bh + 1
  if kind == "term" then by = h - bh end  -- term keeps its bottom row for the command bar
  local bw = math.max(8, math.floor((cw - 2) / 3))
  button(x, by, bw, bh, "Save", K.lime, savePreset)
  button(x + bw + 1, by, bw, bh, "Cancel", K.grey, function() ui.edit, ui.page = nil, "presets" end, K.white)
  if e.idx then
    button(x + 2 * (bw + 1), by, bw, bh, e.confirmDel and "Sure?" or "Delete", e.confirmDel and K.orange or K.red, function()
      if e.confirmDel then deletePreset(e.idx); ui.edit, ui.page = nil, "presets" else e.confirmDel = true end
    end)
  end
end

---------------------------------------------------------------------------
-- Rules: when Firecrests drink lava (a Canary's dock top-up), what the dimension keeps, what Firecrest throws away
---------------------------------------------------------------------------
function keepList()
  local out = {}
  for name, c in pairs(cfg.keep) do out[#out + 1] = { name, c } end
  table.sort(out, function(a, b) return pretty(a[1]) < pretty(b[1]) end)
  return out
end
function setKeep(name, c)
  cfg.keep[name] = (c and c > 0) and math.min(c, 99999) or nil
  saveCfg()
end
function setLava(key, v)
  v = math.max(5, math.min(95, v))
  if key == "hungryAt" then cfg.hungryAt = math.min(v, cfg.fullAt - 5)
  elseif P.lava then cfg.fullAt = math.max(v, cfg.hungryAt + 5)
  else cfg.fullAt = math.max(10, v) end
  saveCfg()
  for id in pairs(reg) do sendNow[id] = true end
end

function drawRules(w, h, kind)
  header(w, "< RULES", P.junk and ("%d kept, %d junk"):format(#keepList(), #cfg.junk) or ("%d kept"):format(#keepList()))
  hit(1, 1, 10, 1, function() ui.page = "overview" end)
  local y = 3
  if not P.lava then
    -- A Canary's dock tops him up to this much of his tank
    at(2, y, "FUEL", K.grey)
    local t = ("dock tops up to %d%%"):format(cfg.fullAt)
    at(8, y, t, K.white)
    local x = smallButton(8 + #t + 1, y, "-", K.grey, function() setLava("fullAt", cfg.fullAt - 5) end, K.white) - 1
    smallButton(x, y, "+", K.grey, function() setLava("fullAt", cfg.fullAt + 5) end, K.white)
    y = y + 2
    return drawKeepJunk(w, h, kind, y)
  end
  -- Lava
  at(2, y, "LAVA", K.grey)
  local x = 8
  local t1 = ("drink under %d%%"):format(cfg.hungryAt)
  at(x, y, t1, K.white); x = x + #t1 + 1
  x = smallButton(x, y, "-", K.grey, function() setLava("hungryAt", cfg.hungryAt - 5) end, K.white) - 1
  x = smallButton(x, y, "+", K.grey, function() setLava("hungryAt", cfg.hungryAt + 5) end, K.white) + 1
  local t2 = ("until %d%%"):format(cfg.fullAt)
  if x + #t2 + 8 <= w then
    at(x, y, t2, K.white); x = x + #t2 + 1
    x = smallButton(x, y, "-", K.grey, function() setLava("fullAt", cfg.fullAt - 5) end, K.white) - 1
    smallButton(x, y, "+", K.grey, function() setLava("fullAt", cfg.fullAt + 5) end, K.white)
  else
    y = y + 1
    at(8, y, t2, K.white)
    local x2 = 8 + #t2 + 1
    x2 = smallButton(x2, y, "-", K.grey, function() setLava("fullAt", cfg.fullAt - 5) end, K.white) - 1
    smallButton(x2, y, "+", K.grey, function() setLava("fullAt", cfg.fullAt + 5) end, K.white)
  end
  y = y + 2
  drawKeepJunk(w, h, kind, y)
end

-- The rest of the Rules page: what stays here, and the junk list
function drawKeepJunk(w, h, kind, y)
  -- Keep
  at(2, y, pad(("KEEP IN %s (the rest goes home)"):format(P.place:upper()), w - 10), K.grey)
  at(w - 5, y, "have", K.grey)
  y = y + 1
  local list = keepList()
  -- The junk list, wrapped (worked out first: it gets the rows it needs, up to 6)
  local jline, jlines = "", {}
  for _, j in ipairs(P.junk and cfg.junk or {}) do
    local word = j:gsub("^minecraft:", "")
    local add = (jline == "" and "" or ", ") .. word
    if #jline + #add > w - 3 then jlines[#jlines + 1] = jline .. ","; jline = word else jline = jline .. add end
  end
  if jline ~= "" then jlines[#jlines + 1] = jline end
  if #jlines == 0 then jlines[1] = P.junk and "nothing: he brings everything home" or ("junk.txt on each %s"):format(P.bird) end
  local junkRows = math.min(6, #jlines)
  local rows = math.max(2, h - y - junkRows - 3)
  local pages = math.max(1, math.ceil(#list / rows))
  ui.kscroll = math.max(1, math.min(ui.kscroll or 1, pages))
  for i = 1, rows do
    local e = list[(ui.kscroll - 1) * rows + i]
    if not e then
      if i == 1 then at(2, y, "Nothing kept: everything goes home", K.grey); y = y + 1 end
      break
    end
    local name, c = e[1], e[2]
    local bg = (i % 2 == 0) and K.grey or K.black
    at(1, y, (" "):rep(w), K.white, bg)
    local bx = w - 25
    at(2, y, pad(pretty(name), math.max(4, bx - 3)), K.white, bg)
    at(bx, y, ("%5d"):format(c), K.cyan, bg)
    bx = bx + 6
    bx = smallButton(bx, y, "-", K.lightGrey, function() setKeep(name, c - (c > 16 and 16 or 1)) end) - 1
    bx = smallButton(bx, y, "+", K.lightGrey, function() setKeep(name, c + (c >= 16 and 16 or 1)) end) - 1
    smallButton(bx, y, "x", K.red, function() setKeep(name, 0); say("Not keeping " .. pretty(name) .. ": it goes home.", K.orange) end)
    local have = barrel.stock[name] or 0
    at(w - 6, y, ("%6d"):format(have), have < c and K.orange or K.lime, bg)
    y = y + 1
  end
  if pages > 1 then
    smallButton(2, y, "<", ui.kscroll > 1 and K.cyan or K.grey, function() ui.kscroll = ui.kscroll - 1 end)
    at(6, y, ("%d/%d"):format(ui.kscroll, pages), K.lightGrey)
    smallButton(12, y, ">", ui.kscroll < pages and K.cyan or K.grey, function() ui.kscroll = ui.kscroll + 1 end)
    y = y + 1
  end
  y = y + 1
  -- Junk
  y = math.min(y, h - 1 - junkRows)
  if y <= h - 2 then
    at(2, y, ("%s THROWS AWAY (underground)"):format(P.bird:upper()), K.grey); y = y + 1
    for i, l in ipairs(jlines) do
      if y > h - 1 then break end
      if y == h - 1 and i < #jlines then l = "... /unjunk <item> to take one off" end
      at(2, y, pad(l, w - 2), K.lightGrey); y = y + 1
    end
  end
  -- Footer
  at(1, h, (" "):rep(w))
  local fx = smallButton(2, h, "+ Keep", K.lime, function()
    termUi.cmd = "/keep "
    if kind == "monitor" then say("Type it on the computer: /keep <item> <count>", K.yellow) end
  end)
  if P.junk then
    fx = smallButton(fx, h, "+ Junk", K.orange, function()
      termUi.cmd = "/junk "
      if kind == "monitor" then say("Type it on the computer: /junk <item>  (/unjunk to undo)", K.yellow) end
    end)
  end
  smallButton(fx, h, "Back", K.grey, function() ui.page = "overview" end, K.white)
end
