-- miner_panel.lua  --  touch panel for the mining turtle (runs on the base computer)
--
-- Needs: an advanced monitor (1x3 or 3x2) and a wireless or ender modem on the base computer.
-- Pick a target range, press START. STOP sends the turtle home to its dock.
-- The panel keeps repeating the current order, so the turtle picks it up as soon as it's in range.

local PROTOCOL   = "tanis-miner"
local CONFIG     = "miner_panel.cfg"
local SEND_EVERY = 3     -- seconds between order broadcasts
local STALE      = 15    -- seconds without news before the status greys out
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
-- Config: the current order (want/minY/maxY/seq) and the range being edited (pMin/pMax)
---------------------------------------------------------------------------
local cfg = { want = "dock", minY = -59, maxY = -58, seq = 0, pMin = -59, pMax = -58 }
local function loadCfg()
  if fs.exists(CONFIG) then
    local f = fs.open(CONFIG, "r")
    local t = textutils.unserialize(f.readAll())
    f.close()
    if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
  end
end
local function saveCfg()
  local f = fs.open(CONFIG, "w")
  f.write(textutils.serialize(cfg))
  f.close()
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local mon = peripheral.find("monitor")
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
local status, lastSeen = nil, nil
local sendNow = true

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

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local K = colours
local STATES = {
  mining    = { "MINING", K.lime },
  returning = { "RETURNING", K.yellow },
  docked    = { "DOCKED", K.lightBlue },
  waiting   = { "WAITING", K.orange },
  error     = { "ERROR", K.red },
  lost      = { "LOST", K.red },
}

local hits = {}
local function hit(x1, y1, x2, y2, fn) hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn } end

local function at(x, y, text, fg, bg)
  mon.setCursorPos(x, y)
  mon.setBackgroundColour(bg or K.black)
  mon.setTextColour(fg or K.white)
  mon.write(text)
