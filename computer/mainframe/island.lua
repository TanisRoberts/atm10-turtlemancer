-- island.lua  --  Island Station + mainframe alerts (CC:Tweaked + Advanced Peripherals, ATM10 / MC 1.21.1)
-- Needs an Environment Detector next to the computer. Optional: a Chat Box and a monitor.
--
-- Chat commands (start with $ to keep them out of public chat, e.g. "$island miner"):
--   island status | scan | miner (every Canary) | storage | alerts | test | help
-- ($dump and $pocket are the butler's: see butler.lua)
-- "island alerts" subscribes you to private alerts: storage filling up, the miner going quiet,
-- getting lost, running out of fuel, finishing, or bringing home diamonds. Alerts you miss
-- while offline are replayed the next time you say anything in chat.

local PREFIX       = "Mainframe" -- name shown in chat brackets
local ALERT_RANGE  = 64          -- range for public station messages (sunset, mobs...)
local SCAN_RANGE   = 16          -- entity scan radius
local REFRESH      = 2           -- seconds between updates
local SILENT_AFTER = 120         -- seconds without hearing from the miner before alerting
local ALERTS_FILE  = "alerts.cfg"
local HOSTILES = {
  Zombie=true, Skeleton=true, Creeper=true, Spider=true, Drowned=true,
  Enderman=true, Witch=true, Phantom=true, Husk=true, Stray=true, Slime=true,
}
local VALUABLE = { "diamond", "emerald", "ancient_debris", "netherite" }

-- 1.21.1 uses snake_case names; older packs used camelCase. Try both.
local function find(...)
  for _, t in ipairs({ ... }) do
    local p = peripheral.find(t)
    if p then return p end
  end
end

local env = find("environment_detector", "environmentDetector")
local mon = peripheral.find("monitor")
local function chatBox() return find("chat_box", "chatBox") end -- looked up each time, so a new box just works

if not env then
  printError("No Environment Detector found.")
  print("Put the detector block next to this computer.")
  return
end

-- List what this build of the detector actually supports (handy when the docs drift)
do
  local want = { "getBiome", "getMoonId", "getMoonName", "isRaining", "isThunder",
    "getSkyLightLevel", "getBlockLightLevel", "scanEntities" }
  local missing = {}
  for _, m in ipairs(want) do
    if type(env[m]) ~= "function" then missing[#missing + 1] = m end
  end
  if #missing > 0 then
    print("Detector lacks: " .. table.concat(missing, ", ") .. " (working around it)")
  end
end

local out = mon or term
if mon then mon.setTextScale(0.5) end

local function col(c)
  out.setTextColour(out.isColour() and c or colours.white)
end

local function pretty(id)
  local s = tostring(id):gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
-- Chat box has a ~1s cooldown between messages. Returns true if the message went out.
-- The cooldown is shared with butler.lua through _G.CHAT_LAST, so the two never trip it.
local function say(msg, player)
  local chat = chatBox()
  if not chat then return false end
  while true do
    local wait = 1.1 - (os.clock() - (_G.CHAT_LAST or -10))
    if wait <= 0 then break end
    os.sleep(math.max(wait, 0.05))
  end
  _G.CHAT_LAST = os.clock()
  -- AP 0.8+ (ATM10): sendMessage(msg, {options}); sendMessageToPlayer was merged into it.
  local opts = { prefix = PREFIX, brackets = "[]", bracketsColor = "&b" }
  if player then opts.player = player else opts.range = ALERT_RANGE end
  local ok, res = pcall(chat.sendMessage, msg, opts)
  if ok and res then return true end
  -- Older AP: positional arguments
  if player and chat.sendMessageToPlayer then
    ok, res = pcall(chat.sendMessageToPlayer, msg, player, PREFIX, "[]", "&b")
  elseif not player then
    ok, res = pcall(chat.sendMessage, msg, PREFIX, "[]", "&b", ALERT_RANGE)
  end
  return ok and res and true or false
end

---------------------------------------------------------------------------
-- Alerts: subscribers, missed-message queue, conditions
---------------------------------------------------------------------------
local A = { subs = {}, pending = {} }
local function loadA()
  if fs.exists(ALERTS_FILE) then
    local f = fs.open(ALERTS_FILE, "r")
    local t = textutils.unserialize(f.readAll())
    f.close()
    if type(t) == "table" then A.subs, A.pending = t.subs or {}, t.pending or {} end
  end
end
local function saveA()
  local f = fs.open(ALERTS_FILE, "w")
  f.write(textutils.serialize(A))
  f.close()
end

local function queue(name, text)
  local q = A.pending[name] or {}
  q[#q + 1] = textutils.formatTime(os.time(), true) .. " " .. text
  while #q > 10 do table.remove(q, 1) end
  A.pending[name] = q
end

local function notify(text, only)
  for name in pairs(A.subs) do
    if not only or only == name then
      if not say("&e" .. text, name) then queue(name, text) end
    end
  end
  saveA()
end

local active, activeOrder = {}, {} -- conditions that are currently true
local function condition(key, isTrue, text)
  if isTrue and not active[key] then
    active[key] = text
    activeOrder[#activeOrder + 1] = key
    notify(text)
  elseif not isTrue and active[key] then
    active[key] = nil
    for i, k in ipairs(activeOrder) do if k == key then table.remove(activeOrder, i) break end end
  end
end

local function minerName(m) return (m and m.label) or "The miner" end

-- Every Canary the mainframe has heard (dig_link), sorted by number, retired ones left out
local function canaries()
  local out = {}
  for id, e in pairs(_G.CANARIES or {}) do
    if e.s.state ~= "retired" then out[#out + 1] = { id = id, s = e.s, seen = e.seen } end
  end
  table.sort(out, function(a, b) return (a.s.num or 999) < (b.s.num or 999) end)
  return out
end

local function minerLine(e)
  local m = e.s
  local ago = math.floor(os.clock() - e.seen)
  local function v(x) return x == nil and "-" or tostring(x) end
  local at = m.pos and (" At %d %d %d."):format(m.pos.x, m.pos.y, m.pos.z) or ""
  return ("%s: %s%s. Y %s, layer %s/%s, ring %s/%s. Fuel %s, cargo %s/16.%s Seen %ds ago."):format(
    minerName(m), v(m.state):upper(), (m.msg and m.msg ~= "") and (" (" .. m.msg .. ")") or "",
    v(m.y), v(m.layer), v(m.layers), v(m.ring), v(m.maxRing), v(m.fuel), v(m.slots), at, ago)
end

local function storageLine(s)
  if not s or not s.total or s.total == 0 then return "Storage hasn't reported in yet." end
  local line = ("Storage %d%% full (%d/%d slots, %d item types)."):format(
    math.floor(s.used / s.total * 100), s.used, s.total, s.kinds or 0)
  if s.fuelTarget then
    line = line .. (" Fuel barrel %d%%, %s fuel left in storage."):format(
      math.floor((s.fuelUnits or 0) / s.fuelTarget * 100), tostring(s.fuelAvailable or 0))
  end
  return line
end

local function weaverLine(r)
  if not r then return "Weaver hasn't checked in yet." end
  local ago = _G.WEAVER_SEEN and math.floor(os.clock() - _G.WEAVER_SEEN) or 0
  local pct = (r.total and r.total > 0) and math.floor((r.placed or 0) / r.total * 100) or 0
  local where = r.phase == "ext" and ("edge wall %s/%s"):format(tostring(r.ext), tostring(r.extTotal))
    or r.phase == "layer" and ("layer %s/%s"):format(tostring(r.layer), tostring(r.layers))
    or tostring(r.phase or "not started")
  local gaps = (tonumber(r.gaps) or 0) > 0 and (" %d gaps waiting for blocks storage hasn't got."):format(r.gaps) or ""
  return ("%s: %s%s. %s, %d/%d blocks (%d%%).%s Fuel %s. Seen %ds ago."):format(
    r.label or "Weaver", tostring(r.state or "?"):upper(), (r.msg and r.msg ~= "") and (" (" .. r.msg .. ")") or "",
    where, r.placed or 0, r.total or 0, pct, gaps, tostring(r.fuel), ago)
end

local function farmLine(st)
  local ago = _G.FARM_SEEN and _G.FARM_SEEN[tostring(st.label):lower()] and math.floor(os.clock() - _G.FARM_SEEN[tostring(st.label):lower()]) or 0
  local head = ("%s: %s%s."):format(st.label, tostring(st.state or "?"):upper(), (st.msg and st.msg ~= "") and (" (" .. st.msg .. ")") or "")
  local body
  if st.role == "lumberjack" then
    local lr = st.lastRound or {}
    body = ("%d tree spots, %d saplings on hand."):format(st.spots or 0, st.saplings or 0)
  else
    local lr = st.lastRound or {}
    body = ("%d plots. Last round: harvested %d, planted %d, hoed %d."):format(st.plots or 0, lr.harvested or 0, lr.planted or 0, lr.tilled or 0)
  end
  return ("%s %s Fuel %s. Seen %ds ago."):format(head, body, tostring(st.fuel), ago)
end

local lastHaul = {}   -- per Canary
local factoryKeys = {} -- plastic factory problems we've raised
local neuralKeys = {}  -- neural lab problems we've raised
local function watch()
  local s = _G.STORAGE_STATS
  if s and s.total and s.total > 0 then
    local pct = s.used / s.total
    if pct >= 0.9 then
      condition("storage90", true, ("Storage is %d%% full (%d/%d slots). Time for more barrels."):format(math.floor(pct * 100), s.used, s.total))
    elseif pct < 0.85 then
      condition("storage90", false)
    end
    condition("inputStuck", s.inputStuck == true, "Storage is full: items are piling up in the input chests.")
    if s.fuelTarget then
      condition("fuelDry", (s.fuelUnits or 0) < s.fuelTarget * 0.25 and (s.fuelAvailable or 0) == 0,
        "A Canary fuel barrel is running dry and storage has no coal or lava buckets left.")
    end
  end

  -- The storage and smelter computers (heard via base_link)
  if _G.STORAGE_SEEN then
    condition("storageSilent", os.clock() - _G.STORAGE_SEEN > SILENT_AFTER,
      "Lost contact with the storage computer. Is it running, with its modem on?")
  end
  if _G.SMELTER_SEEN then
    condition("smelterSilent", os.clock() - _G.SMELTER_SEEN > SILENT_AFTER, "Lost contact with the smelter computer.")
  end
  -- The plastic factory sends its own list of problems (dry taps, no water, no power, no fuel)
  if _G.FACTORY_SEEN then
    local silent = os.clock() - _G.FACTORY_SEEN > SILENT_AFTER
    condition("factorySilent", silent, "Lost contact with the plastic factory.")
    local probs = (not silent and _G.FACTORY and type(_G.FACTORY.problems) == "table") and _G.FACTORY.problems or {}
    for k in pairs(factoryKeys) do
      if not probs[k] then condition("plastic:" .. k, false); factoryKeys[k] = nil end
    end
    for k, text in pairs(probs) do factoryKeys[k] = true; condition("plastic:" .. k, true, tostring(text)) end
  end
  -- The neural lab does the same (no matrices, no power, stuck chamber, fab with no drop picked)
  if _G.NEURAL_SEEN then
    local silent = os.clock() - _G.NEURAL_SEEN > SILENT_AFTER
    condition("neuralSilent", silent, "Lost contact with the neural lab.")
    local probs = (not silent and _G.NEURAL and type(_G.NEURAL.problems) == "table") and _G.NEURAL.problems or {}
    for k in pairs(neuralKeys) do
      if not probs[k] then condition("neural:" .. k, false); neuralKeys[k] = nil end
    end
    for k, text in pairs(probs) do neuralKeys[k] = true; condition("neural:" .. k, true, tostring(text)) end
  end

  for _, e in ipairs(canaries()) do
    local m, k = e.s, tostring(e.id)
    local name = minerName(m)
    local ago = os.clock() - e.seen
    condition("minerSilent:" .. k, ago > SILENT_AFTER,
      ("Lost contact with %s (last seen at Y %s, %s)."):format(name, tostring(m.y), tostring(m.state)))
    condition("minerLost:" .. k, m.state == "lost",
      name .. (m.gps and (" is stuck: " .. tostring(m.msg)) or " lost track of which way he's facing. Carry him to the dock and press Enter on him."))
    condition("minerError:" .. k, m.state == "error", name .. " hit a problem: " .. tostring(m.msg))
    condition("minerFuel:" .. k, m.state == "waiting" and tostring(m.msg):find("fuel") ~= nil,
      name .. " is waiting at the dock for fuel.")
    condition("minerDump:" .. k, m.state == "waiting" and tostring(m.msg):find("Dump") ~= nil,
      name .. "'s dump barrel is full. Is storage running?")
    condition("minerMoved:" .. k, m.offPath == true and m.state == "waiting",
      name .. " was moved by hand. Press START or DOCK for him on the Foreman to send him home.")
    condition("minerDone:" .. k, m.done == true and m.state == "docked",
      name .. " finished the range and is docked. Pick a new one on the Foreman.")

    -- Valuables in a fresh haul
    local parts = {}
    for _, h in ipairs(m.haul or {}) do parts[#parts + 1] = tostring(h[1]) .. "=" .. tostring(h[2]) end
    local sig = table.concat(parts, ",")
    if sig ~= lastHaul[k] then
      if lastHaul[k] ~= nil and sig ~= "" then
        local found = {}
        for _, h in ipairs(m.haul or {}) do
          for _, v in ipairs(VALUABLE) do
            if tostring(h[1]):find(v) then found[#found + 1] = h[2] .. "x " .. pretty(h[1]); break end
          end
        end
        if #found > 0 then notify(name .. " brought home " .. table.concat(found, ", ") .. "!") end
      end
      lastHaul[k] = sig
    end
  end

  for k, st in pairs(_G.FARM_STATUS or {}) do
    local name = st.label or k
    local ago = (_G.FARM_SEEN and _G.FARM_SEEN[k]) and (os.clock() - _G.FARM_SEEN[k]) or 0
    condition("farmSilent:" .. k, ago > SILENT_AFTER, "Lost contact with " .. name .. ".")
    condition("farmError:" .. k, st.state == "error", name .. " hit a problem: " .. tostring(st.msg))
    condition("farmLost:" .. k, st.state == "lost", name .. " is lost. " .. tostring(st.msg))
    condition("farmWait:" .. k, st.state == "waiting", name .. ": " .. tostring(st.msg))
  end
  if _G.FARMHAND_SEEN then
    condition("farmhandSilent", os.clock() - _G.FARMHAND_SEEN > SILENT_AFTER,
      "Lost contact with the Farmhand (" .. tostring(_G.FARMHAND.label or "Farmhand") .. ").")
  end

  local r = _G.WEAVER_STATUS
  if r then
    local name = r.label or "Weaver"
    local ago = _G.WEAVER_SEEN and (os.clock() - _G.WEAVER_SEEN) or 0
    condition("weaversilent", ago > SILENT_AFTER, ("Lost contact with %s (last seen at Y %s)."):format(name, tostring(r.y)))
    condition("weaverWaiting", r.state == "waiting", name .. " is waiting at the dock. " .. tostring(r.msg))
    condition("weaverError", r.state == "error", name .. " hit a problem: " .. tostring(r.msg))
    condition("weaverLost", r.state == "lost", name .. " lost track of which way he's facing. Carry him to his dock and type: weaver found")
    condition("weaverDone", r.state == "done", name .. " finished building " .. tostring(r.plan or "the island") .. "!")
    if r.phase == "layer" and r.layers and r.layer then
      local tenth = math.floor((r.layer - 1) / r.layers * 10)
      if A.weaverTenth and tenth > A.weaverTenth then
        notify(("%s is %d%% of the way up (layer %d/%d)."):format(name, tenth * 10, r.layer, r.layers))
      end
      A.weaverTenth = tenth
    end
  end
end

---------------------------------------------------------------------------
-- Station (environment)
---------------------------------------------------------------------------
local function phase(h)
  if h >= 6 and h < 17.5 then return "Day"
  elseif h >= 17.5 and h < 18.5 then return "Sunset"
  elseif h >= 18.5 or h < 5 then return "Night"
  else return "Dawn" end
end

-- AP renames/drops methods between versions, so every detector call goes through this.
local function call(name, ...)
  local f = env[name]
  if type(f) ~= "function" then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
end

local MOONS = { [0] = "Full", "Waning gibbous", "Third quarter", "Waning crescent",
  "New", "Waxing crescent", "First quarter", "Waxing gibbous" }

local function read()
  local r = {}
  r.hour    = os.time()
  r.time    = textutils.formatTime(r.hour, true)
  r.day     = os.day()
  r.phase   = phase(r.hour)
  r.weather = call("isThunder") and "Thunder" or (call("isRaining") and "Rain" or "Clear")
  local moonId = call("getMoonId") or (os.day() % 8)
  r.moon    = call("getMoonName") or MOONS[moonId] or "?"
  r.biome   = (tostring(call("getBiome") or "?")):gsub("^.-:", ""):gsub("_", " ")
  r.sky     = call("getSkyLightLevel") or "?"
  r.block   = call("getBlockLightLevel") or "?"
  r.fuel    = turtle and turtle.getFuelLevel() or nil
  r.near = {}
  local ok, ents = pcall(call, "scanEntities", SCAN_RANGE)
  if ok and type(ents) == "table" then
    for _, e in ipairs(ents) do
      local d = math.sqrt((e.x or 0) ^ 2 + (e.y or 0) ^ 2 + (e.z or 0) ^ 2)
      r.near[#r.near + 1] = { name = tostring(e.name or "?"), d = d }
    end
    table.sort(r.near, function(a, b) return a.d < b.d end)
  end
  return r
end

local function line(y, label, value, c)
  out.setCursorPos(1, y)
  col(colours.lightGrey); out.write(label)
  col(c or colours.white); out.write(value)
end

-- Compact strip for when the station shares the monitor (3 lines)
local function drawCompact(r, w, h)
  local function seg(text, c) col(c or colours.white); out.write(text) end
  out.setCursorPos(1, 1)
  seg(" ISLAND ", colours.lime)
  seg(r.time .. "  ")
  seg(r.phase, r.phase == "Night" and colours.red or colours.yellow)
  seg("  day " .. r.day .. "  ", colours.lightGrey)
  seg(r.weather, r.weather == "Clear" and colours.lightBlue or colours.orange)
  if h >= 2 then
    out.setCursorPos(1, 2)
    seg((" Moon %s  Biome %s  Light %s/%s"):format(r.moon, r.biome, tostring(r.sky), tostring(r.block)):sub(1, w),
      colours.lightGrey)
  end
  if h >= 3 then
    out.setCursorPos(1, 3)
    local hostile, others = {}, 0
    for _, e in ipairs(r.near) do
      if HOSTILES[e.name] then hostile[#hostile + 1] = ("%s %.0fm"):format(e.name, e.d) else others = others + 1 end
    end
    if #hostile > 0 then
      seg((" Danger: " .. table.concat(hostile, ", ")):sub(1, w), colours.red)
    elseif #activeOrder > 0 then
      local text = active[activeOrder[#activeOrder]]
      local more = #activeOrder > 1 and (" (+%d more)"):format(#activeOrder - 1) or ""
      seg((" ! " .. text):sub(1, w - #more) .. more, colours.orange)
    else
      seg((" All clear (%d other thing%s nearby)"):format(others, others == 1 and "" or "s"):sub(1, w), colours.lime)
    end
  end
end

local function draw(r)
  out.setBackgroundColour(colours.black)
  out.clear()
  local w, h = out.getSize()
  if h < 10 then return drawCompact(r, w, h) end
  out.setCursorPos(1, 1); col(colours.lime); out.write("ISLAND STATION")
  line(3, "Time    ", r.time .. "  (day " .. r.day .. ")")
  line(4, "Phase   ", r.phase, r.phase == "Night" and colours.red or colours.yellow)
  line(5, "Weather ", r.weather, r.weather == "Clear" and colours.lightBlue or colours.orange)
  line(6, "Moon    ", r.moon)
  line(7, "Biome   ", r.biome)
  line(8, "Light   ", ("sky %s  block %s"):format(tostring(r.sky), tostring(r.block)))
  if r.fuel then line(9, "Fuel    ", tostring(r.fuel)) end
  out.setCursorPos(1, 11); col(colours.lightGrey)
  out.write("Nearby (" .. SCAN_RANGE .. "m):")
  if #r.near == 0 then line(12, " ", "nothing", colours.grey) end
  for i, e in ipairs(r.near) do
    if 11 + i > h then break end
    line(11 + i, " ", ("%-14s %5.1fm"):format(e.name:sub(1, 14), e.d),
      HOSTILES[e.name] and colours.red or colours.white)
  end
end

local function summary(r)
  return ("%s (%s), %s, %s moon"):format(r.time, r.phase, r.weather, r.moon)
end

local state, prev, lastHostileAlert = nil, {}, -100
local function stationAlerts(r)
  if prev.phase and r.phase ~= prev.phase then
    if r.phase == "Sunset" then say("Sun's going down. About a minute until mobs.") end
    if r.phase == "Night"  then say("Night. Bed time.") end
    if r.phase == "Dawn"   then say("Morning! Day " .. r.day .. ".") end
  end
  if prev.weather and r.weather ~= prev.weather then
    say("Weather changed: " .. r.weather .. ".")
  end
  for _, e in ipairs(r.near) do
    if HOSTILES[e.name] and e.d < 10 and os.clock() - lastHostileAlert > 30 then
      say(("&c%s&r %.0f blocks from the station!"):format(e.name, e.d))
      lastHostileAlert = os.clock()
      break
    end
  end
  prev = { phase = r.phase, weather = r.weather }
end

local function stationLoop()
  while true do
    state = read()
    watch()
    draw(state)
    stationAlerts(state)
    os.sleep(REFRESH)
  end
end

---------------------------------------------------------------------------
-- Chat commands
---------------------------------------------------------------------------
local HELP = "Commands: island status | scan | miner | storage | weaver | woodpecker | partridge | smelt | plastic | neural | alerts | test."
  .. " Your inventory: $get [n] <item> | $dump | $pocket"

local function chatLoop()
  while true do
    -- AP 0.8 (ATM10): "chat", uuid, name, message, isHidden
    -- AP 0.7 and older: "chat", name, message, uuid, isHidden
    local _, a, b, c = os.pullEvent("chat")
    local user, msg
    if type(a) == "string" and a:match("^%x+%-%x+%-%x+%-%x+%-%x+$") then
      user, msg = b, c
    elseif a == nil then
      user, msg = b, c   -- 0.8 /say messages have no uuid
    else
      user, msg = a, b
    end
    user = tostring(user)

    -- Replay anything this player missed
    local missed = A.pending[user]
    if missed and #missed > 0 and say(("While you were away (%d):"):format(#missed), user) then
      for _, t in ipairs(missed) do say("&7" .. t, user) end
      A.pending[user] = nil
      saveA()
    end

    local cmd = tostring(msg):lower():gsub("^%$", ""):match("^%s*island%s*(%a*)")
    if cmd then
      if (cmd == "" or cmd == "status") and state then
        say(summary(state), user)
      elseif cmd == "scan" and state then
        local names = {}
        for i = 1, math.min(#state.near, 8) do
          names[#names + 1] = ("%s %.0fm"):format(state.near[i].name, state.near[i].d)
        end
        say(#names > 0 and table.concat(names, ", ") or "Nothing nearby.", user)
      elseif cmd == "miner" or cmd == "canaries" or cmd == "canary" then
        local list = canaries()
        if #list == 0 then say("No Canary has checked in yet.", user) end
        for _, e in ipairs(list) do say(minerLine(e), user) end
      elseif cmd == "storage" then
        say(storageLine(_G.STORAGE_STATS), user)
      elseif (_G.FARM_STATUS and _G.FARM_STATUS[cmd]) or cmd == "woodpecker" or cmd == "partridge" then
        local sub = tostring(msg):lower():match(cmd .. "%s+(%a+)")
        local orders = { rounds = "rounds", now = "rounds", survey = "survey", remap = "survey", stop = "stop", pause = "stop",
          go = "go", resume = "go", found = "found" }
        local st = _G.FARM_STATUS and _G.FARM_STATUS[cmd]
        local proper = st and st.label or (cmd:sub(1, 1):upper() .. cmd:sub(2))
        if sub and orders[sub] then
          _G.FARM_CMD = _G.FARM_CMD or {}
          _G.FARM_CMD[cmd] = { want = orders[sub], seq = os.epoch("utc") }
          local words = { rounds = "heading out on his rounds now.", survey = "re-mapping his area.",
            stop = "pausing. He'll stay docked.", go = "back on his schedule.",
            found = "working out where he is (put him on his home spot first)." }
          say(proper .. " is " .. words[orders[sub]], user)
        elseif st then
          say(farmLine(st), user)
          say("Orders: island " .. cmd .. " rounds | survey | stop | go | found", user)
        else
          say(proper .. " hasn't checked in yet. Is his modem on and his script running?", user)
        end
      elseif cmd == "smelt" then
        local item, amount = tostring(msg):lower():match("smelt%s+(%S+)%s+(%d+)")
        if item then
          _G.SMELT_CMD = { item = item, amount = tonumber(amount), seq = os.epoch("utc") }
          if _G.SMELTER_SEEN and os.clock() - _G.SMELTER_SEEN < 30 then
            say(("Queued %s %s for smelting."):format(amount, item), user)
          else
            say(("I'll pass on %s %s, but the smelter isn't answering right now."):format(amount, item), user)
          end
        else
          local lines = _G.SMELT_STATUS or { "The smelter hasn't reported in yet." }
          for i = 1, math.min(#lines, 5) do say(lines[i], user) end
        end
      elseif cmd == "plastic" or cmd == "factory" then
        local fac = _G.FACTORY
        local sub = tostring(msg):lower():match(cmd .. "%s+(%a+)")
        local orders = { pause = "pause", stop = "pause", go = "go", resume = "go", run = "go", start = "go" }
        if not fac then
          say("The plastic factory hasn't checked in. It needs a wireless or ender modem to reach me.", user)
        elseif sub and orders[sub] then
          rednet.broadcast({ type = "factory_cmd", to = fac.id, want = orders[sub] }, "tanis-base")
          say(orders[sub] == "pause" and "Pausing the plastic factory." or "Plastic factory running again.", user)
        else
          local lines = fac.lines or { tostring(fac.note) }
          for i = 1, math.min(#lines, 6) do say(lines[i], user) end
          say("Orders: island plastic pause | go", user)
        end
      elseif cmd == "neural" or cmd == "lab" then
        local nl = _G.NEURAL
        local sub = tostring(msg):lower():match(cmd .. "%s+(%a+)")
        local orders = { pause = "pause", stop = "pause", go = "go", resume = "go", run = "go", start = "go" }
        if not nl then
          say("The neural lab hasn't checked in. It needs a wireless or ender modem to reach me.", user)
        elseif sub and orders[sub] then
          rednet.broadcast({ type = "neural_cmd", to = nl.id, want = orders[sub] }, "tanis-base")
          say(orders[sub] == "pause" and "Pausing the neural lab." or "Neural lab running again.", user)
        else
          local lines = nl.lines or { tostring(nl.note) }
          for i = 1, math.min(#lines, 8) do say(lines[i], user) end
          say("Orders: island neural pause | go", user)
        end
      elseif cmd == "weaver" then
        local sub = tostring(msg):lower():match("weaver%s+(%a+)")
        local orders = { build = "build", start = "build", stop = "dock", dock = "dock", test = "test", clear = "clear" }
        if sub and orders[sub] then
          _G.WEAVER_CMD = { want = orders[sub], seq = os.epoch("utc") }
          local words = { build = "Building. He'll restock as he goes.", dock = "Stopping. He'll head back to his dock.",
            test = "Placing markers on the 8 corners of the build.", clear = "Taking the corner markers back down." }
          say("Weaver: " .. words[orders[sub]], user)
        else
          say(weaverLine(_G.WEAVER_STATUS), user)
          say("Orders: island weaver test | clear | build | stop", user)
        end
      elseif cmd == "alerts" then
        if A.subs[user] then
          A.subs[user] = nil
          say("Alerts off.", user)
        else
          A.subs[user] = true
          say("Alerts on. I'll message you about storage and the miner, even when you're away from base.", user)
        end
        saveA()
      elseif cmd == "test" then
        if A.subs[user] then notify("Test alert. This is what alerts look like.", user)
        else say("You're not subscribed. Say: island alerts", user) end
      else
        say(HELP, user)
      end
    end
  end
end

loadA()
parallel.waitForAny(stationLoop, chatLoop)
