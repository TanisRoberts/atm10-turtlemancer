-- farmer.lua  --  Partridge, the crop farmer (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: a turtle with a diamond hoe and a wireless or ender modem. GPS towers make him unlosable
--        (optional: without them he finds his way from his map, like before).
-- Farm:  Partridge flies one block above the crops. Mark the farm's edge with slabs at crop height
--        (one block above the farmland), so the slabs sit right under him at the edge.
--        Start him inside the farm at flying height next to his dock barrel, or ON TOP of a dock
--        barrel built into the slab ring, facing into the farm.
-- Dock:  a barrel storage knows as a dock (/dock on storage, or the coal marker in /setup).
--
-- Every round (every EVERY minutes):
--   * ripe crops: harvest and replant (wheat, carrots, potatoes, beetroot, nether wart, hemp,
--     Mystical Agriculture crops...); empty farmland gets the crop that grew there, else the main crop
--   * bare dirt in the farm: hoe it and plant it; pumpkins and melons: harvest (stems stay)
--   * picks up whatever lands on the ground (ATM10's right-click harvest drops crops there)
--   * unloads at the dock (keeps KEEP_SEEDS of each seed), refuels; unloads mid-round if full
--   * re-maps the farm every RESURVEY_EVERY rounds, so an extended field is picked up by itself
-- Control: the Farmhand computer, chat (island partridge rounds|survey|stop|go|found), or here:
--   farmer rounds | survey (new map from where he stands) | stop | go | found
-- Settings: partridge.env (edit live, or from the Farmhand).

local B = dofile("farmbot.lua")
local S              -- B.S once running
local key, unkey, DX, DZ = B.key, B.unkey, B.DX, B.DZ

local ZONE_VERSION = 3

local DEFAULTS = {
  { "EVERY", 10, "Minutes between rounds.", remote = true, min = 1 },
  { "KEEP_SEEDS", 64, "Seeds of each kind he keeps for replanting; the rest goes to storage.", remote = true, min = 0 },
  { "RESURVEY_EVERY", 6, "Re-map the farm every this many rounds, so new rows get picked up (0 = never).", remote = true, min = 0 },
  { "FUEL_TARGET", 3000, "Fuel he tops up to at the dock.", min = 200 },
  { "FUEL_LOW", 150, "Below this he won't start a round until he's refuelled.", min = 50 },
  { "MAX_REACH", 32, "How far the farm may reach from his start; further means the slab border has a gap.", min = 4 },
  { "SURVEY_RETRY", 5, "Minutes between tries when mapping the farm fails.", min = 1 },
}

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
local function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = tostring(d.name); return n:find("barrel") or n:find("chest")
end

-- Plants that may stick up into his flying layer (2-tall hemp, tall grass, flowers).
local function isPlantInWay(d)
  if type(d) ~= "table" then return false end
  local n, t = tostring(d.name), d.tags or {}
  if n:find("hemp") or n:find("tall_grass") or n:find("large_fern") then return true end
  if d.state and d.state.age ~= nil and not n:find("stem") then return true end
  return t["minecraft:crops"] or t["minecraft:replaceable"] or t["minecraft:flowers"]
    or t["minecraft:tall_flowers"] or t["c:crops"] or false
end

local topsCut = 0
B.onBlocked = function(kind, ok, d, op)
  if ok and kind == "f" and isPlantInWay(d) then
    if op.dig() then topsCut = topsCut + 1 end    -- tall crop top (hemp etc.) at flying height: harvest, fly on
    op.suck()
    return "retry"
  end
  if ok then return "fail" end
end

local function selectItem(name)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == name then turtle.select(s); return true end
  end
  return false
end

-- Harvest drops can land on the ground instead of in his inventory: with a hoe, CC:Tweaked
-- right-clicks the crop before digging it, and ATM10 treats a right-click on a ripe crop as a
-- harvest (crop replanted at age 0, items dropped on the farmland). So always hoover up below.
local function pickUp()
  local got = false
  for _ = 1, 6 do if turtle.suckDown() then got = true else break end end
  return got
end

---------------------------------------------------------------------------
-- The map: cells ["x,z"] = plot / gourd / skip (fly over) / border / blocked / dock
---------------------------------------------------------------------------
local function flyable(k)
  local c = B.Z.cells[k]
  return c == "plot" or c == "skip" or c == "gourd" or k == B.Z.home
end
local function passableKind(kind) return kind == "plot" or kind == "skip" or kind == "gourd" end

local function goTo(goalK) return B.goTo(function(k) return k == goalK end, flyable) end

local function goHome()
  while S.y > 0 do if not B.move("d") then break end end
  while S.y < 0 do if not B.move("u") then break end end
  local home = B.Z.home or key(0, 0)
  if key(S.x, S.z) == home then return true end
  if not goTo(home) then
    B.tempBlocked = {}
    if not goTo(home) then error("Can't find my way home", 0) end
  end
  return true
end

local function survey(fresh)
  B.setStatus("surveying", "Mapping the farm")
  local old = (not fresh) and B.Z or nil
  local anchor = old and old.anchor
  if fresh then
    S.x, S.y, S.z, S.h = 0, 0, 0, 0
    B.save()
  end
  -- Fuel check before wandering anywhere: burn anything burnable he's carrying first
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isSeedItem(d.name) and B.fuel() < 2000 then
      turtle.select(s)
      if turtle.refuel(0) then turtle.refuel() end
    end
  end
  turtle.select(1)
  if B.fuel() < 300 then
    error(("Only %d fuel. Put some coal in me and say: island %s survey"):format(B.fuel(), B.NAME:lower()), 0)
  end
  if fresh then
    -- Pin the new map to the world now (GPS): here = 0,0, the way he faces = heading 0
    local c, ax, ay, az = B.findCompass()
    anchor = c and { x = ax, y = ay, z = az, f = c } or nil
  end

  local cells, crop, stemAt = {}, {}, {}
  local dockCell, dockDir, gap = nil, nil, false
  local startK = key(S.x, S.z)
  local maxReach = B.E.MAX_REACH

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

  if fresh then
    cells[startK] = classify(startK)
    if cells[startK] == "border" then error("I'm sitting over the border. Put me inside the farm.", 0) end
    if cells[startK] == "dock" then
      -- Started on top of the dock, facing into the farm: step in and map from there
      B.face(0)
      local ok, why = B.move("f")
      if not ok then error("I start on my dock facing into the farm, but couldn't step forward (" .. tostring(why) .. ")", 0) end
      local k = key(S.x, S.z)
      cells[k] = classify(k)
      if cells[k] == "border" or cells[k] == "dock" then
        error("Facing the wrong way: put me on my dock facing INTO the farm.", 0)
      end
    end
    for h = 0, 3 do                                   -- a dock next to the start spot
      B.face(h)
      local ok, d = turtle.inspect()
      if isContainer(ok, d) then dockDir = h; cells[key(S.x + DX[h], S.z + DZ[h])] = "dock"; break end
    end
  else
    -- Re-map from home in the same frame: the dock is where it was
    dockDir = old.dockDir
    if dockDir == "down" then
      cells[startK] = "dock"; dockCell = startK
      local into
      for h = 0, 3 do
        local c = old.cells[key(S.x + DX[h], S.z + DZ[h])]
        if passableKind(c) then into = h; break end
      end
      if not into then error("Can't see a way into the farm from my dock", 0) end
      B.face(into)
      local ok, why = B.move("f")
      if not ok then error("Couldn't step off my dock into the farm (" .. tostring(why) .. ")", 0) end
      local k = key(S.x, S.z)
      cells[k] = classify(k)
    else
      cells[startK] = classify(startK)
      if type(dockDir) == "number" then cells[key(S.x + DX[dockDir], S.z + DZ[dockDir])] = "dock" end
    end
  end

  local function visit()
    for h = 0, 3 do
      local nx, nz = S.x + DX[h], S.z + DZ[h]
      local k = key(nx, nz)
      if cells[k] == nil then
        local sx, sz = unkey(startK)
        if math.abs(nx - sx) > maxReach or math.abs(nz - sz) > maxReach then gap = true; return end
        B.face(h)
        local okF, dF = turtle.inspect()
        if okF and isContainer(okF, dF) and fresh and not dockDir and key(S.x, S.z) == startK then
          cells[k] = "dock"; dockDir = h
        elseif okF and not isPlantInWay(dF) then
          cells[k] = "blocked"
        elseif B.move("f") then              -- move() harvests a tall-crop top in the way
          local kind = classify(k)
          cells[k] = kind
          if kind ~= "border" and kind ~= "dock" then visit() end
          B.face((h + 2) % 4)          -- always fly back, even after finding a gap
          local back, why = B.move("f")
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
  if gap then error("The slab border has a gap (farm runs past " .. maxReach .. " blocks). Fix it and survey again.", 0) end

  local home = startK
  if fresh then
    if not dockDir then
      local ok, d = turtle.inspectUp()
      if isContainer(ok, d) then dockDir = "up" end
    end
    if not dockDir and dockCell then
      home, dockDir = dockCell, "down"      -- dock in the border: hover above it and use it from the top
      cells[home] = "dock"
    end
    if not dockDir then error("No dock barrel next to my starting spot or in the border.", 0) end
  else
    home = old.home
    cells[home] = (dockDir == "down") and "dock" or cells[home]
  end

  -- Spots next to pumpkin/melon stems are where the fruit grows: never plant or hoe them
  for k in pairs(stemAt) do
    local x, z = unkey(k)
    for h = 0, 3 do
      local nk = key(x + DX[h], z + DZ[h])
      if cells[nk] == "plot" and not crop[nk] and not stemAt[nk] then cells[nk] = "gourd" end
    end
  end
  -- A bare plot remembers the crop it last grew (same frame only)
  if old and old.crop then
    for k, s in pairs(old.crop) do if cells[k] == "plot" and not crop[k] then crop[k] = s end end
  end
  -- Main crop = most common one
  local tally, main, best = {}, nil, 0
  for _, s in pairs(crop) do tally[s] = (tally[s] or 0) + 1; if tally[s] > best then best, main = tally[s], s end end
  if not main and old then main = old.main end
  -- Visiting order: rows, alternating direction
  local plots = {}
  for k, kind in pairs(cells) do if kind == "plot" or kind == "gourd" then plots[#plots + 1] = k end end
  table.sort(plots, function(a, b)
    local ax, az = unkey(a); local bx, bz = unkey(b)
    if az ~= bz then return az < bz end
    if az % 2 == 0 then return ax < bx else return ax > bx end
  end)
  B.Z = { cells = cells, crop = crop, plots = plots, dockDir = dockDir, main = main, home = home,
          anchor = anchor, v = ZONE_VERSION, seen = old and old.seen or nil }
  B.saveZone()
  B.setStatus("docked", ("Farm mapped: %d plots%s"):format(#plots, main and (", mostly " .. main:gsub("^.-:", "")) or ""))
end

---------------------------------------------------------------------------
-- A round
---------------------------------------------------------------------------
local function plantHere(k)
  local Z = B.Z
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

local function dock()
  return B.dock({
    keep = function(name, already) if isSeedItem(name) then return B.E.KEEP_SEEDS - already end return 0 end,
  })
end

local function rounds()
  local Z = B.Z
  B.setStatus("working", "Doing my rounds")
  topsCut = 0
  local harvested, planted, tilled, noSeed, changed = 0, 0, 0, false, false
  local done = 0
  -- What each plot did this round, for the Farmhand's map (h harvested + replanted, g growing, e empty)
  Z.seen = Z.seen or {}
  local seen = Z.seen
  local function mark(k, st) if seen[k] ~= st then seen[k] = st; B.touchMap() end end
  for _, k in ipairs(Z.plots) do
    B.abortIfNeeded()
    if B.freeSlots() < 2 then             -- full: unload, then carry on where he was
      goHome(); dock(); B.setStatus("working", "Doing my rounds")
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
          mark(k, "h")
        else
          local r = plantHere(k)
          if r == "planted" then planted = planted + 1 elseif r == "noseed" then noSeed = true end
          mark(k, r == "planted" and "h" or "e")
        end
      elseif ok and isCrop(d) then
        mark(k, "g")
      elseif ok and isGourd(d.name) then
        turtle.digDown(); harvested = harvested + 1
        pickUp()
      elseif not ok then
        local r = plantHere(k)
        if r == "planted" then planted = planted + 1; mark(k, "g")
        elseif r == "noseed" then noSeed = true; mark(k, "e")
        else
          -- No farmland: drop in, hoe the dirt, plant, come back up
          if B.move("d") then
            local tilledOk = turtle.digDown()
            if B.move("u") and tilledOk then
              tilled = tilled + 1
              r = plantHere(k)
              if r == "planted" then planted = planted + 1 end
            end
            mark(k, r == "planted" and "g" or "e")
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
      if B.fuel() < 60 then break end
    end
    done = done + 1
    S.progress = ("%d/%d"):format(done, #Z.plots)
  end
  S.progress = nil
  B.saveZone()                          -- also keeps the map's last-round marks
  harvested = harvested + topsCut
  S.lastRound = { harvested = harvested, planted = planted, tilled = tilled, at = B.now() }
  local summary = ("Round done: harvested %d, planted %d"):format(harvested, planted)
  return summary, noSeed and ("Out of seeds. Harvested %d, planted %d"):format(harvested, planted) or nil
end

---------------------------------------------------------------------------
-- Finding his way without GPS (restart mid-turn, or "found")
---------------------------------------------------------------------------
local function sense()
  local okF, dF = turtle.inspect()
  if okF and not isPlantInWay(dF) then return { front = true, ok = okF, d = dF } end
  if turtle.forward() then
    local ok, d = turtle.inspectDown()
    for _ = 1, 5 do if turtle.back() then break end; os.sleep(0.5) end
    return { below = true, ok = ok, d = d }
  end
  return { stuck = true }
end
local function fits(kind, seen)
  if kind == nil or seen.stuck then return true end
  if seen.front then return kind == "blocked" or (kind == "dock" and isContainer(seen.ok, seen.d)) end
  local slab = seen.ok and tostring(seen.d.name):find("slab") ~= nil
  local box = isContainer(seen.ok, seen.d)
  if kind == "border" then return slab end
  if kind == "dock" then return box end
  if kind == "blocked" then return true end
  return not slab and not box
end

local function recoverNoGps(why)
  local cands = {}
  if why == "found" then
    local seen = {}
    for _, k in ipairs({ B.Z.home or "0,0", "0,0" }) do
      if not seen[k] then
        seen[k] = true
        local x, z = unkey(k)
        for h = 0, 3 do cands[#cands + 1] = { x, z, h } end
      end
    end
  else
    local hs = type(S.turning) == "table" and S.turning or { 0, 1, 2, 3 }
    for _, h in ipairs(hs) do cands[#cands + 1] = { S.x, S.z, h } end
  end
  local m = B.orient(cands, { sense = sense, fits = fits, passable = passableKind })
  if m then S.x, S.y, S.z, S.h = m[1], 0, m[2], m[3]; return true end
  return false
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
-- Map page: plots by crop (with what happened there last round), water/paths, pumpkin/melon spots
B.mapCell = function(k, kind, cropCode)
  local seen = B.Z.seen and B.Z.seen[k]
  if kind == "plot" then return cropCode(B.Z.crop[k] or B.Z.main), seen end
  if kind == "gourd" then return "&" end
  if kind == "skip" then return "," end
end

B.extraStatus = function()
  local Z = B.Z
  return { plots = Z and #Z.plots or 0, crop = Z and Z.main, progress = S.progress,
           seeds = B.countWhere(isSeedItem) }
end

local R = {
  zoneVersion = ZONE_VERSION,
  boot = function()
    while S.y < 0 do if not B.move("u") then break end end   -- restarted while dipping down to hoe
  end,
  okAt = function(lx, ly, lz)
    local k = key(lx, lz)
    return (ly == 0 or ly == -1) and B.Z.cells[k] ~= nil and (flyable(k) or k == B.Z.home)
  end,
  recoverNoGps = recoverNoGps,
  survey = survey,
  rounds = rounds,
  goHome = goHome,
  dock = dock,
}

local args = { ... }
B.run({ name = "Partridge", role = "farmer", prog = "farmer",
        env = { file = "partridge.env", title = "Partridge (crop farmer)", defaults = DEFAULTS },
        state = "farmer.state", zone = "farmer.zone", onLoad = function(st) S = st end },
      R, args)
