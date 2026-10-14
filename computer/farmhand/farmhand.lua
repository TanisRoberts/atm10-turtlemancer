-- farmhand.lua  --  the Farmhand: control screen for every farm turtle (Partridge, Woodpecker...)
--
-- Needs: an advanced computer with a wireless or ENDER modem (ender reaches farms anywhere) and an
-- advanced monitor touching it (any size; the computer's own screen works too, click with the mouse).
--
-- Laid out for any monitor; tuned for a 3 wide x 2 tall one (57x24 at text scale 0.5).
-- Overview: one tile per farm turtle: what it's doing, fuel, when the next round is, its last round,
-- and its farm drawn small with an arrow where it is right now. Tap one to open it: the map on the
-- left (or the Info / Haul / Settings tab), what it's doing and the order buttons on the right:
--   ROUNDS NOW, PAUSE / GO, RE-MAP (walk the farm again: new rows, moved paths), FOUND (after you've
--   carried a lost turtle home), REBOOT (it finishes what it's doing, restarts and updates)
--   Settings, changed live: how often it does rounds, how many seeds/saplings it keeps, how often it
--   re-maps. They're written into the turtle's own .env file.
--   Its exact position (with GPS), last haul and everything it has brought in since it started.
--   Map tab: the farm from above (north up once it's pinned to GPS): border, dock, every plot by crop
--   (capital letter = harvested last round, small = growing, red dot = empty) or every tree spot
--   (sapling / just replanted / empty), and an arrow where the turtle is right now, live. Big farms
--   follow the turtle; the arrow buttons (or the mouse wheel) pan. Tap a block to see what's there.
-- Orders repeat every few seconds until the turtle confirms them, so it picks them up whenever it's
-- in range. The mainframe board shows every farm turtle and a Farmhand row; chat commands
-- (island partridge rounds...) keep working alongside this screen.

local PROTOCOL   = "tanis-farm"
local CONFIG     = "farmhand.cfg"
local SEND_EVERY = 3
local STALE      = 20      -- seconds without news before a turtle greys out
local TEXT_SCALE = 0.5
local REBOOT_WAIT = 600000 -- ms: give up on an unconfirmed reboot after this

local K = colours

---------------------------------------------------------------------------
-- Registry: every farm turtle seen, by computer ID
--   { label, role, want, seq, set = {KEY=value}, setSeq, reboot, rebootAt }
---------------------------------------------------------------------------
local cfg = { turtles = {} }
local function loadCfg()
  if fs.exists(CONFIG) then
    local f = fs.open(CONFIG, "r"); local t = textutils.unserialize(f.readAll() or ""); f.close()
    if type(t) == "table" and type(t.turtles) == "table" then cfg = t end
  end
end
local function saveCfg()
  local f = fs.open(CONFIG .. ".new", "w"); f.write(textutils.serialize(cfg)); f.close()
  if fs.exists(CONFIG) then fs.delete(CONFIG) end
  fs.move(CONFIG .. ".new", CONFIG)
end

local live = {}         -- id -> { s = status, seen = os.clock() }
local maps = {}         -- id -> the turtle's last map message (see farmbot.lua B.mapMsg)
local mapAskedAt = {}   -- id -> os.clock() of the last map request
local sendNow = {}
local radioOK = nil

local function entry(id)
  local t = cfg.turtles[id]
  if not t then t = {}; cfg.turtles[id] = t end
  return t
end

local function order(id, want)
  local t = entry(id)
  t.want, t.seq = want, os.epoch("utc")
  saveCfg()
  sendNow[id] = true
end
local function requestReboot(id)
  local t = entry(id)
  t.reboot, t.rebootAt = os.epoch("utc"), os.epoch("utc")
  saveCfg()
  sendNow[id] = true
end

-- Settings the Farmhand can change, per role: { key, label, unit, step, min, max }
local SETTINGS = {
  farmer = {
    { "EVERY", "Rounds every", "min", 1, 1, 240 },
    { "KEEP_SEEDS", "Keep seeds", "", 16, 0, 1024 },
    { "RESURVEY_EVERY", "Re-map every", "rounds", 1, 0, 100 },
  },
  lumberjack = {
    { "EVERY", "Rounds every", "min", 5, 1, 240 },
    { "KEEP_SAPLINGS", "Keep saplings", "", 8, 0, 512 },
    { "RESURVEY_EVERY", "Re-map every", "rounds", 1, 0, 100 },
    { "SWEEPS", "Sapling sweeps", "", 1, 0, 5 },
  },
}
local ROLE_NAME = { farmer = "crops", lumberjack = "trees" }

-- Current value: what we're sending (not yet confirmed) or what the turtle reports
local function settingValue(id, k)
  local t, l = cfg.turtles[id], live[id]
  local reported = l and l.s.settings and l.s.settings[k]
  if t and t.set and t.set[k] ~= nil and not (l and (l.s.setSeq or 0) >= (t.setSeq or 0)) then return t.set[k], true end
  return reported, false
end
local function changeSetting(id, k, value)
  local t = entry(id)
  local l = live[id]
  -- Start from what it reports, plus anything still unconfirmed
  local set = {}
  if t.set and not (l and (l.s.setSeq or 0) >= (t.setSeq or 0)) then for a, b in pairs(t.set) do set[a] = b end end
  set[k] = value
  t.set, t.setSeq = set, os.epoch("utc")
  saveCfg()
  sendNow[id] = true
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local STATES = {
  working = { "WORKING", K.lime }, surveying = { "MAPPING", K.lime }, docked = { "DOCKED", K.lightBlue },
  waiting = { "WAITING", K.orange }, error = { "ERROR", K.red }, lost = { "LOST", K.red },
  rebooting = { "REBOOTING", K.purple },
}
local function fmtNum(n)
  if type(n) ~= "number" then return tostring(n or "?") end
  local s = tostring(math.floor(n))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function fmtAgo(s)
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end
local function fmtMins(secs)
  if not secs then return "-" end
  if secs < 60 then return "under a min" end
  return math.ceil(secs / 60) .. " min"
end
local function pretty(id)
  local s = tostring(id):gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end
local function posText(s)
  if not s or not s.pos then return "position unknown" end
  return ("%d, %d, %d"):format(s.pos.x, s.pos.y, s.pos.z)
end
local function stateOf(id)
  local l = live[id]
  if not l then return "NO SIGNAL", K.grey end
  local st = l.s.state
  if l.s.paused and st == "docked" then st = "paused" end
  local m = STATES[st] or (st == "paused" and { "PAUSED", K.orange }) or { tostring(st or "?"):upper(), K.white }
  if os.clock() - l.seen > STALE then return m[1], K.grey end
  return m[1], m[2]
end
local function nameOf(id)
  local l, t = live[id], cfg.turtles[id]
  return (l and l.s.label) or (t and t.label) or ("Turtle #" .. id)
end
local function lastRoundText(s)
  local r = s and s.lastRound
  if not r then return "no round yet" end
  if s.role == "lumberjack" then
    return ("chopped %d, planted %d"):format(r.chopped or 0, r.planted or 0)
      .. (r.picked and (", %d saplings found"):format(r.picked) or "")
  end
  return ("harvested %d, planted %d"):format(r.harvested or 0, r.planted or 0)
end
local function nextText(s)
  if not s then return "" end
  if s.state == "working" and s.progress then return "round " .. s.progress end
  if s.paused then return "paused" end
  if s.nextRound then return "next in " .. fmtMins(s.nextRound) end
  return ""
end

local function ids()
  local out = {}
  for id in pairs(cfg.turtles) do out[#out + 1] = id end
  table.sort(out, function(a, b)
    local na, nb = nameOf(a):lower(), nameOf(b):lower()
    if na ~= nb then return na < nb end
    return a < b
  end)
  return out
end

local function problems()
  local n, worst = 0, nil
  for _, id in ipairs(ids()) do
    local l = live[id]
    local bad = not l or os.clock() - l.seen > STALE or l.s.state == "error" or l.s.state == "lost" or l.s.state == "waiting"
    if bad then
      n = n + 1
      worst = worst or (nameOf(id) .. ": " .. (not l and "never heard" or os.clock() - l.seen > STALE and "silent"
        or tostring(l.s.msg or l.s.state)))
    end
  end
  return n, worst
end

---------------------------------------------------------------------------
-- Screens: monitor + the computer's own screen, each with its own page
---------------------------------------------------------------------------
local function newUi() return { page = "overview", id = nil, tab = "map", scroll = 1, notice = nil, confirm = nil, follow = true, visible = {} } end
local function findMonitor()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then return peripheral.wrap(side), side end
  end
end
local mon, monSide = findMonitor()
local views = {
  { dev = function() return mon end, kind = "monitor", hits = {}, ui = newUi() },
  { dev = function() return term end, kind = "term", hits = {}, ui = newUi() },
}
local ui = views[2].ui

local d, hits
local function at(x, y, text, fg, bg)
  d.setCursorPos(x, y)
  d.setBackgroundColour(bg or K.black)
  d.setTextColour(fg or K.white)
  d.write(text)
end
local function pad(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s > w then return s:sub(1, w) end
  return s .. (" "):rep(w - #s)
end
local function lr(x, y, w, left, right, fgL, fgR)
  left = tostring(left)
  if right then
    right = tostring(right):sub(1, w)
    -- Never let the two halves run into each other: the label gives way first
    local room = w - #right - 1
    if #left > room then left = room > 0 and left:sub(1, room) or "" end
  end
  at(x, y, pad(left, w), fgL or K.lightGrey)
  if right then at(x + w - #right, y, right, fgR or K.white) end
end
local function bar(x, y, w, frac, colour)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  at(x, y, (" "):rep(w), K.white, K.grey)
  if n > 0 then at(x, y, (" "):rep(n), K.white, colour) end
end
local function hit(x1, y1, x2, y2, fn) hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn } end
local function button(x, y, w, rows, label, bg, fn, fg)
  for r = 0, rows - 1 do at(x, y + r, (" "):rep(w), K.black, bg) end
  label = label:sub(1, w)
  at(x + math.floor((w - #label) / 2), y + math.floor(rows / 2), label, fg or K.black, bg)
  hit(x, y, x + w - 1, y + rows - 1, fn)
end
local function smallButton(x, y, label, bg, fn, fg)
  at(x, y, " " .. label .. " ", fg or K.black, bg)
  hit(x, y, x + #label + 1, y, fn)
  return x + #label + 3
end
local function header(w, title, right)
  at(1, 1, (" "):rep(w), K.cyan, K.grey)
  at(2, 1, title, K.cyan, K.grey)
  if right and #right + #title + 4 < w then at(w - #right, 1, right, K.lightGrey, K.grey) end
  if ui.notice and os.clock() < ui.notice.untilT then at(2, 2, pad(ui.notice.text, w - 2), ui.notice.colour) end
end
local function say(text, colour)
  for _, v in ipairs(views) do v.ui.notice = { text = text, colour = colour or K.lime, untilT = os.clock() + 5 } end
end

---------------------------------------------------------------------------
-- Maps: the farm from above, what's planted where, and where the turtle is right now
---------------------------------------------------------------------------
local HEX = "0123456789abcdef"
local BLIT = {}
for i = 0, 15 do BLIT[2 ^ i] = HEX:sub(i + 1, i + 1) end
local ARROW = { [0] = "\30", "\16", "\31", "\17" }      -- facing north / east / south / west
local SPADE = "\6"                                        -- looks like a little tree

-- Crop colours (by the seed/crop id); anything else gets one from the spare list
local CROP_COLOURS = {
  { "wheat", K.yellow }, { "carrot", K.orange }, { "potato", K.white }, { "beetroot", K.red },
  { "nether_wart", K.red }, { "melon", K.lime }, { "pumpkin", K.orange }, { "hemp", K.lime },
  { "immersiveengineering", K.lime }, { "mysticalagriculture", K.magenta }, { "berr", K.pink },
  { "sugar_cane", K.lime }, { "cotton", K.white }, { "flax", K.lightBlue },
}
local SPARE = { K.cyan, K.pink, K.lightBlue, K.purple, K.white, K.lime, K.yellow }
local function cropColour(name, i)
  name = tostring(name)
  for _, c in ipairs(CROP_COLOURS) do if name:find(c[1], 1, true) then return c[2] end end
  return SPARE[((i or 1) - 1) % #SPARE + 1]
end
local function cropName(id)
  local n = tostring(id):gsub("^.-:", ""):gsub("_seeds?$", ""):gsub("_crop$", ""):gsub("_", " ")
  if n == "seed" then n = "hemp" end
  return (n:gsub("^%l", string.upper))
end

-- One cell -> character, text colour, background
local function cellLook(m, c, st)
  if c == " " then return " ", K.black, K.black end
  if c == "#" then return " ", K.grey, K.grey end                          -- slab border
  if c == "@" then return "D", K.black, K.yellow end                       -- dock barrel
  if c == "%" then return "\127", K.grey, K.black end                      -- something solid
  if c == "," then return "~", K.lightBlue, K.blue end                     -- water / path
  if c == "&" then return "o", K.orange, K.brown end                       -- pumpkin/melon spot
  if m.role == "lumberjack" then
    if c == "." then return " ", K.green, K.green end                      -- lane
    if c == "!" then return SPADE, K.lime, K.brown end                     -- wild tree, gets chopped
    if c == "+" then
      if st == "h" then return SPADE, K.yellow, K.green end                -- chopped + replanted
      if st == "g" then return SPADE, K.lime, K.green end                  -- sapling growing
      if st == "e" then return "+", K.red, K.green end                     -- nothing planted
      return "+", K.lightGrey, K.green                                     -- not visited yet
    end
  end
  if c == "." then return " ", K.grey, K.black end
  if c == "*" then return ".", K.lightGrey, K.brown end
  local i = c:byte() - 96
  if i >= 1 and i <= 26 then
    local name = m.crops and m.crops[i]
    local letter = cropName(name or "?"):sub(1, 1)
    if st == "e" then return ".", K.red, K.brown end                       -- empty: no seed
    local col = cropColour(name, i)
    if st == "h" then return letter:upper(), col, K.brown end              -- harvested last round
    return letter:lower(), col, K.brown                                    -- growing
  end
  return "?", K.white, K.black
end

local function mapStats(m)
  local n = { cells = 0 }
  local perCrop = {}
  for r = 1, m.h do
    local row, srow = m.rows[r], m.states[r] or ""
    for c = 1, m.w do
      local ch, st = row:sub(c, c), srow:sub(c, c)
      if ch ~= " " and ch ~= "#" and ch ~= "%" then n.cells = n.cells + 1 end
      n[ch] = (n[ch] or 0) + 1
      local key = ch .. st
      n[key] = (n[key] or 0) + 1
      local i = ch:byte() - 96
      if i >= 1 and i <= 26 then
        perCrop[i] = perCrop[i] or { all = 0, h = 0, g = 0, e = 0 }
        perCrop[i].all = perCrop[i].all + 1
        if st ~= " " then perCrop[i][st] = (perCrop[i][st] or 0) + 1 end
      end
    end
  end
  return n, perCrop
end


local function turtleCell(id, m)
  local l = live[id]
  local s = l and l.s
  if m and s and s.mp and s.mapStamp then return s.mp.x - m.x0 + 1, s.mp.z - m.z0 + 1, s.mp.h or 0 end
end

-- When a map is shrunk to fit, each screen cell stands for a block of cells: show the one that
-- matters most (an empty spot beats a crop beats a lane), so sparse tree spots don't vanish.
local PRIORITY = { [" "] = -1, ["."] = 0, ["%"] = 1, ["#"] = 2, [","] = 3, ["&"] = 4, ["*"] = 5, ["+"] = 5, ["!"] = 5, ["@"] = 9 }
local function priority(ch, st)
  local p = PRIORITY[ch] or 5                      -- crop letters
  if p == 5 and st == "e" then p = 8 end
  return p
end
local shrinkCache = {}   -- id -> { key, rows = { { ch, st }... } }
local function shrunk(id, m, k, dw, dh)
  local key = ("%s/%s/%d/%d"):format(tostring(m.stamp), tostring(k), dw, dh)
  local c = shrinkCache[id]
  if c and c.key == key then return c.grid end
  local grid = {}
  for j = 1, dh do
    grid[j] = {}
    local r1, r2 = math.floor((j - 1) * k) + 1, math.min(m.h, math.floor(j * k))
    for i = 1, dw do
      local c1, c2 = math.floor((i - 1) * k) + 1, math.min(m.w, math.floor(i * k))
      local best, bc, bs = -2, " ", " "
      for r = r1, math.max(r1, r2) do
        local row, srow = m.rows[r] or "", m.states[r] or ""
        for cc = c1, math.max(c1, c2) do
          local ch, st = row:sub(cc, cc), srow:sub(cc, cc)
          if ch == "" then ch = " " end
          local p = priority(ch, st)
          if p > best then best, bc, bs = p, ch, st end
        end
      end
      grid[j][i] = { bc, bs }
    end
  end
  shrinkCache[id] = { key = key, grid = grid }
  return grid
end

-- Draw a turtle's map in the box (x, y, bw, bh).
--   fit = true: shrunk to fit the box (overview tiles).
--   otherwise 1:1 (2 characters per cell when it fits), scrolled by ui.mapC / ui.mapR, following the
--   turtle while ui.follow, and a tap on a block says what's there. Returns true if it all fits.
local function drawMapBox(id, m, x, y, bw, bh, fit)
  if bw < 3 or bh < 2 then return true end
  local l = live[id]
  local s = l and l.s
  local stale = not l or os.clock() - l.seen > STALE
  local tc, tr, th = turtleCell(id, m)
  local cw = (m.w * 2 <= bw) and 2 or 1
  local cols, rows = math.floor(bw / cw), bh
  local fitsX, fitsY = m.w <= cols, m.h <= rows
  local function cellAt(ch, st, isTurtle)
    if isTurtle then return ARROW[th] or "@", K.white, stale and K.grey or K.magenta end
    return cellLook(m, ch, st)
  end
  local function blitRow(px, py, cells)
    local txt, fg, bg = {}, {}, {}
    for _, c in ipairs(cells) do
      local ch, f, b = c[1], c[2], c[3]
      for n = 1, cw do
        txt[#txt + 1] = (n == 1 or ch == "\127") and ch or " "
        fg[#fg + 1] = BLIT[f]; bg[#bg + 1] = BLIT[b]
      end
    end
    d.setCursorPos(px, py)
    d.blit(table.concat(txt), table.concat(fg), table.concat(bg))
  end

  if fit and not (fitsX and fitsY) then
    cw = 1
    local k = math.max(m.w / bw, m.h / bh)
    local dw, dh = math.max(1, math.ceil(m.w / k)), math.max(1, math.ceil(m.h / k))
    dw, dh = math.min(dw, bw), math.min(dh, bh)
    local grid = shrunk(id, m, k, dw, dh)
    local ti = tc and math.min(dw, math.floor((tc - 1) / k) + 1)
    local tj = tr and math.min(dh, math.floor((tr - 1) / k) + 1)
    local ox, oy = x + math.floor((bw - dw) / 2), y + math.floor((bh - dh) / 2)
    for j = 1, dh do
      local cells = {}
      for i = 1, dw do
        local g = grid[j][i]
        local ch, f, b = cellAt(g[1], g[2], ti == i and tj == j)
        cells[i] = { ch, f, b }
      end
      blitRow(ox, oy + j - 1, cells)
    end
    return true
  end

  if fit then
    ui.mapC, ui.mapR = 1, 1
  elseif ui.follow or ui.mapC == nil then
    ui.mapC = tc and (tc - math.floor(cols / 2)) or 1
    ui.mapR = tr and (tr - math.floor(rows / 2)) or 1
  end
  local c0 = fitsX and 1 or math.max(1, math.min(ui.mapC, m.w - cols + 1))
  local r0 = fitsY and 1 or math.max(1, math.min(ui.mapR, m.h - rows + 1))
  if not fit then ui.mapC, ui.mapR = c0, r0 end
  local ox = x + (fitsX and math.floor((cols - m.w) / 2) * cw or 0)
  local oy = y + (fitsY and math.floor((rows - m.h) / 2) or 0)
  local shownC, shownR = math.min(cols, m.w), math.min(rows, m.h)
  for r = 0, shownR - 1 do
    local mr = r0 + r
    local row, srow = m.rows[mr] or "", m.states[mr] or ""
    local cells = {}
    for c = 0, shownC - 1 do
      local mc = c0 + c
      local ch, st = row:sub(mc, mc), srow:sub(mc, mc)
      cells[#cells + 1] = { cellAt(ch ~= "" and ch or " ", st, tc and mc == tc and mr == tr) }
    end
    blitRow(ox, oy + r, cells)
  end
  if fit then return true end
  hit(ox, oy, ox + shownC * cw - 1, oy + shownR - 1, function(px, py)
    local mc, mr = c0 + math.floor((px - ox) / cw), r0 + (py - oy)
    local ch = (m.rows[mr] or ""):sub(mc, mc)
    local st = (m.states[mr] or ""):sub(mc, mc)
    local what = ({ ["#"] = "the slab border", ["@"] = "the dock barrel", ["%"] = "something solid",
      [","] = "water or a path (skipped)", ["&"] = "pumpkin/melon spot", ["."] = "lane",
      ["!"] = "a wild tree (gets chopped, then it's a lane)", ["*"] = "a plot (crop not known yet)", [" "] = "outside the farm" })[ch]
    if ch == "+" then what = "tree spot: " .. (({ h = "chopped last round, replanted", g = "sapling growing", e = "nothing planted (no sapling)" })[st] or "not visited yet") end
    local i = ch ~= "" and ch:byte() - 96 or 0
    if i >= 1 and i <= 26 then
      what = cropName(m.crops[i] or "?") .. ": " .. (({ h = "harvested last round, replanted", g = "growing", e = "empty (no seeds)" })[st] or "not visited yet")
    end
    if tc and mc == tc and mr == tr then what = nameOf(id) .. " is here" end
    local wx, wz
    if tc and s.pos and m.north then wx, wz = s.pos.x + (mc - tc), s.pos.z + (mr - tr) end
    say((wx and ("%d, %d: "):format(wx, wz) or "") .. (what or "?"), K.white)
  end)
  return fitsX and fitsY
end

-- The key: { glyph, fg, bg, long text, colour, short text }
local function mapKey(id, m)
  local l = live[id]
  local s = l and l.s
  local stale = not l or os.clock() - l.seen > STALE
  local n, perCrop = mapStats(m)
  local lines = {}
  local function add(ch, f, b, text, colour, short) lines[#lines + 1] = { ch, f, b, text, colour, short } end
  local tc = turtleCell(id, m)
  add(ARROW[s and s.mp and s.mp.h or 0], K.white, stale and K.grey or K.magenta,
    stale and "not heard" or (tc and "here" or "off the map"), stale and K.grey or K.white)
  if m.role == "lumberjack" then
    add(SPADE, K.yellow, K.green, ("replanted %d"):format(n["+h"] or 0))
    add(SPADE, K.lime, K.green, ("saplings %d"):format(n["+g"] or 0))
    if (n["+e"] or 0) > 0 then add("+", K.red, K.green, ("empty %d"):format(n["+e"]), K.orange) end
    if (n["+ "] or 0) > 0 then add("+", K.lightGrey, K.green, ("unvisited %d"):format(n["+ "])) end
    if (n["!"] or 0) > 0 then add(SPADE, K.lime, K.brown, ("wild %d"):format(n["!"])) end
  else
    for i, name in ipairs(m.crops or {}) do
      local pc = perCrop[i] or { all = 0, e = 0 }
      add(cropName(name):sub(1, 1):upper(), cropColour(name, i), K.brown, ("%s %d"):format(cropName(name), pc.all))
    end
    add("A", K.white, K.brown, "harvested")
    add("a", K.white, K.brown, "growing")
    local empty = 0
    for _, pc in pairs(perCrop) do empty = empty + (pc.e or 0) end
    add(".", K.red, K.brown, ("empty %d"):format(empty), empty > 0 and K.orange or nil)
    if (n[","] or 0) > 0 then add("~", K.lightBlue, K.blue, "water") end
    if (n["&"] or 0) > 0 then add("o", K.orange, K.brown, "gourd") end
  end
  add("D", K.black, K.yellow, "dock")
  return lines
end
-- Lay the key out in rows of width w; draw = false just counts the rows
local function drawKey(lines, x, y, w, maxRows, draw)
  local row, cx = 1, x
  for _, e in ipairs(lines) do
    local len = #e[4] + 3
    if cx + len - 1 > x + w and cx > x then row, cx = row + 1, x end
    if row > maxRows then break end
    if draw then at(cx, y + row - 1, e[1], e[2], e[3]); at(cx + 1, y + row - 1, " " .. e[4]:sub(1, w - 2), e[5] or K.lightGrey) end
    cx = cx + len
  end
  return math.min(row, maxRows)
end

---------------------------------------------------------------------------
-- Overview: a tile per farm turtle, with its farm drawn small and where it is right now
---------------------------------------------------------------------------
local function fuelPct(s)
  if s and type(s.fuel) == "number" and type(s.fuelLimit) == "number" and s.fuelLimit > 0 then
    return s.fuel / s.fuelLimit
  end
end

local function drawTile(id, x, y, w, h)
  local l = live[id]
  local s = l and l.s
  local stale = not l or os.clock() - l.seen > STALE
  local st, colour = stateOf(id)
  -- Name bar
  at(x, y, (" "):rep(w), K.white, K.grey)
  at(x + 1, y, pad(nameOf(id), w - #st - 3), stale and K.lightGrey or K.white, K.grey)
  at(x + w - #st - 1, y, st, colour == K.grey and K.lightGrey or colour, K.grey)
  local yy = y + 1
  local function line(text, fg) if yy < y + h then at(x, yy, pad(text, w), fg or K.lightGrey) end; yy = yy + 1 end
  -- What it's doing
  local msg
  if stale then msg = l and ("not heard for " .. fmtAgo(math.floor(os.clock() - l.seen))) or "never heard from"
  else msg = tostring(s.msg or "") end
  line(" " .. msg, stale and K.grey or ((s and (s.state == "error" or s.state == "lost" or s.state == "waiting")) and K.orange or K.lightGrey))
  -- Fuel bar, then the next round (or how far through this one it is)
  if yy < y + h then
    local frac = fuelPct(s)
    local pct = frac and (math.floor(frac * 100) .. "%") or "-"
    at(x + 1, yy, "Fuel", K.grey)
    bar(x + 6, yy, w - 8 - #pct, frac or 0, frac and frac < 0.1 and K.red or K.lime)
    at(x + w - 1 - #pct, yy, pct, K.white)
    yy = yy + 1
  end
  local nt = s and nextText(s) or ""
  if nt ~= "" and yy < y + h - 1 then
    at(x + 1, yy, pad(nt:gsub("^%l", string.upper), w - 2), s.state == "working" and K.lime or K.lightGrey)
    yy = yy + 1
  end
  -- The farm, small
  local m = maps[id]
  local mapRows = (y + h - 1) - yy        -- leave the last row for the last round
  if mapRows >= 3 then
    if m and not m.none then
      drawMapBox(id, m, x + 1, yy, w - 2, mapRows, true)
    else
      local t = (m and m.none) and "not mapped yet" or (s and s.mapStamp == nil) and "reboot it once for the map" or "asking for its map..."
      at(x + 1, yy + math.floor(mapRows / 2), pad(t, w - 2), K.grey)
    end
    yy = yy + mapRows
  end
  if yy <= y + h - 1 then
    local lr_ = s and s.lastRound and ("Last: " .. lastRoundText(s)) or ""
    at(x, yy, pad(" " .. lr_, w), K.grey)
  end
  hit(x, y, x + w - 1, y + h - 1, function() ui.page, ui.id, ui.tab, ui.confirm, ui.follow = "turtle", id, "map", nil, true end)
end

local function drawOverview(w, h)
  local list = ids()
  if radioOK == false and not (ui.notice and os.clock() < ui.notice.untilT) then
    ui.notice = { text = "No wireless/ender modem on me: the turtles can't hear me", colour = K.red, untilT = os.clock() + 1e9 }
  end
  local nProb = problems()
  header(w, "FARMHAND", ("%d turtle%s%s"):format(#list, #list == 1 and "" or "s",
    nProb > 0 and ("  " .. nProb .. " need" .. (nProb == 1 and "s" or "") .. " you") or "  all fine"))
  local top, bottom = 3, h - 2
  local availH = bottom - top + 1
  ui.visible = {}
  if #list == 0 then
    local lines = { "No farm turtles heard yet.", "Set up a turtle as Partridge (crops) or Woodpecker (trees):",
                    "it shows up here as soon as it's on the air." }
    for i, l in ipairs(lines) do at(2, top + i, pad(l, w - 2), i == 1 and K.white or K.lightGrey) end
  end
  -- Tiles: two across on wide screens, as many rows as fit (at least 5 lines each)
  local cols = (w >= 46 and #list >= 2) and 2 or 1
  local tileW = math.floor((w - 1 - (cols - 1)) / cols)
  local maxRows = math.max(1, math.floor((availH + 1) / 6))
  local tileRows = math.max(1, math.min(maxRows, math.ceil(#list / cols)))
  local tileH = math.floor((availH + 1) / tileRows) - 1
  local per = cols * tileRows
  local pages = math.max(1, math.ceil(#list / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))
  for i = 1, per do
    local id = list[(ui.scroll - 1) * per + i]
    if not id then break end
    ui.visible[#ui.visible + 1] = id
    local c, r = (i - 1) % cols, math.floor((i - 1) / cols)
    drawTile(id, 1 + c * (tileW + 1) + (cols == 1 and 0 or 0), top + r * (tileH + 1), cols == 1 and w or tileW, tileH)
  end

  local fy = h
  at(1, fy, (" "):rep(w))
  local x = 2
  if #list > 0 then
    x = smallButton(x, fy, "Rounds all", K.lime, function()
      for _, id in ipairs(ids()) do order(id, "rounds") end
      say("Every farm turtle is off on its rounds.")
    end)
    x = smallButton(x, fy, "Pause all", K.orange, function()
      for _, id in ipairs(ids()) do order(id, "stop") end
      say("Every farm turtle will stay docked (Go to start again).", K.orange)
    end)
    if w >= 50 then
      x = smallButton(x, fy, "Reboot all", K.purple, function()
        for _, id in ipairs(ids()) do requestReboot(id) end
        say("Reboot sent: each finishes what it's doing, then restarts.", K.purple)
      end, K.white)
    end
  end
  if pages > 1 then
    local label = ("%d/%d"):format(ui.scroll, pages)
    local px = w - #label - 9
    if px > x then
      smallButton(px, fy, "<", ui.scroll > 1 and K.cyan or K.grey, function() ui.scroll = ui.scroll - 1 end)
      at(px + 4, fy, label, K.lightGrey)
      smallButton(w - 3, fy, ">", ui.scroll < pages and K.cyan or K.grey, function() ui.scroll = ui.scroll + 1 end)
    end
  end
end

---------------------------------------------------------------------------
-- One turtle: its map (or info / haul / settings) on the left, what it's doing + orders on the right
---------------------------------------------------------------------------
local function wrap(text, w)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end

local function drawStatus(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  local function line(fn) if y <= maxY then fn() end y = y + 1 end
  line(function() lr(x, y, w, "Seen", l and (fmtAgo(math.floor(os.clock() - l.seen)) .. " ago") or "never", K.lightGrey, K.grey) end)
  local f = s and s.fuel
  line(function() lr(x, y, w, "Fuel", type(f) == "number" and (fmtNum(f) .. " / " .. fmtNum(s.fuelLimit)) or (f or "-")) end)
  if s and s.role == "lumberjack" then
    line(function() lr(x, y, w, "Zone", s.mapped and ("%s blocks, %s trees"):format(fmtNum(s.cells), fmtNum(s.spots)) or "not mapped") end)
    line(function() lr(x, y, w, "Saplings", fmtNum(s.saplings)) end)
  else
    line(function()
      local crop = s and s.crop and pretty(tostring(s.crop):gsub("_seeds$", ""):gsub("^.-:", "")) or nil
      lr(x, y, w, "Farm", s and s.mapped and (fmtNum(s.plots) .. " plots" .. (crop and (", " .. crop) or "")) or "not mapped")
    end)
    line(function() lr(x, y, w, "Seeds", s and fmtNum(s.seeds) or "-") end)
  end
  line(function() lr(x, y, w, "Last round", s and lastRoundText(s) or "-") end)
  line(function() lr(x, y, w, "Next", s and (nextText(s) ~= "" and nextText(s) or "-") or "-") end)
  line(function() lr(x, y, w, "Rounds done", s and fmtNum(s.rounds) or "-") end)
  y = y + 1
  line(function() lr(x, y, w, "At", posText(s), K.lightGrey, K.white) end)
  line(function() lr(x, y, w, "Facing", s and s.facing or "?") end)
  line(function() lr(x, y, w, "Home", s and s.home and ("%d, %d, %d"):format(s.home.x, s.home.y, s.home.z) or "?") end)
  line(function()
    local txt = not s and "-" or s.anchored and "pinned: never lost" or s.gps and "seen, not pinned yet" or "none: counting moves"
    lr(x, y, w, "GPS", txt, K.lightGrey, s and not s.anchored and K.orange or K.grey)
  end)
  line(function() lr(x, y, w, "Computer", "#" .. id, K.lightGrey, K.grey) end)
  return y
end

local function drawHaul(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  local function list(title, items)
    if y > maxY then return end
    at(x, y, pad(title, w), K.grey); y = y + 1
    if (not items or #items == 0) and y <= maxY then at(x, y, pad("Nothing yet", w), K.grey); y = y + 1 end
    for _, e in ipairs(items or {}) do
      if y > maxY then break end
      lr(x, y, w, pretty(e[1]), fmtNum(e[2]), K.white, K.cyan)
      y = y + 1
    end
    y = y + 1
  end
  list("LAST HAUL", s and s.lastHaul)
  list("BROUGHT IN SO FAR", s and s.totals)
  return y
end

local function drawSettings(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  at(x, y, pad("SETTINGS (changed live)", w), K.grey); y = y + 2
  for _, def in ipairs(SETTINGS[s and s.role or ""] or {}) do
    if y > maxY then break end
    local k, label, unit, step, mn, mx = def[1], def[2], def[3], def[4], def[5], def[6]
    local v, pending = settingValue(id, k)
    local val = (v == nil) and "?" or (tostring(v) .. (unit ~= "" and (" " .. unit) or ""))
    if k == "RESURVEY_EVERY" and v == 0 then val = "never" end
    if k == "SWEEPS" and v == 0 then val = "off" end
    local bx = x + w - 3
    local vx = bx - 1 - #val
    local mxL = vx - 4 - x - 1
    if #label > mxL then label = label:gsub("^Rounds every", "Every"):gsub("^Re%-map every", "Re-map"):gsub("^Keep ", ""):gsub("^Sapling sweeps", "Sweeps") end
    at(x, y, pad(label:sub(1, math.max(0, mxL)), w), K.lightGrey)
    at(math.max(x, vx - 4), y, " - ", K.black, (v and v > mn) and K.cyan or K.grey)
    hit(math.max(x, vx - 4), y, math.max(x, vx - 4) + 2, y, function()
      if type(v) == "number" then changeSetting(id, k, math.max(mn, v - step)) end
    end)
    at(vx, y, val, pending and K.yellow or K.white)
    at(bx, y, " + ", K.black, (v and v < mx) and K.cyan or K.grey)
    hit(bx, y, bx + 2, y, function()
      if type(v) == "number" then changeSetting(id, k, math.min(mx, v + step)) end
    end)
    y = y + 2
  end
  for _, t in ipairs(wrap("Yellow = sent, waiting for the turtle to confirm. Written into its own .env file.", w)) do
    if y > maxY then break end
    at(x, y, pad(t, w), K.grey); y = y + 1
  end
end

local function drawMapTab(id, x, y, w, maxY)
  local m = maps[id]
  local l = live[id]
  local s = l and l.s
  if not m or m.none then
    local t = (m and m.none) and "It hasn't mapped its farm yet."
      or (s and s.mapStamp == nil) and "No map from it: reboot it once so it gets the new program."
      or "Asking " .. nameOf(id) .. " for its map..."
    for i, line in ipairs(wrap(t, w)) do at(x, y + i, pad(line, w), K.lightGrey) end
    return
  end
  local key = mapKey(id, m)
  local keyRows = drawKey(key, x, 0, w, 3, false)
  local panRow = maxY
  local mapH = maxY - y + 1 - keyRows - 1
  -- Try without the pan row first: if it all fits, no pan buttons
  local fits = m.w <= ((m.w * 2 <= w) and math.floor(w / 2) or w) and m.h <= mapH + 1
  if fits then mapH = mapH + 1 end
  drawMapBox(id, m, x, y, w, mapH, false)
  drawKey(key, x, y + mapH, w, keyRows, true)
  if not fits then
    local step = math.max(2, math.floor(math.min(w, mapH) / 3))
    local function pan(dc, dr) return function() ui.follow = false; ui.mapC, ui.mapR = (ui.mapC or 1) + dc, (ui.mapR or 1) + dr end end
    local bx = x
    bx = smallButton(bx, panRow, "\17", K.cyan, pan(-step, 0))
    bx = smallButton(bx, panRow, "\30", K.cyan, pan(0, -step))
    bx = smallButton(bx, panRow, "\31", K.cyan, pan(0, step))
    bx = smallButton(bx, panRow, "\16", K.cyan, pan(step, 0))
    smallButton(bx, panRow, "Follow", ui.follow and K.lime or K.grey, function() ui.follow = true end, ui.follow and K.black or K.white)
  end
end

-- Right column: what it's doing, fuel, and the order buttons
local function drawSide(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  local t = cfg.turtles[id] or {}
  local st, colour = stateOf(id)
  at(x, y, pad(st, w), colour); y = y + 1
  local msg = s and s.msg or "Waiting to hear from it"
  for i, line in ipairs(wrap(msg, w)) do
    if i > 2 then break end
    at(x, y, pad(line, w), K.lightGrey); y = y + 1
  end
  local frac = fuelPct(s)
  at(x, y, "Fuel", K.grey)
  local pct = frac and (math.floor(frac * 100) .. "%") or "-"
  bar(x + 5, y, w - 6 - #pct, frac or 0, frac and frac < 0.1 and K.red or K.lime)
  at(x + w - #pct, y, pct, K.white); y = y + 1
  lr(x, y, w, "Next", s and (nextText(s) ~= "" and nextText(s) or "-") or "-"); y = y + 1
  if s and s.role == "lumberjack" then lr(x, y, w, "Saplings", fmtNum(s.saplings))
  elseif s then lr(x, y, w, "Seeds", fmtNum(s.seeds)) end
  y = y + 2

  local btns = {
    { "ROUNDS NOW", K.lime, function() order(id, "rounds"); say(nameOf(id) .. " is off on its rounds.") end },
    s and s.paused and { "GO", K.lime, function() order(id, "go"); say(nameOf(id) .. " is back on its timer.") end }
      or { "PAUSE", K.orange, function() order(id, "stop"); say(nameOf(id) .. " will stay docked.", K.orange) end },
    { "RE-MAP", K.lightBlue, function() order(id, "survey"); say(nameOf(id) .. " will walk its farm again.", K.lightBlue) end },
  }
  if s and s.state == "lost" then
    btns[#btns + 1] = { "FOUND", K.yellow, function()
      order(id, "found"); say("Put " .. nameOf(id) .. " on its home spot first: it works out the rest.", K.yellow)
    end }
  end
  btns[#btns + 1] = { t.reboot and "REBOOTING..." or "REBOOT", K.purple, function()
    requestReboot(id); say(nameOf(id) .. " reboots once it's finished what it's doing.", K.purple)
  end, K.white }
  local n, avail = #btns, maxY - y + 1
  local bh, gap = 1, 0
  for _, try in ipairs({ { 3, 1 }, { 2, 1 }, { 1, 1 }, { 1, 0 } }) do
    if n * try[1] + (n - 1) * try[2] <= avail then bh, gap = try[1], try[2]; break end
  end
  for _, b in ipairs(btns) do
    if y + bh - 1 > maxY then break end
    button(x, y, w, bh, b[1], b[2], b[3], b[4]); y = y + bh + gap
  end
end

local TABS = { { "map", "Map" }, { "info", "Info" }, { "haul", "Haul" }, { "settings", "Settings" } }

local function drawTurtle(w, h)
  local id = ui.id
  if not cfg.turtles[id] then ui.page = "overview"; return drawOverview(w, h) end
  ui.tab = ui.tab or "map"
  local st, colour = stateOf(id)
  local m = maps[id]
  header(w, "< " .. nameOf(id), (ui.tab == "map" and m and not m.none) and (m.north and "north is up" or "up = way it faced") or nil)
  hit(1, 1, math.min(w, #nameOf(id) + 4), 1, function() ui.page = "overview" end)

  local side = w >= 44
  local sw = side and math.max(18, math.min(24, math.floor(w * 0.36))) or 0
  local px, pw = 2, side and (w - sw - 3) or (w - 2)
  local top, bottom = 3, h - 1
  if side then drawSide(id, w - sw, top, sw, bottom) end
  if not side and ui.tab == "do" then drawSide(id, px, top, pw, bottom)
  elseif ui.tab == "info" then
    local y = drawStatus(id, px, top, pw, bottom)
    local l = live[id]
    if (not l or os.clock() - l.seen > 120) and y + 1 <= bottom then
      if ui.confirm == "forget" then
        smallButton(px, y + 1, "Sure? Forget it", K.red, function()
          cfg.turtles[id] = nil; live[id] = nil; maps[id] = nil; saveCfg(); ui.page, ui.confirm = "overview", nil
          say("Forgotten. If it talks again it comes back.", K.orange)
        end, K.white)
      else
        smallButton(px, y + 1, "Forget this turtle", K.grey, function() ui.confirm = "forget" end, K.white)
      end
    end
  elseif ui.tab == "haul" then drawHaul(id, px, top, pw, bottom)
  elseif ui.tab == "settings" then drawSettings(id, px, top, pw, bottom)
  else drawMapTab(id, px, top, pw, bottom) end

  -- Footer: tabs + Back
  at(1, h, (" "):rep(w))
  local x = 2
  local tabs = TABS
  if not side then tabs = { { "map", "Map" }, { "do", "Do" }, { "info", "Info" }, { "settings", "Set" } } end
  for _, tb in ipairs(tabs) do
    local on = ui.tab == tb[1]
    if x + #tb[2] + 1 <= w - 7 then
      x = smallButton(x, h, tb[2], on and K.cyan or K.grey, function() ui.tab, ui.confirm = tb[1], nil end, on and K.black or K.white) - 1
    end
  end
  smallButton(w - 7, h, "Back", K.grey, function() ui.page, ui.confirm = "overview", nil end, K.white)
end

local function draw()
  for _, v in ipairs(views) do
    d = v.dev()
    if d then
      hits = {}
      ui = v.ui
      local ok = pcall(function()
        if v.kind == "monitor" then d.setTextScale(TEXT_SCALE) end
        local w, h = d.getSize()
        if not w then return end
        d.setBackgroundColour(K.black); d.clear()
        if ui.page == "map" then ui.page, ui.tab = "turtle", "map" end
        if ui.page == "turtle" then drawTurtle(w, h) else drawOverview(w, h) end
      end)
      v.hits = hits
      if not ok and v.kind == "monitor" then mon, monSide = findMonitor() end
    end
  end
end

---------------------------------------------------------------------------
-- Radio
---------------------------------------------------------------------------
local function sendOrder(id)
  local t = cfg.turtles[id]
  local l = live[id]
  if t.reboot and os.epoch("utc") - (t.rebootAt or 0) > REBOOT_WAIT then
    t.reboot, t.rebootAt = nil, nil
    saveCfg()
    say(nameOf(id) .. " never confirmed its reboot: old program? Reboot it by hand once.", K.orange)
  end
  local msg = { type = "cmd", to = id }
  local need = false
  if t.seq and not (l and (l.s.seq or 0) >= t.seq) then msg.want, msg.seq = t.want, t.seq; need = true end
  if t.setSeq and t.set and not (l and (l.s.setSeq or 0) >= t.setSeq) then msg.set, msg.setSeq = t.set, t.setSeq; need = true end
  if t.reboot then msg.reboot = t.reboot; need = true end
  if need then rednet.send(id, msg, PROTOCOL) end
end

local function summary()
  local n = 0
  for _ in pairs(cfg.turtles) do n = n + 1 end
  local nProb, worst = problems()
  local working = 0
  for id, l in pairs(live) do if cfg.turtles[id] and l.s.state == "working" and os.clock() - l.seen <= STALE then working = working + 1 end end
  return { type = "farmhand", id = os.getComputerID(), label = os.getComputerLabel() or "Farmhand",
           turtles = n, working = working, problems = nProb,
           note = nProb > 0 and worst or (n == 0 and "no farm turtles yet"
             or ("%d turtle%s, %s"):format(n, n == 1 and "" or "s", working > 0 and (working .. " working") or "all docked")) }
end

local function netLoop()
  local opened = 0
  radioOK = false
  peripheral.find("modem", function(name, m)
    rednet.open(name); opened = opened + 1
    if m.isWireless() then radioOK = true end
    return false
  end)
  if opened == 0 then
    say("No modem! I need a wireless or ender modem to reach the farm turtles.", K.red)
    while true do draw(); os.sleep(5) end
  end
  local lastSend, lastSummary = -100, -100
  while true do
    local from, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "status" and (msg.role == "farmer" or msg.role == "lumberjack") then
      local id = tonumber(msg.id) or from
      live[id] = { s = msg, seen = os.clock() }
      local t = cfg.turtles[id]
      if not t or t.label ~= msg.label or t.role ~= msg.role then
        t = entry(id); t.label, t.role = msg.label, msg.role; saveCfg()
      end
      if t.reboot and msg.rebootDone == t.reboot and msg.state ~= "rebooting" then
        t.reboot, t.rebootAt = nil, nil; saveCfg()
        say(nameOf(id) .. " is back up.", K.lime)
      end
    end
    if type(msg) == "table" and msg.type == "map" and cfg.turtles[tonumber(msg.id) or from] then
      maps[tonumber(msg.id) or from] = msg
    end
    -- Maps: fetched for the turtles on screen (overview tiles, or the one open), and again whenever
    -- a turtle says its map changed (it does during rounds, so the arrow and marks stay live)
    local want = {}
    for _, v in ipairs(views) do
      if v.ui.page == "turtle" and v.ui.id then want[v.ui.id] = true
      else for _, vid in ipairs(v.ui.visible or {}) do want[vid] = true end end
    end
    for mid in pairs(want) do
      local l, m = live[mid], maps[mid]
      local changed = not m or (l and l.s.mapStamp and l.s.mapStamp ~= m.stamp)
      if l and l.s.mapStamp and changed and os.clock() - (mapAskedAt[mid] or -100) >= 5 then
        rednet.send(mid, { type = "mapreq", to = mid }, PROTOCOL)
        mapAskedAt[mid] = os.clock()
      end
    end
    local all = os.clock() - lastSend >= SEND_EVERY
    for id in pairs(cfg.turtles) do if all or sendNow[id] then sendOrder(id) end end
    sendNow = {}
    if all then lastSend = os.clock() end
    if os.clock() - lastSummary >= 5 then rednet.broadcast(summary(), PROTOCOL); lastSummary = os.clock() end
    draw()
  end
end

local function inputLoop()
  while true do
    local e, a, b, c = os.pullEvent()
    local v, x, y
    if e == "monitor_touch" and a == monSide then v, x, y = views[1], b, c
    elseif e == "mouse_click" then v, x, y = views[2], b, c
    elseif e == "mouse_scroll" then
      local u = views[2].ui
      if u.page == "overview" then u.scroll = u.scroll + a
      elseif u.page == "turtle" and (u.tab or "map") == "map" then u.follow = false; u.mapR = (u.mapR or 1) + a * 3 end
      draw()
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      mon, monSide = findMonitor(); draw()
    end
    if v then
      ui = v.ui
      for _, r in ipairs(v.hits) do
        if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then r.fn(x, y); break end
      end
      draw()
    end
  end
end

loadCfg()
draw()
parallel.waitForAny(netLoop, inputLoop)
