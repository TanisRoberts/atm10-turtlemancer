-- gps_host.lua  --  one of the GPS towers that tell turtles their exact X/Y/Z (CC:Tweaked)
--
-- Needs: a computer with an ENDER modem (reaches every turtle in the dimension).
-- Build 4 of these, spread out and high up, NOT all at the same height (three at one height
-- and one higher works). A turtle then knows exactly where it is, anywhere in the dimension.
--
-- First run asks for this computer's coordinates (F3, the computer block itself) and saves them.
-- If other GPS towers already work, it fills them in for you. Delete gps.cfg to re-enter them.
--
-- Aircraft warning light: a redstone lamp touching the computer (on top by default) flashes like a
-- pylon light. Every tower flashes in time with the others (they all use the real-world clock).
-- To use another side, or none, edit lamp = "top" in gps.cfg ("none" turns it off).

local CFG = "gps.cfg"
local FLASH_EVERY = 3000   -- ms between flashes
local FLASH_ON    = 800    -- ms the lamp stays lit

local function readCfg()
  if not fs.exists(CFG) then return nil end
  local f = fs.open(CFG, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  if type(t) == "table" and tonumber(t.x) and tonumber(t.y) and tonumber(t.z) then return t end
end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then
  printError("I need an ender (or wireless) modem on this computer.")
  return
end
local side = peripheral.getName(modem)

local pos = readCfg()
if not pos then
  term.clear(); term.setCursorPos(1, 1)
  if term.isColour() then term.setTextColour(colours.cyan) end
  print("GPS HOST SETUP")
  term.setTextColour(colours.white)
  rednet.open(side)
  local x, y, z = gps.locate(3)
  rednet.close(side)
  if x then
    print(("The other towers say I'm at %d %d %d."):format(x, y, z))
    write("Use that? (Enter = yes, n = type it) ")
    if read():lower():sub(1, 1) ~= "n" then pos = { x = x, y = y, z = z } end
  end
  while not pos do
    print("This computer's coordinates (F3 while looking at it):")
    write("X: "); local px = tonumber(read())
    write("Y: "); local py = tonumber(read())
    write("Z: "); local pz = tonumber(read())
    if px and py and pz then pos = { x = px, y = py, z = pz } else printError("Numbers only, try again.") end
  end
  pos.lamp = "top"
  local f = fs.open(CFG, "w"); f.write(textutils.serialize(pos)); f.close()
end
local lampSide = pos.lamp or "top"
local SIDES = {}
for _, s in ipairs(rs.getSides()) do SIDES[s] = true end
if not SIDES[lampSide] then lampSide = nil end

term.clear(); term.setCursorPos(1, 1)
if term.isColour() then term.setTextColour(colours.lime) end
print(("GPS host at %d %d %d"):format(pos.x, pos.y, pos.z))
term.setTextColour(colours.white)
print("Turtles ask me where they are. Leave me running.")
print("Delete gps.cfg and reboot if I'm moved.")
if lampSide then print("Warning light: lamp on my " .. lampSide .. " side.") end

local function host()
  shell.run("gps", "host", tostring(pos.x), tostring(pos.y), tostring(pos.z))
end

-- Flash the lamp on a shared beat: all towers light up together
local function blink()
  if not lampSide then return os.pullEvent("never") end
  while true do
    local t = os.epoch("utc") % FLASH_EVERY
    local on = t < FLASH_ON
    rs.setOutput(lampSide, on)
    local wait = on and (FLASH_ON - t) or (FLASH_EVERY - t)
    os.sleep(math.max(0.05, wait / 1000))
  end
end

parallel.waitForAny(host, blink)
if lampSide then rs.setOutput(lampSide, false) end
