-- architect_site.lua  --  wizard step 3 (Site) and step 4 (Go). docs/design/architect-fleet.md. A part of architect.lua.

local floor, max, min = math.floor, math.max, math.min
local HEAD = { N = 0, E = 1, S = 2, W = 3 }
local HLET = { [0] = "N", "E", "S", "W" }

local function whole(t) if not t:match("^%-?%d+$") then return "a whole number" end end
local FIELDS = { "dx", "dy", "dz", "cx", "cy", "cz" }
local function fieldOf(k) return ui.field({ hint = "0", max = 8, validate = whole }) end
V.sf = {}
for _, k in ipairs(FIELDS) do V.sf[k] = fieldOf(k) end
V.dh, V.rot, V.siteInit = "N", 0, false

local function initSite()
  if V.siteInit then return end
  V.siteInit = true
  local s = S.site
  if siteOK(s) then
    for _, k in ipairs(FIELDS) do V.sf[k].text = tostring(s[k]) end
    V.dh, V.rot = HLET[s.dh] or "N", s.rot or 0
  end
end

-- the site the fields describe, or nil
function siteFromFields()
  local s = { dh = HEAD[V.dh], rot = V.rot }
  for _, k in ipairs(FIELDS) do
    local t = V.sf[k].text
    if not t:match("^%-?%d+$") then return nil end
    s[k] = tonumber(t)
  end
  return s
end

