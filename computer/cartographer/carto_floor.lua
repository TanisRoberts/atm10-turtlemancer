-- carto_floor.lua  --  the Cartographer's floor: a big advanced monitor that shows only the map.
--
-- Layout (docs/design/cartographer.md): the map on the left, a zoom bar on the right 8 columns (+, a track with one
-- tick per zoom level, -, FILL). With Fill on the map takes the whole floor, fits everything explored and keeps
-- fitting as it grows; only a lit FILL button stays.
local G = dofile("art_gfx.lua")
local P = require("carto_paint")
local K = P.K

local F = {}
local Floor = {}
Floor.__index = Floor

local BAR = 8

-- mon: the monitor, side: its peripheral name, sh: { store, painter, st, act, breathe }
--   st:  the live state (view, fill, rot, turtles, pylons, scan, nextRegion)
--   act: what taps do { zoom(dir), zoomTo(i), fill(on), centre(x, z) }
function F.new(mon, side, sh)
  local o = setmetatable({ mon = mon, side = side, sh = sh }, Floor)
  o:build()
  return o
end

function Floor:build()
  local mon = self.mon
  if mon.getTextScale and mon.getTextScale() ~= 0.5 then mon.setTextScale(0.5) end
  P.apply(mon)
  self.gfx = G.new(mon)
  self.gfx.breathe = self.sh.breathe
  self.gfx.setPalette(P.list())
  self.W, self.H = self.gfx.W, self.gfx.H
  self.pane = P.pane(self.gfx, self.sh.painter, self.sh.st.view)
  self.key = nil
  self.hits = {}
  for _, n in ipairs({ "labels", "zoom", "fill" }) do self.gfx.setLayer(n, {}) end
  self.gfx.fill(K.black)
end

function Floor:resize() self:build() end

function Floor:close()
  self.gfx.resetPalette()
  self.mon.setBackgroundColour(colours.black); self.mon.clear()
end

-- Rows of the zoom bar: +, track, -, FILL
function Floor:barGeom()
  local H = self.H
  local bh = H >= 24 and 3 or 1
  local x = self.W - BAR + 1
  local g = { x = x, w = 6, bh = bh }
  g.plus = 2
  g.fill = H - bh - 1
  g.minus = g.fill - bh - 1
  g.t1, g.t2 = g.plus + bh + 1, g.minus - 2
  return g
end

local function levelRows(g)
  local rows = {}
  local n = #P.ZOOMS
  local span = math.max(0, g.t2 - g.t1)
  for i = 1, n do rows[i] = g.t1 + math.floor((i - 1) * span / (n - 1) + 0.5) end
  return rows
end

local function levelIndex(s)
  for i, z in ipairs(P.ZOOMS) do if z == s then return i end end
  return 1
end

