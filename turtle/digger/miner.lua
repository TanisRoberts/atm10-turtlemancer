-- miner.lua  --  shaft + expanding-square mining turtle (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: a mining turtle (diamond pickaxe) with a wireless or ender modem on its other side.
-- Dock: place the turtle where the shaft should start. Put the DUMP barrel (a storage input)
-- on one side and the FUEL barrel on another side (or above). Below must be free to dig.
--
-- What it does, once you press START on the panel:
--   * digs a shaft straight down from the dock to the chosen Y range
--   * mines expanding squares around the shaft (3x3, 5x5 ... up to 101x101), 3 levels per pass:
--     it walks the middle level and digs the block above/below only if it's an ore
--   * drops 3 levels and repeats until the range is done
--   * comes home through the shaft when full or low on fuel, unloads, refuels, goes back
--   * dumps junk (cobble, deepslate ...) underground once storage has 20 stacks of it
--   * saves its position after every move, so it resumes after chunk unloads / restarts
-- Hold Ctrl+T to stop the program (the turtle stays where it is).

local PROTOCOL     = "tanis-miner"
local STATE_FILE   = "miner.state"
local MAX_RING     = 50     -- 50 rings = 101x101
local FUEL_RESERVE = 60     -- spare fuel kept on top of the trip home
local STATUS_EVERY = 3      -- seconds between status broadcasts

-- Things that count as junk live in junk.txt (one item per line, # for comments).
-- Junk is carried home while storage still wants it (under its cap), up to 4 slots, else dumped.
-- Edit junk.txt any time: it's re-read every time Digger docks.
local JUNK_FILE = "junk.txt"
local DEFAULT_JUNK = [[
# Digger's junk list: blocks he may throw away underground.
# One item per line. "minecraft:" is optional. Lines starting with # are ignored.
# Junk still comes home (up to 4 slots) while storage has less than its cap of it.
# Ores, raw metals and gems always come home. Anything else (flint, dripstone...)
# gets thrown out when his bag is full, unless you add a "keep" line, e.g.:
#   keep flint
cobblestone
cobbled_deepslate
stone
deepslate
tuff
granite
diorite
andesite
calcite
dirt
gravel
sand
sandstone
netherrack
smooth_basalt
basalt
blackstone
mud
clay
]]
local JUNK, KEEP = {}, {}
local function loadJunk()
  if not fs.exists(JUNK_FILE) then
    local f = fs.open(JUNK_FILE, "w"); f.write(DEFAULT_JUNK); f.close()
  end
  local f = fs.open(JUNK_FILE, "r")
  local text = f.readAll(); f.close()
  local junk, keep = {}, {}
  for line in text:gmatch("[^\r\n]+") do
    local item = line:gsub("#.*", ""):match("^%s*(.-)%s*$")
    local isKeep = false
    if item:lower():sub(1, 5) == "keep " then isKeep = true; item = item:sub(6):match("^%s*(.-)%s*$") end
    if item ~= "" then
      if not item:find(":") then item = "minecraft:" .. item end
      if isKeep then keep[item] = true else junk[item] = true end
    end
  end
  JUNK, KEEP = junk, keep
end
loadJunk()

---------------------------------------------------------------------------
-- State (saved to disk after every move)
---------------------------------------------------------------------------
local S = {}
local function save()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize(S))
  f.close()
end
local function load()
  if not fs.exists(STATE_FILE) then return end
  local f = fs.open(STATE_FILE, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  if type(t) == "table" then S = t end
end

local ctrl = nil -- latest command from the panel (set by the network loop)

local function fuel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end
local function fuelLimit()
  local l = turtle.getFuelLimit()
  return l == "unlimited" and math.huge or l
end

local lastShown = ""
local function setStatus(st, msg)
  S.status, S.msg = st, msg or ""
  local line = st .. (S.msg ~= "" and (": " .. S.msg) or "")
  if line ~= lastShown then
    lastShown = line
    print(("[%s] %s"):format(textutils.formatTime(os.time(), true), line))
    if S.dockY then save() end
  end
end

---------------------------------------------------------------------------
-- Movement (position is relative to the dock: x/z flat, y up; heading 0 = facing at setup)
---------------------------------------------------------------------------
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }

local function apply(kind)
  if kind == "f" then S.x, S.z = S.x + DX[S.h], S.z + DZ[S.h]
  elseif kind == "u" then S.y = S.y + 1
  else S.y = S.y - 1 end
end

local OPS = {
  f = { move = turtle.forward, dig = turtle.dig,     detect = turtle.detect,     attack = turtle.attack },
  u = { move = turtle.up,      dig = turtle.digUp,   detect = turtle.detectUp,   attack = turtle.attackUp },
  d = { move = turtle.down,    dig = turtle.digDown, detect = turtle.detectDown, attack = turtle.attackDown },
}

-- Move one block, digging/attacking whatever is in the way.
-- The fuel level before the move is saved, so after a crash we can tell if the move happened.
local function move(kind)
  local op = OPS[kind]
  for _ = 1, 60 do
    if turtle.getFuelLevel() == 0 then return false, "Out of fuel" end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }
    save()
    if op.move() then
      apply(kind)
      S.pending = nil
      save()
      return true
    end
    S.pending = nil
    if op.detect() then
      local ok, why = op.dig()
      if not ok then
        why = tostring(why)
        if why:find("nbreakable") or why:find("ermission") or why:find("rotect") then save(); return false, why end
        if why:lower():find("tool") then save(); return false, "No pickaxe equipped" end
      end
    else
      op.attack() -- a mob, or falling sand/gravel mid-air
    end
  end
  save()
  return false, "Stuck"