end
local function pad(s, w)
  s = tostring(s)
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
local function button(x, y, w, rows, label, bg, fn)
  for r = 0, rows - 1 do at(x, y + r, (" "):rep(w), K.black, bg) end
  label = label:sub(1, w)
  at(x + math.floor((w - #label) / 2), y + math.floor(rows / 2), label, K.black, bg)
  hit(x, y, x + w - 1, y + rows - 1, fn)
end

local function drawStatus(x, y, w)
  local s = status
  local ago = lastSeen and math.floor(os.clock() - lastSeen) or nil
  local label, colour
  if not s then
    label, colour = "NO SIGNAL", K.grey
  else
    local m = STATES[s.state] or { tostring(s.state or "?"):upper(), K.white }
    label, colour = m[1], m[2]
    if ago and ago > STALE then colour = K.grey end
  end
  at(x, y, pad(label, w), colour)
  local msg = s and s.msg or (modem and "Waiting for the turtle" or "No wireless modem!")
  at(x, y + 1, pad(msg, w), K.lightGrey)
  at(x, y + 2, pad(s and ("Seen " .. fmtAgo(ago) .. " ago") or "", w), K.grey)

  local f, l = s and s.fuel, s and s.fuelLimit
  local frac = (type(f) == "number" and type(l) == "number" and l > 0) and f / l or 1
  lr(x, y + 4, w, "Fuel", type(f) == "number" and fmtNum(f) or (f or "-"))
  bar(x, y + 5, w, s and frac or 0, frac < 0.2 and K.red or K.lime)
  lr(x, y + 6, w, "Cargo", s and (s.slots .. "/16") or "-")
  bar(x, y + 7, w, s and (s.slots / 16) or 0, (s and s.slots >= 14) and K.orange or K.lightBlue)
  lr(x, y + 8, w, "Y " .. tostring(s and s.y or "-"),
    "L " .. tostring(s and s.layer or "-") .. "/" .. tostring(s and s.layers or "-"))
  lr(x, y + 9, w, "Ring", s and s.ring and (s.ring .. "/" .. (s.maxRing or 50)) or "-")
  lr(x, y + 10, w, "Range", s and s.minY and (s.minY .. ".." .. s.maxY) or "-")
  return y + 11
end

local function adjust(key, d)
  cfg[key] = math.max(-63, math.min(319, cfg[key] + d))
  if cfg.pMin > cfg.pMax then
    if key == "pMin" then cfg.pMax = cfg.pMin else cfg.pMin = cfg.pMax end
  end
end

local function order(want)
  cfg.want = want
  if want == "run" then cfg.minY, cfg.maxY = cfg.pMin, cfg.pMax end
  cfg.seq = os.epoch("utc") -- unique id for this order
  sendNow = true
end

local function drawControls(x, y, w)
  at(x, y, pad("TARGET", w), K.grey)
  y = y + 1
  for _, p in ipairs(PRESETS) do
    local sel = cfg.pMin == p[2] and cfg.pMax == p[3]
    local bg, fg = sel and K.cyan or K.black, sel and K.black or K.white
    at(x, y, (" "):rep(w), fg, bg)
    at(x + 1, y, p[1]:sub(1, w - 2), fg, bg)
    if w >= 20 then
      local r = p[2] .. ".." .. p[3]
      at(x + w - #r - 1, y, r, sel and K.black or K.lightGrey, bg)
    end
    hit(x, y, x + w - 1, y, function() cfg.pMin, cfg.pMax = p[2], p[3] end)
    y = y + 1
  end
  for _, row in ipairs({ { "Min", "pMin" }, { "Max", "pMax" } }) do
    at(x, y, pad(row[1] .. " " .. cfg[row[2]], w), K.white)
    at(x + w - 7, y, " - ", K.white, K.grey)
    hit(x + w - 7, y, x + w - 5, y, function() adjust(row[2], -1) end)
    at(x + w - 3, y, " + ", K.white, K.grey)
    hit(x + w - 3, y, x + w - 1, y, function() adjust(row[2], 1) end)
    y = y + 1
  end
  local hint, hc = "", K.grey
  if status and status.seq ~= cfg.seq then hint, hc = "Sending...", K.yellow
  elseif status and status.want == "run" and (status.minY ~= cfg.pMin or status.maxY ~= cfg.pMax) then
    hint, hc = "START to switch", K.orange
  end
  at(x, y, pad(hint, w), hc)
  y = y + 1
  button(x, y, w, 3, "START", K.lime, function() order("run") end)
  y = y + 4
  button(x, y, w, 3, w >= 11 and "STOP + DOCK" or "STOP", K.red, function() order("dock") end)
  return y + 3
end

local function drawHaul(x, y, w, h)
  at(x, y, pad("LAST HAUL", w), K.grey)
  y = y + 1
  local haul = status and status.haul or {}
  if #haul == 0 then at(x, y, pad("Nothing yet", w), K.grey) end
  for _, e in ipairs(haul) do
    if y > h then break end
    lr(x, y, w, pretty(e[1]), fmtNum(e[2]), K.white, K.cyan)
    y = y + 1
  end
end

local function draw()
  if not mon then return end
  mon.setTextScale(TEXT_SCALE)
  local w, h = mon.getSize()
  hits = {}
  mon.setBackgroundColour(K.black); mon.clear()
  at(1, 1, (" "):rep(w), K.cyan, K.grey)
  at(2, 1, "MINER", K.cyan, K.grey)
  local name = status and (status.label or ("#" .. status.id)) or ""
  if #name > 0 and w > 12 then at(w - #name, 1, name:sub(1, w - 8), K.lightGrey, K.grey) end
  if w >= 40 then
    local cw = math.floor((w - 3) / 2)
    local y = drawStatus(2, 3, cw)
    drawHaul(2, y + 1, cw, h)
    drawControls(cw + 3, 3, w - cw - 3)
  else
    local y = drawStatus(1, 3, w)
    y = drawControls(1, y + 1, w)
    drawHaul(1, y + 1, w, h)
  end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function send()
  rednet.broadcast({
    type = "cmd", want = cfg.want, minY = cfg.minY, maxY = cfg.maxY, seq = cfg.seq,
    capped = _G.STORAGE_OVERCAP or {},
  }, PROTOCOL)
end

local function netLoop()
  if not modem then
    while true do draw(); os.sleep(5) end
  end
  rednet.open(peripheral.getName(modem))
  local lastSend = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "status" then
      status, lastSeen = msg, os.clock()
      _G.MINER_STATUS = msg -- storage sizes the fuel refill from it; alerts watch it
      _G.MINER_SEEN = lastSeen
    end
    if sendNow or os.clock() - lastSend >= SEND_EVERY then
      send(); lastSend = os.clock(); sendNow = false
    end
    draw()
  end
end

local function touchLoop()
  if not mon then return os.pullEvent("never") end
  while true do
    local _, _, x, y = os.pullEvent("monitor_touch")
    for _, r in ipairs(hits) do
      if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then
        r.fn()
        saveCfg()
        draw()
        break
      end
    end
  end
end

loadCfg()
if cfg.seq == 0 then cfg.seq = os.epoch("utc") end
draw()
parallel.waitForAny(netLoop, touchLoop)
