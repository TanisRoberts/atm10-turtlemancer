-- glasses.lua  --  Smart Glasses HUD role (Advanced Peripherals 0.8; worn on the head or in a Curios slot)
--
-- Night vision with three modes:
--   AUTO  on when it's dark where you stand (block + sky light from the glasses' Environment
--         Detector) or you're in the Deep Dark; off again once it's properly bright, so the base
--         and daytime don't get washed out. Without a detector, AUTO just keeps it on.
--   ON    always on.        OFF   always off (night vision potions don't work either while off:
--                                that's the module, not this script).
--
-- HUD (Overlay Module), top-right under the potion effect icons, one line each (all optional):
--   NV AUTO: on              night vision mode + state
--   14:20  night in 3:05     Minecraft time, and real time until night / day (Environment Detector)
--   281 50 -14  NE           where you are + which way you face (Player Detector); OW coords in the Nether
--   Inv 28% [=====     ]     free inventory space (Inventory Manager in the glasses; hidden until fitted)
-- Aggro alert, top-middle: a mob within AGGRO_RANGE that's attacking (creepers in red, the Warden
-- whenever it's near), with distance and which side it's on. From the Environment Detector's scan.
--
-- The glasses' screen has three switches: Night vision AUTO/ON/OFF (keys 1/2/3), Aggro alert ON/OFF
-- (A) with a scan-speed button (S: every 2/4/8 s), and HUD ON/OFF (H). Q quits. Open the screen with
-- the glasses in your hand (right-click), or while wearing them with a Smart Glasses Interface. glasses.env holds every setting: made on first run, edit it
-- live; deleted keys come back with their defaults and your lines are never overwritten.
-- Reboot (hold Ctrl+R) to update from GitHub.

local ENV_FILE = "glasses.env"
local NV_ID    = "advancedperipherals:night_vision"
local OV_ID    = "advancedperipherals:overlay"
local INV_SLOTS = 36   -- main inventory incl. hotbar: what the Inventory Manager's getEmptySlots counts

local DEFAULTS = {
  { "NV_MODE", "auto", "Night vision: auto, on or off. The buttons on the glasses' screen change this line." },
  { "NV_DARK", 7, "AUTO: night vision comes on when the light where you stand is this or lower (0-15)." },
  { "NV_BRIGHT", 10, "AUTO: ...and goes off again at this light or higher (keep it above NV_DARK so it doesn't flicker)." },
  { "NV_DEEP_DARK", "yes", "AUTO: always on in the Deep Dark biome (yes/no)." },
  { "HUD", "yes", "Show the HUD at all (yes/no). H on the glasses' screen toggles it." },
  { "HUD_CORNER", "top-right", "Where the HUD sits: top-right, top-left, bottom-right or bottom-left." },
  { "HUD_EDGE_X", 4, "Gap from the left/right edge of the screen, in GUI pixels." },
  { "HUD_EDGE_Y", 52, "Gap from the top/bottom edge, in GUI pixels. 52 clears both rows of potion effect icons in the top-right." },
  { "HUD_NV", "yes", "HUD line: night vision mode and state (yes/no)." },
  { "HUD_CLOCK", "yes", "HUD line: Minecraft time and how long until night/day (yes/no). Needs the Environment Detector." },
  { "HUD_COORDS", "yes", "HUD line: your coordinates and facing (yes/no). Needs the Player Detector." },
  { "HUD_INV", "yes", "HUD line: free inventory space bar (yes/no). Shows once an Inventory Manager is in the glasses." },
  { "INV_BAR_W", 40, "Width of the inventory bar, in GUI pixels." },
  { "OWNER", "", "Your Minecraft name, for coordinates. Blank = worked out by the glasses and saved here." },
  { "AGGRO", "yes", "Top-middle alert when a mob near you is attacking (yes/no). Needs the Environment Detector." },
  { "AGGRO_RANGE", 8, "Blocks to scan for aggro. AP scans up to 8 for free; more needs fuel the glasses don't have." },
  { "AGGRO_IGNORE", "minecraft:wolf,minecraft:iron_golem,minecraft:snow_golem", "Mobs that never trigger the alert (comma separated ids)." },
  { "AGGRO_Y", 30, "Alert height from the top of the screen, in GUI pixels (30 clears a boss bar)." },
  { "AGGRO_HOLD", 3, "Seconds the alert stays up after the last sighting." },
  { "AGGRO_EVERY", 2, "Seconds between mob scans (2 is AP's fastest). Each scan makes AP wipe the HUD, which is redrawn at once; raise this if you still see a blink." },
  { "CHECK_EVERY", 1, "Seconds between updates." },
}

---------------------------------------------------------------------------
-- Settings (glasses.env), same rules as the mainframe's butler.env
---------------------------------------------------------------------------
local E, envStamp = {}, nil

local function stampOf(path)
  if not fs.exists(path) or not fs.attributes then return nil end
  local ok, a = pcall(fs.attributes, path)
  return ok and a and (tostring(a.modified) .. ":" .. tostring(a.size)) or nil
end

local function readEnv()
  local vals = {}
  if fs.exists(ENV_FILE) then
    local f = fs.open(ENV_FILE, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then vals[k:upper()] = v end
    end
    f.close()
  end
  local missing = {}
  for _, d in ipairs(DEFAULTS) do
    if vals[d[1]] == nil then missing[#missing + 1] = d; vals[d[1]] = tostring(d[2]) end
  end
  if #missing > 0 then
    local new = not fs.exists(ENV_FILE)
    local f = fs.open(ENV_FILE, new and "w" or "a")
    if new then f.writeLine("# Smart Glasses settings. Edit and save: the glasses pick changes up within a second or two.") end
    for _, d in ipairs(missing) do
      f.writeLine("")
      f.writeLine("# " .. d[3])
      f.writeLine(d[1] .. "=" .. tostring(d[2]))
    end
    f.close()
  end
  for _, d in ipairs(DEFAULTS) do
    local v = vals[d[1]]
    if type(d[2]) == "number" then E[d[1]] = tonumber(v) or d[2] else E[d[1]] = v end
  end
  envStamp = stampOf(ENV_FILE)
end

local function refreshEnv()
  if stampOf(ENV_FILE) ~= envStamp then readEnv() end
end

local function yes(key)
  local v = tostring(E[key]):lower()
  return v == "yes" or v == "true" or v == "on" or v == "1"
end

-- Change one setting: rewrites that KEY= line in place, leaves every other line alone
local function setEnv(key, value)
  local lines, done = {}, false
  if fs.exists(ENV_FILE) then
    local f = fs.open(ENV_FILE, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local k = line:match("^%s*([%w_]+)%s*=")
      if k and k:upper() == key and not done then line = key .. "=" .. value; done = true end
      lines[#lines + 1] = line
    end
    f.close()
  end
  if not done then lines[#lines + 1] = key .. "=" .. value end
  local f = fs.open(ENV_FILE, "w")
  f.write(table.concat(lines, "\n") .. "\n")
  f.close()
  readEnv()
end

local function mode()
  local m = tostring(E.NV_MODE):lower()
  if m == "on" or m == "off" then return m end
  return "auto"
end

---------------------------------------------------------------------------
-- Hardware: modules (via the smartglasses API, falling back to the peripheral) and peripherals
---------------------------------------------------------------------------
local glasses = peripheral.find("smart_glasses")

local function getModule(id)
  if smartglasses and type(smartglasses.modules) == "table" and smartglasses.modules[id] then
    return smartglasses.modules[id]
  end
  if glasses and glasses.getModule then
    local ok, m = pcall(glasses.getModule, id)
    if ok and type(m) == "table" then return m end
  end
  return nil
end

local nv, overlay, detector, players, invMgr
local function findHardware()
  nv = getModule(NV_ID)
  overlay = getModule(OV_ID)
  detector = peripheral.find("environment_detector") or peripheral.find("environmentDetector")
  players = peripheral.find("player_detector") or peripheral.find("playerDetector")
  invMgr = peripheral.find("inventory_manager") or peripheral.find("inventoryManager")
end

-- Fix the glasses' blank name (AP throws on getName when it was never set)
if glasses and glasses.getName and glasses.setName then
  local ok = pcall(glasses.getName)
  if not ok then pcall(glasses.setName, os.getComputerLabel() or "Glasses") end
end

local function call(obj, fn, ...)
  if not obj or type(obj[fn]) ~= "function" then return nil end
  local ok, a = pcall(obj[fn], ...)
  if ok then return a end
  return nil
end

---------------------------------------------------------------------------
-- What night vision should be doing
---------------------------------------------------------------------------
local S = {
  want = nil,        -- what AUTO decided last time (for hysteresis)
  nvOn = nil,        -- what the module says right now
  light = nil, block = nil, sky = nil, biome = nil,
  why = "",
}

local function readLight()
  S.block = call(detector, "getBlockLightLevel")
  S.sky = call(detector, "getSkyLightLevel")
  S.biome = call(detector, "getBiome")
  if S.block or S.sky then S.light = math.max(S.block or 0, S.sky or 0) else S.light = nil end
end

local function decide()
  local m = mode()
  if m == "on" then S.why = "always on"; return true end
  if m == "off" then S.why = "always off"; return false end
  if not detector then S.why = "no detector: kept on"; return true end
  readLight()
  local biome = tostring(S.biome or ""):lower()
  if yes("NV_DEEP_DARK") and biome:find("deep_dark", 1, true) then
    S.want = true; S.why = "Deep Dark"; return true
  end
  if not S.light then S.why = "light unknown: kept on"; return true end
  local dark, bright = E.NV_DARK, math.max(E.NV_BRIGHT, E.NV_DARK + 1)
  if S.light <= dark then
    S.want = true; S.why = "dark here"
  elseif S.light >= bright then
    S.want = false; S.why = "bright enough"
  else
    -- In between: keep whatever it was doing, so torch-lit edges don't flicker
    if S.want == nil then S.want = false end
    S.why = S.want and "dim: staying on" or "dim: staying off"
  end
  return S.want
end

local function apply(want)
  if not nv then S.nvOn = nil; return end
  local now = call(nv, "isNightVisionEnabled")
  if now ~= want then
    call(nv, "enableNightVision", want)
    now = call(nv, "isNightVisionEnabled")
  end
  S.nvOn = now
end

---------------------------------------------------------------------------
-- Stats: you (position, facing), clock, inventory
---------------------------------------------------------------------------
local P = {}   -- latest player info: x, y, z, yaw, dimension
local INV = {} -- free, total

-- Your name: OWNER, else the Inventory Manager's owner, else the only player standing where the
-- glasses are (saved to glasses.env so it sticks).
local function ownerName()
  if E.OWNER ~= "" then return E.OWNER end
  if invMgr and type(invMgr.getOwner) == "function" then
    local ok, _, name = pcall(invMgr.getOwner)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  if players and type(players.getPlayersInRange) == "function" then
    local ok, list = pcall(players.getPlayersInRange, 1)
    if ok and type(list) == "table" and #list == 1 and type(list[1]) == "string" then
      setEnv("OWNER", list[1])
      return list[1]
    end
  end
  return nil
end

local function readPlayer()
  P = {}
  if not players or type(players.getPlayer) ~= "function" then return end
  local name = ownerName()
  if not name then P.err = "who?"; return end
  local ok, p = pcall(players.getPlayer, name)
  if ok and type(p) == "table" and p.x then
    P = { x = p.x, y = p.y, z = p.z, yaw = p.yaw, dimension = p.dimension, name = name }
  else
    P.err = "not found"
  end
end

local function readInventory()
  INV = {}
  if not invMgr then return end
  local ok, free = pcall(invMgr.getEmptySlots)
  if ok and type(free) == "number" then INV.free, INV.total = free, INV_SLOTS else INV.err = true end
end

-- Minecraft yaw: 0 = south, 90 = west, 180 = north, 270 = east (clockwise seen from above)
local DIRS = { "S", "SW", "W", "NW", "N", "NE", "E", "SE" }
local function facing(yaw)
  if type(yaw) ~= "number" then return "?" end
  return DIRS[math.floor(((yaw % 360) + 22.5) / 45) % 8 + 1]
end

local function inNether()
  return tostring(P.dimension or ""):find("nether", 1, true) ~= nil
end

local function coordsText()
  if not P.x then return nil end
  local fl = math.floor
  local s = ("%d %d %d  %s"):format(fl(P.x), fl(P.y), fl(P.z), facing(P.yaw))
  if inNether() then s = s .. ("  OW %d %d"):format(fl(P.x * 8), fl(P.z * 8)) end
  return s
end

local function mmss(ticks)
  local secs = math.max(0, math.floor(ticks / 20 + 0.5))
  return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

-- Day 0 = 06:00. Monsters come out around 13000, and it's light again around 23000.
local function clockText()
  local t = call(detector, "getTime")
  if type(t) ~= "number" then return nil end
  t = t % 24000
  local hours = math.floor((t / 1000 + 6) % 24)
  local mins = math.floor((t % 1000) * 60 / 1000)
  local s = ("%02d:%02d"):format(hours, mins)
  local dim = tostring(P.dimension or call(detector, "getDimension") or "")
  if dim ~= "" and not dim:find("overworld", 1, true) then return s end   -- no day/night there
  if t < 13000 then
    s = s .. "  night in " .. mmss(13000 - t)
  elseif t < 23000 then
    s = s .. "  day in " .. mmss(23000 - t)
  else
    s = s .. "  dawn"
  end
  return s
end

---------------------------------------------------------------------------
-- Aggro: mobs near you that are attacking (Environment Detector entity scan)
---------------------------------------------------------------------------
local AG = { last = nil, until_ = 0, lastScan = -100, err = nil }

local function ignored(name)
  for id in tostring(E.AGGRO_IGNORE):gmatch("[^,%s]+") do
    if id == name then return true end
  end
  return false
end

-- Which side of you something is: dx/dz relative to you, your yaw from the Player Detector
local function side(dx, dz)
  if type(P.yaw) ~= "number" then return nil end
  local bearing = math.deg(math.atan2 and math.atan2(-dx, dz) or math.atan(-dx, dz))
  local diff = (bearing - P.yaw + 540) % 360 - 180
  if math.abs(diff) <= 45 then return "ahead" end
  if math.abs(diff) >= 135 then return "BEHIND" end
  return diff > 0 and "right" or "left"
end

local function scanAggro()
  if not detector or not yes("AGGRO") or type(detector.scanEntities) ~= "function" then AG.last = nil; return end
  local now = os.clock()
  if now - AG.lastScan < math.max(2, tonumber(E.AGGRO_EVERY) or 2) then return end   -- AP allows one scan every 2 s
  AG.lastScan = now
  AG.scanned = true   -- the main loop watches for the HUD wipe that follows a scan
  local range = math.max(1, math.min(16, E.AGGRO_RANGE))
  local ok, list, why = pcall(detector.scanEntities, range, true)
  if not ok or type(list) ~= "table" then AG.err = tostring(ok and why or list); return end
  AG.err = nil
  local best, bestRank, bestDist, count = nil, 0, math.huge, 0
  for _, e in ipairs(list) do
    local name = tostring(e.name or "")
    local creeper = name:find("creeper", 1, true) ~= nil
    local warden = name == "minecraft:warden"
    if (e.aggressive == true or warden) and not ignored(name) then
      local dx, dy, dz = tonumber(e.x) or 0, tonumber(e.y) or 0, tonumber(e.z) or 0
      local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
      local rank = creeper and 3 or (warden and 2 or 1)
      count = count + 1
      if rank > bestRank or (rank == bestRank and dist < bestDist) then
        best = { name = e.displayName or name, dist = dist, side = side(dx, dz), creeper = creeper, warden = warden }
        bestRank, bestDist = rank, dist
      end
    end
  end
  if best then
    best.others = count - 1
    AG.last = best
    AG.until_ = now + math.max(0, E.AGGRO_HOLD)
  elseif now >= AG.until_ then
    AG.last = nil
  end
end

---------------------------------------------------------------------------
-- HUD objects (Overlay Module, GUI space). Each object is created once and only updated when a
-- field changes. AP wipes them all when the glasses come off, and setters on a wiped object do
-- nothing, so we also check now and then that they still exist.
---------------------------------------------------------------------------
local hud = {}     -- key -> { obj = overlay object, kind = "Text"/"Rectangle", shown = { field = value } }
local diag = {}    -- what the overlay told us last, shown on the glasses' screen

local function setterFor(field)
  return "set" .. field:sub(1, 1):upper() .. field:sub(2)
end

local function hudPut(key, kind, props)
  if not overlay then return end
  props.enabled = true
  local e = hud[key]
  if e and e.kind == kind then
    local ok = pcall(function()
      for field, v in pairs(props) do
        if e.shown[field] ~= v then
          e.obj[setterFor(field)](v)
          e.shown[field] = v
        end
      end
    end)
    if ok then return end
    hud[key] = nil
  end
  local create = overlay["create" .. kind]
  if type(create) ~= "function" then return end
  local init = { gui = true }
  for k, v in pairs(props) do init[k] = v end
  local ok, obj = pcall(create, init)
  if ok and type(obj) == "table" then
    local shown = {}
    for k, v in pairs(props) do shown[k] = v end
    hud[key] = { obj = obj, kind = kind, shown = shown, born = os.clock() }
    diag.err = nil
  else
    diag.err = (not ok) and tostring(obj) or ("create" .. kind .. " gave " .. type(obj))
  end
end

local function hudHide(key)
  local e = hud[key]
  if e and e.shown.enabled ~= false then
    if pcall(e.obj.setEnabled, false) then e.shown.enabled = false end
  end
end

local function hudHideAll(except)
  for key in pairs(hud) do
    if not (except and except[key]) then hudHide(key) end
  end
end

local function hudForget()
  hud = {}
end

-- hud.log: one line per notable event (boots, HUD wiped by something else, glasses on/off,
-- module events), last LOG_KEEP lines. Times are seconds since this boot (os.clock).
local LOG_FILE, LOG_KEEP = "hud.log", 60
local BOOT = ("%04x"):format(math.random(0, 0xFFFF))   -- tells two copies of this program apart in the log
local function hudLog(msg)
  pcall(function()
    local lines = {}
    if fs.exists(LOG_FILE) then
      local f = fs.open(LOG_FILE, "r")
      for line in f.readAll():gmatch("[^\n]+") do lines[#lines + 1] = line end
      f.close()
    end
    lines[#lines + 1] = ("%s %7.1f %s"):format(BOOT, os.clock(), msg)
    while #lines > LOG_KEEP do table.remove(lines, 1) end
    local f = fs.open(LOG_FILE, "w")
    f.write(table.concat(lines, "\n") .. "\n")
    f.close()
  end)
end

-- AP only lists a new object after its next server tick, so ignore ones younger than that.
local YOUNG = 0.15

local function hudCheckAlive(why, quiet)
  if not overlay or type(overlay.getObject) ~= "function" then return 0 end
  local had, lost = 0, 0
  local now = os.clock()
  for key, e in pairs(hud) do
    local okId, id = pcall(e.obj.getId)
    if okId and id ~= nil and now - (e.born or 0) >= YOUNG then
      had = had + 1
      local okGet, o = pcall(overlay.getObject, id)
      if okGet and o == nil then hud[key] = nil; lost = lost + 1 end
    end
  end
  if lost > 0 then
    diag.wipes = (diag.wipes or 0) + 1
    if not quiet then
      hudLog(("lost %d/%d HUD objects (%s), %d on server, equipped=%s"):format(lost, had, why or "check",
        tonumber(call(overlay, "getObjectsCount")) or -1, tostring(diag.equipped)))
    end
  end
  return lost
end

local function hudCount()
  local n = 0
  for _ in pairs(hud) do n = n + 1 end
  return n
end

-- Minecraft's default font: most characters are 6 GUI pixels wide (5 + 1 spacing). Used to
-- right-align, since text objects only know left and centre.
local NARROW = { ["i"] = 2, ["!"] = 2, ["."] = 2, [","] = 2, [":"] = 2, [";"] = 2, ["'"] = 2, ["|"] = 2,
  ["l"] = 3, ["`"] = 3, ["I"] = 4, ["t"] = 4, ["["] = 4, ["]"] = 4, [" "] = 4,
  ["f"] = 5, ["k"] = 5, ["<"] = 5, [">"] = 5, ["("] = 5, [")"] = 5, ["{"] = 5, ["}"] = 5, ["*"] = 5 }
local function textWidth(str)
  local w = 0
  for ch in tostring(str):gmatch(".") do w = w + (NARROW[ch] or 6) end
  return math.max(0, w - 1)   -- no spacing after the last character
end

-- Screen size in GUI pixels (the overlay reports the window in real pixels + the GUI scale)
local function guiSize()
  local ok, w, h, scale = pcall(overlay.getGuiSize)
  diag.w, diag.h, diag.scale = ok and w or nil, ok and h or nil, ok and scale or nil
  if not ok or type(w) ~= "number" or w <= 0 then return nil end
  scale = (type(scale) == "number" and scale > 0) and scale or 1
  return w / scale, h / scale
end

local LINE_H = 11

local function nvText()
  if not nv then return "NV: no module", 0xFF5555 end
  return ("NV %s: %s"):format(mode():upper(), S.nvOn and "on" or "off"), S.nvOn and 0x55FF55 or 0xAAAAAA
end

local function invColour(frac)
  if frac >= 0.5 then return 0x55FF55 end
  if frac >= 0.2 then return 0xFFAA00 end
  return 0xFF5555
end

local function drawHud()
  if not overlay then hudForget(); return end
  if not yes("HUD") then hudHideAll(); return end
  local gw, gh = guiSize()
  local corner = tostring(E.HUD_CORNER):lower()
  local right = gw and corner:find("right", 1, true) ~= nil
  local bottom = gh and corner:find("bottom", 1, true) ~= nil
  local used = {}

  -- Build the rows: { key, text, colour } or the inventory bar row
  local rows = {}
  if yes("HUD_NV") then
    local t, c = nvText()
    rows[#rows + 1] = { key = "nv", text = t, colour = c }
  end
  if yes("HUD_CLOCK") then
    local t = clockText()
    if t then rows[#rows + 1] = { key = "clock", text = t, colour = 0xFFFFFF } end
  end
  if yes("HUD_COORDS") then
    local t = coordsText()
    if t then rows[#rows + 1] = { key = "coords", text = t, colour = 0xFFFFFF } end
  end
  if yes("HUD_INV") and INV.free then
    local frac = INV.total > 0 and INV.free / INV.total or 0
    rows[#rows + 1] = { key = "inv", bar = true, frac = frac,
      text = ("Inv %d%%"):format(math.floor(frac * 100 + 0.5)), colour = invColour(frac) }
  end

  -- Lay them out from the corner
  local edgeX, edgeY = E.HUD_EDGE_X, E.HUD_EDGE_Y
  local barW = math.max(10, E.INV_BAR_W)
  for i, r in ipairs(rows) do
    local y = bottom and (gh - edgeY - 9 - (#rows - i) * LINE_H) or (edgeY + (i - 1) * LINE_H)
    local width = textWidth(r.text) + (r.bar and (4 + barW) or 0)
    local x = right and (gw - edgeX - width) or edgeX
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if i == 1 then diag.x, diag.y = x, y end
    hudPut(r.key, "Text", { x = x, y = y, content = r.text, color = r.colour, shadow = true })
    used[r.key] = true
    if r.bar then
      local bx = x + textWidth(r.text) + 4
      hudPut("invBg", "Rectangle", { x = bx, y = y + 1, sizeX = barW, sizeY = 6, color = 0x000000, opacity = 0.55 })
      hudPut("invFill", "Rectangle", { x = bx, y = y + 1, sizeX = math.floor(barW * r.frac + 0.5), sizeY = 6,
        color = r.colour, opacity = 0.9 })
      used.invBg, used.invFill = true, true
    end
  end

  -- Aggro alert, top-middle
  if AG.last and gw then
    local a = AG.last
    local label = (a.creeper or a.warden) and tostring(a.name):upper() or tostring(a.name)
    local text = ("! %s %dm%s"):format(label, math.floor(a.dist + 0.5), a.side and (" " .. a.side) or "")
    if a.others and a.others > 0 then text = text .. (" +%d"):format(a.others) end
    local blink = math.floor(os.clock() * 2) % 2 == 0
    local colour = (a.creeper or a.warden) and (blink and 0xFF3333 or 0xFFAA00) or 0xFFAA00
    hudPut("aggro", "Text", { x = math.floor(gw / 2 + 0.5), y = E.AGGRO_Y, content = text, color = colour,
      shadow = true, center = true, fontSize = 1.5 })
    used.aggro = true
  end

  hudHideAll(used)
end

---------------------------------------------------------------------------
-- The glasses' own screen
---------------------------------------------------------------------------
local W, H = term.getSize()
local COLOUR = term.isColour()
local hits = {}

local function at(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setBackgroundColour(COLOUR and bg or colours.black)
  term.setTextColour(COLOUR and fg or colours.white)
  term.write(s)
end
local function fill(y, bg) at(1, y, (" "):rep(W), colours.white, bg) end

local function setMode(m)
  if m ~= mode() then setEnv("NV_MODE", m) end
  S.want = nil
end

local function setYes(key, on) setEnv(key, on and "yes" or "no") end
local SPEEDS = { 2, 4, 8 }
local function aggroEvery() return math.max(2, tonumber(E.AGGRO_EVERY) or 2) end
local function nextSpeed()
  local cur = aggroEvery()
  for _, v in ipairs(SPEEDS) do if v > cur then return v end end
  return SPEEDS[1]
end

-- Segmented switch: [AUTO][ ON ][OFF ]. opts = { {value, text, action}, ... }. Returns the next free x.
local function switch(x, y, opts, current)
  for _, o in ipairs(opts) do
    local on = o[1] == current
    local text = " " .. o[2] .. " "
    at(x, y, text, on and colours.black or colours.white, on and colours.cyan or colours.grey)
    hits[#hits + 1] = { y = y, x1 = x, x2 = x + #text - 1, action = o[3] }
    x = x + #text
  end
  return x
end

local function button(x, y, text, action)
  text = " " .. text .. " "
  at(x, y, text, colours.white, colours.grey)
  hits[#hits + 1] = { y = y, x1 = x, x2 = x + #text - 1, action = action }
  return x + #text
end

local function fit(s) return tostring(s):sub(1, W - 3) end

-- One setting: label, switch (and extra button) on the same line when it fits, else on the next,
-- then a status line. Returns the next y.
local LABEL_W = 13
local function setting(y, label, opts, current, status, statusColour, extra)
  local need = 0
  for _, o in ipairs(opts) do need = need + #o[2] + 2 end
  if extra then need = need + #extra[1] + 3 end
  at(2, y, label, colours.white, colours.black)
  local x = 2 + LABEL_W
  if x + need - 1 > W then y = y + 1; x = 4 end
  x = switch(x, y, opts, current)
  if extra then button(x + 1, y, extra[1], extra[2]) end
  at(4, y + 1, fit(status), statusColour or colours.lightGrey, colours.black)
  return y + 3
end

local function drawScreen()
  hits = {}
  term.setBackgroundColour(colours.black); term.clear()
  fill(1, colours.grey)
  at(2, 1, "GLASSES", colours.cyan, colours.grey)
  local label = os.getComputerLabel() or ""
  at(W - #label, 1, label, colours.lightGrey, colours.grey)

  local y = 3

  -- Night vision
  local nvStatus, nvColour
  if not nv then nvStatus, nvColour = "No Night Vision Module fitted", colours.red
  else nvStatus, nvColour = (S.nvOn and "on - " or "off - ") .. tostring(S.why), S.nvOn and colours.lime or colours.lightGrey end
  y = setting(y, "Night vision", {
    { "auto", "AUTO", function() setMode("auto") end },
    { "on",   "ON",   function() setMode("on") end },
    { "off",  "OFF",  function() setMode("off") end },
  }, mode(), nvStatus, nvColour)

  -- Aggro alert
  local agOn = yes("AGGRO")
  local agStatus, agColour
  if not detector then agStatus, agColour = "Needs an Environment Detector", colours.orange
  elseif not agOn then agStatus, agColour = "off - HUD stays steady", colours.lightGrey
  elseif AG.err then agStatus, agColour = "scan failed: " .. AG.err, colours.orange
  elseif AG.last then
    local a = AG.last
    agStatus = ("! %s %dm%s"):format(tostring(a.name), math.floor(a.dist + 0.5), a.side and (" " .. a.side) or "")
    agColour = (a.creeper or a.warden) and colours.red or colours.orange
  else
    agStatus, agColour = ("on - %d blocks, HUD blinks each scan"):format(math.max(1, math.min(16, E.AGGRO_RANGE))), colours.lightGrey
  end
  y = setting(y, "Aggro alert", {
    { true,  "ON",  function() setYes("AGGRO", true) end },
    { false, "OFF", function() setYes("AGGRO", false) end },
  }, agOn, agStatus, agColour,
    { ("every %ds"):format(aggroEvery()), function() setEnv("AGGRO_EVERY", tostring(nextSpeed())) end })

  -- HUD
  local hudOn = yes("HUD")
  local hudStatus, hudColour = nil, colours.lightGrey
  if not overlay then hudStatus, hudColour = "No Overlay Module fitted", colours.red
  elseif diag.err then hudStatus, hudColour = "error: " .. diag.err, colours.orange
  elseif not hudOn then hudStatus = "off"
  elseif diag.equipped == false then hudStatus = "shows when you wear the glasses"
  else
    local n = tonumber(call(overlay, "getObjectsCount")) or 0
    local corner = tostring(E.HUD_CORNER):lower()
    hudStatus = ("%d obj, %s"):format(n, corner)
    if diag.w == 0 or diag.w == nil then hudStatus = "waiting for the screen size" end
    local other = (diag.wipes or 0) - (diag.scanWipes or 0)
    if (diag.scanWipes or 0) > 0 then hudStatus = hudStatus .. (", scan %d"):format(diag.scanWipes) end
    if other > 0 then hudStatus, hudColour = hudStatus .. (", wiped %d"):format(other), colours.orange end
  end
  y = setting(y, "HUD", {
    { true,  "ON",  function() setYes("HUD", true) end },
    { false, "OFF", function() setYes("HUD", false) end },
  }, hudOn, hudStatus, hudColour)

  -- What the sensors see (only if there's a spare line above the footer)
  if y <= H - 1 then
    local bits = {}
    bits[#bits + 1] = players and (P.name or "player ?") or "no player detector"
    if invMgr then bits[#bits + 1] = INV.free and ("inv %d/%d free"):format(INV.free, INV.total) or "inv ?" end
    if detector then
      local biome = tostring(S.biome or "?"):gsub("^[%w_%.%-]+:", "")
      bits[#bits + 1] = ("light %s %s"):format(S.light and tostring(S.light) or "?", biome)
    end
    at(2, H - 1, fit(table.concat(bits, " | ")), colours.grey, colours.black)
  end

  -- Footer: keys
  fill(H, colours.black)
  local keys
  for _, k in ipairs({ "1-3 NV  A aggro  S speed  H HUD  Q quit", "1-3 NV A aggro S speed H HUD Q quit", "keys: 1-3 A S H Q" }) do
    if #k <= W - 2 then keys = k; break end
  end
  keys = keys or "keys: 1-3 A S H Q"
  at(2, H, keys:sub(1, W - 2), colours.grey, colours.black)
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
readEnv()
findHardware()
math.randomseed(os.epoch and os.epoch("utc") or os.time())
BOOT = ("%04x"):format(math.random(0, 0xFFFF))
hudLog(("boot: computer #%d %s"):format(os.getComputerID(), tostring(os.getComputerLabel())))
call(overlay, "clear")   -- drop the HUD left over from before the reboot

-- AP wipes every overlay object when the glasses come off (incl. opening the terminal with them
-- in your hand). So: rebuild the HUD the moment they go back on.
local wasEquipped = nil
local function equipped()
  if smartglasses and smartglasses.isEquipped then
    local ok, v = pcall(smartglasses.isEquipped)
    if ok then return v and true or false end
  end
  return true
end

local ticks = 0
local function tick()
  ticks = ticks + 1
  local eq = equipped()
  diag.equipped = eq
  if wasEquipped ~= nil and eq ~= wasEquipped then
    diag.flips = (diag.flips or 0) + 1
    hudLog(eq and "glasses on" or "glasses off")
  end
  -- Re-create whatever AP removed (never clear everything ourselves: that made the HUD flash).
  -- Checked every update so anything wiped from outside comes back within one update.
  hudCheckAlive(eq and wasEquipped == false and "put back on" or nil)
  wasEquipped = eq
  refreshEnv()
  apply(decide())
  readPlayer()
  readInventory()
  scanAggro()
  drawHud()
  drawScreen()
end

-- After each mob scan AP rewrites the glasses' saved data and, a tick or so later, wipes every HUD
-- object. Watch closely for a moment after each scan and redraw the instant it happens, so the
-- HUD only blinks for a tick or two instead of disappearing until the next update.
local WATCH_FOR, WATCH_STEP = 0.6, 0.05
local watchUntil, watchTimer = 0, nil
local function afterTick()
  if AG.scanned then
    AG.scanned = false
    watchUntil = os.clock() + WATCH_FOR
    watchTimer = os.startTimer(WATCH_STEP)
  end
end
local function watchStep()
  watchTimer = nil
  if hudCheckAlive("after scan", true) > 0 then
    diag.scanWipes = (diag.scanWipes or 0) + 1
    drawHud()
    watchUntil = 0   -- one wipe per scan
  end
  if os.clock() < watchUntil then watchTimer = os.startTimer(WATCH_STEP) end
end

tick(); afterTick()
local timer = os.startTimer(math.max(0.25, E.CHECK_EVERY))
while true do
  local e, a, b, c = os.pullEvent()
  local act
  if e == "timer" and a == timer then
    tick(); afterTick()
    timer = os.startTimer(math.max(0.25, E.CHECK_EVERY))
  elseif e == "timer" and a == watchTimer then
    watchStep()
  elseif e == "mouse_click" then
    for _, r in ipairs(hits) do
      if c == r.y and (not r.x1 or (b >= r.x1 and b <= r.x2)) then act = r.action; break end
    end
  elseif e == "char" then
    local ch = a:lower()
    if ch == "1" then act = function() setMode("auto") end
    elseif ch == "2" then act = function() setMode("on") end
    elseif ch == "3" then act = function() setMode("off") end
    elseif ch == "h" then act = function() setYes("HUD", not yes("HUD")) end
    elseif ch == "a" then act = function() setYes("AGGRO", not yes("AGGRO")) end
    elseif ch == "s" then act = function() setEnv("AGGRO_EVERY", tostring(nextSpeed())) end
    elseif ch == "q" then
      hudHideAll()
      term.setBackgroundColour(colours.black); term.clear(); term.setCursorPos(1, 1)
      print("Glasses HUD stopped. Night vision stays as it was. Reboot to start again.")
      return
    end
  elseif e == "glasses_module" or e == "glasses_module_detach" or e == "peripheral" or e == "peripheral_detach" then
    hudLog(e .. " " .. tostring(a))
    findHardware()
    act = function() hudCheckAlive() end
  elseif e == "term_resize" then
    W, H = term.getSize()
    act = function() end
  end
  if act then
    act()
    tick(); afterTick()
  end
end
