-- rigger.lua  --  plan-following builder turtle (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: a turtle with a diamond pickaxe (to clear kelp/sand in the way) and a wireless or
-- ender modem. A plan file (e.g. mossy.plan) on the turtle. A SUPPLY barrel next to the dock
-- that storage fills (marker: 1 brick in /setup).
--
-- Commands come from chat via the mainframe:  island rigger test | clear | build | stop | status
-- Or type them here:  rigger test  /  rigger build  /  rigger stop  /  rigger clear
--
-- How it builds:
--   1. Edge columns: walls under the island's outer edge, from your real seabed up to the plan.
--   2. Layers, bottom to top: flies one block above each layer and places blocks below him.
--      Cells that are already solid (your seabed, or blocks he placed before a restart) are skipped.
--   3. Whenever he's missing the next block or getting low on fuel, he flies home, asks storage
--      for the next batch, and carries on exactly where he stopped.

local PROTOCOL   = "tanis-rigger"
local STATE_FILE = "rigger.state"
local CFG_FILE   = "rigger.cfg"
local MARKER     = "minecraft:dirt" -- block used by "test" to mark the corners
local FUEL_TOPUP = 20000            -- fuel to top up to at every dock visit
local SLOTS_FOR_BLOCKS = 15         -- one slot kept free for junk/fuel

local args = { ... }

---------------------------------------------------------------------------
-- Config and state
---------------------------------------------------------------------------
local function readT(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  return type(t) == "table" and t or nil
end
local function writeT(path, t)
  local f = fs.open(path, "w"); f.write(textutils.serialize(t)); f.close()
end

local C = readT(CFG_FILE)   -- dock, build site, plan file
local S = readT(STATE_FILE) or {}
local function save() writeT(STATE_FILE, S) end

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------
local P -- { info, ext = {{x,z,ch}}, layers = { [n] = {{z,x0,rle}} } }

local function loadPlan(path)
  local f = fs.open(path, "r")
  if not f then error("Plan file not found: " .. tostring(path), 0) end
  local plan = { ext = {}, layers = {} }
  local section, cur
  while true do
    local line = f.readLine()
    if not line then break end
    if line:sub(1, 6) == "#info " then
      plan.info = textutils.unserialize(line:sub(7))
    elseif line == "#ext" then
      section = "ext"
    elseif line:sub(1, 3) == "#L " then
      section = "L"; cur = {}
      plan.layers[tonumber(line:sub(4))] = cur
    elseif line ~= "" then
      if section == "ext" then
        local x, z, ch = line:match("^(%-?%d+),(%-?%d+),(%a)$")
        plan.ext[#plan.ext + 1] = { tonumber(x), tonumber(z), ch }
      elseif section == "L" then
        local z, x0, rle = line:match("^(%-?%d+)|(%-?%d+)|(.+)$")
        cur[#cur + 1] = { tonumber(z), tonumber(x0), rle }
      end
    end
  end
  f.close()
  if not plan.info then error("Not a plan file: " .. path, 0) end
  return plan
end

-- Rotate plan x/z (clockwise steps of 90 degrees, seen from above) and move to the build site
local function toWorld(px, py, pz)
  local r = (C.rot or 0) % 360
  local x, z = px, pz
  if r == 90 then x, z = -pz, px elseif r == 180 then x, z = -px, -pz elseif r == 270 then x, z = pz, -px end
  return C.cx + x, C.sea + py, C.cz + z
end

-- Walk order: always go to the nearest unbuilt cell (follows the island's outline instead of
-- zig-zagging across the hollow middle). Deterministic, so a restart picks the same order.
local function nearestOrder(cells)
  if #cells < 3 then return cells end
  local grid = {}
  local function k(x, z) return x * 65536 + z end
  for i, c in ipairs(cells) do grid[k(c[1], c[2])] = i end
  local used, out = {}, {}
  local cur = 1
  for _ = 1, #cells do
    used[cur] = true
    out[#out + 1] = cells[cur]
    grid[k(cells[cur][1], cells[cur][2])] = nil
    local cx, cz = cells[cur][1], cells[cur][2]
    local best
    for r = 1, 4 do                       -- look in growing rings first (fast path)
      local bd = math.huge
      for dx = -r, r do
        for dz = -r, r do
          if math.max(math.abs(dx), math.abs(dz)) == r then
            local j = grid[k(cx + dx, cz + dz)]
            if j then
              local d = math.abs(dx) + math.abs(dz)
              if d < bd or (d == bd and j < best) then bd, best = d, j end
            end
          end
        end
      end
      if best then break end
    end
    if not best then                      -- nothing close: scan everything left
      local bd = math.huge
      for j, c in ipairs(cells) do
        if not used[j] then
          local d = math.abs(c[1] - cx) + math.abs(c[2] - cz)
          if d < bd then bd, best = d, j end
        end
      end
    end
    if not best then break end
    cur = best
  end
  return out
end

-- Ordered cell list for layer n
local cellCache = {}
local function layerCells(n)
  if cellCache.n == n then return cellCache.cells end
  local rows, cells = P.layers[n] or {}, {}
  local py = P.info.ybase + n - 1
  for ri, row in ipairs(rows) do
    local z, x, rowCells = row[1], row[2], {}
    for countStr, ch in row[3]:gmatch("(%d+)(.)") do
      local count = tonumber(countStr)
      if ch ~= "." then
        for i = 0, count - 1 do rowCells[#rowCells + 1] = { x + i, z, ch } end
      end
      x = x + count
    end
    if ri % 2 == 0 then
      for i = #rowCells, 1, -1 do cells[#cells + 1] = rowCells[i] end
    else
      for _, c in ipairs(rowCells) do cells[#cells + 1] = c end
    end
  end
  cells = nearestOrder(cells)
  for _, c in ipairs(cells) do c[4], c[5], c[6] = toWorld(c[1], py, c[2]) end
  cellCache = { n = n, cells = cells }
  return cells
end

local function bounds()
  local i = P.info
  local pts = {}
  for _, x in ipairs({ i.minX, i.maxX }) do
    for _, z in ipairs({ i.minZ, i.maxZ }) do
      local wx, _, wz = toWorld(x, 0, z)
      pts[#pts + 1] = { wx, wz }
    end
  end
  local b = { x1 = math.huge, x2 = -math.huge, z1 = math.huge, z2 = -math.huge }
  for _, p in ipairs(pts) do
    b.x1 = math.min(b.x1, p[1]); b.x2 = math.max(b.x2, p[1])
    b.z1 = math.min(b.z1, p[2]); b.z2 = math.max(b.z2, p[2])
  end
  b.y1 = C.sea + i.ybase
  b.y2 = C.sea + i.topY
  return b
end

local function inSite(x, z)
  local b = bounds()
  return x >= b.x1 - 2 and x <= b.x2 + 2 and z >= b.z1 - 2 and z <= b.z2 + 2
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
local lastShown = ""
local function setStatus(st, msg)
  S.status, S.msg = st, msg or ""
  local line = st .. (S.msg ~= "" and (": " .. S.msg) or "")
  if line ~= lastShown then
    lastShown = line
    print(("[%s] %s"):format(textutils.formatTime(os.time(), true), line))
    save()
  end
end

---------------------------------------------------------------------------
-- Movement in world coordinates. Heading: 0 north (-Z), 1 east (+X), 2 south (+Z), 3 west (-X)
---------------------------------------------------------------------------
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }

local function apply(kind)
  if kind == "f" then S.x, S.z = S.x + DX[S.h], S.z + DZ[S.h]
  elseif kind == "u" then S.y = S.y + 1
  else S.y = S.y - 1 end
end

local OPS = {
  f = { move = turtle.forward, dig = turtle.dig,     detect = turtle.detect,     inspect = turtle.inspect,     attack = turtle.attack },
  u = { move = turtle.up,      dig = turtle.digUp,   detect = turtle.detectUp,   inspect = turtle.inspectUp,   attack = turtle.attackUp },
  d = { move = turtle.down,    dig = turtle.digDown, detect = turtle.detectDown, inspect = turtle.inspectDown, attack = turtle.attackDown },
}

local NATURAL = { "kelp", "seagrass", "sea_pickle", "sand", "gravel", "clay", "dirt", "mud", "stone", "deepslate",
  "tuff", "andesite", "diorite", "granite", "coral", "magma_block", "snow", "ice", "grass" }
local PROTECTED = { "computer", "turtle", "chest", "barrel", "modem", "monitor", "shulker", "cable", "furnace" }

local function canDig(name, x, z)
  name = tostring(name)
  for _, p in ipairs(PROTECTED) do if name:find(p, 1, true) then return false end end
  if not inSite(x, z) then return false end -- never dig anything at the base
  for _, n in ipairs(NATURAL) do if name:find(n, 1, true) then return true end end
  return false
end

local JUNK_KEEP = {} -- filled with palette item names: never dropped
local function dropJunk()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not JUNK_KEEP[d.name] then
      turtle.select(s)
      if not turtle.refuel(0) then turtle.dropUp() end
    end
  end
  turtle.select(1)
end

-- One block of movement, clearing natural blocks inside the build site.
-- Returns false, reason if something unbreakable / protected is in the way.
local function move(kind)
  local op = OPS[kind]
  for _ = 1, 40 do
    if turtle.getFuelLevel() == 0 then return false, "Out of fuel" end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }
    save()
    if op.move() then
      apply(kind); S.pending = nil; save()
      return true
    end
    S.pending = nil
    local ok, d = op.inspect()
    if ok and d.name ~= "minecraft:water" and d.name ~= "minecraft:lava" then
      local tx, tz = S.x, S.z
      if kind == "f" then tx, tz = S.x + DX[S.h], S.z + DZ[S.h] end
      if not canDig(d.name, tx, tz) then save(); return false, "Blocked by " .. tostring(d.name) end
      op.dig(); dropJunk()
    else
      op.attack()
    end
  end
  save()
  return false, "Stuck"
end

local function turnRight() S.turning = true; save(); turtle.turnRight(); S.h = (S.h + 1) % 4; S.turning = nil; save() end
local function turnLeft()  S.turning = true; save(); turtle.turnLeft();  S.h = (S.h + 3) % 4; S.turning = nil; save() end
local function face(h)
  local d = (h - S.h) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end

local function walkX(tx)
  while S.x ~= tx do
    face(tx > S.x and 1 or 3)
    local ok, why = move("f"); if not ok then return false, why end
  end
  return true
end
local function walkZ(tz)
  while S.z ~= tz do
    face(tz > S.z and 2 or 0)
    local ok, why = move("f"); if not ok then return false, why end
  end
  return true
end
local function goY(ty)
  while S.y ~= ty do
    local ok, why = move(S.y < ty and "u" or "d"); if not ok then return false, why end
  end
  return true
end

-- Flat move at the current height; if blocked, climb over (up to 24 blocks) and keep going.
local function goXZ(tx, tz)
  for _ = 1, 24 do
    local ok = walkX(tx)
    if ok then ok = walkZ(tz) end
    if ok then return true end
    local up = move("u")
    if not up then return false, "Can't climb over an obstacle" end
  end
  return false, "Too many obstacles"
end

local function travelAlt(extraY)
  return math.max(C.cruise, S.y, extraY or -math.huge)
end

-- Safe trip to a point: up to cruise height, across, then straight down.
local function travel(tx, ty, tz)
  local alt = travelAlt(ty)
  local ok, why = goY(alt); if not ok then return false, why end
  ok, why = goXZ(tx, tz); if not ok then return false, why end
  return goY(ty)
end

local function goHome()
  local ok, why = travel(C.dx, C.dy, C.dz)
  if not ok then error("Can't get home: " .. tostring(why), 0) end
  face(C.dh)
end

local function atDock() return S.x == C.dx and S.y == C.dy and S.z == C.dz end

local function fuel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

local function fuelHome()
  local alt = travelAlt()
  return math.abs(S.x - C.dx) + math.abs(S.z - C.dz) + (alt - S.y) + (alt - C.dy) + 60
end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------
local function slotOf(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then return s end
  end
end

local function counts()
  local c = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then c[d.name] = (c[d.name] or 0) + d.count end
  end
  return c
end

local abortWith -- forward declaration

local function placeHere(name)
  -- Place `name` in the block below. Returns "placed", "skipped" or "missing".
  local ok, d = turtle.inspectDown()
  if ok then
    if d.name == name then return "skipped" end
    local n = tostring(d.name)
    if n:find("kelp") or n:find("seagrass") or n:find("sea_pickle") or n == "minecraft:tall_grass" or n == "minecraft:short_grass" then
      turtle.digDown(); dropJunk()
    elseif n ~= "minecraft:water" and n ~= "minecraft:lava" and n ~= "minecraft:bubble_column" then
      return "skipped" -- already solid: seabed or something we shouldn't touch
    end
  end
  local s = slotOf(name)
  if not s then return "missing" end
  turtle.select(s)
  if turtle.placeDown() then return "placed" end
  -- Something non-solid might be in the way (e.g. a mob or falling item); try once more
  turtle.attackDown(); turtle.digDown()
  if turtle.placeDown() then return "placed" end
  return "skipped"
end

---------------------------------------------------------------------------
-- Work list helpers
---------------------------------------------------------------------------
local function pal(ch) return P.info.palette[ch] end

local function layer1Y() return C.sea + P.info.ybase end

-- Estimate the next batch of materials needed from the current work position.
local function upcomingNeeds()
  local need, order = {}, {}
  local function add(name, n)
    if not need[name] then need[name] = 0; order[#order + 1] = name end
    need[name] = need[name] + n
  end
  local function slots()
    local s = 0
    for _, v in pairs(need) do s = s + math.ceil(v / 64) end
    return s
  end
  if S.phase == "ext" then
    local depth = math.max(0, layer1Y() - (C.seabed or (C.sea - 20)) - 1)
    for i = S.ext or 1, #P.ext do
      add(pal(P.ext[i][3]), depth + 2)
      if slots() > SLOTS_FOR_BLOCKS then need[pal(P.ext[i][3])] = need[pal(P.ext[i][3])] - depth - 2; break end
    end
  end
  if S.phase == "ext" or S.phase == "layer" then
    local startL = S.phase == "layer" and S.layer or 1
    local startC = S.phase == "layer" and S.cell or 1
    local done = false
    for n = startL, P.info.layers do
      local cells = layerCells(n)
      for i = (n == startL and startC or 1), #cells do
        local name = pal(cells[i][3])
        add(name, 1)
        if slots() > SLOTS_FOR_BLOCKS then need[name] = need[name] - 1; done = true; break end
      end
      if done then break end
    end
  end
  -- Everything he carries goes back in the barrel first, so ask for the whole batch
  local req = {}
  for _, name in ipairs(order) do
    if need[name] > 0 then req[#req + 1] = { name, need[name] } end
  end
  return req
end

---------------------------------------------------------------------------
-- Talking to the base
---------------------------------------------------------------------------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
local inbox = {}   -- supply replies
local ctrl = nil   -- latest command

local function send(msg)
  if modem then rednet.broadcast(msg, PROTOCOL) end
end

-- Where am I? Asked of the GPS towers every few seconds in the background, for the art wall's
-- turtle map. Nothing else uses it, and without towers it just stays empty.
local gpsPos, gpsAt = nil, nil
local function gpsLoop()
  while true do
    local ok, x, y, z = pcall(gps.locate, 1)
    if ok and x then
      gpsPos, gpsAt = { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }, os.clock()
    end
    os.sleep(5)
  end
end
local function gpsNow() return (gpsAt and os.clock() - gpsAt < 30) and gpsPos or nil end

local function statusMsg()
  local total = P and P.info.blocks or 0
  return {
    type = "status", id = os.getComputerID(), label = os.getComputerLabel(),
    state = S.status, msg = S.msg, phase = S.phase, layer = S.layer, layers = P and P.info.layers,
    ext = S.ext, extTotal = P and #P.ext, placed = S.placed or 0, total = total,
    fuel = turtle.getFuelLevel(), fuelLimit = turtle.getFuelLimit(), y = S.y,
    missing = S.missing, plan = P and P.info.name, bill = S.billLeft, seq = S.seq,
    markers = S.markers and #S.markers or 0, pos = gpsNow(),
  }
end

local function faceSupply()
  if C.supplyDir ~= "up" and C.supplyDir ~= "down" then face(C.supplyDir) end
end
local function dropSupply()
  if C.supplyDir == "up" then return turtle.dropUp() elseif C.supplyDir == "down" then return turtle.dropDown() end
  return turtle.drop()
end

-- Hand everything back (storage takes it in before loading the next batch)
local function depositAll()
  faceSupply()
  for s = 1, 16 do
    if turtle.getItemCount(s) > 0 then turtle.select(s); dropSupply() end
  end
  turtle.select(1)
end

-- Ask storage for materials + fuel, then take everything from the supply barrel.
local function restock(req, fuelUnits)
  depositAll()
  local seq = os.epoch("utc")
  local reply
  for _ = 1, 3 do
    send({ type = "need", seq = seq, items = req, fuel = fuelUnits })
    local t = os.clock() + 8
    while os.clock() < t do
      os.sleep(0.5)
      for i, m in ipairs(inbox) do
        if m.seq == seq then reply = m; table.remove(inbox, i); break end
      end
      if reply then break end
    end
    if reply then break end
  end
  -- Take whatever is in the barrel (storage may be offline and you filled it by hand)
  faceSupply()
  local suck = C.supplyDir == "up" and turtle.suckUp or C.supplyDir == "down" and turtle.suckDown or turtle.suck
  for _ = 1, 32 do
    if not suck() then break end
  end
  -- Burn fuel items that aren't building blocks
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not JUNK_KEEP[d.name] then
      turtle.select(s)
      if turtle.refuel(0) then turtle.refuel() end
    end
  end
  turtle.select(1)
  face(C.dh)
  return reply
end

local function solidBelow()
  local ok, d = turtle.inspectDown()
  if not ok then return false end
  local n = tostring(d.name)
  return not (n == "minecraft:water" or n == "minecraft:lava" or n:find("kelp") or n:find("seagrass")
    or n == "minecraft:bubble_column" or n:find("sea_pickle"))
end

-- Go down until something solid is below (or we reach ty), without digging.
local function descendTo(ty)
  while S.y > ty and not solidBelow() do
    if not move("d") then break end
  end
end

---------------------------------------------------------------------------
-- Markers ("test" / "clear")
---------------------------------------------------------------------------
local function cornerPoints()
  local b = bounds()
  local pts = {}
  for _, y in ipairs({ b.y1, b.y2 }) do
    for _, x in ipairs({ b.x1, b.x2 }) do
      for _, z in ipairs({ b.z1, b.z2 }) do pts[#pts + 1] = { x, y, z } end
    end
  end
  return pts
end

local function placeMarkers()
  S.markers = S.markers or {}
  local have = counts()[MARKER] or 0
  if have < 8 then
    goHome()
    restock({ { MARKER, 8 - have } }, math.max(0, 3000 - fuel()))
    if (counts()[MARKER] or 0) < 8 then setStatus("waiting", "Need 8 " .. MARKER .. " for markers"); return false end
  end
  for i, p in ipairs(cornerPoints()) do
    setStatus("marking", ("Corner %d/8 at %d %d %d"):format(i, p[1], p[2], p[3]))
    -- Fly in above the corner, then drop to it (stopping on the seabed if it's higher)
    local ok, why = travel(p[1], math.max(p[2] + 1, travelAlt()), p[3])
    if ok then descendTo(p[2] + 1) end
    if not ok then setStatus("error", "Marker trip: " .. tostring(why)); goHome(); return false end
    if placeHere(MARKER) == "placed" then S.markers[#S.markers + 1] = { S.x, S.y - 1, S.z }; save() end
  end
  goHome()
  setStatus("docked", "Markers placed. Check the corners, then build or clear.")
  return true
end

local function clearMarkers()
  for i = #(S.markers or {}), 1, -1 do
    local p = S.markers[i]
    setStatus("clearing", ("Marker %d at %d %d %d"):format(i, p[1], p[2], p[3]))
    local ok = travel(p[1], p[2] + 1, p[3])
    if ok then
      local found, d = turtle.inspectDown()
      if found and d.name == MARKER then turtle.digDown() end
    end
    table.remove(S.markers, i); save()
  end
  goHome()
  setStatus("docked", "Markers cleared")
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
abortWith = function(reason) error({ abort = reason }, 0) end

local function applyCtrl()
  if not ctrl or ctrl.seq == nil or ctrl.seq == S.seq then return end
  S.seq = ctrl.seq
  S.want = ctrl.want
  save()
end

local function checkpoint()
  applyCtrl()
  if S.want ~= "build" then abortWith("stop") end
  if fuel() < fuelHome() then abortWith("fuel") end
end

local function buildPillar(i)
  local col = P.ext[i]
  local name = pal(col[3])
  local wx, _, wz = toWorld(col[1], 0, col[2])
  local topY = layer1Y() - 1           -- pillar goes up to just under layer 1
  local plane = layer1Y() + 1          -- flying height between edge columns
  checkpoint()
  if not (S.x == wx and S.z == wz) then
    local ok, why
    if S.y == plane and inSite(S.x, S.z) then ok, why = goXZ(wx, wz) else ok, why = travel(wx, plane, wz) end
    if ok and S.y ~= plane then ok, why = travel(wx, plane, wz) end
    if not ok then error("Can't reach edge column: " .. tostring(why), 0) end
  end
  -- Go down the column until we sit on something solid (your seabed, or a half-built wall)
  descendTo(-60)
  -- Climb back up, filling below, to the top of the wall
  while S.y <= topY + 1 do
    checkpoint()
    local r = placeHere(name)
    if r == "missing" then abortWith("restock") end
    if r == "placed" then S.placed = (S.placed or 0) + 1 end
    local ok, why = move("u")
    if not ok then error("Pillar blocked: " .. tostring(why), 0) end
  end
end

local function buildLayer(n)
  local cells = layerCells(n)
  for i = S.cell or 1, #cells do
    S.cell = i
    local c = cells[i]
    local name = pal(c[3])
    checkpoint()
    local wx, wy, wz = c[4], c[5], c[6]
    local nearPlane = inSite(S.x, S.z) and math.abs(S.y - (wy + 1)) <= 1
    if not nearPlane then
      local ok, why = travel(wx, wy + 1, wz)
      if not ok then error("Can't reach layer " .. n .. ": " .. tostring(why), 0) end
    else
      local ok, why = goY(wy + 1)                -- step up to the next layer's flying height
      if ok then ok, why = goXZ(wx, wz) end
      if not ok then error("Layer " .. n .. " path blocked: " .. tostring(why), 0) end
      if S.y ~= wy + 1 then
        local ok2, why2 = travel(wx, wy + 1, wz)
        if not ok2 then error("Can't get back to layer " .. n .. ": " .. tostring(why2), 0) end
      end
    end
    local r = placeHere(name)
    if r == "missing" then abortWith("restock") end
    if r == "placed" then
      S.placed = (S.placed or 0) + 1
      S.billLeft[name] = math.max(0, (S.billLeft[name] or 1) - 1)
    end
    save()
  end
  S.cell = 1
end

local function runBuild()
  if S.markers and #S.markers > 0 then clearMarkers() end
  if not S.phase then S.phase, S.ext, S.layer, S.cell = "ext", 1, 1, 1 end
  if S.phase == "ext" then
    setStatus("building", "Edge walls down to the seabed")
    for i = S.ext or 1, #P.ext do
      S.ext = i
      setStatus("building", ("Edge wall %d/%d"):format(i, #P.ext))
      buildPillar(i)
      S.ext = i + 1; save()
    end
    S.phase, S.layer, S.cell = "layer", 1, 1; save()
  end
  if S.phase == "layer" then
    for n = S.layer or 1, P.info.layers do
      S.layer = n
      setStatus("building", ("Layer %d/%d (Y %d)"):format(n, P.info.layers, C.sea + P.info.ybase + n - 1))
      buildLayer(n)
      S.layer = n + 1; S.cell = 1; save()
    end
    S.phase = "done"; save()
  end
end

local function topUpFuel()
  local fuelWant = math.max(0, math.min(FUEL_TOPUP, (turtle.getFuelLimit() == "unlimited" and 0 or turtle.getFuelLimit())) - fuel())
  if fuelWant >= 800 then restock({}, fuelWant) end   -- fuel first, with empty pockets
end

local function dockVisit()
  setStatus("docked", "Restocking")
  dropJunk()
  topUpFuel()
  local req = upcomingNeeds()
  local reply = restock(req, 0)
  S.missing = reply and reply.missing or nil
  save()
end

local function nextNeededItem()
  if S.phase == "ext" then return pal(P.ext[S.ext or 1][3]) end
  if S.phase == "layer" then
    local cells = layerCells(S.layer)
    local c = cells[S.cell or 1]
    return c and pal(c[3])
  end
end

local function mainLoop()
  while true do
    applyCtrl()
    if S.lost then
      setStatus("lost", "Carry me back to the dock, then type: rigger found")
      os.sleep(5)
    elseif S.want == "test" then
      S.want = "idle"; save()
      if not atDock() then goHome() end
      topUpFuel()
      placeMarkers()
    elseif S.want == "clear" then
      S.want = "idle"; save()
      if not atDock() then goHome() end
      topUpFuel()
      clearMarkers()
    elseif S.want == "build" and S.phase ~= "done" then
      if not atDock() and S.phase == nil then goHome() end
      if atDock() then
        dockVisit()
        local need = nextNeededItem()
        if need and not slotOf(need) then
          local m = {}
          for _, e in ipairs(S.missing or {}) do m[#m + 1] = e[2] .. " " .. e[1]:gsub("^.-:", "") end
          setStatus("waiting", "Need " .. (#m > 0 and table.concat(m, ", ") or need:gsub("^.-:", "")))
          os.sleep(30)
        elseif fuel() < fuelHome() * 2 + 500 then
          setStatus("waiting", "Need fuel (have " .. fuel() .. ")")
          os.sleep(30)
        else
          S.missing = nil
          local ok, err = pcall(runBuild)
          if ok then
            goHome()
            setStatus("done", "Build finished! " .. (S.placed or 0) .. " blocks placed.")
          elseif type(err) == "table" and err.abort then
            setStatus("returning", err.abort == "restock" and "Out of the next block"
              or err.abort == "fuel" and "Low on fuel" or "Stop requested")
            goHome()
          else
            setStatus("error", tostring(err))
            pcall(goHome)
            os.sleep(30)
          end
        end
      else
        setStatus("returning", "Heading home")
        goHome()
      end
    else
      if not atDock() then setStatus("returning", "Heading home"); goHome() end
      if S.phase == "done" then setStatus("done", "Build finished. " .. (S.placed or 0) .. " blocks placed.")
      else setStatus("docked", "Waiting. Say: island rigger build | test | clear") end
      local t = os.clock() + 10
      while os.clock() < t and not (ctrl and ctrl.seq ~= S.seq) do os.sleep(1) end
    end
  end
end

local function netLoop()
  if not modem then return os.pullEvent("never") end
  rednet.open(peripheral.getName(modem))
  local lastSend = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" then
      if msg.type == "cmd" then ctrl = msg
      elseif msg.type == "supplied" then inbox[#inbox + 1] = msg end
    end
    if os.clock() - lastSend >= 3 then send(statusMsg()); lastSend = os.clock() end
  end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
local HEAD = { north = 0, east = 1, south = 2, west = 3, n = 0, e = 1, s = 2, w = 3 }

local function ask(q, default, conv)
  while true do
    write(q .. (default ~= nil and (" [" .. tostring(default) .. "]") or "") .. ": ")
    local a = read()
    if a == "" and default ~= nil then return default end
    local v = conv and conv(a) or a
    if v ~= nil then return v end
    printError("Didn't understand that.")
  end
end

local function nums(s)
  local t = {}
  for n in s:gmatch("%-?%d+") do t[#t + 1] = tonumber(n) end
  return t
end

local function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = tostring(d.name)
  return n:find("barrel") or n:find("chest")
end

local function setup()
  term.clear(); term.setCursorPos(1, 1)
  print("RIGGER SETUP  (use F3 for coordinates)")
  local plan = ask("Plan file", "mossy.plan")
  local p = loadPlan(plan)
  print(("%s: %d blocks, %d layers, %dx%d"):format(p.info.name, p.info.blocks, p.info.layers,
    p.info.maxX - p.info.minX + 1, p.info.maxZ - p.info.minZ + 1))
  local dock = ask("My X Y Z (the block I'm in)", nil, function(a) local t = nums(a); return #t == 3 and t or nil end)
  local dh = ask("Which way am I facing (north/east/south/west)", nil, function(a) return HEAD[a:lower()] end)
  local site = ask("Island centre X Z", nil, function(a) local t = nums(a); return #t == 2 and t or nil end)
  local sea = ask("Sea level Y (the top water block)", 62, tonumber)
  local seabed = ask("Seabed Y there, roughly", sea - 20, tonumber)
  local rot = ask("Rotate the island 0/90/180/270", 0, function(a) local v = tonumber(a); return (v == 0 or v == 90 or v == 180 or v == 270) and v or nil end)
  local cruise = ask("Safe flying height (clears your base)", math.max(dock[2] + 12, sea + 12), tonumber)
  C = { plan = plan, dx = dock[1], dy = dock[2], dz = dock[3], dh = dh, cx = site[1], cz = site[2],
        sea = sea, seabed = seabed, rot = rot, cruise = cruise }
  -- Find the supply barrel
  S = { x = C.dx, y = C.dy, z = C.dz, h = C.dh, want = "idle" }
  local found
  for _ = 0, 3 do
    if not found and isContainer(turtle.inspect()) then found = S.h end
    turnRight()
  end
  if not found and isContainer(turtle.inspectUp()) then found = "up" end
  if not found and isContainer(turtle.inspectDown()) then found = "down" end
  face(C.dh)
  if not found then error("No supply barrel next to me. Place one and run rigger again.", 0) end
  C.supplyDir = found
  writeT(CFG_FILE, C)
  save()
  print("Setup saved. Supply barrel found.")
  print("Next: island rigger test   (puts markers on the 8 corners)")
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
if args[1] == "setup" or not C then
  setup()
end

if not fs.exists("startup.lua") then
  local f = fs.open("startup.lua", "w"); f.write('shell.run("rigger")\n'); f.close()
end

P = loadPlan(C.plan)
for _, name in pairs(P.info.palette) do JUNK_KEEP[name] = true end
JUNK_KEEP[MARKER] = true
if not S.billLeft then
  S.billLeft = {}
  for n, c in pairs(P.info.bill) do S.billLeft[n] = c end
end

-- No saved position (fresh state file): he must be sitting on his dock
if S.x == nil then S.x, S.y, S.z, S.h, S.want = C.dx, C.dy, C.dz, C.dh, S.want or "idle" end

-- Recover from an interrupted move
if S.turning then S.lost = true; S.turning = nil end
if S.pending then
  local f = turtle.getFuelLevel()
  if type(f) == "number" and type(S.pending.fuel) == "number" then
    if f < S.pending.fuel then apply(S.pending.kind) end
  else
    S.lost = true
  end
  S.pending = nil
end
if args[1] == "found" then S.x, S.y, S.z, S.h, S.lost = C.dx, C.dy, C.dz, C.dh, nil end
if args[1] == "build" or args[1] == "stop" or args[1] == "test" or args[1] == "clear" then
  S.want = args[1] == "stop" and "dock" or args[1]
end
save()

setStatus("docked", "Starting")
parallel.waitForAny(mainLoop, netLoop, gpsLoop)
