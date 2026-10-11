-- install.lua  --  one-time setup for a machine. Run it with:
--   wget run https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/install.lua
-- It swaps in the self-updating startup.lua (keeping a backup of the old one) and reboots.
-- From then on, every reboot pulls the latest scripts.

local URL = "https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/startup.lua"

local label = os.getComputerLabel()
if turtle and not label then
  printError("Label this turtle first, e.g.:  label set Digger")
  return
end

local h, err = http.get(URL .. "?t=" .. os.epoch("utc"), nil, true)
if not h then printError("Couldn't download startup.lua: " .. tostring(err)); return end
local body = h.readAll(); h.close()
if not body or #body == 0 or not load(body, "@startup.lua") then
  printError("The download looks broken. Try again in a minute.")
  return
end

if fs.exists("startup.lua") then
  if fs.exists("startup.old.lua") then fs.delete("startup.old.lua") end
  fs.move("startup.lua", "startup.old.lua")
  print("Old startup.lua kept as startup.old.lua")
end
local f = fs.open("startup.lua", "wb"); f.write(body); f.close()
print("Installed. Rebooting to pull everything...")
os.sleep(2)
os.reboot()
