-- farmhand.lua  --  the Farmhand: control screen for every farm turtle (Partridge, Woodpecker...)
--
-- Needs: an advanced computer with a wireless or ENDER modem (ender reaches farms anywhere) and an
-- advanced monitor touching it (any size; the computer's own screen works too, click with the mouse).
--
-- Laid out for any monitor; tuned for a 3 wide x 2 tall one (57x24 at text scale 0.5). The screens are built
-- from the UI kit (shared/ui.lua, ui_widgets.lua) in farmhand_screens.lua and farmhand_map.lua; this file is the
-- registry, the orders and the radio.
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
local REBOOT_WAIT = 600000 -- ms: give up on an unconfirmed reboot after this


---------------------------------------------------------------------------
-- Registry: every farm turtle seen, by computer ID
--   { label, role, want, seq, set = {KEY=value}, setSeq, reboot, rebootAt }
---------------------------------------------------------------------------
local cfg = { turtles = {} }
local function loadCfg()
  if fs.exists(CONFIG) then
    local f = fs.open(CONFIG, "r"); local t = textutils.unserialize(f.readAll() or ""); f.close()
    -- fill the one table in place: the screens keep a reference to it
    if type(t) == "table" and type(t.turtles) == "table" then
      for k in pairs(cfg) do cfg[k] = nil end
      for k, v in pairs(t) do cfg[k] = v end
    end
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

local function forget(id)
  cfg.turtles[id] = nil; live[id] = nil; maps[id] = nil
  saveCfg()
end

---------------------------------------------------------------------------
-- Who is who, and who needs you
---------------------------------------------------------------------------
local function nameOf(id)
  local l, t = live[id], cfg.turtles[id]
  return (l and l.s.label) or (t and t.label) or ("Turtle #" .. id)
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
-- Screens: the computer's own screen, plus a monitor if one touches it. Each view keeps its own page and tab.
---------------------------------------------------------------------------
local ui = require("ui")
local commandList = {}   -- filled once summary() exists (below)
local screens = require("farmhand_screens")({
  commands = commandList,
  cfg = cfg, live = live, maps = maps, SETTINGS = SETTINGS, STALE = STALE,
  order = order, requestReboot = requestReboot, changeSetting = changeSetting, settingValue = settingValue,
  forget = forget, nameOf = nameOf, ids = ids, problems = problems, radioOK = function() return radioOK end,
})

-- The monitor: the biggest one touching the computer, else one picked from the cable (shared/screens.lua,
-- docs/systems/screens.md). Asked once at boot; findMonitor only re-reads it.
local scr = require("screens").new({ slots = { { id = "wall", label = "the Farmhand screen", required = false, scale = 0.5 } } })
scr:open()
local function findMonitor() return scr:current("wall") end
local views = { ui.view(term.current()) }
local function syncMonitor()
  local mon, side = findMonitor()
  if views[2] and views[2].side == side then views[2].t = mon or views[2].t; views[2]:measure(); return end
  views[2] = mon and ui.view(mon, { side = side }) or nil
end
scr:get("wall")
syncMonitor()

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

-- Typed commands on the computer's own screen (docs/systems/ui.md)
local slash = require("slash")
local cmds = slash.new()
cmds:add({ name = "status", help = "turtles, what is working, who needs you", max = 0,
           run = function()
             local sum = summary()
             return true, sum.note, sum.problems > 0 and "warn" or "good"
           end })
cmds:add({ name = "monitors", help = "pick the monitor again (reboots)", max = 0,
           run = function() scr:repick("wall"); os.reboot() end })
for _, c in ipairs(cmds:commands()) do commandList[#commandList + 1] = c end

local function netLoop()
  local opened = 0
  radioOK = false
  peripheral.find("modem", function(name, m)
    rednet.open(name); opened = opened + 1
    if m.isWireless() then radioOK = true end
    return false
  end)
  if opened == 0 then
    ui.say("No modem! I need a wireless or ender modem to reach the farm turtles.", "bad")
    while true do os.sleep(60) end
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
        ui.say(nameOf(id) .. " is back up.", "good")
      end
    end
    if type(msg) == "table" and msg.type == "map" and cfg.turtles[tonumber(msg.id) or from] then
      maps[tonumber(msg.id) or from] = msg
    end
    -- Maps: fetched for the turtles on screen (overview tiles, or the one open), and again whenever
    -- a turtle says its map changed (it does during rounds, so the arrow and marks stay live)
    for mid in pairs(screens.wanted(views)) do
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
  end
end

loadCfg()
-- The kit draws after every event (a status from a turtle, a tap, a key) and once a second; a monitor that
-- comes or goes, or is resized, is picked up here.
parallel.waitForAny(netLoop, function()
  ui.run(views, screens.draw, { tick = 1, on_event = function(e, ...)
    scr:handle(e, ...)
    if e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" or e == "screens_changed" then syncMonitor() end
  end })
end)
