-- shared/ui_widgets.lua  --  UI kit part 2 (docs/design/ui-kit.md 4.4 to 4.10), loaded by ui.lua:
-- footer with tabs and paging, tiles, bars, text fields, search and command bar, paged lists, map viewport.
-- Extends ui.View; nothing in part 1 changes. Paging state lives on the view: lists and tiles set `v.pages`
-- while drawing, the footer (drawn last) shows the pager, and v.page is the page being shown.
return function(ui)
local View, C = ui.View, ui.c
local floor, max, min, ceil = math.floor, math.max, math.min, math.ceil
local fit = ui.text.fit
local K = keys

local function clamp(n, lo, hi) return max(lo, min(hi, n)) end
local function log2(c) local n = 0; while c > 1 do c = c / 2; n = n + 1 end; return n end
local function hex(slot) return ("0123456789abcdef"):sub(log2(slot) + 1, log2(slot) + 1) end

-- Frame state added by this module is forgotten at the start of every frame.
local begin = View.begin
function View:begin()
  begin(self)
  self.pages, self.tabs, self.sbar, self.listInfo, self.tileInfo, self.mapInfo, self.pagefn = nil
  self.page = self.page or 1
end

-- Show page n (the screen's own on_page if it has one, else the view's).
function View:turn(delta)
  local n = clamp(self.page + delta, 1, self.pages or 1)
  if n == self.page then return end
  if self.pagefn then self.pagefn(n) else self.page = n end
end
local function setPage(self, n) self.page = clamp(n, 1, self.pages or 1); if self.pagefn then self.pagefn(self.page) end end
local function focused(self) for _, b in ipairs(self.foc) do if b.id == self.focus then return b end end end

