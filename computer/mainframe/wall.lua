-- wall.lua  --  the mainframe's monitor wall, built on the UI kit (docs/systems/mainframe.md).
-- island.lua, board.lua and butler.lua keep their logic and hand over what to show:
--   _G.WALL_STRIP     island: time, phase, weather, moon, nearby, the alert line
--   _G.WALL_BOARD     board: one row per machine { name, state, detail, seen, group }
--   _G.WALL_VISITORS  butler: who is around, and the "are you home" line
-- wall.run(mon, name) draws all three on one monitor; `name` is its peripheral name (monitor_touch needs it).
-- The wall is read-only: nothing to tap.
local ui = require("ui")
local opfmt = require("operator_fmt")

local wall = {}

local STRIP_ROWS = 3
local VISITOR_W  = 20     -- width of the visitor column at the right of the board
local VISITOR_MIN = 50    -- the visitor column appears at this width and up
local BIG_W, BIG_H = 120, 60
local PAGE_S     = 8      -- seconds a page of the board stays when the rows do not fit
local GLANCE_W, GLANCE_H = 80, 40   -- the floor-readable wall (docs/design/mainframe.md, "Wall 82x40")
local SLOTS = 9                    -- two-row board entries a page on it
local GROUPS = { "Storage", "Mining", "Farming", "Building", "Labs" }

