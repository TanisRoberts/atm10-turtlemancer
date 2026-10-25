-- cartographer.lua  --  the Cartographer: holds the whole world map and draws it on its own floor.
--
-- Needs: an advanced computer, an ender modem, and an advanced monitor touching it (laid flat as a floor: 8x6 is
-- 328 x 243 map pixels; any size works). Disk drives with floppies are optional: when the computer's own disk fills,
-- regions spill over to /disk, /disk2, ... and every mount is read as one map.
--
--   Seagull (turtle/seagull) finds the world region by region and sends the chunks; this computer keeps them
--   (computer/cartographer/carto_store.lua), asks for what it is missing, tells him when a finished region is safe
--   (region_ok), and sends him orders: MAP, DOCK, or "next region = x,z". The floor (carto_floor.lua) shows only the
--   map; the computer's screen (carto_screen.lua) has Seagull's panel, the next region, storage and the controls.
--   Spec: docs/design/cartographer.md.  Notes: docs/systems/cartographer.md.
--
-- Settings: cartographer.env.   Map: regions/<rx>_<rz>.map (and the same on every floppy).
local ui = require("ui")
local slash = require("slash")
local mc = require("mapchunk")
local envfile = require("envfile")
local R = require("carto_store")
local P = require("carto_paint")
local F = require("carto_floor")
local Screen = require("carto_screen")

local CARTO = "tanis-carto"
local BASE  = "tanis-base"
local ENV_FILE = "cartographer.env"

local env = envfile.new(ENV_FILE, "Cartographer settings.", {
  { "FLOOR_FILL", "false", "true = the floor is a static map table that fits everything explored (the FILL button sets this)." },
  { "FLOOR_ROTATE", 0, "Quarter turns for the floor, 0-3: which way the monitor's top points (0 north, 1 east, 2 south, 3 west)." },
  { "SAVE_EVERY", 30, "Seconds between saves of the regions that changed." },
  { "STALE", 30, "Seconds without news before Seagull shows as off the radio." },
  { "HIDE_AFTER", 900, "Seconds without news before a turtle disappears from the map." },
  { "RESERVE", 60000, "Bytes kept free on the computer's own disk before maps spill over to floppies." },
})
env.load()

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local store = R.new({ reserve = env.v.RESERVE })
local painter = P.painter(store)
local st = {
  view = { cx = 0, cz = 0, s = 1, fit = true },
  fill = env.v.FLOOR_FILL == "true", rot = tonumber(env.v.FLOOR_ROTATE) or 0,
  turtles = {}, pylons = {}, page = "main",
  seagull = nil, seagullId = nil, seagullSeen = nil,
  changed = {}, mapRev = 0,
}
local turtleInfo = {}       -- [id] = { label, role, pos, seen }
local ord = nil             -- the order waiting for Seagull to confirm { want, next, seq, untilT, sentAt }
local seq = math.floor(os.epoch("utc") / 1000) % 100000
local floor = nil
local lastOkSent = {}

local function sleepNow() os.sleep(0) end

local function say(text, tone) ui.say(text, tone) end

