-- art_scenes.lua  --  the art controller's generative art: Plasma, Rings and Aurora.
--
-- How it moves without redrawing: every pixel holds a fixed colour NUMBER (1..14) worked out from
-- a pattern, and the palette behind those numbers slides along a looping gradient a little every
-- frame. Only 14 palette entries change per frame, so a full 328x243 wall animates for almost nothing.
-- A tap sends a ripple out from where you touched: a ring of shifted colours that grows and fades.
-- Each scene gets a new random pattern when it starts, and again after RESEED minutes without a tap.

local G = dofile("art_gfx.lua")

local S = {}

local NC = 14          -- colours 1..14 animate; 0 stays black, 15 stays white (menu, labels)

local SCENES = {
  plasma = {
    title = "Plasma",
    stops = { 0x1a0b3d, 0x5b1a7a, 0xb3246b, 0xff4f4f, 0xff9a3c, 0xffd866, 0xff9a3c, 0xb3246b, 0x5b1a7a },
    speed = 0.06,
    make = function(PW, PH)
      local a, b = 9 + math.random() * 14, 7 + math.random() * 12
      local c, d = 12 + math.random() * 20, 6 + math.random() * 10
      local cx, cy = math.random() * PW, math.random() * PH
      local rep = 1 + math.random()
      return function(x, y)
        local v = math.sin(x / a) + math.sin(y / b) + math.sin((x + y) / c)
          + math.sin(math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / d)
        return (v + 4) / 8 * rep
      end
    end,
  },
  rings = {
    title = "Rings",
    stops = { 0x03122b, 0x0a3d7a, 0x1479b8, 0x2fc3d6, 0x9df3ee, 0xf2fffe, 0x2fc3d6, 0x1479b8, 0x0a3d7a },
    speed = 0.05,
    make = function(PW, PH)
      -- Two ring centres interfering (their distances subtracted), plus one slow set of wide rings.
      -- Wide enough that a colour lap is never under ~13 pixels: finer than that turns to noise.
      local function spot() return { math.random() * PW, math.random() * PH } end
      local c1, c2, c3 = spot(), spot(), spot()
      local w = 34 + math.random() * 16
      local w3 = 60 + math.random() * 30
      return function(x, y)
        local d1 = math.sqrt((x - c1[1]) ^ 2 + (y - c1[2]) ^ 2)
        local d2 = math.sqrt((x - c2[1]) ^ 2 + (y - c2[2]) ^ 2)
        local d3 = math.sqrt((x - c3[1]) ^ 2 + (y - c3[2]) ^ 2)
        return (d1 - d2) / w + d3 / w3
      end
    end,
  },
  aurora = {
    title = "Aurora",
    stops = { 0x040612, 0x0b2a24, 0x12805a, 0x2ee6a0, 0x8ff7d0, 0x6a4cff, 0x2a145e, 0x0b0820 },
    speed = 0.035,
    make = function(PW, PH)
      local a, b = 14 + math.random() * 20, 30 + math.random() * 40
      local c, d = 5 + math.random() * 8, 20 + math.random() * 30
      local ph = math.random() * 6.28
      return function(x, y)
        return y / PH * 1.3 + 0.2 * math.sin(x / a + ph + 1.7 * math.sin(x / b))
          + 0.06 * math.sin(x / c + y / d)
      end
    end,
  },
}
S.LIST = { "plasma", "rings", "aurora" }
S.SCENES = SCENES

local RIPPLE_SPEED = 3      -- pixels per frame
local RIPPLE_BAND  = 7      -- ring thickness in pixels
local RIPPLE_AMP   = 0.45   -- colour shift at the crest (in "laps" of the gradient)
local MAX_RIPPLES  = 6

function S.new(gfx, name, opts)
  opts = opts or {}
  local def = SCENES[name] or SCENES.plasma
  local o = { name = name, title = def.title }
  local PW, PH = gfx.PW, gfx.PH
  local F = {}                 -- pattern value per pixel
  local field = nil
  local painted = 0            -- pixel rows painted so far
  local t = math.random()
  local ripples = {}
  local rmax = math.floor(math.max(PW, PH) * 0.45)
  local lastTap = os.clock()
  local speedMul = opts.speed or 1

  local function colourOf(v)
    return 1 + math.floor((v % 1) * NC) % NC
  end

  function o.reseed()
    field = def.make(PW, PH)
    painted = 0
  end

  function o.palette()
    local pal = { [1] = 0x000000, [16] = 0xffffff }
    for j = 1, NC do pal[j + 1] = G.loop(def.stops, (j - 1) / NC - t) end
    return pal
  end

  -- Value of a pixel including every ripple passing over it
  local function valueAt(x, y)
    local v = F[(y - 1) * PW + x]
    if not v then return nil end
    for _, r in ipairs(ripples) do
      local d = math.sqrt((x - r.x) ^ 2 + (y - r.y) ^ 2)
      local u = (r.r - d) / RIPPLE_BAND
      if u >= 0 and u <= 1 then
        v = v + r.amp * math.sin(u * math.pi)
      end
    end
    return v
  end

  local function repaint(x, y)
    local v = valueAt(x, y)
    if v then gfx.setPixel(x, y, colourOf(v)) end
  end

  function o.tap(cx, cy)
    lastTap = os.clock()
    if #ripples >= MAX_RIPPLES then table.remove(ripples, 1) end
    ripples[#ripples + 1] = { x = cx * 2 - 0.5, y = cy * 3 - 1, r = 0, amp = RIPPLE_AMP }
  end

  -- One frame: paint more of a new pattern, move the ripples, slide the palette
  function o.step(dt)
    if (opts.reseed or 0) > 0 and os.clock() - lastTap > opts.reseed * 60 and painted >= PH then
      lastTap = os.clock()
      o.reseed()
    end
    if painted < PH then
      local upto = math.min(PH, painted + 14)
      for y = painted + 1, upto do
        local row = (y - 1) * PW
        for x = 1, PW do
          local v = field(x, y)
          F[row + x] = v
          gfx.setPixel(x, y, colourOf(v))
        end
      end
      painted = upto
    end
    local keep = {}
    for _, r in ipairs(ripples) do
      local r0 = r.r
      r.r = r.r + RIPPLE_SPEED
      r.amp = RIPPLE_AMP * math.max(0, 1 - r.r / rmax)
      local inner = math.max(0, r0 - RIPPLE_BAND - 1)
      local outer = r.r
      local y0, y1 = math.max(1, math.floor(r.y - outer)), math.min(PH, math.ceil(r.y + outer))
      for y = y0, y1 do
        local dy = y - r.y
        local o2 = outer * outer - dy * dy
        if o2 >= 0 then
          local xo = math.floor(math.sqrt(o2))
          local xi = 0
          local i2 = inner * inner - dy * dy
          if i2 > 0 then xi = math.ceil(math.sqrt(i2)) end
          local cx = math.floor(r.x + 0.5)
          for x = math.max(1, cx - xo), math.min(PW, cx - xi) do repaint(x, y) end
          for x = math.max(1, cx + xi), math.min(PW, cx + xo) do repaint(x, y) end
        end
      end
      -- Its strength has faded to nothing by rmax, so the last ring it drew is already plain pattern
      if r.r - RIPPLE_BAND <= rmax then keep[#keep + 1] = r end
    end
    ripples = keep
    t = t + dt * def.speed * speedMul
    gfx.setPalette(o.palette())
  end

  function o.busy() return painted < PH or #ripples > 0 end

  o.reseed()
  return o
end

return S
