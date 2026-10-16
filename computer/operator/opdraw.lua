-- opdraw.lua  --  small drawing helpers for the Operator screens: the rods, the buffer bar with its threshold marks,
-- the << value >> stepper, a section label that keeps its case. Screen-local pieces the UI kit does not have.
local D = {}
local floor, max, min = math.floor, math.max, math.min

function D.num(n)
  if type(n) ~= "number" then return "?" end
  local s = tostring(floor(n + 0.5))
  local neg = s:sub(1, 1) == "-"
  if neg then s = s:sub(2) end
  s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (neg and "-" or "") .. s
end

function D.pct(f) return f and (floor(f * 100 + 0.5) .. "%") or "?" end

function D.fit(s, n)
  s = tostring(s)
  if n <= 0 then return "" end
  if #s <= n then return s end
  return n > 1 and (s:sub(1, n - 1) .. "~") or s:sub(1, n)
end

-- "2s", "3m", "1h"
function D.age(sec)
  if not sec then return "?" end
  if sec < 60 then return floor(sec) .. "s" end
  if sec < 3600 then return floor(sec / 60) .. "m" end
  return floor(sec / 3600) .. "h"
end

function D.clock(sec)
  sec = max(0, floor(sec or 0))
  return ("%d:%02d"):format(floor(sec / 60), sec % 60)
end

