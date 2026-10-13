-- art_gfx.lua  --  sub-pixel renderer for the art controller's monitor wall.
--
-- Every character cell is split 2 wide x 3 tall (CC's teletext characters 128-159), so an 8x6
-- advanced monitor at text scale 0.5 (164 x 81 cells) becomes 328 x 243 square "pixels".
-- A cell can only show two colours, so each cell keeps the two that matter most: overlay pixels
-- (turtles, pylons) always win, then the most common colours; the rest snap to the nearest of those.
--
-- Layers, bottom to top:
--   base pixels    (the picture: terrain, art)
--   overlay pixels (things drawn on top that move: turtles, trails, pylons)
--   text layers    (whole cells: labels, legend, buttons, menu), in the order they were made
-- Only cells that changed are redrawn, a run of cells per blit.

local G = {}
local HEX = {}
for i = 0, 15 do HEX[i] = ("0123456789abcdef"):sub(i + 1, i + 1) end
G.HEX = HEX

function G.new(mon)
  local o = { mon = mon }
  local W, H = mon.getSize()
  o.W, o.H = W, H
  o.PW, o.PH = W * 2, H * 3
  local base = {}
  for i = 1, o.PW * o.PH do base[i] = 0 end
  o.base = base
  o.over = {}            -- [pixel index] = colour
  o.layers = {}          -- list of { name, cells = { [cell index] = { ch, fg, bg } } }
  o.layerByName = {}
  o.dirty = {}           -- [row] = { [x] = true }
  o.all = true           -- redraw everything on the next flush
  o.paletteNow = {}

  local PW = o.PW

  local function markCell(cx, cy)
    if cx < 1 or cy < 1 or cx > W or cy > H then return end
    local r = o.dirty[cy]
    if not r then r = {}; o.dirty[cy] = r end
    r[cx] = true
  end
  o.markCell = markCell

  local function markPixel(px, py)
    markCell(math.floor((px + 1) / 2), math.floor((py + 2) / 3))
  end

  function o.markAll() o.all = true end

  function o.setPixel(px, py, c)
    if px < 1 or py < 1 or px > PW or py > o.PH then return end
    local i = (py - 1) * PW + px
    if base[i] ~= c then base[i] = c; markPixel(px, py) end
  end
  -- Set without dirty marking (caller will markAll)
  function o.rawPixel(px, py, c)
    base[(py - 1) * PW + px] = c
  end
  function o.getPixel(px, py) return base[(py - 1) * PW + px] end

  function o.fill(c)
    for i = 1, PW * o.PH do base[i] = c end
    o.all = true
  end

  -- Replace the whole overlay with a new set of pixels: { [index] = colour }
  function o.setOverlay(px)
    for i in pairs(o.over) do
      if px[i] ~= o.over[i] then
        local x = (i - 1) % PW + 1
        markPixel(x, (i - x) / PW + 1)
      end
    end
    for i, c in pairs(px) do
      if o.over[i] ~= c then
        local x = (i - 1) % PW + 1
        markPixel(x, (i - x) / PW + 1)
      end
    end
    o.over = px
  end
  function o.pixelIndex(px, py)
    if px < 1 or py < 1 or px > PW or py > o.PH then return nil end
    return (py - 1) * PW + px
  end

  -- Text layers -------------------------------------------------------------
  function o.setLayer(name, cells)
    local l = o.layerByName[name]
    if not l then
      l = { name = name, cells = {} }
      o.layers[#o.layers + 1] = l
      o.layerByName[name] = l
    end
    for ci, v in pairs(l.cells) do
      local n = cells[ci]
      if not n or n[1] ~= v[1] or n[2] ~= v[2] or n[3] ~= v[3] then
        local x = (ci - 1) % W + 1
        markCell(x, (ci - x) / W + 1)
      end
    end
    for ci, v in pairs(cells) do
      local old = l.cells[ci]
      if not old or old[1] ~= v[1] or old[2] ~= v[2] or old[3] ~= v[3] then
        local x = (ci - 1) % W + 1
        markCell(x, (ci - x) / W + 1)
      end
    end
    l.cells = cells
  end
  function o.clearLayer(name) o.setLayer(name, {}) end

  -- Helpers to build a layer's cells
  function o.text(cells, x, y, s, fg, bg)
    s = tostring(s)
    for i = 1, #s do
      local cx = x + i - 1
      if cx >= 1 and cx <= W and y >= 1 and y <= H then
        cells[(y - 1) * W + cx] = { s:sub(i, i), fg, bg }
      end
    end
  end
  function o.box(cells, x, y, w, h, bg, ch, fg)
    for yy = y, y + h - 1 do
      for xx = x, x + w - 1 do
        if xx >= 1 and xx <= W and yy >= 1 and yy <= H then
          cells[(yy - 1) * W + xx] = { ch or " ", fg or bg, bg }
        end
      end
    end
  end

  -- Encoding ----------------------------------------------------------------
  local cnt, p, c = {}, {}, {}
  local function encode(cx, cy)
    local ci = (cy - 1) * W + cx
    for li = #o.layers, 1, -1 do
      local v = o.layers[li].cells[ci]
      if v then return v[1], HEX[v[2]], HEX[v[3]] end
    end
    local ov = o.over
    local i1 = ((cy - 1) * 3) * PW + cx * 2 - 1
    local i3, i5 = i1 + PW, i1 + PW * 2
    p[1], p[2], p[3], p[4], p[5], p[6] = i1, i1 + 1, i3, i3 + 1, i5, i5 + 1
    local has = false
    for k = 1, 6 do
      local ov_ = ov[p[k]]
      if ov_ then c[k] = ov_; has = true else c[k] = base[p[k]] end
    end
    local a = c[1]
    if not has and a == c[2] and a == c[3] and a == c[4] and a == c[5] and a == c[6] then
      return " ", HEX[a], HEX[a]
    end
    -- Pick the two colours that matter most
    for k in pairs(cnt) do cnt[k] = nil end
    for k = 1, 6 do
      local v = c[k]
      cnt[v] = (cnt[v] or 0) + (ov[p[k]] and 10 or 1)
    end
    local c1, n1, c2, n2 = nil, -1, nil, -1
    for v, n in pairs(cnt) do
      if n > n1 or (n == n1 and v < c1) then c2, n2 = c1, n1; c1, n1 = v, n
      elseif n > n2 or (n == n2 and (c2 == nil or v < c2)) then c2, n2 = v, n end
    end
    if not c2 then return " ", HEX[c1], HEX[c1] end
    for k = 1, 6 do
      local v = c[k]
      if v ~= c1 and v ~= c2 then
        c[k] = (math.abs(v - c1) <= math.abs(v - c2)) and c1 or c2
      end
    end
    local bg = c[6]
    local fg = (bg == c1) and c2 or c1
    local bits = 0
    if c[1] == fg then bits = bits + 1 end
    if c[2] == fg then bits = bits + 2 end
    if c[3] == fg then bits = bits + 4 end
    if c[4] == fg then bits = bits + 8 end
    if c[5] == fg then bits = bits + 16 end
    if bits == 0 then return " ", HEX[bg], HEX[bg] end
    return string.char(128 + bits), HEX[fg], HEX[bg]
  end
  o.encode = encode

  local function blitRow(y, x0, x1)
    local ch, fg, bg = {}, {}, {}
    for x = x0, x1 do
      local a, b, c = encode(x, y)
      local n = x - x0 + 1
      ch[n], fg[n], bg[n] = a, b, c
    end
    mon.setCursorPos(x0, y)
    mon.blit(table.concat(ch), table.concat(fg), table.concat(bg))
  end

  -- Draw everything that changed. Returns the number of cells redrawn.
  function o.flush()
    local n = 0
    if o.all then
      o.all = false
      o.dirty = {}
      for y = 1, H do
        blitRow(y, 1, W)
        if o.breathe and y % 16 == 0 then o.breathe() end
      end
      return W * H
    end
    local rows = o.dirty
    o.dirty = {}
    for y, set in pairs(rows) do
      local xs = {}
      for x in pairs(set) do xs[#xs + 1] = x end
      table.sort(xs)
      local i = 1
      while i <= #xs do
        local a, b = xs[i], xs[i]
        while i < #xs and xs[i + 1] - b <= 3 do i = i + 1; b = xs[i] end
        blitRow(y, a, b)
        n = n + (b - a + 1)
        i = i + 1
      end
    end
    return n
  end

  -- Palette: list of 16 0xRRGGBB values (index 0..15 = list[1..16]). Only changed slots are sent.
  function o.setPalette(list, from, to)
    from, to = from or 0, to or 15
    for i = from, to do
      local v = list[i + 1]
      if v and o.paletteNow[i] ~= v then
        mon.setPaletteColour(2 ^ i, v)
        o.paletteNow[i] = v
      end
    end
  end

  -- Put CC's normal colours back (when the program stops)
  function o.resetPalette()
    for i = 0, 15 do
      local c = 2 ^ i
      local r, g, b = term.nativePaletteColour(c)
      mon.setPaletteColour(c, r, g, b)
    end
    o.paletteNow = {}
  end

  return o
end

-- Colour helpers -------------------------------------------------------------
function G.lerp(a, b, t)
  local ar, ag, ab = math.floor(a / 65536) % 256, math.floor(a / 256) % 256, a % 256
  local br, bgc, bb = math.floor(b / 65536) % 256, math.floor(b / 256) % 256, b % 256
  local r = math.floor(ar + (br - ar) * t + 0.5)
  local g = math.floor(ag + (bgc - ag) * t + 0.5)
  local bl = math.floor(ab + (bb - ab) * t + 0.5)
  return r * 65536 + g * 256 + bl
end

-- Colour at position t (any number, wraps) along a looping list of stops
function G.loop(stops, t)
  local n = #stops
  t = (t % 1) * n
  local i = math.floor(t)
  local f = t - i
  return G.lerp(stops[i % n + 1], stops[(i + 1) % n + 1], f)
end

return G
