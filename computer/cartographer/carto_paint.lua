-- carto_paint.lua  --  draws the map: colours, a pane (a pixel rectangle showing the view), overlays.
--
-- A pane paints into an art_gfx surface (2 x 3 pixels per character cell). The floor has one pane (the big
-- monitor); the computer's screen has a small one for its thumbnail. Both show the same view {cx, cz, s}:
-- the centre in blocks and s blocks per pixel (1, 2, 4, 8 or 16). A pane may be turned in quarter turns (a floor
-- laid the other way round): rot 0 has north up, rot 1 has east up, 2 south, 3 west.
local mc = require("mapchunk")

local P = {}
P.ZOOMS = { 1, 2, 4, 8, 16 }

-- The palette, by the kit's colour names (docs/design/cartographer.md). Pink, magenta and purple are land here.
P.palette = {
  black = 0x17181C, grey = 0x3A3C42, lightGrey = 0xA6A8B0, white = 0xF2EFE4, yellow = 0xF2B71F, orange = 0xF58340,
  red = 0xF2686E, lime = 0x86D96B, cyan = 0x4CC3CC, blue = 0x1E3C8C, lightBlue = 0x3F78C8, green = 0x2E6B30,
  pink = 0xE0D49A, magenta = 0x5AA646, purple = 0x7D9A4A, brown = 0x8B5E3C,
}
local NAMES = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "grey", "lightGrey", "cyan",
                "purple", "blue", "brown", "green", "red", "black" }

-- gfx colour index (0..15, the blit digit) of a colour name
function P.idx(name)
  local c = (colours or colors)[name]
  local n = 0
  while c > 1 do c = c / 2; n = n + 1 end
  return n
end

-- The 16 hex values in gfx order (index 0 = white)
function P.list()
  local l = {}
  for i, n in ipairs(NAMES) do l[i] = P.palette[n] end
  return l
end

-- Put the map's colours on a terminal or monitor
function P.apply(t)
  for name, hex in pairs(P.palette) do pcall(t.setPaletteColour, (colours or colors)[name], hex) end
end

local K = {}
for _, n in ipairs(NAMES) do K[n] = P.idx(n) end
P.K = K

-- Land bands, lowest first: beach, grass, low land, mid land, hills, stone
local BANDS = { "pink", "lime", "magenta", "purple", "brown", "lightGrey" }
P.BANDS = BANDS
P.landMax = 96

local function band(y)
  if y <= 63 then return K[BANDS[1]] end
  local top = math.max(P.landMax, 80)
  local f = math.floor((y - 64) / (top - 63) * 5)
  return K[BANDS[2 + math.max(0, math.min(4, f))]]
end
-- First height of band i (2..6), for the key
function P.bandFloor(i)
  if i == 1 then return nil end
  local top = math.max(P.landMax, 80)
  return 64 + math.ceil((i - 2) * (top - 63) / 5)
end

---------------------------------------------------------------------------
-- Painter: colour of any world column, cached per chunk
---------------------------------------------------------------------------
local Painter = {}
Painter.__index = Painter

function P.painter(store)
  return setmetatable({ store = store, cache = {} }, Painter)
end

function Painter:invalidate(key) if key then self.cache[key] = nil else self.cache = {} end end

-- Note a changed chunk; returns true when the land colours need repainting everywhere (a new height record)
function Painter:note(key)
  local c = self.store.chunks[key]
  self.cache[key] = nil
  if not c then return false end
  local arr = mc.toArray(c.data)
  local grew = false
  for n = 1, 256 do
    local y, kind = mc.unpack(arr[n])
    if y and kind == mc.LAND and y + 1 > P.landMax then P.landMax = math.ceil((y + 1) / 4) * 4; grew = true end
  end
  if grew then self.cache = {} end
  return grew
end

function Painter:colours(key)
  local a = self.cache[key]
  if a then return a end
  local c = self.store.chunks[key]
  if not c then return nil end
  a = {}
  local arr = mc.toArray(c.data)
  for n = 1, 256 do
    local y, kind = mc.unpack(arr[n])
    if not y then a[n] = -1
    elseif kind == mc.DEEP then a[n] = K.blue
    elseif kind == mc.SHALLOW then a[n] = K.lightBlue
    elseif kind == mc.FOLIAGE then a[n] = K.green
    else a[n] = band(y) end
  end
  self.cache[key] = a
  return a
end

---------------------------------------------------------------------------
-- Pane
---------------------------------------------------------------------------
local Pane = {}
Pane.__index = Pane

-- gfx: an art_gfx surface; rect in pixels {x, y, w, h} (default: all of it); view: { cx, cz, s }
function P.pane(gfx, painter, view, rect)
  local o = setmetatable({ gfx = gfx, painter = painter, view = view, rot = 0 }, Pane)
  o:setRect(rect or { x = 0, y = 0, w = gfx.PW, h = gfx.PH })
  return o
end

function Pane:setRect(r)
  self.x0, self.y0, self.w, self.h = r.x, r.y, r.w, r.h
  self.mx, self.my = r.x + r.w / 2, r.y + r.h / 2     -- pixel the view's centre sits on
end

-- pixel -> block offset from the centre, per quarter turn
local function turn(rot, dx, dy)
  if rot == 0 then return dx, dy elseif rot == 1 then return -dy, dx elseif rot == 2 then return -dx, -dy end
  return dy, -dx
end
local function unturn(rot, ox, oz)
  if rot == 0 then return ox, oz elseif rot == 1 then return oz, -ox elseif rot == 2 then return -ox, -oz end
  return -oz, ox
end

