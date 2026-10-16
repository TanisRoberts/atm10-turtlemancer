-- shared/ui_parts.lua  --  UI kit part 3 (docs/design/ui-kit.md section 10), loaded by ui.lua after ui_widgets.lua:
-- section label, key-value row, alert line, segmented switch, board, picker card, report page, spinner line.
-- Extends ui.View; parts 1 and 2 do not change. Single-row components return the next free row; the switch
-- returns the next free x and its last row, like v:buttons.
return function(ui)
local View = ui.View
local floor, max, min = math.floor, math.max, math.min
local fit = ui.text.fit
local K = keys
local RULE = "\140"

local function clamp(n, lo, hi) return max(lo, min(hi, n)) end
local function rule(self) return self.colour and RULE or "-" end

local begin = View.begin
function View:begin()
  begin(self)
  self.pickInfo = nil
end

---------------------------------------------------------------------------------------------------------
-- 10.1 Section label, 10.2 key-value row, 10.3 alert line
---------------------------------------------------------------------------------------------------------
-- v:section(x, y, w, "Layers"): dim caps label and a rule to x+w-1. Callers leave one blank row above it.
function View:section(x, y, w, text)
  local label = fit(tostring(text):upper(), w - 2)
  local nx = self:put(x, y, label, "dim", "bg")
  if w - #label - 1 > 0 then self:put(nx + 1, y, rule(self):rep(w - #label - 1), "bar", "bg") end
  return y + 1
end

