-- seagull.lua  --  Seagull, the map-painting turtle (CC:Tweaked + Advanced Peripherals, ATM10)
--
-- Seagull maps the world one REGION (16 x 16 chunks) at a time. He flies a few blocks above the ground to the
-- middle of each chunk of the region, one chunk after another, and scans it (one radius-8 scan from a chunk's
-- middle covers the whole chunk; a second scan only where a cliff or deep water left columns unseen). That builds
-- a height map: land, trees, shallow and deep water. He keeps the chunk he is scanning loaded himself with a chunk
-- controller (swapped onto his modem's side for a moment, see docs/systems/turtle.md), so nothing is skipped.
-- A finished region goes to the Cartographer computer in one piece; once it answers region_ok he forgets it and is
-- ready for the next. Protocol and fields: docs/systems/cartographer.md.
--
-- Needs: a turtle with a GEO SCANNER on one side and an ENDER (or wireless) MODEM on the other, and an Advanced
--        Peripherals CHUNK CONTROLLER in his bag. No pickaxe: he never digs, he flies over things. GPS towers.
-- Dock:  a barrel or chest touching him (any side, above or below) that storage keeps fuelled:
--        run /dock on the storage computer and pick it, or use the coal marker in /setup.
--        Open sky above the dock: he leaves and comes home straight up and down.
--
-- First start: put him next to his dock and start him. He finds the barrel, works out which way
-- he faces from GPS (he steps one block and back), remembers home, and waits.
-- Then press MAP on the Cartographer (or M on his own screen). He maps the next region (the one tapped on the
-- Cartographer, else the next one in a spiral out from home), comes home for fuel when he needs it, hands the
-- region over and docks. MAP again: the next region. Restarts: he asks GPS where he is and carries on with the
-- same region.
--
-- Settings: seagull.env (made on first run; same rules as the other .env files: edit live).
-- Map: seagull.map (his copy of the region he is on; the Cartographer keeps the whole map).

local mc = dofile("mapchunk.lua")
local plan = dofile("regionplan.lua")
local core = dofile("turtlecore.lua")   -- fuel, dock and GPS shared by every turtle (docs/systems/turtle.md)

local PROTO      = "tanis-carto"
local BASE       = "tanis-base"
local ENV_FILE   = "seagull.env"
local STATE_FILE = "seagull.state"
local MAP_FILE   = "seagull.map"
local ROLE       = "seagull"

local DEFAULTS = {
  { "REGION_CHUNKS", 16, "Chunks along one side of a region. Leave at 16: the Cartographer expects 16 x 16." },
  { "CLEARANCE", 3, "How high above the ground (or trees, water) he flies." },
  { "RADIUS", 8, "Scan radius. 8 is free and covers a whole chunk from its middle; up to 16 costs fuel per scan." },
  { "SHALLOW", 4, "Water this deep or less counts as shallow (lighter blue)." },
  { "FUEL_FULL", 8000, "Fuel he tops up to at the dock." },
  { "FUEL_RESERVE", 200, "Spare fuel kept on top of the trip home." },
  { "MAX_Y", 300, "He never flies higher than this; places that would need it are skipped." },
}

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
local E, envStamp = {}, nil
local function stampOf(path)
  if not fs.exists(path) or not fs.attributes then return nil end
  local ok, a = pcall(fs.attributes, path)
  return ok and a and (tostring(a.modified) .. ":" .. tostring(a.size)) or nil
end
local function readEnv()
  local vals = {}
  if fs.exists(ENV_FILE) then
    local f = fs.open(ENV_FILE, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then vals[k:upper()] = v end
    end
    f.close()
  end
  local missing = {}
  for _, d in ipairs(DEFAULTS) do
    if vals[d[1]] == nil then missing[#missing + 1] = d; vals[d[1]] = tostring(d[2]) end
  end
  if #missing > 0 then
    local new = not fs.exists(ENV_FILE)
    local f = fs.open(ENV_FILE, new and "w" or "a")
    if new then f.writeLine("# Seagull (cartographer) settings. Edit and save: picked up within a few seconds.") end
    for _, d in ipairs(missing) do
      f.writeLine(""); f.writeLine("# " .. d[3]); f.writeLine(d[1] .. "=" .. tostring(d[2]))
    end
    f.close()
  end
  for _, d in ipairs(DEFAULTS) do
    local v = vals[d[1]]
    if type(d[2]) == "number" then E[d[1]] = tonumber(v) or d[2] else E[d[1]] = v end
  end
  E.RADIUS = math.max(8, math.min(16, math.floor(E.RADIUS)))
  E.REGION_CHUNKS = math.max(1, math.floor(E.REGION_CHUNKS))
  envStamp = stampOf(ENV_FILE)
end
local function refreshEnv()
  if stampOf(ENV_FILE) ~= envStamp then readEnv() end
end

---------------------------------------------------------------------------
-- State (saved): home, dock side, facing, plan progress
---------------------------------------------------------------------------
local S = {}
local function save()
  local f = fs.open(STATE_FILE .. ".new", "w")
  f.write(textutils.serialize(S)); f.close()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
  fs.move(STATE_FILE .. ".new", STATE_FILE)
end
local function load()
  for _, p in ipairs({ STATE_FILE, STATE_FILE .. ".new" }) do
    if fs.exists(p) then
      local f = fs.open(p, "r"); local t = textutils.unserialize(f.readAll()); f.close()
      if type(t) == "table" then S = t; return end
    end
  end
end

-- Live (not saved)
local pos = nil          -- {x,y,z} absolute, nil until GPS answers
local heading = nil      -- 0 N, 1 E, 2 S, 3 W
local status, note = "starting", "Starting"
local ctrl = nil         -- latest order from the art wall
local lastScanAt = nil
local scanner = nil
local modem = nil

local COMPASS = { [0] = "north", "east", "south", "west" }
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }

local function setStatus(st, msg)
  status, note = st, msg or ""
  local w = term.getSize()
  local x, y = term.getCursorPos()
  term.setCursorPos(1, 1); term.clearLine()
  if term.isColour() then term.setTextColour(colours.cyan) end
  term.write(("SEAGULL  %s: %s"):format(st:upper(), note):sub(1, w))
  term.setTextColour(colours.white)
  term.setCursorPos(x, math.max(2, y))
end

local function log(text)
  local _, h = term.getSize()
  local _, y = term.getCursorPos()
  if y >= h then term.scroll(1); y = h - 1 end
  term.setCursorPos(1, math.max(2, y + 1))
  term.clearLine()
  term.write(text)
end

---------------------------------------------------------------------------
-- The map
---------------------------------------------------------------------------
local chunks = mc.load(MAP_FILE)    -- [key] = { rev, data }
local nav = {}                      -- ground seen outside the region he is on: only for flying, never sent or saved
local dirtyKeys = {}                -- chunks changed since the last broadcast
local inRegion                      -- (key, region) -> bool, defined with the plan below
local mapDirty, mapSavedAt = false, 0

local function now() return os.epoch("utc") end

local function chunkCount()
  local n = 0
  for _ in pairs(chunks) do n = n + 1 end
  return n
end

-- Height of the known top block at (x, z), or nil
local function topAt(x, z)
  local cx, cz, lx, lz = mc.locate(x, z)
  local k = mc.key(cx, cz)
  local c = chunks[k] or nav[k]
  if not c then return nil end
  return (mc.unpack(mc.get(c.data, lx, lz)))
end

local function saveMap(force)
  if not mapDirty then return end
  if not force and os.clock() - mapSavedAt < 30 then return end
  mc.save(MAP_FILE, chunks)
  mapDirty, mapSavedAt = false, os.clock()
end

local WATERY = { ["minecraft:water"] = true, ["minecraft:bubble_column"] = true, ["minecraft:kelp"] = true,
  ["minecraft:kelp_plant"] = true, ["minecraft:seagrass"] = true, ["minecraft:tall_seagrass"] = true }

local function isWater(name) return WATERY[name] == true end
local function isFoliage(name)
  return name:find("leaves") or name:find("_log$") or name:find("_wood$") or name:find("mushroom_block")
    or name:find("_stem$") or name:find("hyphae")
end
-- Things that sit on the ground without being the ground (grass tufts, flowers, snow layers...)
local function isFluff(b)
  if b.name:find("lava") then return false end
  local t = b.tags
  if type(t) == "table" and (t["minecraft:replaceable"] or t["minecraft:flowers"] or t["minecraft:small_flowers"]) then
    return true
  end
  local n = b.name
  return n:find("torch") ~= nil or n:find("carpet") ~= nil
end

local function round(v) return math.floor((tonumber(v) or 0) + 0.5) end

-- Turn one scan into column tops and write them into the map
local function absorb(blocks, ox, oy, oz, R)
  local cols = {}   -- [dx * 64 + dz] = { top, topName, floor (highest non-water below a water top) }
  for _, b in ipairs(blocks) do
    if type(b) == "table" and type(b.name) == "string" then
      local dx, dy, dz = round(b.x), round(b.y), round(b.z)
      if not (dx == 0 and dy == 0 and dz == 0) and not (b.name == "minecraft:air" or b.name:find("computercraft:turtle")) then
        local water = isWater(b.name)
        if water or not isFluff(b) then
          local k = (dx + 32) * 64 + (dz + 32)
          local c = cols[k]
          if not c then c = { dx = dx, dz = dz, blocks = {} }; cols[k] = c end
          c.blocks[#c.blocks + 1] = { dy, b.name, water }
          if not c.top or dy > c.top then c.top, c.topName, c.topWater = dy, b.name, water end
        end
      end
    end
  end
  local touched = {}
  local function setCol(x, z, v, forceIt)
    local cx, cz, lx, lz = mc.locate(x, z)
    local key = mc.key(cx, cz)
    local t = touched[key]
    if not t then
      -- Only the region he is mapping goes into the map; ground seen on the way is kept for flying only
      local mine = S.region ~= nil and inRegion(key, S.region)
      local c = (mine and chunks or nav)[key]
      t = { arr = mc.toArray(c and c.data), changed = false, mine = mine }
      touched[key] = t
    end
    local i = lz * 16 + lx + 1
    local old = t.arr[i]
    if not forceIt and old ~= 0 and v ~= 0 then
      -- Only a partial view (top may be cut off by the scan cube): never lower what we knew
      local oy = mc.unpack(old)
      local ny = mc.unpack(v)
      if oy and ny and oy > ny then return end
    end
    if old ~= v then t.arr[i] = v; t.changed = true end
  end
  for dx = -R, R do
    for dz = -R, R do
      local c = cols[(dx + 32) * 64 + (dz + 32)]
      local x, z = ox + dx, oz + dz
      if c then
        local kind = mc.LAND
        if c.topWater then
          local floor = nil
          for _, bl in ipairs(c.blocks) do
            if not bl[3] and bl[1] < c.top and (not floor or bl[1] > floor) then floor = bl[1] end
          end
          kind = (floor and c.top - floor <= E.SHALLOW) and mc.SHALLOW or mc.DEEP
        elseif isFoliage(c.topName) then
          kind = mc.FOLIAGE
        end
        -- The cube reaches R above us: a top at the very edge may continue higher
        setCol(x, z, mc.pack(oy + c.top, kind), c.top < R)
      end
    end
  end
  local t = now()
  for key, tt in pairs(touched) do
    if tt.changed then
      if tt.mine then
        chunks[key] = { rev = t, data = mc.fromArray(tt.arr) }
        dirtyKeys[key] = true
        mapDirty = true
      else
        nav[key] = { rev = t, data = mc.fromArray(tt.arr) }
      end
    end
  end
  local n = 0
  for _ in pairs(nav) do n = n + 1 end
  if n > 600 then nav = {} end
end

---------------------------------------------------------------------------
-- GPS, facing, movement
---------------------------------------------------------------------------
local gpsOk = false
local function locate(timeout)
  local ok, x, y, z, stale = core.gps.locate(timeout or 2)
  if ok and not stale then
    gpsOk = true
    return math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
  end
  gpsOk = false
end

local function dirOf(dx, dz)
  if dz < 0 then return 0 elseif dx > 0 then return 1 elseif dz > 0 then return 2 elseif dx < 0 then return 3 end
end

-- Step one free block (forward, turning, or up first if boxed in), read GPS, step back.
local function findHeading()
  local x0, y0, z0 = locate(3)
  if not x0 then return false end
  pos = { x = x0, y = y0, z = z0 }
  for attempt = 1, 2 do
    for turns = 0, 3 do
      if not turtle.detect() and turtle.forward() then
        local x1, _, z1 = locate(3)
        turtle.back()
        if x1 and (x1 ~= x0 or z1 ~= z0) then
          heading = dirOf(x1 - x0, z1 - z0)
          local x2, y2, z2 = locate(3)
          if x2 then pos = { x = x2, y = y2, z = z2 } end
          return true
        end
      end
      turtle.turnRight()
    end
    -- Boxed in on all four sides: go up one and try again
    if attempt == 1 then
      if turtle.up() then pos.y = pos.y + 1 else break end
    end
  end
  return false
end

local function turnTo(h)
  local d = (h - heading) % 4
  if d == 1 then turtle.turnRight() elseif d == 2 then turtle.turnRight(); turtle.turnRight()
  elseif d == 3 then turtle.turnLeft() end
  heading = h
end

local blockedWhy = nil
local function up()
  if turtle.up() then pos.y = pos.y + 1; return true end
  return false
end
local function down()
  if turtle.down() then pos.y = pos.y - 1; return true end
  return false
end
local function forward()
  local ok, why = turtle.forward()
  if ok then pos.x, pos.z = pos.x + DX[heading], pos.z + DZ[heading]; return true end
  blockedWhy = tostring(why or "")
  return false
end

-- Highest known top around (x, z), radius r
local function groundNear(x, z, r)
  local best = nil
  for dx = -r, r do
    for dz = -r, r do
      local t = topAt(x + dx, z + dz)
      if t and (not best or t > best) then best = t end
    end
  end
  return best
end

-- Fly one block towards compass direction h, keeping CLEARANCE above the ground ahead.
-- Returns true, or false + reason ("unloaded", "high", "stuck", "fuel")
local function hop(h)
  if turtle.getFuelLevel() == 0 then return false, "fuel" end
  local nx, nz = pos.x + DX[h], pos.z + DZ[h]
  local g = groundNear(nx, nz, 0)
  local want = g and (g + 1 + E.CLEARANCE) or pos.y
  if want > E.MAX_Y then return false, "high" end
  while pos.y < want do
    if not up() then break end
  end
  turnTo(h)
  for _ = 1, 24 do
    if forward() then
      -- Sink back down to the right height over lower ground (one block at a time, never into things)
      local g2 = groundNear(pos.x, pos.z, 0)
      local want2 = g2 and (g2 + 1 + E.CLEARANCE) or pos.y
      while pos.y > want2 and not turtle.detectDown() do
        if not down() then break end
      end
      return true
    end
    if blockedWhy:lower():find("loaded") then return false, "unloaded" end
    if pos.y >= E.MAX_Y or not up() then return false, "stuck" end
  end
  return false, "stuck"
end

-- Fly to column (tx, tz), long axis first. onHop is called after every block.
local function flyTo(tx, tz, onHop)
  local guard = 0
  while pos.x ~= tx or pos.z ~= tz do
    guard = guard + 1
    if guard > 4000 then return false, "stuck" end
    -- Keep going the way he faces while that still gets him closer (turning costs as much as a move)
    local h
    local keepX = (heading == 1 and tx > pos.x) or (heading == 3 and tx < pos.x)
    local keepZ = (heading == 2 and tz > pos.z) or (heading == 0 and tz < pos.z)
    if keepX or keepZ then h = heading
    elseif math.abs(tx - pos.x) >= math.abs(tz - pos.z) then h = tx > pos.x and 1 or 3
    else h = tz > pos.z and 2 or 0 end
    local ok, why = hop(h)
    if not ok then
      -- Try the other axis once before giving up (goes round a pylon or tree)
      local h2
      if h == 1 or h == 3 then h2 = (tz ~= pos.z) and (tz > pos.z and 2 or 0) or nil
      else h2 = (tx ~= pos.x) and (tx > pos.x and 1 or 3) or nil end
      if why == "stuck" and h2 then ok, why = hop(h2) end
      if not ok then return false, why end
    end
    if onHop then onHop() end
  end
  return true
end

---------------------------------------------------------------------------
-- Scanning
---------------------------------------------------------------------------
local function findScanner()
  scanner = peripheral.find("geo_scanner") or peripheral.find("geoScanner")
  return scanner
end

local function scan()
  if not scanner and not findScanner() then return false, "No Geo Scanner" end
  for _ = 1, 12 do
    local ok, res, err = pcall(scanner.scanBlocks, E.RADIUS)
    if ok and type(res) == "table" then
      absorb(res, pos.x, pos.y, pos.z, E.RADIUS)
      lastScanAt = { x = pos.x, y = pos.y, z = pos.z, r = E.RADIUS, t = now() }
      return true
    end
    local why = tostring(ok and err or res)
    if why:lower():find("fuel") then return false, "Scanner needs fuel: lower RADIUS to 8" end
    if not why:lower():find("cool") then
      -- Unknown problem: the peripheral may have gone away
      findScanner()
    end
    os.sleep(0.5)
  end
  return false, "Scanner keeps failing"
end

-- Scan, and if the ground under him is still out of sight (he climbed over a pylon, or he's never
-- been here), sink until a scan can see it. Without this he'd stay up high over unknown ground.
local function scanAndSettle()
  local ok, err = scan()
  if not ok then return false, err end
  local guard = 0
  while topAt(pos.x, pos.z) == nil and guard < 60 do
    guard = guard + 1
    local sank = 0
    while sank < E.RADIUS - 1 and pos.y > -60 and not turtle.detectDown() do
      if not down() then break end
      sank = sank + 1
    end
    ok, err = scan()
    if not ok then return false, err end
    if sank == 0 then break end   -- standing on something the scan doesn't count (a tuft): fine
  end
  return true
end

-- Scan whenever the last scan is a STEP behind: keeps the ground ahead known
local function scanIfDue()
  if not lastScanAt or math.abs(pos.x - lastScanAt.x) + math.abs(pos.z - lastScanAt.z) >= E.STEP
    or math.abs(pos.y - lastScanAt.y) > E.RADIUS then
    scanAndSettle()
  end
end

-- On the way home: only scan when the ground under him or a few blocks ahead isn't on the map yet
local function scanIfUnknown()
  local ahead = heading and topAt(pos.x + DX[heading] * 4, pos.z + DZ[heading] * 4)
  if topAt(pos.x, pos.z) == nil or ahead == nil then
    if not lastScanAt or math.abs(pos.x - lastScanAt.x) + math.abs(pos.z - lastScanAt.z) >= 4
      or math.abs(pos.y - lastScanAt.y) > E.RADIUS then
      scanAndSettle()
    end
  end
end

---------------------------------------------------------------------------
-- The plan: a region, chunk by chunk
---------------------------------------------------------------------------
local function regionKey(r) return r and plan.key(r[1], r[2]) end

-- Chunks of the region he is on, in scanning order (rebuilt on demand; 256 small tables)
local chunkList, chunkListFor = nil, nil
local function regionChunks()
  local k = regionKey(S.region) .. ":" .. E.REGION_CHUNKS
  if chunkListFor ~= k then
    chunkList, chunkListFor = plan.chunks(S.region[1], S.region[2], E.REGION_CHUNKS), k
  end
  return chunkList
end

inRegion = function(key, r)
  local cx, cz = mc.parseKey(key)
  if not cx then return false end
  local rx, rz = plan.regionOf(cx, cz, E.REGION_CHUNKS)
  return rx == r[1] and rz == r[2]
end

-- The region being scanned is withheld from the Cartographer until it is whole: it appears in one go
local function withheld(key)
  return S.region ~= nil and S.doneRegion == nil and inRegion(key, S.region)
end

-- Which region he maps next: the one tapped on the Cartographer, else the next unmapped one in the spiral from home
local function pickRegion()
  local nx = S.nextReg
  if type(nx) == "table" and tonumber(nx[1]) and tonumber(nx[2]) then return { nx[1], nx[2] }, true end
  local home = S.home or { x = 0, z = 0 }
  local hx, hz = plan.regionOf(math.floor(home.x / 16), math.floor(home.z / 16), E.REGION_CHUNKS)
  local rx, rz = plan.spiral(hx, hz, S.done or {})
  return rx and { rx, rz } or nil, false
end

---------------------------------------------------------------------------
-- Network: status, map pieces, orders
---------------------------------------------------------------------------
local function statusMsg()
  local scanSecs
  if S.region and S.rstart then
    local elapsed = (now() - S.rstart) / 1000
    local n = #regionChunks()
    if (S.ci or 1) > 4 then scanSecs = elapsed * n / ((S.ci or 1) - 1)
    elseif S.lastSecs then scanSecs = S.lastSecs end
  end
  return {
    type = "status", role = ROLE, id = os.getComputerID(), label = os.getComputerLabel(),
    state = status, msg = note, seq = S.seq, pos = pos and { x = pos.x, y = pos.y, z = pos.z } or nil,
    home = S.home, gps = gpsOk, fuel = turtle.getFuelLevel(), fuelLimit = turtle.getFuelLimit(),
    wp = S.region and (S.ci or 1) or nil, wps = S.region and #regionChunks() or nil, pass = S.pass or 0,
    mapping = S.mapping, chunks = chunkCount(), scan = lastScanAt, skipped = S.skipped,
    scan_region = S.mapping and S.region or nil, scan_started = S.mapping and S.rstart or nil, scan_secs = scanSecs,
    done_region = S.doneRegion, next_region = S.nextReg or nil,
  }
end

local function sendChunks(keys, to, more)
  local out, n = {}, 0
  for _, k in ipairs(keys) do
    local c = chunks[k]
    if c and not withheld(k) then out[k] = c; n = n + 1 end
  end
  if n == 0 then return end
  local msg = { type = "chunks", from = os.getComputerID(), chunks = out, more = more }
  if to then rednet.send(to, msg, PROTO) else rednet.broadcast(msg, PROTO) end
end

local okRegion = nil   -- "rx,rz" the Cartographer last confirmed (region_ok)

local function netLoop()
  modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then
    log("No ender/wireless modem: no map on the wall, no orders.")
    return os.pullEvent("never")
  end
  rednet.open(peripheral.getName(modem))
  local me = os.getComputerID()
  local lastStatus = -100
  while true do
    local from, msg
    if core.chunk.busy then os.sleep(0.2)   -- mid chunk swap: the modem is off for a moment
    else from, msg = rednet.receive(PROTO, 1) end
    if type(msg) == "table" then
      if msg.type == "cmd" and msg.to == me then
        ctrl = msg
      elseif msg.type == "region_ok" and msg.to == me and type(msg.region) == "table" then
        okRegion = regionKey({ tonumber(msg.region[1]), tonumber(msg.region[2]) })
      elseif msg.type == "have" and msg.to == me and type(msg.revs) == "table" then
        -- The art controller tells us what it has; send what it's missing (a batch at a time)
        local want = {}
        for k, c in pairs(chunks) do
          local r = tonumber(msg.revs[k])
          if not withheld(k) and (not r or r < (c.rev or 0)) then want[#want + 1] = k end
        end
        table.sort(want)
        local batch = {}
        for i = 1, math.min(24, #want) do batch[i] = want[i] end
        if #batch > 0 then sendChunks(batch, from, #want > #batch)
        else rednet.send(from, { type = "chunks", from = me, chunks = {}, more = false }, PROTO) end
      end
    end
    -- Fresh map pieces go out straight away (not the region he is still scanning)
    local keys = {}
    for k in pairs(dirtyKeys) do
      if not withheld(k) then keys[#keys + 1] = k; dirtyKeys[k] = nil end
    end
    if #keys > 0 then
      for i = 1, #keys, 12 do
        local part = {}
        for j = i, math.min(#keys, i + 11) do part[#part + 1] = keys[j] end
        sendChunks(part, nil, false)
      end
    end
    if os.clock() - lastStatus >= 3 and not core.chunk.busy then
      local st = statusMsg()
      rednet.broadcast(st, PROTO)
      local copy = {}
      for k, v in pairs(st) do copy[k] = v end
      copy.type = "carto"
      rednet.broadcast(copy, BASE)
      lastStatus = os.clock()
    end
  end
end

---------------------------------------------------------------------------
-- Dock: find it, refuel
---------------------------------------------------------------------------
local function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = tostring(d.name)
  return n:find("barrel") ~= nil or n:find("chest") ~= nil or n:find("drawer") ~= nil
end

-- Returns "up", "down" or a compass number
local function findDock()
  if isContainer(turtle.inspectUp()) then return "up" end
  if isContainer(turtle.inspectDown()) then return "down" end
  for _ = 1, 4 do
    if isContainer(turtle.inspect()) then return heading end
    turtle.turnRight(); heading = (heading + 1) % 4
  end
  return nil
end

local function suckDock(n)
  local d = S.dock
  if d == "up" then return turtle.suckUp(n) elseif d == "down" then return turtle.suckDown(n) end
  turnTo(d); return turtle.suck(n)
end
local function dropDock()
  local d = S.dock
  if d == "up" then return turtle.dropUp() elseif d == "down" then return turtle.dropDown() end
  turnTo(d); return turtle.drop()
end

local function fuelTarget()
  local limit = turtle.getFuelLimit()
  return math.min(E.FUEL_FULL, limit == "unlimited" and E.FUEL_FULL or limit)
end

-- Take fuel from the dock up to FUEL_FULL (lava first); the core hands back anything else, and the empty buckets.
local function refuel()
  local d = S.dock
  if d ~= "up" and d ~= "down" then turnTo(d) end
  core.fuel.refuelFromInventory(fuelTarget())
  core.fuel.refuelFromDock(d, fuelTarget())
end

-- Tell Storage where the dock is (core.dock.report), now and then
local function reportDock()
  local d = S.dock
  if not (S.home and d) then return end
  local x, y, z = S.home.x, S.home.y, S.home.z
  if d == "up" then y = y + 1 elseif d == "down" then y = y - 1 else x, z = x + DX[d], z + DZ[d] end
  core.dock.set({ x = x, y = y, z = z }, d)
  core.dock.maybeReport({ role = "cartographer" })
end

---------------------------------------------------------------------------
-- Trips
---------------------------------------------------------------------------
local function tripHome()
  if not S.home or not pos then return 0 end
  return math.abs(pos.x - S.home.x) + math.abs(pos.z - S.home.z) + math.abs(pos.y - S.home.y) + 40
end

local function atHome()
  return pos and S.home and pos.x == S.home.x and pos.z == S.home.z and pos.y == S.home.y
end

local function goHome()
  setStatus("returning", "Flying home")
  local ok, why = flyTo(S.home.x, S.home.z, scanIfUnknown)
  if not ok then return false, why end
  -- Straight down onto the dock spot (open sky above it, see the top of this file)
  while pos.y > S.home.y do
    if not down() then return false, "blocked above my dock" end
  end
  while pos.y < S.home.y do
    if not up() then return false, "can't get back up to my dock" end
  end
  return true
end

local function enoughFuelFor(tx, tz)
  if not pos then return true end
  local there = math.abs(tx - pos.x) + math.abs(tz - pos.z) + 2 * E.CLEARANCE + 20
  local back = math.abs(tx - S.home.x) + math.abs(tz - S.home.z) + math.abs(pos.y - S.home.y) + 40
  return turtle.getFuelLevel() >= there + back + E.FUEL_RESERVE
end

---------------------------------------------------------------------------
-- Orders
---------------------------------------------------------------------------
local queued = nil   -- an order typed on his own screen
local function takeOrder()
  if queued then local q = queued; queued = nil; return q end
  local c = ctrl
  if c and c.seq ~= S.seq then
    S.seq = c.seq
    if type(c.next) == "table" and tonumber(c.next[1]) and tonumber(c.next[2]) then
      S.nextReg = { math.floor(c.next[1]), math.floor(c.next[2]) }
    elseif c.next == false then
      S.nextReg = nil
    end
    save()
    return c.want
  end
end
local function orderWaiting() return queued ~= nil or (ctrl ~= nil and ctrl.seq ~= S.seq) end

-- Wait up to `secs`, or until an order comes in (it's left for the main loop to take)
local function waitOrder(secs)
  local t = os.startTimer(secs)
  while not orderWaiting() do
    local ev, p = os.pullEvent()
    if ev == "timer" and p == t then return end
    if ev == "char" then
      local k = p:lower()
      if k == "m" then queued = "map" elseif k == "d" then queued = "dock" end
    end
  end
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function dockAndRefuel(why)
  local ok, err = goHome()
  if not ok then setStatus("error", "Can't get home: " .. tostring(err)); return false end
  setStatus("docked", why or "Refuelling")
  refuel()
  reportDock()
  return true
end

-- Keep the chunk he is in loaded (chunk controller swap, only in a new chunk or every 45 s)
local function loadHere(force)
  if not S.chunky or not pos then return end
  core.chunk.ensure(math.floor(pos.x / 16) .. "," .. math.floor(pos.z / 16), force)
end

-- Save the map, then the place he got to: a reboot carries on from here
local function checkpoint()
  saveMap(true)
  S.cp = S.ci
  save()
end

local function startRegion()
  local r, tapped = pickRegion()
  if not r then setStatus("error", "No region left to map"); return end
  S.region, S.ci, S.cp, S.mapping, S.skipped, S.retry = r, 1, 1, true, 0, nil
  S.rstart, S.doneRegion = nil, nil
  if tapped then S.nextReg = nil end
  S.chunky = core.chunk.have()
  save()
end

-- The region is whole: name it to the Cartographer and wait for region_ok, then forget it
local function finishRegion()
  local r = S.region
  local rk = regionKey(r)
  S.mapping = false
  S.doneRegion = r
  saveMap(true); save()
  for k in pairs(chunks) do
    if inRegion(k, r) then dirtyKeys[k] = true end
  end
  if not atHome() then dockAndRefuel("Region done") end
end

local function forgetRegion()
  local r = S.doneRegion
  local rk = regionKey(r)
  for k in pairs(chunks) do
    if inRegion(k, r) then chunks[k] = nil; dirtyKeys[k] = nil end
  end
  S.done = S.done or {}
  S.done[rk] = true
  if S.rstart then S.lastSecs = (now() - S.rstart) / 1000 end
  S.region, S.doneRegion, S.rstart, S.ci, S.cp, S.retry = nil, nil, nil, nil, nil, nil
  S.pass = (S.pass or 0) + 1
  mapDirty = true
  saveMap(true); save()
  okRegion = nil
  setStatus("done", ("Region %s done and handed over: %d regions mapped"):format(rk, S.pass))
end

-- Scan the chunk he is over, and again from the middle of any quarter the first scan left unseen
local function scanChunk(cx, cz)
  local ok, err = scanAndSettle()
  if not ok then return false, err end
  local c = chunks[mc.key(cx, cz)]
  local extras = plan.extras(cx, cz, mc.toArray(c and c.data))
  for _, p in ipairs(extras) do
    if flyTo(p.x, p.z, loadHere) then
      local sok, serr = scanAndSettle()
      if not sok then return false, serr end
    end
  end
  return true
end

-- One chunk of the region: fly to its middle, keep it loaded, scan it
local function mapOneChunk()
  local list = regionChunks()
  local ch = list[S.ci]
  local tx, tz = plan.centre(ch.cx, ch.cz)
  if not enoughFuelFor(tx, tz) then
    if dockAndRefuel("Refuelling") then
      if not enoughFuelFor(tx, tz) then
        setStatus("waiting", "Waiting for fuel in my dock")
        waitOrder(30)
      end
    else
      waitOrder(30)
    end
    return
  end
  setStatus("mapping", ("Region %s, chunk %d/%d"):format(regionKey(S.region), S.ci, #list))
  loadHere(true)
  local ok, why = flyTo(tx, tz, loadHere)
  if ok then
    loadHere(true)
    if not S.rstart then S.rstart = now() end
    local sok, serr = scanChunk(ch.cx, ch.cz)
    if not sok then
      setStatus("error", serr)
      waitOrder(20)
      return
    end
    S.ci = S.ci + 1
    if S.ci % 8 == 0 then checkpoint() else save() end
  elseif why == "fuel" then
    setStatus("error", "Out of fuel")
    S.mapping = false
    save()
  elseif why == "unloaded" and (S.retry or 0) < 3 then
    S.retry = (S.retry or 0) + 1   -- a neighbouring chunk that is not loaded yet: wait, load mine again, retry
    os.sleep(1)
    loadHere(true)
  else
    S.skipped = (S.skipped or 0) + 1
    log(("Skipped chunk %d,%d (%s)"):format(ch.cx, ch.cz, why == "unloaded" and "chunk not loaded" or tostring(why)))
    S.retry = nil
    S.ci = S.ci + 1
    save()
  end
  if ok then S.retry = nil end
  saveMap(false)
end

local pushedAt = -100   -- last time the finished region was queued for sending again

local function mapLoop()
  while true do
    refreshEnv()
    local order = takeOrder()
    if order == "dock" then
      S.mapping = false; save()
      if not atHome() then dockAndRefuel("Docked (told to)") end
    elseif order == "map" then
      if S.doneRegion then
        setStatus("waiting", "Waiting for the Cartographer to take " .. regionKey(S.doneRegion))
      elseif not S.region then startRegion()
      else S.mapping = true; save() end   -- DOCK mid-region: MAP carries on with it
    end

    if S.doneRegion then
      -- Handed over, or about to be: wait for region_ok (and say it again now and then)
      if okRegion == regionKey(S.doneRegion) then forgetRegion()
      else
        if not atHome() then dockAndRefuel("Region done") end
        if status ~= "waiting" then setStatus("waiting", "Waiting for the Cartographer to take " .. regionKey(S.doneRegion)) end
        if os.clock() - pushedAt > 60 then
          pushedAt = os.clock()
          for k in pairs(chunks) do if inRegion(k, S.doneRegion) then dirtyKeys[k] = true end end
        end
        if atHome() and turtle.getFuelLevel() < math.min(E.FUEL_FULL, turtle.getFuelLimit()) then refuel() end
        reportDock()
        waitOrder(5)
      end
    elseif S.mapping and S.region then
      if S.ci > #regionChunks() then finishRegion()
      else mapOneChunk() end
    else
      if atHome() then
        if status ~= "done" and status ~= "error" then setStatus("docked", "Ready. MAP on the Cartographer (or M here)") end
        if turtle.getFuelLevel() < math.min(E.FUEL_FULL, turtle.getFuelLimit()) then refuel() end
        reportDock()
      elseif status ~= "error" then
        dockAndRefuel("Docked")
      end
      saveMap(true)
      waitOrder(10)
    end
  end
end

-- A new turtle has no fuel, and he needs a step to learn his facing: take a first fill from any
-- barrel touching him (whichever way he's facing), burning only fuel and handing the rest back.
local function bootFuel()
  if turtle.getFuelLevel() >= 200 then return end
  local function from(dir) if turtle.getFuelLevel() < 2000 then core.fuel.refuelFromDock(dir, 2000) end end
  if isContainer(turtle.inspectUp()) then from("up") end
  if isContainer(turtle.inspectDown()) then from("down") end
  for _ = 1, 4 do
    if turtle.getFuelLevel() >= 200 then break end
    if isContainer(turtle.inspect()) then from("front") end
    turtle.turnRight()
  end
end

local function boot()
  readEnv()
  load()
  term.clear(); term.setCursorPos(1, 2)
  print("Seagull the cartographer. M = map now, D = dock.")
  print("Hold Ctrl+T to stop him where he is.")
  if not findScanner() then
    setStatus("error", "No Geo Scanner: equip one on a side")
  end
  bootFuel()
  if core.chunk.restore() then log("Put my modem back on (a chunk swap was cut short).") end
  setStatus("starting", "Asking GPS where I am")
  while not findHeading() do
    setStatus("error", not gpsOk and "No GPS: I need the GPS towers"
      or turtle.getFuelLevel() == 0 and "No fuel: put coal in my dock barrel" or "Can't move to find my facing")
    bootFuel()
    os.sleep(10)
  end
  log(("At %d %d %d facing %s"):format(pos.x, pos.y, pos.z, COMPASS[heading]))
  if not S.home then
    local d = findDock()
    while d == nil do
      setStatus("error", "Put my dock barrel next to me (any side)")
      os.sleep(5)
      d = findDock()
    end
    S.dock = d
    S.home = { x = pos.x, y = pos.y, z = pos.z }
    S.seq = S.seq or 0
    save()
    log(("Home set at %d %d %d, dock %s"):format(pos.x, pos.y, pos.z, type(d) == "number" and COMPASS[d] or d))
  end
  if S.region and not S.doneRegion then
    S.ci = S.cp or 1   -- the map was saved at the checkpoint: carry on from there
    S.chunky = core.chunk.have()
  end
  if S.mapping then
    setStatus("mapping", "Carrying on where I left off")
  elseif atHome() then
    reportDock()
  end
end

if not fs.exists("startup.lua") then
  local f = fs.open("startup.lua", "w"); f.write('shell.run("seagull")\n'); f.close()
end

local function main()
  boot()
  mapLoop()
end

parallel.waitForAny(main, netLoop)