-- world block -> pixel (may be off the pane)
function Pane:w2p(x, z, view)
  view = view or self.view
  local dx, dy = unturn(self.rot, (x + 0.5 - view.cx) / view.s, (z + 0.5 - view.cz) / view.s)
  return math.floor(self.mx + dx + 0.5), math.floor(self.my + dy + 0.5)
end

-- pixel -> world block
function Pane:p2w(px, py, view)
  view = view or self.view
  local ox, oz = turn(self.rot, px - 0.5 - self.mx, py - 0.5 - self.my)
  return math.floor(view.cx + ox * view.s), math.floor(view.cz + oz * view.s)
end

-- The block rectangle the pane shows (north-up, ignoring the turn): width and height in blocks
function Pane:span(view)
  view = view or self.view
  if self.rot % 2 == 0 then return self.w * view.s, self.h * view.s end
  return self.h * view.s, self.w * view.s
end

-- A view that holds the block box x0,z0..x1,z1 (the smallest zoom that fits, 16 at most)
function Pane:fit(x0, z0, x1, z1, margin)
  local w, h = (x1 - x0 + 1) * (1 + (margin or 0)), (z1 - z0 + 1) * (1 + (margin or 0))
  local pw, ph = self.w, self.h
  if self.rot % 2 == 1 then pw, ph = ph, pw end
  local v = { cx = math.floor((x0 + x1 + 1) / 2), cz = math.floor((z0 + z1 + 1) / 2), s = P.ZOOMS[#P.ZOOMS] }
  for _, s in ipairs(P.ZOOMS) do
    if w <= pw * s and h <= ph * s then v.s = s; break end
  end
  return v
end

-- The region grid, dotted, and the faint dots of ground nobody has seen
local function unseen(px, py, wx, wz, s)
  if wx % 256 < s and py % 2 == 0 then return K.grey end
  if wz % 256 < s and px % 2 == 0 then return K.grey end
  if px % 8 == 4 and py % 6 == 3 then return K.grey end
  return K.black
end

-- Paint the pixels px0..px1, py0..py1 (clipped to the pane) from the map
function Pane:paint(px0, py0, px1, py1, view, breathe)
  view = view or self.view
  local gfx, painter = self.gfx, self.painter
  px0, py0 = math.max(math.floor(px0), self.x0 + 1), math.max(math.floor(py0), self.y0 + 1)
  px1, py1 = math.min(math.ceil(px1), self.x0 + self.w, gfx.PW), math.min(math.ceil(py1), self.y0 + self.h, gfx.PH)
  local s, rot, cx, cz, mx, my = view.s, self.rot, view.cx, view.cz, self.mx, self.my
  local lastKey, arr
  for py = py0, py1 do
    if breathe and py % 16 == 0 then breathe() end
    for px = px0, px1 do
      local ox, oz = turn(rot, px - 0.5 - mx, py - 0.5 - my)
      local wx, wz = math.floor(cx + ox * s), math.floor(cz + oz * s)
      local ccx, ccz = math.floor(wx / 16), math.floor(wz / 16)
      local key = ccx .. "," .. ccz
      if key ~= lastKey then arr = painter:colours(key); lastKey = key end
      local col = arr and arr[(wz - ccz * 16) * 16 + (wx - ccx * 16) + 1] or -1
      if col < 0 then col = unseen(px, py, wx, wz, s) end
      gfx.setPixel(px, py, col)
    end
  end
end

function Pane:paintAll(view, breathe) self:paint(self.x0 + 1, self.y0 + 1, self.x0 + self.w, self.y0 + self.h, view, breathe) end

-- Repaint around a chunk that changed
function Pane:paintChunk(cx, cz, view, breathe)
  local xa, ya = self:w2p(cx * 16, cz * 16, view)
  local xb, yb = self:w2p(cx * 16 + 15, cz * 16 + 15, view)
  self:paint(math.min(xa, xb) - 1, math.min(ya, yb) - 1, math.max(xa, xb) + 1, math.max(ya, yb) + 1, view, breathe)
end

---------------------------------------------------------------------------
-- Overlay pixels: outlines, turtles, pylons
---------------------------------------------------------------------------
function Pane:inside(px, py) return px > self.x0 and px <= self.x0 + self.w and py > self.y0 and py <= self.y0 + self.h end

function Pane:put(list, px, py, c)
  if self:inside(px, py) then list[(py - 1) * self.gfx.PW + px] = c end
end

function Pane:blob(list, px, py, c)
  for dy = 0, 1 do for dx = 0, 1 do self:put(list, px + dx, py + dy, c) end end
end

function Pane:plus(list, px, py, c)
  self:put(list, px, py, c); self:put(list, px - 1, py, c); self:put(list, px + 1, py, c)
  self:put(list, px, py - 1, c); self:put(list, px, py + 1, c)
end

-- A one-pixel outline round the block box x0,z0..x1,z1. Returns the pixel box.
function Pane:outline(list, x0, z0, x1, z1, c, view)
  local xa, ya = self:w2p(x0, z0, view)
  local xb, yb = self:w2p(x1 + 1, z1 + 1, view)
  local a, b = math.min(xa, xb), math.max(xa, xb)
  local u, d = math.min(ya, yb), math.max(ya, yb)
  for x = a, b do self:put(list, x, u, c); self:put(list, x, d, c) end
  for y = u, d do self:put(list, a, y, c); self:put(list, b, y, c) end
  return a, u, b, d
end

-- Character cell of a pixel
function P.cell(px, py) return math.floor((px + 1) / 2), math.floor((py + 2) / 3) end

return P
