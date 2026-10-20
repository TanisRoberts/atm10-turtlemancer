-- miner_inv.lua  --  his slots: gear, junk, what's valuable, making room; chests (emptied before they're dug);
-- chunk loading (core.chunk); the shulker box. A part of miner.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------
function emptySlots()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end
  return n
end

-- Gear: things I carry for myself and never unload, stash or throw away
function isBox(name) return type(name) == "string" and name:find("shulker_box", 1, true) ~= nil end
function isGear(name) return name == core.chunk.ITEM or core.chunk.isModem(name) or isBox(name) end
function freeSlot()
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then return s end end
end

function dropAway()
  if not turtle.detectDown() then return turtle.dropDown() end
  if not turtle.detectUp() then return turtle.dropUp() end
  return turtle.drop()
end

-- Dump junk that storage already has plenty of (or all junk, if `all`)
function dumpJunk(all)
  local capped = S.capped or {}
  if not all and not next(capped) then return end
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and JUNK[d.name] and (all or capped[d.name]) and not (S.loot and S.loot[d.name]) then
      turtle.select(s); dropAway()
    end
  end
  turtle.select(1)
end

-- Valuable = an ore product worth a trip home. Everything else can be dumped to make room.
VALUE_TAGS = { "c:ores", "c:raw_materials", "c:gems", "c:dusts", "c:nuggets", "c:ingots",
  "minecraft:coals", "c:coal" }
-- "computercraft:" = a turtle/computer picked up by an older Canary: always brought home, never dumped
VALUE_NAMES = { "computercraft:", "cable", "raw_", "_ore", "diamond", "emerald", "lapis", "redstone", "coal", "quartz",
  "amethyst_shard", "ancient_debris", "netherite", "nugget", "ingot", "gem", "crystal", "dust", "gilded",
  "glowstone", "shroomlight" }
valuableCache = {}
function isValuable(slot)
  local d = turtle.getItemDetail(slot)
  if not d then return false end
  if S.loot and S.loot[d.name] then return true end -- out of a chest: always comes home
  if isGear(d.name) then return true end
  local v = valuableCache[d.name]
  if v ~= nil then return v end
  if KEEP[d.name] or d.name == BUCKET or d.name == LAVA_BUCKET then valuableCache[d.name] = true; return true end
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
KEEP_JUNK_SLOTS = 4
function makeRoom()
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

function cargoFraction()
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

function burnInventoryFuel(target) core.fuel.refuelFromInventory(target) end

function dropTo(dir, n)
  if dir == "up" then return turtle.dropUp(n) end
  face(dir); return turtle.drop(n)
end
function suckFrom(dir, n)
  if dir == "up" then return turtle.suckUp(n) end
  face(dir); return turtle.suck(n)
end

function isOre(ok, d)
  if not ok or type(d) ~= "table" then return false end
  if d.tags and (d.tags["c:ores"] or d.tags["forge:ores"]) then return true end
  local n = d.name or ""
  return n:find("_ore$") ~= nil or n:find(":ore_") ~= nil or n == "minecraft:ancient_debris"
    or n == "minecraft:gilded_blackstone"
end

---------------------------------------------------------------------------
-- Chests: empty them before digging (a dug chest spills its loot on the floor, and I'd walk on)
---------------------------------------------------------------------------
SUCK = { f = turtle.suck, u = turtle.suckUp, d = turtle.suckDown }
function countsBySlot()
  local c = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    c[s] = d and { d.name, d.count } or false
  end
  return c
end

-- Take everything out of the container on that side. Everything taken that isn't on my junk list
-- is marked as loot (always comes home, never thrown away). True when it's empty; false if I filled up first (after making
-- room by throwing junk away).
lootAt = function(kind)
  local took, roomMade, stashed = 0, false, false
  turtle.select(1)
  while true do
    local before = countsBySlot()
    if SUCK[kind]() then
      took = took + 1
      S.loot = S.loot or {}
      for s = 1, 16 do
        local d = turtle.getItemDetail(s)
        -- (junk out of a chest is still junk: netherrack in a fortress chest gets no free ride home)
        if d and not JUNK[d.name] and (not before[s] or before[s][1] ~= d.name or before[s][2] < d.count) then
          S.loot[d.name] = true
        end
      end
      S.lootItems = (S.lootItems or 0) + 1
      save()
    elseif emptySlots() > 0 then
      -- Room to spare and nothing came out: it's empty
      if took > 0 then
        S.chests = (S.chests or 0) + 1
        setStatus(S.status or "mining", ("Emptied a chest (%d stack%s)"):format(took, took == 1 and "" or "s"))
      end
      return true
    elseif not roomMade then
      makeRoom(); roomMade = true
    elseif not stashed and stash then
      -- Into the shulker box with what I've got (it won't go where the chest is: up/down/behind)
      stashed = true
      if stash() then roomMade, stashed = false, false end
    else
      setStatus(S.status or "mining", "Full, with a chest still to empty")
      return false
    end
  end