end

local function turnRight()
  S.turning = true; save()
  turtle.turnRight()
  S.h = (S.h + 1) % 4; S.turning = nil; save()
end
local function turnLeft()
  S.turning = true; save()
  turtle.turnLeft()
  S.h = (S.h + 3) % 4; S.turning = nil; save()
end
local function face(h)
  local d = (h - S.h) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end

-- Walk to (tx, tz) on the current level, x first (or z first), calling onStep after each block.
local function goToXZ(tx, tz, onStep, zFirst)
  local function walkX()
    while S.x ~= tx do
      face(tx > S.x and 1 or 3)
      local ok, why = move("f"); if not ok then return false, why end
      if onStep then onStep() end
    end
    return true
  end
  local function walkZ()
    while S.z ~= tz do
      face(tz > S.z and 2 or 0)
      local ok, why = move("f"); if not ok then return false, why end
      if onStep then onStep() end
    end
    return true
  end
  local a, b = walkX, walkZ
  if zFirst then a, b = walkZ, walkX end
  local ok, why = a(); if not ok then return false, why end
  return b()
end

local function goY(ty)
  while S.y ~= ty do
    local ok, why = move(S.y < ty and "u" or "d")
    if not ok then return false, why end
  end
  return true
end

local function atDock() return S.x == 0 and S.y == 0 and S.z == 0 end

local function goHome()
  if S.x ~= 0 or S.z ~= 0 then
    local ok = goToXZ(0, 0)
    if not ok then
      local ok2, why = goToXZ(0, 0, nil, true)
      if not ok2 then error("Can't reach the shaft: " .. tostring(why), 0) end
    end
  end
  local ok, why = goY(0)
  if not ok then error("Shaft blocked: " .. tostring(why), 0) end
  face(0)
end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------
local function emptySlots()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end
  return n
end

local function dropAway()
  if not turtle.detectDown() then return turtle.dropDown() end
  if not turtle.detectUp() then return turtle.dropUp() end
  return turtle.drop()
end

-- Dump junk that storage already has plenty of (or all junk, if `all`)
local function dumpJunk(all)
  local capped = S.capped or {}
  if not all and not next(capped) then return end
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and JUNK[d.name] and (all or capped[d.name]) then
      turtle.select(s); dropAway()
    end
  end
  turtle.select(1)
