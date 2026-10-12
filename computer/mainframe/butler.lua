-- butler.lua  --  your inventory from anywhere, and who's on the island (runs from mainframe.lua)
-- CC:Tweaked + Advanced Peripherals 0.8 (ATM10 / MC 1.21.1)
--
-- Hardware, all touching the mainframe (directly or on its full-block wired modem):
--   * Inventory Manager with a Memory Card bound to you (right-click the card, put it in the manager).
--   * Player Detector (range is measured from the detector block).
-- Where items go (butler.env, default "storage" for both): the manager has to reach the chest, so the
-- modem the mainframe's blocks sit on must be joined to the STORAGE cable. Then $dump goes straight into
-- storage's main input chest, and torch top-ups come out of storage's restock chest (/pocket on storage),
-- or its normal output chest if none is set. Or give either one its own chest touching the manager and
-- set it to that side ($pocket dump north).
--
-- What it does:
--   $get [n] <item>   n of an item from storage straight into your inventory (no n = one stack)
--   $dump      everything except your hotbar (armour and offhand stay too) goes to storage
--   $pocket    what the butler sees: your hotbar slots, and which sides of the manager have chests
--   $pocket dump <storage|side> / $pocket restock <storage|side>   change where they go (saved to butler.env)
--   torches    under TORCH_MIN torches -> topped back up to TORCH_FILL from storage
--   warnings   inventory (nearly) full; armour or a tool close to breaking
--   presence   "welcome home" when you get back, guests greeted, storage monitor locks while you're away
--   visitors   side table on the monitor wall: who's been on the island and when
-- The Inventory Manager only works while you're online. Tunables live in butler.env: it's made on
-- first run, edits are picked up live, and missing keys get added back (your lines are never touched).

local ENV_FILE = "butler.env"
local STATE    = "butler.cfg"      -- visitor log + the last owner name we saw
local BASE     = "tanis-base"
local PREFIX   = "Mainframe"

local DEFAULTS = {
  { "OWNER", "", "Your Minecraft name. Blank = whoever the memory card in the Inventory Manager belongs to." },
  { "HOME_RANGE", 48, "Blocks from the Player Detector that count as being on the island." },
  { "AWAY_AFTER", 60, "Seconds out of range before you (or a guest) count as gone." },
  { "WELCOME_AFTER", 300, "Only say welcome home after being away at least this many seconds." },
  { "GREET_GUESTS", "yes", "Say hello to other players who land on the island (yes/no)." },
  { "AUTO_LOCK", "yes", "Lock the storage monitor while you're away (yes/no). /lock and /unlock on storage work either way." },
  { "POCKET_DUMP", "storage", "Where $dump goes: storage = storage's main input chest over the cable, or a side of the Inventory Manager (up/down/north/south/east/west) with its own chest." },
  { "POCKET_RESTOCK", "storage", "Where torch top-ups come from: storage = storage's restock chest (its output chest if none is set), or a side of the manager." },
  { "HOTBAR_FIRST", 1, "Number of the first hotbar slot as the manager counts them (AP 0.8 in ATM10: 1). $pocket shows what it sees." },
  { "TORCH_ITEM", "minecraft:torch", "What to keep topped up." },
  { "TORCH_MIN", 10, "Top up when you're carrying fewer than this many (0 = off)." },
  { "TORCH_FILL", 64, "...back up to this many." },
  { "SLOTS_WARN", 2, "Warn when this many free inventory slots or fewer are left." },
  { "WEAR_WARN", 15, "Warn when armour or a tool is down to this % durability." },
  { "WEAR_CRITICAL", 5, "Warn again at this % (about to break)." },
  { "CHECK_EVERY", 3, "Seconds between checks." },
}

---------------------------------------------------------------------------
-- Settings (butler.env)
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
    if new then f.writeLine("# Butler settings. Edit and save: the mainframe picks changes up within a few seconds.") end
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

-- "up" -> "@up" (a block next to the manager); a full peripheral name is used as it is
local function side(v)
  v = tostring(v)
  if v:find("[:_@]") then return v end
  return "@" .. v:lower()
end

-- Change one setting from chat: rewrites that KEY= line in place, leaves every other line alone
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

local SIDES = { "up", "down", "north", "south", "east", "west" }
local SIDE_OK = { up = true, down = true, north = true, south = true, east = true, west = true,
  top = true, bottom = true, front = true, back = true, left = true, right = true }

