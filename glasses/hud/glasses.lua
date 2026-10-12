-- glasses.lua  --  Smart Glasses HUD role (Advanced Peripherals 0.8; worn on the head or in a Curios slot)
--
-- Night vision with three modes:
--   AUTO  on when it's dark where you stand (block + sky light from the glasses' Environment
--         Detector) or you're in the Deep Dark; off again once it's properly bright, so the base
--         and daytime don't get washed out. Without a detector, AUTO just keeps it on.
--   ON    always on.        OFF   always off (night vision potions don't work either while off:
--                                that's the module, not this script).
-- A small HUD line (Overlay Module) shows the mode and whether night vision is on right now.
--
-- Switch modes on the glasses' screen: click a button or press 1 / 2 / 3. H toggles the HUD,
-- Q quits. Open the screen with the glasses in your hand (right-click), or while wearing them
-- with a Smart Glasses Interface. The mode is saved to glasses.env, so a reboot keeps it.
-- glasses.env holds the tunables: made on first run, edit it live; deleted keys come back with
-- their defaults and your lines are never overwritten. Reboot (hold Ctrl+R) to update from GitHub.

local ENV_FILE = "glasses.env"
local NV_ID    = "advancedperipherals:night_vision"
local OV_ID    = "advancedperipherals:overlay"

local DEFAULTS = {
  { "NV_MODE", "auto", "Night vision: auto, on or off. The buttons on the glasses' screen change this line." },
  { "NV_DARK", 7, "AUTO: night vision comes on when the light where you stand is this or lower (0-15)." },
  { "NV_BRIGHT", 10, "AUTO: ...and goes off again at this light or higher (keep it above NV_DARK so it doesn't flicker)." },
  { "NV_DEEP_DARK", "yes", "AUTO: always on in the Deep Dark biome (yes/no)." },
  { "HUD", "yes", "Show the night vision line on your screen (yes/no). H on the glasses' screen toggles it." },
  { "HUD_X", 4, "HUD position from the left of the screen, in GUI pixels." },
  { "HUD_Y", 4, "HUD position from the top of the screen, in GUI pixels." },
  { "CHECK_EVERY", 1, "Seconds between light checks." },
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
-- Hardware: modules (via the smartglasses API, falling back to the peripheral) and the detector
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

local nv, overlay, detector
local function findHardware()
  nv = getModule(NV_ID)
  overlay = getModule(OV_ID)
  detector = peripheral.find("environment_detector") or peripheral.find("environmentDetector")
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
-- HUD line (Overlay Module, GUI space)
---------------------------------------------------------------------------
local hudText
local function hudContent()
  if not nv then return "NV: no module" end
  local state = S.nvOn and "on" or "off"
  return ("NV %s: %s"):format(mode():upper(), state)
end

local function hudColour()
  if not nv then return 0xFF5555 end
  if S.nvOn then return 0x55FF55 end
  return 0xAAAAAA
end

local function hideHud()
  if hudText then call(hudText, "setEnabled", false) end
end

local function drawHud()
  if not overlay then hudText = nil; return end
  if not yes("HUD") then hideHud(); return end
  local content, colour = hudContent(), hudColour()
  if hudText then
    -- Object may have vanished (module pulled and put back): recreate if a setter fails
    local ok = pcall(function()
      hudText.setEnabled(true)
      hudText.setContent(content)
      hudText.setColor(colour)
      hudText.setPos(E.HUD_X, E.HUD_Y, 0)
    end)
    if ok then return end
    hudText = nil
  end
  local ok, obj = pcall(overlay.createText, {
    gui = true, x = E.HUD_X, y = E.HUD_Y, content = content, color = colour, shadow = true,
  })
  if ok and type(obj) == "table" then hudText = obj end
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

local BUTTONS = {
  { "auto", "1  AUTO", "when dark" },
  { "on",   "2  ON",   "always" },
  { "off",  "3  OFF",  "never" },
}

local function setMode(m)
  if m ~= mode() then setEnv("NV_MODE", m) end
  S.want = nil
end

local function drawScreen()
  hits = {}
  term.setBackgroundColour(colours.black); term.clear()
  fill(1, colours.grey)
  at(2, 1, "GLASSES", colours.cyan, colours.grey)
  local label = os.getComputerLabel() or ""
  at(W - #label, 1, label, colours.lightGrey, colours.grey)

  local y = 3
  if not nv then
    at(2, y, "No Night Vision Module", colours.red, colours.black); y = y + 1
    at(2, y, "Put one in the glasses.", colours.lightGrey, colours.black); y = y + 2
  else
    at(2, y, "Night vision: ", colours.white, colours.black)
    at(16, y, S.nvOn and "ON" or "OFF", S.nvOn and colours.lime or colours.lightGrey, colours.black)
    y = y + 1
    at(2, y, S.why, colours.lightGrey, colours.black); y = y + 2
  end

  for _, b in ipairs(BUTTONS) do
    local on = mode() == b[1]
    local bg = on and colours.cyan or colours.grey
    local fg = on and colours.black or colours.white
    fill(y, bg)
    at(2, y, b[2], fg, bg)
    at(W - #b[3], y, b[3], on and colours.black or colours.lightGrey, bg)
    hits[#hits + 1] = { y = y, action = function() setMode(b[1]) end }
    y = y + 2
  end

  if detector then
    local light = S.light and tostring(S.light) or "?"
    at(2, y, ("Light %s (blk %s sky %s)"):format(light, tostring(S.block or "?"), tostring(S.sky or "?")):sub(1, W - 2),
      colours.lightGrey, colours.black)
    y = y + 1
    local biome = tostring(S.biome or "?"):gsub("^[%w_%.%-]+:", "")
    at(2, y, ("Biome %s"):format(biome):sub(1, W - 2), colours.lightGrey, colours.black)
    y = y + 1
    at(2, y, ("On <=%d, off >=%d"):format(E.NV_DARK, math.max(E.NV_BRIGHT, E.NV_DARK + 1)):sub(1, W - 2),
      colours.grey, colours.black)
  else
    at(2, y, "No Environment Detector:", colours.orange, colours.black); y = y + 1
    at(2, y, "AUTO keeps it on.", colours.orange, colours.black)
  end

  -- Footer: HUD toggle
  local hudLabel = yes("HUD") and " H  HUD: on " or " H  HUD: off "
  fill(H, colours.black)
  at(2, H, hudLabel, colours.white, colours.grey)
  if not overlay then at(2 + #hudLabel + 1, H, "no overlay", colours.grey, colours.black) end
  hits[#hits + 1] = { y = H, action = function() setEnv("HUD", yes("HUD") and "no" or "yes") end }
end

---------------------------------------------------------------------------
-- Main loop
---------------------------------------------------------------------------
readEnv()
findHardware()
call(overlay, "clear")   -- drop the HUD left over from before the reboot

local function tick()
  refreshEnv()
  apply(decide())
  drawHud()
  drawScreen()
end

tick()
local timer = os.startTimer(math.max(0.25, E.CHECK_EVERY))
while true do
  local e, a, b, c = os.pullEvent()
  local act
  if e == "timer" and a == timer then
    tick()
    timer = os.startTimer(math.max(0.25, E.CHECK_EVERY))
  elseif e == "mouse_click" then
    for _, r in ipairs(hits) do
      if c == r.y then act = r.action; break end
    end
  elseif e == "char" then
    local ch = a:lower()
    if ch == "1" then act = function() setMode("auto") end
    elseif ch == "2" then act = function() setMode("on") end
    elseif ch == "3" then act = function() setMode("off") end
    elseif ch == "h" then act = function() setEnv("HUD", yes("HUD") and "no" or "yes") end
    elseif ch == "q" then
      hideHud()
      term.setBackgroundColour(colours.black); term.clear(); term.setCursorPos(1, 1)
      print("Glasses HUD stopped. Night vision stays as it was. Reboot to start again.")
      return
    end
  elseif e == "glasses_module" or e == "glasses_module_detach" or e == "peripheral" or e == "peripheral_detach" then
    findHardware()
    act = function() end   -- drawHud recreates the HUD text if its object went away
  elseif e == "term_resize" then
    W, H = term.getSize()
    act = function() end
  end
  if act then
    act()
    tick()
  end
end