local function preview(v, x, y, w, h, s)
  local ew, ns = footprint(s.rot)
  local fx1, fx2, fz1, fz2 = s.cx, s.cx + ew - 1, s.cz - ns + 1, s.cz
  local bx1, bx2, bz1, bz2 = min(fx1, s.dx) - 1, max(fx2, s.dx) + 1, min(fz1, s.dz) - 1, max(fz2, s.dz) + 1
  local bw, bh = bx2 - bx1 + 1, bz2 - bz1 + 1
  -- blocks per character: the same on both axes (a character is about twice as tall as wide, so rows count double)
  local per = max(bw / w, bh / (h * 1.0))
  local thick = per * 2
  for r = 0, h - 1 do
    local cells = {}
    for c = 0, w - 1 do
      local x1, x2 = bx1 + c * per, bx1 + (c + 1) * per - 1
      local z1, z2 = bz1 + r * per, bz1 + (r + 1) * per - 1
      local ch, fg, bg = " ", "fg", "bg"
      local inter = x2 >= fx1 and x1 <= fx2 and z2 >= fz1 and z1 <= fz2
      if inter then
        local inner = x1 >= fx1 + thick and x2 <= fx2 - thick and z1 >= fz1 + thick and z2 <= fz2 - thick
        bg = inner and "bg" or "info"
      end
      if s.dx >= x1 - 0.01 and s.dx <= x2 + 0.01 and s.dz >= z1 - 0.01 and s.dz <= z2 + 0.01 then ch, fg, bg = "D", "bg", "gold" end
      cells[#cells + 1] = { ch, fg, bg }
    end
    v:cells(x, y + r, cells)
  end
end

function drawStep3(v)
  initSite()
  local W = v.W
  v:put(2, 4, "Read F3 standing there. Block, not XYZ.", "dim", "bg")
  local function triple(y, name, keys, tags)
    v:put(2, y, name, "fg", "bg")
    local x = 16
    for i, k in ipairs(keys) do x = v:field(x, y, tags[i], 7, V.sf[k]) + 1 end
  end
  triple(5, "Weaver's dock", { "dx", "dy", "dz" }, { "x", "y", "z" })
  v:put(2, 6, "He faces", "fg", "bg")
  v:switch(16, 6, { "N", "E", "S", "W" }, V.dh, function(id) V.dh = id end, { id = "dh", maxx = W })
  triple(7, "Corner (SW)", { "cx", "cy", "cz" }, { "X", "Y", "Z" })
  v:put(2, 8, "Turn", "fg", "bg")
  v:switch(16, 8, { { id = 0, label = "0" }, { id = 90, label = "90" }, { id = 180, label = "180" }, { id = 270, label = "270" } },
           V.rot, function(id) V.rot = id end, { id = "rot", maxx = W })
  local s = siteFromFields()
  if not s then
    v:put(2, 10, "Fill in all six numbers.", "dim", "bg")
    return false
  end
  local ew, ns = footprint(s.rot)
  preview(v, 3, 10, 26, 7, s)
  v:put(31, 10, "North up", "dim", "bg")
  v:put(31, 11, ("%d wide E-W"):format(ew), "fg", "bg")
  v:put(31, 12, ("%d deep N-S"):format(ns), "fg", "bg")
  v:put(31, 14, " ", "bg", "info"); v:put(33, 14, "build", "dim", "bg")
  v:put(31, 15, "D", "bg", "gold"); v:put(33, 15, "dock", "dim", "bg")
  local dx, dz = s.cx - s.dx, s.cz - s.dz
  v:put(2, 17, fit(("Corner is %d %s, %d %s of the dock. Needs %d x %d."):format(math.abs(dx), dx >= 0 and "E" or "W",
        math.abs(dz), dz <= 0 and "N" or "S", ew, ns), W - 2), "dim", "bg")
  if dockInside(s) then
    v:put(2, 18, "The dock is inside the build.", "bad", "bg")
    return false
  end
  local face = ({ [0] = "north", "east", "south", "west" })[rotSteps(s.rot)]
  v:put(2, 18, fit(("turn %d: the file's north side faces %s"):format(s.rot, face), W - 2), "dim", "bg")
  local o = S.order
  local st = R.status
  local function busy(word) return o and o.word == word end
  v:buttons(2, v.H - 1, {
    { label = "Test", style = busy("test") and "busy" or "idle", id = "b-test",
      fn = function() if not S.started then S.site = s; save() end; sendOrder("test") end },
    { label = "Clear", style = busy("clear") and "busy" or "idle", id = "b-clear", fn = function() sendOrder("clear") end },
  })
  if st and st.state == "marking" then v:put(20, v.H - 1, ("marking %d/4"):format(st.marked or 0), "info", "bg")
  elseif st and (st.marks or 0) > 0 then v:put(20, v.H - 1, "markers out, type clear", "warn", "bg") end
  return true
end

function step3Next()
  S.site = siteFromFields()
  S.started = false
  save()
  LC, V.grid = {}, nil
  nextStep()
end

function drawStep4(v)
  local W, y = v.W, 5
  local st = R.status
  local ok = S.n and alive() and st
  local function row(k, text, tone) v:put(2, y, k, "dim", "bg"); v:put(11, y, fit(text, W - 11), tone or "fg", "bg"); y = y + 1 end
  if ok then row("Weaver", ("Weaver-%02d, %s, fuel %s"):format(S.n, tostring(st.state), comma(st.fuel or 0)), "good")
  else row("Weaver", ("Weaver-%02d not heard yet, is he on?"):format(S.n or 0), "warn") end
  row("Build", ("%s, %d layers"):format(S.name or "?", P.total))
  local s = S.site
  row("Site", ("SW corner %d %d %d, turn %d"):format(s.cx, s.cy, s.cz, s.rot or 0))
  local kinds, short = 0, 0
  for item, n in pairs(P.plan.info.items or P.plan.info.bill) do
    kinds = kinds + 1
    if R.stock and (R.stock[item] or 0) < n then short = short + 1 end
  end
  row("Bill", R.stock and (short == 0 and "storage has everything" or ("short of %d kinds (gaps are fine)"):format(short)) or "storage not heard yet",
      R.stock and (short == 0 and "good" or "warn") or "dim")
  local secs, fuel = estimate()
  row("Time", ("about %s, fuel about %s"):format(hms(secs), comma(fuel)))
  y = y + 1
  v:put(2, y, "He sends the bill to storage, asks for the", "dim", "bg")
  v:put(2, y + 1, "first batch, then starts the bottom layer.", "dim", "bg")
  return ok and true or false
end

function startNext()
  if startBuild() then V.mode, V.tab = "tabs", "status" end
end

function drawWizard(v)
  if V.step == 2 and V.sub2 then drawStep2List(v); return end
  local ok
  local nxt
  if V.step == 1 then ok = drawStep1(v); nxt = { ok = ok, fn = step1Next }
  elseif V.step == 2 then ok = drawStep2(v); nxt = { ok = ok, fn = function() nextStep() end }
  elseif V.step == 3 then ok = drawStep3(v); nxt = { ok = ok, fn = step3Next }
  else ok = drawStep4(v); nxt = { ok = ok, fn = startNext, label = "Start build" } end
  wizFrame(v, nxt)
end
