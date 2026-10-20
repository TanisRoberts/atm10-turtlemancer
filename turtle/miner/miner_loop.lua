-- miner_loop.lua  --  the main loop (mine, come home, wait for orders), the radio (status out, orders in) and start().
-- A part of miner.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
function safeHome()
  local ok, err = pcall(goHome)
  if not ok then setStatus("error", tostring(err)); save() end
  return ok
end

function runOnce()
  if atDock() then
    local need = fuelToStart()
    if not dockService(need) then
      setStatus("waiting", S.dockDir and ("Dock barrel full. Is %s running?"):format(MODE.boss)
        or "Dump barrel full: empty it")
      waitCtrl(15)
      return
    end
    if MODE.nether and bucketState() == "none" then
      setStatus("waiting", "No bucket: put an empty bucket in a Nether stock barrel")
      waitCtrl(15)
      return
    end
    if fuel() < need then
      setStatus("waiting", ("Need %d fuel, have %d%s"):format(need, fuel(),
        MODE.nether and ": lava buckets in a stock barrel" or S.dockDir and ": lava buckets in my dock" or ""))
      waitCtrl(15)
      return
    end
  end
  setStatus("mining", "")
  local ok, err = pcall(mineChunks)
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

function mainLoop()
  migrateHome()
  setMode()
  checkPosition()
  while true do
    applyCtrl()
    maybeReboot()
    if S.far then
      movedFlow()
    elseif S.lost and gpsSeen then
      checkPosition()
      if S.lost then
        setStatus("lost", "Can't tell which way I face: no free side to step into")
        waitCtrl(30)
      end
    elseif S.lost then
      lostFlow()
    elseif S.offPath and S.seq == S.heldSeq then
      setStatus("waiting", "Moved by hand. START or DOCK on the Foreman to send me home")
      waitCtrl(10)
    elseif S.offPath then
      setStatus("returning", "Tunnelling back to my shaft")
      safeHome()
      if not atDock() then waitCtrl(30) end
    elseif S.retired then
      if not atDock() then setStatus("returning", "Retiring: heading home"); safeHome() end
      if atDock() then dockService(); setStatus("retired", "Retired. Thanks for your service") end
      waitCtrl(30)
    elseif S.want ~= "run" or S.done then
      if not atDock() then setStatus("returning", "Heading home"); safeHome() end
      if atDock() then
        dockService()
        setStatus("docked", S.done and "Range finished. Pick a new one." or "Waiting for START")
        reportDock()
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
function statusMsg()
  local used = 16 - emptySlots()
  local haul = {}
  for n, c in pairs(S.lastHaul or {}) do haul[#haul + 1] = { n, c } end
  table.sort(haul, function(a, b) return a[2] > b[2] end)
  while #haul > 8 do table.remove(haul) end
  local f, l = turtle.getFuelLevel(), turtle.getFuelLimit()
  local px, py, pz = absPos()
  local m = {
    type = "status", id = os.getComputerID(), label = os.getComputerLabel(), num = S.num,
    pos = S.far and S.farPos or (px and { x = px, y = py, z = pz }) or nil, far = S.far, dim = S.dim, home = S.home,
    facing = S.facing and COMPASS[(S.facing + (S.h or 0)) % 4], gps = gpsSeen,
    offPath = S.offPath, retired = S.retired, state = S.status, msg = S.msg, seq = S.seq,
    kind = MODE_KEY, bird = MODE.name, chests = S.chests or 0,
    fuel = f, fuelLimit = l, slots = used,
    y = S.dockY and (S.dockY + (S.y or 0)), x = S.x, z = S.z,
    layer = S.layerIdx, layers = S.layerCount, ring = S.chunkRing, minRing = S.r1 or 0, maxRing = S.r2 or DEFAULT_R2,
    cbc = true, chunk = S.ci, chunks = S.chunkCount, chunksDone = S.chunksDone, cell = S.step,
    chunky = S.chunky == true, chunkyNote = S.chunkyNote, swaps = S.swaps,
    box = boxSlot() and (S.boxFull and "full" or "ok") or "none", boxStacks = S.boxStacks,
    minY = S.minY, maxY = S.maxY, want = S.want, rebootDone = S.rebootDone, done = S.done, ores = S.ores, haul = haul,
  }
  m.dockNote, m.oneDock = S.dockNote, S.dockDir ~= nil
  if MODE.nether then
    m.hungry, m.hungryAt, m.fullAt = S.hungry == true, S.hungryAt or HUNGRY_AT, S.fullAt or FULL_AT
    m.bucket, m.lavaFuel, m.lavaScoops = bucketState(), S.lavaFuel or 0, S.lavaScoops or 0
  end
  return m
end

-- Orders only from my own Foreman: cmd.kind names the bird it's for. On tanis-miner (Canaries and Starlings) an
-- order for a Canary must say so, so an old Overworld Foreman can't order the MD's Canaries about.
function cmdForMe(msg)
  if msg.kind ~= nil then return msg.kind == MODE_KEY end
  return MODE_KEY ~= "canary"
end

function netLoop()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then
    print(("No ender/wireless modem: no %s, no orders."):format((MODE.boss:gsub("^the ", ""))))
    return os.pullEvent("never")
  end
  rednet.open(peripheral.getName(modem))
  local me = os.getComputerID()
  local lastSend = -100
  while true do
    local _, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" and msg.type == "assigned" and msg.id == me and not S.num and tonumber(msg.num) then
      S.num = tonumber(msg.num)
      -- An older Foreman only knows Canary-NN: my name comes from my dimension either way
      local lbl = type(msg.label) == "string" and msg.label or ""
      os.setComputerLabel(lbl:sub(1, #MODE.name + 1) == MODE.name .. "-" and lbl or myLabel(S.num))
      print(("%s named me %s."):format((MODE.boss:gsub("^t", "T")), os.getComputerLabel()))
      save()
    elseif type(msg) == "table" and msg.type == "dock_ready" and msg.id == me then
      dockReply = msg
    elseif type(msg) == "table" and msg.type == "cmd" and msg.to == me and cmdForMe(msg) then
      ctrl = msg
      if MODE.nether and type(msg.junk) == "table" then
        S.junk = msg.junk; setJunk(S.junk); valuableCache = {}
      end
      local hA, fA = tonumber(msg.hungryAt), tonumber(msg.fullAt)
      if MODE.nether and hA and fA and hA >= 1 and fA <= 99 and hA < fA then S.hungryAt, S.fullAt = hA, fA
      elseif not MODE.nether and fA and fA >= 10 and fA <= 99 then S.fullAt = fA end
      if type(msg.capped) == "table" then
        local set = {}
        for _, n in ipairs(msg.capped) do set[n] = true end
        S.capped = set
      end
    end
    if os.clock() - lastSend >= STATUS_EVERY then
      if not S.num then
        -- No number yet: ask the Foreman (a label like Canary-04 is offered back, e.g. after a reset)
        rednet.broadcast({ type = "register", id = me, want = labelNum(), label = os.getComputerLabel(),
          name = MODE.name }, PROTOCOL)
      end
      rednet.broadcast(statusMsg(), PROTOCOL)
      lastSend = os.clock()
    end
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
function start()
  if not fs.exists("startup.lua") then -- auto-resume after chunk reloads and restarts
    local f = fs.open("startup.lua", "w"); f.write('shell.run("miner")\n'); f.close()
  end
  loadState()
  if not S.dockY then setupDock()
  elseif not knowsDock() then
    -- A dock position but no barrel in my state (a setup that never finished): set up again, same number
    print("I don't know my dock barrel. Setting up again (I keep my number).")
    setupDock(S)
  else recover() end
  setMode()
  -- Chunk by chunk since Oct 2026: progress from the old ring miner means nothing now. Start the
  -- Foreman's order afresh (forgetting its seq makes the next order count as new).
  if not S.cbc then
    S.cbc, S.ci, S.cl, S.step, S.k, S.probedLayer, S.r1, S.r2, S.seq = true, 1, 1, 1, nil, nil, nil, nil, nil
    save()
  end
  restoreRadio()
  pickUpBox()
  S.chunky = haveChunky() or nil
  save()
  if S.chunky then
    print("Chunk controller on board: I keep my own chunk loaded.")
    refreshChunk(true)   -- claim this chunk straight away (after a server restart AP restores it anyway)
  end
  fixLabel()
  print(("I'm a %s (%s)."):format(MODE.name, tostring(S.dim or "overworld")))
  setStatus("docked", "Starting")
  parallel.waitForAny(mainLoop, netLoop)
end

