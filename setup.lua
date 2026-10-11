-- setup.lua  --  first-time setup for a device. Run by startup.lua when the device has no role.
-- Asks turtle or computer, then which role, then a label. Saves device.cfg and reboots;
-- startup.lua then downloads that role's files.

local REPO = "https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/"
local CFG  = "device.cfg"

local function colour(c) if term.isColour() then term.setTextColour(c) end end

local function fetchManifest()
  if not http then return nil, "HTTP is turned off on this server" end
  local h, err = http.get(REPO .. "manifest.lua?t=" .. os.epoch("utc"), nil, true)
  if not h then return nil, tostring(err) end
  local body = h.readAll(); h.close()
  local fn = load(body or "", "@manifest.lua", "t", {})
  if not fn then return nil, "bad download" end
  local ok, m = pcall(fn)
  if not ok or type(m) ~= "table" then return nil, "bad manifest" end
  local f = fs.open("manifest.cache", "wb"); f.write(body); f.close()
  return m
end

-- Numbered menu. options = { { key, title, about }, ... }. Enter picks the default.
local function menu(title, options, default)
  while true do
    print()
    colour(colours.yellow); print(title); colour(colours.white)
    local defIdx
    for i, o in ipairs(options) do
      if o[1] == default then defIdx = i end
      colour(o[1] == default and colours.lime or colours.white)
      write((" %d) %s"):format(i, o[2]))
      colour(colours.lightGrey)
      print(o[3] and ("  " .. o[3]) or "")
    end
    colour(colours.white)
    write(defIdx and ("Pick a number [" .. defIdx .. "]: ") or "Pick a number: ")
    local a = read()
    if a == "" and defIdx then return options[defIdx][1] end
    local n = tonumber(a)
    if n and options[n] then return options[n][1] end
    printError("Type one of the numbers.")
  end
end

term.clear(); term.setCursorPos(1, 1)
colour(colours.cyan); print("TURTLEMANCER SETUP"); colour(colours.white)

local M, why
while true do
  M, why = fetchManifest()
  if M then break end
  printError("Couldn't download the role list: " .. tostring(why))
  print("Press Enter to try again (Ctrl+T to give up).")
  read()
end

-- Best guess, so re-setting up an existing machine is mostly pressing Enter
local isTurtle = turtle ~= nil
local label = os.getComputerLabel()
local first = ((label or ""):match("^%a+") or ""):lower()
local guessType, guessRole = isTurtle and "turtle" or "computer", nil
for tk, t in pairs(M.types) do
  for rk, r in pairs(t.roles) do
    if first ~= "" and (rk == first or r.name:lower() == first) then guessType, guessRole = tk, rk end
  end
end
if not isTurtle and guessType == "turtle" then guessType, guessRole = "computer", nil end

-- 1. Type
local typeOptions = {}
for _, tk in ipairs({ "computer", "turtle" }) do
  if M.types[tk] then typeOptions[#typeOptions + 1] = { tk, M.types[tk].name } end
end
local tk
while true do
  tk = menu("What are you setting up?", typeOptions, guessType)
  if tk == "turtle" and not isTurtle then
    printError("This is a computer, not a turtle: turtle roles won't work here.")
  else break end
end
local T = M.types[tk]

-- 2. Role
local roleOptions = {}
for _, rk in ipairs(T.order) do
  local r = T.roles[rk]
  if r then roleOptions[#roleOptions + 1] = { rk, r.name, r.about } end
end
local rk = menu("Which role?", roleOptions, guessType == tk and guessRole or nil)
local R = T.roles[rk]

-- 3. Label
print()
local suggest = (label and label:lower():find(R.name:lower(), 1, true)) and label or R.name
write(("Label for this %s [%s]: "):format(tk, suggest))
local l = read()
if l == "" then l = suggest end
os.setComputerLabel(l)

local f = fs.open(CFG, "w")
f.write(textutils.serialize({ type = tk, role = rk, setAt = os.epoch("utc") }))
f.close()
if fs.exists("setup.lua") then fs.delete("setup.lua") end

print()
colour(colours.lime)
print(("Saved: %s, %s, labelled %s."):format(T.name, R.name, l))
colour(colours.white)
print("Rebooting to download its files...")
os.sleep(2)
os.reboot()
