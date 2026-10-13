-- startup.lua  --  the only file you ever put on a device by hand (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Drag this onto any computer or turtle and reboot (hold Ctrl+R).
--   * No role yet:  downloads setup.lua, which asks what this device is (turtle/computer + role).
--   * Has a role:   pulls that role's latest files from GitHub (see manifest.lua), then starts it.
-- Reboot to update. Type "reset" to wipe the device and pick a new role.
--
-- Safety: if GitHub can't be reached, or a download looks broken, the old files stay and it
-- boots anyway. .lua files must compile before they replace old ones. Files marked "once" in the
-- manifest (your edits, big data) are only fetched if missing. State/config files are never touched.

local REPO     = "https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/"
local CFG      = "device.cfg"
local MANIFEST = "manifest.cache"   -- last good manifest, for booting offline
local BOOT_PAUSE = 1                 -- seconds to leave the update summary on screen before the role starts

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "rb"); local s = f.readAll(); f.close()
  return s
end

local function writeFile(path, body)
  local tmp = path .. ".new"
  local f = fs.open(tmp, "wb"); f.write(body); f.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(tmp, path)
end

local function baseName(p) return p:match("([^/]+)$") end

-- Returns the file's contents, or nil + why. Once GitHub is unreachable, stop trying (no long hangs).
local offline = false
local function fetch(path)
  if offline then return nil, "offline" end
  if not http then offline = true; return nil, "HTTP is turned off on this server" end
  local ok, h, err = pcall(http.get, REPO .. path .. "?t=" .. os.epoch("utc"), nil, true)
  if not ok or not h then
    err = tostring(ok and err or h)
    if not err:find("404") and not err:find("Not Found") then offline = true end
    return nil, err
  end
  local code = h.getResponseCode and h.getResponseCode() or 200
  local body = h.readAll()
  h.close()
  if code ~= 200 then return nil, "HTTP " .. code end
  if not body or #body == 0 then return nil, "empty download" end
  return body
end

-- Fetch a repo file and replace the local copy if it changed and looks sane.
local function update(path)
  local name = baseName(path)
  local body, why = fetch(path)
  if not body then return "failed", why end
  if name:match("%.lua$") then
    local fn, err = load(body, "@" .. name)
    if not fn then return "failed", "doesn't compile: " .. tostring(err) end
  end
  if body == readFile(name) then return "same" end
  writeFile(name, body)
  return "updated"
end

local function say(colour, text)
  if term.isColour() then term.setTextColour(colour) end
  print(text)
  term.setTextColour(colours.white)
end