end

-- A chest just above or below my tunnel: empty it and leave it standing (only with room to spare)
function lootUpDown()
  for _, k in ipairs({ "u", "d" }) do
    if emptySlots() > 2 and isLootable(k, OPS[k].inspect()) then lootAt(k) end
  end
end

function checkUpDown()
  if isOre(turtle.inspectUp()) then turtle.digUp(); S.ores = (S.ores or 0) + 1 end
  if isOre(turtle.inspectDown()) then turtle.digDown(); S.ores = (S.ores or 0) + 1 end
  lootUpDown()
  lookForLava()
end

---------------------------------------------------------------------------
-- Chunk loader: core.chunk (shared/turtlecore_chunk.lua) swaps a chunk controller onto my modem's side in
-- every new chunk (and every 45 s), so only the chunk I'm in is force-loaded. No controller: keep my area
-- loaded (or stay near it).
---------------------------------------------------------------------------
function haveChunky() return core.chunk.have() end
function chunkKey()
  local x, _, z = absPos()
  if not x then return nil end
  return math.floor(x / 16) .. "," .. math.floor(z / 16)
end

refreshChunk = function(force)
  if not S.chunky then return end
  local before = core.chunk.swaps
  core.chunk.ensure(chunkKey(), force)
  S.chunkyNote = core.chunk.note
  if core.chunk.swaps ~= before then S.swaps = (S.swaps or 0) + 1 end
end

-- Boot: a swap that was cut short leaves the modem in my bag and the controller on. Put it back.
function restoreRadio()
  if core.chunk.restore(S.swapSide) then print("Put my modem back on (a chunk swap was cut short).") end
  S.swapSide = nil
  save()
end

---------------------------------------------------------------------------
-- Shulker box: carried along as extra cargo space. Running out of slots, I put it down (above, below
-- or behind me), put my ore in, and dig it back up (it keeps what's in it). At the dock I unpack it.
-- Any shulker box works; Sophisticated Storage ones can be upgraded (bigger, stack upgrades).
---------------------------------------------------------------------------
BOXPLACE = { f = turtle.place, u = turtle.placeUp, d = turtle.placeDown }
BOXDROP = { f = turtle.drop,  u = turtle.dropUp,  d = turtle.dropDown }
BOXDIG = { f = turtle.dig,   u = turtle.digUp,   d = turtle.digDown }
BOXDET = { f = turtle.detect, u = turtle.detectUp, d = turtle.detectDown }
function boxSlot()
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and isBox(d.name) then return s end end
end
-- Things that stay in my slots: gear, and Firecrest's bucket
function isKept(name)
  return isGear(name) or (MODE.nether and (name == BUCKET or name == LAVA_BUCKET))
end

-- Pick the box back up (also after a restart mid-stash: S.boxAt says where it is)
function pickUpBox()
  local k = S.boxAt
  if not k then return true end
  if k == "f" and S.boxH then face(S.boxH) end
  local fs = freeSlot()
  if fs then turtle.select(fs) end
  local ok = BOXDIG[k]()
  turtle.select(1)
  if ok or not BOXDET[k]() then S.boxAt, S.boxH = nil, nil; save() end
  return S.boxAt == nil
end

stash = function()
  local bs = boxSlot()
  if not bs or S.boxFull then return false end
  local oh, k = S.h, nil
  if not BOXDET.u() then k = "u" elseif not BOXDET.d() then k = "d" end
  if not k then
    face((S.h + 2) % 4)                    -- the cell I just came from is open
    if not BOXDET.f() then k = "f" end
  end
  if not k then face(oh); return false end
  turtle.select(bs)
  if not BOXPLACE[k]() then turtle.select(1); face(oh); return false end
  S.boxAt, S.boxH = k, S.h; save()
  local full, moved = false, 0
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isKept(d.name) and isValuable(s) then
      turtle.select(s)
      while turtle.getItemCount(s) > 0 do
        if not BOXDROP[k]() then full = true; break end
      end
      moved = moved + 1
    end
  end
  pickUpBox()
  face(oh)
  if full then S.boxFull = true end
  S.boxStacks = (S.boxStacks or 0) + moved
  setStatus(S.status or "mining", full and "Shulker box full" or ("Put %d stacks in my shulker box"):format(moved))
  save()
  return moved > 0
end

