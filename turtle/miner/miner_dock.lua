-- miner_dock.lua  --  his dock: unloading, the shulker box, fuel. One dock barrel (Canary, Firecrest) or two
-- (Starling). A part of miner.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Dock: unload, refuel
---------------------------------------------------------------------------
function gpsFixHome()
  if not gpsSeen then return end
  local x, y, z = locate()
  local ex, ey, ez = absPos()
  if x and ex and (x ~= ex or y ~= ey or z ~= ez) then
    print(("GPS says %d %d %d, I counted %d %d %d. Trusting GPS."):format(x, y, z, ex, ey, ez))
    S.home = { x = x - (ex - S.home.x), y = y - (ey - S.home.y), z = z - (ez - S.home.z) }
    S.dockY = S.home.y
  end
end

-- Anything in my slots that isn't gear (or Firecrest's bucket)?
function cargoLeft()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isKept(d.name) then return true end
  end
  return false
end

-- Empty my shulker box at the dock: put it down below me (the top of my shaft), take a bagful out,
-- unload it with unload(), repeat. False if the barrel wouldn't take it all (the box then stays put
-- until the next try).
function unpackBox(unload)
  if not S.boxAt then
    local bs = boxSlot()
    if not bs then return true end
    if BOXDET.d() then return true end       -- no room below (never mined): nothing was stashed anyway
    turtle.select(bs)
    if not BOXPLACE.d() then turtle.select(1); return true end
    S.boxAt, S.boxH = "d", nil; save()
  end
  setStatus("docked", "Unpacking my shulker box")
  while true do
    local got = false
    while true do
      local fs = freeSlot()
      if not fs then break end
      turtle.select(fs)
      if turtle.suckDown() then got = true else break end
    end
    turtle.select(1)
    if not unload() then return false end
    if not got then break end
  end
  pickUpBox()
  S.boxFull, S.boxStacks = nil, 0
  save()
  return true
end

-- Two barrels (Starling): DUMP barrel and FUEL barrel
function dockServiceTwo()
  setStatus("docked", "Unloading")
  gpsFixHome()
  loadJunk()            -- pick up any edits to junk.txt
  valuableCache = {}
  local haul = {}
  local function unload()
    for s = 1, 16 do
      local d = turtle.getItemDetail(s)
      if d and not isKept(d.name) then
        turtle.select(s)
        if not JUNK[d.name] then haul[d.name] = (haul[d.name] or 0) + d.count end
        local tries = 0
        while turtle.getItemCount(s) > 0 do
          if not dropTo(S.dumpDir) then
            tries = tries + 1
            setStatus("waiting", "Dump barrel full, waiting")
            os.sleep(3)
            if tries > 10 then return false end -- give up for now; the main loop waits at the dock
          end
        end
      end
    end
    return true
  end
  local ok = unload() and unpackBox(unload)
  if next(haul) then
    S.lastHaul = haul
    S.totals = S.totals or {}
    for n, c in pairs(haul) do S.totals[n] = (S.totals[n] or 0) + c end
  end
  S.ores = 0
  if not ok or cargoLeft() then face(0); save(); return false end -- couldn't unload everything
  S.loot = nil          -- the loot's in the dump barrel now

  -- Refuel from the fuel barrel up to my top-up (core.fuel: best fuel first; empty buckets go back in)
  local limit = fuelLimit()
  if limit ~= math.huge then
    setStatus("docked", "Refuelling")
    face(S.fuelDir)
    core.fuel.refuelFromDock(S.fuelDir, math.floor(limit * (S.fullAt or FULL_AT) / 100))
  end
  turtle.select(1)
  face(0)
  save()
  return not cargoLeft() -- false if the dump barrel wouldn't take everything
end

---------------------------------------------------------------------------
-- One dock barrel (Canary, Firecrest). He empties everything into it (except his gear, and Firecrest's
-- bucket); his Foreman takes it away. If he needs fuel (or Firecrest a bucket) he asks, the Foreman puts
-- it in the barrel, he takes it. Nobody answering: he takes whatever fuel is in the barrel himself.
---------------------------------------------------------------------------
dockReply = nil   -- latest dock_ready for me (set by the network loop)
ASK_FOR = 10      -- seconds to wait for the Foreman's dock_ready

function askDock(needBucket, wantFuel)
  if not rednet.isOpen() then return nil end
  local me, seq = os.getComputerID(), os.epoch("utc")
  dockReply = nil
  local deadline, nextSend = os.clock() + ASK_FOR, 0
  while os.clock() < deadline do
    if os.clock() >= nextSend then
      rednet.broadcast({ type = "dock_req", id = me, seq = seq, bucket = needBucket, fuel = wantFuel }, PROTOCOL)
      nextSend = os.clock() + 3
    end
    if dockReply and dockReply.seq == seq then return dockReply end
    os.sleep(0.5)
  end