---------------------------------------------------------------------------
-- Duplicate ID check
-- A computer's files live in a folder named after its ID. If two machines end up with the same ID
-- (ComputerCraft's ID counter resets after a bad server crash, or a computer gets copied), they
-- share ONE disk, and whichever was set up last takes over the other. owner.cfg remembers which
-- machine this disk belongs to (label + hardware). If a different machine boots from it, stop and ask.
-- Not a false alarm on: `reset` (deletes owner.cfg; the next boot records whoever is here), setup
-- relabelling, `label set`, Diggers naming themselves (all go through os.setComputerLabel, which is
-- wrapped below to keep owner.cfg up to date), or crafting a computer into a turtle (same label).
---------------------------------------------------------------------------
local OWNER = "owner.cfg"

local function hardware()
  if turtle then return "turtle" end
  if smartglasses then return "glasses" end
  if pocket then return "pocket computer" end
  return "computer"
end

local function saveOwner(lbl)
  local f = fs.open(OWNER, "w")
  f.write(textutils.serialize({ label = lbl, kind = hardware(), id = os.getComputerID(), at = os.epoch("utc") }))
  f.close()
end

local function wrapText(s, w)
  local out, line = {}, ""
  for word in s:gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end

-- Returns true to carry on booting, false to stop (left at the shell).
local function ownerCheck()
  local here = { label = os.getComputerLabel(), kind = hardware() }
  local own = textutils.unserialize(readFile(OWNER) or "")
  if type(own) ~= "table" then saveOwner(here.label); return true end   -- fresh disk / first boot with this check
  if own.label == here.label and own.kind == here.kind then return true end
  if own.label == here.label and own.kind == "computer" and here.kind == "turtle" then
    saveOwner(here.label); return true                                       -- a computer crafted into a turtle keeps its ID
  end

  local function name(x) return (x.label and ('"' .. x.label .. '"') or "(no label)") .. " (" .. tostring(x.kind) .. ")" end
  local role = "nothing yet"
  local dc = textutils.unserialize(readFile(CFG) or "")
  if type(dc) == "table" and dc.role then role = tostring(dc.role) .. " " .. tostring(dc.type) end
  local id = os.getComputerID()
  local W, H = term.getSize()
  local colour = term.isColour()

  local function draw(lines, options)
    term.setBackgroundColour(colours.black); term.clear()
    if colour then term.setBackgroundColour(colours.red) end
    term.setCursorPos(1, 1); term.clearLine()
    term.setTextColour(colours.white); term.write(" DUPLICATE ID #" .. id .. "?")
    term.setBackgroundColour(colours.black)
    local y = 3
    for _, l in ipairs(lines) do
      for _, part in ipairs(wrapText(l[1], W - 1)) do
        if y <= H then
          term.setCursorPos(1, y); term.setTextColour(colour and l[2] or colours.white); term.write(part)
        end
        y = y + 1
      end
    end
    local rows = {}
    y = math.max(y + 1, H - #options * 2 + 1)
    for i, o in ipairs(options) do
      local parts = wrapText("[" .. i .. "] " .. o, W - 1)
      rows[i] = { y, y + #parts - 1 }
      for _, part in ipairs(parts) do
        if y <= H then
          term.setCursorPos(1, y); term.setTextColour(colour and colours.yellow or colours.white); term.write(part)
        end
        y = y + 1
      end
    end
    term.setTextColour(colours.white)
    return rows
  end

  local function choose(rows, n)
    while true do
      local e, a, _, my = os.pullEvent()
      if e == "char" and tonumber(a) and tonumber(a) >= 1 and tonumber(a) <= n then return tonumber(a) end
      if e == "mouse_click" then
        for i, r in ipairs(rows) do if my >= r[1] and my <= r[2] then return i end end
      end
    end
  end

  local rows = draw({
    { "This disk belongs to " .. name(own) .. ".", colours.white },
    { "This is " .. name(here) .. ".", colours.white },
    { "Set up as: " .. role .. ".", colours.lightGrey },
    { "Two machines with the same ID share their files.", colours.orange },
  }, { "Same machine, carry on", "Stop: show the fix" })

  if choose(rows, 2) == 1 then saveOwner(here.label); term.clear(); term.setCursorPos(1, 1); return true end

  draw({
    { "1. Keep one, replace the other (glasses: replace the computer).", colours.white },
    { "2. Craft a NEW one at a crafting table, swap it in, drag startup.lua on it.", colours.white },
    { "3. Destroy the old item: it still has ID #" .. id .. ".", colours.white },
    { "4. Reboot the one you kept, pick [1]. Wrong program? Type: reset", colours.white },
    { "Full guide: README, Duplicate IDs.", colours.lightGrey },
  }, {})
  term.setCursorPos(1, H)
  return false
end

if not ownerCheck() then return end

-- Keep owner.cfg in step with label changes made on this machine (setup, `label set`, Diggers naming themselves)
do
  local setLabel = os.setComputerLabel
  os.setComputerLabel = function(lbl)
    setLabel(lbl)
    pcall(saveOwner, lbl)
  end
end

---------------------------------------------------------------------------
-- No role yet: run setup
---------------------------------------------------------------------------
if not fs.exists(CFG) then
  local body = fetch("setup.lua")
  if body and load(body, "@setup.lua") then writeFile("setup.lua", body) end
  if not fs.exists("setup.lua") then
    printError("Can't download setup.lua: " .. (offline and "GitHub unreachable" or "bad download"))
    printError("Check the server allows HTTP, then reboot (hold Ctrl+R).")
    return
  end
  shell.run("setup")
  return
end

---------------------------------------------------------------------------
-- Has a role: update its files, then run it
---------------------------------------------------------------------------
local cfg = textutils.unserialize(readFile(CFG) or "") or {}

-- startup.lua updating itself: the new version only takes effect from the next boot, so reboot once.
-- REBOOT_FLAG stops a loop (e.g. GitHub's cache serving old and new copies by turns): it's set just
-- before that reboot and cleared on the boot after, which never reboots again.
local REBOOT_FLAG = "startup.reboot"
local secondBoot = fs.exists(REBOOT_FLAG)
if secondBoot then fs.delete(REBOOT_FLAG) end

local function loadManifest(body)
  local fn = load(body, "@manifest.lua", "t", {})
  if not fn then return nil end
  local ok, m = pcall(fn)
  if ok and type(m) == "table" and type(m.types) == "table" then return m end
end

local M
local fresh = fetch("manifest.lua")
if fresh then
  M = loadManifest(fresh)
  if M and fresh ~= readFile(MANIFEST) then writeFile(MANIFEST, fresh) end
end
if not M and fs.exists(MANIFEST) then M = loadManifest(readFile(MANIFEST)) end
if not M then
  printError("No manifest (GitHub unreachable and nothing cached). Reboot to try again.")
  return
end

local T = M.types[cfg.type]
local R = T and T.roles[cfg.role]
local label = os.getComputerLabel()
say(colours.cyan, ("Turtlemancer: %s %s%s"):format(R and R.name or tostring(cfg.role), T and T.name:lower() or tostring(cfg.type),
  label and (" (" .. label .. ")") or ""))
if not R then
  printError("That role isn't in the manifest any more. Type: reset")
  return
end

local changed, problems = {}, {}
local function track(path, res, why)
  if res == "updated" then changed[#changed + 1] = baseName(path)
  elseif res == "failed" then problems[#problems + 1] = baseName(path) .. " (" .. tostring(why) .. ")" end
end
for _, path in ipairs(M.common or {}) do if not offline then track(path, update(path)) end end
for _, path in ipairs(R.files or {}) do if not offline then track(path, update(path)) end end
for _, path in ipairs(R.once or {}) do
  if not offline and not fs.exists(baseName(path)) then
    local res = update(path)
    if res == "updated" then changed[#changed + 1] = baseName(path) end
  end
end

if offline then
  printError("Couldn't reach GitHub: starting with the files I already have.")
elseif #changed > 0 then
  print("Updated: " .. table.concat(changed, ", "))
else
  print("Already up to date.")
end
if not offline then for _, p in ipairs(problems) do printError("Kept old " .. p) end end

local selfUpdated = false
for _, n in ipairs(changed) do if n == "startup.lua" then selfUpdated = true end end
if selfUpdated and not secondBoot then
  say(colours.yellow, "startup.lua changed: rebooting to use it...")
  local f = fs.open(REBOOT_FLAG, "w"); f.write("1"); f.close()
  os.sleep(1)
  os.reboot()
end

if fs.exists(R.run .. ".lua") then
  if BOOT_PAUSE > 0 then os.sleep(BOOT_PAUSE) end
  shell.run(R.run)
else
  printError(R.run .. ".lua is missing and couldn't be downloaded. Reboot to try again.")
end
