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
--        run /assign on the storage computer and add it as a Dock (then link it to him), or use the coal
--        marker in /setup. He fills to FUEL_PCT (90%) of his fuel limit there, waiting while Storage refills it.
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
local fly            -- how he flies (seagull_fly.lua), made below once the movement functions exist
local core = dofile("turtlecore.lua")   -- fuel, dock and GPS shared by every turtle (docs/systems/turtle.md)

local PROTO      = "tanis-carto"
local BASE       = "tanis-base"
local ENV_FILE   = "seagull.env"
local STATE_FILE = "seagull.state"
local MAP_FILE   = "seagull.map"
local PITS_FILE  = "seagull.pits"
local FLY_VERSION = 1      -- bumped when how he flies changes so much that his old map can't be trusted (see boot)
local ROLE       = "seagull"

local DEFAULTS = {
  { "REGION_CHUNKS", 16, "Chunks along one side of a region. Leave at 16: the Cartographer expects 16 x 16." },
  { "CLEARANCE", 3, "How high above the ground (or trees, water) he flies." },
  { "RADIUS", 8, "Scan radius. 8 is free and covers a whole chunk from its middle; up to 16 costs fuel per scan." },
  { "SHALLOW", 4, "Water this deep or less counts as shallow (lighter blue)." },
  { "FUEL_PCT", 90, "Fuel he tops up to at the dock, as % of his fuel limit (an advanced turtle holds 100,000)." },
  { "HANDOVER_WAIT", 120, "Seconds he hovers where he finished a region, waiting for the Cartographer to take it, before he goes home to wait." },
  { "DOCK_WAIT", 30, "Seconds he waits at the dock for Storage to bring more fuel before he goes with what he has." },
  { "FUEL_RESERVE", 200, "Spare fuel kept on top of the trip home." },
  { "MAX_Y", 300, "He never flies higher than this; places that would need it are skipped." },
  { "CRUISE_Y", 0, "Lowest Y he flies at between his dock and the region he maps (0 = off: CLEARANCE over the ground)." },
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

local function savePits()
  if not fly.pitsDirty then return end
  local f = fs.open(PITS_FILE .. ".new", "w")
  if not f then return end
  f.write(textutils.serialize(fly.pits)); f.close()
  if fs.exists(PITS_FILE) then fs.delete(PITS_FILE) end
  fs.move(PITS_FILE .. ".new", PITS_FILE)
  fly.pitsDirty = false
end

local function loadPits()
  for _, p in ipairs({ PITS_FILE, PITS_FILE .. ".new" }) do
    if fs.exists(p) then
      local f = fs.open(p, "r"); local t = textutils.unserialize(f.readAll()); f.close()
      if type(t) == "table" then fly.setPits(t); return end
    end
  end
  fly.setPits({})
end

local function saveMap(force)
  if not mapDirty and not fly.pitsDirty then return end
  if not force and os.clock() - mapSavedAt < 30 then return end
  if mapDirty then mc.save(MAP_FILE, chunks) end
  savePits()
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

-- Columns over a hole deeper than a scan reaches (ravine, sinkhole, cave mouth) are "pits" (seagull_fly.lua keeps
-- them, seagull.pits saves them with the map). He never sinks into one to look; the map says "low ground" there.

local function round(v) return math.floor((tonumber(v) or 0) + 0.5) end

-- Turn one scan into column tops and write them into the map
local function absorb(blocks, ox, oy, oz, R)
  -- Never map from underground: anything solid right over him (a cave, an overhang) and nothing is written
  fly.roofed = false
  for _, b in ipairs(blocks) do
    if type(b) == "table" and type(b.name) == "string" and round(b.x) == 0 and round(b.z) == 0 and round(b.y) > 0
      and b.name ~= "minecraft:air" and not isWater(b.name) and not isFluff(b) and not b.name:find("lava")
      and not b.name:find("computercraft:turtle") then
      fly.roofed = true
      return
    end
  end
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
  local seen = 0
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
        if c.top < R then fly.seeTop(x, z, oy + c.top) end      -- seen, with air above it in the cube
      end
    end
  end
  -- Some ground in the cube but not in these columns: they are a hole, not far-off ground. Mark them low (below the
  -- cube) and remember the height he flew over them at, so a second scan never sends him down to look.
  for _ in pairs(cols) do seen = seen + 1 end
  local mostly = seen > 0 and seen * 3 >= (2 * R + 1) ^ 2     -- ground nearly all round: holes in it are real holes
  fly.scanned(seen, mostly)
  if mostly then
    for dx = -R, R do
      for dz = -R, R do
        if not cols[(dx + 32) * 64 + (dz + 32)] and topAt(ox + dx, oz + dz) == nil then
          setCol(ox + dx, oz + dz, mc.pack(oy - R - 1, mc.LAND))
          fly.markPit(ox + dx, oz + dz)
        end
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
  -- Boxed in on all four sides (a launch tube): go up until a side is open, then back down to where he was
  local climbed, found = 0, false
  for _ = 1, 48 do
    for _ = 0, 3 do
      if not turtle.detect() and turtle.forward() then
        local x1, _, z1 = locate(3)
        turtle.back()
        if x1 and (x1 ~= x0 or z1 ~= z0) then heading = dirOf(x1 - x0, z1 - z0); found = true; break end
      end
      turtle.turnRight()
    end
    if found or not turtle.up() then break end
    climbed = climbed + 1
  end
  for _ = 1, climbed do turtle.down() end
  local x2, y2, z2 = locate(3)
  pos = x2 and { x = x2, y = y2, z = z2 } or { x = x0, y = y0, z = z0 }
  return found
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

-- He is either scanning (low, CLEARANCE over the ground: the hop to the next chunk, a second scan in a chunk)
-- or cruising (CRUISE_Y or higher: home, out to a region, back to his chunk after refuelling, a retried chunk).
-- flyTo sets `cruising` for each flight; once there he drops straight down to the ground to scan.
local cruising = false
local SCAN_HOP = 24          -- a flight this long or shorter between scans is part of scanning
local function floorAt(x, z)
  local c = tonumber(E.CRUISE_Y) or 0
  if c <= 0 or not cruising then return -math.huge end
  return math.min(c, E.MAX_Y)
end

-- How he flies: seagull_fly.lua (heights from the heightmap, down only onto seen ground, up when blocked)
local scan   -- defined with the scanning below
fly = dofile("seagull_fly.lua")({
  E = E,
  pos = function() return pos end,
  heading = function() return heading end,
  up = up, down = down,
  step = function(h) turnTo(h); return forward() end,
  blockedWhy = function() return blockedWhy end,
  detectDown = function() return turtle.detectDown() end,
  fuel = function() return turtle.getFuelLevel() end,
  floorAt = floorAt,
  mapTop = function(x, z) return topAt(x, z) end,
  scan = function() return scan() end,
  status = function() return status, note end,
  setStatus = setStatus,
})

-- Leaving the dock: straight up before any sideways move: to CRUISE_Y, or with no cruising height until he is
-- CLEARANCE above everything round him (a launch tube's walls; scanned on the way up, walls can reach past a scan).
local function launch()
  -- With a cruising height: straight up to it, no scanning (the sky over the dock is always open)
  local cruise = tonumber(E.CRUISE_Y) or 0
  if cruise > 0 then
    local top = math.min(cruise, E.MAX_Y)
    while pos.y < top do
      if turtle.getFuelLevel() == 0 then return false, "fuel" end
      if not up() then return false, "stuck" end
    end
    return true
  end
  -- Without one: up until he is CLEARANCE above the tube's walls (scanned on the way up)
  local scannedAt = nil
  for _ = 1, 400 do
    if scanner and (not scannedAt or pos.y - scannedAt >= math.floor(E.RADIUS / 2)) then
      scan(); scannedAt = pos.y
    end
    local walls = fly.groundNear(pos.x, pos.z, 1)
    local want = math.max(walls and (walls + 1 + E.CLEARANCE) or pos.y, floorAt(pos.x, pos.z))
    if want > E.MAX_Y then return false, "high" end
    if pos.y >= want then return true end
    if turtle.getFuelLevel() == 0 then return false, "fuel" end
    if not up() then return false, "stuck" end
  end
  return false, "stuck"
end

-- Fly to column (tx, tz), long axis first. onHop is called after every block. home = true: going home, always
-- cruising; otherwise cruising unless it is a short hop between scans (SCAN_HOP).
local flyTo1
local loadHere        -- defined below; every flight keeps his chunk loaded through it
local scanAndSettle   -- defined with the scanning below
local function flyTo(tx, tz, onHop, home)
  cruising = home or math.abs(tx - pos.x) + math.abs(tz - pos.z) > SCAN_HOP
  loadHere(true)
  local ok, why = flyTo1(tx, tz, onHop)
  cruising = false
  return ok, why
end
flyTo1 = function(tx, tz, onHop)
  if S.home and pos.x == S.home.x and pos.z == S.home.z and (pos.x ~= tx or pos.z ~= tz) then
    local ok, why = launch()
    if not ok then return false, why == "fuel" and "fuel" or "launch" end
  end
  local guard = 0
  local scanning = not cruising and scanner ~= nil   -- low flights between scans are part of scanning: look every RADIUS - 1
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
    local ok, why = fly.hop(h)       -- over what is ahead, never round or under it
    if not ok then return false, why end
    loadHere()
    if onHop then onHop() end
    if scanning and (not lastScanAt or math.abs(pos.x - lastScanAt.x) + math.abs(pos.z - lastScanAt.z) >= E.RADIUS - 1) then
      local sok, serr = scanAndSettle(false)
      if not sok then return false, serr end
    end
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

scan = function(radius)
  if not scanner and not findScanner() then return false, "No Geo Scanner" end
  local R = radius or E.RADIUS
  for _ = 1, 12 do
    local ok, res, err = pcall(scanner.scanBlocks, R)
    if ok and type(res) == "table" then
      absorb(res, pos.x, pos.y, pos.z, R)
      if not radius then lastScanAt = { x = pos.x, y = pos.y, z = pos.z, r = R, t = now() } end
      return true
    end
    local why = tostring(ok and err or res)
    if why:lower():find("fuel") then return false, "Scanner needs fuel: lower RADIUS to 8" end
    if radius then return false, why end   -- the wide scan is a bonus: no waiting
    if not why:lower():find("cool") then
      -- Unknown problem: the peripheral may have gone away
      findScanner()
    end
    os.sleep(0.5)
  end
  return false, "Scanner keeps failing"
end

-- Scan, get out from under a roof if the scan shows one, then settle: up to his flying height here, down only onto
-- ground a scan has seen (seagull_fly.lua).
-- drop = false: a scan on the way (he is already at his flying height); otherwise an arrival, where he may have to
-- come down from cruise.
scanAndSettle = function(drop)
  local ok, err = scan()
  if not ok then return false, err end
  ok, err = fly.openSky()
  if not ok then return false, err end
  return fly.settle(drop ~= false)
end

-- On the way home: only scan when the ground under him or a few blocks ahead isn't on the map yet
local function scanIfUnknown()
  local ahead = heading and topAt(pos.x + DX[heading] * 4, pos.z + DZ[heading] * 4)
  if topAt(pos.x, pos.z) == nil or ahead == nil then
    local every = floorAt(pos.x, pos.z) > -math.huge and E.RADIUS or 4   -- cruising: a scan sees RADIUS ahead
    if not lastScanAt or math.abs(pos.x - lastScanAt.x) + math.abs(pos.z - lastScanAt.z) >= every
      or math.abs(pos.y - lastScanAt.y) > E.RADIUS then
      scanAndSettle(false)
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
  local cn = S.corner or {}
  local k = regionKey(S.region) .. ":" .. E.REGION_CHUNKS .. ":" .. tostring(cn[1]) .. tostring(cn[2])
  if chunkListFor ~= k then
    chunkList, chunkListFor = plan.chunks(S.region[1], S.region[2], E.REGION_CHUNKS, cn[1], cn[2]), k
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
    wp = S.region and math.min(S.ci or 1, #regionChunks()) or nil, wps = S.region and #regionChunks() or nil, pass = S.pass or 0,
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

-- FUEL_PCT of his fuel limit (90% of an advanced turtle's 100,000 is 90 lava buckets: more than a dock holds)
local function fuelTarget()
  local limit = turtle.getFuelLimit()
  if limit == "unlimited" then return 0 end
  local pct = math.max(1, math.min(100, tonumber(E.FUEL_PCT) or 90))
  return math.floor(limit * pct / 100)
end
local function lowOnFuel() return turtle.getFuelLevel() < fuelTarget() end

-- Take fuel from the dock up to fuelTarget() (lava first); the core hands back anything else, and the empty
-- buckets. wait = true (he is about to set off): a dock holds less than he wants, so he stays while Storage keeps
-- refilling it, and leaves once he is full or no fuel has come for DOCK_WAIT seconds.
local function refuel(wait)
  local d = S.dock
  local target = fuelTarget()
  local function once()
    if d ~= "up" and d ~= "down" then turnTo(d) end
    core.fuel.refuelFromInventory(target)
    core.fuel.refuelFromDock(d, target)
  end
  once()
  if not wait then return end
  local last, lastGain = turtle.getFuelLevel(), os.clock()
  while turtle.getFuelLevel() < target and os.clock() - lastGain < (tonumber(E.DOCK_WAIT) or 30) do
    setStatus("docked", ("Refuelling %d / %d"):format(turtle.getFuelLevel(), target))
    sleep(3)
    once()
    local lvl = turtle.getFuelLevel()
    if lvl > last then last, lastGain = lvl, os.clock() end
  end
end

-- Tell Storage where the dock is (core.dock.report), now and then
local function reportDock()
  local d = S.dock
  if not (S.home and d) then return end
  local x, y, z = S.home.x, S.home.y, S.home.z
  if d == "up" then y = y + 1 elseif d == "down" then y = y - 1 else x, z = x + DX[d], z + DZ[d] end
  core.dock.set({ x = x, y = y, z = z }, d)
  local ack, why = core.dock.maybeReport({ role = "cartographer" })
  -- Say on his screen how it went (once per change), so a dock missing from Storage's /assign list can be traced
  local text
  if ack then
    text = ack.assigned and ("Storage has my dock (" .. ack.assigned .. ")")
      or ("Dock %d %d %d reported to Storage: link it in /assign, Dock line"):format(x, y, z)
  elseif why == "no answer" then
    text = "Storage didn't answer my dock report: is it on, with an ender modem? Trying again in 3 min"
  elseif why == "no modem" then
    text = "Dock report: no modem open"
  end
  if text and text ~= S.lastReportText then S.lastReportText = text; log(text) end
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
  local ok, why = flyTo(S.home.x, S.home.z, scanIfUnknown, true)
  local tries = 0
  while not ok and why == "unloaded" and tries < 3 do   -- a chunk on the way is not loaded yet: load mine, wait, go on
    tries = tries + 1
    loadHere(true)
    os.sleep(1)
    ok, why = flyTo(S.home.x, S.home.z, scanIfUnknown, true)
  end
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
  local cruise = tonumber(E.CRUISE_Y) or 0
  if cruise > 0 then         -- up to cruising height and back down, both ways
    local c = math.min(cruise, E.MAX_Y)
    back = back + 2 * math.max(0, c - math.min(pos.y, S.home.y))
    if math.abs(tx - pos.x) + math.abs(tz - pos.z) > SCAN_HOP then there = there + 2 * math.max(0, c - pos.y) end
  end
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
-- wait = true: he is going straight back out, so he stays while Storage refills the dock (see refuel)
local function dockAndRefuel(why, wait)
  local ok, err = goHome()
  if not ok then setStatus("error", "Can't get home: " .. tostring(err)); return false end
  setStatus("docked", why or "Refuelling")
  refuel(wait)
  reportDock()
  return true
end

-- Keep the chunk he is in loaded (chunk controller swap, only in a new chunk or every 45 s)
loadHere = function(force)
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
  S.region, S.ci, S.cp, S.mapping, S.skipped, S.retry, S.redo = r, 1, 1, true, 0, nil, nil
  -- Start at the region's corner nearest him (saved, so a reboot keeps the same order)
  local from = pos or S.home or { x = 0, z = 0 }
  local size = E.REGION_CHUNKS * 16
  local x0, z0 = r[1] * size, r[2] * size
  S.corner = { from.x >= x0 + size / 2, from.z >= z0 + size / 2 }
  S.rstart, S.doneRegion = nil, nil
  if tapped then S.nextReg = nil end
  S.chunky = core.chunk.have()
  save()
end

-- Set while he hovers where he finished a region, waiting for region_ok (os.clock when he began); nil otherwise
local handoverSince = nil

-- The region is whole: name it to the Cartographer and wait for region_ok, then forget it
local function finishRegion()
  local r = S.region
  local rk = regionKey(r)
  S.mapping = false
  S.doneRegion = { r[1], r[2] }      -- a copy: the state file can't hold the same table twice (textutils)
  saveMap(true); save()
  for k in pairs(chunks) do
    if inRegion(k, r) then dirtyKeys[k] = true end
  end
  -- He waits right here (radio works anywhere); mapLoop sends him home only if region_ok is slow
  handoverSince = (not atHome() and (tonumber(E.HANDOVER_WAIT) or 120) > 0) and os.clock() or nil   -- 0 = go home first
end

local function forgetRegion()
  local r = S.doneRegion
  local rk = regionKey(r)
  for k in pairs(chunks) do
    if inRegion(k, r) then chunks[k] = nil; dirtyKeys[k] = nil end
  end
  fly.dropPits(function(x, z)
    local cx, cz = mc.locate(x, z)
    return inRegion(mc.key(cx, cz), r)
  end)
  S.done = S.done or {}
  S.done[rk] = true
  if S.rstart then S.lastSecs = (now() - S.rstart) / 1000 end
  S.region, S.doneRegion, S.rstart, S.ci, S.cp, S.retry, S.redo, S.corner = nil, nil, nil, nil, nil, nil, nil, nil
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
    if flyTo(p.x, p.z) then
      local sok, serr = scanAndSettle()
      if not sok then return false, serr end
    end
  end
  return true
end

-- One chunk of the region: fly to its middle, keep it loaded, scan it
-- Chunks of the region that have no map yet (skipped on the first pass): each gets one more try at the end
local function missingChunks()
  local out = {}
  for _, ch in ipairs(regionChunks()) do
    if not chunks[mc.key(ch.cx, ch.cz)] then out[#out + 1] = { cx = ch.cx, cz = ch.cz } end
  end
  return out
end

-- The region is done once the first pass is over and every chunk has had its second try
local function regionPassDone()
  if S.ci <= #regionChunks() then return false end
  if not S.redo then S.redo = missingChunks(); save() end
  return #S.redo == 0
end

local function mapOneChunk()
  local list = regionChunks()
  local redo = S.ci > #list           -- second try at a chunk the first pass skipped
  local ch = redo and S.redo[1] or list[S.ci]
  local function nextChunk()
    if redo then table.remove(S.redo, 1) else S.ci = S.ci + 1 end
  end
  local tx, tz = plan.centre(ch.cx, ch.cz)
  if not enoughFuelFor(tx, tz) then
    if dockAndRefuel("Refuelling", true) then
      if not enoughFuelFor(tx, tz) then
        setStatus("waiting", "Waiting for fuel in my dock")
        waitOrder(30)
      end
    else
      waitOrder(30)
    end
    return
  end
  setStatus("mapping", redo and ("Region %s, a skipped chunk again (%d left)"):format(regionKey(S.region), #S.redo)
    or ("Region %s, chunk %d/%d"):format(regionKey(S.region), S.ci, #list))
  loadHere(true)
  local x0, y0, z0 = pos.x, pos.y, pos.z
  local ok, why = flyTo(tx, tz)
  if ok then
    loadHere(true)
    if not S.rstart then S.rstart = now() end
    local sok, serr = scanChunk(ch.cx, ch.cz)
    if not sok then
      setStatus("error", serr)
      waitOrder(20)
      return
    end
    if redo and (S.skipped or 0) > 0 then S.skipped = S.skipped - 1 end
    nextChunk()
    if redo or S.ci % 8 == 0 then checkpoint() else save() end
  elseif why == "fuel" then
    setStatus("error", "Out of fuel")
    S.mapping = false
    save()
  elseif why == "unloaded" and (S.retry or 0) < 3 then
    S.retry = (S.retry or 0) + 1   -- a neighbouring chunk that is not loaded yet: wait, load mine again, retry
    os.sleep(1)
    loadHere(true)
  elseif why == "launch" or (why ~= "high" and pos.x == x0 and pos.y == y0 and pos.z == z0) then
    -- He couldn't move at all (boxed in): that says nothing about the chunk, so don't skip it. Wait and try again.
    setStatus("error", why == "launch" and ("Can't climb straight up out of my dock at %d %d %d: is the sky open above it?"):format(pos.x, pos.y, pos.z)
      or ("Can't move from %d %d %d (%s): clear the way or reboot me"):format(pos.x, pos.y, pos.z, tostring(why)))
    waitOrder(30)
  else
    if not redo then S.skipped = (S.skipped or 0) + 1 end
    log(("Skipped chunk %d,%d (%s)%s"):format(ch.cx, ch.cz, why == "unloaded" and "chunk not loaded" or tostring(why),
      redo and ", again" or ": I'll try it again at the end"))
    S.retry = nil
    nextChunk()
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
      handoverSince = nil
      if not atHome() then dockAndRefuel("Docked (told to)") end
    elseif order == "map" then
      if S.doneRegion then
        setStatus("waiting", "Waiting for the Cartographer to take " .. regionKey(S.doneRegion))
      elseif not S.region then startRegion()
      else S.mapping = true; save() end   -- DOCK mid-region: MAP carries on with it
    end

    if S.doneRegion then
      -- Handed over, or about to be: wait for region_ok (and say it again now and then)
      if okRegion == regionKey(S.doneRegion) then
        local inPlace = handoverSince ~= nil
        handoverSince = nil
        forgetRegion()
        -- Handed over where he hovers: straight on to the next region (mapOneChunk goes home first if the fuel
        -- won't cover the trip out and back)
        if inPlace then startRegion() end
      elseif handoverSince and os.clock() - handoverSince <= (tonumber(E.HANDOVER_WAIT) or 120) then
        local msg = "Handing over " .. regionKey(S.doneRegion) .. " here"
        if status ~= "waiting" or note ~= msg then setStatus("waiting", msg) end
        loadHere()
        if os.clock() - pushedAt > 60 then
          pushedAt = os.clock()
          for k in pairs(chunks) do if inRegion(k, S.doneRegion) then dirtyKeys[k] = true end end
        end
        waitOrder(2)
      else
        handoverSince = nil
        if not atHome() then dockAndRefuel("Region done") end
        if status ~= "waiting" then setStatus("waiting", "Waiting for the Cartographer to take " .. regionKey(S.doneRegion)) end
        if os.clock() - pushedAt > 60 then
          pushedAt = os.clock()
          for k in pairs(chunks) do if inRegion(k, S.doneRegion) then dirtyKeys[k] = true end end
        end
        if atHome() and lowOnFuel() then refuel() end
        reportDock()
        waitOrder(5)
      end
    elseif S.mapping and S.region then
      if regionPassDone() then finishRegion()
      else mapOneChunk() end
    else
      if atHome() then
        if status ~= "done" and status ~= "error" then setStatus("docked", "Ready. MAP on the Cartographer (or M here)") end
        if lowOnFuel() then refuel() end
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
  loadPits()
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
  -- Rebooted under a roof (a cave)? Out to open sky before anything else
  if scanner and scan() then fly.openSky() end
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
  -- First boot of this way of flying (#114): the region he is on holds readings from cave trips, so it starts again
  if S.flyV ~= FLY_VERSION then
    S.flyV = FLY_VERSION
    if S.region and not S.doneRegion then
      local r = S.region
      for k in pairs(chunks) do
        if inRegion(k, r) then chunks[k] = nil; dirtyKeys[k] = nil end
      end
      fly.dropPits(function(x, z)
        local cx, cz = mc.locate(x, z)
        return inRegion(mc.key(cx, cz), r)
      end)
      S.ci, S.cp, S.redo, S.retry, S.skipped, S.rstart = 1, 1, nil, nil, 0, nil
      mapDirty = true
      saveMap(true)
      log(("New way of flying: region %s starts again at chunk 1"):format(regionKey(r)))
    end
    save()
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
