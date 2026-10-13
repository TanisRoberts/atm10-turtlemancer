-- farmer.lua  --  Figger, the crop farmer (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: a turtle with a diamond hoe and a wireless (or ender) modem.
-- Farm:  Figger flies one block above the crops. Mark the farm's edge with slabs at crop
--        height (one block above the farmland), so the slabs sit right under him at the edge.
--        Place him inside the farm, at flying height, next to his dock barrel.
-- Dock:  a barrel next to him, on the storage network with 1 coal in it at /setup time.
--
-- What he does every round:
--   * ripe crops: harvest and replant the same crop (wheat, carrots, potatoes, beetroot,
--     nether wart, Mystical Agriculture crops...)
--   * empty farmland: plant it (the crop that grew there before, else the farm's main crop)
--   * bare dirt in the farm: hoe it and plant it
--   * pumpkins and melons: harvest them (stems stay)
--   * picks up whatever lands on the ground (ATM10's right-click harvest drops crops there)
--   * then unload at the dock (keeps a stack of each seed) and refuel; unloads mid-round if full
--   * re-maps the farm every few rounds, so an extended field is picked up by itself
-- Commands (chat: island figger <cmd>, or here: farmer <cmd>):
--   rounds  go now     survey  re-map the farm     stop  stay docked     go  back on schedule

local PROTOCOL    = "tanis-farm"
local ROLE        = "farmer"
local STATE_FILE  = "farmer.state"
local ZONE_FILE   = "farmer.zone"
local ROUND_EVERY = 600     -- seconds between rounds
local MAX_REACH   = 32
local KEEP_SEEDS  = 64
local FUEL_TARGET = 3000
-- Zone format version. v1 zones could have real plots wrongly marked "skip" (see rounds), so an
-- older zone is re-surveyed once on start.
local ZONE_VERSION = 2
-- Re-map the farm every this many rounds, so a field that's been extended gets picked up by itself
local RESURVEY_EVERY = 6

local args = { ... }

local function readT(p)
  if not fs.exists(p) then return nil end
  local f = fs.open(p, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  return type(t) == "table" and t or nil
end
local function writeT(p, t) local f = fs.open(p, "w"); f.write(textutils.serialize(t)); f.close() end

local S = readT(STATE_FILE) or {}
local Z = readT(ZONE_FILE)   -- { cells = {["x,z"]="plot"/"skip"/"border"/"blocked"/"dock"}, crop = {["x,z"]=seed}, plots = {...}, dockDir }
local function save() writeT(STATE_FILE, S) end

local NAME = os.getComputerLabel() or "Figger"
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
-- Movement
---------------------------------------------------------------------------
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local function key(x, z) return x .. "," .. z end
local function unkey(k) local x, z = k:match("^(%-?%d+),(%-?%d+)$"); return tonumber(x), tonumber(z) end

local function apply(kind)
  if kind == "f" then S.x, S.z = S.x + DX[S.h], S.z + DZ[S.h]
  elseif kind == "b" then S.x, S.z = S.x - DX[S.h], S.z - DZ[S.h]
  elseif kind == "u" then S.y = S.y + 1
  else S.y = S.y - 1 end
end

local OPS = {
  f = { move = turtle.forward, inspect = turtle.inspect, attack = turtle.attack },
  b = { move = turtle.back },
  u = { move = turtle.up, inspect = turtle.inspectUp, attack = turtle.attackUp },
  d = { move = turtle.down, inspect = turtle.inspectDown, attack = turtle.attackDown },
}

local TOPS_CUT = 0
-- Plants that may stick up into his flying layer (2-tall hemp, tall grass, flowers).
local function isPlantInWay(d)
  if type(d) ~= "table" then return false end
  local n, t = tostring(d.name), d.tags or {}
  if n:find("hemp") or n:find("tall_grass") or n:find("large_fern") then return true end
  if d.state and d.state.age ~= nil and not n:find("stem") then return true end
  return t["minecraft:crops"] or t["minecraft:replaceable"] or t["minecraft:flowers"]
    or t["minecraft:tall_flowers"] or t["c:crops"] or false
end

local function move(kind)
  local op = OPS[kind]
  for _ = 1, 10 do
    if turtle.getFuelLevel() == 0 then return false, "Out of fuel" end
    S.pending = { kind = kind, fuel = turtle.getFuelLevel() }
    save()
    if op.move() then apply(kind); S.pending = nil; save(); return true end
    S.pending = nil
    if op.inspect then
      local ok, d = op.inspect()
      if ok and kind == "f" and isPlantInWay(d) then
        if turtle.dig() then TOPS_CUT = TOPS_CUT + 1 end  -- tall crop top (hemp etc.) at flying height: harvest it, fly on
        turtle.suck()
      elseif ok then save(); return false, "Blocked by " .. tostring(d.name) end
      op.attack()
    end
    os.sleep(0.5)
  end
  save()
  return false, "Something keeps getting in the way"
end

local function turnRight() S.turning = true; save(); turtle.turnRight(); S.h = (S.h + 1) % 4; S.turning = nil; save() end
local function turnLeft()  S.turning = true; save(); turtle.turnLeft();  S.h = (S.h + 3) % 4; S.turning = nil; save() end
local function face(h)
  local d = (h - S.h) % 4
  if d == 1 then turnRight() elseif d == 2 then turnRight(); turnRight() elseif d == 3 then turnLeft() end
end
local function dirTo(x, z)
  for h = 0, 3 do if S.x + DX[h] == x and S.z + DZ[h] == z then return h end end
end
local function fuel()
  local f = turtle.getFuelLevel()
  return f == "unlimited" and math.huge or f
end

---------------------------------------------------------------------------
-- Crops
---------------------------------------------------------------------------
local MAX_AGE = { ["minecraft:beetroots"] = 3, ["minecraft:nether_wart"] = 3, ["minecraft:sweet_berry_bush"] = 3,
  ["minecraft:torchflower_crop"] = 2, ["minecraft:cocoa"] = 2 }
local SEED = { ["minecraft:wheat"] = "minecraft:wheat_seeds", ["minecraft:carrots"] = "minecraft:carrot",
  ["minecraft:potatoes"] = "minecraft:potato", ["minecraft:beetroots"] = "minecraft:beetroot_seeds",
  ["minecraft:nether_wart"] = "minecraft:nether_wart", ["minecraft:torchflower_crop"] = "minecraft:torchflower_seeds",
  ["immersiveengineering:hemp"] = "immersiveengineering:seed" }
-- Crops whose bottom block stays and regrows: only the top (at his flying height) is harvested.
local KEEP_BOTTOM = { ["immersiveengineering:hemp"] = true }
local SEED_ITEMS = {}
for _, s in pairs(SEED) do SEED_ITEMS[s] = true end

local function seedFor(blockName)
  blockName = tostring(blockName)
  if SEED[blockName] then return SEED[blockName] end
  if blockName:find("hemp") then return "immersiveengineering:seed" end
  local base = blockName:match("^(.-)_crop$")      -- Mystical Agriculture & friends: x_crop -> x_seeds
  if base then return base .. "_seeds" end
end

local function isSeedItem(n) n = tostring(n); return SEED_ITEMS[n] or n:find("_seeds$") ~= nil end

local function isCrop(d)
  if type(d) ~= "table" then return false end
  if tostring(d.name):find("hemp") then return true end
  return d.state and d.state.age ~= nil and seedFor(d.name) ~= nil
end
local function isRipe(d)
  return isCrop(d) and not KEEP_BOTTOM[d.name] and not tostring(d.name):find("hemp")
    and d.state.age >= (MAX_AGE[d.name] or 7)
end
local function isGourd(n) n = tostring(n); return (n:find("pumpkin") or n:find("melon")) and not n:find("stem") and not n:find("carved") end

local function selectItem(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then turtle.select(s); return true end
  end
  return false
end

local function countWhere(pred)
  local c = 0
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and pred(d.name) then c = c + d.count end end
  return c
end

---------------------------------------------------------------------------
-- Base link
---------------------------------------------------------------------------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
local ctrl = nil
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
  return { type = "status", role = ROLE, id = os.getComputerID(), label = NAME, state = S.status, msg = S.msg,
    fuel = turtle.getFuelLevel(), fuelLimit = turtle.getFuelLimit(), plots = Z and #Z.plots or 0,
    lastHaul = S.lastHaul, paused = S.paused, seq = S.seq, lastRound = S.lastRound, pos = gpsNow(),
    nextRound = S.nextRound and math.max(0, math.floor(S.nextRound - os.clock())) }
end

---------------------------------------------------------------------------
-- Survey
---------------------------------------------------------------------------
local function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = tostring(d.name); return n:find("barrel") or n:find("chest")
end

local stemAt = {}
local dockCell = nil
local function survey(sameFrame)
  setStatus("surveying", "Mapping the farm")
  -- A survey always starts fresh from where he stands: that spot becomes 0,0, facing "north"
  S.x, S.y, S.z, S.h = 0, 0, 0, 0
  save()
  local cells, crop = {}, {}
  stemAt = {}
  dockCell = nil
  local dockDir, gap = nil, false

  local function classify(k)
    local ok, d = turtle.inspectDown()
    if ok and tostring(d.name):find("slab") then return "border" end
    if isContainer(ok, d) then                       -- a dock barrel built into the border
      if not dockCell then dockCell = k end
      return "dock"
    end
    if not ok then return "plot" end
    if isCrop(d) then crop[k] = seedFor(d.name); return "plot" end
    if tostring(d.name):find("stem") then stemAt[k] = true; return "plot" end
    if isGourd(d.name) then return "gourd" end
    return "skip"
  end

  -- Fuel check before wandering anywhere: burn anything burnable he's carrying first
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isSeedItem(d.name) and fuel() < 2000 then
      turtle.select(s)
      if turtle.refuel(0) then turtle.refuel() end
    end
  end
  turtle.select(1)
  if fuel() < 300 then
    error(("Only %d fuel. Give me some coal (put it in my inventory) and say: island %s survey"):format(fuel(), NAME:lower()), 0)
  end

  cells[key(0, 0)] = classify(key(0, 0))
  if cells[key(0, 0)] == "border" then error("I'm sitting over the border. Put me inside the farm.", 0) end
  if cells[key(0, 0)] == "dock" then
    -- Started on top of the dock, facing into the farm: step in and map from there
    face(0)
    local ok, why = move("f")
    if not ok then error("I start on my dock facing into the farm, but couldn't step forward (" .. tostring(why) .. ")", 0) end
    local k = key(S.x, S.z)
    cells[k] = classify(k)
    if cells[k] == "border" or cells[k] == "dock" then
      error("Facing the wrong way: put me on my dock facing INTO the farm.", 0)
    end
  end
  -- Find the dock first, from the starting spot
  for h = 0, 3 do
    face(h)
    local ok, d = turtle.inspect()
    if isContainer(ok, d) then dockDir = h; cells[key(DX[h], DZ[h])] = "dock"; break end
  end

  local function visit()
    for h = 0, 3 do
      local nx, nz = S.x + DX[h], S.z + DZ[h]
      local k = key(nx, nz)
      if cells[k] == nil then
        if math.abs(nx) > MAX_REACH or math.abs(nz) > MAX_REACH then gap = true; return end
        face(h)
        local okF, dF = turtle.inspect()
        if okF and isContainer(okF, dF) and not dockDir and S.x == 0 and S.z == 0 then
          cells[k] = "dock"; dockDir = h
        elseif okF and not isPlantInWay(dF) then
          cells[k] = "blocked"
        elseif move("f") then              -- move() harvests a tall-crop top in the way
          local kind = classify(k)
          cells[k] = kind
          if kind ~= "border" and kind ~= "dock" then visit() end
          face((h + 2) % 4)          -- always fly back, even after finding a gap
          local back, why = move("f")
          if not back then
            error(("Couldn't get back to %d,%d during the survey (%s)"):format(S.x + DX[S.h], S.z + DZ[S.h], tostring(why)), 0)
          end
          if gap then return end
        else
          cells[k] = "blocked"
        end
      end
    end
  end
  visit()
  face(0)
  if gap then error("The slab border has a gap (farm runs past " .. MAX_REACH .. " blocks). Fix it and survey again.", 0) end
  local home = key(0, 0)
  if not dockDir then
    local ok, d = turtle.inspectUp()
    if isContainer(ok, d) then dockDir = "up" end
  end
  if not dockDir and dockCell then
    home, dockDir = dockCell, "down"      -- dock in the border: hover above it and use it from the top
    cells[home] = "dock"
  end
  if not dockDir then error("No dock barrel next to my starting spot or in the border.", 0) end

  -- Spots next to pumpkin/melon stems are where the fruit grows: never plant or hoe them
  local stems = {}
  for k, kind in pairs(cells) do
    if kind == "plot" then
      local x, z = unkey(k)
      if stemAt and stemAt[k] then stems[#stems + 1] = { x, z } end
    end
  end
  for _, s in ipairs(stems) do
    for h = 0, 3 do
      local nk = key(s[1] + DX[h], s[2] + DZ[h])
      if cells[nk] == "plot" and not crop[nk] and not (stemAt and stemAt[nk]) then cells[nk] = "gourd" end
    end
  end

  -- Main crop = most common one
  local tally, main, best = {}, nil, 0
  for _, s in pairs(crop) do tally[s] = (tally[s] or 0) + 1; if tally[s] > best then best, main = tally[s], s end end
  -- Visiting order: rows, alternating direction
  local plots = {}
  for k, kind in pairs(cells) do if kind == "plot" or kind == "gourd" then plots[#plots + 1] = k end end
  table.sort(plots, function(a, b)
    local ax, az = unkey(a); local bx, bz = unkey(b)
    if az ~= bz then return az < bz end
    if az % 2 == 0 then return ax < bx else return ax > bx end
  end)
  -- Keep what he learned about plots' crops across re-maps (a bare plot remembers its last crop),
  -- as long as the new map uses the same frame (re-mapped from his old 0,0)
  if Z and Z.crop and (Z.home or key(0, 0)) == key(0, 0) and sameFrame then
    for k, s in pairs(Z.crop) do if cells[k] == "plot" and not crop[k] then crop[k] = s end end
  end
  Z = { cells = cells, crop = crop, plots = plots, dockDir = dockDir, main = main, home = home, v = ZONE_VERSION }
  writeT(ZONE_FILE, Z)
  setStatus("docked", ("Farm mapped: %d plots%s"):format(#plots, main and (", mostly " .. main:gsub("^.-:", "")) or ""))
end

---------------------------------------------------------------------------
-- Getting around (flying above the crops)
---------------------------------------------------------------------------
local tempBlocked = {}
local function flyable(k)
  local c = Z.cells[k]
  return (c == "plot" or c == "skip" or c == "gourd" or k == Z.home) and not tempBlocked[k]
end

local function path(fromK, goalK)
  local prev, q, head = { [fromK] = false }, { fromK }, 1
  while head <= #q do
    local k = q[head]; head = head + 1
    if k == goalK then
      local out = {}
      while k ~= fromK do table.insert(out, 1, k); k = prev[k] end
      return out
    end
    local x, z = unkey(k)
    for h = 0, 3 do
      local nk = key(x + DX[h], z + DZ[h])
      if prev[nk] == nil and flyable(nk) then prev[nk] = k; q[#q + 1] = nk end
    end
  end
end

local function goTo(goalK)
  for _ = 1, 6 do
    local p = path(key(S.x, S.z), goalK)
    if not p then return false end
    local ok = true
    for _, k in ipairs(p) do
      local x, z = unkey(k)
      face(dirTo(x, z))
      if not move("f") then tempBlocked[k] = true; ok = false; break end
    end
    if ok then return true end
  end
  return false
end

local function goHome()
  while S.y > 0 do if not move("d") then break end end
  while S.y < 0 do if not move("u") then break end end
  local home = Z.home or key(0, 0)
  if key(S.x, S.z) == home then return true end
  if not goTo(home) then
    tempBlocked = {}
    if not goTo(home) then error("Can't find my way home", 0) end
  end
  return true
end

-- Re-map from home. Home is normally his old 0,0, so facing "north" keeps the same frame. If his
-- dock is in the border and the first survey started elsewhere, face into the farm from the dock
-- instead (the map is then rebuilt from the dock, in a new frame).
local function resurvey()
  if Z then pcall(goHome) end            -- no map yet (a failed survey): map from where he is
  local same = (Z == nil) or (Z.home or key(0, 0)) == key(0, 0)
  if same then face(0)
  else
    local hx, hz = unkey(Z.home)
    for h = 0, 3 do
      local c = Z.cells[key(hx + DX[h], hz + DZ[h])]
      if c == "plot" or c == "skip" or c == "gourd" then face(h); break end
    end
  end
  survey(same)
end

---------------------------------------------------------------------------
-- A round
---------------------------------------------------------------------------
local function plantHere(k)
  local seed = Z.crop[k] or Z.main
  local tries = {}
  if seed then tries[#tries + 1] = seed end
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and isSeedItem(d.name) and d.name ~= seed then tries[#tries + 1] = d.name end
  end
  local hadAny = false
  for _, sd in ipairs(tries) do
    if selectItem(sd) then
      hadAny = true
      if turtle.placeDown() then Z.crop[k] = sd; turtle.select(1); return "planted" end
    end
  end
  turtle.select(1)
  if not hadAny then return "noseed" end   -- out of seeds: not the plot's fault
  return "failed"
end

-- Harvest drops can land on the ground instead of in his inventory: with a hoe, CC:Tweaked
-- right-clicks the crop before digging it, and ATM10 treats a right-click on a ripe crop as a
-- harvest (crop replanted at age 0, items dropped on the farmland). So always hoover up below.
local function pickUp()
  local got = false
  for _ = 1, 6 do if turtle.suckDown() then got = true else break end end
  return got
end
local function freeSlots()
  local n = 0
  for s = 1, 16 do if turtle.getItemCount(s) == 0 then n = n + 1 end end
  return n
end

local dock   -- defined below; rounds unloads mid-round when he's full

local function rounds()
  setStatus("working", "Doing my rounds")
  tempBlocked = {}
  TOPS_CUT = 0
  local harvested, planted, tilled, noSeed, changed = 0, 0, 0, false, false
  for _, k in ipairs(Z.plots) do
    if ctrl and ctrl.seq ~= S.seq and (ctrl.want == "stop" or ctrl.want == "survey") then break end
    if freeSlots() < 2 then             -- full: unload, then carry on where he was
      goHome(); dock(); setStatus("working", "Doing my rounds")
    end
    local kind = Z.cells[k]
    if kind == "gourd" and goTo(k) then
      local ok, d = turtle.inspectDown()
      if ok and isGourd(d.name) then turtle.digDown(); harvested = harvested + 1 end
      pickUp()
    elseif kind == "plot" and goTo(k) then
      pickUp()                          -- anything lying here from before
      local ok, d = turtle.inspectDown()
      if ok and isRipe(d) then
        turtle.digDown()
        harvested = harvested + 1
        Z.crop[k] = seedFor(d.name)
        pickUp()
        local okA, dA = turtle.inspectDown()
        if okA and isCrop(dA) then
          planted = planted + 1         -- right-click harvest already replanted it
        else
          local r = plantHere(k)
          if r == "planted" then planted = planted + 1 elseif r == "noseed" then noSeed = true end
        end
      elseif ok and isGourd(d.name) then
        turtle.digDown(); harvested = harvested + 1
        pickUp()
      elseif not ok then
        local r = plantHere(k)
        if r == "planted" then planted = planted + 1
        elseif r == "noseed" then noSeed = true
        else
          -- No farmland: drop in, hoe the dirt, plant, come back up
          if move("d") then
            local tilledOk = turtle.digDown()
            if move("u") and tilledOk then
              tilled = tilled + 1
              r = plantHere(k)
              if r == "planted" then planted = planted + 1 end
            end
            if r ~= "planted" then
              local okB, dB = turtle.inspectDown()
              if not (okB and isCrop(dB)) then Z.cells[k] = "skip"; changed = true end
            end
          else
            -- Only write a plot off if there's really nothing farmable down there (never a crop)
            local okB, dB = turtle.inspectDown()
            if not (okB and isCrop(dB)) then Z.cells[k] = "skip"; changed = true end
          end
        end
      end
      if fuel() < 60 then break end
    end
  end
  if changed then writeT(ZONE_FILE, Z) end
  harvested = harvested + TOPS_CUT
  S.lastRound = { harvested = harvested, planted = planted, tilled = tilled }
  return harvested, planted, noSeed
end

---------------------------------------------------------------------------
-- Dock
---------------------------------------------------------------------------
local function faceDock() if Z.dockDir ~= "up" and Z.dockDir ~= "down" then face(Z.dockDir) end end
local function dropDock(n) if Z.dockDir == "up" then return turtle.dropUp(n) elseif Z.dockDir == "down" then return turtle.dropDown(n) end return turtle.drop(n) end
local function suckDock() if Z.dockDir == "up" then return turtle.suckUp() elseif Z.dockDir == "down" then return turtle.suckDown() end return turtle.suck() end

dock = function()
  setStatus("docked", "Unloading")
  faceDock()
  local kept, haul = {}, {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      turtle.select(s)
      if isSeedItem(d.name) or SEED_ITEMS[d.name] then
        local room = KEEP_SEEDS - (kept[d.name] or 0)
        local keep = math.max(0, math.min(room, d.count))
        kept[d.name] = (kept[d.name] or 0) + keep
        if d.count > keep then haul[d.name] = (haul[d.name] or 0) + d.count - keep; dropDock(d.count - keep) end
      else
        haul[d.name] = (haul[d.name] or 0) + d.count
        dropDock()
      end
    end
  end
  local list = {}
  for n, c in pairs(haul) do list[#list + 1] = { n, c } end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  S.lastHaul = list
  local limit = turtle.getFuelLimit()
  local target = math.min(FUEL_TARGET, limit == "unlimited" and 0 or limit)
  for _ = 1, 8 do
    if fuel() >= target then break end
    local free
    for s = 16, 1, -1 do if turtle.getItemCount(s) == 0 then free = s; break end end
    if not free then break end
    turtle.select(free)
    if not suckDock() then break end
    if turtle.refuel(0) then
      while fuel() < target and turtle.getItemCount(free) > 0 do turtle.refuel(1) end
    end
    if turtle.getItemCount(free) > 0 then dropDock() end
  end
  turtle.select(1)
  face(0)
  save()
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------
local function applyCtrl()
  if not ctrl or ctrl.seq == S.seq then return nil end
  S.seq = ctrl.seq; save()
  return ctrl.want
end

local function mainLoop()
  while S.y < 0 do if not move("u") then break end end   -- restarted while dipping down to hoe
  if not Z then
    local ok, err = pcall(survey)
    if not ok then setStatus("error", tostring(err)); pcall(goHome) end
  elseif (Z.v or 1) < ZONE_VERSION then
    -- Old map: plots harvested by the pack's right-click were written off as "skip". Re-map once.
    setStatus("surveying", "Re-mapping the farm (old map)")
    local ok, err = pcall(resurvey)
    if not ok then setStatus("error", tostring(err)); pcall(goHome) end
  end
  S.nextRound = S.nextRound or 0
  while true do
    local want = applyCtrl()
    if want == "survey" then
      local ok, err = pcall(resurvey)
      if not ok then setStatus("error", tostring(err)); pcall(goHome) end
    elseif want == "rounds" then S.nextRound = 0; S.paused = false
    elseif want == "stop" then S.paused = true
    elseif want == "go" then S.paused = false end

    if S.lost then
      setStatus("lost", "Carry me back to my starting spot facing the same way, then type: farmer found")
      os.sleep(10)
    elseif Z and not S.paused and os.clock() >= S.nextRound then
      if fuel() < 150 then
        pcall(goHome); dock()
        if fuel() < 150 then setStatus("waiting", "Need fuel in my dock"); S.nextRound = os.clock() + 60 end
      end
      if fuel() >= 150 then
        local ok, a, b, c = pcall(rounds)
        if not ok then setStatus("error", tostring(a)) end
        local okHome, err = pcall(goHome)
        if not okHome then setStatus("error", tostring(err)) else dock() end
        S.nextRound = os.clock() + ROUND_EVERY
        S.sinceSurvey = (S.sinceSurvey or 0) + 1
        if okHome and S.sinceSurvey >= RESURVEY_EVERY then
          S.sinceSurvey = 0
          local okS, errS = pcall(resurvey)    -- picks up new rows; ends back home, docked
          if not okS then setStatus("error", tostring(errS)); pcall(goHome); ok = false end
        end
        if ok then
          if c then setStatus("waiting", ("Out of seeds. Harvested %d, planted %d"):format(a, b))
          else setStatus("docked", ("Round done: harvested %d, planted %d"):format(a, b)) end
        end
      end
    else
      if S.status ~= "waiting" and S.status ~= "error" then
        setStatus("docked", S.paused and "Paused. Say: island " .. NAME:lower() .. " go"
          or ("Next round in %d min"):format(math.max(0, math.ceil((S.nextRound - os.clock()) / 60))))
      end
      local t = os.clock() + 10
      while os.clock() < t and not (ctrl and ctrl.seq ~= S.seq) do os.sleep(1) end
      if Z and (S.status == "waiting" or S.status == "error") then S.status = "docked" end
    end
  end
end

local function netLoop()
  if not modem then return os.pullEvent("never") end
  rednet.open(peripheral.getName(modem))
  local last = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "cmd" and tostring(msg.target):lower() == NAME:lower() then ctrl = msg end
    if os.clock() - last >= 3 then rednet.broadcast(statusMsg(), PROTOCOL); last = os.clock() end
  end
end

do
  -- startup.lua (the self-updater) normally starts us; only write a fallback if there's none
  if not fs.exists("startup.lua") then
    local f = fs.open("startup.lua", "w"); f.write('shell.run("farmer")\n'); f.close()
  end
end
if S.x == nil then S.x, S.y, S.z, S.h = 0, 0, 0, 0 end
if S.turning then S.lost = true; S.turning = nil end
if S.pending then
  local f = turtle.getFuelLevel()
  if type(f) == "number" and type(S.pending.fuel) == "number" then
    if f < S.pending.fuel then apply(S.pending.kind) end
  else S.lost = true end
  S.pending = nil
end
if args[1] == "found" then S.x, S.y, S.z, S.h, S.lost = 0, 0, 0, 0, nil end
if args[1] == "survey" then Z = nil end
if args[1] == "stop" then S.paused = true end
if args[1] == "go" or args[1] == "rounds" then S.paused = false end
S.nextRound = nil
save()
setStatus("docked", "Starting")
parallel.waitForAny(mainLoop, netLoop, gpsLoop)
