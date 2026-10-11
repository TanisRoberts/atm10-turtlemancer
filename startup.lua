-- startup.lua  --  boots every machine on the island (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- On every boot: pulls this machine's latest scripts from GitHub, then starts its program.
-- Reboot (hold Ctrl+R) to update.
--
-- Which files a machine gets depends on its label (first word, so "Digger-2" counts as Digger):
--   Digger -> miner     Rigger -> rigger     Tigger -> lumberjack     Figger -> farmer
--   any computer that isn't a turtle -> base (island, storage, miner panel, links)
-- Put a role name in role.txt to override (e.g. "miner").
--
-- Safety:
--   * If GitHub can't be reached, or a download looks broken, the old file stays and it boots anyway.
--   * .lua files must compile before they replace the old ones.
--   * Files you edit (junk.txt, smelt.txt) and data (mossy.plan) are only fetched if missing.
--   * State and config files (*.state, *.cfg, *.zone) are never touched.

local REPO = "https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/"

local ROLES = {
  base       = { run = "base",       files = { "startup.lua", "base.lua", "island.lua", "storage.lua",
                                               "miner_panel.lua", "rigger_link.lua", "farm_link.lua" },
                                     once  = { "smelt.txt" } },
  miner      = { run = "miner",      files = { "startup.lua", "miner.lua" },      once = { "junk.txt" } },
  rigger     = { run = "rigger",     files = { "startup.lua", "rigger.lua" },     once = { "mossy.plan" } },
  lumberjack = { run = "lumberjack", files = { "startup.lua", "lumberjack.lua" } },
  farmer     = { run = "farmer",     files = { "startup.lua", "farmer.lua" } },
}
local BY_NAME = { digger = "miner", rigger = "rigger", tigger = "lumberjack", figger = "farmer" }

local function readFile(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "rb"); local s = f.readAll(); f.close()
  return s
end

local function roleOf()
  local forced = readFile("role.txt")
  forced = forced and forced:match("%a+")
  if forced and ROLES[forced:lower()] then return forced:lower() end
  local first = ((os.getComputerLabel() or ""):match("^%a+") or ""):lower()
  if BY_NAME[first] then return BY_NAME[first] end
  if not turtle then return "base" end
end

-- Returns the file's contents, or nil + why. `offline` is set when GitHub can't be reached at all.
local offline = false
local function fetch(name)
  if offline then return nil, "offline" end
  if not http then offline = true; return nil, "HTTP is turned off on this server" end
  local ok, h, err = pcall(http.get, REPO .. name .. "?t=" .. os.epoch("utc"), nil, true)
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

local function install(name, body)
  local tmp = name .. ".new"
  local f = fs.open(tmp, "wb"); f.write(body); f.close()
  if fs.exists(name) then fs.delete(name) end
  fs.move(tmp, name)
end

-- Fetch `name` and replace the local copy if it changed and looks sane.
local function update(name)
  local body, why = fetch(name)
  if not body then return "failed", why end
  if name:match("%.lua$") then
    local fn, err = load(body, "@" .. name)
    if not fn then return "failed", "doesn't compile: " .. tostring(err) end
  end
  if body == readFile(name) then return "same" end
  install(name, body)
  return "updated"
end

local role = roleOf()
local R = role and ROLES[role]
term.setTextColour(colours.cyan)
print(("Turtlemancer: %s"):format(role and ("role " .. role) or "unknown machine"))
term.setTextColour(colours.white)

if not R then
  printError("I don't know what this machine is. Label it (Digger, Rigger, Tigger, Figger)")
  printError("or put a role name in role.txt, then reboot.")
  return
end

local changed, problems = {}, {}
for _, name in ipairs(R.files) do
  local res, why = update(name)
  if res == "updated" then changed[#changed + 1] = name
  elseif res == "failed" then problems[#problems + 1] = name .. " (" .. tostring(why) .. ")" end
  if offline then break end
end
for _, name in ipairs(R.once or {}) do
  if not offline and not fs.exists(name) then
    local res = update(name)
    if res == "updated" then changed[#changed + 1] = name end
  end
end

if offline then
  printError("Couldn't reach GitHub: starting with the files I already have.")
elseif #changed > 0 then
  print("Updated: " .. table.concat(changed, ", "))
else
  print("Already up to date.")
end
for _, p in ipairs(problems) do
  if not offline then printError("Kept old " .. p) end
end

if fs.exists(R.run .. ".lua") then
  shell.run(R.run)
else
  printError(R.run .. ".lua is missing and couldn't be downloaded.")
end