---------------------------------------------------------------------------------------------------------
-- Footer with tabs and paging (4.4)
---------------------------------------------------------------------------------------------------------
-- v:footer({ back = fn, tabs = { { id=, label=, short=, star= } }, tab = id, on_tab = fn(id),
--            page = n, pages = n, on_page = fn(n) })
-- Left to right: Back, the tabs, and at the right the pager. Pager defaults to the pages the list or tiles drew.
-- Tabs shrink to 4-letter labels, then to the active tab plus `..` which cycles. Keys: 1-9 jump to a tab,
-- Tab / Shift+Tab move focus over tabs and buttons, PgUp/PgDn change page, the mouse wheel scrolls a page.
function View:footer(o)
  o = o or {}
  local y, W = self.H, self.W
  self:fill(1, y, W, "bg")
  local x = 1
  if o.back then
    local wide = self.wc == "regular" or self.wc == "wide"
    local fill = self.focus == "back" and "dim" or "bar"
    if self.colour then
      self:put(1, y, " < ", "fg", fill); x = 4
      if wide then x = self:put(x, y, " Back", "fg", "bg") end
    else
      x = self:put(1, y, wide and "[ < ] Back" or "[ < ]", "fg", "bg")
    end
    self:_box({ 1, y, x - 1, y }, nil, { fn = o.back, id = "back", focus = true })
    self.backfn = o.back
  end
  if o.pages then self.pages = o.pages end
  if o.page then self.page = o.page end
  self.pagefn = o.on_page
  local pages = self.pages or 1
  self.page = clamp(self.page, 1, pages)
  local extra = self.colour and 2 or 4
  local right = W + 1                                   -- first column used by the pager
  if pages > 1 then
    local num = (" %d/%d "):format(self.page, pages)
    local pw = (1 + extra) * 2 + #num
    right = W - pw + 1
    local px = self:_pill(right, y, { label = "<", id = "pg-", enabled = self.page > 1, noFocus = true,
                                      fn = function() self:turn(-1) end }, 1)
    px = self:put(px, y, num, "fg", "bg")
    self:_pill(px, y, { label = ">", id = "pg+", enabled = self.page < pages, noFocus = true,
                        fn = function() self:turn(1) end }, 1)
  end
  local tabs = o.tabs
  if tabs and #tabs > 0 then
    self.tabs = tabs
    local function choose(id) self.page = 1; if o.on_tab then o.on_tab(id) end end
    self.tabfn = choose
    local cx = x + (o.back and 1 or 0)
    local room = right - 1 - cx
    local function width(form)
      local w = 0
      for _, t in ipairs(tabs) do w = w + #form(t) + extra + 1 end
      return w - 1
    end
    local function full(t) return t.label .. (t.star and "*" or "") end
    local function short(t) return (t.short or t.label:sub(1, 4)) .. (t.star and "*" or "") end
    local form = self.wc == "narrow" and short or full
    if width(form) > room then form = short end
    local function draw(t, label, onTap)
      local on = t.id == o.tab
      local nx = self:_pill(cx, y, { label = label, id = "tab:" .. t.id, style = on and "on" or "idle",
                                     fn = onTap or function() choose(t.id) end }, 1)
      if t.star then self:put(cx + 1 + #label - 1, y, "*", "good", on and "gold" or "bar") end
      cx = nx + 1
    end
    if width(form) <= room then
      for _, t in ipairs(tabs) do draw(t, form(t)) end
    else
      local at = 1
      for i, t in ipairs(tabs) do if t.id == o.tab then at = i end end
      draw(tabs[at], short(tabs[at]))
      local nxt = tabs[at % #tabs + 1]
      self:_pill(cx, y, { label = "..", id = "tab:cycle", fn = function() choose(nxt.id) end }, 1)
    end
  end
  return x, y
end

---------------------------------------------------------------------------------------------------------
-- Bars (4.6)
---------------------------------------------------------------------------------------------------------
-- v:bar(x, y, w, label, frac, { kind = "fuel"|"cap"|"progress", text = "37/100" })  frac 0..1, nil = unknown.
-- Fuel is lime above 20%, orange 10-20%, red below. Capacity is lime under 70%, orange 70-90%, red above.
-- Progress is cyan. Squeeze: the label goes first, then the number, then the track shrinks to 6 cells.
-- Fill is half-cell precise (\149) on colour screens; the colourless fallback is # and -.
function ui.barColour(kind, frac)
  if kind == "cap" then return frac > 0.9 and "bad" or frac >= 0.7 and "warn" or "good" end
  if kind == "progress" then return "info" end
  return frac < 0.1 and "bad" or frac < 0.2 and "warn" or "good"
end
function View:bar(x, y, w, label, frac, o)
  o = o or {}
  local num = o.text or (frac and (floor(frac * 100 + 0.5) .. "%") or "-")
  local lab = label and (label .. " ") or ""
  local track = w - #lab - #num - 1
  if track < 6 then lab = ""; track = w - #num - 1 end
  if track < 6 then num = ""; track = w end
  track = max(track, 6)
  local cx = x
  if #lab > 0 then cx = self:put(cx, y, lab, "fg", "bg") end
  if frac then frac = clamp(frac, 0, 1) end
  local fillRole = frac and ui.barColour(o.kind or "fuel", frac)
  if self.colour then
    local half = frac and floor(frac * track * 2 + 0.5) or 0
    local full = floor(half / 2)
    if full > 0 then self:put(cx, y, (" "):rep(full), "fg", fillRole) end
    if half % 2 == 1 then self:put(cx + full, y, "\149", fillRole, "bar"); full = full + 1 end
    self:put(cx + full, y, (" "):rep(track - full), "fg", "bar")
  else
    local n = frac and floor(frac * track + 0.5) or 0
    self:put(cx, y, ("#"):rep(n) .. ("-"):rep(track - n), "fg", "bg")
  end
  cx = cx + track
  if #num > 0 then cx = self:put(cx, y, " " .. num, frac and "fg" or "dim", "bg") end
  return cx, y
end

---------------------------------------------------------------------------------------------------------
-- Tiles (4.5)
---------------------------------------------------------------------------------------------------------
-- columns, tile width, tile height, rows of tiles per page, pages -- for W x H and n tiles.
function ui.layout.tiles(W, H, n)
  local cols = max(1, floor((W - 2 + 1) / 25))
  local w = floor((W - 2 - (cols - 1)) / cols)
  local h = H <= 14 and 2 or 5
  local rows = max(1, floor((H - 3 + 1) / (h + 1)))
  return cols, w, h, rows, max(1, ceil((n or 0) / (cols * rows)))
end

-- v:tiles(items, { render = fn(item) -> fields, on = fn(item) })
-- fields: name, state, activity, fuel (0..1), numbers, seen, stale ("3m": not heard for that long), color.
-- 5 rows: name + state, activity, fuel bar, numbers, seen. Short screens: name + state, fuel bar.
-- A stripe in the state colour runs down the left edge (gold on the highlighted tile, grey when stale).
-- Whole tile is the tap target. Arrows move the highlight, Enter opens, Esc clears. Returns the next free row.
function View:tiles(items, o)
  local cols, tw, th, rows, pages = ui.layout.tiles(self.W, self.H, #items)
  local per = cols * rows
  self.pages = pages
  self.page = clamp(self.page, 1, pages)
  self.tileInfo = { items = items, cols = cols, per = per, on = o.on }
  self.sel = self.sel and clamp(self.sel, 1, max(#items, 1)) or nil
  local first = (self.page - 1) * per
  for i = 1, per do
    local item = items[first + i]
    if not item then break end
    local f = o.render(item)
    local x = 2 + ((i - 1) % cols) * (tw + 1)
    local y = 3 + floor((i - 1) / cols) * (th + 1)
    local stale = f.stale ~= nil
    local role = (self.sel == first + i) and "gold" or stale and "bar" or f.color or ui.stateRole(f.state)
    for r = 0, th - 1 do
      if self.colour then self:put(x, y + r, " ", "fg", role) else self:put(x, y + r, "|", "fg", "bg") end
    end
    local tx, w = x + 2, tw - 3
    local state = f.state and tostring(f.state) or ""
    local txt = stale and "dim" or "fg"
    self:put(tx, y, fit(f.name or "", w - #state - 1), txt, "bg")
    if #state > 0 then self:put(tx + w - #state, y, state, stale and "dim" or (f.color or ui.stateRole(f.state)), "bg") end
    if th == 2 then
      if f.fuel ~= nil or f.fuelText then self:bar(tx, y + 1, w, "Fuel", f.fuel, { text = f.fuelText }) end
    else
      self:put(tx, y + 1, fit(stale and ("not heard " .. f.stale) or f.activity or "", w), "dim", "bg")
      if f.fuel ~= nil then self:bar(tx, y + 2, w, "Fuel", f.fuel, { text = f.fuelText }) end
      if f.numbers then self:put(tx, y + 3, fit(f.numbers, w), txt, "bg") end
      if f.seen then self:put(tx, y + 4, fit(f.seen, w), "dim", "bg") end
    end
    local idx = first + i
    self:_box({ x, y, x + tw - 1, y + th - 1 }, nil, { id = "tile:" .. idx,
      fn = function() self.sel = idx; if o.on then o.on(item) end end })
  end
  return 3 + min(rows, ceil(max(#items - first, 0) / cols)) * (th + 1)
end

---------------------------------------------------------------------------------------------------------
-- Text field, search bar, command bar (4.8)
---------------------------------------------------------------------------------------------------------
-- f = ui.field{ hint = "name of the turtle", max = 24, validate = fn(text) -> message or nil,
--               on_commit = fn(text), on_cancel = fn() }; f.text holds what was typed.
function ui.field(o)
  o = o or {}
  return { text = o.text or "", hint = o.hint, max = o.max or 40, validate = o.validate, on_commit = o.on_commit,
           on_cancel = o.on_cancel, committed = o.text or "" }
end

-- v:field(x, y, label, w, f) draws `label [box]`; tap it, or Tab to it, to type. Enter commits, Esc cancels,
-- Tab leaves. A monitor cannot type, so it shows `type on the computer`. An invalid value turns the box red and
-- puts one red line under it. Returns the next free x and the last row used.
function View:field(x, y, label, w, f)
  local id = "field:" .. label
  local bx = x + #label + 1
  self:put(x, y, label, "fg", "bg")
  local typing = not self.side and self.focus == id
  local text = f.text
  local msg = text ~= "" and f.validate and f.validate(text)
  local fill, ink = msg and "bad" or "bar", msg and "bg" or "fg"
  self:put(bx, y, (" "):rep(w), ink, fill)
  if text == "" then
    local hx = typing and 1 or 0
    self:put(bx + hx, y, fit(self.side and "type on the computer" or f.hint or "", w - hx), "dim", fill)
  else
    self:put(bx, y, fit(text, w), ink, fill)
  end
  if typing and #text < w then self:put(bx + #text, y, " ", "bg", "gold") end
  if msg then self:put(bx, y + 1, fit(msg, w), "bad", "bg") end
  if not self.side then
    self:_box({ bx, y, bx + w - 1, y }, nil, { id = id, field = f, focus = true, fn = function() self.focus = id end })
  end
  return bx + w, msg and y + 1 or y
end

-- v:search(f, { hint =, commands = { { name =, help =, fn = fn(arg) } } }) draws the input row above the footer.
-- It takes typing whenever no other field is focused, so button hotkeys and 1-9 are off on screens that have one.
-- Typing `/` first turns it into a command bar: the content above becomes the command list (call search after
-- the list). Tab completes, Up/Down choose, Enter runs, Esc backs out. Returns true while in command mode.
function View:search(f, o)
  o = o or {}
  local y, W = self.H - 1, self.W
  self.sbar = f
  local typing = focused(self)
  typing = not (typing and typing.field and typing.field ~= f)
  self:put(1, y, " > ", "bg", "dim")
  self:put(4, y, (" "):rep(W - 3), "fg", "bar")
  if f.text == "" then
    local hx = self.side and 0 or 1
    self:put(4 + hx, y, fit(o.hint or "search, / = commands", W - 3 - hx), "dim", "bar")
  else
    self:put(4, y, fit(f.text, W - 4), "fg", "bar")
  end
  if typing and not self.side and #f.text < W - 4 then self:put(4 + #f.text, y, " ", "bg", "gold") end
  self:_box({ 1, y, W, y }, nil, { id = "search", field = f, focus = true, fn = function() self.focus = "search" end })
  f._cmds = nil
  if f.text:sub(1, 1) == "/" and o.commands then
    local word = f.text:match("^/(%S*)") or ""
    local list, nw = {}, 0
    for _, c in ipairs(o.commands) do
      if c.name:sub(1, #word) == word then list[#list + 1] = c; nw = max(nw, #c.name) end
    end
    f._cmds = list
    if f._lastText ~= f.text then f.csel = 1 end
    f._lastText = f.text
    f.csel = clamp(f.csel or 1, 1, max(#list, 1))
    local r = self:rect(true)
    for yy = r.y1, r.y2 do self:fill(1, yy, W, "bg") end
    -- the command list replaces whatever was drawn there: its hit boxes and keys go too
    local function outside(t)
      local keep = {}
      for _, b in ipairs(t) do if b.y1 < r.y1 or b.y1 > r.y2 then keep[#keep + 1] = b end end
      return keep
    end
    self.boxes, self.foc, self.listInfo, self.tileInfo = outside(self.boxes), outside(self.foc), nil, nil
    for i, c in ipairs(list) do
      local yy = r.y1 + i - 1
      if yy > r.y2 then break end
      local sel = i == f.csel
      if sel then self:fill(1, yy, W, "gold") end
      self:put(2, yy, "/" .. c.name, sel and "bg" or "fg", sel and "gold" or "bg")
      self:put(4 + nw, yy, fit(c.help or "", W - 5 - nw), sel and "bg" or "dim", sel and "gold" or "bg")
      self:_box({ 1, yy, W, yy }, nil, { id = "cmd:" .. c.name, fn = function() f.csel = i; f.text = "/" .. c.name .. " " end })
    end
    return true
  end
  return false
end

local function commit(self, f)
  if f._cmds then
    local c = f._cmds[f.csel or 1]
    if not c then ui.say("Unknown command", "warn"); return end
    local arg = f.text:match("^/%S*%s*(.-)%s*$")
    f.text = ""
    c.fn(arg)
  elseif f.on_commit then
    f.committed = f.text
    f.on_commit(f.text)
  elseif f == self.sbar and self.listInfo and self.listInfo.on then
    -- Enter on a search bar opens the selected row, else the top match
    local row = self.listInfo.rows[self.sel or 1] or self.listInfo.rows[1]
    if row then self.listInfo.on(row) end
  end
end

-- The field keys go to: a focused field, else the search bar.
local function efield(self)
  local fb = focused(self)
  if fb and fb.field then return fb.field, fb end
  return self.sbar
end

---------------------------------------------------------------------------------------------------------
-- Paged list rows (4.9)
---------------------------------------------------------------------------------------------------------
-- v:list(rows, { on = fn(row), input = true if a search bar sits below })  rows: { name, value, state, id }.
-- name left, value right (cyan: you can open it), a one-cell stripe in the stock-state colour (not on narrow),
-- the selected row gold. Tap a row to select it, tap it again or the value to open. Up/Down, PgUp/PgDn, Home/End
-- move, Enter opens. Rows per page = the free rows between the rule and the footer (less one for an input row).
-- Sets v.pages. Returns pages and rows per page.
function View:list(rows, o)
  o = o or {}
  local r = self:rect(o.input)
  local rpp = max(r.y2 - r.y1 + 1, 1)
  local pages = max(1, ceil(#rows / rpp))
  self.pages = pages
  self.page = clamp(self.page, 1, pages)
  self.listInfo = { rows = rows, rpp = rpp, on = o.on }
  if self.sel then self.sel = clamp(self.sel, 1, max(#rows, 1)) end
  local W = self.W
  local first = (self.page - 1) * rpp
  local sx = self.wc ~= "narrow"
  for i = 1, rpp do
    local row = rows[first + i]
    if not row then break end
    local idx, y = first + i, r.y1 + i - 1
    local sel = self.sel == idx
    local rb, ink = sel and "gold" or "bg", sel and "bg" or "fg"
    self:fill(1, y, W, rb)
    if sx and not sel then self:put(1, y, " ", "fg", row.state or "bg") end
    local val = row.value ~= nil and tostring(row.value) or ""
    local vx = W - #val
    local nx = sx and 3 or 2
    self:put(nx, y, fit(row.name or "", vx - 1 - nx), ink, rb)
    if #val > 0 then
      self:put(vx, y, val, sel and "bg" or "info", rb)
      self:_box({ vx, y, W, y }, nil, { id = "val:" .. idx, fn = function() self.sel = idx; if o.on then o.on(row) end end })
    end
    self:_box({ 1, y, W, y }, nil, { id = "row:" .. idx, fn = function()
      if self.sel == idx then if o.on then o.on(row) end else self.sel = idx end end })
  end
  return pages, rpp
end

---------------------------------------------------------------------------------------------------------
-- Map viewport with pan (4.10)
---------------------------------------------------------------------------------------------------------
-- v:map({ get = fn(x, z) -> role or { role, char, text }, at = { x =, z =, facing = 0..3 (N E S W) or "^>v<" },
--         on_cell = fn(x, z, info), input = true if a search bar sits below })
-- Block-coloured cells (soil, good2 crops, good saplings, water, bar land) with the machine as a cyan arrow. It follows
-- the machine until you pan; then a Follow button appears. The pan row (^ v < > Follow) sits above the footer unless
-- the screen is short (keys and the wheel only). A tap on a cell says what is there. Arrows pan, Home or f follows.
local ARROW = { [0] = "^", [1] = ">", [2] = "v", [3] = "<" }
function View:map(o)
  local r = self:rect(o.input)
  local pan = self.hc ~= "short"
  local x1, y1, x2, y2 = r.x1, r.y1, r.x2, pan and r.y2 - 1 or r.y2
  local vw, vh = x2 - x1 + 1, y2 - y1 + 1
  local at = o.at
  local cx = self.panTo and self.panTo.x or at.x
  local cz = self.panTo and self.panTo.z or at.z
  local ox, oz = cx - floor(vw / 2), cz - floor(vh / 2)
  local arrow = type(at.facing) == "string" and at.facing or ARROW[at.facing or 0] or "^"
  for row = 0, vh - 1 do
    local chs, fgs, bgs = {}, {}, {}
    for col = 0, vw - 1 do
      local wx, wz = ox + col, oz + row
      local info = o.get(wx, wz)
      local role = type(info) == "table" and info[1] or info or "bg"
      local ch = type(info) == "table" and info[2] or " "
      local fgr = "fg"
      if wx == at.x and wz == at.z then ch, fgr = arrow, "info" end
      if self.colour then
        chs[#chs + 1], fgs[#fgs + 1], bgs[#bgs + 1] = ch, hex(self:slot(fgr)), hex(self:slot(role))
      else
        chs[#chs + 1] = (wx == at.x and wz == at.z) and arrow or (ch ~= " " and ch or (info and "." or " "))
      end
    end
    if self.colour then
      self.t.setCursorPos(x1, y1 + row)
      self.t.blit(table.concat(chs), table.concat(fgs), table.concat(bgs))
    else
      self:put(x1, y1 + row, table.concat(chs), "fg", "bg")
    end
  end
  local function panBy(dx, dz)
    local p = self.panTo or { x = at.x, z = at.z }
    self.panTo = { x = p.x + dx, z = p.z + dz }
  end
  local function follow() self.panTo = nil end
  self.mapInfo = { pan = panBy, follow = follow, hx = max(floor(vw / 2), 1), hz = max(floor(vh / 2), 1) }
  self:_box({ x1, y1, x2, y2 }, nil, { id = "map", fn = function(tx, ty)
    local wx, wz = ox + tx - x1, oz + ty - y1
    local info = o.get(wx, wz)
    if o.on_cell then o.on_cell(wx, wz, info)
    else
      local text = type(info) == "table" and info[3] or (wx == at.x and wz == at.z and "Here") or nil
      ui.say(text or (info and tostring(type(info) == "table" and info[1] or info)) or "Nothing known here", "plain")
    end
  end })
  if pan then
    local mi = self.mapInfo
    local list = {
      { label = "^", id = "pan^", fn = function() panBy(0, -mi.hz) end },
      { label = "v", id = "panv", fn = function() panBy(0, mi.hz) end },
      { label = "<", id = "pan<", fn = function() panBy(-mi.hx, 0) end },
      { label = ">", id = "pan>", fn = function() panBy(mi.hx, 0) end },
    }
    if self.panTo then list[#list + 1] = { label = "Follow", style = "primary", id = "follow", fn = follow } end
    self:buttons(2, r.y2, list)
  end
  return y2
end

---------------------------------------------------------------------------------------------------------
-- Keys and wheel for the components above
---------------------------------------------------------------------------------------------------------
local function moveSel(self, to)
  local info = self.listInfo or self.tileInfo
  local n = #(info.rows or info.items)
  to = clamp(to, 1, max(n, 1))
  self.sel = to
  local per = info.rpp or info.per
  local pg = ceil(to / per)
  if pg ~= self.page then setPage(self, pg) end
end

local baseKey, baseChar = View.key, View.char

function View:key(code, shift)
  local f, fb = efield(self)
  local isSearch = f and f == self.sbar and not (fb and fb.field and fb.id ~= "search")
  if f and (fb or isSearch) then
    if code == K.backspace then
      if #f.text > 0 then f.text = f.text:sub(1, -2) end
      return true
    elseif code == K.enter or code == K.numPadEnter then
      commit(self, f); if not isSearch then self.focus = nil end
      return true
    elseif code == 256 then
      if isSearch then f.text = "" else f.text = f.committed or ""; self.focus = nil; if f.on_cancel then f.on_cancel() end end
      return true
    elseif code == K.tab then
      if f._cmds and f._cmds[f.csel or 1] then f.text = "/" .. f._cmds[f.csel or 1].name .. " "; return true end
    elseif f._cmds and (code == K.up or code == K.down) then
      f.csel = clamp((f.csel or 1) + (code == K.down and 1 or -1), 1, max(#f._cmds, 1))
      return true
    elseif not isSearch then
      if code ~= K.tab then return true end                -- typing: only Tab leaves a plain field
    end
  end
  local fb2 = focused(self)
  local stepper = fb2 and fb2.stepper
  if not stepper then
    local mi = self.mapInfo
    if code == K.enter and not fb2 then
      local li, ti = self.listInfo, self.tileInfo
      if li and self.sel and li.rows[self.sel] and li.on then li.on(li.rows[self.sel]); return true end
      if ti and self.sel and ti.items[self.sel] and ti.on then ti.on(ti.items[self.sel]); return true end
    elseif code == 256 and self.tileInfo then self.sel = nil
    elseif code == K.pageUp or code == K.pageDown then
      self:turn(code == K.pageUp and -1 or 1); return true
    elseif self.listInfo then
      local s = self.sel or 0
      if code == K.up then moveSel(self, s == 0 and 1 or s - 1); return true
      elseif code == K.down then moveSel(self, s + 1); return true
      elseif code == K.home then moveSel(self, 1); return true
      elseif code == K["end"] then moveSel(self, #self.listInfo.rows); return true end
    elseif self.tileInfo then
      local cols, s = self.tileInfo.cols, self.sel or 0
      local d = ({ [K.left] = -1, [K.right] = 1, [K.up] = -cols, [K.down] = cols })[code]
      if d then moveSel(self, s == 0 and 1 or s + d); return true end
    elseif mi then
      local d = ({ [K.left] = { -1, 0 }, [K.right] = { 1, 0 }, [K.up] = { 0, -1 }, [K.down] = { 0, 1 } })[code]
      if d then mi.pan(d[1], d[2]); return true end
      if code == K.home then mi.follow(); return true end
    end
  end
  return baseKey(self, code, shift)
end

function View:char(ch)
  local f, fb = efield(self)
  if f and (fb or f == self.sbar) then
    if #f.text < (f.max or 40) and ch:byte() >= 32 then f.text = f.text .. ch end
    self.armed = nil
    return true
  end
  if self.tabs and ch:match("^[1-9]$") then
    local t = self.tabs[tonumber(ch)]
    if t then self.tabfn(t.id); return true end
  end
  if self.mapInfo and ch == "f" then self.mapInfo.follow(); return true end
  return baseChar(self, ch)
end

-- Mouse wheel: scrolls a page, or pans a map vertically.
function View:scroll(dir)
  if self.mapInfo then self.mapInfo.pan(0, dir * 3) else self:turn(dir) end
end

end