function Floor:drawBar(st)
  local gfx = self.gfx
  local zc, fc = {}, {}
  local g = self:barGeom()
  local grey, white, black = K.grey, K.white, K.black
  local function button(cells, y, label, bg, fg)
    gfx.box(cells, g.x, y, g.w, g.bh, bg)
    gfx.text(cells, g.x + math.floor((g.w - #label) / 2), y + math.floor(g.bh / 2), label, fg, bg)
  end
  if st.fill then
    -- only FILL, lit, over the map's bottom-right corner
    button(fc, self.H - g.bh - 1, "FILL", white, black)
    self.hits = { { x0 = g.x, x1 = g.x + g.w - 1, y0 = self.H - g.bh - 1, y1 = self.H - 2, id = "fill" } }
  else
    button(zc, g.plus, "+", grey, white)
    button(zc, g.minus, "-", grey, white)
    button(fc, g.fill, "FILL", grey, white)
    local rows = levelRows(g)
    local cur = levelIndex(st.view.s)
    local tx = g.x + 1
    for y = g.t1, g.t2 do gfx.text(zc, tx, y, "|", K.lightGrey, black) end
    for i, y in ipairs(rows) do
      if i == cur then
        gfx.box(zc, tx - 1, y, 3, 1, white)
        gfx.text(zc, tx + 3, y, tostring(P.ZOOMS[i]), white, black)
      else
        gfx.text(zc, tx - 1, y, "-+-", K.lightGrey, black)
        gfx.text(zc, tx + 3, y, tostring(P.ZOOMS[i]), K.lightGrey, black)
      end
    end
    self.hits = {
      { x0 = g.x, x1 = g.x + g.w - 1, y0 = g.plus, y1 = g.plus + g.bh - 1, id = "plus" },
      { x0 = g.x, x1 = g.x + g.w - 1, y0 = g.minus, y1 = g.minus + g.bh - 1, id = "minus" },
      { x0 = g.x, x1 = g.x + g.w - 1, y0 = g.fill, y1 = g.fill + g.bh - 1, id = "fill" },
      { x0 = g.x - 1, x1 = self.W, y0 = g.t1 - 1, y1 = g.t2 + 1, id = "track", rows = rows },
    }
  end
  gfx.setLayer("zoom", zc)
  gfx.setLayer("fill", fc)
end

-- Label next to a dot, nudged so labels do not sit on each other
local function placeLabel(gfx, cells, used, px, py, text, fg)
  local cx, cy = P.cell(px, py)
  local x = cx + 2
  if x + #text - 1 > gfx.W then x = cx - #text - 1 end
  for _, dy in ipairs({ 0, -1, 1, -2, 2 }) do
    local y = cy + dy
    if y >= 1 and y <= gfx.H then
      local free = true
      for xx = x, x + #text - 1 do if used[(y - 1) * gfx.W + xx] then free = false; break end end
      if free then
        for xx = x, x + #text - 1 do used[(y - 1) * gfx.W + xx] = true end
        gfx.text(cells, x, y, text, fg, K.black)
        return
      end
    end
  end
end
F.placeLabel = placeLabel

-- Region outlines, turtles, pylons, labels. `view` is the one the pane is showing.
function F.overlay(pane, gfx, st, labels, view)
  local px, cells, used = {}, {}, {}
  local R = 256
  local function box(rg, colour, text)
    local x0, z0 = rg[1] * R, rg[2] * R
    local a, u, b, d = pane:outline(px, x0, z0, x0 + R - 1, z0 + R - 1, colour, view)
    if labels and text then
      local cx, cy = P.cell(a, u)
      if (b - a) / 2 > #text + 3 and (d - u) / 3 > 3 then
        gfx.text(cells, math.max(1, cx + 2), math.max(1, cy + 1), text, colour, K.black)
      end
    end
  end
  local sc = st.scan
  if sc then box({ sc.rx, sc.rz }, K.cyan, sc.pct and ("~%d%%"):format(sc.pct) or "scanning") end
  if st.nextRegion then box({ st.nextRegion.rx, st.nextRegion.rz }, K.white, "NEXT") end
  for _, p in pairs(st.pylons or {}) do
    local x, y = pane:w2p(p.x, p.z, view)
    pane:plus(px, x, y, K.red)
  end
  for _, t in ipairs(st.turtles or {}) do
    local x, y = pane:w2p(t.pos.x, t.pos.z, view)
    pane:blob(px, x, y, K.white)
    if labels and pane:inside(x, y) then placeLabel(gfx, cells, used, x, y, t.short or t.label or "?", K.white) end
  end
  return px, cells
end

-- Draw what changed. `changed` is { [chunk key] = true } since the last call.
function Floor:refresh(changed)
  local st, gfx, pane = self.sh.st, self.gfx, self.pane
  local store = self.sh.store
  local fillOn = st.fill
  pane.rot = (st.rot or 0) % 4
  local rect = fillOn and { x = 0, y = 0, w = gfx.PW, h = gfx.PH } or { x = 0, y = 0, w = (self.W - BAR) * 2, h = gfx.PH }
  local view = st.view
  if fillOn then
    pane:setRect(rect)
    local x0, z0, x1, z1 = store:bounds()
    view = x0 and pane:fit(x0, z0, x1, z1, 0.06) or { cx = 0, cz = 0, s = 1 }
  else
    pane:setRect(rect)
  end
  pane.view = view
  local key = table.concat({ view.cx, view.cz, view.s, pane.rot, fillOn and 1 or 0, self.W, self.H }, ",")
  if key ~= self.key then
    self.key = key
    gfx.fill(K.black)
    pane:paintAll(view, self.sh.breathe)
  else
    for k in pairs(changed or {}) do
      local cx, cz = k:match("^(%-?%d+),(%-?%d+)$")
      if cx then pane:paintChunk(tonumber(cx), tonumber(cz), view, self.sh.breathe) end
    end
  end
  local px, cells = F.overlay(pane, gfx, st, true, view)
  gfx.setOverlay(px)
  gfx.setLayer("labels", cells)
  self:drawBar(st)
end

-- A tap at character cell (cx, cy). Returns what it did (for the tests).
function Floor:tap(cx, cy)
  local st, act = self.sh.st, self.sh.act
  for _, h in ipairs(self.hits) do
    if cx >= h.x0 and cx <= h.x1 and cy >= h.y0 and cy <= h.y1 then
      if h.id == "plus" then act.zoom(-1) elseif h.id == "minus" then act.zoom(1)
      elseif h.id == "fill" then act.fill(not st.fill)
      elseif h.id == "track" then
        local best, bd = 1, 1e9
        for i, y in ipairs(h.rows) do if math.abs(y - cy) < bd then best, bd = i, math.abs(y - cy) end end
        act.zoomTo(best)
      end
      return h.id
    end
  end
  if st.fill then return nil end            -- the static table: a tap on the map does nothing
  local pane = self.pane
  local x, z = pane:p2w(cx * 2 - 0.5, cy * 3 - 1, st.view)
  if pane:inside(math.floor(cx * 2 - 0.5), math.floor(cy * 3 - 1)) then
    act.centre(x, z)
    return "centre"
  end
end

return F