-- Which blocks touching the manager are inventories. It tries to move an item you can't be carrying:
-- an empty side (or the computer, a modem...) errors "not an inventory", a chest just moves nothing.
local function notInventory(err)
  err = tostring(err):lower()
  return err:find("not an inventory") ~= nil or err:find("target") ~= nil
end
local function hasChest(m, target)
  local ok, err = pcall(m.exportItem, target, { name = "minecraft:structure_void", count = 1 })
  return ok or not notInventory(err)
end

-- Where $dump / restock go: the chest on the configured side of the manager, or (no chest there)
-- storage's own chest by name, when the mainframe is on the storage cable and can see it.
local function pocketTarget(m, key)
  if tostring(E[key]):lower() ~= "storage" then
    local t = side(E[key])
    if hasChest(m, t) then return t end
  end
  local st = _G.STORAGE_STATS
  local name = st and (key == "POCKET_DUMP" and st.mainInput or st.restockChest)
  if type(name) == "string" and peripheral.isPresent(name) and hasChest(m, name) then return name, true end
end

local function chestSides(m)
  local found = {}
  for _, sd in ipairs(SIDES) do
    local ok, err = pcall(m.exportItem, "@" .. sd, { name = "minecraft:structure_void", count = 1 })
    if ok or not notInventory(err) then found[#found + 1] = sd end
  end
  return found
end

---------------------------------------------------------------------------
-- Saved state: visitor log
---------------------------------------------------------------------------
local S = { visitors = {}, owner = nil }
local function loadS()
  if fs.exists(STATE) then
    local f = fs.open(STATE, "r")
    local t = textutils.unserialize(f.readAll())
    f.close()
    if type(t) == "table" then S.visitors, S.owner = t.visitors or {}, t.owner end
  end
end
local function saveS()
  local f = fs.open(STATE, "w")
  f.write(textutils.serialize(S))
  f.close()
end

---------------------------------------------------------------------------
-- Peripherals and chat
---------------------------------------------------------------------------
-- 1.21.1 uses snake_case names; older packs used camelCase. Looked up each time, so a new block just works.
local function find(...)
  for _, t in ipairs({ ... }) do
    local p = peripheral.find(t)
    if p then return p end
  end
end
local function manager()  return find("inventory_manager", "inventoryManager") end
local function detector() return find("player_detector", "playerDetector") end
local function chatBox()  return find("chat_box", "chatBox") end
local mon = peripheral.find("monitor")   -- the visitor table window (nil if the wall is too narrow)

-- The chat box has a ~1 s cooldown shared with island.lua (_G.CHAT_LAST), so we never trip it.
local function say(msg, player, range)
  local chat = chatBox()
  if not chat then return false end
  while true do
    local wait = 1.1 - (os.clock() - (_G.CHAT_LAST or -10))
    if wait <= 0 then break end
    os.sleep(math.max(wait, 0.05))
  end
  _G.CHAT_LAST = os.clock()
  local opts = { prefix = PREFIX, brackets = "[]", bracketsColor = "&b" }
  if player then opts.player = player else opts.range = range or E.HOME_RANGE end
  local ok, res = pcall(chat.sendMessage, msg, opts)
  return ok and res and true or false
end

local function pretty(id)
  local s = tostring(id):gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end
local function label(it) return it.displayName or pretty(it.name) end
local function plural(id)
  local w = pretty(id):lower()
  if w:find("[sx]$") or w:find("[cs]h$") then return w .. "es" end
  return w .. "s"
end

local function commas(n)
  local s = tostring(math.floor(n))
  while true do
    local k
    s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    if k == 0 then return s end
  end
end

-- Your name: OWNER from butler.env, or the memory card's owner (remembered for when you're offline)
local function ownerName()
  if E.OWNER and E.OWNER ~= "" then return E.OWNER end
  local m = manager()
  if m then
    local ok, _, name = pcall(m.getOwner)
    if ok and type(name) == "string" then
      if S.owner ~= name then S.owner = name; saveS() end
      return name
    end
  end
  return S.owner
end

-- The manager, but only while the card's owner is online (it can't reach an offline inventory)
local function liveManager()
  local m = manager()
  if not m then return nil end
  local ok, _, name = pcall(m.getOwner)
  if ok and name then return m end
end

local function isOwner(name, owner)
  return owner ~= nil and tostring(name):lower() == tostring(owner):lower()
end

