-- farmhand.lua  --  the Farmhand: control screen for every farm turtle (Partridge, Woodpecker...)
--
-- Needs: an advanced computer with a wireless or ENDER modem (ender reaches farms anywhere) and an
-- advanced monitor touching it (any size; the computer's own screen works too, click with the mouse).
--
-- Overview: one card per farm turtle: what it's doing, fuel, its last round, when the next one is.
-- Tap one to open it:
--   ROUNDS NOW, PAUSE / GO, RE-MAP (walk the farm again: new rows, moved paths), FOUND (after you've
--   carried a lost turtle home), REBOOT (it finishes what it's doing, restarts and updates)
--   Settings, changed live: how often it does rounds, how many seeds/saplings it keeps, how often it
--   re-maps. They're written into the turtle's own .env file.
--   Its exact position (with GPS), last haul and everything it has brought in since it started.
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
  if s.role == "lumberjack" then return ("chopped %d, planted %d"):format(r.chopped or 0, r.planted or 0) end
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
local function newUi() return { page = "overview", id = nil, scroll = 1, notice = nil, confirm = nil } end
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
-- Overview
---------------------------------------------------------------------------
local function drawOverview(w, h)
  local list = ids()
  if radioOK == false and not (ui.notice and os.clock() < ui.notice.untilT) then
    ui.notice = { text = "No wireless/ender modem on me: the turtles can't hear me", colour = K.red, untilT = os.clock() + 1e9 }
  end
  local nProb = problems()
  header(w, "FARMHAND", ("%d turtle%s%s"):format(#list, #list == 1 and "" or "s",
    nProb > 0 and ("  " .. nProb .. " need" .. (nProb == 1 and "s" or "") .. " you") or "  all fine"))
  local top, bottom = 3, h - 2
  local rowH = (h >= 16) and 3 or 1
  local per = math.max(1, math.floor((bottom - top + 1) / rowH))
  local pages = math.max(1, math.ceil(#list / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))

  if #list == 0 then
    local lines = { "No farm turtles heard yet.", "Set up a turtle as Partridge (crops) or Woodpecker (trees):",
                    "it shows up here as soon as it's on the air." }
    for i, l in ipairs(lines) do at(2, top + i, pad(l, w - 2), i == 1 and K.white or K.lightGrey) end
  end

  for i = 1, per do
    local id = list[(ui.scroll - 1) * per + i]
    if not id then break end
    local l = live[id]
    local s = l and l.s
    local y = top + (i - 1) * rowH
    local st, colour = stateOf(id)
    local stale = not l or os.clock() - l.seen > STALE
    local bg = (rowH == 3) and K.black or (i % 2 == 0 and K.grey or K.black)
    at(1, y, (" "):rep(w), K.white, bg)
    at(2, y, pad(nameOf(id), 10), stale and K.lightGrey or K.white, bg)
    at(13, y, pad(st, 10), colour, bg)
    local bits = {}
    if s then
      bits[#bits + 1] = ROLE_NAME[s.role] or s.role or "?"
      if type(s.fuel) == "number" and type(s.fuelLimit) == "number" and s.fuelLimit > 0 then
        bits[#bits + 1] = ("fuel %d%%"):format(math.floor(s.fuel / s.fuelLimit * 100))
      end
      local nt = nextText(s)
      if nt ~= "" then bits[#bits + 1] = nt end
    end
    local arrow = w >= 56
    local room = w - 24 - (arrow and 3 or 0)
    if room > 4 then at(24, y, pad(table.concat(bits, "  "), room), stale and K.grey or K.lightGrey, bg) end
    if arrow then at(w - 1, y, ">", K.cyan, bg) end
    if rowH == 3 then
      local left
      if stale then
        left = l and ("not heard for " .. fmtAgo(math.floor(os.clock() - l.seen))) or "never heard from"
      elseif s.state == "docked" and s.lastRound then
        left = "Last round: " .. lastRoundText(s)
      else
        left = tostring(s.msg or "")
      end
      local where = s and s.pos and posText(s) or ""
      local roomL = w - 5 - #where - 2
      at(4, y + 1, pad(left, roomL), stale and K.grey or (s and (s.state == "error" or s.state == "lost") and K.orange or K.lightGrey))
      if #where > 0 then at(w - #where, y + 1, where, K.grey) end
    end
    hit(1, y, w, y + rowH - 1, function() ui.page, ui.id, ui.confirm = "turtle", id, nil end)
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
-- One turtle
---------------------------------------------------------------------------
local function drawStatus(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  local st, colour = stateOf(id)
  local function line(fn) if y <= maxY then fn() end y = y + 1 end
  line(function() at(x, y, pad(st, w), colour) end)
  line(function() at(x, y, pad(s and s.msg or "Waiting to hear from it", w), K.lightGrey) end)
  line(function() at(x, y, pad(l and ("Seen " .. fmtAgo(math.floor(os.clock() - l.seen)) .. " ago") or "Never heard", w), K.grey) end)
  y = y + 1
  local f, lim = s and s.fuel, s and s.fuelLimit
  local frac = (type(f) == "number" and type(lim) == "number" and lim > 0) and f / lim or 1
  line(function() lr(x, y, w, "Fuel", type(f) == "number" and fmtNum(f) or (f or "-")) end)
  line(function() bar(x, y, w, s and frac or 0, frac < 0.1 and K.red or K.lime) end)
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
  line(function() lr(x, y, w, s and s.facing and ("facing " .. s.facing) or "", s and s.home and ("home %d, %d, %d"):format(s.home.x, s.home.y, s.home.z) or "", K.lightGrey, K.lightGrey) end)
  line(function()
    local txt = not s and "-" or s.anchored and "pinned to GPS: never lost" or s.gps and "GPS seen, not pinned yet" or "no GPS: counting moves"
    lr(x, y, w, "GPS", txt, K.grey, s and not s.anchored and K.orange or K.grey)
  end)
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

local function drawControls(id, x, y, w, maxY)
  local l = live[id]
  local s = l and l.s
  local t = cfg.turtles[id] or {}
  local bh = (maxY - y >= 22) and 3 or 1
  local gap = bh == 3 and 1 or 0
  local function big(label, bg, fn, fg)
    if y + bh - 1 > maxY then return end
    button(x, y, w, bh, label, bg, fn, fg); y = y + bh + gap
  end
  big("ROUNDS NOW", K.lime, function() order(id, "rounds"); say(nameOf(id) .. " is off on its rounds.") end)
  if s and s.paused then
    big("GO", K.lime, function() order(id, "go"); say(nameOf(id) .. " is back on its timer.") end)
  else
    big("PAUSE", K.orange, function() order(id, "stop"); say(nameOf(id) .. " will stay docked.", K.orange) end)
  end
  big("RE-MAP", K.lightBlue, function() order(id, "survey"); say(nameOf(id) .. " will walk its farm again.", K.lightBlue) end)
  if s and s.state == "lost" then
    big("FOUND", K.yellow, function()
      order(id, "found"); say("Put " .. nameOf(id) .. " on its home spot first: it works out the rest.", K.yellow)
    end)
  end
  local pendingReboot = t.reboot ~= nil
  big(pendingReboot and "REBOOTING..." or "REBOOT", K.purple, function()
    requestReboot(id); say(nameOf(id) .. " reboots once it's finished what it's doing.", K.purple)
  end, K.white)

  -- Settings
  if y + 1 > maxY then return end
  y = y + (gap > 0 and 0 or 1)
  at(x, y, pad("SETTINGS", w), K.grey); y = y + 1
  for _, def in ipairs(SETTINGS[s and s.role or ""] or {}) do
    if y > maxY then break end
    local k, label, unit, step, mn, mx = def[1], def[2], def[3], def[4], def[5], def[6]
    local v, pending = settingValue(id, k)
    local val = (v == nil) and "?" or (tostring(v) .. (unit ~= "" and (" " .. unit) or ""))
    if k == "RESURVEY_EVERY" and v == 0 then val = "never" end
    local bx = x + w - 3
    local vx = bx - 1 - #val
    local mxL = vx - 4 - x - 1                 -- room left for the label
    if #label > mxL then label = label:gsub("^Rounds every", "Every"):gsub("^Re%-map every", "Re-map"):gsub("^Keep ", "") end
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
    y = y + 1
  end
  if y <= maxY then at(x, y, pad("Yellow = sent, not confirmed yet", w), K.grey) end
end

local function drawTurtle(w, h)
  local id = ui.id
  if not cfg.turtles[id] then ui.page = "overview"; return drawOverview(w, h) end
  header(w, "< " .. nameOf(id), "computer #" .. id)
  hit(1, 1, math.min(w, 16), 1, function() ui.page = "overview" end)
  if w >= 44 then
    local cw = math.floor((w - 3) / 2)
    local y = drawStatus(id, 2, 3, cw, h - 1)
    drawHaul(id, 2, y + 1, cw, h - 1)
    drawControls(id, cw + 3, 3, w - cw - 3, h - 2)
  else
    local y = drawStatus(id, 1, 3, w, h - 1)
    drawControls(id, 1, y + 1, w, h - 2)
  end
  local l = live[id]
  local stale = not l or os.clock() - l.seen > 120
  local x = 2
  if stale then
    if ui.confirm == "forget" then
      x = smallButton(x, h, "Sure? Forget it", K.red, function()
        cfg.turtles[id] = nil; live[id] = nil; saveCfg(); ui.page, ui.confirm = "overview", nil
        say("Forgotten. If it talks again it comes back.", K.orange)
      end, K.white)
    else
      x = smallButton(x, h, "Forget", K.grey, function() ui.confirm = "forget" end, K.white)
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
      if u.page == "overview" then u.scroll = u.scroll + a end
      draw()
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      mon, monSide = findMonitor(); draw()
    end
    if v then
      ui = v.ui
      for _, r in ipairs(v.hits) do
        if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then r.fn(); break end
      end
      draw()
    end
  end
end

loadCfg()
draw()
parallel.waitForAny(netLoop, inputLoop)