-- Colour roles for state words the kit does not know (the kit's own map covers ok, working, waiting, error ...).
local TONE = { running = "good", paused = "warn", setup = "info" }

local function fit(s, n) return ui.text.fit(tostring(s), n) end

-- Where everything goes for a W x H wall. Pure, so a test can read it.
function wall.layout(W, H)
  local L = { W = W, H = H }
  if W >= GLANCE_W and H >= GLANCE_H and not (W >= BIG_W and H >= BIG_H) then
    L.glance = true
    L.vw = VISITOR_W                           -- visitors at the right, columns 63-82 on 82 wide
    L.bx, L.bw, L.top = 1, W - L.vw - 1, 1
    L.vx = L.bw + 2
    L.ruleY = SLOTS * 2 + 3                    -- 21: the thin rule under the board
    L.dotsY = L.ruleY - 1                      -- 20: page dots and the visitor foot
    L.footY, L.lastY = L.dotsY, L.dotsY - 1
    L.gy = L.ruleY + 2                         -- 23: chip and header row of the glance
    L.cw = 38                                  -- clock column x 2..39, divider at 40, power column from 42
    L.px, L.pw = 42, W - 41
    L.needY = L.gy + 11                        -- 34: NEEDS YOU label, four slots under it
    L.islandY = H                              -- 40
  elseif W >= BIG_W and H >= BIG_H then
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
    if y > (L.lastY or L.H - 2) then break end
    local nameW = math.max(1, w - #e.when - 3)
    v:put(x + 1, y, fit(e.name, nameW), e.here and "good" or "fg", "bg")
    v:put(x + w - #e.when, y, e.when, e.tone, "bg")
    y = y + 1
  end
  if vis.foot then v:put(x + 1, L.footY or L.H, fit(vis.foot.text, w - 1), vis.foot.tone, "bg") end
end

---------------------------------------------------------------------------------------------------------
-- The 82x40 wall: board on top, the glance (clock, power, Needs you, island line) below
---------------------------------------------------------------------------------------------------------
local BAD_STATE = { lost = true, error = true, offline = true, stuck = true, failed = true }

-- Power for the power column: { digits, tone, tag, line1, line2, tone2 }. `pw` is the Operator's fresh record or nil.
-- pw.limit (FE/t, set by #121 only while throttled), pw.asked (FE/t the base wanted), pw.askedFor (seconds).
local function powerView(pw, op)
  if not pw then return { digits = "--", tone = "dim", line1 = "Operator not reporting", tone1 = "dim" } end
  local pot = tonumber(pw.potential) or 0
  local buf = op and op.plant and op.plant.buf
  local bufText = buf and (math.floor(buf * 100 + 0.5) .. "%") or "?"
  if pw.limit then
    local capped = pot > 0 and math.floor(pw.limit / pot * 100 + 0.5) or pw.pct
    local out = { digits = capped .. "%", tone = "bad", tag = "THROTTLED", tone1 = "fg",
      line1 = ("Throttled at %s FE/t"):format(opfmt.num(pw.limit)) }
    if pw.asked then
      local askedPct = pot > 0 and math.floor(pw.asked / pot * 100 + 0.5) or 0
      local secs = tonumber(pw.askedFor)
      out.line2 = ("Asked for %s (%d%%)%s"):format(opfmt.num(pw.asked), askedPct,
        secs and (" for " .. (secs >= 60 and (math.floor(secs / 60) .. "m") or (math.floor(secs) .. "s"))) or "")
      out.tone2 = "bad"
    end
    return out
  end
  local pct = math.floor(pw.pct + 0.5)
  local out = { digits = pct .. "%", tone1 = "fg", line1 = ("%s of %s FE/t"):format(opfmt.num(pw.draw), opfmt.num(pot)) }
  if pct >= 100 then
    out.tone = "warn"
    out.line2 = ("Over output, buffer %s%s"):format(bufText, pw.draw > pot and " falling" or "")
    out.tone2 = "warn"
  else
    out.tone = "good"
    out.line2, out.tone2 = "Buffer " .. bufText, "dim"
  end
  out.line3 = opfmt.avgText(op)
  return out
end

-- Alerts for the Needs you slots, from the board rows (lost/error red, waiting orange) and the power limit.
local function needs(list, pw)
  local alerts = {}
  if pw and pw.limit then
    local pot = tonumber(pw.potential) or 0
    local want = pw.asked and pot > 0 and ("%d%% of the reactor"):format(math.floor(pw.asked / pot * 100 + 0.5))
      or "more than the reactor makes"
    alerts[#alerts + 1] = { text = "Power throttled: the base wants " .. want .. ". Add power.", tone = "bad", name = "Power" }
  end
  local n, working, docked, lost = 0, 0, 0, 0
  for _, r in ipairs(list or {}) do
    n = n + 1
    local name, state = (r.name or ""):gsub("^%s+", ""), tostring(r.state)
    local text = name .. " " .. state .. ((r.detail and r.detail ~= "") and (": " .. r.detail) or "")
    if BAD_STATE[state] then lost = lost + 1; alerts[#alerts + 1] = { text = text, tone = "bad", name = name }
    elseif state == "waiting" then alerts[#alerts + 1] = { text = text, tone = "warn", name = name }
    elseif state == "working" then working = working + 1
    elseif state == "docked" then docked = docked + 1 end
  end
  local parts = {}
  if working > 0 then parts[#parts + 1] = working .. " working" end
  if docked > 0 then parts[#parts + 1] = docked .. " docked" end
  parts[#parts + 1] = lost > 0 and (lost .. " lost") or "none lost"
  return alerts, ("%d machine%s: %s"):format(n, n == 1 and "" or "s", table.concat(parts, ", "))
end

local function islandLine(v, L, st)
  if not st then v:put(2, L.islandY, "Island station not running", "dim", "bg"); return end
  st.W = L.W - 1
  local text, tone = dangerLine(st)
  if tone == "good" then text = (" All clear on the island (%d other thing%s nearby)"):format(st.others, st.others == 1 and "" or "s") end
  v:put(1, L.islandY, fit(text, L.W), tone, "bg")
end

local function glanceDraw(v, L, st, list, vis)
  -- top half: board with two-row entries, then the visitors
  local items = boardItems(list or {}, true)
  items.title = "Machines"
  v:board(L.bx, 1, L.bw, items, { tworow = true, slots = SLOTS })
  if not list then v:put(L.bx + 2, 2, "no data yet", "dim", "bg") end
  visitors(v, L, vis)
  for y = 1, L.dotsY do v:put(L.vx - 1, y, " ", "fg", "bar") end
  rule(v, L.ruleY, L.W)
  -- clock column
  local gy, cx = L.gy, 2
  local x = chip(v, cx - 1, gy, "ISLAND")
  if st then
    local time = tostring(st.time)
    if #time == 4 then time = "0" .. time end
    v:bigNumber(cx, gy + 2, time, "fg", { px = 2, py = 1 })
    local px = v:put(cx, gy + 8, st.phase, phaseTone(st.phase), "bg")
    px = v:put(px, gy + 8, "  day " .. st.day .. "  ", "dim", "bg")
    v:put(px, gy + 8, st.weather, weatherTone(st.weather), "bg")
    v:put(cx, gy + 9, fit(("Moon %s  %s  Light %s/%s"):format(st.moon, st.biome, tostring(st.sky), tostring(st.block)), L.cw), "dim", "bg")
  else
    v:put(cx, gy + 2, "Island station not running", "dim", "bg")
  end
  -- power column
  local op = _G.OPERATOR
  local pw = opfmt.power(op)
  local p = powerView(pw, op)
  v:boardHeader(L.px, gy, L.pw, "Power use")
  if p.tag then v:put(L.px + L.pw - #p.tag - 2, gy, " " .. p.tag .. " ", "bg", "bad") end
  v:bigNumber(L.px + 1, gy + 2, p.digits, p.tone, { px = 2, py = 1 })
  v:put(L.px + 1, gy + 8, fit(p.line1, L.pw - 1), p.tone1, "bg")
  if p.line2 then v:put(L.px + 1, gy + 9, fit(p.line2, L.pw - 1), p.tone2, "bg") end
  if p.line3 then v:put(L.px + 1, gy + 10, fit(p.line3, L.pw - 1), "dim", "bg") end
  for y = gy - 1, gy + 10 do v:put(L.px - 2, y, " ", "fg", "bar") end
  -- Needs you and the island line
  local alerts, summary = needs(list, pw)
  v:needsYou(2, L.needY, L.W - 2, 4, alerts, { summary = summary })
  islandLine(v, L, st)
end

---------------------------------------------------------------------------------------------------------
-- The wall
---------------------------------------------------------------------------------------------------------
function wall.draw(v)
  local L = wall.layout(v.W, v.H)
  local st, list, vis = _G.WALL_STRIP, _G.WALL_BOARD, _G.WALL_VISITORS
  if st then st = setmetatable({ W = L.W }, { __index = st }) end
  if L.glance then return glanceDraw(v, L, st, list, vis) end
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
-- opts.scale: the monitor's text scale (mainframe.lua reads SCALE from wall.env).
function wall.run(mon, name, opts)
  ui.loadAnim("wall.env")
  if (opts or {}).pageS and opts.pageS > 0 then ui.PAGE_S = opts.pageS end
  local v = ui.view(mon, { side = name, scale = (opts or {}).scale })
  ui.run(v, function(view)
    local ok, err = pcall(wall.draw, view)
    if not ok then view:put(1, view.H, fit("wall: " .. tostring(err), view.W), "bad", "bg") end
  end, { tick = 1 })
end

return wall
