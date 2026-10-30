-- wall.lua  --  the mainframe's monitor wall, built on the UI kit (docs/systems/mainframe.md).
-- island.lua, board.lua and butler.lua keep their logic and hand over what to show:
--   _G.WALL_STRIP     island: time, phase, weather, moon, nearby, the alert line
--   _G.WALL_BOARD     board: one row per machine { name, state, detail, seen, group }
--   _G.WALL_VISITORS  butler: who is around, and the "are you home" line
-- wall.run(mon, name) draws all three on one monitor; `name` is its peripheral name (monitor_touch needs it).
-- The wall is read-only: nothing to tap.
local ui = require("ui")

local wall = {}

local STRIP_ROWS = 3
local VISITOR_W  = 20     -- width of the visitor column at the right of the board
local VISITOR_MIN = 50    -- the visitor column appears at this width and up
local BIG_W, BIG_H = 120, 60
local PAGE_S     = 8      -- seconds a page of the board stays when the rows do not fit
local GROUPS = { "Storage", "Mining", "Farming", "Building", "Labs" }

-- Colour roles for state words the kit does not know (the kit's own map covers ok, working, waiting, error ...).
local TONE = { running = "good", paused = "warn", setup = "info" }

local function fit(s, n) return ui.text.fit(tostring(s), n) end

-- Where everything goes for a W x H wall. Pure, so a test can read it.
function wall.layout(W, H)
  local L = { W = W, H = H }
  if W >= BIG_W and H >= BIG_H then
    L.big = true
    L.sw = 44                                  -- station column
    L.vw = 26                                  -- visitor column
    L.bx, L.bw = L.sw + 2, W - L.sw - L.vw - 2
    L.vx = W - L.vw + 1
    L.top = 1
  else
    L.top = STRIP_ROWS + 2                     -- strip, rule, then the board header
    L.bx, L.bw = 1, W
    if W >= VISITOR_MIN then
      L.vw = VISITOR_W
      L.bw = W - L.vw - 1
      L.vx = L.bw + 2
    end
  end
  return L
end

local function age(seen)
  if type(seen) ~= "number" then return "never" end
  return math.max(0, os.clock() - seen)
end

---------------------------------------------------------------------------------------------------------
-- Island strip and station
---------------------------------------------------------------------------------------------------------
local function phaseTone(p) return p == "Night" and "bad" or "gold" end
local function weatherTone(w) return w == "Clear" and "idle" or "warn" end

local function dangerLine(st)
  if #st.hostile > 0 then
    local t = {}
    for _, e in ipairs(st.hostile) do t[#t + 1] = ("%s %.0fm"):format(e.name, e.d) end
    return " Danger: " .. table.concat(t, ", "), "bad"
  elseif st.alert then
    local more = st.alert.more > 0 and (" (+%d more)"):format(st.alert.more) or ""
    return (" ! " .. st.alert.text):sub(1, math.max(1, st.W - #more)) .. more, "warn"
  end
  return (" All clear (%d other thing%s nearby)"):format(st.others, st.others == 1 and "" or "s"), "good"
end

local function chip(v, x, y, text)
  if v.colour then v:put(x, y, " " .. text .. " ", "bg", "good") else v:put(x, y, "[" .. text .. "]", "fg", "bg") end
  return x + #text + 2
end

local function strip(v, L, st)
  local W = L.W
  if not st then
    v:put(2, 1, fit("Island station not running", W - 2), "dim", "bg")
    return
  end
  local x = chip(v, 1, 1, "ISLAND")
  x = v:put(x + 1, 1, st.time .. "  ", "fg", "bg")
  x = v:put(x, 1, st.phase, phaseTone(st.phase), "bg")
  x = v:put(x, 1, "  day " .. st.day .. "  ", "dim", "bg")
  v:put(x, 1, st.weather, weatherTone(st.weather), "bg")
  v:put(1, 2, fit((" Moon %s  Biome %s  Light %s/%s"):format(st.moon, st.biome, tostring(st.sky), tostring(st.block)), W),
    "dim", "bg")
  st.W = W
  local text, tone = dangerLine(st)
  v:put(1, 3, fit(text, W), tone, "bg")
end

local function rule(v, y, W)
  v:put(1, y, (v.colour and "\140" or "-"):rep(W), "bar", "bg")
end

-- The big wall's left column: the whole station with the nearby list.
local function station(v, L, st)
  v:boardHeader(1, 1, L.sw, "Island station")
  if not st then v:put(2, 3, "not running", "dim", "bg"); return end
  local y = 3
  y = v:kv(2, y, L.sw - 2, "Time", ("%s  (day %s)"):format(st.time, st.day))
  y = v:kv(2, y, L.sw - 2, "Phase", st.phase, phaseTone(st.phase))
  y = v:kv(2, y, L.sw - 2, "Weather", st.weather, weatherTone(st.weather))
  y = v:kv(2, y, L.sw - 2, "Moon", st.moon)
  y = v:kv(2, y, L.sw - 2, "Biome", st.biome)
  y = v:kv(2, y, L.sw - 2, "Light", ("sky %s  block %s"):format(tostring(st.sky), tostring(st.block)))
  if st.fuel then y = v:kv(2, y, L.sw - 2, "Fuel", tostring(st.fuel)) end
  st.W = L.sw - 2
  local text, tone = dangerLine(st)
  y = v:alert(2, y + 1, L.sw - 2, (text:gsub("^ !? ?", "")), tone) + 1
  v:section(2, y, L.sw - 2, ("Nearby (%dm)"):format(st.range or 16))
  y = y + 1
  if #st.near == 0 then v:put(2, y, "nothing", "dim", "bg") end
  for _, e in ipairs(st.near) do
    if y > L.H then break end
    y = v:kv(2, y, L.sw - 2, fit(e.name, 24), ("%.1fm"):format(e.d), st.hostiles[e.name] and "bad" or "fg")
  end
end

---------------------------------------------------------------------------------------------------------
-- Board
---------------------------------------------------------------------------------------------------------
-- Rows for the kit's v:board. On the big wall they come grouped under section labels.
local function boardItems(list, grouped)
  local items = {}
  local function row(r)
    items[#items + 1] = { name = r.name, state = r.state, detail = r.detail, age = r.seen and age(r.seen) or "never",
      color = TONE[r.state] or (not r.seen and "dim") or nil }
  end
  if not grouped then
    for _, r in ipairs(list) do row(r) end
    return items
  end
  local by = {}
  for _, r in ipairs(list) do
    local g = r.group or "Other"
    by[g] = by[g] or {}
    by[g][#by[g] + 1] = r
  end
  local order = {}
  for _, g in ipairs(GROUPS) do order[#order + 1] = g end
  if by.Other then order[#order + 1] = "Other" end
  for _, g in ipairs(order) do
    if by[g] then
      items[#items + 1] = { section = g }
      for _, r in ipairs(by[g]) do row(r) end
    end
  end
  return items
end

-- Cut items into pages of `cap` rows, never leaving a section label alone at the bottom of a page.
local function paginate(items, cap)
  local pages, cur = {}, {}
  for i, it in ipairs(items) do
    if #cur >= cap or (it.section and #cur >= cap - 1) then pages[#pages + 1] = cur; cur = {} end
    cur[#cur + 1] = it
  end
  if #cur > 0 or #pages == 0 then pages[#pages + 1] = cur end
  return pages
end

local function board(v, L, list)
  local items = boardItems(list or {}, L.big)
  local cap = L.H - L.top                       -- rows below the header
  local pages = paginate(items, cap)
  if #pages > 1 then pages = paginate(items, cap - 1) end   -- the last row shows where we are
  local page = #pages > 1 and (math.floor(os.clock() / PAGE_S) % #pages + 1) or 1
  local rows = pages[page]
  rows.title = "Machines"
  v:board(L.bx, L.top, L.bw, rows)
  if not list then v:put(L.bx + 1, L.top + 1, "no data yet", "dim", "bg") end
  if #pages > 1 then
    local dots = {}
    for i = 1, #pages do dots[i] = i == page and "o" or "." end
    local s = table.concat(dots, " ")
    v:put(L.bx + math.floor((L.bw - #s) / 2), L.H, s, "dim", "bg")
  end
end

---------------------------------------------------------------------------------------------------------
-- Visitors
---------------------------------------------------------------------------------------------------------
local function visitors(v, L, vis)
  local x, w = L.vx, L.vw
  v:boardHeader(x, L.top, w, "Visitors")
  if not vis then return end
  local y = L.top + 1
  if not vis.detector then
    v:put(x + 1, y, fit("No player detector", w - 1), "bad", "bg")
  elseif #vis.rows == 0 then
    v:put(x + 1, y, fit("Nobody yet", w - 1), "dim", "bg")
  end
  for _, e in ipairs(vis.rows) do
    if y > L.H - 2 then break end
    local nameW = math.max(1, w - #e.when - 3)
    v:put(x + 1, y, fit(e.name, nameW), e.here and "good" or "fg", "bg")
    v:put(x + w - #e.when, y, e.when, e.tone, "bg")
    y = y + 1
  end
  if vis.foot then v:put(x + 1, L.H, fit(vis.foot.text, w - 1), vis.foot.tone, "bg") end
end

---------------------------------------------------------------------------------------------------------
-- The wall
---------------------------------------------------------------------------------------------------------
function wall.draw(v)
  local L = wall.layout(v.W, v.H)
  local st, list, vis = _G.WALL_STRIP, _G.WALL_BOARD, _G.WALL_VISITORS
  if st then st = setmetatable({ W = L.W }, { __index = st }) end
  if L.big then station(v, L, st) else strip(v, L, st); rule(v, STRIP_ROWS + 1, L.W) end
  board(v, L, list)
  if L.vx then
    visitors(v, L, vis)
    -- the divider(s) between columns
    for y = L.big and 1 or L.top, L.H do
      if L.big then v:put(L.bx - 1, y, " ", "fg", "bar") end
      v:put(L.vx - 1, y, " ", "fg", "bar")
    end
  end
end

-- Draw the wall on `mon` (a monitor, peripheral name `name`) until the program ends.
function wall.run(mon, name)
  ui.loadAnim("wall.env")
  local v = ui.view(mon, { side = name })
  ui.run(v, function(view)
    local ok, err = pcall(wall.draw, view)
    if not ok then view:put(1, view.H, fit("wall: " .. tostring(err), view.W), "bad", "bg") end
  end, { tick = 1 })
end

return wall
