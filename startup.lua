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

if fs.exists(R.run .. ".lua") then
  shell.run(R.run)
else
  printError(R.run .. ".lua is missing and couldn't be downloaded. Reboot to try again.")
end
