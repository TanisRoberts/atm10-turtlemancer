-- gps_host.lua  --  one of the GPS towers that tell turtles their exact X/Y/Z (CC:Tweaked)
--
-- Needs: a computer with an ENDER modem (reaches every turtle in the dimension).
-- Build 4 of these, spread out and high up, NOT all at the same height (three at one height
-- and one higher works). A turtle then knows exactly where it is, anywhere in the dimension.
--
-- First run asks for this computer's coordinates (F3, the computer block itself) and saves them.
-- If other GPS towers already work, it fills them in for you. Delete gps.cfg to re-enter them.

local CFG = "gps.cfg"

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
  local f = fs.open(CFG, "w"); f.write(textutils.serialize(pos)); f.close()
end

term.clear(); term.setCursorPos(1, 1)
if term.isColour() then term.setTextColour(colours.lime) end
print(("GPS host at %d %d %d"):format(pos.x, pos.y, pos.z))
term.setTextColour(colours.white)
print("Turtles ask me where they are. Leave me running.")
print("Delete gps.cfg and reboot if I'm moved.")
shell.run("gps", "host", tostring(pos.x), tostring(pos.y), tostring(pos.z))