---------------------------------------------------------------------------
-- Settings: the FILL button writes its line back
---------------------------------------------------------------------------
local function setEnvLine(key, value)
  local lines, found = {}, false
  if fs.exists(ENV_FILE) then
    local f = fs.open(ENV_FILE, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      if line:match("^%s*" .. key .. "%s*=") then line = key .. "=" .. tostring(value); found = true end
      lines[#lines + 1] = line
    end
    f.close()
  end
  if not found then lines[#lines + 1] = key .. "=" .. tostring(value) end
  local f = fs.open(ENV_FILE, "w")
  f.write(table.concat(lines, "\n") .. "\n")
  f.close()
  env.load()
end

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
local function floorPane()
  if floor then return floor.pane end
  return P.pane({ PW = 312, PH = 243 }, painter, st.view)
end

-- Refit when the view follows what is explored
local lastBounds
local function refit(force)
  if not st.view.fit then return end
  local x0, z0, x1, z1 = store:bounds()
  local key = x0 and table.concat({ x0, z0, x1, z1 }, ",") or "none"
  if not force and key == lastBounds then return end
  lastBounds = key
  local v = x0 and floorPane():fit(x0, z0, x1, z1, 0.08) or { cx = 0, cz = 0, s = 1 }
  st.view.cx, st.view.cz, st.view.s = v.cx, v.cz, v.s
end

local function levelIndex(s)
  local best, bd = 1, 1e9
  for i, z in ipairs(P.ZOOMS) do if math.abs(z - s) < bd then best, bd = i, math.abs(z - s) end end
  return best
end

local act = {}
function act.zoom(dir)
  local i = math.max(1, math.min(#P.ZOOMS, levelIndex(st.view.s) + dir))
  st.view.s, st.view.fit = P.ZOOMS[i], false
end
function act.zoomTo(i) st.view.s, st.view.fit = P.ZOOMS[math.max(1, math.min(#P.ZOOMS, i))], false end
function act.centre(x, z) st.view.cx, st.view.cz, st.view.fit = math.floor(x), math.floor(z), false end
function act.pan(dx, dz)
  local w, h = floorPane():span(st.view)
  st.view.cx = math.floor(st.view.cx + dx * w / 2)
  st.view.cz = math.floor(st.view.cz + dz * h / 2)
  st.view.fit = false
end
function act.fit() st.view.fit = true; refit(true) end
function act.fill(on)
  st.fill = on and true or false
  setEnvLine("FLOOR_FILL", st.fill and "true" or "false")
  if floor then floor.key = nil end
  say(st.fill and "Floor: static table, fits everything explored." or "Floor: follows the computer's view again.", "good")
end

---------------------------------------------------------------------------
-- Regions, the spiral, the scan estimate
---------------------------------------------------------------------------
local function regionOfBlock(x, z) return R.regionOf(math.floor(x / 16), math.floor(z / 16)) end

local function homeRegion()
  local h = st.seagull and st.seagull.home
  if type(h) == "table" and tonumber(h.x) then return regionOfBlock(h.x, h.z) end
  return 0, 0
end

local function ringOf(rx, rz)
  local hx, hz = homeRegion()
  return math.max(math.abs(rx - hx), math.abs(rz - hz))
end

-- The next n regions nobody has mapped, in rings round home (nearest ring first, clockwise from north)
local function upcoming(n)
  local hx, hz = homeRegion()
  local out = {}
  local function open(rx, rz)
    if store:has(rx, rz) then return false end
    local sc = st.scan
    if sc and sc.rx == rx and sc.rz == rz then return false end
    if st.nextRegion and st.nextRegion.rx == rx and st.nextRegion.rz == rz then return false end
    return true
  end
  for r = 0, 40 do
    local cells = {}
    if r == 0 then cells[1] = { 0, 0 }
    else
      for dx = 0, r do cells[#cells + 1] = { dx, -r } end                  -- top edge, left to right from centre
      for dz = -r + 1, r do cells[#cells + 1] = { r, dz } end              -- right edge, down
      for dx = r - 1, -r, -1 do cells[#cells + 1] = { dx, r } end          -- bottom edge, right to left
      for dz = r - 1, -r, -1 do cells[#cells + 1] = { -r, dz } end         -- left edge, up
      for dx = -r + 1, -1 do cells[#cells + 1] = { dx, -r } end            -- top edge, back to centre
    end
    for _, c in ipairs(cells) do
      if open(hx + c[1], hz + c[2]) then
        out[#out + 1] = { hx + c[1], hz + c[2] }
        if #out >= n then return out end
      end
    end
  end
  return out
end

-- Seagull's scan: the region and, from his start time and the usual time per region, a percentage
local function updateScan()
  local sg = st.seagull
  st.scan, st.seagullRegion, st.seagullRing = nil, nil, nil
  if not sg then return end
  local rg = sg.scan_region
  local rx, rz
  if type(rg) == "table" then rx, rz = tonumber(rg[1] or rg.rx), tonumber(rg[2] or rg.rz) end
  if not rx and type(sg.pos) == "table" and tonumber(sg.pos.x) then rx, rz = regionOfBlock(sg.pos.x, sg.pos.z) end
  if rx then st.seagullRegion, st.seagullRing = { rx, rz }, ringOf(rx, rz) end
  if sg.state == "mapping" and rx then
    local pct
    local started, secs = tonumber(sg.scan_started), tonumber(sg.scan_secs)
    if started and secs and secs > 0 then
      if started > 1e11 then started = started / 1000 end
      pct = math.max(0, math.min(99, math.floor((os.epoch("utc") / 1000 - started) / secs * 100)))
    end
    st.scan = { rx = rx, rz = rz, pct = pct }
    if st.nextRegion and st.nextRegion.rx == rx and st.nextRegion.rz == rz then st.nextRegion = nil end
  end
end

---------------------------------------------------------------------------
-- Orders for Seagull
---------------------------------------------------------------------------
local function newOrder()
  seq = seq + 1
  if not ord then ord = {} end
  ord.seq, ord.untilT, ord.sentAt = seq, os.clock() + 30, -100
  return ord
end

function act.order(want)
  if not st.seagullId then say("No Seagull heard yet.", "warn"); return end
  newOrder().want = want
  say(want == "map" and "MAP sent: Seagull maps the next region." or "DOCK sent: Seagull flies home.", "good")
end

local function setNext(rx, rz)
  if not st.seagullId then say("No Seagull heard yet.", "warn"); return end
  st.nextRegion = rx and { rx = rx, rz = rz } or nil
  st.pick = nil
  newOrder().next = rx and { rx, rz } or false
  if rx then say(("Next: region %d,%d."):format(rx, rz), "good") else say("Next region cleared: back to the spiral.", "good") end
end
act.setNext = setNext

-- A tap on the computer's small map: ground that is mapped centres the view; an unmapped region needs two taps
function act.tapMap(wx, wz, rx, rz)
  if store:has(rx, rz) then act.centre(wx, wz); st.pick = nil; return end
  local pk = st.pick
  if pk and pk.rx == rx and pk.rz == rz and os.clock() - pk.t < 4 then
    setNext(rx, rz)
  else
    st.pick = { rx = rx, rz = rz, t = os.clock() }
    say(("Region %d,%d: tap again to map it next."):format(rx, rz), "plain")
  end
end

---------------------------------------------------------------------------
-- Typed commands (docs/systems/ui.md, shared/slash.lua)
---------------------------------------------------------------------------
local cmds = slash.new()
local function regionArg(a, i)
  local x, z = a:xz(i)
  return x, z
end
cmds:add({ name = "map", help = "Seagull maps the next region", max = 0, run = function() act.order("map"); return true, "MAP sent" end })
cmds:add({ name = "dock", help = "Seagull flies home", max = 0, run = function() act.order("dock"); return true, "DOCK sent" end })
cmds:add({ name = "next", args = "X,Z | clear", help = "map region X,Z next (region numbers)", min = 1, max = 2,
  run = function(a)
    if a:is(1, "clear") then setNext(nil); return true, "Next region cleared" end
    local x, z = regionArg(a, 1)
    if not x then return false, z end
    if store:complete(x, z) then return false, ("Region %d,%d is already mapped"):format(x, z) end
    setNext(x, z)
    return true, ("Next: region %d,%d"):format(x, z)
  end })
cmds:add({ name = "goto", args = "x z", help = "centre the map on a block", min = 2, max = 2,
  run = function(a)
    local x, z = a:xz(1)
    if not x then return false, z end
    act.centre(x, z)
    return true, ("Map centred on %d,%d"):format(x, z)
  end })
cmds:add({ name = "fit", help = "show everything explored", max = 0, run = function() act.fit(); return true, "Fitting everything" end })
cmds:add({ name = "fill", args = "on|off", help = "the floor as a static table", min = 1, max = 1,
  run = function(a)
    local w = a.words[1]:lower()
    if w ~= "on" and w ~= "off" then return false, "say on or off" end
    act.fill(w == "on")
    return true, "Fill " .. w
  end })
cmds:add({ name = "storage", help = "where the map lives and what is left", max = 0,
  run = function()
    local mounts, room = store:gauge()
    local parts = {}
    for i, m in ipairs(mounts) do
      parts[#parts + 1] = ("%s %d%%"):format(i == 1 and "disk" or m.name, m.capacity > 0 and math.floor(m.used / m.capacity * 100) or 0)
    end
    return true, table.concat(parts, ", ") .. (", room for ~%d regions"):format(room)
  end })
cmds:add({ name = "status", help = "regions, Seagull, what is next", max = 0,
  run = function()
    local sg = st.seagull
    local t = ("%d regions, %d chunks. "):format(store:regionCount(), store:count())
    if not sg then return true, t .. "No Seagull heard yet.", "warn" end
    t = t .. ("%s: %s"):format(tostring(sg.label or "Seagull"), tostring(sg.state or "?"))
    if st.scan then t = t .. (st.scan.pct and (" ~%d%%"):format(st.scan.pct) or " scanning") end
    return true, t
  end })
local sh = { store = store, painter = painter, st = st, act = act, cmds = cmds, upcoming = upcoming }
local screen = Screen.new(sh)
_G.CARTO_DEBUG = { st = st, store = store, sh = sh }   -- for the simulator scenarios

---------------------------------------------------------------------------
-- Monitors
---------------------------------------------------------------------------
local function findFloor()
  local best, bestSide, bestSize = nil, nil, -1
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then
      local m = peripheral.wrap(side)
      if m.isColour and m.isColour() then
        local w, h = m.getSize()
        if w * h > bestSize then best, bestSide, bestSize = m, side, w * h end
      end
    end
  end
  return best, bestSide
end

local function syncFloor()
  local m, side = findFloor()
  if not m then
    if floor then floor = nil end
    st.floorPx = nil
    return
  end
  if floor and floor.side == side then floor:resize(); return end
  floor = F.new(m, side, sh)
  sh.floorSide = side
  st.floorPx = { w = (floor.W - 8) * 2, h = floor.gfx.PH }
  refit(true)
end

local function refreshFloor()
  if not floor then return end
  local changed = st.changed
  st.changed = {}
  floor.pane.rot = (st.rot or 0) % 4
  st.floorPx = { w = (floor.W - 8) * 2, h = floor.gfx.PH }
  local ok, err = pcall(function() floor:refresh(changed); floor.gfx.flush() end)
  if not ok then
    st.err = "Floor error: " .. tostring(err)
    floor.key = nil
  end
end

---------------------------------------------------------------------------
-- Turtles on the map
---------------------------------------------------------------------------
local function short(label, id)
  local s = tostring(label or ("#" .. id))
  local d = s:match("^[Cc]anary%-(%d+)$")
  if d then return "C" .. d end
  return s:sub(1, 12)
end

local function noteTurtle(id, msg)
  if type(msg.pos) ~= "table" or not tonumber(msg.pos.x) then return end
  if msg.dim and not tostring(msg.dim):find("overworld") then turtleInfo[id] = nil; return end
  turtleInfo[id] = { label = msg.label, pos = { x = math.floor(msg.pos.x), y = math.floor(msg.pos.y or 64), z = math.floor(msg.pos.z) },
                     seen = os.clock(), short = short(msg.label, id) }
end

local function liveTurtles()
  local out = {}
  for id, t in pairs(turtleInfo) do
    if os.clock() - t.seen > env.v.HIDE_AFTER then turtleInfo[id] = nil else out[#out + 1] = t end
  end
  table.sort(out, function(a, b) return (a.label or "") < (b.label or "") end)
  return out
end

---------------------------------------------------------------------------
-- Radio
---------------------------------------------------------------------------
local function absorb(list)
  local n = 0
  for k, c in pairs(list or {}) do
    if type(c) == "table" and store:put(k, c.rev, c.data) then
      st.changed[k] = true
      if painter:note(k) then if floor then floor.key = nil end end
      n = n + 1
    end
  end
  if n > 0 then st.mapRev = st.mapRev + 1 end
  return n
end

-- A finished region Seagull names is safe once it is complete here and on disk: tell him he may drop it.
local function checkDone(msg, from)
  local dr = msg.done_region
  if type(dr) ~= "table" then return end
  local rx, rz = tonumber(dr[1] or dr.rx), tonumber(dr[2] or dr.rz)
  if not rx or not store:complete(rx, rz) then return end
  local rk = R.rkey(rx, rz)
  if store.dirty[rk] then store:save() end
  if store.dirty[rk] then st.err = "Can't save region " .. rk .. ": storage is full. Add a disk drive with a floppy."; return end
  if os.clock() - (lastOkSent[rk] or -100) > 3 then
    lastOkSent[rk] = os.clock()
    rednet.send(from, { type = "region_ok", to = from, region = { rx, rz } }, CARTO)
  end
end

local function netLoop()
  local opened = false
  peripheral.find("modem", function(name, m)
    if m.isWireless() then rednet.open(name); opened = true end
    return false
  end)
  if not opened then
    st.err = "No ender/wireless modem: I can't hear Seagull."
    return os.pullEvent("never")
  end
  local lastSync, syncMore, lastBase, lastSave = -1000, false, -100, os.clock()
  while true do
    local from, msg, proto = rednet.receive(nil, 0.5)
    if type(msg) == "table" and from then
      if proto == "tanis-miner" and msg.type == "status" then noteTurtle(from, msg)
      elseif proto == "tanis-farm" and msg.type == "status" then noteTurtle(from, msg)
      elseif proto == "tanis-rigger" and msg.type == "status" then noteTurtle(from, msg)
      elseif proto == CARTO then
        if msg.type == "status" then
          local first = st.seagullId == nil
          st.seagull, st.seagullId, st.seagullSeen = msg, from, os.clock()
          noteTurtle(from, msg)
          if first then lastSync = -1000 end
          if ord and msg.seq == ord.seq then ord = nil end
          updateScan()
          checkDone(msg, from)
        elseif msg.type == "chunks" and type(msg.chunks) == "table" then
          absorb(msg.chunks)
          if from == st.seagullId and msg.more then syncMore = true end
        end
      end
    end
    -- Catch up with Seagull's map (on start, then every few minutes, faster while he has more)
    if st.seagullId and (os.clock() - lastSync > 180 or (syncMore and os.clock() - lastSync > 0.2)) then
      rednet.send(st.seagullId, { type = "have", to = st.seagullId, revs = store.revs }, CARTO)
      lastSync, syncMore = os.clock(), false
    end
    -- Orders: repeat until his status shows he took it
    if ord then
      if os.clock() > ord.untilT then ord = nil
      elseif st.seagullId and os.clock() - ord.sentAt > 2 then
        rednet.send(st.seagullId, { type = "cmd", to = st.seagullId, want = ord.want, seq = ord.seq, next = ord.next }, CARTO)
        ord.sentAt = os.clock()
      end
    end
    if os.clock() - lastSave >= env.v.SAVE_EVERY then
      lastSave = os.clock()
      if next(store.dirty) then store:save() end
    end
    if os.clock() - lastBase >= 5 then
      lastBase = os.clock()
      local sg = st.seagull
      rednet.broadcast({ type = "cartographer", id = os.getComputerID(), label = os.getComputerLabel() or "Cartographer",
        regions = store:regionCount(), chunks = store:count(),
        seagull = sg and { label = sg.label, state = sg.state, msg = sg.msg, fuel = sg.fuel, wp = sg.wp, wps = sg.wps,
                           mapping = sg.mapping, heard = math.floor(os.clock() - (st.seagullSeen or 0)) } or nil,
        scan = st.scan and st.scan.pct }, BASE)
    end
  end
end

-- Ask every GPS host where it is: they are the pylons
local function pylonLoop()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then return os.pullEvent("never") end
  local reply = 64000 + os.getComputerID() % 1000
  while true do
    local found = {}
    modem.open(reply)
    modem.transmit(gps.CHANNEL_GPS, reply, "PING")
    local t = os.startTimer(2)
    while true do
      local e, side, ch, _, msg = os.pullEvent()
      if e == "timer" and side == t then break end
      if e == "modem_message" and ch == reply and type(msg) == "table" and #msg == 3
        and tonumber(msg[1]) and tonumber(msg[2]) and tonumber(msg[3]) then
        local x, y, z = math.floor(msg[1]), math.floor(msg[2]), math.floor(msg[3])
        found[x .. "," .. y .. "," .. z] = { x = x, y = y, z = z, seen = os.clock() }
      end
    end
    modem.close(reply)
    for k, p in pairs(found) do st.pylons[k] = p end
    for k, p in pairs(st.pylons) do if os.clock() - p.seen > 300 then st.pylons[k] = nil end end
    os.sleep(60)
  end
end

---------------------------------------------------------------------------
-- Screen loop
---------------------------------------------------------------------------
local view = ui.view(term.current())
P.apply(term.current())

local lastTick, lastGauge = -100, -100
local rescan = false
local function onEvent(e, a, b, c)
  if e == "disk" or e == "disk_eject" then rescan = true
  elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then syncFloor()
  elseif e == "monitor_touch" and floor and a == floor.side then
    local ok, err = pcall(floor.tap, floor, b, c)
    if not ok then st.err = "Tap error: " .. tostring(err) end
    refit(true)
    refreshFloor()
    lastTick = os.clock()
  elseif e == "key" and st.page == "main" and (not st.field or st.field.text == "") then
    local K = keys
    if a == K.left then act.pan(-1, 0) elseif a == K.right then act.pan(1, 0)
    elseif a == K.up then act.pan(0, -1) elseif a == K.down then act.pan(0, 1) end
  elseif e == "char" and st.page == "main" and (not st.field or st.field.text == "") then
    if a == "-" then act.zoom(1); st.stripNext = a
    elseif a == "+" or a == "=" then act.zoom(-1); st.stripNext = a
    elseif a == "f" then act.fit(); st.stripNext = a end
  end
  if st.err then ui.say(st.err, "bad"); st.err = nil end
  if rescan then
    rescan = false
    store:load(nil, true)
    st.mapRev = st.mapRev + 1
    if floor then floor.key = nil end
  end
  if os.clock() - lastGauge >= 5 then
    lastGauge = os.clock()
    st.gauge = { store:gauge() }
  end
  if os.clock() - lastTick >= 1 then
    lastTick = os.clock()
    st.turtles = liveTurtles()
    st.rot = tonumber(env.v.FLOOR_ROTATE) or 0
    if env.refresh() then st.fill = env.v.FLOOR_FILL == "true"; if floor then floor.key = nil end end
    refit(false)
    refreshFloor()
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
term.clear()
term.setCursorPos(1, 1)
print("CARTOGRAPHER: loading the map...")
store:load(sleepNow)
local n = 0
for k in pairs(store.chunks) do
  painter:note(k)
  n = n + 1
  if n % 100 == 0 then sleepNow() end
end
st.mapRev = 1
syncFloor()
if not floor then ui.say("No advanced monitor touching me: the floor is dark, this screen still works.", "warn") end
st.gauge = { store:gauge() }
refit(true)
parallel.waitForAny(netLoop, pylonLoop, function()
  ui.run({ view }, screen.draw, { tick = 1, on_event = onEvent })
end)
if floor then floor:close() end
if next(store.dirty) then store:save() end
