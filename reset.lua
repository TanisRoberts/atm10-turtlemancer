-- reset.lua  --  wipe this device so it can be set up with a new role.
-- Deletes everything on the device except startup.lua (role, scripts, saved state, maps, configs),
-- then reboots into setup. The label stays (setup lets you change it).

local REPO = "https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/"

local function colour(c) if term.isColour() then term.setTextColour(c) end end

colour(colours.red); print("RESET THIS DEVICE"); colour(colours.white)
print("Wipes its role, scripts, saved state, maps and configs,")
print("then runs setup again so you can pick a new role.")
if turtle then print("Items in the turtle stay where they are.") end
print()
write("Type RESET to confirm: ")
if read():upper() ~= "RESET" then print("Cancelled. Nothing changed."); return end

-- Get setup.lua first, so a wiped device can always be set up again
local setupBody
if http then
  local h = http.get(REPO .. "setup.lua?t=" .. os.epoch("utc"), nil, true)
  if h then setupBody = h.readAll(); h.close() end
  if setupBody and not load(setupBody, "@setup.lua") then setupBody = nil end
end
if not setupBody then
  printError("Can't download setup.lua right now, so I won't wipe anything.")
  printError("Check GitHub/HTTP and try again.")
  return
end

for _, name in ipairs(fs.list("/")) do
  if name ~= "startup.lua" and name ~= "rom" and fs.getDrive(name) == "hdd" then fs.delete(name) end
end
local f = fs.open("setup.lua", "wb"); f.write(setupBody); f.close()

print("Wiped. Rebooting into setup...")
os.sleep(2)
os.reboot()
