-- weaver_loop.lua  --  setup, the main loop and the start. A part of weaver.lua.

local function ask(q, default)
  while true do
    write(q .. (default and (" [" .. default .. "]") or "") .. ": ")
    local a = read()
    if a == "" and default then return default end
    if HEAD[a:lower()] then return HEAD[a:lower()] end
    print("north, east, south or west")
  end
end

local function isContainer(ok, d)
  return ok and d and (d.name:find("chest", 1, true) or d.name:find("barrel", 1, true)) ~= nil
end

-- First start: which way he faces on his dock. The supply chest (any chest or barrel) is under him.
local function setup()
  term.clear(); term.setCursorPos(1, 1)
  print("WEAVER SETUP  (F3 shows which way you face)")
  if not isContainer(turtle.inspectDown()) then
    error("No chest or barrel under me. Put the dock's Ender Storage chest below and run weaver again.", 0)
  end
  C = { dh = ask("Which way am I facing (north/east/south/west)") }
  writeT(CFG_FILE, C)
  S = { x = 0, y = 0, z = 0, h = C.dh, want = "idle", short = {}, skip = {}, orderSeq = 0, supSeq = 0, topY = -1 }
  GAPS = {}; saveGaps(); save()
  print("Setup saved. Waiting for an Architect to pair with me.")
end

local function boot()
  if core.chunk.restore() then print("Put my modem back on.") end
  openModem()
  if S.x == nil then S.x, S.y, S.z, S.h, S.want = 0, 0, 0, C.dh, S.want or "idle" end   -- fresh: he sits on his dock
  recoverMove()
  if M_ARGS[1] == "found" then S.x, S.y, S.z, S.h, S.lost = 0, 0, 0, C.dh, nil end
  S.n = myNumber()
  save()
  if core.chunk.have() then keepChunk(true) end
end

local function reboot()
  save(); setStatus("reboot", "Rebooting"); os.sleep(0.5); os.reboot()
end

local function mainLoop()
  while true do
    NEWORDER = false
    if REBOOT then reboot() end
    if S.lost then
      setStatus("lost", "Carry me to my dock, then run: weaver found"); os.sleep(5)
    elseif S.n == nil then
      os.sleep(1)
    elseif S.sup then
      finishSupply()
    elseif S.marks and (S.want == "clear" or S.want == "build") then
      clearStep()                                    -- markers out: take them away first (also before a build)
    elseif S.want == "test" and S.markCells then
      markStep()
    elseif S.want ~= "build" then
      if not atDock() then goHome() end
      setStatus(S.want == "stop" and "stopped" or "idle", "Waiting for an order")
      os.sleep(1)
    elseif S.layer > (S.total or math.huge) and S.work == "layer" and fs.exists(GAPLIST) then
      S.work, S.idx = "gap", 1; save()
    elseif S.layer > (S.total or math.huge) and S.work == "layer" then
      if not atDock() then goHome() end
      setStatus("done", ("Build %s finished, %d gaps"):format(tostring(S.build), #GAPS))
      send({ type = "done", build = S.build, hash = S.hash, gaps = #GAPS })
      os.sleep(3)
    else
      buildStep()
    end
  end
end

function start()
  M_ARGS = args
  if args[1] == "setup" or not C then setup() end
  boot()
  setStatus("starting", "Booted")
  parallel.waitForAny(mainLoop, netLoop)
end
