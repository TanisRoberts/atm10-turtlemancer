-- art.lua  --  the art controller: a monitor wall that shows off the island (CC:Tweaked, ATM10)
--
-- Needs: an Advanced Computer, an ender (or wireless) modem, and an ADVANCED monitor touching it
--        (the bigger the better: an 8x6 wall gives 328 x 243 pixels).
--
-- Screens (tap the three bars in the bottom-right corner to switch):
--   Turtle map  every turtle that reports a GPS position, as a dot coloured by its height (14 bands
--               from Y_MIN to Y_MAX, key on the right), with a trail of where it's been. The GPS
--               pylons are the red crosses. Tap a turtle for its details; tap anywhere else to
--               move the map there; - / + zoom; FIT follows everything again.
--   Plasma, Rings, Aurora   generative art. Tap it to send a ripple out from your finger.
--
-- The world map lives on the Cartographer computer (computer/cartographer), not here.
--
-- Settings: art.env (made on first run; edit live).
-- Terminal keys: 1-4 switch screens, Q stops (and puts the monitor's colours back).

local G = dofile("art_gfx.lua")
local Scenes = dofile("art_scenes.lua")

local ENV_FILE = "art.env"
local CARTO    = "tanis-carto"

local DEFAULTS = {
  { "DEFAULT_VIEW", "turtles", "Screen to show at start and to go back to when nobody touches it: turtles, plasma, rings, aurora." },
  { "IDLE_RETURN", 300, "Seconds without a tap before it goes back to DEFAULT_VIEW. 0 = never." },
  { "CYCLE", 0, "Seconds per screen when nobody touches it: it rotates through every screen. 0 = off." },
  { "FPS", 8, "Frames per second for the art (the turtle map updates once a second)." },
  { "ART_SPEED", 1, "Colour flow speed for the art (1 = normal)." },
  { "RESEED", 10, "Minutes without a tap before an art screen draws a new pattern. 0 = never." },
  { "Y_MIN", -64, "Turtle map: bottom of the height colours." },
  { "Y_MAX", 320, "Turtle map: top of the height colours." },
  { "BANDS", 14, "Turtle map: number of height colours (2-14)." },
  { "TRAIL", 60, "Turtle map: positions kept in each turtle's trail." },
  { "STALE", 60, "Seconds without news before a turtle shows as quiet (?)." },
  { "HIDE_AFTER", 900, "Seconds without news before a turtle disappears from the maps." },
}

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local E, envStamp = {}, nil
local function stampOf(path)
  if not fs.exists(path) or not fs.attributes then return nil end
  local ok, a = pcall(fs.attributes, path)
  return ok and a and (tostring(a.modified) .. ":" .. tostring(a.size)) or nil
end
local function readEnv()
  local vals = {}
  if fs.exists(ENV_FILE) then
    local f = fs.open(ENV_FILE, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then vals[k:upper()] = v end
    end
    f.close()
  end
  local missing = {}
  for _, d in ipairs(DEFAULTS) do
    if vals[d[1]] == nil then missing[#missing + 1] = d; vals[d[1]] = tostring(d[2]) end
  end
  if #missing > 0 then
    local new = not fs.exists(ENV_FILE)
    local f = fs.open(ENV_FILE, new and "w" or "a")
    if new then f.writeLine("# Art controller settings. Edit and save: picked up within a few seconds.") end
    for _, d in ipairs(missing) do
      f.writeLine(""); f.writeLine("# " .. d[3]); f.writeLine(d[1] .. "=" .. tostring(d[2]))
    end
    f.close()
  end
  for _, d in ipairs(DEFAULTS) do
    local v = vals[d[1]]
    if type(d[2]) == "number" then E[d[1]] = tonumber(v) or d[2] else E[d[1]] = tostring(v):lower() end
  end
  E.BANDS = math.max(2, math.min(14, math.floor(E.BANDS)))
  E.FPS = math.max(1, math.min(20, E.FPS))
  if E.Y_MAX <= E.Y_MIN then E.Y_MAX = E.Y_MIN + 1 end
  envStamp = stampOf(ENV_FILE)
  return true
end
local envChanged = false
local function refreshEnv()
  if stampOf(ENV_FILE) ~= envStamp then readEnv(); envChanged = true end
end

---------------------------------------------------------------------------
-- Long jobs (a full repaint) call breathe() now and then: CC stops a program
-- that runs too long without yielding. It yields briefly, and if the screen's frame timer fires
-- meanwhile it notes that (frameTimer = nil) so the screen loop starts a new one.
---------------------------------------------------------------------------
local frameTimer = nil
local lastBreath = os.epoch("utc")
local function breathe()
  if os.epoch("utc") - lastBreath < 1000 then return end
  os.queueEvent("art_breathe")
  while true do
    local e, p = os.pullEvent()
    if e == "art_breathe" then break end
    if e == "timer" and p == frameTimer then frameTimer = nil end
  end
  lastBreath = os.epoch("utc")
end

---------------------------------------------------------------------------
-- What we know: turtles, pylons
---------------------------------------------------------------------------
local turtles = {}        -- [id] = { id, label, role, state, msg, pos, seen, trail, fuel }
local pylons = {}         -- [key] = { x, y, z, seen }

local function short(label, id)
  local s = tostring(label or ("#" .. id))
  local d = s:match("^[Cc]anary%-(%d+)$")
  if d then return "C" .. d end
  return s:sub(1, 10)
end

local function noteTurtle(id, msg, role)
  if type(msg.pos) ~= "table" or not tonumber(msg.pos.x) then return end
  if msg.dim and tostring(msg.dim) ~= "overworld" and not tostring(msg.dim):find("overworld") then
    if turtles[id] then turtles[id] = nil end
    return
  end
  local t = turtles[id]
  if not t then t = { id = id, trail = {} }; turtles[id] = t end
  local p = { x = math.floor(msg.pos.x), y = math.floor(msg.pos.y), z = math.floor(msg.pos.z) }
  local last = t.trail[#t.trail]
  if not last or last.x ~= p.x or last.y ~= p.y or last.z ~= p.z then
    t.trail[#t.trail + 1] = p
    while #t.trail > E.TRAIL do table.remove(t.trail, 1) end
  end
  t.pos = p
  t.label, t.role, t.state, t.msg = msg.label, role or msg.role, msg.state, msg.msg
  t.fuel = msg.fuel
  t.seen = os.clock()
end

local function liveTurtles()
  local out = {}
  for id, t in pairs(turtles) do
    if os.clock() - (t.seen or 0) > E.HIDE_AFTER then turtles[id] = nil
    else out[#out + 1] = t end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

---------------------------------------------------------------------------
-- Monitor
---------------------------------------------------------------------------
local mon, monName, gfx = nil, nil, nil
-- Finds the biggest advanced monitor touching us. Returns true if the screen changed (new monitor,
-- different size, or gone), so the caller knows to rebuild. Only sets the text scale when it isn't
-- 0.5 already: every setTextScale fires monitor_resize, which would bring us straight back here.
local function findMonitor()
  local best, bestName, bestM = -1, nil, nil
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then
      local m = peripheral.wrap(side)
      if m.isColour and m.isColour() then
        if not m.getTextScale or m.getTextScale() ~= 0.5 then m.setTextScale(0.5) end
        local w, h = m.getSize()
        if w * h > best then bestM, bestName, best = m, side, w * h end
      end
    end
  end
  if not bestM then
    local changed = mon ~= nil
    mon, monName, gfx = nil, nil, nil
    return changed
  end
  local w, h = bestM.getSize()
  if gfx and monName == bestName and gfx.W == w and gfx.H == h then return false end
  mon, monName = bestM, bestName
  gfx = G.new(mon)
  gfx.breathe = breathe
  return true
end

---------------------------------------------------------------------------
-- Shared drawing bits: menu button, menu, map viewport
---------------------------------------------------------------------------
local VIEWS = {
  { id = "turtles", label = "Turtle map" },
  { id = "plasma",  label = "Art: Plasma" },
  { id = "rings",   label = "Art: Rings" },
  { id = "aurora",  label = "Art: Aurora" },
}
local VIEW_INDEX = {}
for i, v in ipairs(VIEWS) do VIEW_INDEX[v.id] = i end

local LAYERS = { "labels", "legend", "title", "buttons", "info", "burger", "menu" }
local function initLayers()
  for _, n in ipairs(LAYERS) do gfx.setLayer(n, {}) end
end
local function clearLayers()
  for _, n in ipairs(LAYERS) do gfx.clearLayer(n) end
end

local menuOpen, menuOpenedAt = false, 0
local current = nil       -- the active view object
local currentId = nil

local function burgerGeom()
  local W, H = gfx.W, gfx.H
  local big = W >= 60 and H >= 24
  local bw = big and 6 or 3
  local pw, ph = bw + 3, big and 7 or 5
  return W - pw + 1, H - ph + 1, pw, ph, bw, big
end

local function drawBurger(fg, bg)
  local cells = {}
  local x, y, pw, ph, bw, big = burgerGeom()
  gfx.box(cells, x, y, pw, ph, bg)
  local bx = x + math.floor((pw - bw) / 2)
  local rows = big and { y + 1, y + 3, y + 5 } or { y + 1, y + 2, y + 3 }
  if not big then
    -- Small screens: three thin bars from teletext half-blocks
    for _, ry in ipairs({ y + 1, y + 2, y + 3 }) do
      for xx = bx, bx + bw - 1 do cells[(ry - 1) * gfx.W + xx] = { string.char(131), fg, bg } end
    end
  else
    for _, ry in ipairs(rows) do gfx.box(cells, bx, ry, bw, 1, fg) end
  end
  gfx.setLayer("burger", cells)
end

local function inBurger(cx, cy)
  local x, y, pw, ph = burgerGeom()
  return cx >= x - 1 and cy >= y - 1
end

local function menuGeom()
  local W, H = gfx.W, gfx.H
  local _, by = burgerGeom()
  local mw = math.min(22, W - 2)
  local rowH = (H >= 40) and 3 or 1
  local mh = 1 + #VIEWS * rowH + 1
  local x = W - mw + 1
  local y = math.max(1, by - mh)
  return x, y, mw, mh, rowH
end

local function drawMenu(ui)
  if not menuOpen then gfx.clearLayer("menu"); return end
  local cells = {}
  local x, y, mw, mh, rowH = menuGeom()
  gfx.box(cells, x, y, mw, mh, ui.bg)
  gfx.text(cells, x + 1, y, "SHOW", ui.fg, ui.bg)
  for i, v in ipairs(VIEWS) do
    local ry = y + 1 + (i - 1) * rowH
    local sel = v.id == currentId
    local bg = sel and ui.hi or ui.bg
    gfx.box(cells, x, ry, mw, rowH, bg)
    gfx.text(cells, x + 2, ry + math.floor(rowH / 2), v.label, ui.fg, bg)
  end
  gfx.setLayer("menu", cells)
end

local function menuHit(cx, cy)
  local x, y, mw, mh, rowH = menuGeom()
  if cx < x or cx > x + mw - 1 or cy < y or cy > y + mh - 1 then return nil end
  local i = math.floor((cy - y - 1) / rowH) + 1
  if i >= 1 and i <= #VIEWS then return VIEWS[i].id end
  return false
end

-- Buttons: a row of labelled boxes; returns cells and a hit list
local function buttonRow(cells, x, y, list, ui, h)
  local hits = {}
  h = h or 3
  for _, b in ipairs(list) do
    local w = #b.label + 2
    if x + w - 1 > gfx.W then break end
    local bg = b.on and ui.hi or ui.btn
    gfx.box(cells, x, y, w, h, bg)
    gfx.text(cells, x + 1, y + math.floor(h / 2), b.label, ui.fg, bg)
    hits[#hits + 1] = { x0 = x, x1 = x + w - 1, y0 = y, y1 = y + h - 1, id = b.id }
    x = x + w + 1
  end
  return hits
end

local function hitTest(hits, cx, cy)
  for _, h in ipairs(hits or {}) do
    if cx >= h.x0 and cx <= h.x1 and cy >= h.y0 and cy <= h.y1 then return h.id end
  end
end

-- Map viewport: centre (cx, cz) in blocks, s = blocks per pixel
local NICE = { 0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64 }
local function niceAtLeast(s)
  for _, n in ipairs(NICE) do if n >= s - 1e-9 then return n end end
  return NICE[#NICE]
end
local function zoomStep(s, dir)
  local i = 1
  for k, n in ipairs(NICE) do if math.abs(n - s) < 1e-9 then i = k end end
  return NICE[math.max(1, math.min(#NICE, i + dir))]
end

local function newViewport() return { cx = 0, cz = 0, s = 1, auto = true } end
local function w2p(V, x, z)
  return math.floor((x + 0.5 - V.cx) / V.s + gfx.PW / 2 + 0.5), math.floor((z + 0.5 - V.cz) / V.s + gfx.PH / 2 + 0.5)
end
local function p2w(V, px, py)
  return math.floor(V.cx + (px - 0.5 - gfx.PW / 2) * V.s), math.floor(V.cz + (py - 0.5 - gfx.PH / 2) * V.s)
end
local function fitTo(V, x0, z0, x1, z1, fill)
  local fx, fz = fill and 1 or 0.82, fill and 1 or 0.78
  local s = math.max((x1 - x0 + 1) / (gfx.PW * fx), (z1 - z0 + 1) / (gfx.PH * fz))
  V.s = niceAtLeast(math.max(0.25, s))
  V.cx, V.cz = math.floor((x0 + x1 + 1) / 2), math.floor((z0 + z1 + 1) / 2)
end

local function plus(list, x, y, c)
  local function put(a, b)
    local i = gfx.pixelIndex(a, b)
    if i then list[i] = c end
  end
  put(x, y); put(x - 1, y); put(x + 1, y); put(x, y - 1); put(x, y + 1)
end
local function blob(list, x, y, c)
  for dy = 0, 1 do for dx = 0, 1 do
    local i = gfx.pixelIndex(x + dx, y + dy)
    if i then list[i] = c end
  end end
end
local function pixelToCell(px, py) return math.floor((px + 1) / 2), math.floor((py + 2) / 3) end

-- Label next to a dot, nudged so labels don't sit on each other
local function placeLabel(cells, used, px, py, text, fg, bg)
  local cx, cy = pixelToCell(px, py)
  local x = cx + 2
  if x + #text - 1 > gfx.W then x = cx - #text - 1 end
  for _, dy in ipairs({ 0, -1, 1, -2, 2 }) do
    local y = cy + dy
    if y >= 1 and y <= gfx.H then
      local free = true
      for xx = x, x + #text - 1 do if used[(y - 1) * gfx.W + xx] then free = false; break end end
      if free then
        for xx = x, x + #text - 1 do used[(y - 1) * gfx.W + xx] = true end
        gfx.text(cells, x, y, text, fg, bg)
        return
      end
    end
  end
end

local function ago(t)
  local s = math.floor(os.clock() - (t or 0))
  if s < 60 then return s .. "s" elseif s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end

---------------------------------------------------------------------------
-- Turtle map
---------------------------------------------------------------------------
local TURTLE_COLS = { 0x6b2fd6, 0x4b4bf0, 0x2f7df5, 0x1fb6e8, 0x22d39a, 0x5fe04a, 0xd9e83a,
                      0xffc02e, 0xff8fb3, 0xe05cff, 0xb38cff, 0x8fc7ff, 0xc9eef5, 0xf4f4f4 }
local T_WHITE, T_RED = 14, 15

local function turtlePalette()
  local pal = { [1] = 0x000000, [16] = 0xff2424 }
  local n = E.BANDS
  for i = 1, n do
    local t = (n == 1) and 1 or (i - 1) / (n - 1)
    local f = t * (#TURTLE_COLS - 1)
    local a = math.floor(f)
    pal[i + 1] = G.lerp(TURTLE_COLS[a + 1], TURTLE_COLS[math.min(#TURTLE_COLS, a + 2)], f - a)
  end
  for i = n + 1, 14 do pal[i + 1] = 0xf4f4f4 end
  pal[15] = 0xf4f4f4     -- slot 14: always white (labels, menu)
  return pal
end

local function bandOf(y)
  local f = (y - E.Y_MIN) / (E.Y_MAX - E.Y_MIN)
  return math.max(1, math.min(E.BANDS, math.floor(f * E.BANDS) + 1))
end
local function bandFloor(b) return math.floor(E.Y_MIN + (b - 1) * (E.Y_MAX - E.Y_MIN) / E.BANDS + 0.5) end

local function TurtleView()
  local o = { ui = { fg = T_WHITE, bg = 0, hi = 3, btn = 2 } }
  local V = newViewport()
  local hits = {}
  local info = nil          -- { id, until }
  local lastDraw = -100

  local function fitAll()
    local x0, z0, x1, z1
    local function add(x, z)
      x0, x1 = math.min(x0 or x, x), math.max(x1 or x, x)
      z0, z1 = math.min(z0 or z, z), math.max(z1 or z, z)
    end
    for _, p in pairs(pylons) do add(p.x, p.z) end
    for _, t in ipairs(liveTurtles()) do add(t.pos.x, t.pos.z) end
    if not x0 then V.cx, V.cz, V.s = 0, 0, 1; return end
    fitTo(V, x0 - 8, z0 - 8, x1 + 8, z1 + 8)
  end

  local function draw()
    local px = {}
    local cells, used = {}, {}
    -- Pylons
    local np = 0
    for _, p in pairs(pylons) do
      np = np + 1
      local x, y = w2p(V, p.x, p.z)
      plus(px, x, y, T_RED)
    end
    -- Trails, then turtles on top
    local list = liveTurtles()
    for _, t in ipairs(list) do
      for i = 1, #t.trail - 1 do
        local p = t.trail[i]
        local x, y = w2p(V, p.x, p.z)
        local idx = gfx.pixelIndex(x, y)
        if idx then px[idx] = bandOf(p.y) end
      end
    end
    for _, t in ipairs(list) do
      local x, y = w2p(V, t.pos.x, t.pos.z)
      local b = bandOf(t.pos.y)
      blob(px, x, y, b)
      local stale = os.clock() - t.seen > E.STALE
      placeLabel(cells, used, x, y, short(t.label, t.id) .. (stale and "?" or ""), b, 0)
    end
    gfx.setOverlay(px)
    gfx.setLayer("labels", cells)

    -- Title
    local tc = {}
    gfx.text(tc, 2, 1, ("TURTLE MAP  %d turtle%s  %d pylon%s"):format(#list, #list == 1 and "" or "s", np,
      np == 1 and "" or "s"), T_WHITE, 0)
    local scale = V.s >= 1 and ("1 px = %s block%s"):format(V.s, V.s == 1 and "" or "s")
      or ("1 block = %d px"):format(math.floor(1 / V.s + 0.5))
    gfx.text(tc, 2, 2, scale .. "   N is up" .. (V.auto and "" or "   (moved: FIT to follow)"), T_WHITE, 0)
    gfx.setLayer("title", tc)

    -- Height key down the right edge (top = high)
    local lc = {}
    local _, by = burgerGeom()
    local room = by - 4
    local step = math.max(1, math.floor(room / E.BANDS))
    if step >= 1 and room >= E.BANDS then
      local x = gfx.W - 8
      gfx.text(lc, x, 2, "HEIGHT", T_WHITE, 0)
      for i = 0, E.BANDS - 1 do
        local b = E.BANDS - i
        local y = 3 + i * step
        gfx.box(lc, x, y, 2, math.max(1, step - (step > 2 and 1 or 0)), b)
        local lbl = tostring(bandFloor(b)) .. "+"
        gfx.text(lc, x + 3, y, lbl, T_WHITE, 0)
      end
      local y = 3 + E.BANDS * step
      if y < by - 1 then
        gfx.text(lc, x, y, "+", T_RED, 0)
        gfx.text(lc, x + 2, y, "pylon", T_WHITE, 0)
      end
    end
    gfx.setLayer("legend", lc)

    -- Buttons, bottom left
    local bc = {}
    local bh = gfx.H >= 30 and 3 or 1
    hits = buttonRow(bc, 2, gfx.H - bh, {
      { id = "out", label = " - " }, { id = "in", label = " + " }, { id = "fit", label = "FIT", on = V.auto } }, o.ui, bh)
    gfx.setLayer("buttons", bc)

    -- Details box for a tapped turtle
    local ic = {}
    if info and os.clock() < info.untilT and turtles[info.id] and turtles[info.id].pos then
      local t = turtles[info.id]
      local lines = {
        tostring(t.label or ("#" .. t.id)),
        ("%s %s"):format(tostring(t.state or "?"), t.msg and t.msg ~= "" and ("- " .. t.msg) or ""),
        ("At %d %d %d"):format(t.pos.x, t.pos.y, t.pos.z),
        ("Fuel %s   heard %s ago"):format(tostring(t.fuel or "?"), ago(t.seen)),
      }
      local w = 0
      for _, l in ipairs(lines) do w = math.max(w, #l) end
      w = math.min(w + 2, gfx.W - 4)
      local x, y = 3, 4
      gfx.box(ic, x, y, w, #lines + 2, 2)
      for i, l in ipairs(lines) do gfx.text(ic, x + 1, y + i, l:sub(1, w - 2), T_WHITE, 2) end
    else
      info = nil
    end
    gfx.setLayer("info", ic)
  end

  function o.enter()
    gfx.setPalette(turtlePalette())
    gfx.fill(0)
    if V.auto then fitAll() end
    lastDraw = -100
  end

  function o.step()
    if os.clock() - lastDraw < 1 then return end
    lastDraw = os.clock()
    if envChanged then gfx.setPalette(turtlePalette()) end
    if V.auto then fitAll() end
    draw()
  end

  function o.tap(cx, cy)
    local id = hitTest(hits, cx, cy)
    if id == "in" then V.s = zoomStep(V.s, -1); V.auto = false
    elseif id == "out" then V.s = zoomStep(V.s, 1); V.auto = false
    elseif id == "fit" then V.auto = true; fitAll()
    else
      -- A turtle near the tap?
      local best, bd = nil, 5
      for _, t in ipairs(liveTurtles()) do
        local x, y = w2p(V, t.pos.x, t.pos.z)
        local tx, ty = pixelToCell(x, y)
        local d = math.max(math.abs(tx - cx), math.abs(ty - cy))
        if d < bd then best, bd = t, d end
      end
      if best then
        info = { id = best.id, untilT = os.clock() + 12 }
      else
        V.cx, V.cz = p2w(V, cx * 2 - 0.5, cy * 3 - 1)
        V.auto = false
      end
    end
    lastDraw = -100
  end

  return o
end

---------------------------------------------------------------------------
-- Art screens
---------------------------------------------------------------------------
local function ArtView(name)
  local o = { ui = { fg = 15, bg = 0, hi = 7, btn = 0 } }
  local scene
  function o.enter()
    clearLayers()
    gfx.fill(0)
    scene = Scenes.new(gfx, name, { reseed = E.RESEED, speed = E.ART_SPEED })
    gfx.setPalette(scene.palette())
    local tc = {}
    gfx.setLayer("title", tc)
  end
  function o.step(dt) scene.step(dt) end
  function o.tap(cx, cy) scene.tap(cx, cy) end
  return o
end

---------------------------------------------------------------------------
-- Switching screens
---------------------------------------------------------------------------
local viewObjs = {}
local lastTouch, lastSwitch = os.clock(), os.clock()

local function makeView(id)
  if id == "turtles" then return TurtleView()
  else return ArtView(id) end
end

local function switchTo(id)
  if not VIEW_INDEX[id] then id = "turtles" end
  if not viewObjs[id] or id ~= "turtles" then viewObjs[id] = makeView(id) end
  current, currentId = viewObjs[id], id
  lastSwitch = os.clock()
  clearLayers()
  gfx.setOverlay({})
  current.enter()
  drawBurger(current.ui.fg, current.ui.bg)
  drawMenu(current.ui)
end

local function resetViews()
  viewObjs = {}
  initLayers()
  switchTo(currentId or E.DEFAULT_VIEW)
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local status = {}
local function showStatus()
  local w = term.getSize()
  term.setCursorPos(1, 1); term.clear()
  if term.isColour() then term.setTextColour(colours.cyan) end
  print("ART CONTROLLER")
  term.setTextColour(colours.white)
  local np = 0
  for _ in pairs(pylons) do np = np + 1 end
  print(("Monitor: %s"):format(mon and (("%s, %dx%d px"):format(monName, gfx.PW, gfx.PH)) or "none touching me"))
  print(("Showing: %s"):format(tostring(currentId)))
  print(("Turtles on the map: %d   Pylons: %d"):format(#liveTurtles(), np))
  print("")
  print("1 Turtles 2 Plasma 3 Rings 4 Aurora")
  print("Q = stop. Settings: art.env")
  if status.err then
    term.setTextColour(colours.red); print(status.err:sub(1, w * 3)); term.setTextColour(colours.white)
  end
end

local function uiLoop()
  local frame = 1 / E.FPS
  frameTimer = os.startTimer(frame)
  local last = os.clock()
  local lastStatus = -100
  while true do
    local ev = table.pack(os.pullEvent())
    local e = ev[1]
    if e == "timer" and ev[2] == frameTimer then
      refreshEnv()
      frame = 1 / E.FPS
      frameTimer = os.startTimer(frame)
      local dt = os.clock() - last
      last = os.clock()
      if gfx then
        local now = os.clock()
        if E.IDLE_RETURN > 0 and now - lastTouch > E.IDLE_RETURN and currentId ~= E.DEFAULT_VIEW
          and VIEW_INDEX[E.DEFAULT_VIEW] and (E.CYCLE <= 0) then
          switchTo(E.DEFAULT_VIEW)
        elseif E.CYCLE > 0 and now - lastTouch > E.CYCLE and now - lastSwitch > E.CYCLE then
          switchTo(VIEWS[VIEW_INDEX[currentId] % #VIEWS + 1].id)
        end
        if menuOpen and now - menuOpenedAt > 15 then menuOpen = false; drawMenu(current.ui) end
        local ok, err = pcall(current.step, dt)
        if not ok then status.err = "Screen error: " .. tostring(err) end
        envChanged = false
        local ok2, err2 = pcall(gfx.flush)
        if not ok2 then
          status.err = "Monitor error: " .. tostring(err2)
          if findMonitor() and gfx then resetViews() end
        end
      end
      if os.clock() - lastStatus > 2 then lastStatus = os.clock(); showStatus() end
      if frameTimer == nil then frameTimer = os.startTimer(frame) end
    elseif e == "monitor_touch" and gfx and ev[2] == monName then
      local cx, cy = ev[3], ev[4]
      lastTouch = os.clock()
      if inBurger(cx, cy) then
        menuOpen = not menuOpen
        menuOpenedAt = os.clock()
        drawMenu(current.ui)
      elseif menuOpen then
        local hit = menuHit(cx, cy)
        menuOpen = false
        if hit then switchTo(hit) else drawMenu(current.ui) end
      else
        local ok, err = pcall(current.tap, cx, cy)
        if not ok then status.err = "Tap error: " .. tostring(err) end
      end
    elseif e == "monitor_resize" or e == "peripheral" or e == "peripheral_detach" then
      if findMonitor() then
        if gfx then resetViews() else status.err = "Monitor gone: put an advanced monitor on a side." end
      end
    elseif e == "char" then
      local k = ev[2]:lower()
      if k == "q" then return end
      local n = tonumber(k)
      if n and VIEWS[n] and gfx then lastTouch = os.clock(); switchTo(VIEWS[n].id) end
    end
  end
end

local function netLoop()
  local any = false
  peripheral.find("modem", function(name, m)
    if m.isWireless() then rednet.open(name); any = true end
    return false
  end)
  if not any then
    status.err = "No ender/wireless modem: I can't hear the turtles."
    return os.pullEvent("never")
  end
  while true do
    local from, msg, proto = rednet.receive(nil, 0.5)
    if type(msg) == "table" and from then
      if proto == "tanis-miner" and msg.type == "status" then noteTurtle(from, msg, "canary")
      elseif proto == "tanis-farm" and msg.type == "status" then noteTurtle(from, msg, msg.role)
      elseif proto == "tanis-rigger" and msg.type == "status" then noteTurtle(from, msg, "weaver")
      elseif proto == CARTO and msg.type == "status" then noteTurtle(from, msg, "seagull")
      end
    end
  end
end

-- Ask every GPS host where it is: they're the pylons
local function pylonLoop()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then return os.pullEvent("never") end
  local reply = 64000 + os.getComputerID() % 1000
  while true do
    local found = {}
    modem.open(reply)
    modem.transmit(gps.CHANNEL_GPS, reply, "PING")
    local t = os.startTimer(2)
    while true do
      local e, side, ch, _, msg = os.pullEvent()
      if e == "timer" and side == t then break end
      if e == "modem_message" and ch == reply and type(msg) == "table" and #msg == 3
        and tonumber(msg[1]) and tonumber(msg[2]) and tonumber(msg[3]) then
        local x, y, z = math.floor(msg[1]), math.floor(msg[2]), math.floor(msg[3])
        found[x .. "," .. y .. "," .. z] = { x = x, y = y, z = z, seen = os.clock() }
      end
    end
    modem.close(reply)
    for k, p in pairs(found) do pylons[k] = p end
    for k, p in pairs(pylons) do
      if os.clock() - p.seen > 300 then pylons[k] = nil end
    end
    os.sleep(60)
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
readEnv()
math.randomseed(os.epoch("utc"))
term.clear()
findMonitor()
while not gfx do
  term.setCursorPos(1, 1)
  print("ART CONTROLLER")
  print("I need an ADVANCED monitor touching one of my sides.")
  os.pullEvent("peripheral")
  findMonitor()
end
initLayers()
switchTo(E.DEFAULT_VIEW)
parallel.waitForAny(uiLoop, netLoop, pylonLoop)
-- Stopped with Q: leave the wall tidy
if gfx then
  gfx.resetPalette()
  mon.setBackgroundColour(colours.black); mon.clear()
end
term.clear(); term.setCursorPos(1, 1)
print("Art controller stopped. Reboot (Ctrl+R) to start again.")
