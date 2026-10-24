-- miner_setup.lua  --  his name, first-time setup, and finding himself again: restarts, being carried a little
-- way, being carried to a new dock or dimension. A part of miner.lua (one shared environment: see there).
-- My number from a label like Canary-04 / Firecrest-01 (any bird: it's offered back after a reset)
function labelNum()
  return tonumber(((os.getComputerLabel() or ""):match("^%a+%-(%d+)$")))
end
function myLabel(num) return ("%s-%02d"):format(MODE.name, num) end

-- Name follows the dimension: a numbered miner whose label names another bird gets his own
function fixLabel()
  if not S.num then return end
  local lbl = os.getComputerLabel()
  local bird, n = (lbl or ""):match("^(%a+)%-(%d+)$")
  if lbl and not bird then return end           -- a label Tanis typed himself: leave it
  if bird ~= MODE.name or tonumber(n) ~= S.num then os.setComputerLabel(myLabel(S.num)) end
end

---------------------------------------------------------------------------
-- First-time setup at the dock
---------------------------------------------------------------------------
function isContainer(ok, d)
  if not ok or type(d) ~= "table" then return false end
  local n = d.name or ""
  return n:find("barrel") or n:find("chest") or (d.tags and (d.tags["c:barrels"] or d.tags["c:chests"]))
end

function sideName(dir)
  if dir == "up" then return "above me" end
  return ({ [0] = "in front", "on my right", "behind me", "on my left" })[dir]
end

function title(text)
  if term.isColour() then term.setTextColour(colours.cyan) end
  print(text)
  term.setTextColour(colours.white)
end

function askNumber(prompt)
  while true do
    write(prompt)
    local n = tonumber(read())
    if n then return math.floor(n) end
    printError("A number, please.")
  end
end

function askChoice(prompt, options, default)
  while true do
    for i, o in ipairs(options) do print(("  %d) %s"):format(i, o)) end
    write(prompt)
    local a = read()
    if a == "" and default then return default end
    local n = tonumber(a)
    if n and options[n] then return n end
    for i, o in ipairs(options) do if a ~= "" and o:lower():sub(1, #a) == a:lower() then return i end end
    printError("Pick one of the numbers.")
  end
end

function askFacing()
  print("Which way am I facing? (stand behind me, look the same")
  print("way, read 'Facing' on F3)")
  return askChoice("Facing: ", { "North", "East", "South", "West" }) - 1
end

DIM_CHOICES = { "allthemodium:mining", "overworld", "the_nether", "the_end" }
function askDimension()
  local d = askChoice("Dimension [1]: ", { "Mining", "Overworld", "Nether", "End", "Other" }, 1)
  if d == 5 then write("Its name: "); return read() end
  return DIM_CHOICES[d]
end

-- Containers next to me (the four sides and above), as dock directions. Turns all the way round.
function barrelsAround()
  local found = {}
  for _ = 0, 3 do
    if isContainer(turtle.inspect()) then found[#found + 1] = S.h end
    turnRight()
  end
  if isContainer(turtle.inspectUp()) then found[#found + 1] = "up" end
  return found
end

-- What a moved miner keeps when he sets up again at a new dock (same bird only: a new bird gets a new number)
KEEP_ON_MOVE = { "num", "totals", "lastHaul", "chests", "capped", "junk", "hungryAt", "fullAt", "rebootDone",
  "lavaFuel", "lavaScoops", "seq", "chunksDone" }

-- First-time setup, or again at a new dock (keep = the old state: number and label stay)
function setupDock(keep)
  term.clear(); term.setCursorPos(1, 1)
  title(keep and "SETTING UP AT MY NEW DOCK" or "MINER SETUP")
  S = { x = 0, y = 0, z = 0, h = 0, want = "dock", seq = nil, cbc = true }
  print("Which dimension am I in?")
  S.dim = askDimension()
  setMode()
  if keep and modeFor(keep.dim) == MODE_KEY then
    for _, k in ipairs(KEEP_ON_MOVE) do S[k] = keep[k] end
  end
  term.clear(); term.setCursorPos(1, 1)
  title(("I'M A %s HERE"):format(MODE.name:upper()))
  print("I'm sitting on top of my future shaft.")
  print("I need ONE barrel next to me (a side")
  if MODE.selfServe then
    print("or above): my dock. Put fuel in it;")
    print("take my haul out of it.")
  else
    print("or above): my dock, a Dock on")
    print(("%s's cable."):format(MODE.boss))
  end
  if MODE.nether then print("And one empty bucket in my inventory, for lava.") end
  print()
  local x, y, z = locate()
  if x then
    print(("GPS says I'm at %d %d %d."):format(x, y, z))
    S.home = { x = x, y = y, z = z }
    local c, _, stuck = compassByStep(false)
    S.facing = c
    if stuck then apply("f") end -- couldn't step back onto the dock; goHome fixes it later
    if S.facing then print("I'm facing " .. COMPASS[S.facing] .. ".") else S.facing = askFacing() end
  else
    print("No GPS towers heard. Type my position")
    print("(F3, the block I'm in):")
    local hx = askNumber("X: ")
    local hy = askNumber("Y: ")
    local hz = askNumber("Z: ")
    S.home = { x = hx, y = hy, z = hz }
    S.facing = askFacing()
  end
  S.dockY = S.home.y
  save()
  while true do
    local found = barrelsAround()
    face(0)
    if #found == 1 then
      S.dockDir = found[1]
      print(("Dock barrel: %s."):format(sideName(S.dockDir)))
      break
    end
    printError(#found == 0 and "No barrel next to me." or ("%d barrels here: I need just one."):format(#found))
    print("Fix that, then press Enter.")
    read()
  end
  if MODE.nether and bucketState() == "none" then
    printError("No bucket on me: put an empty bucket")
    print("in me, or in a Nether stock barrel.")
  end
  if haveChunky() then print("Chunk controller: I'll keep my chunk loaded.")
  else print("No chunk controller: keep my area loaded.") end
  if boxSlot() then print("Shulker box: extra room for ore.") end
  save()
  if S.num then
    print(("Setup done. I'm still %s."):format(os.getComputerLabel() or ("number " .. S.num)))
    print(("Press START on %s."):format(MODE.boss))
  else
    print(("Setup done. %s gives me a"):format((MODE.boss:gsub("^t", "T"))))
    print("number; pick my layers and press")
    print("START there.")
  end
end

function recover()
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

function lostFlow()
  setStatus("lost", "Carry me back to the dock")
  print("I lost track of which way I'm facing (unloaded mid-turn).")
  print(("Put me back on the dock with the barrel %s,"):format(sideName(S.dockDir)))
  print("then press Enter here.")
  read()
  S.x, S.y, S.z, S.h, S.lost = 0, 0, 0, 0, nil
  S.step = 1   -- redo this level of this chunk from its start
  save()
end

-- Older Canaries only knew their dock's Y. Fill in X/Z, facing and dimension once.
function migrateHome()
  if S.home and S.facing then return end
  setStatus("waiting", "Working out where my dock is")
  local x, y, z = locate()
  if x and not S.lost then
    local c, turns, stuck = compassByStep(S.y <= -2)
    S.h = (S.h + turns) % 4
    if stuck then apply("f") end
    if c then
      S.facing = (c - S.h) % 4
      x, y, z = locate()
      if x then
        local ax, az = rot(S.x, S.z, S.facing)
        S.home = { x = x - ax, y = y - S.y, z = z - az }
        S.dockY = S.home.y
        S.dim = S.dim or "overworld"
        save()
        return
      end
    end
  end
  setStatus("waiting", "Type my dock's position on my screen (one time)")
  term.clear(); term.setCursorPos(1, 1)
  title("ONE-TIME: WHERE IS MY DOCK?")
  print(("My dock is at Y %d. I need its X and Z (F3 on the"):format(S.dockY))
  print("block I sit in when docked), and which way I face there.")
  local hx = askNumber("Dock X: ")
  local hz = askNumber("Dock Z: ")
  S.home = { x = hx, y = S.dockY, z = hz }
  S.facing = askFacing()
  print("Which dimension?")
  S.dim = askDimension()
  save()
  print("Thanks! Carrying on.")
end

-- Far from my dock: outside my chunk area (plus one ring), or above the dock (another dock, or another
-- dimension: the Mining Dimension's pads keep X/Z, its surface is at Y 253).
function farFrom(x, y, z)
  if y > S.home.y + 2 then return true end
  local cx, cz = dockChunk()
  local r = (S.r2 or DEFAULT_R2) + 1
  return math.abs(math.floor(x / 16) - cx) > r or math.abs(math.floor(z / 16) - cz) > r
end

-- Check my counted position against GPS. If I've been carried off nearby, re-learn where I am and
-- which way I face, then wait for an order before going anywhere. Carried far: see movedFlow.
function checkPosition()
  if not (S.home and S.facing) then return end
  local x, y, z = locate()
  if not x then return end
  local ex, ey, ez = absPos()
  local moved = x ~= ex or y ~= ey or z ~= ez
  if moved and farFrom(x, y, z) then
    S.far, S.farPos = true, { x = x, y = y, z = z }
    save()
    return
  end
  if moved then
    setFromAbs(x, y, z)
    S.lost, S.offPath, S.heldSeq = true, true, S.seq
  end
  S.far, S.farPos = nil, nil
  if S.lost then
    save()
    local c = compassByStep(not S.offPath and S.y <= -2)
    if c then
      S.h, S.lost = (c - S.facing) % 4, nil
      local x2, y2, z2 = locate()
      if x2 then setFromAbs(x2, y2, z2) end
    end
  end
  save()
end

DIM_NAMES = { ["allthemodium:mining"] = "Mining", overworld = "Overworld", the_nether = "Nether", the_end = "End" }

-- Carried far from my dock: never tunnel there. With a barrel next to me I offer to set up here (keeping
-- my number and label); otherwise (or if Tanis says no) I wait to be carried back.
function movedFlow()
  local x, y, z = locate()
  if x and not farFrom(x, y, z) then          -- carried back near my dock: the usual way home
    S.far, S.farPos = nil, nil
    checkPosition()
    return
  end
  if x then S.farPos = { x = x, y = y, z = z } end
  local here = x and (x .. "," .. y .. "," .. z)
  if here and here ~= S.farDeclined and #barrelsAround() > 0 then
    setStatus("waiting", "Moved to a new dock: confirm on my screen to set up here")
    term.clear(); term.setCursorPos(1, 1)
    title("I'VE BEEN MOVED")
    print(("My dock was at %d %d %d (%s)."):format(S.home.x, S.home.y, S.home.z, DIM_NAMES[S.dim] or tostring(S.dim or "?")))
    print(("I'm at %d %d %d, next to a barrel."):format(x, y, z))
    print("Set up here as my new dock?")
    print(("I stay %s."):format(os.getComputerLabel() or MODE.name))
    if askChoice("> ", { "Yes, set up here", "No, I'll carry you back" }) == 1 then
      setupDock(S)
      fixLabel()
      setStatus("docked", "Set up at my new dock. Waiting for START")
      return
    end
    S.farDeclined = here
    save()
  end
  setStatus("waiting", ("Moved far from my dock. Carry me back to %d %d %d"):format(S.home.x, S.home.y, S.home.z))
  waitCtrl(10)
end