-- Section label that keeps its case (the kit's v:section upper-cases): text, then the rule to the edge.
function D.section(v, x, y, w, text, tone)
  text = D.fit(text, w - 2)
  local nx = v:put(x, y, text, tone or "dim", "bg")
  if w - #text - 1 > 0 then v:put(nx + 1, y, (v.colour and "\140" or "-"):rep(w - #text - 1), "bar", "bg") end
  return y + 1
end

-- A bar of w cells: fill in `role` over grey. frac nil = empty.
function D.track(v, x, y, w, frac, role)
  w = max(w, 1)
  local n = frac and floor(max(0, min(1, frac)) * w + 0.5) or 0
  if v.colour then
    if n > 0 then v:put(x, y, (" "):rep(n), "fg", role) end
    if w - n > 0 then v:put(x + n, y, (" "):rep(w - n), "fg", "bar") end
  else
    v:put(x, y, ("#"):rep(n) .. ("-"):rep(w - n), "fg", "bg")
  end
end

-- "Buffer ▥▥▥▦▦ 62%" on one row, no marks.
function D.barRow(v, x, y, w, label, frac, tone)
  local lab = label and (label .. " ") or ""
  local num = " " .. D.pct(frac)
  local tw = w - #lab - #num
  if tw < 4 then lab = ""; tw = w - #num end
  if tw < 4 then num = ""; tw = w end
  if #lab > 0 then v:put(x, y, lab, tone or "fg", "bg") end
  D.track(v, x + #lab, y, tw, frac, tone and "bar" or "good")
  if #num > 0 then v:put(x + #lab + tw, y, num, frac and (tone or "fg") or "dim", "bg") end
end

-- The buffer bar on row y ("Buffer ▥▥▥▦▦ 62%") and the threshold marks on row y+1 ("^on 30%   ^off 90%").
-- Returns the next free row. `label` may be nil (no word before the bar).
function D.buffer(v, x, y, w, frac, on, off, label)
  local lab = label and (label .. " ") or ""
  local num = " " .. D.pct(frac)
  local tw = w - #lab - #num
  if tw < 6 then lab = ""; tw = w - #num end
  if tw < 6 then num = ""; tw = w end
  local tx = x + #lab
  if #lab > 0 then v:put(x, y, lab, "fg", "bg") end
  D.track(v, tx, y, tw, frac, "good")
  if #num > 0 then v:put(tx + tw, y, num, frac and "fg" or "dim", "bg") end
  local function mark(f, long, short, alignRight)
    local px = tx + floor(f * tw)
    local t = "^" .. long
    if alignRight and px + #t > x + w then px = x + w - #t end
    return px, t, "^" .. short
  end
  local onx, ont, ons = mark(on, "on " .. floor(on * 100 + 0.5) .. "%", floor(on * 100 + 0.5))
  local offx, offt, offs = mark(off, "off " .. floor(off * 100 + 0.5) .. "%", floor(off * 100 + 0.5), true)
  if onx + #ont + 1 > offx then ont, offt = ons, offs; offx = min(offx, x + w - #offt) end
  v:put(onx, y + 1, ont, "dim", "bg")
  v:put(offx, y + 1, offt, "dim", "bg")
  return y + 2
end

-- Rods: one column per rod (up to 8; more rods are averaged in groups), `rw` wide and `rh` tall. Grey where the rod
-- is inserted, lime where it is withdrawn (light blue when the reactor is off). Returns the width drawn and a caption.
function D.rods(v, x, y, levels, rw, rh, running)
  if not levels or #levels == 0 then
    v:put(x, y, "rods not readable", "dim", "bg")
    return 17, "rods not readable"
  end
  local n = #levels
  local cols = min(n, 8)
  local lo, hi = 100, 0
  for _, l in ipairs(levels) do lo, hi = min(lo, l), max(hi, l) end
  local role = running and "good" or "idle"
  for c = 1, cols do
    local a, b = floor((c - 1) * n / cols) + 1, floor(c * n / cols)
    local sum = 0
    for i = a, b do sum = sum + levels[i] end
    local lvl = sum / (b - a + 1)
    local ins = floor(rh * (100 - lvl) / 100 + 0.5)
    local cx = x + (c - 1) * (rw + 1)
    for r = 1, rh do
      if r <= ins then
        if v.colour then v:fill(cx, y + r - 1, rw, "bar") else v:put(cx, y + r - 1, ("."):rep(rw), "fg", "bg") end
      else
        if v.colour then v:fill(cx, y + r - 1, rw, role) else v:put(cx, y + r - 1, ("#"):rep(rw), "fg", "bg") end
      end
    end
  end
  local width = cols * (rw + 1) - 1
  local insLo, insHi = floor(100 - hi + 0.5), floor(100 - lo + 0.5)
  local cap
  if insLo == insHi then
    cap = n == 1 and ("The rod is at %d%% in"):format(insLo) or ("All %d rods at %d%% in"):format(n, insLo)
  else
    cap = ("%d rods, %d%% to %d%% in"):format(n, insLo, insHi)
  end
  return width, cap
end

-- ░<<░ 60% ░>>░  -- two pills around a value. Returns the next free x. `dec`/`inc` are tap functions (or nil to
-- disable); the pair joins the Tab order and takes Left/Right.
function D.pair(v, x, y, text, dec, inc, id, valueW)
  valueW = valueW or 5
  local cx = v:_pill(x, y, { label = "<<", id = id .. "<", enabled = dec ~= nil, noFocus = true, fn = dec or function() end }, 1)
  local t = tostring(text)
  local pad = max(valueW - #t, 0)
  local left = floor(pad / 2)
  cx = cx + 1
  v:put(cx, y, (" "):rep(left) .. t .. (" "):rep(pad - left), "fg", "bg")
  cx = cx + valueW + 1
  local ex = v:_pill(cx, y, { label = ">>", id = id .. ">", enabled = inc ~= nil, noFocus = true, fn = inc or function() end }, 1)
  local box = v:_box({ x, y, ex - 1, y }, nil, { id = id, focus = dec ~= nil or inc ~= nil,
    stepper = { dec = dec or function() end, inc = inc or function() end, dec10 = dec or function() end, inc10 = inc or function() end } })
  box.fn = function() end
  box.tx1, box.ty1, box.tx2, box.ty2 = 0, 0, -1, -1
  if v.focus == id and x > 1 then v:put(x - 1, y, ">", "fg", "bg") end
  return ex
end

return D