end

-- Empty everything into the dock but my gear (and Firecrest's one bucket). False if the barrel wouldn't take it all.
function unloadAll()
  local keepSlot = MODE.nether and (findSlot(BUCKET) or findSlot(LAVA_BUCKET)) or nil
  local haul = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then
      local keep = (s == keepSlot) and 1 or 0
      if isGear(d.name) then keep = d.count end
      if d.count > keep then
        turtle.select(s)
        if not JUNK[d.name] and d.name ~= BUCKET and d.name ~= LAVA_BUCKET then
          haul[d.name] = (haul[d.name] or 0) + d.count
        end
        local tries = 0
        while turtle.getItemCount(s) > keep do
          if not dropTo(S.dockDir, turtle.getItemCount(s) - keep) then
            tries = tries + 1
            setStatus("waiting", "Dock barrel full, waiting")
            os.sleep(3)
            if tries > 10 then break end -- give up for now; the main loop waits at the dock
          end
        end
      end
    end
  end
  turtle.select(1)
  if next(haul) then
    S.lastHaul = haul
    S.totals = S.totals or {}
    for n, c in pairs(haul) do S.totals[n] = (S.totals[n] or 0) + c end
  end
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isGear(d.name) and d.count > ((s == keepSlot) and 1 or 0) then return false end
  end
  return true
end

-- Take what the Foreman put in the dock: burn the fuel (as much as fits), keep Firecrest's bucket, hand
-- the rest back (empty buckets, spare coal) for the Foreman's stock.
function takeSupplies()
  for _ = 1, 16 do
    local free = nil
    for s = 1, 16 do if turtle.getItemCount(s) == 0 then free = s; break end end
    if not free then break end
    turtle.select(free)
    if not suckFrom(S.dockDir) then break end
  end
  drinkHeld()
  core.fuel.refuelFromInventory(fuelLimit())   -- the rest of what he asked for (coal ...), as much as fits
  local ok = unloadAll()
  face(0)
  if rednet.isOpen() then rednet.broadcast({ type = "dock_done", id = os.getComputerID() }, PROTOCOL) end
  return ok
end

function dockServiceOne(needStart)
  setStatus("docked", "Unloading")
  gpsFixHome()
  if not MODE.nether then loadJunk() end   -- pick up any edits to junk.txt
  valuableCache = {}
  drinkHeld()
  if MODE.nether then dumpJunk(true) end   -- junk picked up on the way home goes down the shaft, not into the dock
  S.ores = 0
  if not (unloadAll() and unpackBox(unloadAll)) then face(0); save(); return false end
  S.loot = nil     -- the loot's with the Foreman now

  local limit = fuelLimit()
  local needBucket = MODE.nether and bucketState() == "none"
  local target = limit ~= math.huge and math.floor(limit * (S.fullAt or FULL_AT) / 100) or 0
  local wantFuel = 0
  -- Only before heading out (needStart given): while he just sits docked he doesn't pester the dock.
  -- Firecrest asks when he's short or hungry (he drinks lava underground); a Canary tops up whenever a
  -- lava bucket's worth is missing.
  local short = needStart and fuel() < needStart
  if MODE.nether then short = short or (needStart and hungry())
  else short = short or (needStart and fuel() <= target - 1000) end
  if needStart and limit ~= math.huge and short then
    wantFuel = math.max(needStart or 0, target) - fuel()
  end
  if needStart and (needBucket or wantFuel > 0) then
    setStatus("docked", needBucket and "Asking the dock for a bucket" or "Asking the dock for fuel")
    local r = askDock(needBucket, wantFuel)
    if r then
      takeSupplies()
      S.dockNote = r.note
    else
      S.dockNote = ("%s didn't answer"):format((MODE.boss:gsub("^t", "T")))
      if wantFuel > 0 then
        -- Fuel put in by hand: take it myself (empty buckets go back in)
        setStatus("docked", "Taking fuel from my dock")
        face(S.dockDir)
        core.fuel.refuelFromDock(S.dockDir, math.max(needStart or 0, target))
      end
    end
  elseif needStart then
    S.dockNote = nil
  end
  face(0)
  save()
  return true
end

-- Tell Storage where my dock is (core.dock: at most every 10 minutes; nobody answering costs a second)
function reportDock()
  if not (S.dockDir and S.home) then return end
  core.dock.set(S.home, S.dockDir)
  core.dock.maybeReport({ role = "miner", tries = 1, timeout = 1 })
end

-- needStart: fuel needed to head out (one dock: asks for it; two barrels: just refuels)
function dockService(needStart)
  S.chunky = haveChunky() or nil   -- picked one up (or lost it) since last time?
  if S.dockDir then return dockServiceOne(needStart) end
  return dockServiceTwo()
end

