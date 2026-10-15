-- sim/term.lua  --  a screen: computer terminal, turtle terminal or monitor.
-- Keeps text, text colour and background colour per cell, so a scenario can check a layout
-- at a given width x height (t:text(), t:find("Storage"), t:colourAt(x, y)).
local Term = {}
Term.__index = Term

local function log2(c) local n = 0; while c > 1 do c = c / 2; n = n + 1 end; return n end

function Term.new(w, h, opts)
  opts = opts or {}
  local t = setmetatable({ w = w, h = h, cx = 1, cy = 1, fg = 1, bg = 32768, blink = false,
                           colour = opts.colour ~= false, scale = 1, types = { "monitor" } }, Term)
  t:resize(w, h)
  return t
end

function Term:resize(w, h)
  self.w, self.h = w, h
  self.ch, self.fgs, self.bgs = {}, {}, {}
  for y = 1, h do self:_blankRow(y) end
end

function Term:_blankRow(y)
  local c, f, b = {}, {}, {}
  for x = 1, self.w do c[x], f[x], b[x] = " ", self.fg, self.bg end
  self.ch[y], self.fgs[y], self.bgs[y] = c, f, b
end

-- peripheral/term methods (called with self)
function Term:getSize() return self.w, self.h end
function Term:getCursorPos() return self.cx, self.cy end
function Term:setCursorPos(x, y) self.cx, self.cy = math.floor(x), math.floor(y) end
function Term:setCursorBlink(b) self.blink = b and true or false end
function Term:getCursorBlink() return self.blink end
function Term:isColour() return self.colour end
Term.isColor = Term.isColour
function Term:setTextColour(c) self.fg = c end
function Term:setBackgroundColour(c) self.bg = c end
function Term:getTextColour() return self.fg end
function Term:getBackgroundColour() return self.bg end
function Term:setPaletteColour() end
function Term:getPaletteColour() return 0, 0, 0 end
function Term:setTextScale(s) self.scale = s end
function Term:getTextScale() return self.scale end
Term.setTextColor, Term.setBackgroundColor = Term.setTextColour, Term.setBackgroundColour
Term.getTextColor, Term.getBackgroundColor = Term.getTextColour, Term.getBackgroundColour
Term.setPaletteColor, Term.getPaletteColor = Term.setPaletteColour, Term.getPaletteColour

function Term:write(s)
  s = tostring(s)
  local y = self.cy
  if y >= 1 and y <= self.h then
    for i = 1, #s do
      local x = self.cx + i - 1
      if x >= 1 and x <= self.w then
        self.ch[y][x], self.fgs[y][x], self.bgs[y][x] = s:sub(i, i), self.fg, self.bg
      end
    end
  end
  self.cx = self.cx + #s
end

function Term:blit(s, fgs, bgs)
  if #s ~= #fgs or #s ~= #bgs then error("Arguments must be the same length", 2) end
  local y = self.cy
  if y >= 1 and y <= self.h then
    for i = 1, #s do
      local x = self.cx + i - 1
      if x >= 1 and x <= self.w then
        self.ch[y][x] = s:sub(i, i)
        self.fgs[y][x] = 2 ^ tonumber(fgs:sub(i, i), 16)
        self.bgs[y][x] = 2 ^ tonumber(bgs:sub(i, i), 16)
      end
    end
  end
  self.cx = self.cx + #s
end

function Term:clear() for y = 1, self.h do self:_blankRow(y) end end
function Term:clearLine() if self.cy >= 1 and self.cy <= self.h then self:_blankRow(self.cy) end end

function Term:scroll(n)
  for _ = 1, math.abs(n) do
    if n > 0 then
      table.remove(self.ch, 1); table.remove(self.fgs, 1); table.remove(self.bgs, 1)
      self:_blankRow(self.h)
    else
      table.remove(self.ch); table.remove(self.fgs); table.remove(self.bgs)
      self:_blankRow(self.h)                      -- appended at the bottom, then moved to the top
      table.insert(self.ch, 1, table.remove(self.ch))
      table.insert(self.fgs, 1, table.remove(self.fgs))
      table.insert(self.bgs, 1, table.remove(self.bgs))
    end
  end
end

-- Test-side helpers (not peripheral methods).
function Term:line(y) return table.concat(self.ch[y] or {}) end
function Term:lines()
  local out = {}
  for y = 1, self.h do out[y] = self:line(y) end
  return out
end
-- Whole screen as text, trailing spaces trimmed, trailing blank lines dropped.
function Term:text()
  local out = {}
  for y = 1, self.h do out[y] = (self:line(y):gsub("%s+$", "")) end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  return table.concat(out, "\n")
end
-- x, y of the first place `s` appears (plain match), or nil.
function Term:find(s)
  for y = 1, self.h do
    local x = self:line(y):find(s, 1, true)
    if x then return x, y end
  end
end
function Term:colourAt(x, y) return self.fgs[y][x], self.bgs[y][x] end
function Term:dump(title)
  print(("--- %s (%dx%d)"):format(title or "screen", self.w, self.h))
  for y = 1, self.h do print((self:line(y):gsub("%s+$", ""))) end
  print("---")
end

-- The global `term` table for a computer: plain functions that act on the current target
-- (the computer's own screen until term.redirect points it at a monitor).
local METHODS = { "getSize", "getCursorPos", "setCursorPos", "setCursorBlink", "getCursorBlink", "isColour",
  "isColor", "setTextColour", "setTextColor", "setBackgroundColour", "setBackgroundColor", "getTextColour",
  "getTextColor", "getBackgroundColour", "getBackgroundColor", "write", "blit", "clear", "clearLine", "scroll",
  "setPaletteColour", "setPaletteColor", "getPaletteColour", "getPaletteColor" }

Term.peripheralMethods = { "getSize", "getCursorPos", "setCursorPos", "setCursorBlink", "getCursorBlink", "isColour",
  "isColor", "setTextColour", "setTextColor", "setBackgroundColour", "setBackgroundColor", "getTextColour",
  "getTextColor", "getBackgroundColour", "getBackgroundColor", "write", "blit", "clear", "clearLine", "scroll",
  "setPaletteColour", "setPaletteColor", "getPaletteColour", "getPaletteColor", "setTextScale", "getTextScale" }

function Term.api(native)
  local cur = native
  local api = {}
  for _, m in ipairs(METHODS) do api[m] = function(...) return cur[m](cur, ...) end end
  function api.current() return cur end
  function api.native() return native end
  function api.redirect(target) local old = cur; cur = target; return old end
  return api
end

return Term
