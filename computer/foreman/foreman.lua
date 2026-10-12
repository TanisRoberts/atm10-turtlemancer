-- foreman.lua  --  mining control for every Digger (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: an advanced computer with an ENDER modem (reaches the Diggers anywhere) and an advanced
-- monitor touching it (bigger is nicer; the computer's own screen works too, click with the mouse).
--
-- Overview: one card per Digger (state, depth, fuel, cargo, where it is). Tap one to open it:
--   its layers (presets or Min/Max), START, STOP + DOCK, its exact position and last haul,
--   and RETIRE (tap twice): it docks for good and its number is never handed out again.
-- Numbers: a new Digger asks for one when it first starts and gets the next free one (Digger-04).
--   A Digger keeps its number when you move it or reset it. Saved in foreman.cfg.
-- Orders are repeated every few seconds, so a Digger picks them up whenever it's in range.
-- Junk caps from storage are passed on, so Diggers stop bringing home what storage has plenty of.

local PROTOCOL   = "tanis-miner"
local BASE       = "tanis-base"
local CONFIG     = "foreman.cfg"
local SEND_EVERY = 3     -- seconds between order broadcasts
local STALE      = 15    -- seconds without news before a Digger greys out
local TEXT_SCALE = 0.5

-- Presets (absolute Y). Each pass covers 3 levels, so small ranges are cheap.
local PRESETS = {
  { "Diamonds",  -59, -58 },
  { "Deep ores", -59, -48 },
  { "Gold",      -19, -13 },
  { "Lapis",      -3,   3 },
  { "Iron",       13,  19 },
  { "Copper",     45,  51 },
}

---------------------------------------------------------------------------
-- Registry: every Digger ever seen, keyed by computer ID
--   { num, label, retired, want, minY, maxY, seq, pMin, pMax }
---------------------------------------------------------------------------
local cfg = { nextNum = 1, diggers = {}, retiredNums = {} }
local function loadCfg()
  if not fs.exists(CONFIG) then return end
  local f = fs.open(CONFIG, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  if type(t) == "table" then
    cfg.nextNum = tonumber(t.nextNum) or 1
    cfg.diggers = type(t.diggers) == "table" and t.diggers or {}
    cfg.retiredNums = type(t.retiredNums) == "table" and t.retiredNums or {}
  end
end
local function saveCfg()
  local f = fs.open(CONFIG, "w"); f.write(textutils.serialize(cfg)); f.close()
end

local function newEntry(num)
  return { num = num, want = "dock", minY = -59, maxY = -58, pMin = -59, pMax = -58, seq = os.epoch("utc") }
end
local function numTaken(num, exceptId)
  if cfg.retiredNums[num] then return true end
  for id, d in pairs(cfg.diggers) do
    if id ~= exceptId and d.num == num and not d.retired then return true end
  end
  return false
end
local function nameOf(num) return ("Digger-%02d"):format(num) end

local live = {}        -- id -> { s = last status, seen = os.clock() }
local capped = {}      -- junk storage has plenty of (from the storage computer)
local storageSeen = nil
local sendNow = {}     -- id -> true: send its order on the next pass

-- A Digger asks for a number. Same computer keeps its number; a hint (its old label) is honoured
-- if free; otherwise the next number. Retired numbers are never reused.
local function assign(id, hint)
  local d = cfg.diggers[id]
  if d and not d.retired then return d.num end
  local num = tonumber(hint)
  if not num or num < 1 or numTaken(num, id) then
    num = cfg.nextNum
    while numTaken(num, id) do num = num + 1 end
  end
  cfg.diggers[id] = newEntry(num)
  cfg.diggers[id].label = nameOf(num)
  cfg.nextNum = math.max(cfg.nextNum, num + 1)
  saveCfg()
  return num
end

local function retire(id)
  local d = cfg.diggers[id]
  if not d then return end
  d.retired, d.want, d.seq = true, "dock", os.epoch("utc")
  cfg.retiredNums[d.num] = d.label or nameOf(d.num)
  saveCfg()
  sendNow[id] = true
end

local function order(id, want)
  local d = cfg.diggers[id]
  if not d or d.retired then return end
  d.want = want
  if want == "run" then d.minY, d.maxY = d.pMin, d.pMax end
  d.seq = os.epoch("utc") -- unique id for this order
  saveCfg()
  sendNow[id] = true
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local K = colours
local STATES = {
  mining = { "MINING", K.lime }, returning = { "RETURNING", K.yellow }, docked = { "DOCKED", K.lightBlue },
  waiting = { "WAITING", K.orange }, error = { "ERROR", K.red }, lost = { "LOST", K.red },
  retired = { "RETIRED", K.grey },
}
local DIMS = { overworld = "Overworld", the_nether = "Nether", the_end = "End" }

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
local function pretty(id)
  local s = tostring(id):gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end
local function presetName(a, b)
  for _, p in ipairs(PRESETS) do if p[2] == a and p[3] == b then return p[1] end end
end
local function rangeText(a, b)
  if not a then return "-" end
  local n = presetName(a, b)
  return (n and (n .. " ") or "") .. a .. ".." .. b
end
local function posText(s)
  if not s or not s.pos then return "position unknown" end
  return ("%d, %d, %d"):format(s.pos.x, s.pos.y, s.pos.z)
end
local function stateOf(id)
  local d, l = cfg.diggers[id], live[id]
  if d and d.retired then return "RETIRED", K.grey end
  if not l then return "NO SIGNAL", K.grey end
  local m = STATES[l.s.state] or { tostring(l.s.state or "?"):upper(), K.white }
  if os.clock() - l.seen > STALE then return m[1], K.grey end
  return m[1], m[2]
end

-- Sorted list of Digger IDs to show
local function digIds(showRetired)
  local out = {}
  for id, d in pairs(cfg.diggers) do
    if (d.retired == true) == (showRetired == true) then out[#out + 1] = id end
  end
  table.sort(out, function(a, b) return cfg.diggers[a].num < cfg.diggers[b].num end)
  return out
end

---------------------------------------------------------------------------
-- Screens: the monitor (if one touches the computer) and the computer's own screen.
-- Both show the same page; each keeps its own tap areas.
---------------------------------------------------------------------------
local ui = { page = "overview", id = nil, scroll = 1, showRetired = false, confirmRetire = nil, notice = nil }

local function findMonitor()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then return peripheral.wrap(side), side end
  end
end
local mon, monSide = findMonitor()
local views = {
  { dev = function() return mon end, kind = "monitor", hits = {} },
  { dev = function() return term end, kind = "term", hits = {} },
}

local d, hits -- current device and its hit list while drawing
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
  at(x, y, pad(left, w), fgL or K.lightGrey)
  if right then
    right = tostring(right):sub(1, w)
    at(x + w - #right, y, right, fgR or K.white)
  end
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
  if ui.notice and os.clock() < ui.notice.untilT then
    at(2, 2, pad(ui.notice.text, w - 2), ui.notice.colour)
  end
end

local function say(text, colour) ui.notice = { text = text, colour = colour or K.lime, untilT = os.clock() + 5 } end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local function drawOverview(w, h)
  local ids = digIds(ui.showRetired)
  local active, retiredN = 0, 0
  for _, dd in pairs(cfg.diggers) do if dd.retired then retiredN = retiredN + 1 else active = active + 1 end end
  local storageTxt = storageSeen and (os.clock() - storageSeen < 30) and "storage ok" or "storage ?"
  header(w, ui.showRetired and "FOREMAN  retired" or "FOREMAN",
    ("%d digger%s  %s"):format(active, active == 1 and "" or "s", storageTxt))

  local top, bottom = 3, h - 2
  local rowH = (h >= 16) and 3 or 1      -- a card is 2 lines + a gap, or 1 line on small screens
  local per = math.max(1, math.floor((bottom - top + 1) / rowH))
  local pages = math.max(1, math.ceil(#ids / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))

  if #ids == 0 then
    local lines = ui.showRetired and { "No retired Diggers." } or {
      "No Diggers yet.",
      "Set up a turtle as a Digger (startup.lua, pick Digger):",
      "it asks me for a number and shows up here.",
    }
    for i, l in ipairs(lines) do at(2, top + i, pad(l, w - 2), i == 1 and K.white or K.lightGrey) end
  end

  for i = 1, per do
    local id = ids[(ui.scroll - 1) * per + i]
    if not id then break end
    local dd, l = cfg.diggers[id], live[id]
    local s = l and l.s
    local y = top + (i - 1) * rowH
    local name = dd.label or nameOf(dd.num)
    local st, colour = stateOf(id)
    local stale = not l or os.clock() - l.seen > STALE
    local bg = (rowH == 3) and K.black or (i % 2 == 0 and K.grey or K.black)
    at(1, y, (" "):rep(w), K.white, bg)
    at(2, y, pad(name, 10), stale and K.lightGrey or K.white, bg)
    at(13, y, pad(st, 9), colour, bg)
    -- the numbers: depth, fuel, cargo
    local bits = {}
    if s then
      bits[#bits + 1] = "Y " .. tostring(s.y or "?")
      if type(s.fuel) == "number" and type(s.fuelLimit) == "number" and s.fuelLimit > 0 then
        bits[#bits + 1] = ("fuel %d%%"):format(math.floor(s.fuel / s.fuelLimit * 100))
      end
      bits[#bits + 1] = ("cargo %s/16"):format(tostring(s.slots or "?"))
    end
    local arrow = w >= 56
    local room = w - 22 - (arrow and 3 or 0)
    if room > 4 then at(22, y, pad(table.concat(bits, "  "), room), stale and K.grey or K.lightGrey, bg) end
    if arrow then at(w - 1, y, ">", K.cyan, bg) end
    if rowH == 3 then
      -- Line 2: what it's doing (or when it was last heard) on the left, where it is on the right
      local where = ""
      if s and s.pos then
        where = posText(s)
        if s.dim and s.dim ~= "overworld" then where = where .. " " .. (DIMS[s.dim] or s.dim) end
      end
      local left
      if stale then
        left = l and ("not heard for " .. fmtAgo(math.floor(os.clock() - l.seen))) or "never heard from"
      elseif s and s.state == "mining" and s.layer and s.layers then
        left = ("%s, layer %s/%s"):format(rangeText(s.minY, s.maxY), s.layer, s.layers)
      else
        left = (s and s.msg ~= "" and s.msg) or rangeText(dd.minY, dd.maxY)
      end
      local roomL = w - 5 - #where - 2
      at(4, y + 1, pad(left, roomL), stale and K.grey or K.lightGrey)
      if #where > 0 then at(w - #where, y + 1, where, K.grey) end
    end
    hit(1, y, w, y + rowH - 1, function() ui.page, ui.id, ui.confirmRetire = "digger", id, nil end)
  end

  -- Footer: dock everyone, show retired, pages
  local fy = h
  at(1, fy, (" "):rep(w))
  local x = 2
  if not ui.showRetired then
    x = smallButton(x, fy, "Dock all", K.red, function()
      for _, id in ipairs(digIds(false)) do order(id, "dock") end
      say("Sent every Digger home.", K.yellow)
    end)
  end
  if retiredN > 0 or ui.showRetired then
    x = smallButton(x, fy, ui.showRetired and "Back" or ("Retired " .. retiredN), K.grey,
      function() ui.showRetired = not ui.showRetired; ui.scroll = 1 end, K.white)
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
-- One Digger
---------------------------------------------------------------------------
local function drawStatus(id, x, y, w, maxY)
  local dd, l = cfg.diggers[id], live[id]
  local s = l and l.s
  local st, colour = stateOf(id)
  local function line(fn) if y <= maxY then fn(); end y = y + 1 end
  line(function() at(x, y, pad(st, w), colour) end)
  line(function() at(x, y, pad(s and s.msg or (dd.retired and "Retired" or "Waiting to hear from it"), w), K.lightGrey) end)
  line(function() at(x, y, pad(l and ("Seen " .. fmtAgo(math.floor(os.clock() - l.seen)) .. " ago") or "Never heard", w), K.grey) end)
  y = y + 1
  local f, lim = s and s.fuel, s and s.fuelLimit
  local frac = (type(f) == "number" and type(lim) == "number" and lim > 0) and f / lim or 1
  line(function() lr(x, y, w, "Fuel", type(f) == "number" and fmtNum(f) or (f or "-")) end)
  line(function() bar(x, y, w, s and frac or 0, frac < 0.2 and K.red or K.lime) end)
  line(function() lr(x, y, w, "Cargo", s and ((s.slots or "?") .. "/16") or "-") end)
  line(function() bar(x, y, w, s and ((s.slots or 0) / 16) or 0, (s and (s.slots or 0) >= 14) and K.orange or K.lightBlue) end)
  line(function() lr(x, y, w, "Layer", s and s.layer and s.layers and (s.layer .. "/" .. s.layers) or "-") end)
  line(function() lr(x, y, w, "Ring", s and s.ring and (s.ring .. "/" .. (s.maxRing or 50)) or "-") end)
  line(function() lr(x, y, w, "Range", s and s.minY and (s.minY .. ".." .. s.maxY) or "-") end)
  y = y + 1
  line(function() lr(x, y, w, "At", posText(s), K.lightGrey, K.white) end)
  line(function()
    local dim = s and s.dim and (DIMS[s.dim] or s.dim) or "?"
    lr(x, y, w, dim, s and s.facing and ("facing " .. s.facing) or "", K.lightGrey, K.lightGrey)
  end)
  line(function()
    local hm = s and s.home
    lr(x, y, w, "Dock", hm and ("%d, %d, %d"):format(hm.x, hm.y, hm.z) or "-", K.lightGrey, K.lightGrey)
  end)
  line(function() lr(x, y, w, "GPS", s and (s.gps and "yes" or "no, counting moves") or "-", K.grey, K.grey) end)
  if s and s.offPath then
    line(function() at(x, y, pad("Moved by hand. Goes home", w), K.orange) end)
    line(function() at(x, y, pad("by a tunnel at Y 0.", w), K.orange) end)
  end
  return y
end

local function drawHaul(id, x, y, w, maxY)
  local l = live[id]
  if y > maxY then return end
  at(x, y, pad("LAST HAUL", w), K.grey)
  y = y + 1
  local haul = l and l.s.haul or {}
  if #haul == 0 and y <= maxY then at(x, y, pad("Nothing yet", w), K.grey) end
  for _, e in ipairs(haul) do
    if y > maxY then break end
    lr(x, y, w, pretty(e[1]), fmtNum(e[2]), K.white, K.cyan)
    y = y + 1
  end
end

local function adjust(dd, key, delta)
  dd[key] = math.max(-63, math.min(319, dd[key] + delta))
  if dd.pMin > dd.pMax then
    if key == "pMin" then dd.pMax = dd.pMin else dd.pMin = dd.pMax end
  end
  saveCfg()
end

local function drawControls(id, x, y, w, maxY)
  local dd, l = cfg.diggers[id], live[id]
  local s = l and l.s
  local tall = maxY - y >= 20
  local bh = tall and 3 or 1
  at(x, y, pad("LAYERS", w), K.grey)
  y = y + 1
  for _, p in ipairs(PRESETS) do
    local sel = dd.pMin == p[2] and dd.pMax == p[3]
    local bg, fg = sel and K.cyan or K.black, sel and K.black or K.white
    at(x, y, (" "):rep(w), fg, bg)
    at(x + 1, y, p[1]:sub(1, w - 2), fg, bg)
    if w >= 20 then
      local r = p[2] .. ".." .. p[3]
      at(x + w - #r - 1, y, r, sel and K.black or K.lightGrey, bg)
    end
    hit(x, y, x + w - 1, y, function() dd.pMin, dd.pMax = p[2], p[3]; saveCfg() end)
    y = y + 1
  end
  for _, row in ipairs({ { "Min Y", "pMin" }, { "Max Y", "pMax" } }) do
    at(x, y, pad(row[1] .. " " .. dd[row[2]], w), K.white)
    at(x + w - 7, y, " - ", K.white, K.grey)
    hit(x + w - 7, y, x + w - 5, y, function() adjust(dd, row[2], -1) end)
    at(x + w - 3, y, " + ", K.white, K.grey)
    hit(x + w - 3, y, x + w - 1, y, function() adjust(dd, row[2], 1) end)
    y = y + 1
  end
  local hint, hc = "", K.grey
  if s and s.seq ~= dd.seq then hint, hc = "Sending...", K.yellow
  elseif s and s.offPath then hint, hc = "START/DOCK: send it home", K.orange
  elseif dd.want == "run" and (dd.minY ~= dd.pMin or dd.maxY ~= dd.pMax) then hint, hc = "START to switch", K.orange end
  at(x, y, pad(hint, w), hc)
  y = y + 1
  button(x, y, w, bh, "START", K.lime, function() order(id, "run"); say(dd.label .. ": START sent.") end)
  y = y + bh + (tall and 1 or 0)
  button(x, y, w, bh, w >= 11 and "STOP + DOCK" or "STOP", K.red, function()
    order(id, "dock"); say(dd.label .. ": heading home.", K.yellow)
  end)
  y = y + bh + 1
  if y <= maxY then
    if ui.confirmRetire == id then
      button(x, y, w, 1, "Tap again to retire", K.orange, function()
        retire(id); ui.confirmRetire = nil; ui.page = "overview"
        say(dd.label .. " retired. Number " .. dd.num .. " won't be used again.", K.orange)
      end)
    else
      button(x, y, w, 1, "Retire " .. (dd.label or ""), K.grey, function() ui.confirmRetire = id end, K.white)
    end
  end
end

local function drawDigger(w, h)
  local id = ui.id
  local dd = cfg.diggers[id]
  if not dd then ui.page = "overview"; return drawOverview(w, h) end
  header(w, "< " .. (dd.label or nameOf(dd.num)), "computer #" .. id)
  hit(1, 1, math.min(w, 14), 1, function() ui.page, ui.confirmRetire = "overview", nil end)
  if w >= 44 then
    local cw = math.floor((w - 3) / 2)
    local y = drawStatus(id, 2, 3, cw, h)
    drawHaul(id, 2, y + 1, cw, h)
    if not dd.retired then drawControls(id, cw + 3, 3, w - cw - 3, h) end
  else
    local y = drawStatus(id, 1, 3, w, h)
    if not dd.retired then
      drawControls(id, 1, y + 1, w, h)
    else
      drawHaul(id, 1, y + 1, w, h)
    end
  end
  smallButton(w - 7, h, "Back", K.grey, function() ui.page, ui.confirmRetire = "overview", nil end, K.white)
end

local function draw()
  for _, v in ipairs(views) do
    d = v.dev()
    if d then
      hits = {}
      local ok = pcall(function()
        if v.kind == "monitor" then d.setTextScale(TEXT_SCALE) end
        local w, h = d.getSize()
        if not w then return end
        d.setBackgroundColour(K.black); d.clear()
        if ui.page == "digger" then drawDigger(w, h) else drawOverview(w, h) end
      end)
      v.hits = hits
      if not ok and v.kind == "monitor" then mon, monSide = findMonitor() end
    end
  end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function sendOrder(id)
  local dd = cfg.diggers[id]
  local list = {}
  for name in pairs(capped) do list[#list + 1] = name end
  rednet.send(id, {
    type = "cmd", to = id, want = dd.retired and "dock" or dd.want, minY = dd.minY, maxY = dd.maxY,
    seq = dd.seq, retired = dd.retired == true, capped = list,
  }, PROTOCOL)
end

local function netLoop()
  local opened = 0
  peripheral.find("modem", function(name) rednet.open(name); opened = opened + 1; return false end)
  if opened == 0 then
    say("No modem! I need an ender modem to reach the Diggers.", K.red)
    while true do draw(); os.sleep(5) end
  end
  local lastSend = -100
  while true do
    local from, msg, proto = rednet.receive(1)
    if type(msg) == "table" and proto == PROTOCOL then
      if msg.type == "register" and msg.id == from then
        local num = assign(from, msg.want)
        local label = nameOf(num)
        rednet.send(from, { type = "assigned", id = from, num = num, label = label }, PROTOCOL)
        say(("%s joined the crew."):format(label))
        sendNow[from] = true
      elseif msg.type == "status" and msg.id == from then
        live[from] = { s = msg, seen = os.clock() }
        local dd = cfg.diggers[from]
        if not dd and tonumber(msg.num) and not numTaken(tonumber(msg.num), from) then
          -- A Digger I don't know that already has a number (e.g. foreman.cfg was lost): adopt it
          dd = newEntry(tonumber(msg.num))
          dd.label = msg.label or nameOf(dd.num)
          if msg.minY then dd.minY, dd.maxY, dd.pMin, dd.pMax = msg.minY, msg.maxY, msg.minY, msg.maxY end
          if msg.want then dd.want = msg.want end
          if msg.seq then dd.seq = msg.seq end
          if msg.retired then dd.retired = true; cfg.retiredNums[dd.num] = dd.label end
          cfg.diggers[from] = dd
          cfg.nextNum = math.max(cfg.nextNum, dd.num + 1)
          saveCfg()
        elseif dd and msg.label and msg.label ~= dd.label and not dd.retired then
          dd.label = msg.label; saveCfg()
        end
      end
    elseif type(msg) == "table" and proto == BASE and msg.type == "storage" then
      storageSeen = os.clock()
      local set = {}
      for _, n in ipairs(type(msg.overcap) == "table" and msg.overcap or {}) do set[n] = true end
      capped = set
    end
    local all = os.clock() - lastSend >= SEND_EVERY
    for id in pairs(cfg.diggers) do
      if all or sendNow[id] then sendOrder(id) end
    end
    sendNow = {}
    if all then lastSend = os.clock() end
    draw()
  end
end

local function inputLoop()
  while true do
    local e, a, b, c = os.pullEvent()
    local v, x, y
    if e == "monitor_touch" and a == monSide then v, x, y = views[1], b, c
    elseif e == "mouse_click" then v, x, y = views[2], b, c
    elseif e == "mouse_scroll" and ui.page == "overview" then ui.scroll = ui.scroll + a; draw()
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      mon, monSide = findMonitor(); draw()
    end
    if v then
      for _, r in ipairs(v.hits) do
        if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then
          r.fn()
          draw()
          break
        end
      end
    end
  end
end

loadCfg()
draw()
parallel.waitForAny(netLoop, inputLoop)