end

-- Valuable = an ore product worth a trip home. Everything else can be dumped to make room.
local VALUE_TAGS = { "c:ores", "c:raw_materials", "c:gems", "c:dusts", "c:nuggets", "c:ingots",
  "minecraft:coals", "c:coal" }
local VALUE_NAMES = { "raw_", "_ore", "diamond", "emerald", "lapis", "redstone", "coal", "quartz",
  "amethyst_shard", "ancient_debris", "netherite", "nugget", "ingot", "gem", "crystal", "dust" }
local valuableCache = {}
local function isValuable(slot)
  local d = turtle.getItemDetail(slot)
  if not d then return false end
  local v = valuableCache[d.name]
  if v ~= nil then return v end
  if KEEP[d.name] then valuableCache[d.name] = true; return true end
  v = false
  local full = turtle.getItemDetail(slot, true)
  for _, t in ipairs(VALUE_TAGS) do if full and full.tags and full.tags[t] then v = true end end
  if not v and not JUNK[d.name] then
    for _, p in ipairs(VALUE_NAMES) do if d.name:find(p, 1, true) then v = true; break end end
  end
  valuableCache[d.name] = v
  return v
end

-- When slots run out: dump everything that isn't valuable, except up to KEEP_JUNK_SLOTS of
-- junk that storage still wants (under its 20-stack cap), fullest stacks first.
local KEEP_JUNK_SLOTS = 4
local function makeRoom()
  local capped, keep = S.capped or {}, {}
  local wanted = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and JUNK[d.name] and not capped[d.name] then wanted[#wanted + 1] = { s = s, n = d.count } end
  end
  table.sort(wanted, function(a, b) return a.n > b.n end)
  for i = 1, math.min(KEEP_JUNK_SLOTS, #wanted) do keep[wanted[i].s] = true end
  for s = 1, 16 do
    if turtle.getItemCount(s) > 0 and not keep[s] and not isValuable(s) then
      turtle.select(s); dropAway()
    end
  end
  turtle.select(1)
end

local function cargoFraction()
  local used, room = 0, 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      used = used + d.count
      room = room + d.count + turtle.getItemSpace(s)
    end
  end
  return room > 0 and used / room or 0
end

local function burnInventoryFuel(target)
  for s = 1, 16 do
    if fuel() >= target then break end
    local d = turtle.getItemDetail(s)
    if d and not JUNK[d.name] then
      turtle.select(s)
      if turtle.refuel(0) then turtle.refuel() end
    end
  end
  turtle.select(1)
end

local function dropTo(dir)
  if dir == "up" then return turtle.dropUp() end
  face(dir); return turtle.drop()
end
local function suckFrom(dir)
  if dir == "up" then return turtle.suckUp() end
  face(dir); return turtle.suck()
end

local function isOre(ok, d)
  if not ok or type(d) ~= "table" then return false end
  if d.tags and (d.tags["c:ores"] or d.tags["forge:ores"]) then return true end
  local n = d.name or ""
  return n:find("_ore$") ~= nil or n:find(":ore_") ~= nil or n == "minecraft:ancient_debris"
end

local function checkUpDown()
  if isOre(turtle.inspectUp()) then turtle.digUp(); S.ores = (S.ores or 0) + 1 end
  if isOre(turtle.inspectDown()) then turtle.digDown(); S.ores = (S.ores or 0) + 1 end
end

---------------------------------------------------------------------------
-- Commands from the panel
---------------------------------------------------------------------------
local function applyCtrl()
  if not ctrl or ctrl.seq == nil or ctrl.seq == S.seq then return end
  S.seq = ctrl.seq
  if ctrl.want == "run" then
    local changed = ctrl.minY ~= S.minY or ctrl.maxY ~= S.maxY
    if changed or S.done then
      S.layerIdx, S.k, S.step, S.done = 1, 1, 1, false
      if changed and S.want == "run" then S.regionChanged = true end
    end
    S.minY, S.maxY, S.want = ctrl.minY, ctrl.maxY, "run"
  else
    S.want = "dock"
  end
  save()
end

local function abort(reason, msg) error({ abort = reason, msg = msg }, 0) end

-- Called before every block of mining
local function checkpoint()
  applyCtrl()
  if S.want ~= "run" then abort("stop", "Stop requested") end
  if S.regionChanged then S.regionChanged = nil; abort("region") end
  dumpJunk(false)
  if emptySlots() <= 1 then
    makeRoom()
    if emptySlots() <= 1 then
      abort("full", ("Full of ore (%d%% of stacks)"):format(math.floor(cargoFraction() * 100)))
    end
  end
  local need = math.abs(S.x) + math.abs(S.z) + math.abs(S.y) + FUEL_RESERVE
  if fuel() < need then
    burnInventoryFuel(need + 400)
    if fuel() < need then abort("fuel", "Low on fuel") end
  end
end

local function waitCtrl(seconds)
  local t = os.clock() + seconds
  while os.clock() < t do
    if ctrl and ctrl.seq ~= S.seq then return end
    os.sleep(1)
  end
end

---------------------------------------------------------------------------
-- Mining plan
---------------------------------------------------------------------------
-- Layer centres (absolute Y). Each pass covers centre-1 .. centre+1.
local function layerList()
  local out = {}
  if not S.minY or not S.maxY then return out end
  local c = math.min(S.maxY - 1, S.dockY - 3)
  while c + 1 >= S.minY and c >= -63 do
    out[#out + 1] = c
    c = c - 3
  end
  return out
end

local function ringCells(k)
  local c = {}
  for z = -k, k do c[#c + 1] = { k, z } end
  for x = k - 1, -k, -1 do c[#c + 1] = { x, k } end
  for z = k - 1, -k, -1 do c[#c + 1] = { -k, z } end
  for x = -k + 1, k - 1 do c[#c + 1] = { x, -k } end
  return c
end

local function fuelToStart()
  local layers = layerList()
  local y = layers[S.layerIdx or 1] or layers[1] or S.dockY
  return 2 * (S.dockY - y) + 4 * (S.k or 1) + 500
end

local function mineRegion()
  local layers = layerList()
  S.layerCount = #layers
  if #layers == 0 then
    S.done = true; save()
    setStatus("error", "Range must be below the dock")
    return
  end
  for li = S.layerIdx or 1, #layers do
    S.layerIdx, S.layerY = li, layers[li]
    local cy = layers[li] - S.dockY
    setStatus("mining", ("Y %d"):format(layers[li]))
    -- Travel to the layer via the shaft
    if S.y ~= cy then
      if S.x ~= 0 or S.z ~= 0 then
        local ok, why = goToXZ(0, 0)
        if not ok then error("Can't reach the shaft: " .. tostring(why), 0) end
      end
      while S.y ~= cy do
        checkpoint()
        local ok, why = move(S.y > cy and "d" or "u")
        if not ok then error("Shaft blocked at Y " .. (S.dockY + S.y) .. ": " .. tostring(why), 0) end
      end
    end
    -- Expanding squares
    local blocked = false
    for k = S.k or 1, MAX_RING do
      S.k = k
      local cells = ringCells(k)
      for i = S.step or 1, #cells do
        S.step = i
        checkpoint()
        local ok = goToXZ(cells[i][1], cells[i][2], checkUpDown)
        if not ok then blocked = true; break end
      end
      if blocked then break end
      S.step = 1
    end
    if blocked then setStatus("mining", ("Hit unbreakable blocks at Y %d, next layer"):format(layers[li])) end
    S.k, S.step = 1, 1
    S.layerIdx = li + 1
    save()
  end
  S.done = true
  save()
end

---------------------------------------------------------------------------
-- Dock: unload, refuel
---------------------------------------------------------------------------
local function dockService()
  setStatus("docked", "Unloading")
  loadJunk()            -- pick up any edits to junk.txt
  valuableCache = {}
  local haul = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      turtle.select(s)
      if not JUNK[d.name] then haul[d.name] = (haul[d.name] or 0) + d.count end
      local tries = 0
      while turtle.getItemCount(s) > 0 do
        if not dropTo(S.dumpDir) then
          tries = tries + 1
          setStatus("waiting", "Dump barrel full, waiting")
          os.sleep(3)
          if tries > 10 then break end -- give up for now; the main loop waits at the dock
        end
      end
    end
  end
  if next(haul) then
    S.lastHaul = haul
    S.totals = S.totals or {}
    for n, c in pairs(haul) do S.totals[n] = (S.totals[n] or 0) + c end
  end
  S.ores = 0
  if emptySlots() < 16 then face(0); save(); return false end -- couldn't unload everything

  -- Refuel from the fuel barrel, taking only what fits in the tank
  local limit = fuelLimit()
  if limit ~= math.huge then
    setStatus("docked", "Refuelling")
    turtle.select(1)
    for _ = 1, 40 do
      if fuel() >= limit - 80 then break end
      if not suckFrom(S.fuelDir) then break end
      local returned = false
      if turtle.refuel(0) then
        local before = fuel()
        turtle.refuel(1)
        local per = fuel() - before
        if per > 0 then
          local n = math.floor((limit - fuel()) / per)
          if n > 0 then turtle.refuel(math.min(n, turtle.getItemCount(1))) end
        end
      end
      if turtle.getItemCount(1) > 0 then
        if turtle.refuel(0) then dropTo(S.fuelDir); returned = true -- leftover fuel goes back
        else dropTo(S.dumpDir) end                                -- empty buckets etc. to storage
      end
      if returned then break end
    end
  end
  face(0)
  save()
  return emptySlots() == 16 -- false if the dump barrel wouldn't take everything
end

---------------------------------------------------------------------------
-- First-time setup at the dock
---------------------------------------------------------------------------
local function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = d.name or ""
  return n:find("barrel") or n:find("chest") or (d.tags and (d.tags["c:barrels"] or d.tags["c:chests"]))
end

local function sideName(dir)
  if dir == "up" then return "above me" end
  return ({ [0] = "in front", "on my right", "behind me", "on my left" })[dir]
end

local function setupDock()
  term.clear(); term.setCursorPos(1, 1)
  print("MINER SETUP")
  print("I'm sitting on top of my future shaft.")
  print("I need two barrels next to me (sides or above):")
  print(" - DUMP barrel (a storage input, empty)")
  print(" - FUEL barrel (with some coal in it)")
  print()
  local y
  repeat
    write("My Y level (F3, block I'm in): ")
    y = tonumber(read())
  until y
  S = { dockY = math.floor(y), x = 0, y = 0, z = 0, h = 0, want = "dock", seq = nil }
  save()
  while true do
    local found = {}
    for _ = 0, 3 do
      if isContainer(turtle.inspect()) then found[#found + 1] = S.h end
      turnRight()
    end
    if isContainer(turtle.inspectUp()) then found[#found + 1] = "up" end
    local fuelDir, others = nil, {}
    turtle.select(1)
    for _, dir in ipairs(found) do
      if suckFrom(dir) then
        local isFuel = turtle.refuel(0)
        dropTo(dir)
        if isFuel and not fuelDir then fuelDir = dir else others[#others + 1] = dir end
      else
        others[#others + 1] = dir
      end
    end
    face(0)
    if fuelDir and #others >= 1 then
      S.fuelDir, S.dumpDir = fuelDir, others[1]
      print(("Fuel barrel: %s. Dump barrel: %s."):format(sideName(S.fuelDir), sideName(S.dumpDir)))
      break
    end
    printError(("Found %d barrel(s); fuel %s."):format(#found, fuelDir and "found" or "not found"))
    print("Put coal in the FUEL barrel, keep the DUMP barrel empty, then press Enter.")
    read()
  end
  save()
  print("Setup done. Press START on the panel.")
end

local function recover()
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
  save()
end

local function lostFlow()
  setStatus("lost", "Carry me back to the dock")
  print("I lost track of which way I'm facing (unloaded mid-turn).")
  print(("Put me back on the dock with the dump barrel %s,"):format(sideName(S.dumpDir)))
  print("then press Enter here.")
  read()
  S.x, S.y, S.z, S.h, S.lost = 0, 0, 0, 0, nil
  S.k, S.step = 1, 1
  save()
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
local function safeHome()
  local ok, err = pcall(goHome)
  if not ok then setStatus("error", tostring(err)); save() end
  return ok
end

local function runOnce()
  if atDock() then
    if not dockService() then
      setStatus("waiting", "Dump barrel full. Is storage running?")
      waitCtrl(15)
      return
    end
    local need = fuelToStart()
    if fuel() < need then
      setStatus("waiting", ("Need %d fuel, have %d"):format(need, fuel()))
      waitCtrl(15)
      return
    end
  end
  setStatus("mining", "")
  local ok, err = pcall(mineRegion)
  if ok then return end
  if type(err) == "table" and err.abort then
    if err.abort == "region" then return end
    setStatus("returning", err.msg or "")
    safeHome()
  else
    setStatus("error", tostring(err)); save()
    safeHome()
    waitCtrl(30)
  end
end

local function mainLoop()
  while true do
    applyCtrl()
    if S.lost then
      lostFlow()
    elseif S.want ~= "run" or S.done then
      if not atDock() then setStatus("returning", "Heading home"); safeHome() end
      if atDock() then
        dockService()
        setStatus("docked", S.done and "Range finished. Pick a new one." or "Waiting for START")
      end
      waitCtrl(10)
    else
      runOnce()
    end
  end
end

---------------------------------------------------------------------------
-- Network: status out, commands in
---------------------------------------------------------------------------
local function statusMsg()
  local used = 16 - emptySlots()
  local haul = {}
  for n, c in pairs(S.lastHaul or {}) do haul[#haul + 1] = { n, c } end
  table.sort(haul, function(a, b) return a[2] > b[2] end)
  while #haul > 8 do table.remove(haul) end
  local f, l = turtle.getFuelLevel(), turtle.getFuelLimit()
  return {
    type = "status", id = os.getComputerID(), label = os.getComputerLabel(),
    state = S.status, msg = S.msg, seq = S.seq,
    fuel = f, fuelLimit = l, slots = used,
    y = S.dockY and (S.dockY + (S.y or 0)), x = S.x, z = S.z,
    layer = S.layerIdx, layers = S.layerCount, ring = S.k, maxRing = MAX_RING,
    minY = S.minY, maxY = S.maxY, want = S.want, done = S.done, ores = S.ores, haul = haul,
  }
end

local function netLoop()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then
    print("No wireless modem: running without the panel.")
    return os.pullEvent("never")
  end
  rednet.open(peripheral.getName(modem))
  local lastSend = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "cmd" then
      ctrl = msg
      if type(msg.capped) == "table" then
        local set = {}
        for _, n in ipairs(msg.capped) do set[n] = true end
        S.capped = set
      end
    end
    if os.clock() - lastSend >= STATUS_EVERY then
      rednet.broadcast(statusMsg(), PROTOCOL)
      lastSend = os.clock()
    end
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
if not fs.exists("startup.lua") then -- auto-resume after chunk reloads and restarts
  local f = fs.open("startup.lua", "w"); f.write('shell.run("miner")\n'); f.close()
end
load()
if not S.dockY then setupDock() else recover() end
setStatus("docked", "Starting")
parallel.waitForAny(mainLoop, netLoop)
