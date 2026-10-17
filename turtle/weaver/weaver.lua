-- weaver.lua  --  plan-following builder turtle (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: a turtle with a diamond pickaxe (to clear kelp/sand in the way) and a wireless or
-- ender modem. A plan file (e.g. mossy.plan) on the turtle. A SUPPLY barrel next to the dock
-- that storage fills (marker: 1 brick in /setup).
--
-- Commands come from the Architect computer, or chat via the mainframe:
--   island weaver test | clear | build | stop | status
-- Or type them here:  weaver test  /  weaver build  /  weaver stop  /  weaver clear
-- The plan maths (loading, building order, rotation) is in weaverplan.lua, shared with the Architect.
--
-- How it builds:
--   1. Edge columns: walls under the island's outer edge, from your real seabed up to the plan.
--   2. Layers, bottom to top: flies one block above each layer and places blocks below him.
--      Cells that are already solid (your seabed, or blocks he placed before a restart) are skipped.
--   3. Whenever he's missing the next block or getting low on fuel, he flies home, asks storage
--      for the next batch, and carries on exactly where he stopped.
--   4. If storage has run out of a block, he leaves a GAP there and builds everything else he
--      can. Nothing is ever built straight on top of a gap (the column above it waits too), so
--      he can always drop down to it later. At each dock visit he asks for the gaps' blocks and
--      fills whatever has turned up, bottom up, before carrying on. When everything else is
--      built he waits at the dock until storage has the rest.

local PROTOCOL   = "tanis-rigger"
local STATE_FILE = "weaver.state"
local CFG_FILE   = "weaver.cfg"
local GAPS_FILE  = "weaver.gaps"    -- the gaps, as a log of "+ x y z block [wall]" / "- x y z" lines
local MARKER     = "minecraft:dirt" -- block used by "test" to mark the corners
local FUEL_TOPUP = 20000            -- fuel to top up to at every dock visit
local SLOTS_FOR_BLOCKS = 15         -- one slot kept free for junk/fuel
local GAP_SLOTS  = 8                -- at most this many slots of a batch go to filling gaps
local GAP_PROBE  = 64               -- while storage is out of a block, ask for at most this many
local DRY_MAX    = 5000             -- blocks in a row he can't place before he gives up and waits
local GAP_MAX    = 4000             -- most gaps he'll leave before waiting for storage (disk space)
local DISK_MIN   = 120000           -- bytes of turtle disk he keeps free (the plan file is big)
local STOCK_WAIT = 300              -- longest wait at the dock before asking storage again (s)

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

---------------------------------------------------------------------------
-- Gaps: blocks left out because storage had none of that block
---------------------------------------------------------------------------
-- G.list[key] = { x, y, z, name, ext = edge wall number or nil, above = true if it only waits for a
-- gap lower down (storage has the block) }; G.cols["x,z"] = { x, z, ys, low }
-- New lines are buffered and written by save() BEFORE the state file, so a gap is always on disk
-- by the time his progress counter has moved past it.
local G = { list = {}, cols = {}, n = 0, ver = 0, buf = {} }
local function gkey(x, y, z) return x .. "," .. y .. "," .. z end
local function ckey(x, z) return x .. "," .. z end

local PCH = {}   -- block name -> its one-letter plan code (filled once the plan is loaded): short lines
local function gapLine(g)
  return ("+ %d %d %d %s %s%s"):format(g.x, g.y, g.z, PCH[g.name] or g.name, g.ext and tostring(g.ext) or "-",
    g.above and " a" or "")
end

local function addGap(x, y, z, name, ext, above)
  local k = gkey(x, y, z)
  if G.list[k] then return end
  local g = { x = x, y = y, z = z, name = name, ext = ext, above = above or nil }
  G.list[k] = g
  local c = G.cols[ckey(x, z)]
  if not c then c = { x = x, z = z, ys = {} }; G.cols[ckey(x, z)] = c end
  c.ys[y] = true
  if not c.low or y < c.low then c.low = y end
  G.n, G.ver = G.n + 1, G.ver + 1
  G.buf[#G.buf + 1] = gapLine(g)
end

local function delGap(x, y, z)
  local k = gkey(x, y, z)
  if not G.list[k] then return end
  G.list[k] = nil
  local c = G.cols[ckey(x, z)]
  if c then
    c.ys[y] = nil
    if c.low == y then
      c.low = nil
      for yy in pairs(c.ys) do if not c.low or yy < c.low then c.low = yy end end
      if not c.low then G.cols[ckey(x, z)] = nil end
    end
  end
  G.n, G.ver = G.n - 1, G.ver + 1
  G.buf[#G.buf + 1] = ("- %d %d %d"):format(x, y, z)
end

-- Is there a gap lower down in this column? Then nothing above it may be built yet.
local function gapBelow(x, y, z)
  local c = G.cols[ckey(x, z)]
  return c ~= nil and c.low < y
end

local function flushGaps()
  if #G.buf == 0 then return end
  local f = fs.open(GAPS_FILE, "a")
  for _, l in ipairs(G.buf) do f.writeLine(l) end
  f.close()
  G.buf = {}
end

-- Rewrite the log with just the gaps still open (keeps it short)
local function compactGaps()
  G.buf = {}
  local f = fs.open(GAPS_FILE .. ".new", "w")
  for _, g in pairs(G.list) do f.writeLine(gapLine(g)) end
  f.close()
  if fs.exists(GAPS_FILE) then fs.delete(GAPS_FILE) end
  fs.move(GAPS_FILE .. ".new", GAPS_FILE)
end

local function loadGaps(palette)
  if fs.exists(GAPS_FILE .. ".new") and not fs.exists(GAPS_FILE) then fs.move(GAPS_FILE .. ".new", GAPS_FILE) end
  if not fs.exists(GAPS_FILE) then return end
  local f = fs.open(GAPS_FILE, "r")
  while true do
    local l = f.readLine()
    if not l then break end
    local op, x, y, z, rest = l:match("^([%+%-]) (%-?%d+) (%-?%d+) (%-?%d+)%s*(.*)$")
    if op == "+" then
      local name, ext, above = rest:match("^(%S+)%s*(%S*)%s*(%S*)")
      if name and palette and palette[name] then name = palette[name] end   -- one-letter plan code
      if name then addGap(tonumber(x), tonumber(y), tonumber(z), name, tonumber(ext), above == "a") end
    elseif op == "-" then
      delGap(tonumber(x), tonumber(y), tonumber(z))
    end
  end
  f.close()
  compactGaps()
end

local function clearGaps()
  G.list, G.cols, G.n, G.ver, G.buf = {}, {}, 0, G.ver + 1, {}
  if fs.exists(GAPS_FILE) then fs.delete(GAPS_FILE) end
end

-- { {block, count}, ... } biggest first, and the same for just the gaps storage is out of
-- (not counting those that only wait for a gap below). Cached until the gaps change.
local gapItemsCache
local function gapItems(onlyShort)
  if not (gapItemsCache and gapItemsCache.ver == G.ver) then
    local c, s, above = {}, {}, 0
    for _, g in pairs(G.list) do
      c[g.name] = (c[g.name] or 0) + 1
      if g.above then above = above + 1 else s[g.name] = (s[g.name] or 0) + 1 end
    end
    local function list(m)
      local t = {}
      for n, v in pairs(m) do t[#t + 1] = { n, v } end
      table.sort(t, function(a, b) return a[2] > b[2] end)
      return t
    end
    gapItemsCache = { ver = G.ver, all = list(c), short = list(s), above = above }
  end
  return onlyShort and gapItemsCache.short or gapItemsCache.all, gapItemsCache.above
end

local function save() flushGaps(); writeT(STATE_FILE, S) end
local function isShort(name) return S.short ~= nil and S.short[name] == true end

---------------------------------------------------------------------------
-- Plan
---------------------------------------------------------------------------
local RP = dofile("weaverplan.lua")
local P -- { info, ext = {{x,z,ch}}, layers = { [n] = {{z,x0,rle}} } }

local function loadPlan(path) return RP.load(path) end
local function toWorld(px, py, pz) return RP.toWorld(C, px, py, pz) end
local function pal(ch) return P.info.palette[ch] end
local function layer1Y() return C.sea + P.info.ybase end

-- The highest Y he may have built at so far. Flying above it never runs into his own work
-- (which matters when he drops down into an old gap far below the layer he's on).
local function builtTop()
  if not P or not S.phase then return -math.huge end
  if S.phase == "ext" then return layer1Y() - 1 end
  if S.phase == "layer" then return layer1Y() + (S.layer or 1) - 1 end
  return layer1Y() + P.info.layers - 1
end

-- Ordered cell list for layer n: { px, pz, ch, wx, wy, wz }
local cellCache = {}
local function layerCells(n)
  if cellCache.n == n then return cellCache.cells end
  local py = P.info.ybase + n - 1
  local cells = RP.orderRows(P.layers[n])
  for _, c in ipairs(cells) do c[4], c[5], c[6] = toWorld(c[1], py, c[2]) end
  cellCache = { n = n, cells = cells }
  return cells
end

local boundsCache
local function bounds()
  if not boundsCache then boundsCache = RP.bounds(P.info, C) end
  return boundsCache
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

---------------------------------------------------------------------------
-- Chunk controller (Advanced Peripherals' "Chunky Turtle" upgrade), same trick as the miners:
-- carried in my bag, swapped onto my modem's side for a moment whenever I cross into a new chunk
-- and every REFRESH_EVERY seconds. That force-loads the chunk I'm in (only that one: the last one is
-- released) and it stays loaded after I swap back (the mod's timeout, 600 s by default, >= 60 s).
-- Gear (the controller, modems) is never dropped as junk or handed back to storage.
---------------------------------------------------------------------------
local CHUNKY_ITEM = "advancedperipherals:chunk_controller"
local REFRESH_EVERY = 45
local function isModemItem(name)
  return name == "computercraft:wireless_modem_advanced" or name == "computercraft:wireless_modem_normal"
end
local function isGear(name) return name == CHUNKY_ITEM or isModemItem(name) end
local EQUIP = { left = turtle.equipLeft, right = turtle.equipRight }
local function sideOfType(t)
  for _, sd in ipairs({ "left", "right" }) do
    for _, x in ipairs({ peripheral.getType(sd) }) do if x == t then return sd end end
  end
end
local function chunkySlot()
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and d.name == CHUNKY_ITEM then return s end end
end
local chunkyAt, chunkyKey = -1e9, nil
local function refreshChunk(force)
  if not (chunkySlot() or sideOfType("chunky")) or not S.x then return end
  local key = math.floor(S.x / 16) .. "," .. math.floor(S.z / 16)
  if not force and key == chunkyKey and os.clock() - chunkyAt < REFRESH_EVERY then return end
  if sideOfType("chunky") then
    os.sleep(0.1)                         -- worn all the time: it reloads my chunk every tick
  else
    local slot, side = chunkySlot(), sideOfType("modem")
    if not side then S.chunkyNote = "No modem to swap with"; return end
    local prev = turtle.getSelectedSlot()
    turtle.select(slot)
    S.swapSide = side; save()             -- unloaded mid-swap: boot puts the modem back
    if EQUIP[side]() then
      os.sleep(0.15)                      -- at least one server tick with it on: loads + touches this chunk
      turtle.select(slot)
      EQUIP[side]()                       -- modem back on; the controller back in that slot
    end
    S.swapSide = nil; save()
    turtle.select(prev)
    pcall(rednet.open, side)
    S.swaps = (S.swaps or 0) + 1
  end
  S.chunkyNote = nil
  chunkyAt, chunkyKey = os.clock(), key
end
-- A swap that was cut short leaves the modem in my bag: put it back before anything looks for it
do
  if not sideOfType("modem") then
    local ms
    for s = 1, 16 do local d = turtle.getItemDetail(s); if d and isModemItem(d.name) then ms = s end end
    local side = sideOfType("chunky") or S.swapSide
    if ms and side then turtle.select(ms); EQUIP[side](); turtle.select(1); print("Put my modem back on.") end
  end
  S.swapSide = nil
end

local JUNK_KEEP = {} -- filled with palette item names: never dropped
local function dropJunk()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not JUNK_KEEP[d.name] and not isGear(d.name) then
      turtle.select(s)
      if not turtle.refuel(0) then turtle.dropUp() end
    end
  end
  turtle.select(1)
end

local orderWaiting   -- set further down: true when a newer order has arrived

-- The next block is in a chunk that isn't loaded: wait there (it loads when you come near)
-- instead of giving up. Returns true once he's moved, or false if a new order arrives first.
local function waitForChunk(kind, op)
  local tx, tz = S.x, S.z
  if kind == "f" then tx, tz = S.x + DX[S.h], S.z + DZ[S.h] end
  local was, wasMsg = S.status, S.msg
  setStatus("waiting", ("Chunk at X %d Z %d isn't loaded: waiting for it"):format(tx, tz))
  while true do
    refreshChunk()
    os.sleep(5)
    if orderWaiting and orderWaiting() then setStatus(was, wasMsg); return false end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }
    save()
    local ok, why = op.move()
    if ok then
      apply(kind); S.pending = nil; save()
      setStatus(was, wasMsg)
      refreshChunk()
      return true
    end
    S.pending = nil
    if not tostring(why):find("loaded world") then setStatus(was, wasMsg); return nil end
  end
end

-- One block of movement, clearing natural blocks inside the build site.
-- Returns false, reason if something unbreakable / protected is in the way.
local function move(kind)
  local op = OPS[kind]
  for _ = 1, 40 do
    if turtle.getFuelLevel() == 0 then return false, "Out of fuel" end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }
    save()
    local moved, why = op.move()
    if moved then
      apply(kind); S.pending = nil; save()
      refreshChunk()   -- a new chunk (or time's up): keep the one I'm in loaded
      return true
    end
    S.pending = nil
    why = tostring(why)
    if why:find("loaded world") then
      local r = waitForChunk(kind, op)
      if r == true then return true elseif r == false then return false, "Chunk not loaded" end
    elseif why:find("protected area") or why:find("world border") or why:find("leave the world")
        or why:find("Too high") or why:find("Too low") then
      save(); return false, "Blocked: " .. why
    end
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
  return math.max(C.cruise, S.y, extraY or -math.huge, builtTop() + 1)
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
-- Estimate the next batch of materials: first the gaps' blocks (up to GAP_SLOTS), then what the
-- build needs next. A block storage was out of last time is only asked for in a GAP_PROBE-sized
-- amount, so the batch isn't wasted on it; if storage has it again, the next visit asks for more.
local function upcomingNeeds()
  local need, order = {}, {}
  -- gear (a chunk controller) takes a slot of its own: one block slot less per batch
  local gear = 0
  for sl = 1, 16 do local d = turtle.getItemDetail(sl); if d and isGear(d.name) then gear = gear + 1 end end
  local maxSlots = SLOTS_FOR_BLOCKS - gear
  local function slots()
    local s = 0
    for _, v in pairs(need) do s = s + math.ceil(v / 64) end
    return s
  end
  -- storage was out of it last visit, and its broadcast doesn't show any back in yet
  local function stillShort(name)
    if not isShort(name) then return false end
    if stock and stockAt and os.clock() - stockAt < 20 then return (tonumber(stock[name]) or 0) == 0 end
    return true
  end
  -- add n of a block; false = the batch is full (nothing was added)
  local function add(name, n, limit)
    local have = need[name] or 0
    if stillShort(name) then n = math.min(n, GAP_PROBE - have) end
    if n <= 0 then return true end
    need[name] = have + n
    if slots() > (limit or maxSlots) then need[name] = have; return false end
    if have == 0 then order[#order + 1] = name end
    return true
  end
  -- the gaps' blocks (an edge-wall gap is a whole wall: up to depth + 2 blocks)
  local depth = math.max(0, layer1Y() - (C.seabed or (C.sea - 20)) - 1)
  local gneed, glist = {}, {}
  for _, g in pairs(G.list) do
    if not gneed[g.name] then gneed[g.name] = 0; glist[#glist + 1] = g.name end
    gneed[g.name] = gneed[g.name] + (g.ext and (depth + 2) or 1)
  end
  table.sort(glist, function(a, b) return gneed[a] > gneed[b] end)
  local full = false
  for _, name in ipairs(glist) do
    local left = gneed[name]
    while left > 0 do
      local k = math.min(left, 64)
      if not add(name, k, GAP_SLOTS) then full = true; break end
      left = left - k
      if stillShort(name) and (need[name] or 0) >= GAP_PROBE then break end
    end
    if full then break end
  end
  if S.phase == "ext" then
    for i = S.ext or 1, #P.ext do
      if not add(pal(P.ext[i][3]), depth + 2) then break end
    end
  end
  if S.phase == "ext" or S.phase == "layer" then
    local startL = S.phase == "layer" and S.layer or 1
    local startC = S.phase == "layer" and S.cell or 1
    local done = false
    for n = startL, P.info.layers do
      local cells = layerCells(n)
      for i = (n == startL and startC or 1), #cells do
        local c = cells[i]
        if not gapBelow(c[4], c[5], c[6]) then          -- those wait for the gap under them
          if not add(pal(c[3]), 1) then done = true; break end
        end
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
local rebootToken = nil   -- the Architect asked for a reboot (done at the dock, so he updates)
local stock, stockAt = nil, nil   -- storage's item counts, from its broadcast on tanis-base

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
    markers = S.markers and #S.markers or 0, cell = S.cell,
    at = S.x and { x = S.x, y = S.y, z = S.z, h = S.h } or nil,
    pos = gpsNow() or (S.x and { x = S.x, y = S.y, z = S.z }) or nil, gps = gpsNow() ~= nil,
    corners = S.corners, rebootDone = S.rebootDone, want = S.want, v = 3,
    skipped = S.skipped, skips = S.skips,
    gaps = G.n, gapsVer = G.ver, gapItems = { table.unpack(gapItems(true), 1, 8) },
    gapsAbove = select(2, gapItems()),
    chunky = (chunkySlot() or sideOfType("chunky")) ~= nil, chunkyNote = S.chunkyNote, swaps = S.swaps,
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
    local d = turtle.getItemDetail(s)
    if d and not isGear(d.name) then turtle.select(s); dropSupply() end
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
    if d and not JUNK_KEEP[d.name] and not isGear(d.name) then
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

local function applyCtrl()
  -- Orders come from the mainframe and the Architect: only a newer one counts (seqs are epochs)
  if not ctrl or type(ctrl.seq) ~= "number" or (type(S.seq) == "number" and ctrl.seq <= S.seq) then return end
  S.seq = ctrl.seq
  S.want = ctrl.want
  save()
end

local function haveMarkerAt(x, y, z)
  for _, m in ipairs(S.markers or {}) do
    if m[1] == x and m[2] == y and m[3] == z then return true end
  end
end

-- One corner. Returns a report { x, y, z (the corner), res, my (where the marker went), why }:
--   placed  = right on the corner          seabed = the corner is underground/on land, so the
--   already = a marker was there already            marker sits on top of the ground above it
--   failed  = couldn't put it down (why)    trip   = couldn't fly there (why)
local function markCorner(p)
  local rep = { x = p[1], y = p[2], z = p[3] }
  -- Fly in above the corner, then drop to it (stopping on the seabed if it's higher)
  local ok, why = travel(p[1], math.max(p[2] + 1, travelAlt()), p[3])
  if not ok then rep.res, rep.why = "trip", tostring(why); return rep end
  descendTo(p[2] + 1)
  local r = placeHere(MARKER)
  if r == "placed" then
    rep.res, rep.my = (S.y - 1 == p[2]) and "placed" or "seabed", S.y - 1
  else
    local found, d = turtle.inspectDown()
    if found and d.name == MARKER then
      rep.res, rep.my = "already", S.y - 1
    elseif found then
      -- Solid ground at or above the corner: put the marker on top of it instead
      local up, why2 = move("u")
      if up and placeHere(MARKER) == "placed" then
        rep.res, rep.my = "seabed", S.y - 1
        rep.why = "ground is " .. tostring(d.name):gsub("^.-:", "")
      else
        rep.res, rep.why = "failed", up and "couldn't place" or tostring(why2)
      end
    else
      rep.res, rep.why = "failed", r == "missing" and "out of markers" or "couldn't place"
    end
  end
  if rep.my and not haveMarkerAt(p[1], rep.my, p[3]) then
    S.markers[#S.markers + 1] = { p[1], rep.my, p[3] }
  end
  return rep
end

local function placeMarkers()
  S.markers = S.markers or {}
  S.corners = {}
  local have = counts()[MARKER] or 0
  if have < 8 then
    goHome()
    restock({ { MARKER, 8 - have } }, math.max(0, 3000 - fuel()))
    if (counts()[MARKER] or 0) < 8 then setStatus("waiting", "Need 8 " .. MARKER .. " for markers"); return false end
  end
  local pts = cornerPoints()
  for i, p in ipairs(pts) do
    applyCtrl()
    if S.want ~= "idle" then                -- a new order arrived: stop marking
      S.corners[i] = { x = p[1], y = p[2], z = p[3], res = "todo" }
      for j = i + 1, #pts do S.corners[j] = { x = pts[j][1], y = pts[j][2], z = pts[j][3], res = "todo" } end
      save(); goHome()
      setStatus("docked", "Marker test stopped at corner " .. i)
      return false
    end
    setStatus("marking", ("Corner %d/8 at %d %d %d"):format(i, p[1], p[2], p[3]))
    S.corners[i] = { x = p[1], y = p[2], z = p[3], res = "going" }
    local rep = markCorner(p)
    S.corners[i] = rep
    save()
    if rep.res == "trip" then
      for j = i + 1, #pts do S.corners[j] = { x = pts[j][1], y = pts[j][2], z = pts[j][3], res = "todo" } end
      save()
      setStatus("error", "Marker trip, corner " .. i .. ": " .. tostring(rep.why))
      pcall(goHome)
      return false
    end
  end
  goHome()
  local n, sb, bad = 0, 0, 0
  for _, c in ipairs(S.corners) do
    if c.res == "placed" or c.res == "already" then n = n + 1
    elseif c.res == "seabed" then n = n + 1; sb = sb + 1
    else bad = bad + 1 end
  end
  setStatus("docked", ("Markers: %d of 8 down%s%s. The top 4 are up at Y %d.")
    :format(n, sb > 0 and (", " .. sb .. " on the ground") or "", bad > 0 and (", " .. bad .. " failed") or "",
      bounds().y2))
  return true
end

local function clearMarkers(expect)
  for i = #(S.markers or {}), 1, -1 do
    applyCtrl()
    if S.want ~= (expect or "idle") then save(); goHome(); setStatus("docked", "Clearing stopped"); return end
    local p = S.markers[i]
    setStatus("clearing", ("Marker %d at %d %d %d"):format(i, p[1], p[2], p[3]))
    local ok = travel(p[1], p[2] + 1, p[3])
    if ok then
      local found, d = turtle.inspectDown()
      if found and d.name == MARKER then turtle.digDown() end
    end
    table.remove(S.markers, i); save()
  end
  S.corners = nil
  goHome()
  setStatus("docked", "Markers cleared")
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
abortWith = function(reason) error({ abort = reason }, 0) end

local function checkpoint()
  applyCtrl()
  if S.want ~= "build" then abortWith("stop") end
  if fuel() < fuelHome() then abortWith("fuel") end
end

-- Something he isn't allowed to dig (your shack, a claim, a chest...) keeps him from a block:
-- note it and move on, so one obstacle can't stall the whole build. Lots in a row = real trouble.
local SKIP_RUN_MAX = 25
local function skipBlock(x, y, z, why)
  why = tostring(why)
  if why == "Chunk not loaded" then checkpoint(); abortWith("stop") end   -- a new order came in while waiting
  if why == "Out of fuel" then error("Out of fuel", 0) end
  S.skipped = (S.skipped or 0) + 1
  S.skipRun = (S.skipRun or 0) + 1
  S.skips = S.skips or {}
  S.skips[#S.skips + 1] = { x, y, z, why }
  while #S.skips > 20 do table.remove(S.skips, 1) end
  save()
  if S.skipRun > SKIP_RUN_MAX then
    S.skipRun = 0
    error(("Skipped %d blocks in a row, last: %s"):format(SKIP_RUN_MAX, why), 0)
  end
end

-- Edge wall i: from the seabed up to just under layer 1. Returns "short" if he ran out of a
-- block storage hasn't got (or, while patching, of any block): the caller leaves it as a gap.
local function buildPillar(i, patching)
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
    if not ok then skipBlock(wx, layer1Y() - 1, wz, why); return end
  end
  -- Go down the column until we sit on something solid (your seabed, or a half-built wall)
  descendTo(-60)
  -- Climb back up, filling below, to the top of the wall
  while S.y <= topY + 1 do
    checkpoint()
    local r = placeHere(name)
    if r == "missing" then
      if patching or isShort(name) then return "short" end
      abortWith("restock")
    end
    if r == "placed" then S.placed = (S.placed or 0) + 1 end
    local ok, why = move("u")
    if not ok then skipBlock(S.x, S.y + 1, S.z, why); return end
  end
  S.skipRun = 0
end

-- Does he carry any building block at all?
local function bagHasBlocks()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and JUNK_KEEP[d.name] and d.name ~= MARKER then return true end
  end
  return false
end

-- One more block he couldn't place (no stock, or waiting on a gap below). These cost no
-- moves, so a long run of them is fast; he saves now and then, lets the radio talk, and gives
-- up (goes home to wait) if his bag is empty or nothing has fitted for DRY_MAX blocks.
local function diskLow()
  local ok, free = pcall(fs.getFreeSpace, "/")
  return ok and type(free) == "number" and free < DISK_MIN
end
local function dryStep()
  S.dry = (S.dry or 0) + 1
  if S.dry == 1 or S.dry % 100 == 0 then
    save()
    os.sleep(0)
    if not bagHasBlocks() or S.dry >= DRY_MAX then abortWith("short") end
    if G.n >= GAP_MAX or diskLow() then abortWith("gapcap") end
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
    if gapBelow(wx, wy, wz) then
      addGap(wx, wy, wz, name, nil, true)          -- a gap lower down keeps this column open
      dryStep()
    elseif isShort(name) and not slotOf(name) then
      addGap(wx, wy, wz, name)                     -- storage has none of this block: leave a gap
      dryStep()
    else
      local nearPlane = inSite(S.x, S.z) and math.abs(S.y - (wy + 1)) <= 1
      local ok, why
      if not nearPlane then
        ok, why = travel(wx, wy + 1, wz)
      else
        ok, why = goY(wy + 1)                       -- step up to the next layer's flying height
        if ok then ok, why = goXZ(wx, wz) end
        if ok and S.y ~= wy + 1 then ok, why = travel(wx, wy + 1, wz) end
        if not ok then ok, why = travel(wx, wy + 1, wz) end   -- try the long way round, over the top
      end
      local r = "skip"
      if ok then r = placeHere(name) else skipBlock(wx, wy, wz, why) end
      if r ~= "skip" then S.skipRun = 0 end
      if r == "missing" then
        if not isShort(name) then abortWith("restock") end
        addGap(wx, wy, wz, name)                     -- ran out, and storage has none either
      elseif r == "placed" or r == "skipped" then
        if r == "placed" then
          S.placed = (S.placed or 0) + 1
          S.billLeft[name] = math.max(0, (S.billLeft[name] or 1) - 1)
        end
        delGap(wx, wy, wz)                           -- (only there after a crash mid-block)
        S.dry = 0
      end
      save()
    end
  end
  S.cell = 1
end

-- Fill the gaps whose blocks he now carries: column by column, bottom up, dropping in from
-- above (the column over a gap is always left open). Returns how many blocks went in.
local stuckCols = {}   -- ["x,z"] = os.clock() until which a column he couldn't reach is left alone
local function canTry(c) return not stuckCols[ckey(c.x, c.z)] or os.clock() > stuckCols[ckey(c.x, c.z)] end

local function patchGaps()
  local have = counts()
  local todo = {}
  for _, c in pairs(G.cols) do
    local g = G.list[gkey(c.x, c.low, c.z)]
    if g and (have[g.name] or 0) > 0 and canTry(c) then todo[#todo + 1] = c end
  end
  if #todo == 0 then return 0 end
  -- strips 8 wide, back and forth: short hops between columns
  table.sort(todo, function(a, b)
    local sa, sb = math.floor(a.x / 8), math.floor(b.x / 8)
    if sa ~= sb then return sa < sb end
    if sa % 2 == 0 then return a.z < b.z end
    return a.z > b.z
  end)
  local filled = 0
  for ci, c in ipairs(todo) do
    checkpoint()
    if G.cols[ckey(c.x, c.z)] == c then
      setStatus("building", ("Filling gaps: column %d/%d"):format(ci, #todo))
      local ys = {}
      for y in pairs(c.ys) do ys[#ys + 1] = y end
      table.sort(ys)
      local ok, why = goY(travelAlt())
      if ok then ok, why = goXZ(c.x, c.z) end
      if not ok then
        skipBlock(c.x, c.low, c.z, why)
        stuckCols[ckey(c.x, c.z)] = os.clock() + 600   -- don't keep flying at it: try again later
      else
        for _, y in ipairs(ys) do
          checkpoint()
          local g = G.list[gkey(c.x, y, c.z)]
          if g then
            if not slotOf(g.name) then break end
            if g.ext then
              local before = S.placed or 0
              if buildPillar(g.ext, true) == "short" then break end
              filled = filled + (S.placed or 0) - before
            else
              local ok2, why2 = goY(y + 1)
              if not ok2 then skipBlock(c.x, y, c.z, why2); stuckCols[ckey(c.x, c.z)] = os.clock() + 600; break end
              local r = placeHere(g.name)
              if r == "missing" then break end
              if r == "placed" then
                S.placed = (S.placed or 0) + 1
                S.billLeft[g.name] = math.max(0, (S.billLeft[g.name] or 1) - 1)
                filled = filled + 1
              end
            end
            delGap(c.x, y, c.z)
            save()
          end
        end
      end
      goY(travelAlt())                               -- back up his own (open) column
    end
  end
  return filled
end

local function runBuild()
  if S.markers and #S.markers > 0 then clearMarkers("build") end
  if not S.phase then S.phase, S.ext, S.layer, S.cell = "ext", 1, 1, 1; clearGaps(); save() end
  if S.phase == "ext" then
    setStatus("building", "Edge walls down to the seabed")
    for i = S.ext or 1, #P.ext do
      S.ext = i
      local col = P.ext[i]
      local name = pal(col[3])
      local wx, _, wz = toWorld(col[1], 0, col[2])
      if isShort(name) and not slotOf(name) then
        addGap(wx, layer1Y() - 1, wz, name, i)
        dryStep()
      else
        setStatus("building", ("Edge wall %d/%d"):format(i, #P.ext))
        if buildPillar(i) == "short" then addGap(wx, layer1Y() - 1, wz, name, i)
        else delGap(wx, layer1Y() - 1, wz); S.dry = 0 end
      end
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
  if reply then
    -- whatever storage couldn't give in full is "short" until a later visit gets it
    S.short = {}
    for _, e in ipairs(reply.missing or {}) do
      if e[1] ~= "fuel" then S.short[e[1]] = true end
    end
  end
  save()
  compactGaps()                                      -- keep the gap log short
end

-- Columns whose lowest gap he could fill with what he's carrying
local function patchable()
  local have, n = counts(), 0
  for _, c in pairs(G.cols) do
    local g = G.list[gkey(c.x, c.low, c.z)]
    if g and (have[g.name] or 0) > 0 and canTry(c) then n = n + 1 end
  end
  return n
end

-- Blocks he's waiting for: what storage was short of, plus the gaps' blocks
local function wantedNames()
  local seen, out = {}, {}
  for _, e in ipairs(S.missing or {}) do
    if e[1] ~= "fuel" and not seen[e[1]] then seen[e[1]] = true; out[#out + 1] = e[1] end
  end
  for _, e in ipairs(gapItems(true)) do
    if not seen[e[1]] then seen[e[1]] = true; out[#out + 1] = e[1] end
  end
  return out
end

local function shortList(list, max)
  local m = {}
  for i = 1, math.min(#list, max or 4) do
    m[#m + 1] = (list[i][2] and (tostring(list[i][2]) .. " ") or "") .. tostring(list[i][1]):gsub("^.-:", "")
  end
  if #list > (max or 4) then m[#m + 1] = "..." end
  return table.concat(m, ", ")
end

local function nextNeededItem()
  if S.phase == "ext" then return pal(P.ext[S.ext or 1][3]) end
  if S.phase == "layer" then
    -- the next block he'd actually place (blocks waiting on a gap below need nothing yet)
    local cells = layerCells(S.layer)
    for i = S.cell or 1, math.min(#cells, (S.cell or 1) + 500) do
      local c = cells[i]
      if not gapBelow(c[4], c[5], c[6]) then return pal(c[3]) end
    end
    local c = cells[S.cell or 1]
    return c and pal(c[3])
  end
end

local function newOrder()
  return ctrl and type(ctrl.seq) == "number" and (type(S.seq) ~= "number" or ctrl.seq > S.seq)
end
local function rebootWanted() return rebootToken ~= nil and rebootToken ~= S.rebootDone end
orderWaiting = newOrder

-- Sleep, but wake up for a new order or a reboot request
local function waitFor(sec)
  local t = os.clock() + sec
  while os.clock() < t and not newOrder() and not rebootWanted() do refreshChunk(); os.sleep(0.5) end
end

-- Wait at the dock until storage's count of any of these blocks goes UP (seen in its broadcast), a
-- new order or reboot comes in, or `sec` runs out. A block storage merely has a few of doesn't
-- count: he was just handed those, and returning for them again is the restock loop. Without
-- storage's broadcast, just waits a minute.
local function waitForStock(names, sec)
  local t = os.clock() + sec
  local low = {}   -- the lowest count of each block seen while waiting
  while os.clock() < t and not newOrder() and not rebootWanted() do
    refreshChunk()
    os.sleep(1)
    if stock and stockAt and os.clock() - stockAt < 20 then
      for _, n in ipairs(names) do
        local c = tonumber(stock[n]) or 0
        if low[n] and c > low[n] then return true end
        if not low[n] or c < low[n] then low[n] = c end
      end
    elseif os.clock() > t - sec + 60 then
      return false
    end
  end
end

local function doReboot()
  S.rebootDone = rebootToken
  setStatus("rebooting", "Rebooting to update")
  save()
  send(statusMsg())
  os.sleep(1)
  send(statusMsg())
  os.reboot()
end

-- goHome raises an error if he can't get there; in the main loop that must never crash him
local function safeHome()
  local ok, err = pcall(goHome)
  if not ok then setStatus("error", "Can't get home: " .. tostring(err)); waitFor(30) end
  return ok
end

local function mainLoop()
  while true do
    applyCtrl()
    if rebootWanted() and (atDock() or S.lost) then doReboot() end
    if S.lost then
      setStatus("lost", "Carry me back to the dock, then type: weaver found")
      waitFor(5)
    elseif S.want == "test" then
      S.want = "idle"; save()
      if atDock() or safeHome() then
        topUpFuel()
        local ok, err = pcall(placeMarkers)
        if not ok then setStatus("error", "Marker test: " .. tostring(err)); safeHome() end
      end
    elseif S.want == "clear" then
      S.want = "idle"; save()
      if atDock() or safeHome() then
        topUpFuel()
        local ok, err = pcall(clearMarkers)
        if not ok then setStatus("error", "Clearing markers: " .. tostring(err)); safeHome() end
      end
    elseif S.want == "build" and (S.phase ~= "done" or G.n > 0) then
      if not atDock() and S.phase == nil then safeHome() end
      if atDock() then
        dockVisit()
        local need = nextNeededItem()
        local canPatch = patchable() > 0
        -- Go on building if he has the next block, or storage is out of it but he carries other
        -- blocks to get on with (unless the last trip already found nothing he could place)
        local canBuild = S.phase ~= "done" and (need == nil or slotOf(need) ~= nil
          or (isShort(need) and not S.dryOut and bagHasBlocks()))
        -- His gap log is full: every block that needs a gap would stop him at once, so he waits
        -- for the gaps' blocks (patching is all he can do) rather than flying out to turn back
        local capped = G.n >= GAP_MAX or diskLow()
        if capped and not canPatch then canBuild = false end
        if not canPatch and not canBuild then
          local m = {}
          for _, e in ipairs(S.missing or {}) do
            if e[1] ~= "fuel" then m[#m + 1] = { e[1], e[2] } end
          end
          if capped and S.phase ~= "done" then
            setStatus("waiting", ("%d gaps is my limit: waiting for %s"):format(G.n, shortList(gapItems(true))))
          elseif S.phase == "done" then
            setStatus("waiting", ("Built all I can. %d gaps left, waiting for %s"):format(G.n, shortList(gapItems(true))))
          else
            for i, e in ipairs(m) do m[i] = { e[1] } end   -- names only: the counts were just this batch
            setStatus("waiting", (#m > 0 and ("Storage is out of " .. shortList(m)) or ("Need " .. tostring(need):gsub("^.-:", "")))
              .. (G.n > 0 and (" (" .. G.n .. " gaps left)") or ""))
          end
          waitForStock(wantedNames(), STOCK_WAIT)
        elseif fuel() < fuelHome() * 2 + 500 then
          setStatus("waiting", "Need fuel (have " .. fuel() .. ")")
          waitFor(30)
        else
          S.dryOut, S.dry = nil, 0
          save()
          local ok, err = pcall(function()
            if canPatch then patchGaps() end
            if S.phase ~= "done" then runBuild() end
          end)
          if ok then
            safeHome()
            if G.n == 0 then
              compactGaps()
              setStatus("done", "Build finished! " .. (S.placed or 0) .. " blocks placed.")
            else
              setStatus("docked", ("Built all I can. %d gaps left"):format(G.n))
            end
          elseif type(err) == "table" and err.abort then
            if err.abort == "short" or err.abort == "gapcap" then S.dryOut = true; save() end
            setStatus("returning", err.abort == "restock" and "Out of the next block"
              or err.abort == "fuel" and "Low on fuel"
              or err.abort == "short" and "Nothing left I can place: going home to wait for blocks"
              or err.abort == "gapcap" and ("%d gaps is my limit: going home to wait for blocks"):format(G.n)
              or "Stop requested")
            safeHome()
          else
            setStatus("error", tostring(err))
            pcall(goHome)
            waitFor(30)
          end
        end
      else
        setStatus("returning", "Heading home")
        safeHome()
      end
    else
      if not atDock() then setStatus("returning", "Heading home"); safeHome() end
      if S.phase == "done" and G.n == 0 then setStatus("done", "Build finished. " .. (S.placed or 0) .. " blocks placed.")
      elseif S.phase == "done" then
        setStatus("docked", ("Stopped with %d gaps left: say build to fill them"):format(G.n))
      elseif S.status ~= "docked" or not ((S.msg or ""):find("^Marker") or (S.msg or ""):find("stopped")) then
        setStatus("docked", "Waiting. Say: island weaver build | test | clear")
      end
      waitFor(10)
    end
  end
end

-- The Architect asks for the plan's shape and the site so it can draw him
local infoCache
local function answer(msg)
  if msg.what == "info" then
    if not infoCache then
      local ext = {}
      for i, e in ipairs(P.ext) do
        local wx, _, wz = toWorld(e[1], 0, e[2])
        ext[i] = { wx, wz, e[3] }
      end
      local i = P.info
      infoCache = {
        type = "info", id = os.getComputerID(), plan = i.name, layers = i.layers, blocks = i.blocks,
        ybase = i.ybase, topY = i.topY, minX = i.minX, maxX = i.maxX, minZ = i.minZ, maxZ = i.maxZ,
        palette = i.palette, bill = i.bill,
        site = { cx = C.cx, cz = C.cz, sea = C.sea, seabed = C.seabed, rot = C.rot or 0, cruise = C.cruise,
                 dx = C.dx, dy = C.dy, dz = C.dz, dh = C.dh, supplyDir = C.supplyDir, planFile = C.plan },
        bounds = bounds(), profile = RP.profile(P, C), ext = ext,
      }
    end
    return infoCache
  elseif msg.what == "layer" and tonumber(msg.n) and P.layers[tonumber(msg.n)] then
    return { type = "layer", id = os.getComputerID(), n = tonumber(msg.n), rows = P.layers[tonumber(msg.n)] }
  elseif msg.what == "gaps" then
    -- the gaps on one layer ({x, z} each), or the edge walls' (n = "ext")
    local cells = {}
    local y = msg.n ~= "ext" and tonumber(msg.n) and (layer1Y() + tonumber(msg.n) - 1)
    for _, g in pairs(G.list) do
      if (msg.n == "ext" and g.ext) or (y and g.y == y and not g.ext) then cells[#cells + 1] = { g.x, g.z } end
    end
    return { type = "gaps", id = os.getComputerID(), n = msg.n, ver = G.ver, cells = cells }
  end
end

local function netLoop()
  if not modem then return os.pullEvent("never") end
  rednet.open(peripheral.getName(modem))
  local lastSend = -100
  while true do
    local from, msg, proto = rednet.receive(nil, 1)
    if proto == "tanis-base" and type(msg) == "table" and msg.type == "storage" and type(msg.items) == "table" then
      stock, stockAt = msg.items, os.clock()      -- so he knows when a block he's waiting for turns up
    elseif proto == PROTOCOL and type(msg) == "table" then
      if msg.type == "cmd" then
        if type(msg.seq) == "number" and (not ctrl or type(ctrl.seq) ~= "number" or msg.seq > ctrl.seq) then ctrl = msg end
      elseif msg.type == "supplied" then inbox[#inbox + 1] = msg
      elseif msg.type == "reboot" and msg.to == os.getComputerID() and msg.token then
        rebootToken = msg.token
      elseif msg.type == "ask" and (msg.to == nil or msg.to == os.getComputerID()) and P then
        local ok, reply = pcall(answer, msg)
        if ok and reply then rednet.send(from, reply, PROTOCOL) end
      end
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
  print("WEAVER SETUP  (use F3 for coordinates)")
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
  if not found then error("No supply barrel next to me. Place one and run weaver again.", 0) end
  C.supplyDir = found
  writeT(CFG_FILE, C)
  clearGaps()
  save()
  print("Setup saved. Supply barrel found.")
  print("Next: island weaver test   (puts markers on the 8 corners)")
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
if args[1] == "setup" or not C then
  setup()
end

if not fs.exists("startup.lua") then
  local f = fs.open("startup.lua", "w"); f.write('shell.run("weaver")\n'); f.close()
end

P = loadPlan(C.plan)
for ch, name in pairs(P.info.palette) do PCH[name] = ch end
loadGaps(P.info.palette)
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

-- The build box and the chunks he'll fly through, so they can be chunk-loaded
do
  local b = bounds()
  local x1, x2 = math.min(b.x1 - 2, C.dx), math.max(b.x2 + 2, C.dx)
  local z1, z2 = math.min(b.z1 - 2, C.dz), math.max(b.z2 + 2, C.dz)
  local c1, c2, d1, d2 = math.floor(x1 / 16), math.floor(x2 / 16), math.floor(z1 / 16), math.floor(z2 / 16)
  print(("Box X %d..%d Z %d..%d"):format(b.x1, b.x2, b.z1, b.z2))
  print(("    Y %d (bottom) .. %d (top)"):format(b.y1, b.y2))
  print(("Chunks X %d..%d Z %d..%d (%d)"):format(c1, c2, d1, d2, (c2 - c1 + 1) * (d2 - d1 + 1)))
end
if chunkySlot() or sideOfType("chunky") then
  print("Chunk controller on board: I keep my own chunk loaded.")
  refreshChunk(true)
end
setStatus("docked", "Starting")
parallel.waitForAny(mainLoop, netLoop, gpsLoop)
