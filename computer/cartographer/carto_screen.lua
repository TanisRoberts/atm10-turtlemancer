-- carto_screen.lua  --  the Cartographer's own screen (51 x 19), on the UI kit: a small copy of the map, Seagull's
-- panel, the next region, storage, and the map controls. Spec: docs/design/cartographer.md.
--
--   local screen = require("carto_screen").new(sh)      sh: { store, painter, st, act, field, cmds }
--   ui.run({ view }, screen.draw, ...)
local ui = require("ui")
local G = dofile("art_gfx.lua")
local P = require("carto_paint")
local F = require("carto_floor")
local R = require("carto_store")
local K = P.K

local S = {}

local function fit(s, n) return ui.text.fit(s, n) end

local function ago(secs)
  secs = math.floor(secs)
  if secs < 60 then return secs .. "s" elseif secs < 3600 then return math.floor(secs / 60) .. "m" end
  return math.floor(secs / 3600) .. "h"
end

function S.new(sh)
  local o = { sh = sh }
  local st, store, act = sh.st, sh.store, sh.act
  local thumb = nil          -- { gfx, pane, w, h, key }

  -- The small map: a gfx surface of its own that is read back as characters
  local function thumbFor(w, h)
    if thumb and thumb.w == w and thumb.h == h then return thumb end
    local fake = { getSize = function() return w, h end }
    local gfx = G.new(fake)
    thumb = { w = w, h = h, gfx = gfx, pane = P.pane(gfx, sh.painter, { cx = 0, cz = 0, s = 1 }) }
    return thumb
  end

  -- The view the small map shows: the floor's centre and zoom, scaled up so the same ground fits in it
  local function thumbView(t)
    local v = st.view
    local fw, fh = st.floorPx and st.floorPx.w or 312, st.floorPx and st.floorPx.h or 243
    local k = math.max(fw / t.gfx.PW, fh / t.gfx.PH, 1)
    return { cx = v.cx, cz = v.cz, s = v.s * k }
  end

  function o.tap(t, view, x, y)
    -- (x, y) is the character cell the tap landed on, relative to the screen
    local wx, wz = t.pane:p2w((x - t.x1) * 2 + 1.5, (y - t.y1 + 1) * 3 - 1, view)
    local rx, rz = R.regionOf(math.floor(wx / 16), math.floor(wz / 16))
    act.tapMap(wx, wz, rx, rz)
  end

  ---------------------------------------------------------------------------
  -- The colour key (its own page)
  ---------------------------------------------------------------------------
  local function drawKey(v)
    v:header("Cartographer", { state = "colour key" })
    local y = 4
    local function row(colour, text, mark)
      v:put(3, y, mark or "  ", "bg", colour)
      v:put(7, y, text, "fg", "bg")
      y = y + 1
    end
    local C = colours or colors
    row(C.blue, "deep water"); row(C.lightBlue, "shallow water"); row(C.green, "trees")
    for i = #P.BANDS, 1, -1 do
      local f = P.bandFloor(i)
      row(C[P.BANDS[i]], i == 1 and "beach (sea level)" or ("land from y " .. f))
    end
    y = y + 1
    row(C.black, "never seen: dark, with a faint dot (and the region grid)", ". ")
    row(C.white, "turtles; white outline = the next region", "\7 ")
    row(C.red, "GPS pylon", "+ ")
    row(C.cyan, "cyan outline = Seagull is scanning it, with ~%")
    v:footer({ back = function() st.page = "main" end })
  end

  ---------------------------------------------------------------------------
  -- The main page
  ---------------------------------------------------------------------------
  local function panel(v, x, w, y, maxY)
    local sg, now = st.seagull, os.clock()
    local function kv(k, val, tone)
      if y <= maxY then v:kv(x, y, w, k, val, tone) end
      y = y + 1
    end
    local function section(t)
      if y <= maxY then v:section(x, y, w, t) end
      y = y + 1
    end
    section("Seagull")
    if not sg then
      kv("", "not heard yet", "dim")
    else
      local off = now - (st.seagullSeen or 0)
      local quiet = off > 30
      kv(fit(tostring(sg.label or "Seagull"), w - 12), tostring(sg.state or "?"), ui.stateRole(tostring(sg.state)))
      local here = st.seagullRegion
      if here then kv("Region", ("%d,%d  ring %d"):format(here[1], here[2], st.seagullRing or 0)) end
      if st.scan then kv("Scan", st.scan.pct and ("~%d%%"):format(st.scan.pct) or "scanning") end
      local f, fl = tonumber(sg.fuel), tonumber(sg.fuelLimit)
      if f then
        local pct = fl and fl > 0 and math.floor(f / fl * 100) or nil
        kv("Fuel", pct and (pct .. "%") or tostring(f), pct and pct < 20 and "warn" or "fg")
      end
      local where = type(sg.pos) == "table" and ("%d,%d"):format(sg.pos.x or 0, sg.pos.z or 0) or ""
      kv(quiet and ("off radio " .. ago(off)) or "on the radio", where, quiet and "warn" or "dim")
    end
    y = y + 1
    section("Next")
    local n1 = st.nextRegion
    local up = sh.upcoming and sh.upcoming(2) or {}
    if not n1 and up[1] then n1 = { rx = up[1][1], rz = up[1][2] } end
    kv(n1 and ("Region %d,%d"):format(n1.rx, n1.rz) or "Nothing left near", st.nextRegion and "you" or "spiral",
       st.nextRegion and "fg" or "dim")
    local after = st.nextRegion and up[1] or up[2]
    if after and y <= maxY then kv("then", ("%d,%d (spiral)"):format(after[1], after[2]), "dim") end
    y = y + 1
    section("Storage")
    local mounts, room = st.gauge and st.gauge[1] or {}, st.gauge and st.gauge[2] or 0
    for i, m in ipairs(mounts) do
      if y > maxY - 1 then break end
      local pct = m.capacity > 0 and math.floor(m.used / m.capacity * 100) or 0
      local tone = pct > 95 and "bad" or pct > 80 and "warn" or "fg"
      kv(i == 1 and "Disk" or m.name, pct .. "%", tone)
    end
    kv("", ("room for ~%d regions"):format(room), "dim")
  end

  local function drawMain(v)
    local nReg = store:regionCount()
    local sg = st.seagull
    local state = sg and tostring(sg.state or "?") or "no Seagull"
    v:header("Cartographer", { state = state, color = sg and ui.stateRole(state) or "dim",
                               right = nReg .. " region" .. (nReg == 1 and "" or "s") })
    local typed = not v.side
    local H, W = v.H, v.W
    local top, bot = 3, H - 3
    local tw, th = math.min(23, W), bot - top + 1
    local wide = W >= 40
    if th >= 3 then
      local t = thumbFor(tw, th)
      local view = thumbView(t)
      t.pane.view = view
      local key = table.concat({ view.cx, view.cz, view.s, tw, th, st.mapRev or 0 }, ",")
      if key ~= t.key then
        t.key = key
        t.gfx.fill(K.black)
        t.pane:paintAll(view)
      end
      local px = F.overlay(t.pane, t.gfx, st, false, view)
      if st.pick then
        local pk = st.pick
        t.pane:outline(px, pk.rx * 256, pk.rz * 256, pk.rx * 256 + 255, pk.rz * 256 + 255, K.white, view)
      end
      t.gfx.setOverlay(px)
      for cy = 1, th do
        local chs, fgs, bgs = {}, {}, {}
        for cx = 1, tw do chs[cx], fgs[cx], bgs[cx] = t.gfx.encode(cx, cy) end
        v:_write(1, top + cy - 1, table.concat(chs), table.concat(fgs), table.concat(bgs))
      end
      local rect = { x1 = 1, y1 = top, x2 = tw, y2 = top + th - 1, pane = t.pane }
      st.thumbRect = rect
      v:_box({ rect.x1, rect.y1, rect.x2, rect.y2 }, nil, { id = "thumb", fn = function(x, y)
        o.tap({ x1 = rect.x1, y1 = rect.y1, pane = t.pane }, view, x, y)
      end })
    end
    if wide then
      for y = top, bot do v:put(tw + 1, y, "\149", "bar", "bg") end
      panel(v, tw + 3, W - tw - 3, top, bot)
    end
    -- controls
    local y = H - 2
    local pad = function(dx, dz) return function() act.pan(dx, dz) end end
    local list = {
      { label = "MAP", style = "primary", fn = function() act.order("map") end },
      { label = "DOCK", fn = function() act.order("dock") end },
      { label = "<", fn = pad(-1, 0) }, { label = ">", fn = pad(1, 0) },
      { label = "^", fn = pad(0, -1) }, { label = "v", fn = pad(0, 1) },
      { label = "-", fn = function() act.zoom(1) end }, { label = "+", fn = function() act.zoom(-1) end },
      { label = "FIT", style = st.view.fit and "on" or "idle", fn = function() act.fit() end },
    }
    v:buttons(2, y, list, { gap = 1 })
    if typed then
      st.field = st.field or ui.field({ hint = "/ = commands (/help)" })
      v:search(st.field, { hint = "/map  /dock  /next 2,0  /goto x z  /fit  /help", commands = sh.cmds:commands() })
    end
    v:footer({})
    v:put(2, H, fit("tap map: pick next region", W - 10), "dim", "bg")
    v:buttons(W - 5, H, { { label = "Key", fn = function() st.page = "key" end } })
    -- keys typed into an empty command bar: - + f act as map keys (the bar gets them too, so take them back out)
    if st.stripNext and st.field and st.field.text == st.stripNext then st.field.text = "" end
    st.stripNext = nil
  end

  function o.draw(v)
    if st.page == "key" then drawKey(v) else drawMain(v) end
  end

  return o
end

return S