-- v:kv(x, y, w, "Plan", "island_v3", tone): key at the left (dim), value at the right (white or a role).
-- Too long: the key is cut first, the value last.
function View:kv(x, y, w, key, value, tone)
  key, value = tostring(key), tostring(value)
  if #value > w then value, key = fit(value, w), ""
  elseif #key > w - #value - 1 then key = fit(key, w - #value - 1) end
  self:put(x, y, key, "dim", "bg")
  self:put(x + w - #value, y, value, tone or "fg", "bg")
  return y + 1
end

-- v:alert(x, y, w, "Tap #4 is dry", "bad"): a stripe in the tone and the text in the tone (default orange).
function View:alert(x, y, w, text, tone)
  tone = tone or "warn"
  if self.colour then self:put(x, y, " ", "fg", tone) else self:put(x, y, "!", "fg", "bg") end
  self:put(x + 2, y, fit(text, w - 2), tone, "bg")
  return y + 1
end

---------------------------------------------------------------------------------------------------------
-- 10.4 Segmented switch
---------------------------------------------------------------------------------------------------------
-- v:switch(x, y, options, current, on_pick, { id, maxx })
-- options: ids (strings) or { id, label, short }; current is an id; on_pick(id, option). Touching pills, the
-- current one gold. Squeeze: short labels, then a second row. Tap a segment to pick it. Focused (Tab): Left/Right
-- move a cursor (wraps), Enter picks it. Returns the next free x and the last row.
function View:switch(x, y, options, current, on_pick, o)
  o = o or {}
  local opts, ci = {}, 1
  for i, op in ipairs(options) do
    if type(op) ~= "table" then op = { id = op, label = tostring(op) } end
    opts[i] = op
    if op.id == current then ci = i end
  end
  local id = o.id or ("switch:" .. x .. ":" .. y)
  local maxx = o.maxx or (self.W - 1)
  local function total(short)
    local n = 0
    for _, op in ipairs(opts) do n = n + #((short and op.short) or op.label) + 2 end
    return n
  end
  local allShort = #opts > 0
  for _, op in ipairs(opts) do if not op.short then allShort = false end end
  local short = false
  if x + total(false) - 1 > maxx and allShort then short = true end
  self.swcur = self.swcur or {}
  local focused = self.focus == id
  local cur = focused and (self.swcur[id] or ci) or ci
  if not focused then self.swcur[id] = nil end
  local function pick(i)
    self.swcur[id] = nil
    if on_pick then on_pick(opts[i].id, opts[i]) end
  end
  local cx, cy, lastx = x, y, x
  for i, op in ipairs(opts) do
    local lab = (short and op.short) or op.label
    local w = #lab + 2
    if cx > x and cx + w - 1 > maxx then cx = x; cy = cy + 1 end
    local on = i == ci
    if self.colour then
      local fill, text = on and "gold" or "bar", on and "bg" or "fg"
      if focused and i == cur and not on then fill, text = "dim", "bg" end
      self:put(cx, cy, " " .. lab .. " ", text, fill)
    else
      self:put(cx, cy, (on and "[" or " ") .. lab .. (on and "]" or " "), "fg", "bg")
    end
    self:_box({ cx, cy, cx + w - 1, cy }, { cx, cy - 1, cx + w - 1, cy + 1 },
      { id = id .. ":" .. i, fn = function() pick(i) end })
    cx = cx + w; lastx = cx - 1
  end
  if focused and x > 1 then self:put(x - 1, y, ">", "fg", "bg") end
  local n = #opts
  local function move(d) if n > 0 then self.swcur[id] = (cur - 1 + d) % n + 1 end end
  local box = self:_box({ x, y, max(lastx, x), cy }, nil, { id = id, focus = true,
    stepper = { dec = function() move(-1) end, inc = function() move(1) end, dec10 = function() end, inc10 = function() end } })
  box.fn = function() if n > 0 then pick(cur) end end
  box.tx1, box.ty1, box.tx2, box.ty2 = 0, 0, -1, -1        -- taps belong to the segments
  return lastx, cy
end

---------------------------------------------------------------------------------------------------------
-- 10.5 Board
---------------------------------------------------------------------------------------------------------
local STILL = { ok = "+", running = "\\", working = "\\", building = "+", docked = "=", done = "+", idle = "-",
                stale = "?", lost = "!", error = "!", stopped = "!", waiting = "o", returning = "<",
                rebooting = "|", updating = "|" }
local STALE_S = 30

local function age(a)
  if type(a) ~= "number" then return a and tostring(a) or "" end
  if a < 60 then return floor(a) .. "s" elseif a < 3600 then return floor(a / 60) .. "m" end
  return floor(a / 3600) .. "h"
end

-- v:boardHeader(x, y, w, "Machines"): a grey bar with a gold caps label (a board has no page title of its own).
function View:boardHeader(x, y, w, title)
  local label = fit(tostring(title):upper(), w - 2)
  if self.colour then
    self:fill(x, y, w, "bar")
    self:put(x + 1, y, label, "gold", "bar")
  else
    self:put(x, y, ("-"):rep(w), "fg", "bg")
    self:put(x + 1, y, " " .. label .. " ", "fg", "bg")
  end
  return y + 1
end

-- v:board(x, y, w, rows): rows = { title = "Machines" (optional), { name, state, detail, age (seconds or text),
-- color (role, default from the state word), glyph }, ... }. Read-only, no focus. A row not heard for 30 s goes grey
-- and still. Returns the next free row.
function View:board(x, y, w, rows)
  if rows.title then y = self:boardHeader(x, y, w, rows.title) end
  local nl, sl, al = 6, 2, 2
  for _, r in ipairs(rows) do
    nl = max(nl, #tostring(r.name or "")); sl = max(sl, #tostring(r.state or "")); al = max(al, #age(r.age))
  end
  nl = min(nl, max(6, floor(w * 0.32))); sl = min(sl, 10)
  local sx = x + 2 + nl + 1                      -- the state cell: glyph, space, word
  local dx = sx + 2 + sl + 1
  local ax = x + w - al - 1
  for _, r in ipairs(rows) do
    local stale = type(r.age) == "number" and r.age >= STALE_S
    local state = tostring(r.state or "")
    local tone = stale and "dim" or (r.color or ui.stateRole(state))
    if self.colour then self:put(x, y, " ", "fg", stale and "bar" or tone) else self:put(x, y, stale and "?" or "|", "fg", "bg") end
    self:put(x + 2, y, fit(tostring(r.name or ""), nl), stale and "dim" or "fg", "bg")
    if sx + 2 < ax then
      if not stale and not r.glyph and self.glyph then self:glyph(sx, y, state)       -- motion (kit section 9)
      else self:put(sx, y, stale and "?" or r.glyph or STILL[state] or "-", tone, "bg") end
      self:put(sx + 2, y, fit(state, min(sl, ax - sx - 3)), tone, "bg")
    end
    if r.detail and dx + 3 < ax then self:put(dx, y, fit(tostring(r.detail), ax - dx - 1), stale and "dim" or "fg", "bg") end
    local a = age(r.age)
    self:put(x + w - #a, y, a, "dim", "bg")
    y = y + 1
  end
  return y
end

---------------------------------------------------------------------------------------------------------
-- 10.6 Picker card
---------------------------------------------------------------------------------------------------------
-- p = ui.picker{ question = "Which role?", items = { { id, name, tag, lines = {..} or text = ".." } }, index = 1,
--                hint = "up/down browse", on_pick = fn(item, index), on_move = fn(item, index) }
function ui.picker(o)
  local p = { question = o.question, items = o.items or {}, index = o.index or 1, hint = o.hint,
              on_pick = o.on_pick, on_move = o.on_move }
  function p:move(d)
    local n = #self.items
    if n == 0 then return end
    self.index = (self.index - 1 + d) % n + 1
    if self.on_move then self.on_move(self.items[self.index], self.index) end
  end
  function p:jump(i)
    if self.items[i] and i ~= self.index then
      self.index = i
      if self.on_move then self.on_move(self.items[i], i) end
    end
  end
  function p:pick()
    local it = self.items[self.index]
    if it and self.on_pick then self.on_pick(it, self.index) end
  end
  return p
end

local function wrap(text, w)
  local out = {}
  for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for word in para:gmatch("%S+") do
      if line == "" then line = word
      elseif #line + 1 + #word <= w then line = line .. " " .. word
      else out[#out + 1] = line; line = word end
    end
    out[#out + 1] = line
  end
  return out
end

-- v:picker(p): question and counter, the previous and next options peeking in, the current one as a gold card.
-- Draws in the content area and puts its hint and `Pick >` on the footer row, so call it after v:footer{ back }.
-- Keys: Up/Down/Left/Right, wheel, Home/End, 1-9 jump; Enter (nothing focused) or Pick > picks; wraps around.
function View:picker(p)
  local W, H = self.W, self.H
  local r = self:rect()
  local n = #p.items
  self.pickInfo = p
  local y1, y2 = r.y1, r.y2
  if p.question then
    self:put(2, y1, fit(p.question, W - 12), "fg", "bg")
    if n > 0 then
      local c = p.index .. " of " .. n
      self:put(W - #c, y1, c, "dim", "bg")
    end
  end
  local item = p.items[p.index]
  if item then
    local function peek(y, d, mark)
      if n < 2 then return end
      local o = p.items[(p.index - 1 + d) % n + 1]
      self:put(2, y, mark .. " " .. fit(o.name or "", W - 5), "dim", "bg")
      self:_box({ 2, y, W - 1, y }, { 1, y, W, y }, { id = "peek" .. d, fn = function() p:move(d) end })
    end
    peek(y1 + 1, -1, "^"); peek(y2, 1, "v")
    local cy, ch = y1 + 2, y2 - y1 - 2          -- card rows: the title bar, then the body
    if ch >= 1 then
      local tag = item.tag and (" " .. item.tag .. " ") or ""
      local title = fit(" " .. tostring(item.name or ""):upper(), W - 2 - #tag)
      if self.colour then
        self:fill(2, cy, W - 2, "gold")
        self:put(2, cy, title, "bg", "gold")
        if tag ~= "" then self:put(W - #tag, cy, tag, "bg", "gold") end
      else
        self:put(2, cy, "[" .. fit(title:sub(2), W - 4 - #tag) .. "]" .. tag, "fg", "bg")
      end
      local bw = W - 5
      local lines = item.lines or wrap(item.text or "", bw)
      local rows = ch - 1
      if #lines > rows and rows > 0 then lines[rows] = (lines[rows] or "") .. "..." end
      for i = 1, rows do
        if self.colour then self:put(2, cy + i, " ", "fg", "gold") else self:put(2, cy + i, "|", "fg", "bg") end
        if lines[i] then self:put(4, cy + i, fit(lines[i], bw), "fg", "bg") end
      end
    end
  end
  -- footer row: hint, then the Pick button at the right
  local lab = "Pick >"
  local bw = #lab + (self.colour and 2 or 4)
  local px = W - bw
  if p.hint and 12 + #p.hint < px - 1 then self:put(12, H, p.hint, "dim", "bg") end
  self:_pill(px, H, { label = lab, style = "primary", id = "pick", enabled = n > 0, fn = function() p:pick() end }, 1)
end

---------------------------------------------------------------------------------------------------------
-- 10.7 Report page, 10.8 spinner line
---------------------------------------------------------------------------------------------------------
-- v:report{ title, state, color, right, back = fn, rows = { {section="Plan"}, {key=, value=, tone=},
--   {alert=, tone=}, {text=, tone=}, {blank=true} } }: header, rows from the content area (a blank row goes
-- above every section but the first), a pager when it does not fit, and the footer with Back.
function View:report(o)
  self:header(o.title, { state = o.state, color = o.color, right = o.right })
  local r = self:rect()
  local lines = {}
  for _, row in ipairs(o.rows or {}) do
    if row.section and #lines > 0 then lines[#lines + 1] = { blank = true } end
    lines[#lines + 1] = row
  end
  local rpp = max(r.y2 - r.y1 + 1, 1)
  local pages = max(1, math.ceil(#lines / rpp))
  self.pages = pages
  self.page = clamp(self.page, 1, pages)
  local w, y = self.W - 2, r.y1
  for i = (self.page - 1) * rpp + 1, min(#lines, self.page * rpp) do
    local row = lines[i]
    if row.blank then if y > r.y1 then y = y + 1 end
    elseif row.section then self:section(2, y, w, row.section); y = y + 1
    elseif row.alert then self:alert(2, y, w, row.alert, row.tone); y = y + 1
    elseif row.key then self:kv(2, y, w, row.key, row.value, row.tone); y = y + 1
    else self:put(2, y, fit(row.text or "", w), row.tone or "fg", "bg"); y = y + 1 end
  end
  self:footer({ back = o.back })
end

-- v:spinner_line(x, y, "Waiting for storage"): the waiting glyph at 4 beats a second, then the sentence.
function View:spinner_line(x, y, text)
  self:spinner(x, y)
  self:put(x + 2, y, fit(text, self.W - x - 2), "fg", "bg")
  return y + 1
end

---------------------------------------------------------------------------------------------------------
-- Keys for the picker
---------------------------------------------------------------------------------------------------------
local baseKey, baseChar, baseScroll = View.key, View.char, View.scroll

function View:key(code, shift)
  local p = self.pickInfo
  if p then
    local d = ({ [K.up] = -1, [K.left] = -1, [K.down] = 1, [K.right] = 1 })[code]
    if d then self.armed = nil; p:move(d); return true end
    if code == K.home then p:jump(1); return true end
    if code == K["end"] then p:jump(#p.items); return true end
    if (code == K.enter or code == K.numPadEnter) and not self.focus then p:pick(); return true end
  end
  return baseKey(self, code, shift)
end

function View:char(ch)
  local p = self.pickInfo
  if p and ch:match("^[1-9]$") then p:jump(tonumber(ch)); return true end
  return baseChar(self, ch)
end

function View:scroll(dir)
  local p = self.pickInfo
  if p then p:move(dir); return end
  baseScroll(self, dir)
end

end
