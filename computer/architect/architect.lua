-- architect.lua  --  Weaver's control computer (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: an advanced computer with a wireless or ender modem. Everything is on the computer's own
-- screen (click with the mouse, type commands at the bottom). An advanced monitor touching the
-- computer (any size, made for 2x2) shows just the map, always following Weaver: his layer, him, the
-- progress bar and the layer's gaps. It's display only; the computer's Map tab is the one you drive.
--
-- Tabs (click them, or press Tab):
--   Status   what he's doing, where he is, fuel, what he's missing, buttons for every order
--   Map      the build seen from above: the layer he's on (done / to do / gaps), him, his next
--            block, the dock and the corner markers. Gaps (magenta) are blocks he left out because
--            storage had none: he fills them in when it does. Scroll or [-] [+] to zoom, arrows to pan, PgUp/PgDn to
--            look at other layers, [Follow] to go back to him
--   Side     the whole island from the side: layers done, the one he's on, him, sea level
--   Bill     materials still needed vs what storage has
--   Corners  where the 8 test markers went (the top 4 are high up in the sky)
--   Log      everything he's reported and every order sent
-- Commands (type at the bottom, Enter): build, stop, test, clear, reboot, layer <n>, follow, ext,
--   zoom <n>, refresh, help. "reboot" makes him reboot (and update) the next time he's at the dock.
--
-- Orders: sent straight to Weaver and repeated until he confirms. The mainframe's weaver_link hears
-- them too and keeps repeating the newest order, so chat orders and Architect orders never fight.
-- The plan's shape comes from Weaver himself (he has the plan file), so nothing to copy over here.

local PROTOCOL = "tanis-rigger"
local BASE     = "tanis-base"
local LOGFILE  = "architect.log"
local LOG_KEEP = 200
local STALE    = 15      -- seconds without a status before he greys out
local RESEND   = 2       -- seconds between order repeats until he confirms
local GIVE_UP  = 60      -- stop repeating an order after this long
local PAD      = 3       -- blocks of padding around the build on the map

local G  = dofile("art_gfx.lua")
local RP = dofile("weaverplan.lua")

local W, H = term.getSize()
local TOP, BOT = 3, H - 2           -- content rows

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local st = {
  id = nil, status = nil, seen = nil,        -- Weaver's latest status
  info = nil, infoAsked = -100,               -- plan + site (from Weaver)
  layers = {}, layerAsked = {},               -- [n] = ordered cells { px, pz, ch, wx, wz }
  gaps = {}, gapsAsked = {}, gapsVer = nil,   -- ["n" or "ext"] = { {x, z}, ... } of the gaps there
  items = nil, itemsSeen = nil,               -- storage's stock (by item name)
  lastLine = nil,
}
local ui = {
  tab = "status", input = "", notice = nil, noticeAt = 0,
  layer = nil, follow = true, ext = nil, zoom = nil, vx = nil, vz = nil, axis = "x",
  scroll = { bill = 0, log = 0 }, hits = {}, help = false,
}
local order = nil    -- { want, seq, sentAt, firstAt, word } until Weaver confirms
local reboot = nil   -- { token, sentAt, firstAt, done }
local log = {}

local TABS = { { "status", "Status" }, { "map", "Map" }, { "side", "Side" }, { "bill", "Bill" },
               { "corners", "Corners" }, { "log", "Log" } }
local WANTS = { build = "build", stop = "dock", dock = "dock", home = "dock", test = "test", clear = "clear" }
local WORDS = { build = "build", dock = "stop", test = "test", clear = "clear", idle = "idle" }

---------------------------------------------------------------------------
-- Little helpers
---------------------------------------------------------------------------
local function now() return os.clock() end
local function clock()
  local ok, s = pcall(os.date, "!%H:%M:%S", math.floor(os.epoch("local") / 1000))
  return ok and s or textutils.formatTime(os.time(), true)
