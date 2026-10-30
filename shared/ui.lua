-- shared/ui.lua  --  the UI kit (docs/design/ui-kit.md). Part 1: look, header, buttons, steppers, notices,
-- footer with a back button, and the event loop. Part 2 (issue #15) adds tabs, tiles, bars, lists, text
-- fields and the map to this same module without changing what is here.
--
--   local ui = require("ui")          -- shared files land flat on a device: shared/ui.lua -> ui.lua
--   local view = ui.view(term.current())          -- or a wrapped monitor: ui.view(mon, { side = "right" })
--   ui.run({ view }, function(v)
--     v:header("FOREMAN", { state = "working" })
--     v:buttons(2, 4, { { label = "Pause", style = "primary", fn = pause }, { label = "Forget", confirm = true, fn = f } })
--     v:footer({ back = goBack })
--   end)
--
-- A screen says what it shows; the kit decides sizes, colours, hit boxes and keys. Colours are role names
-- (ui.c.good), never colours.lime. Every drawing call returns where it ended and registers its hit boxes in
-- the same call, so layout and taps cannot drift apart.
local ui = {}

---------------------------------------------------------------------------------------------------------
-- Palette and roles (kit section 2)
---------------------------------------------------------------------------------------------------------
local C = colours or colors
ui.c = { bg = C.black, bar = C.grey, dim = C.lightGrey, fg = C.white, gold = C.yellow, warn = C.orange,
         bad = C.red, good = C.lime, good2 = C.green, info = C.cyan, idle = C.lightBlue, water = C.blue,
         busy = C.purple, mark = C.magenta, soft = C.pink, soil = C.brown }

-- slot -> hex. The kit remaps CC's 16 slots on every colour terminal.
ui.palette = { { "black", 0x17181C }, { "grey", 0x3A3C42 }, { "lightGrey", 0xA6A8B0 }, { "white", 0xF2EFE4 },
               { "yellow", 0xF2B71F }, { "orange", 0xF58340 }, { "red", 0xF2686E }, { "lime", 0x86D96B },
               { "green", 0x4FB06C }, { "cyan", 0x4CC3CC }, { "lightBlue", 0x7AA7EE }, { "blue", 0x3E5CB0 },
               { "purple", 0xB28DEA }, { "magenta", 0xE077C2 }, { "pink", 0xF4A6C6 }, { "brown", 0x8B5E3C } }
local STOCK = { black = 0x111111, grey = 0x4C4C4C, lightGrey = 0x999999, white = 0xF0F0F0, yellow = 0xDEDE6C,
                orange = 0xF2B233, red = 0xCC4C4C, lime = 0x7FCC19, green = 0x57A64E, cyan = 0x4C99B2,
                lightBlue = 0x99B2F2, blue = 0x3366CC, purple = 0xB266E5, magenta = 0xE57FD8, pink = 0xF2B2CC,
                brown = 0x7F664C }

-- state word -> role. One state, one colour, and the state is always also a word.
ui.state = { ok = "good", ["?"] = "dim", offline = "warn", returning = "info",
             docked = "idle", done = "idle", idle = "idle", waiting = "warn", low = "warn", stale = "warn",
             error = "bad", lost = "bad", stopped = "bad", rebooting = "busy", updating = "busy" }
for _, s in ipairs({ "working", "mining", "building", "mapping", "surveying", "clearing", "marking" }) do
  ui.state[s] = "good"
end

-- A role name or a raw colour slot -> the slot.
function ui.col(x)
  if type(x) == "number" then return x end
  return ui.c[x] or error("unknown colour role: " .. tostring(x), 2)
end
function ui.stateRole(s) return ui.state[s] or "dim" end

local RULE = "\140"            -- teletext thin rule
local ESC = keys and keys.escape or 256
local CONFIRM_S = 4            -- tap-twice window
local NOTICE_S = 5
local NOTICE_TONES = { good = "good", warn = "warn", bad = "bad", busy = "busy", fg = "fg", plain = "fg" }

---------------------------------------------------------------------------------------------------------
-- Pure helpers: text, layout classes, hit boxes (testable without a screen)
---------------------------------------------------------------------------------------------------------
ui.text = {}
-- Cut to n cells with ".." at the end.
function ui.text.fit(s, n)
  s = tostring(s)
  if n <= 0 then return "" end
  if #s <= n then return s end
  if n <= 2 then return (".."):sub(1, n) end
  return s:sub(1, n - 2) .. ".."
end

ui.layout = {}
-- Width class and height class from the screen size (kit section 1). Chosen separately.
function ui.layout.classes(W, H)
  local wc = W <= 30 and "narrow" or W <= 45 and "compact" or W <= 70 and "regular" or "wide"
  local hc = H <= 14 and "short" or H <= 30 and "normal" or "tall"
  return wc, hc
end
-- The area content may draw in: one column margin each side, below the 2 header rows, above the footer
-- (and above an input row when the screen has one; a number reserves that many rows).
function ui.layout.content(W, H, inputRow)
  return { x1 = 2, y1 = 3, x2 = W - 1, y2 = H - 1 - (inputRow == true and 1 or tonumber(inputRow) or 0) }
end

ui.hit = {}
-- Distance from a tap to a box's drawn cells (0 inside).
local function dist(b, x, y)
  local dx = math.max(b.x1 - x, 0, x - b.x2)
  local dy = math.max(b.y1 - y, 0, y - b.y2)
  return dx + dy
end
ui.hit.dist = dist
-- boxes: { x1,y1,x2,y2 = drawn cells, tx1,ty1,tx2,ty2 = tap target (defaults to the drawn cells), ... }.
-- A tap picks the box whose target contains it; if several do, the one whose drawn cells are nearest;
-- a tie goes to the one registered first.
function ui.hit.find(boxes, x, y)
  local best, bd
  for _, b in ipairs(boxes) do
    if x >= (b.tx1 or b.x1) and x <= (b.tx2 or b.x2) and y >= (b.ty1 or b.y1) and y <= (b.ty2 or b.y2) then
      local d = dist(b, x, y)
      if not bd or d < bd then best, bd = b, d end
    end
  end
  return best
end

---------------------------------------------------------------------------------------------------------
-- Notices (kit 4.7): one message in the rule row, shared by every view of the computer
---------------------------------------------------------------------------------------------------------
ui.notice = nil
-- ui.say("Reboot sent", "busy", { action = { label = "Undo", fn = f } })
-- Tones: good lime, warn orange, bad red, busy purple, plain white. Never gold. Errors stay until tapped
-- or until the next notice; everything else expires after 5 seconds.
function ui.say(text, tone, opts)
  tone = NOTICE_TONES[tone or "plain"] or "fg"
  ui.notice = { text = tostring(text), tone = tone, action = opts and opts.action,
                expires = tone ~= "bad" and (os.clock() + NOTICE_S) or nil }
end
function ui.dismiss() ui.notice = nil end

local function expire(views)
  local now = os.clock()
  if ui.notice and ui.notice.expires and now >= ui.notice.expires then ui.notice = nil end
  for _, v in ipairs(views or {}) do
    if v.armed and now - v.armed.at >= CONFIRM_S then v.armed = nil end
  end
end

---------------------------------------------------------------------------------------------------------
-- View
---------------------------------------------------------------------------------------------------------
local View = {}
View.__index = View
ui.View = View

-- ui.view(term.current())  /  ui.view(monitor, { side = "right" })
-- opts.side: the peripheral name, so monitor_touch events find this view (nil = the computer's own screen).
-- opts.scale: monitor text scale (default 0.5, CC's smallest).
function ui.view(t, opts)
  opts = opts or {}
  local v = setmetatable({ t = t, side = opts.side, boxes = {}, foc = {}, hot = {} }, View)
  if t.setTextScale and opts.scale ~= false then pcall(t.setTextScale, opts.scale or 0.5) end
  v.colour = t.isColour and t.isColour() or false
  if v.colour and t.setPaletteColour then
    for _, p in ipairs(ui.palette) do pcall(t.setPaletteColour, C[p[1]], p[2]) end
  end
  v:measure()
  return v
end

-- Drawing goes into a buffer (one character, text colour and background per cell). flush() then sends the rows
-- that differ from what the screen already shows, with one blit each. The screen is never cleared and an unchanged
-- frame writes nothing, so redrawing often cannot flicker (the computer runs alongside the game: a clear that is
-- repainted a moment later can be seen blank).
local HEXD = "0123456789abcdef"
local function hexOf(slot)
  local n = 0
  while slot > 1 do slot = slot / 2; n = n + 1 end
  return HEXD:sub(n + 1, n + 1)
end
ui.hex = hexOf

function View:measure()
  self.W, self.H = self.t.getSize()
  self.wc, self.hc = ui.layout.classes(self.W, self.H)
  self.shown = {}                                   -- the screen's size changed or is new: show every row again
  self:blank()
end
-- Clear the buffer (not the screen).
function View:blank()
  self.bc, self.bf, self.bb = {}, {}, {}
  local f, b = hexOf(self:slot("fg")), hexOf(self:slot("bg"))
  for y = 1, self.H do
    local c, ff, bb = {}, {}, {}
    for x = 1, self.W do c[x], ff[x], bb[x] = " ", f, b end
    self.bc[y], self.bf[y], self.bb[y] = c, ff, bb
  end
end
-- Send the rows that changed since the last flush.
function View:flush()
  local t = self.t
  for y = 1, self.H do
    local c, f, b = table.concat(self.bc[y]), table.concat(self.bf[y]), table.concat(self.bb[y])
    local key = c .. "|" .. f .. "|" .. b
    if self.shown[y] ~= key then
      t.setCursorPos(1, y)
      t.blit(c, f, b)
      self.shown[y] = key
    end
  end
  self.frames = (self.frames or 0) + 1
end
-- Force every row to be sent again at the next flush (something else wrote on the screen).
function View:invalidate() self.shown = {} end
function View:rect(inputRow) return ui.layout.content(self.W, self.H, inputRow) end

-- Put the stock palette back (call when the program ends and the screen goes back to the shell).
function View:close()
  if self.colour and self.t.setPaletteColour then
    for _, p in ipairs(ui.palette) do pcall(self.t.setPaletteColour, C[p[1]], STOCK[p[1]]) end
  end
end

-- Colour slot for drawing: the kit's colour, or on a terminal without colour the nearest grey.
function View:slot(x)
  local s = ui.col(x)
  if self.colour then return s end
  if s == ui.c.bg then return C.black end
  if s == ui.c.bar or s == ui.c.dim then return C.lightGrey end
  return C.white
end

-- Write into the buffer at x,y, clipped to the screen: s is the text, f and b the text and background colour as
-- blit digits (one digit for the whole string, or one per character).
function View:_write(x, y, s, f, b)
  local n = #s
  if y < 1 or y > self.H or x > self.W or n == 0 then return end
  local i0 = 1
  if x < 1 then i0 = 2 - x; x = 1 end
  local last = math.min(n, i0 + self.W - x)
  local c, ff, bb = self.bc[y], self.bf[y], self.bb[y]
  local fone, bone = #f == 1, #b == 1
  for i = i0, last do
    local cx = x + i - i0
    c[cx] = s:sub(i, i)
    ff[cx] = fone and f or f:sub(i, i)
    bb[cx] = bone and b or b:sub(i, i)
  end
end

-- Write text at x,y clipped to the screen. Returns the first column after it.
function View:put(x, y, s, fg, bg)
  self:_write(x, y, s, hexOf(self:slot(fg or "fg")), hexOf(self:slot(bg or "bg")))
  return x + #s
end
function View:fill(x, y, w, bg, ch)
  if w > 0 then self:put(x, y, (ch or " "):rep(w), "fg", bg) end
end

-- Start a frame: forget last frame's hit boxes and focus list, blank the buffer.
function View:begin()
  expire({ self })
  self.boxes, self.foc, self.hot, self.backfn, self.noticeDrawn = {}, {}, {}, nil, false
  self:blank()
end
-- One frame: draw into the buffer, then show what changed.
function View:frame(draw) self:begin(); draw(self); self:flush() end

-- Register a hit box. `drawn` is {x1,y1,x2,y2}; `target` defaults to the drawn cells. o: fn, id, enabled,
-- confirm, focus (join the Tab order), stepper (a record with dec/inc functions).
function View:_box(drawn, target, o)
  local b = { x1 = drawn[1], y1 = drawn[2], x2 = drawn[3], y2 = drawn[4] }
  if target then b.tx1, b.ty1, b.tx2, b.ty2 = target[1], target[2], target[3], target[4] end
  for k, val in pairs(o) do b[k] = val end
  if b.enabled == nil then b.enabled = true end
  self.boxes[#self.boxes + 1] = b
  if b.focus and b.enabled then self.foc[#self.foc + 1] = b end
  return b
end

function View:isArmed(id)
  local a = self.armed
  return a and a.id == id and os.clock() - a.at < CONFIRM_S
end

---------------------------------------------------------------------------------------------------------
-- Header (4.1)
---------------------------------------------------------------------------------------------------------
-- v:header("FOREMAN", { state = "working", color = "good", right = "4 canaries", onState = fn })
-- Row 1: gold chip with the title, optional dim summary (regular and wide), the state word in its colour.
-- Row 2: the rule, or a notice. Returns the first free row (3).
function View:header(title, o)
  o = o or {}
  local W = self.W
  self:fill(1, 1, W, "bg")
  local state = o.state and tostring(o.state)
  local sw = state and (#state + 1) or 0                 -- the word and one cell of margin
  local room = W - sw - (state and 1 or 0) - 2           -- for the title between chip padding
  title = ui.text.fit(tostring(title):upper(), math.max(room, 1))
  local chipW = #title + 2
  if self.colour then
    self:put(1, 1, " " .. title .. " ", "bg", "gold")
  else
    self:put(1, 1, "[" .. title .. "]", "fg", "bg")
  end
  if state then
    local x = W - #state
    self:put(x, 1, state, o.color or ui.stateRole(state), "bg")
    if x - 2 > chipW + 1 then self:glyph(x - 2, 1, state) end
    if o.onState then self:_box({ x, 1, W, 1 }, nil, { fn = o.onState, id = "state" }) end
    local right = (self.wc == "regular" or self.wc == "wide") and o.right
    if right then
      local rx = x - 4 - #right
      if rx > chipW + 1 then self:put(rx, 1, right, "dim", "bg") end
    end
  end
  self:put(1, 2, (self.colour and RULE or "-"):rep(W), "bar", "bg")
  self:notice()
  return 3
end

-- Draw the current notice in the rule row, if one is showing. A tap on it dismisses it (or runs its action).
function View:notice()
  if self.noticeDrawn then return false end
  expire({ self })
  local n = ui.notice
  if not n then return false end
  self.noticeDrawn = true
  local W = self.W
  self:fill(1, 2, W, "bg")
  local actionW = 0
  if n.action then
    local lab = " " .. n.action.label .. " "
    actionW = #lab + 1
    local ax = W - #lab
    self:put(ax, 2, lab, "bg", "gold")
    self:_box({ ax, 2, W - 1, 2 }, nil, { fn = function() ui.dismiss(); n.action.fn() end, id = "notice-action" })
  end
  self:put(1, 2, " " .. ui.text.fit(n.text, W - 2 - actionW) .. " ", n.tone, "bg")
  self:_box({ 1, 2, W, 2 }, nil, { fn = ui.dismiss, id = "notice" })
  return true
end

---------------------------------------------------------------------------------------------------------
-- Buttons (4.2)
---------------------------------------------------------------------------------------------------------
-- style -> fill, text. "armed" is the tap-twice state.
local STYLE = { idle = { "bar", "fg" }, primary = { "gold", "bg" }, danger = { "bad", "bg" }, busy = { "busy", "bg" },
                on = { "gold", "bg" }, disabled = { "bg", "bar" } }

function View:_label(b)
  local lab = b.label
  if self.wc == "narrow" and b.short then lab = b.short end
  if b.style == "busy" or b.busy then lab = self:glyphChar("rebooting") .. " " .. lab end
  return lab
end

-- Draw one pill at x,y and register it. Returns the first free x. Used by buttons, steppers and the footer.
-- b: label, short, style, fn, id, confirm, key, busy, enabled, noFocus. gap: cells to the neighbour, for the tap target.
function View:_pill(x, y, b, gap)
  local style = b.style or "idle"
  if b.busy then style = "busy" end
  if b.enabled == false then style = "disabled" end
  local enabled = not (style == "disabled" or style == "busy")
  local id = b.id or b.label
  local lab = self:_label(b)
  local armed = b.confirm and self:isArmed(id)
  if b.confirm then
    lab = armed and "Sure?" or lab
    local w = math.max(#lab, #(b.label or ""), 5)
    local pad = w - #lab
    lab = (" "):rep(math.floor(pad / 2)) .. lab .. (" "):rep(math.ceil(pad / 2))
  end
  local focused = self.focus == id and enabled
  local fill, text
  if armed then fill, text = (style == "danger") and "bad" or "gold", "bg"
  else fill, text = STYLE[style][1], STYLE[style][2] end
  local drawnW
  if self.colour then
    drawnW = #lab + 2
    if focused and x > 1 then
      self:put(x - 1, y, ">", "fg", "bg")
    elseif focused then fill, text = "dim", "bg" end
    self:put(x, y, " " .. lab .. " ", text, fill)
  else
    drawnW = #lab + 4
    local l, r = "[", "]"
    if not enabled then l, r = " ", " " end
    if focused and x > 1 then self:put(x - 1, y, ">", "fg", "bg") end
    self:put(x, y, l .. " " .. lab .. " " .. r, "fg", "bg")
  end
  local half = math.ceil((gap or 1) / 2)
  self:_box({ x, y, x + drawnW - 1, y }, { x - half, y - 1, x + drawnW - 1 + half, y + 1 },
    { fn = b.fn, id = id, enabled = enabled, confirm = b.confirm, focus = not b.noFocus, style = style })
  if b.key then self.hot[b.key] = self.boxes[#self.boxes] end
  return x + drawnW
end

-- v:buttons(x, y, list, { gap = 1, maxx = W - 1 }) draws pills left to right from x,y; a row that does not fit
-- wraps to the next row down. Returns the next free x and the row of the last button.
-- Each item: label, short (used on narrow screens), fn, style (idle primary danger disabled busy on),
-- confirm (tap twice), key (a letter that taps it), busy (an order is in flight), id.
function View:buttons(x, y, list, o)
  o = o or {}
  local gap = o.gap or 1
  local maxx = o.maxx or (self.W - 1)
  local cx = x
  for _, b in ipairs(list) do
    local wlab = #self:_label(b)
    if b.confirm then wlab = math.max(wlab, #(b.label or ""), 5) end
    local w = wlab + (self.colour and 2 or 4)
    if cx > x and cx + w - 1 > maxx then cx = x; y = y + 1 end
    cx = self:_pill(cx, y, b, gap) + gap
  end
  return cx - gap, y
end

---------------------------------------------------------------------------------------------------------
-- Steppers (4.3)
---------------------------------------------------------------------------------------------------------
-- v:stepper(x, y, "Mine depth", value, { min=, max=, step=1, on = function(newValue) end, pending = false, small = false })
-- `-` value `+`, and on regular and wide screens `<<` `>>` for ten steps. At its minimum the `-` is disabled;
-- at its maximum the `+`. A value sent but not yet confirmed (pending) is gold. Narrow screens stack the label
-- above. Keys when focused: Left/Right or - / + one step, PgUp/PgDn ten. Returns the next free x and the row.
function View:stepper(x, y, label, value, o)
  o = o or {}
  local step = o.step or 1
  local lo, hi = o.min, o.max
  local id = o.id or ("step:" .. label)
  local function go(delta)
    local n = value + delta
    if lo and n < lo then n = lo end
    if hi and n > hi then n = hi end
    if n ~= value and o.on then o.on(n) end
  end
  local cx = x
  if self.wc == "narrow" then
    self:put(x, y, label, "fg", "bg"); y = y + 1
  else
    cx = self:put(x, y, label .. " ", "fg", "bg")
  end
  local big = (self.wc == "regular" or self.wc == "wide") and not o.small   -- small = true: no ten-step pills
  local atMin = lo and value <= lo
  local atMax = hi and value >= hi
  local focused = self.focus == id
  local function pill(label2, enabled, delta)
    cx = self:_pill(cx, y, { label = label2, id = id .. label2, enabled = enabled, noFocus = true,
                             fn = function() go(delta) end }, 1) + 1
  end
  local first = cx
  if big then pill("<<", not atMin, -10 * step) end
  pill("-", not atMin, -step)
  local vw = math.max(#tostring(value), #tostring(lo or 0), #tostring(hi or 0)) + 1
  local vs = tostring(value)
  self:put(cx, y, (" "):rep(vw - #vs) .. vs, o.pending and "gold" or "fg", "bg")
  cx = cx + vw + 1
  pill("+", not atMax, step)
  if big then pill(">>", not atMax, 10 * step) end
  local last = cx - 2
  if focused and first > 1 then self:put(x - 1, y, ">", "fg", "bg") end
  local box = self:_box({ x, y, last, y }, nil, { id = id, focus = true,
    stepper = { dec = function() go(-step) end, inc = function() go(step) end,
                dec10 = function() go(-10 * step) end, inc10 = function() go(10 * step) end } })
  box.fn = function() end           -- Enter on a stepper does nothing; the pills do the work
  -- The wrapping box only joins the Tab order and the keys; taps belong to the pills drawn above it.
  box.tx1, box.ty1, box.tx2, box.ty2 = 0, 0, -1, -1
  return last, y
end

---------------------------------------------------------------------------------------------------------
-- Input: taps and keys
---------------------------------------------------------------------------------------------------------
-- Run a box's action, honouring disabled and tap-twice.
function View:press(b, x, y)
  if not b or not b.enabled then return end
  if b.confirm then
    if self:isArmed(b.id) then self.armed = nil; b.fn(x, y) else self.armed = { id = b.id, at = os.clock() } end
    return
  end
  self.armed = nil
  if b.fn then b.fn(x, y) end
end

-- A tap (monitor_touch or mouse_click) at x,y.
function View:tap(x, y)
  local b = ui.hit.find(self.boxes, x, y)
  if self.armed and not (b and b.id == self.armed.id) then self.armed = nil end
  self:press(b, x, y)
end

local function focusIndex(self)
  for i, b in ipairs(self.foc) do if b.id == self.focus then return i end end
end
local function stepper(self)
  local i = focusIndex(self)
  return i and self.foc[i].stepper
end

-- A key press. shift: whether a Shift key is held. Returns true if the kit used it.
function View:key(code, shift)
  local K = keys
  if code == K.tab then
    self.armed = nil
    local n = #self.foc
    if n == 0 then return true end
    local i = focusIndex(self)
    i = i and (i - 1 + (shift and -1 or 1)) % n + 1 or (shift and n or 1)
    self.focus = self.foc[i].id
    return true
  elseif code == K.enter or code == K.numPadEnter then
    local i = focusIndex(self)
    if i then self:press(self.foc[i]) end
    return true
  end
  self.armed = nil
  if code == K.backspace and self.backfn then self.backfn(); return true end
  if code == ESC then self.focus = nil; return true end
  local s = stepper(self)
  if s then
    if code == K.left then s.dec() elseif code == K.right then s.inc()
    elseif code == K.pageUp then s.inc10() elseif code == K.pageDown then s.dec10()
    else return false end
    return true
  end
  return false
end

-- A typed character: a button's hotkey, or - / + on a focused stepper.
function View:char(ch)
  local b = self.hot[ch]
  if b then self.armed = nil; self:press(b); return true end
  local s = stepper(self)
  if s then
    if ch == "-" then s.dec(); return true elseif ch == "+" or ch == "=" then s.inc(); return true end
  end
  return false
end

---------------------------------------------------------------------------------------------------------
-- Event loop
---------------------------------------------------------------------------------------------------------
local quit = false
function ui.quit() quit = true end

-- ui.run(views, draw, opts): draw every view, then redraw after every event.
--   opts.on_event(...)  called first with each raw event, so a controller can handle rednet and its own timers
--   opts.tick           seconds between redraws with no event (a clock, live numbers); default none
-- Returns when ui.quit() has been called.
function ui.run(views, draw, opts)
  opts = opts or {}
  if views.t then views = { views } end
  quit = false
  local shift = false
  local timer
  local MIN = opts.min_interval or 0.25
  local lastFrame, pending = -1e9, false
  local function redraw()
    for _, v in ipairs(views) do v:frame(draw) end
    lastFrame, pending = os.clock(), false
  end
  local function rearm()
    local at = opts.tick and (os.clock() + opts.tick)
    local function soon(t) if t and (not at or t < at) then at = t end end
    if ui.notice then soon(ui.notice.expires) end
    for _, v in ipairs(views) do if v.armed then soon(v.armed.at + CONFIRM_S) end end
    if pending then soon(lastFrame + MIN) end
    for _, v in ipairs(views) do if v.animated and v.animRate then soon(ui.nextBeat(v.animRate)) end end
    if timer then os.cancelTimer(timer); timer = nil end
    if at then timer = os.startTimer(math.max(at - os.clock(), 0.05)) end
  end
  -- Input is shown at once; anything else (a message on the radio, a timer) at most every MIN seconds. The screen
  -- only changes where the picture changed (View:flush), so a busy radio cannot make it flicker.
  local INPUT = { mouse_click = true, monitor_touch = true, key = true, char = true, mouse_scroll = true,
                  term_resize = true, monitor_resize = true }
  redraw(); rearm()
  while not quit do
    local ev = table.pack(os.pullEvent())
    local name = ev[1]
    if opts.on_event then opts.on_event(table.unpack(ev, 1, ev.n)) end
    if name == "mouse_click" then
      for _, v in ipairs(views) do if not v.side then v:tap(ev[3], ev[4]) end end
    elseif name == "monitor_touch" then
      for _, v in ipairs(views) do if v.side == ev[2] then v:tap(ev[3], ev[4]) end end
    elseif name == "key" then
      if ev[2] == keys.leftShift or ev[2] == keys.rightShift then shift = true end
      for _, v in ipairs(views) do v:key(ev[2], shift) end
    elseif name == "key_up" then
      if ev[2] == keys.leftShift or ev[2] == keys.rightShift then shift = false end
    elseif name == "char" then
      for _, v in ipairs(views) do v:char(ev[2]) end
    elseif name == "mouse_scroll" then
      for _, v in ipairs(views) do if not v.side then v:scroll(ev[2]) end end
    elseif name == "term_resize" then
      for _, v in ipairs(views) do if not v.side then v:measure() end end
    elseif name == "monitor_resize" then
      for _, v in ipairs(views) do if v.side == ev[2] then v:measure() end end
    end
    if name ~= "key_up" and name ~= "mouse_up" then
      expire(views)
      if not quit then
        if INPUT[name] or os.clock() - lastFrame >= MIN - 0.001 then redraw() else pending = true end
      end
      rearm()
    end
  end
end

-- Part 2 (tabs and paging footer, tiles, bars, fields, lists, map) lives in ui_widgets.lua and extends View;
-- part 3 (section, kv, alert, switch, board, picker, report, spinner line) in ui_parts.lua;
-- motion (beat, glyphs, spinner, indeterminate bar, ANIM) in ui_motion.lua.
require("ui_widgets")(ui)
require("ui_parts")(ui)
require("ui_motion")(ui)

return ui