---------------------------------------------------------------------------
-- Presence: who's on the island
---------------------------------------------------------------------------
local seen      = {}    -- lower-case name -> { name, at } for everyone currently around
local first     = true  -- first scan after boot: nobody gets greeted
local leftAt    = nil   -- os.clock() when you last left the island
local whileAway = {}    -- guests who came by while you were out
local known     = false -- the detector answered and we know who you are
local lastSave  = 0

local function playersNear()
  local d = detector()
  if not d then return nil end
  local ok, list = pcall(d.getPlayersInRange, E.HOME_RANGE)
  if not ok or type(list) ~= "table" then return nil end
  local out = {}
  for _, p in pairs(list) do
    local n = type(p) == "table" and (p.name or p.username) or p
    if n then out[#out + 1] = tostring(n) end
  end
  return out
end

local function ownerHome(owner)
  return owner ~= nil and seen[owner:lower()] ~= nil
end

local function storageLine()
  local s = _G.STORAGE_STATS
  if not s or not s.total or s.total == 0 then return nil end
  return ("Storage is %d%% full."):format(math.floor(s.used / s.total * 100))
end

local function arrived(name, owner)
  if isOwner(name, owner) then
    if leftAt and os.clock() - leftAt >= E.WELCOME_AFTER then
      local parts = { ("Welcome home, %s!"):format(name) }
      parts[#parts + 1] = storageLine()
      if #whileAway > 0 then
        local who = #whileAway == 1 and whileAway[1]
          or table.concat(whileAway, ", ", 1, #whileAway - 1) .. " and " .. whileAway[#whileAway]
        parts[#parts + 1] = who .. " dropped by while you were out."
      end
      say(table.concat(parts, " "), name)
    end
    leftAt, whileAway = nil, {}
    return
  end
  local v = S.visitors[name] or { visits = 0 }
  v.visits, v.last = (v.visits or 0) + 1, os.epoch("utc")
  S.visitors[name] = v
  saveS()
  if yes("GREET_GUESTS") then
    say(owner and ("Welcome to %s's island, %s!"):format(owner, name) or ("Welcome to the island, %s!"):format(name))
  end
  if owner then
    if ownerHome(owner) then
      say(name .. " just landed on the island.", owner)
    else
      local dup = false
      for _, n in ipairs(whileAway) do if n == name then dup = true end end
      if not dup then whileAway[#whileAway + 1] = name end
      say(name .. " just landed on the island while you're away.", owner)   -- only arrives if you're online
    end
  end
end

local function presenceTick()
  local owner = ownerName()
  local near = playersNear()
  local now = os.clock()
  known = near ~= nil and owner ~= nil
  if near then
    for _, n in ipairs(near) do
      local k = n:lower()
      if not seen[k] then
        seen[k] = { name = n, at = now }
        if not first then arrived(n, owner) end
      end
      seen[k].at = now
      if not isOwner(n, owner) and S.visitors[n] then S.visitors[n].last = os.epoch("utc") end
      if not isOwner(n, owner) and not S.visitors[n] then
        S.visitors[n] = { visits = 1, last = os.epoch("utc") }   -- here since boot
      end
    end
    -- Only age people out when the detector is answering (a missing detector mustn't mean "everyone left")
    for k, e in pairs(seen) do
      if now - e.at > E.AWAY_AFTER then
        seen[k] = nil
        if isOwner(e.name, owner) then leftAt, whileAway = os.clock(), {} end
      end
    end
    -- Not here when the mainframe starts: count as away, so your first arrival gets a welcome
    if first and owner and not ownerHome(owner) then leftAt = now - E.WELCOME_AFTER end
    first = false
  end
  if os.clock() - lastSave > 60 then saveS(); lastSave = os.clock() end
  if rednet.isOpen() then
    rednet.broadcast({ type = "presence", known = known, home = ownerHome(owner), owner = owner,
      autoLock = yes("AUTO_LOCK") }, BASE)
  end
end

---------------------------------------------------------------------------
-- Visitor table (right-hand side of the wall)
---------------------------------------------------------------------------
local function whenText(name, v)
  if seen[name:lower()] then return "here", colours.lime end
  local s = math.floor((os.epoch("utc") - (v.last or 0)) / 1000)
  if s < 60 then return "just now", colours.white end
  if s < 3600 then return math.floor(s / 60) .. "m ago", colours.white end
  if s < 86400 then return math.floor(s / 3600) .. "h ago", colours.lightGrey end
  if s < 7 * 86400 then return math.floor(s / 86400) .. "d ago", colours.lightGrey end
  return os.date("%d %b", math.floor((v.last or 0) / 1000)), colours.grey
end

local function drawVisitors()
  if not mon then return end
  local w, h = mon.getSize()
  mon.setBackgroundColour(colours.black); mon.clear()
  mon.setCursorPos(1, 1); mon.setBackgroundColour(colours.grey); mon.clearLine()
  mon.setTextColour(colours.cyan); mon.write(" VISITORS")
  mon.setBackgroundColour(colours.black)

  local owner = ownerName()
  local list = {}
  for name, v in pairs(S.visitors) do
    if not isOwner(name, owner) then
      list[#list + 1] = { name = name, v = v, here = seen[name:lower()] ~= nil }
    end
  end
  table.sort(list, function(a, b)
    if a.here ~= b.here then return a.here end
    return (a.v.last or 0) > (b.v.last or 0)
  end)
  if not detector() then
    mon.setCursorPos(2, 3); mon.setTextColour(colours.red); mon.write(("No player detector"):sub(1, w - 2))
  elseif #list == 0 then
    mon.setCursorPos(2, 3); mon.setTextColour(colours.grey); mon.write(("Nobody yet"):sub(1, w - 2))
  end
  for i, e in ipairs(list) do
    local y = i + 2
    if y > h - 2 then break end
    local when, c = whenText(e.name, e.v)
    mon.setCursorPos(2, y)
    mon.setTextColour(e.here and colours.lime or colours.white)
    mon.write(e.name:sub(1, math.max(1, w - #when - 3)))
    mon.setCursorPos(w - #when, y); mon.setTextColour(c); mon.write(when)
  end

  -- Footer: are you home (and so is storage locked)?
  mon.setCursorPos(2, h)
  if not known then
    mon.setTextColour(colours.grey); mon.write(("You: ?"):sub(1, w - 2))
  elseif ownerHome(owner) then
    mon.setTextColour(colours.lime); mon.write(("You're home"):sub(1, w - 2))
  else
    local away = leftAt and math.max(0, math.floor((os.clock() - leftAt) / 60)) or nil
    local txt = away and ("Away %dm"):format(away) or "Away"
    if yes("AUTO_LOCK") then txt = txt .. ", locked" end
    mon.setTextColour(colours.orange); mon.write(txt:sub(1, w - 2))
  end
end

---------------------------------------------------------------------------
-- Your inventory
---------------------------------------------------------------------------
local function listItems(m)
  local ok, list = pcall(m.list)
  if ok and type(list) == "table" then return list end
end

-- Durability left as a fraction (and uses left when known), from AP's item components
local function durability(it)
  if type(it) ~= "table" then return nil end
  local c = type(it.components) == "table" and it.components or {}
  if c["minecraft:unbreakable"] then return nil end
  local max = tonumber(it.maxDamage or c["minecraft:max_damage"])
  local dmg = tonumber(it.damage or c["minecraft:damage"]) or 0
  if max and max > 0 then return 1 - dmg / max, max - dmg end
  local d = tonumber(it.durability)   -- CC-style 0..1, if this build gives that instead
  if d then return d end
end

-- How many of `name` you carry: inventory + offhand (when list() doesn't already include the offhand)
local function countItem(m, list, name)
  local total, high = 0, false
  for slot, it in pairs(list) do
    if type(slot) == "number" and slot > E.HOTBAR_FIRST + 35 then high = true end
    if it.name == name and not (type(slot) == "number" and slot >= 100) then total = total + (it.count or 0) end
  end
  if not high then
    local ok, off = pcall(m.getItemInOffHand)
    if ok and type(off) == "table" and off.name == name then total = total + (off.count or 0) end
  end
  return total
end

local spaceLevel = 0      -- 0 fine, 1 nearly full (warned), 2 full (warned)
local function checkSpace(m, owner)
  local ok, free = pcall(m.getEmptySlots)
  free = ok and tonumber(free) or nil
  if not free then return end
  local level = free == 0 and 2 or (free <= E.SLOTS_WARN and 1 or 0)
  if level > spaceLevel then
    if level == 2 then
      say("&cInventory full! Say $dump to send everything except your hotbar home.", owner)
    else
      say(("&eOnly %d free slot%s left. $dump sends everything except your hotbar home."):format(
        free, free == 1 and "" or "s"), owner)
    end
  end
  spaceLevel = level
end

local wearLevel = {}      -- item id -> 0 fine, 1 warned, 2 warned critical
local function checkWear(m, list, owner)
  local worst = {}        -- item id -> { frac, uses, it }
  local function consider(it)
    local frac, uses = durability(it)
    if not frac then return end
    local w = worst[it.name]
    if not w or frac < w.frac then worst[it.name] = { frac = frac, uses = uses, it = it } end
  end
  for _, it in pairs(list) do consider(it) end
  for _, f in ipairs({ "getItemInHand", "getItemInOffHand" }) do
    if m[f] then
      local ok, it = pcall(m[f])
      if ok then consider(it) end
    end
  end
  if m.getArmor then   -- older AP builds
    local ok, armour = pcall(m.getArmor)
    if ok and type(armour) == "table" then for _, it in pairs(armour) do consider(it) end end
  end
  for name, w in pairs(worst) do
    local pct = w.frac * 100
    local level = pct <= E.WEAR_CRITICAL and 2 or (pct <= E.WEAR_WARN and 1 or 0)
    if level > (wearLevel[name] or 0) then
      local uses = w.uses and (" (%d use%s left)"):format(w.uses, w.uses == 1 and "" or "s") or ""
      if level == 2 then
        say(("&cYour %s is about to break: %d%%%s!"):format(label(w.it), math.floor(pct), uses), owner)
      else
        say(("&eYour %s is down to %d%%%s."):format(label(w.it), math.floor(pct), uses), owner)
      end
      wearLevel[name] = level
    elseif pct > E.WEAR_WARN + 5 then
      wearLevel[name] = 0   -- repaired or swapped for a fresh one
    end
  end
  for name in pairs(wearLevel) do if not worst[name] then wearLevel[name] = nil end end
end

-- No chest where butler.env says: look around the manager and say how to fix it
local function explainMissing(m, which, key, user)
  if tostring(E[key]):lower() == "storage" then
    local st = _G.STORAGE_STATS
    local name = st and (key == "POCKET_DUMP" and st.mainInput or st.restockChest)
    if not st then
      say("&eI haven't heard from the storage computer yet. Is it running?", user)
    elseif not name then
      say("&eStorage didn't tell me its chest names. Reboot the storage computer so it updates.", user)
    else
      say(("&eI can't reach storage's %s chest (%s) from the mainframe. Is the modem the Inventory Manager sits "
        .. "under joined to the storage cable, and switched on (right-click: red ring)?"):format(
        key == "POCKET_DUMP" and "input" or "restock", name), user)
    end
    return
  end
  local found = chestSides(m)
  local other = key == "POCKET_DUMP" and tostring(E.POCKET_RESTOCK):lower() or tostring(E.POCKET_DUMP):lower()
  local spare = {}
  for _, sd in ipairs(found) do if sd ~= other then spare[#spare + 1] = sd end end
  local head = ("No chest on the %s side of the Inventory Manager (%s=%s)."):format(tostring(E[key]), key, tostring(E[key]))
  if #found == 0 then
    say("&e" .. head .. " No chest touches the manager at all. Either put one against the manager block (wired modem "
      .. "on the storage cable, then /pocket on storage), or put a wired modem on the mainframe joined to the "
      .. "storage cable and I'll use storage's chests directly.", user)
  elseif #spare == 1 then
    say(("&e%s Chests touch it on: %s. Probably the %s one: $pocket %s %s"):format(head, table.concat(found, ", "),
      spare[1], which, spare[1]), user)
  else
    say(("&e%s Chests touch it on: %s. Tell me which is the %s chest: $pocket %s <side>"):format(head,
      table.concat(found, ", "), which, which), user)
  end
end

-- Torches: ask storage to put them in the restock chest, then pull them into your inventory
local restock = { nextTry = 0, warned = nil }
-- Ask storage to put `count` of an item in the restock chest (stack = "one stack, whatever that is
-- for this item"). Returns its reply { got, ready } or nil if storage didn't answer in 10 s.
local reqSeq = 0
local function requestPocket(item, count, stack)
  reqSeq = reqSeq + 1
  local seq = os.epoch("utc") * 100 + reqSeq % 100
  rednet.broadcast({ type = "pocket_fill", item = item, count = count, stack = stack, seq = seq }, BASE)
  local untilT = os.clock() + 10
  while os.clock() < untilT do
    local _, msg = rednet.receive(BASE, math.max(0.1, untilT - os.clock()))
    if type(msg) == "table" and msg.type == "pocket_filled" and msg.seq == seq then return msg end
  end
end

local function topUpTorches(m, list, owner)
  local name = E.TORCH_ITEM
  if E.TORCH_MIN <= 0 or os.clock() < restock.nextTry then return end
  local have = countItem(m, list, name)
  if have >= E.TORCH_MIN then restock.warned = nil; return end
  local want = E.TORCH_FILL - have
  if want <= 0 then return end
  restock.nextTry = os.clock() + 20
  if not _G.STORAGE_SEEN or os.clock() - _G.STORAGE_SEEN > 30 then return end   -- storage isn't around

  local reply = requestPocket(name, want)
  if not reply then return end
  if reply.ready == false then
    if restock.warned ~= "chest" then
      say("&eLow on " .. plural(name) .. ", but storage has no POCKET RESTOCK chest. On the storage computer: /pocket", owner)
      restock.warned = "chest"
    end
    restock.nextTry = os.clock() + 300
    return
  end
  if (reply.got or 0) <= 0 then
    if restock.warned ~= "empty" then
      say("&eYou're low on " .. plural(name) .. " and storage has none left.", owner)
      restock.warned = "empty"
    end
    restock.nextTry = os.clock() + 300
    return
  end
  local from = pocketTarget(m, "POCKET_RESTOCK") or side(E.POCKET_RESTOCK)
  local ok, moved = pcall(m.importItem, from, { name = name, count = math.min(want, reply.got) })
  if ok and (tonumber(moved) or 0) > 0 then
    say(("&7Topped up your %s (+%d)."):format(plural(name), moved), owner)
  elseif restock.warned ~= "pull" then
    if not ok and notInventory(moved) then
      explainMissing(m, "restock", "POCKET_RESTOCK", owner)
    else
      say("&eStorage filled the restock chest but I couldn't pull from it" .. (ok and "" or (": " .. tostring(moved)))
        .. ". Is POCKET_RESTOCK the right side? $pocket shows where the chests are.", owner)
    end
    restock.warned = "pull"
    restock.nextTry = os.clock() + 120
  end
end

-- Match what you typed against what storage holds: "iron ingot", "iron_ingot", "minecraft:iron_ingot"
-- all work; a vaguer word ("iron") lists the options. Returns a list of item ids, best first.
local function findItem(query)
  local items = _G.STORAGE_STATS and _G.STORAGE_STATS.items
  if type(items) ~= "table" then return nil end
  local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local qid = q:gsub("%s+", "_")
  local tiers = { {}, {}, {}, {} }
  for id, c in pairs(items) do
    if (tonumber(c) or 0) > 0 then
      local path = id:gsub("^.-:", "")
      if id == q or id == qid then table.insert(tiers[1], id)
      elseif path == qid then table.insert(tiers[2], id)
      elseif path == qid:gsub("es$", "") or path == qid:gsub("s$", "") then table.insert(tiers[3], id)   -- plurals
      elseif path:find(qid, 1, true) or id:find(qid, 1, true) then table.insert(tiers[4], id) end
    end
  end
  for _, t in ipairs(tiers) do
    if #t > 0 then
      table.sort(t, function(a, b) return (items[a] or 0) > (items[b] or 0) end)
      return t
    end
  end
  return {}
end

-- $get [count] <item>: storage puts it in its restock (or output) chest, the manager hands it to you
local function getItem(user, args)
  local m = liveManager()
  if not m then say("I can't reach your inventory. Is the memory card in the Inventory Manager?", user); return end
  args = args:gsub("^%s+", ""):gsub("%s+$", "")
  local n, what = args:match("^(%d+)%s+(.+)$")
  if not n then what, n = args:match("^(.-)%s+x?(%d+)$") end
  what = what or args
  local count = tonumber(n)
  if what == "" or (count and count <= 0) then
    say("Say what you want: $get 32 iron ingot  (no number = one stack)", user); return
  end
  if not _G.STORAGE_SEEN or os.clock() - _G.STORAGE_SEEN > 30 then
    say("I can't hear the storage computer right now.", user); return
  end
  local found = findItem(what)
  if not found then say("Storage hasn't told me what it holds yet. Give it a few seconds.", user); return end
  if #found == 0 then say("Storage has no " .. what .. ".", user); return end
  if #found > 1 then
    local opts = {}
    for i = 1, math.min(5, #found) do opts[i] = pretty(found[i]):lower() end
    say(("Which one? %s%s. E.g. $get 16 %s"):format(table.concat(opts, ", "), #found > 5 and ", ..." or "", opts[1]), user)
    return
  end
  local id = found[1]
  local from = pocketTarget(m, "POCKET_RESTOCK")
  if not from then explainMissing(m, "restock", "POCKET_RESTOCK", user); return end
  local reply = requestPocket(id, count, count == nil)
  if not reply then say("Storage didn't answer. Is it running?", user); return end
  if reply.ready == false then say("Storage has no chest to hand things over from (no output chest set?).", user); return end
  if (reply.got or 0) <= 0 then say("Storage is out of " .. pretty(id):lower() .. ".", user); return end
  local function many(k) return k == 1 and pretty(id):lower() or plural(id) end
  local ok, moved = pcall(m.importItem, from, { name = id, count = reply.got })
  moved = ok and (tonumber(moved) or 0) or 0
  if not ok then
    say("Couldn't hand it over: " .. tostring(select(2, pcall(m.importItem, from, { name = id, count = 1 }))), user)
  elseif moved == 0 then
    say(("No room in your inventory: %d %s waiting in storage's chest."):format(reply.got, many(reply.got)), user)
  elseif moved < reply.got then
    say(("Here's %d %s. Your inventory's full: %d more waiting in storage's chest."):format(
      moved, many(moved), reply.got - moved), user)
  else
    local short = count and reply.got < count and (" (all storage had)") or ""
    say(("Here's %d %s%s."):format(moved, many(moved), short), user)
  end
end

-- $dump: every slot except the hotbar (armour and offhand aren't in the range at all)
local function dump(user)
  local m = liveManager()
  if not m then say("I can't reach your inventory. Is the memory card in the Inventory Manager?", user); return end
  local target, direct = pocketTarget(m, "POCKET_DUMP")
  if not target then explainMissing(m, "dump", "POCKET_DUMP", user); return end
  local firstSlot, lastSlot = E.HOTBAR_FIRST + 9, E.HOTBAR_FIRST + 35
  local stacks, count, stuck = 0, 0, false
  for pass = 1, 5 do
    local list = listItems(m)
    if not list then say("I couldn't read your inventory just now.", user); return end
    local left, movedThisPass = 0, 0
    for slot = firstSlot, lastSlot do
      local it = list[slot]
      if it and (it.count or 0) > 0 then
        local ok, moved = pcall(m.exportItem, target, { name = it.name, fromSlot = slot, count = it.count })
        if not ok then
          if notInventory(moved) then explainMissing(m, "dump", "POCKET_DUMP", user)
          else say("Dump failed: " .. tostring(moved), user) end
          return
        end
        moved = tonumber(moved) or 0
        if moved > 0 then movedThisPass = movedThisPass + moved; count = count + moved end
        if moved >= it.count then stacks = stacks + 1 else left = left + 1 end
      end
    end
    if left == 0 then stuck = false; break end
    stuck = true
    os.sleep(3)   -- the dump chest is full: give storage a moment to empty it
  end
  if count == 0 and not stuck then
    say("Nothing to dump: it's all in your hotbar.", user)
  elseif stuck then
    say(("Sent %d stack%s (%s items) to storage, but the dump chest is full, so some is still on you. Is storage running?")
      :format(stacks, stacks == 1 and "" or "s", commas(count)), user)
  else
    say(("Sent %d stack%s (%s items) to storage%s. Hotbar untouched."):format(stacks, stacks == 1 and "" or "s",
      commas(count), direct and " (straight into its input chest)" or ""), user)
  end
  spaceLevel = 0
end

-- $pocket: what the manager sees, so you can check HOTBAR_FIRST
local function pocketInfo(user)
  local m = liveManager()
  if not m then say("I can't reach your inventory. Is the memory card in the Inventory Manager?", user); return end
  local list = listItems(m) or {}
  local lo, hi, used = nil, nil, 0
  for k in pairs(list) do
    if type(k) == "number" then
      lo, hi, used = math.min(lo or k, k), math.max(hi or k, k), used + 1
    end
  end
  local ok, free = pcall(m.getEmptySlots)
  say(("I see %d stacks in slots %s to %s, %s free slots."):format(used, tostring(lo or "-"), tostring(hi or "-"),
    ok and tostring(free) or "?"), user)
  local hot = {}
  for s = E.HOTBAR_FIRST, E.HOTBAR_FIRST + 8 do
    local it = list[s]
    hot[#hot + 1] = it and (label(it) .. (it.count > 1 and (" x" .. it.count) or "")) or "-"
  end
  say(("Hotbar = slots %d-%d: %s"):format(E.HOTBAR_FIRST, E.HOTBAR_FIRST + 8, table.concat(hot, ", ")), user)
  local found, at = chestSides(m), {}
  for _, sd in ipairs(found) do at[sd] = true end
  local function mark(key)
    local t, direct = pocketTarget(m, key)
    if not t then return tostring(E[key]) .. " (NO CHEST)" end
    return direct and ("storage's " .. t .. " over the cable") or (tostring(E[key]) .. " (ok)")
  end
  say(("Chests touching the manager: %s. Dump: %s. Restock: %s."):format(
    #found > 0 and table.concat(found, ", ") or "none", mark("POCKET_DUMP"), mark("POCKET_RESTOCK")), user)
  say("&7Change with: $pocket dump storage|<side>, $pocket restock storage|<side>. Wrong hotbar? HOTBAR_FIRST in butler.env.", user)
end

-- $pocket dump north / $pocket restock west
local function setPocket(user, which, sd)
  if not SIDE_OK[sd] and sd ~= "storage" and not sd:find("[:_]") then
    say("Use storage, or a side: up, down, north, south, east, west. E.g. $pocket " .. which .. " storage", user)
    return
  end
  local key = which == "dump" and "POCKET_DUMP" or "POCKET_RESTOCK"
  local other = which == "dump" and E.POCKET_RESTOCK or E.POCKET_DUMP
  if sd ~= "storage" and tostring(other):lower() == sd then
    say(("That's the %s chest's side already. Use two different chests."):format(which == "dump" and "restock" or "dump"), user)
    return
  end
  setEnv(key, sd)
  local m = liveManager()
  local there = true
  if m then
    local key2 = which == "dump" and "POCKET_DUMP" or "POCKET_RESTOCK"
    there = pocketTarget(m, key2) ~= nil
  end
  say(("%s chest set to %s.%s"):format(which == "dump" and "Dump" or "Restock", sd,
    there and "" or " (I can't see a chest there yet, mind.)"), user)
  if which == "restock" then restock.nextTry, restock.warned = 0, nil end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function presenceLoop()
  while true do
    refreshEnv()
    pcall(presenceTick)
    pcall(drawVisitors)
    os.sleep(E.CHECK_EVERY)
  end
end

local function inventoryLoop()
  while true do
    refreshEnv()
    local m, owner = liveManager(), ownerName()
    if m and owner then
      local list = listItems(m)
      if list then
        pcall(checkSpace, m, owner)
        pcall(checkWear, m, list, owner)
        pcall(topUpTorches, m, list, owner)
      end
    end
    os.sleep(E.CHECK_EVERY)
  end
end

local function chatLoop()
  while true do
    -- AP 0.8 (ATM10): "chat", uuid, name, message, isHidden.  AP 0.7: "chat", name, message, uuid, isHidden
    local _, a, b, c = os.pullEvent("chat")
    local user, msg
    if (type(a) == "string" and a:match("^%x+%-%x+%-%x+%-%x+%-%x+$")) or a == nil then
      user, msg = b, c
    else
      user, msg = a, b
    end
    user = tostring(user)
    local text = tostring(msg):lower():gsub("^%$", "")
    local cmd, arg1, arg2 = text:match("^%s*(%a+)%s*(%a*)%s*(%S*)%s*$")
    local getArgs = text:match("^%s*get%s*(.*)$")
    if getArgs then
      local owner = ownerName()
      if owner and not isOwner(user, owner) then say("Only " .. owner .. " can use that.", user)
      else getItem(user, getArgs) end
    elseif cmd == "dump" or cmd == "pocket" then
      local owner = ownerName()
      if owner and not isOwner(user, owner) then
        say("Only " .. owner .. " can use that.", user)
      elseif cmd == "dump" then
        dump(user)
      elseif arg1 == "dump" or arg1 == "restock" then
        setPocket(user, arg1, arg2)
      else
        pocketInfo(user)
      end
    end
  end
end

readEnv()
loadS()
peripheral.find("modem", function(name) rednet.open(name); return false end)
if not manager() then print("Butler: no Inventory Manager next to the mainframe (dump, torches and warnings are off).") end
if not detector() then print("Butler: no Player Detector next to the mainframe (welcomes, visitors and auto-lock are off).") end
parallel.waitForAny(presenceLoop, inventoryLoop, chatLoop)