end
local function short(name) return (tostring(name):gsub("^.-:", ""):gsub("_", " ")) end
local function comma(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local neg = s:sub(1, 1) == "-"; if neg then s = s:sub(2) end
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return (neg and "-" or "") .. out
end
local function ago(t)
  if not t then return "never" end
  local s = math.floor(now() - t)
  if s < 60 then return s .. "s ago" end
  if s < 3600 then return math.floor(s / 60) .. "m ago" end
  return math.floor(s / 3600) .. "h ago"
end
local function fit(s, n)
  s = tostring(s)
  if #s > n then return s:sub(1, math.max(0, n - 1)) .. "~" end
  return s
end
local function wrap(s, n)
  local out, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    if #line == 0 then line = word
    elseif #line + 1 + #word <= n then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if #line > 0 then out[#out + 1] = line end
  return out
end

local function addLog(text)
  log[#log + 1] = clock() .. " " .. text
  while #log > LOG_KEEP do table.remove(log, 1) end
  pcall(function()
    local f = fs.open(LOGFILE, "a"); f.writeLine(log[#log]); f.close()
  end)
end
local function loadLog()
  if not fs.exists(LOGFILE) then return end
  local f = fs.open(LOGFILE, "r")
  while true do
    local l = f.readLine()
    if not l then break end
    log[#log + 1] = l
  end
  f.close()
  while #log > LOG_KEEP do table.remove(log, 1) end
  local f2 = fs.open(LOGFILE, "w")            -- keep the file short
  for _, l in ipairs(log) do f2.writeLine(l) end
  f2.close()
end

local function notice(text) ui.notice, ui.noticeAt = text, now(); end

local function alive() return st.seen and now() - st.seen < STALE end

---------------------------------------------------------------------------
-- Network
---------------------------------------------------------------------------
local hasModem, hasWireless = false, false
peripheral.find("modem", function(name, m)
  rednet.open(name); hasModem = true
  if m.isWireless and m.isWireless() then hasWireless = true end
  return false
end)

local function toWeaver(msg)
  if st.id then rednet.send(st.id, msg, PROTOCOL) else rednet.broadcast(msg, PROTOCOL) end
end

local function askInfo()
  st.infoAsked = now()
  toWeaver({ type = "ask", what = "info", to = st.id })
end
local function askLayer(n)
  if not n or st.layers[n] or (st.layerAsked[n] and now() - st.layerAsked[n] < 5) then return end
  st.layerAsked[n] = now()
  toWeaver({ type = "ask", what = "layer", n = n, to = st.id })
end

-- The gaps on layer n (or "ext"), asked again whenever his gap list changes
local function askGaps(n)
  local s = st.status
  if not s or (tonumber(s.gaps) or 0) == 0 then return end
  local key = tostring(n)
  if st.gaps[key] or (st.gapsAsked[key] and now() - st.gapsAsked[key] < 5) then return end
  st.gapsAsked[key] = now()
  toWeaver({ type = "ask", what = "gaps", n = n, to = st.id })
end

local function gapText(s, max)
  local m = {}
  for i, e in ipairs(s.gapItems or {}) do
    if i > (max or 3) then m[#m + 1] = "..."; break end
    m[#m + 1] = comma(e[2]) .. " " .. short(e[1])
  end
  return table.concat(m, ", ")
end

local function sendOrder(word)
  local want = WANTS[word]
  order = { want = want, word = word, seq = os.epoch("utc"), firstAt = now(), sentAt = -100 }
  addLog("> order: " .. word)
  notice("Sent \"" .. word .. "\". Waiting for Weaver to pick it up...")
end

local function sendReboot()
  if not st.id then notice("Haven't heard from Weaver yet, so I can't reboot him."); return end
  reboot = { token = os.epoch("utc"), firstAt = now(), sentAt = -100 }
  addLog("> reboot requested")
  notice("Reboot queued: he'll reboot (and update) next time he's at the dock.")
end

local function pump()  -- repeat orders until Weaver confirms them
  local s = st.status
  if order then
    if s and type(s.seq) == "number" and s.seq >= order.seq then
      addLog("Weaver took the order: " .. order.word)
      notice("Weaver got it: " .. order.word)
      order = nil
    elseif now() - order.firstAt > GIVE_UP then
      addLog("Weaver never confirmed: " .. order.word)
      notice("Weaver didn't answer. Out of range, or not running? The mainframe keeps repeating it.")
      order = nil
    elseif now() - order.sentAt >= RESEND then
      order.sentAt = now()
      rednet.broadcast({ type = "cmd", want = order.want, seq = order.seq, from = "architect" }, PROTOCOL)
    end
  end
  if reboot and not reboot.done then
    if s and s.rebootDone == reboot.token and s.state ~= "rebooting" then
      reboot.done = true
      addLog("Weaver rebooted and is back")
      notice("Weaver rebooted and is back up.")
      reboot = nil
    elseif now() - reboot.firstAt > 20 * 60 then
      addLog("Reboot request expired (20 min)")
      reboot = nil
    elseif now() - reboot.sentAt >= 3 then
      reboot.sentAt = now()
      rednet.send(st.id, { type = "reboot", to = st.id, token = reboot.token }, PROTOCOL)
    end
  end
end

local function onStatus(from, msg)
  local first = not st.status
  st.id, st.status, st.seen = from, msg, now()
  -- Log what he's doing, but not every "Edge wall 133/550": only when it changes in kind
  local line = tostring(msg.state) .. ((msg.msg and msg.msg ~= "") and (": " .. msg.msg) or "")
  local kind = line:gsub("%d+", "#")
  if kind ~= st.lastKind or (msg.layer and msg.layer ~= st.lastLayer) then
    st.lastKind, st.lastLayer = kind, msg.layer
    addLog(line)
  end
  -- Blocks he had to skip (something he's not allowed to dig was in the way)
  local sk = tonumber(msg.skipped) or 0
  if st.lastSkipped and sk > st.lastSkipped and type(msg.skips) == "table" then
    local new = math.min(sk - st.lastSkipped, #msg.skips)
    for i = #msg.skips - new + 1, #msg.skips do
      local e = msg.skips[i]
      addLog(("Skipped block at %d %d %d: %s"):format(e[1], e[2], e[3], tostring(e[4])))
    end
  end
  st.lastSkipped = sk
  -- Gaps: blocks left out until storage has them
  local gaps = tonumber(msg.gaps) or 0
  if msg.gapsVer ~= st.gapsVer then st.gapsVer, st.gaps = msg.gapsVer, {} end
  if st.lastGaps and (st.lastGaps == 0) ~= (gaps == 0) then
    addLog(gaps > 0 and ("Gaps: leaving out what storage hasn't got (" .. gapText(msg) .. ")")
      or "All gaps filled")
  end
  st.lastGaps = gaps
  if first and (msg.v or 0) < 2 then
    notice("Weaver is on old software: reboot him once by hand (hold Ctrl+R) to update.")
  end
  if (not st.info or st.info.id ~= from) and now() - st.infoAsked > 10 then askInfo()
  elseif st.info and msg.phase == "layer" and msg.layer then askLayer(msg.layer) end
end

local function onMessage(from, msg, proto)
  if type(msg) ~= "table" then return end
  if proto == PROTOCOL then
    st.heardAny = now()
    if msg.type == "cmd" and msg.from ~= "architect" then st.heardLink, st.linkId = now(), from end
    if msg.type == "info" and not st.id then st.id = from end
    if msg.type == "status" then onStatus(from, msg)
    elseif msg.type == "info" then
      st.info = msg; st.layers = {}; st.layerAsked = {}
      addLog("Plan from Weaver: " .. tostring(msg.plan) .. ", " .. comma(msg.blocks) .. " blocks")
    elseif msg.type == "gaps" and msg.n ~= nil then
      if msg.ver == st.gapsVer then st.gaps[tostring(msg.n)] = msg.cells or {} end
    elseif msg.type == "layer" and tonumber(msg.n) and st.info then
      local py = st.info.ybase + msg.n - 1
      local cells = RP.orderRows(msg.rows)
      for _, c in ipairs(cells) do
        c[4], _, c[5] = RP.toWorld(st.info.site, c[1], py, c[2])
      end
      -- keep a handful of layers
      local n = 0
      for k in pairs(st.layers) do n = n + 1 end
      if n >= 6 then
        for k in pairs(st.layers) do if k ~= (st.status and st.status.layer) then st.layers[k] = nil; break end end
      end
      st.layers[msg.n] = cells
    end
  elseif proto == BASE and msg.type == "storage" and type(msg.items) == "table" then
    st.items, st.itemsSeen = msg.items, now()
  end
end

---------------------------------------------------------------------------
-- Drawing basics
---------------------------------------------------------------------------
local HEX = G.HEX
local function cidx(c) return math.floor(math.log(c, 2) + 0.5) end

local function put(x, y, s, fg, bg)
  if y < 1 or y > H then return end
  s = tostring(s)
  if x < 1 then s = s:sub(2 - x); x = 1 end
  if x > W then return end
  s = s:sub(1, W - x + 1)
  if #s == 0 then return end
  term.setCursorPos(x, y)
  term.blit(s, HEX[cidx(fg or colors.white)]:rep(#s), HEX[cidx(bg or colors.black)]:rep(#s))
end
local function clearRow(y, bg) put(1, y, (" "):rep(W), colors.white, bg or colors.black) end
local function button(x, y, label, action, fg, bg)
  local s = "[" .. label .. "]"
  put(x, y, s, fg or colors.white, bg or colors.gray)
  ui.hits[#ui.hits + 1] = { x1 = x, x2 = x + #s - 1, y = y, action = action }
  return x + #s + 1
end
local function bar(x, y, w, frac, fg, bg)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(w * frac + 0.5)
  put(x, y, (" "):rep(n), fg, fg)
  put(x + n, y, (" "):rep(w - n), bg or colors.gray, bg or colors.gray)
end

local STATE_COL = {
  building = colors.lime, docked = colors.lightBlue, returning = colors.yellow, waiting = colors.orange,
  marking = colors.yellow, clearing = colors.yellow, error = colors.red, lost = colors.red,
  done = colors.lime, rebooting = colors.magenta,
}

---------------------------------------------------------------------------
-- Header, summary, footer
---------------------------------------------------------------------------
local function drawHeader()
  clearRow(1, colors.gray)
  put(1, 1, " ARCHITECT", colors.yellow, colors.gray)
  local x = 12
  for _, t in ipairs(TABS) do
    local on = ui.tab == t[1] and not ui.help
    local s = " " .. t[2] .. " "
    put(x, 1, s, on and colors.black or colors.white, on and colors.white or colors.gray)
    ui.hits[#ui.hits + 1] = { x1 = x, x2 = x + #s - 1, y = 1, action = "tab:" .. t[1] }
    x = x + #s
  end
  -- summary
  clearRow(2)
  local s = st.status
  if not s then
    put(1, 2, hasModem and "Listening for Weaver..." or "No modem! Put a wireless or ender modem on me.",
      hasModem and colors.lightGray or colors.red)
  else
    local col = alive() and (STATE_COL[s.state] or colors.white) or colors.gray
    local head = (s.label or "Weaver") .. " " .. tostring(s.state or "?")
    put(1, 2, head, col)
    local rest = (s.msg and s.msg ~= "") and (" " .. s.msg) or ""
    if not alive() then rest = " (not heard " .. ago(st.seen) .. ")" .. rest end
    put(#head + 1, 2, fit(rest, W - #head), alive() and colors.lightGray or colors.gray)
  end
end

local function drawFooter()
  clearRow(H - 1)
  if ui.notice and now() - ui.noticeAt < 20 then put(1, H - 1, fit(ui.notice, W), colors.yellow) end
  clearRow(H, colors.gray)
  put(1, H, "> " .. ui.input, colors.white, colors.gray)
  if #ui.input == 0 then put(3, H, "type a command (help)", colors.lightGray, colors.gray) end
end

---------------------------------------------------------------------------
-- Status tab
---------------------------------------------------------------------------
local FACING = { [0] = "north", "east", "south", "west" }

local function phaseText(s, info)
  if s.phase == "ext" then
    return ("Edge walls %d of %d"):format(math.max(0, (s.ext or 1) - 1), s.extTotal or 0), (s.ext or 1) - 1, s.extTotal or 1
  elseif s.phase == "layer" then
    local n = s.layer or 1
    local cells = st.layers[n]
    local total = cells and #cells
    local y = info and (info.site.sea + info.ybase + n - 1)
    local t = ("Layer %d of %d%s, block %s"):format(n, s.layers or 0, y and (" (Y " .. y .. ")") or "",
      comma(math.max(0, (s.cell or 1) - 1)) .. (total and (" of " .. comma(total)) or ""))
    return t, math.max(0, (s.cell or 1) - 1), total
  elseif s.phase == "done" and (tonumber(s.gaps) or 0) > 0 then
    return "Built all he could: " .. comma(s.gaps) .. " gaps left", 1, 1
  elseif s.phase == "done" then
    return "Finished!", 1, 1
  end
  return "Not started", 0, 1
end

local function drawStatus()
  local s, info = st.status, st.info
  local y = TOP
  if not s then
    put(1, y, "Weaver hasn't been heard yet.", colors.white)
    y = y + 2
    put(1, y, "My radio  ", colors.gray)
    put(11, y, hasWireless and "wireless/ender modem, listening" or (hasModem and "only a WIRED modem: add a wireless/ender one" or "NO modem"),
      hasWireless and colors.lime or colors.red)
    y = y + 1
    put(1, y, "Mainframe ", colors.gray)
    put(11, y, st.heardLink and ("its Weaver link heard " .. ago(st.heardLink) .. " (#" .. st.linkId .. ")") or "not heard either",
      st.heardLink and colors.lime or colors.orange)
    y = y + 1
    put(1, y, "Plan ask  ", colors.gray)
    put(11, y, st.info and ("answered by #" .. tostring(st.id)) or "no answer yet", st.info and colors.lime or colors.orange)
    y = y + 2
    local lines
    if not hasWireless then
      lines = { "I can't hear the turtles without a wireless or ender modem." }
    elseif st.heardLink and not st.info then
      lines = { "The mainframe gets through but Weaver doesn't, so:",
        "- look at Weaver's own screen: is there an error?",
        "- or he's out of my range: plain wireless reaches ~64 blocks.",
        "  An ENDER modem on me hears him anywhere." }
    elseif not st.heardLink then
      lines = { "Nothing at all on Weaver's channel yet. If the mainframe",
        "is running, I'm probably out of range of everything:",
        "an ENDER modem on me fixes that." }
    else
      lines = { "Waiting for his first status (every 3 s)..." }
    end
    for _, l in ipairs(lines) do put(1, y, fit(l, W), colors.lightGray); y = y + 1 end
    return
  end
  put(1, y, "Plan   ", colors.gray)
  put(8, y, fit((info and info.plan or s.plan or "?") .. "  " .. comma(s.total or 0) .. " blocks, "
    .. (s.layers or "?") .. " layers", W - 8), colors.white)
  y = y + 1
  local ptxt, a, b = phaseText(s, info)
  put(1, y, "Now    ", colors.gray); put(8, y, fit(ptxt, W - 8), colors.white)
  y = y + 1
  if b and b > 0 then
    local frac = math.min(1, a / b)
    bar(8, y, W - 15, frac, colors.lime)
    put(W - 6, y, ("%3d%%"):format(math.floor(100 * frac)), colors.lightGray)
  end
  y = y + 1
  local tot = (s.total or 0) > 0 and math.min(1, (s.placed or 0) / s.total) or 0
  put(1, y, "Build  ", colors.gray)
  bar(8, y, W - 15, tot, colors.green)
  put(W - 6, y, ("%3d%%"):format(math.floor(100 * tot)), colors.lightGray)
  y = y + 1
  put(8, y, comma(s.placed or 0) .. " blocks placed by him so far", colors.lightGray)
  y = y + 1
  local at = s.at
  put(1, y, "At     ", colors.gray)
  if at then
    local where = ("X %d  Y %d  Z %d  facing %s"):format(at.x, at.y, at.z, FACING[at.h] or "?")
    put(8, y, where, colors.white)
    y = y + 1
    local gtxt
    if s.gps and s.pos then
      if s.pos.x == at.x and s.pos.y == at.y and s.pos.z == at.z then gtxt = "GPS agrees"
      else gtxt = ("GPS says %d %d %d!"):format(s.pos.x, s.pos.y, s.pos.z) end
    else gtxt = "no GPS fix" end
    local dock = info and info.site
    local dist = dock and (math.abs(at.x - dock.dx) + math.abs(at.y - dock.dy) + math.abs(at.z - dock.dz))
    put(8, y, fit((dist and (dist == 0 and "at the dock, " or (comma(dist) .. " from the dock, ")) or "") .. gtxt, W - 8),
      (s.gps and gtxt ~= "GPS agrees") and colors.red or colors.lightGray)
  else
    put(8, y, "unknown (old software)", colors.lightGray)
  end
  y = y + 1
  put(1, y, "Fuel   ", colors.gray)
  local lim = tonumber(s.fuelLimit) or 20000
  local f = tonumber(s.fuel) or 0
  bar(8, y, W - 22, f / lim, f < 2000 and colors.red or colors.orange)
  put(W - 13, y, comma(f), colors.lightGray)
  y = y + 1
  local m = {}
  for _, e in ipairs(s.missing or {}) do m[#m + 1] = e[1] == "fuel" and (comma(e[2]) .. " fuel") or short(e[1]) end
  if #m > 0 then
    put(1, y, "Out of ", colors.gray)
    local lines = wrap(table.concat(m, ", "), W - 8)
    for i = 1, math.min(2, #lines) do put(8, y, lines[i], colors.red); y = y + 1 end
  end
  if (tonumber(s.gaps) or 0) > 0 then
    put(1, y, "Gaps   ", colors.gray)
    put(8, y, fit(comma(s.gaps) .. " left out, waiting for " .. gapText(s), W - 8), colors.magenta)
    y = y + 1
    if (tonumber(s.gapsAbove) or 0) > 0 then
      put(8, y, fit("(" .. comma(s.gapsAbove) .. " of them sit on top of those, so they wait too)", W - 8), colors.gray)
      y = y + 1
    end
  end
  if (tonumber(s.skipped) or 0) > 0 then
    put(1, y, "Skips  ", colors.gray)
    put(8, y, fit(comma(s.skipped) .. " blocks he couldn't reach (they're in the Log)", W - 8), colors.orange)
    y = y + 1
  end
  if order then
    put(1, y, "Order  ", colors.gray)
    put(8, y, fit(order.word .. ", sent " .. ago(order.firstAt) .. ", waiting for him", W - 8), colors.yellow)
    y = y + 1
  elseif s.want then
    put(1, y, "Order  ", colors.gray); put(8, y, WORDS[s.want] or s.want, colors.lightGray)
    y = y + 1
  end
  if reboot then
    put(1, y, "Reboot ", colors.gray)
    put(8, y, s.state == "rebooting" and "rebooting now..." or "queued: happens at the dock", colors.magenta)
    y = y + 1
  end
  local x = 1
  x = button(x, BOT, "Build", "cmd:build", colors.black, colors.lime)
  x = button(x, BOT, "Stop", "cmd:stop", colors.white, colors.red)
  x = button(x, BOT, "Test", "cmd:test")
  x = button(x, BOT, "Clear", "cmd:clear")
  x = button(x, BOT, "Reboot", "cmd:reboot")
  put(x, BOT, fit("seen " .. ago(st.seen), W - x + 1), alive() and colors.gray or colors.red)
end

---------------------------------------------------------------------------
-- Map tab: the build from above
---------------------------------------------------------------------------
local ROWS = BOT - TOP          -- map rows (the last content row is its toolbar)
local mapDev = {
  getSize = function() return W, ROWS end,
  setCursorPos = function(x, y) term.setCursorPos(x, y + TOP - 1) end,
  blit = function(a, b, c) term.blit(a, b, c) end,
  setPaletteColour = function() end,
}
local gfx = G.new(mapDev)
local PW, PH = gfx.PW, gfx.PH

local C_DONE, C_TODO, C_BOX, C_RIG, C_NEXT, C_DOCK, C_MARK, C_BG, C_SEA, C_GROUND, C_NOW =
  cidx(colors.lime), cidx(colors.lightGray), cidx(colors.gray), cidx(colors.red), cidx(colors.yellow),
  cidx(colors.orange), cidx(colors.brown), cidx(colors.black), cidx(colors.blue), cidx(colors.brown),
  cidx(colors.yellow)
local C_GAP = cidx(colors.magenta)

-- v is a view ({ layer, ext, zoom, vx, vz, follow }): the Map tab's is `ui`, the monitor's is `monView`
local function viewLayer(v)
  local s = st.status
  v = v or ui
  if v.layer then return v.layer end
  return (s and s.phase == "layer" and s.layer) or (s and s.phase == "done" and st.info and st.info.layers) or 1
end
local function showingExt(v)
  v = v or ui
  if v.ext ~= nil then return v.ext end
  local s = st.status
  return s and s.phase == "ext" and not v.layer
end

local function fitZoom(g)
  g = g or gfx
  local b = st.info.bounds
  return math.max((b.x2 - b.x1 + 1 + 2 * PAD) / g.PW, (b.z2 - b.z1 + 1 + 2 * PAD) / g.PH)
end
local function zoomNow(v, g) return (v or ui).zoom or fitZoom(g) end
local function viewCentre(v, g)
  v = v or ui
  local b = st.info.bounds
  local z = zoomNow(v, g)
  local at = st.status and st.status.at
  if v.follow and at and v.zoom and v.zoom < fitZoom(g) then return at.x, at.z end
  if v.vx then return v.vx, v.vz end
  return (b.x1 + b.x2) / 2, (b.z1 + b.z2) / 2
end

-- Draw the map into gfx `g` (w columns wide) for view `v`. Returns the caption (layer, progress, gaps).
local function renderMap(g, w, v)
  local info, s = st.info, st.status
  local PW, PH = g.PW, g.PH
  local gfx = g
  local z = zoomNow(v, g)
  local cx, cz = viewCentre(v, g)
  local function px(wx) return math.floor((wx - cx) / z + PW / 2) + 1 end
  local function pz(wz) return math.floor((wz - cz) / z + PH / 2) + 1 end

  gfx.fill(C_BG)
  local b = info.bounds
  local x1, x2, y1, y2 = px(b.x1 - PAD), px(b.x2 + PAD), pz(b.z1 - PAD), pz(b.z2 + PAD)
  for x = x1, x2 do if x >= 1 and x <= PW then
    if y1 >= 1 and y1 <= PH then gfx.rawPixel(x, y1, C_BOX) end
    if y2 >= 1 and y2 <= PH then gfx.rawPixel(x, y2, C_BOX) end end end
  for y = y1, y2 do if y >= 1 and y <= PH then
    if x1 >= 1 and x1 <= PW then gfx.rawPixel(x1, y, C_BOX) end
    if x2 >= 1 and x2 <= PW then gfx.rawPixel(x2, y, C_BOX) end end end

  local over = {}
  local function ov(wx, wz, col)
    local i = gfx.pixelIndex(px(wx), pz(wz))
    if i then over[i] = col end
  end
  -- Count done / to-do blocks per pixel, majority wins
  local tally = {}
  local function add(wx, wz, done)
    local i = gfx.pixelIndex(px(wx), pz(wz))
    if not i then return end
    local t = tally[i]
    if not t then t = { 0, 0 }; tally[i] = t end
    if done then t[1] = t[1] + 1 else t[2] = t[2] + 1 end
  end
  local n = viewLayer(v)
  local label
  if showingExt(v) then
    local upto = (s and s.phase == "ext") and (s.ext or 1) - 1 or ((s and (s.phase == "layer" or s.phase == "done")) and #info.ext or 0)
    for i, e in ipairs(info.ext) do add(e[1], e[2], i <= upto) end
    label = ("Edge walls %d/%d"):format(upto, #info.ext)
    if s and s.phase == "ext" and info.ext[s.ext or 1] then
      local e = info.ext[s.ext or 1]; ov(e[1], e[2], C_NEXT)
    end
  else
    local cells = st.layers[n]
    if not cells then askLayer(n); label = "Layer " .. n .. ": asking Weaver..."
    else
      local doneUpTo
      if not s or s.phase == nil or s.phase == "ext" then doneUpTo = 0
      elseif s.phase == "done" then doneUpTo = #cells
      elseif n < (s.layer or 1) then doneUpTo = #cells
      elseif n > (s.layer or 1) then doneUpTo = 0
      else doneUpTo = (s.cell or 1) - 1 end
      for i, c in ipairs(cells) do add(c[4], c[5], i <= doneUpTo) end
      label = ("Layer %d/%d  Y %d  %s/%s"):format(n, info.layers, info.site.sea + info.ybase + n - 1,
        comma(doneUpTo), comma(#cells))
      if s and s.phase == "layer" and n == s.layer and cells[s.cell or 1] then
        local c = cells[s.cell or 1]; ov(c[4], c[5], C_NEXT)
      end
    end
  end
  for i, t in pairs(tally) do
    local x = (i - 1) % PW + 1
    gfx.rawPixel(x, (i - x) / PW + 1, t[1] >= t[2] and C_DONE or C_TODO)
  end
  -- Gaps on this layer (or in the edge walls): left out until storage has the block
  if s and (tonumber(s.gaps) or 0) > 0 then
    local key = showingExt(v) and "ext" or n
    local gl = st.gaps[tostring(key)]
    if gl then
      for _, g in ipairs(gl) do ov(g[1], g[2], C_GAP) end
      if #gl > 0 then label = (label or "") .. "  gaps " .. comma(#gl) end
    else
      askGaps(key)
    end
  end
  -- Corner markers, dock, Weaver
  for _, c in ipairs((s and s.corners) or {}) do if c.my then ov(c.x, c.z, C_MARK) end end
  ov(info.site.dx, info.site.dz, C_DOCK)
  local at = s and s.at
  if at then
    local i = gfx.pixelIndex(px(at.x), pz(at.z))
    if i then over[i] = C_RIG
    else
      local dx, dz = at.x - cx, at.z - cz
      label = (label or "") .. "  Weaver " .. (math.abs(dx) > math.abs(dz) and (dx > 0 and "->" or "<-") or (dz > 0 and "v" or "^"))
    end
  end
  gfx.setOverlay(over)
  -- Labels on top
  local cells_ = {}
  gfx.text(cells_, 1, 1, "N^", cidx(colors.white), C_BG)
  if at then
    local rel = ""
    if not showingExt(v) and info then
      local ly = info.site.sea + info.ybase + n - 1
      local d = at.y - ly - 1
      rel = d == 0 and " (on this layer)" or (d > 0 and (" (" .. d .. " above)") or (" (" .. -d .. " below)"))
    end
    gfx.text(cells_, w - #("Weaver Y " .. at.y .. rel) + 1, 1, "Weaver Y " .. at.y .. rel, cidx(colors.red), C_BG)
  end
  gfx.setLayer("labels", cells_)
  gfx.markAll()
  gfx.flush()
  return label
end

local function drawMap()
  ui.mapLabel = nil
  if not st.info then
    put(2, TOP + 2, st.status and "Asking Weaver for the plan..." or "Waiting for Weaver...", colors.lightGray)
    if st.status and now() - st.infoAsked > 10 then askInfo() end
    return
  end
  local label = renderMap(gfx, W, ui)
  ui.mapLabel = label

  -- toolbar
  local y = BOT
  clearRow(y)
  local x = 1
  x = button(x, y, "-", "zoom:out")
  x = button(x, y, "+", "zoom:in")
  x = button(x, y, "Fit", "zoom:fit")
  x = button(x, y, "<", "layer:-1")
  x = button(x, y, ">", "layer:1")
  x = button(x, y, ui.follow and not ui.layer and "Following" or "Follow", "follow",
    (ui.follow and not ui.layer) and colors.black or colors.white, (ui.follow and not ui.layer) and colors.lime or colors.gray)
  x = button(x, y, "Ext", "ext", showingExt() and colors.black or colors.white, showingExt() and colors.orange or colors.gray)
  put(x, y, fit(label or "", W - x + 1), colors.lightGray)
end

---------------------------------------------------------------------------
-- Monitor: the map alone, following Weaver
---------------------------------------------------------------------------
local monView = { follow = true }      -- no layer / zoom / pan set: his layer, fitted to the screen
local mon = { dev = nil, side = nil, gfx = nil, w = 0, h = 0 }

local function findMonitor()
  for _, side in ipairs(redstone.getSides()) do
    if peripheral.hasType(side, "monitor") then return peripheral.wrap(side), side end
  end
end

-- (Re)attach to the monitor on one of our sides, and size the map to it
local function syncMonitor()
  local dev, side = findMonitor()
  if not dev then mon.dev, mon.side, mon.gfx = nil, nil, nil; return end
  pcall(dev.setTextScale, 0.5)
  local w, h = dev.getSize()
  if dev == mon.dev and mon.side == side and w == mon.w and h == mon.h and mon.gfx then return end
  mon.dev, mon.side, mon.w, mon.h = dev, side, w, h
  local rows = h - 2                    -- the top row is the progress line, the bottom one the caption
  mon.gfx = G.new({
    getSize = function() return w, rows end,
    setCursorPos = function(x, y) dev.setCursorPos(x, y + 1) end,
    blit = function(a, b, c) dev.blit(a, b, c) end,
    setPaletteColour = function() end,
  })
end

local function monPut(x, s, fg, bg, y)
  s = tostring(s):sub(1, mon.w - x + 1)
  if #s == 0 then return end
  mon.dev.setCursorPos(x, y or 1)
  mon.dev.blit(s, HEX[cidx(fg or colors.white)]:rep(#s), HEX[cidx(bg or colors.black)]:rep(#s))
end

local function drawMonitor()
  if not mon.dev then return end
  local w = mon.w
  local s = st.status
  monPut(1, (" "):rep(w), colors.white, colors.black)
  if not (st.info and s) or mon.h < 5 then
    mon.dev.setBackgroundColour(colors.black); mon.dev.clear()
    monPut(1, fit(s and "Asking Weaver for the plan..." or "Waiting for Weaver...", w), colors.lightGray)
    return
  end
  -- Progress line: Weaver, what he's doing, how much of the build is placed
  local frac = (s.total or 0) > 0 and math.min(1, (s.placed or 0) / s.total) or 0
  local col = alive() and (STATE_COL[s.state] or colors.white) or colors.gray
  local pct = ("%3d%%"):format(math.floor(100 * frac))
  local head = fit((s.label or "Weaver") .. " " .. tostring(s.state or "?"), math.max(1, w - #pct - 1))
  local n = math.floor((w - #pct - 1) * frac + 0.5)
  for x = 1, w - #pct - 1 do
    -- the bar sits behind the text: lime for done, grey for to go
    local ch = head:sub(x, x)
    mon.dev.setCursorPos(x, 1)
    mon.dev.blit(ch ~= "" and ch or " ", HEX[cidx(x <= n and colors.black or col)],
      HEX[cidx(x <= n and colors.lime or colors.gray)])
  end
  monPut(w - #pct + 1, pct, colors.white, colors.black)
  local label = renderMap(mon.gfx, w, monView)
  monPut(1, (" "):rep(w), colors.white, colors.black, mon.h)
  if not alive() then monPut(1, fit("not heard " .. ago(st.seen), w), colors.red, colors.black, mon.h)
  else monPut(1, fit(label or "", w), colors.lightGray, colors.black, mon.h) end
end

---------------------------------------------------------------------------
-- Side tab: the whole island from the side
---------------------------------------------------------------------------
local function drawSide()
  local info, s = st.info, st.status
  if not info then
    put(2, TOP + 2, st.status and "Asking Weaver for the plan..." or "Waiting for Weaver...", colors.lightGray)
    return
  end
  local site, b = info.site, info.bounds
  local useX = ui.axis == "x"
  local a1, a2 = (useX and b.x1 or b.z1) - PAD, (useX and b.x2 or b.z2) + PAD
  local yLo = math.min(site.seabed or (site.sea - 20), b.y1) - 2
  local yHi = b.y2 + 2
  local hz = (a2 - a1 + 1) / PW
  local vz = (yHi - yLo + 1) / PH
  local function px(a) return math.floor((a - a1) / hz) + 1 end
  local function py(y) return PH - math.floor((y - yLo) / vz) end
  gfx.fill(C_BG)
  local function hline(y, col, from, to)
    local yy = py(y)
    for x = px(from or a1), px(to or a2) do if x >= 1 and x <= PW and yy >= 1 and yy <= PH then gfx.rawPixel(x, yy, col) end end
  end
  -- ground and sea
  for y = yLo, (site.seabed or yLo) do hline(y, C_GROUND) end
  hline(site.sea, C_SEA)
  -- edge walls (shown as a band from the seabed up to layer 1, filled as they get built)
  local extDone = (s and s.phase == "ext") and (s.ext or 1) - 1 or ((s and s.phase and s.phase ~= "ext") and #info.ext or 0)
  local extFrac = #info.ext > 0 and extDone / #info.ext or 0
  local prof = info.profile or {}
  if prof[1] then
    local e1, e2 = useX and prof[1][1] or prof[1][3], useX and prof[1][2] or prof[1][4]
    for y = (site.seabed or yLo) + 1, b.y1 - 1 do
      hline(y, C_BOX, e1, e2)
      if extFrac > 0 then hline(y, C_DONE, e1, e1 + math.floor((e2 - e1) * extFrac)) end
    end
  end
  -- layers
  local cur = (s and s.phase == "layer") and s.layer or ((s and s.phase == "done") and info.layers + 1 or 0)
  for n = 1, info.layers do
    local p = prof[n]
    if p then
      local y = site.sea + info.ybase + n - 1
      local col = n < cur and C_DONE or (n == cur and C_NOW or C_TODO)
      hline(y, col, useX and p[1] or p[3], useX and p[2] or p[4])
    end
  end
  local over = {}
  local function ov(a, y, col)
    local i = gfx.pixelIndex(px(a), py(y)); if i then over[i] = col end
  end
  ov(useX and site.dx or site.dz, site.dy, C_DOCK)
  local at = s and s.at
  if at then ov(useX and at.x or at.z, at.y, C_RIG) end
  gfx.setOverlay(over)
  local lab = {}
  gfx.text(lab, 1, 1, "Y " .. yHi, cidx(colors.gray), C_BG)
  gfx.text(lab, 1, ROWS, "Y " .. yLo, cidx(colors.gray), C_BG)
  gfx.text(lab, W - 9, 1, useX and "west|east" or "nrth|sth", cidx(colors.gray), C_BG)
  gfx.setLayer("labels", lab)
  gfx.markAll()
  gfx.flush()
  local y = BOT
  clearRow(y)
  local x = button(1, y, useX and "Looking north" or "Looking west", "axis")
  local txt = cur > info.layers and "all layers done" or (cur > 0 and ("layer " .. cur .. " of " .. info.layers) or "no layers yet")
  if at then txt = txt .. ", him at Y " .. at.y end
  put(x, y, fit(txt .. ", sea Y " .. site.sea, W - x + 1), colors.lightGray)
end

---------------------------------------------------------------------------
-- Bill tab: what's still needed vs storage
---------------------------------------------------------------------------
local function drawBill()
  local s = st.status
  local bill = s and s.bill
  if type(bill) ~= "table" then
    put(2, TOP + 1, "No bill yet: Weaver sends it with his status.", colors.lightGray)
    return
  end
  local missing = {}
  for _, e in ipairs(s.missing or {}) do missing[e[1]] = e[2] end
  local rows, left, covered = {}, 0, 0
  for name, n in pairs(bill) do
    if n > 0 then
      local have = st.items and (st.items[name] or 0) or nil
      rows[#rows + 1] = { name = name, left = n, have = have }
      left = left + n
      if have then covered = covered + math.min(have, n) end
    end
  end
  table.sort(rows, function(a, b)
    local sa, sb = a.have and a.have < a.left, b.have and b.have < b.left
    if sa ~= sb then return sa end
    return a.left > b.left
  end)
  local y = TOP
  put(1, y, fit(comma(left) .. " blocks left" .. (st.items and (", storage covers " ..
    math.floor(100 * covered / math.max(1, left)) .. "%") or ", storage not heard"), W), colors.white)
  y = y + 1
  if st.info and s.phase == "ext" then
    local depth = math.max(0, st.info.bounds.y1 - (st.info.site.seabed or st.info.site.sea - 20) - 1)
    put(1, y, fit("+ edge walls: about " .. comma(((s.extTotal or 0) - (s.ext or 1) + 1) * (depth + 1))
      .. " blocks of rock", W), colors.lightGray)
    y = y + 1
  end
  put(1, y, ("%-24s %9s %9s %6s"):format("Material", "left", "storage", ""), colors.gray)
  y = y + 1
  local room = BOT - y + 1
  ui.scroll.bill = math.max(0, math.min(ui.scroll.bill, #rows - room))
  for i = 1 + ui.scroll.bill, math.min(#rows, ui.scroll.bill + room) do
    local r = rows[i]
    local short_ = r.have and r.have < r.left
    local tag = missing[r.name] and "NEEDED" or (short_ and "short" or (r.have and "ok" or ""))
    local col = missing[r.name] and colors.red or (short_ and colors.orange or colors.white)
    put(1, y, ("%-24s %9s %9s %6s"):format(fit(short(r.name), 24), comma(r.left), r.have and comma(r.have) or "?", tag), col)
    y = y + 1
  end
  if #rows > room then
    put(W - 9, TOP, ("%d-%d/%d"):format(ui.scroll.bill + 1, math.min(#rows, ui.scroll.bill + room), #rows), colors.gray)
  end
end

---------------------------------------------------------------------------
-- Corners tab
---------------------------------------------------------------------------
local RES = {
  placed = { "on the corner", colors.lime }, already = { "already there", colors.lime },
  seabed = { "on the ground", colors.yellow }, failed = { "FAILED", colors.red },
  trip = { "couldn't fly there", colors.red }, going = { "on his way", colors.yellow },
  todo = { "not done", colors.gray },
}
-- The 8 corners in the order Weaver visits them, with a compass name for walking there
local function plannedCorners(bx)
  local out = {}
  for _, y in ipairs({ bx.y1, bx.y2 }) do
    for _, x in ipairs({ bx.x1, bx.x2 }) do
      for _, z in ipairs({ bx.z1, bx.z2 }) do
        out[#out + 1] = { x = x, y = y, z = z, res = "todo",
          name = (z == bx.z1 and "N" or "S") .. (x == bx.x1 and "W" or "E") .. (y == bx.y1 and " bottom" or " top") }
      end
    end
  end
  return out
end

-- Chunks he flies through: the build box + the 2 blocks he may clear around it + his dock
local function chunkSpan(info)
  local b, site = info.bounds, info.site
  local x1, x2 = math.min(b.x1 - 2, site.dx), math.max(b.x2 + 2, site.dx)
  local z1, z2 = math.min(b.z1 - 2, site.dz), math.max(b.z2 + 2, site.dz)
  local c1, c2, d1, d2 = math.floor(x1 / 16), math.floor(x2 / 16), math.floor(z1 / 16), math.floor(z2 / 16)
  return c1, c2, d1, d2, (c2 - c1 + 1) * (d2 - d1 + 1)
end

local function drawCorners()
  local s, info = st.status, st.info
  local tested = s and type(s.corners) == "table" and #s.corners > 0
  local y = TOP
  if not info then
    put(1, y + 1, st.status and "Asking Weaver for the plan..." or "Waiting for Weaver...", colors.lightGray)
    put(1, y + 3, "Weaver also prints the box and chunks on his own screen", colors.lightGray)
    put(1, y + 4, "every time he starts.", colors.lightGray)
  else
    local b = info.bounds
    put(1, y, fit(("Box X %d..%d  Z %d..%d  Y %d..%d"):format(b.x1, b.x2, b.z1, b.z2, b.y1, b.y2), W), colors.white)
    y = y + 1
    local c1, c2, d1, d2, n = chunkSpan(info)
    put(1, y, fit(("Chunks X %d..%d  Z %d..%d  (%d chunks to load)"):format(c1, c2, d1, d2, n), W), colors.cyan)
    y = y + 1
    put(1, y, fit(("  = blocks X %d..%d  Z %d..%d  (incl. his dock)")
      :format(c1 * 16, c2 * 16 + 15, d1 * 16, d2 * 16 + 15), W), colors.cyan)
    y = y + 1
    put(1, y, ("%-2s %-10s %-17s %s"):format("#", "corner", "X Y Z", tested and "marker" or ""), colors.gray)
    y = y + 1
    local plan = plannedCorners(b)
    for i, p in ipairs(plan) do
      local c = tested and s.corners[i] or p
      put(1, y, ("%-2d %-10s %-17s"):format(i, p.name, ("%d %d %d"):format(p.x, p.y, p.z)), colors.white)
      if tested then
        local r = RES[c.res] or { tostring(c.res), colors.white }
        local txt = r[1]
        if c.res == "seabed" and c.my then txt = "on ground Y " .. c.my end
        if c.why and c.res ~= "seabed" then txt = txt .. ": " .. c.why end
        put(32, y, fit(txt, W - 31), r[2])
      end
      y = y + 1
    end
    put(1, y, fit(tested and "The top 4 are high up: look up!" or
      "No test yet: [Test] marks all 8 with dirt.", W), colors.lightGray)
  end
  local x = button(1, BOT, "Test", "cmd:test")
  x = button(x, BOT, "Clear", "cmd:clear")
  put(x, BOT, fit((s and s.markers or 0) .. " markers out", W - x + 1), colors.gray)
end

---------------------------------------------------------------------------
-- Log tab and help
---------------------------------------------------------------------------
local function drawLog()
  local room = BOT - TOP + 1
  local maxScroll = math.max(0, #log - room)
  ui.scroll.log = math.max(0, math.min(ui.scroll.log, maxScroll))
  local first = #log - room + 1 - ui.scroll.log
  for i = 0, room - 1 do
    local l = log[first + i]
    if l then
      local col = l:find(" > ") and colors.yellow or (l:find("error") or l:find("lost")) and colors.red or colors.lightGray
      put(1, TOP + i, fit(l, W), col)
    end
  end
  if #log == 0 then put(2, TOP, "Nothing yet.", colors.gray) end
end

local HELP = {
  "build     start or carry on building",
  "stop      fly home and wait (also: dock, home)",
  "test      put dirt markers on the 8 corners",
  "clear     pick the markers back up",
  "reboot    reboot + update him at the next dock visit",
  "layer N   show layer N on the map (follow = back)",
  "ext       show the edge walls on the map",
  "zoom N    blocks per pixel on the map (fit = all)",
  "status / map / side / bill / corners / log",
  "refresh   ask Weaver for his plan again",
  "Keys: Tab = next tab, arrows pan/scroll, PgUp/PgDn",
  "layers or pages, mouse wheel zooms the map.",
}
local function drawHelp()
  for i, l in ipairs(HELP) do put(2, TOP + i - 1, l, i <= 10 and colors.white or colors.lightGray) end
  put(2, BOT, "Any key or click closes this.", colors.gray)
end

---------------------------------------------------------------------------
-- Draw everything
---------------------------------------------------------------------------
local function draw()
  ui.hits = {}
  term.setCursorBlink(false)
  drawHeader()
  for y = TOP, BOT do clearRow(y) end
  if ui.help then drawHelp()
  elseif ui.tab == "status" then drawStatus()
  elseif ui.tab == "map" then drawMap()
  elseif ui.tab == "side" then drawSide()
  elseif ui.tab == "bill" then drawBill()
  elseif ui.tab == "corners" then drawCorners()
  elseif ui.tab == "log" then drawLog() end
  drawFooter()
  pcall(drawMonitor)
  term.setCursorPos(math.min(W, 3 + #ui.input), H)
  term.setTextColour(colors.white); term.setBackgroundColour(colors.gray)
  term.setCursorBlink(true)
end

---------------------------------------------------------------------------
-- Commands and input
---------------------------------------------------------------------------
local ZOOMS = { 4, 2, 1, 0.5 }
local function zoomStep(dir)
  if not st.info then return end
  local cur = zoomNow()
  local list = { fitZoom() }
  for _, z in ipairs(ZOOMS) do if z < fitZoom() then list[#list + 1] = z end end
  local best = 1
  for i, z in ipairs(list) do if math.abs(z - cur) < math.abs(list[best] - cur) then best = i end end
  best = math.max(1, math.min(#list, best + dir))
  ui.zoom = best == 1 and nil or list[best]
  if not ui.zoom then ui.vx, ui.vz = nil, nil end
end

local function setLayer(n)
  local max = st.info and st.info.layers or (st.status and st.status.layers) or 1
  n = math.max(1, math.min(max, n))
  ui.layer, ui.ext = n, false
  askLayer(n)
end

local function pan(dx, dz)
  if not st.info then return end
  local x, z = viewCentre()
  local step = zoomNow() * 8
  ui.vx, ui.vz = x + dx * step, z + dz * step
  ui.follow = false
end

local function run(line)
  local words = {}
  for w in line:lower():gmatch("%S+") do words[#words + 1] = w end
  local c, a = words[1], words[2]
  if not c then return end
  if WANTS[c] then sendOrder(c)
  elseif c == "reboot" then sendReboot()
  elseif c == "layer" or c == "l" then
    if tonumber(a) then setLayer(tonumber(a)); ui.tab = "map"
    else ui.layer, ui.ext, ui.follow = nil, nil, true; ui.tab = "map" end
  elseif c == "follow" then ui.layer, ui.ext, ui.follow, ui.vx, ui.vz = nil, nil, true, nil, nil; ui.tab = "map"
  elseif c == "ext" then ui.ext = not showingExt(); ui.tab = "map"
  elseif c == "zoom" then
    if a == "fit" or not tonumber(a) then ui.zoom, ui.vx, ui.vz = nil, nil, nil
    else ui.zoom = math.max(0.25, tonumber(a)) end
    ui.tab = "map"
  elseif c == "refresh" then st.info = nil; st.layers = {}; askInfo(); notice("Asked Weaver for his plan.")
  elseif c == "help" or c == "?" then ui.help = true
  else
    for _, t in ipairs(TABS) do
      if t[1] == c or t[2]:lower() == c then ui.tab = t[1]; return end
    end
    notice("Don't know \"" .. c .. "\". Type help.")
  end
end

local function act(action)
  local kind, arg = action:match("^(%w+):?(.*)$")
  if kind == "tab" then ui.tab = arg; ui.help = false
  elseif kind == "cmd" then run(arg)
  elseif kind == "zoom" then
    if arg == "in" then zoomStep(1) elseif arg == "out" then zoomStep(-1)
    else ui.zoom, ui.vx, ui.vz = nil, nil, nil end
  elseif kind == "layer" then setLayer(viewLayer() + tonumber(arg))
  elseif kind == "follow" then run("follow")
  elseif kind == "ext" then ui.ext = not showingExt()
  elseif kind == "axis" then ui.axis = ui.axis == "x" and "z" or "x" end
end

local function onEvent(e)
  local ev = e[1]
  if ev == "rednet_message" then onMessage(e[2], e[3], e[4])
  elseif ev == "peripheral" or ev == "peripheral_detach" or ev == "monitor_resize" then pcall(syncMonitor)
  elseif ev == "mouse_click" then
    if ui.help then ui.help = false; return end
    for _, h in ipairs(ui.hits) do
      if e[4] == h.y and e[3] >= h.x1 and e[3] <= h.x2 then act(h.action); return end
    end
  elseif ev == "mouse_scroll" then
    if ui.tab == "map" then zoomStep(-e[2])
    elseif ui.tab == "bill" then ui.scroll.bill = ui.scroll.bill + e[2]
    elseif ui.tab == "log" then ui.scroll.log = ui.scroll.log - e[2] end
  elseif ev == "char" then
    if ui.help then ui.help = false end
    if #ui.input < W - 4 then ui.input = ui.input .. e[2] end
  elseif ev == "paste" then
    ui.input = (ui.input .. e[2]):sub(1, W - 4)
  elseif ev == "key" then
    local k = e[2]
    if ui.help and k ~= keys.leftShift and k ~= keys.rightShift then ui.help = false; return end
    if k == keys.enter or k == keys.numPadEnter then
      local l = ui.input; ui.input = ""; run(l)
    elseif k == keys.backspace then ui.input = ui.input:sub(1, -2)
    elseif k == keys.tab then
      for i, t in ipairs(TABS) do
        if t[1] == ui.tab then ui.tab = TABS[i % #TABS + 1][1]; break end
      end
    elseif #ui.input == 0 then
      if ui.tab == "map" then
        if k == keys.left then pan(-1, 0) elseif k == keys.right then pan(1, 0)
        elseif k == keys.up then pan(0, -1) elseif k == keys.down then pan(0, 1)
        elseif k == keys.pageUp then setLayer(viewLayer() + 1)
        elseif k == keys.pageDown then setLayer(viewLayer() - 1) end
      elseif ui.tab == "bill" then
        if k == keys.up then ui.scroll.bill = ui.scroll.bill - 1 elseif k == keys.down then ui.scroll.bill = ui.scroll.bill + 1
        elseif k == keys.pageUp then ui.scroll.bill = ui.scroll.bill - 10 elseif k == keys.pageDown then ui.scroll.bill = ui.scroll.bill + 10 end
      elseif ui.tab == "log" then
        if k == keys.up then ui.scroll.log = ui.scroll.log + 1 elseif k == keys.down then ui.scroll.log = ui.scroll.log - 1
        elseif k == keys.pageUp then ui.scroll.log = ui.scroll.log + 10 elseif k == keys.pageDown then ui.scroll.log = ui.scroll.log - 10 end
      elseif ui.tab == "side" and (k == keys.left or k == keys.right) then ui.axis = ui.axis == "x" and "z" or "x" end
    end
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
local A = { st = st, ui = ui, draw = draw, onEvent = onEvent, pump = pump, run = run, log = log }
if _G.ARCHITECT_TEST then return A end

if not fs.exists("startup.lua") then
  local f = fs.open("startup.lua", "w"); f.write('shell.run("architect")\n'); f.close()
end
loadLog()
pcall(syncMonitor)
addLog("Architect started")
if hasModem then askInfo() end
local tick = os.startTimer(0.5)
draw()
while true do
  local e = { os.pullEventRaw() }
  if e[1] == "terminate" then
    term.setBackgroundColour(colors.black); term.clear(); term.setCursorPos(1, 1)
    print("Architect stopped.")
    return
  end
  if e[1] == "timer" and e[2] == tick then
    tick = os.startTimer(0.5)
    pump()
    draw()
  else
    local ok, err = pcall(onEvent, e)
    if not ok then notice("Error: " .. tostring(err)) end
    if e[1] ~= "rednet_message" or e[4] == PROTOCOL then draw() end
  end
end
