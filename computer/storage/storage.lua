-- storage.lua  --  touch-screen storage system for CC:Tweaked (ATM10 / MC 1.21.1)
--
-- Hardware:
--   * An Advanced Computer
--   * Storage: any chests/barrels/drawers, each with a wired modem, joined with networking cable
--   * INPUT chest(s) and one OUTPUT chest, also on the network
--   * Optional: a FUEL barrel for the miner turtle (kept at exactly one refill)
--   * Optional: an advanced monitor wall (touch screen). Normal monitors work as display-only.
--   * A wireless or ender modem, so it can talk to the mainframe, the smelter and the turtles
--
-- Use:
--   * Dump items into any INPUT chest. They get sorted into storage automatically.
--   * Tap an item on the monitor to send it to the OUTPUT chest (tap x1 / x16 / Stack to choose how many).
--   * Or type on the computer: a search word, then the item number and an amount.
--   * Commands: /rescan /clear /setup /addinput /fuel /inputs /help
-- Junk (cobble, deepslate, ...) is capped at JUNK_CAP; the miner is told to stop bringing more.
--
-- Storage is the only computer that moves items in or out of storage. Over the network it:
--   * broadcasts its status (fill level, item totals, junk caps) for the mainframe and smelter
--   * fills Rigger's supply barrel when he asks, and keeps Digger's fuel barrel at one refill
--   * carries out the smelter's moves (furnace output back to storage, inputs and fuel in)
--
-- Drawers (Functional Storage / Storage Drawers) are bulk storage: an item a drawer already
-- holds always goes there first, and empty drawers are only used when every barrel is full.
-- Claim a drawer by putting one of the item in it (and lock it). Taking items out empties
-- barrels before drawers, so loose stock drains away over time.

local CONFIG       = "storage.cfg"
local TICK         = 2       -- seconds between input-chest checks
local FULL_SCAN    = 30      -- seconds between full rescans (catches things you move by hand)
local TEXT_SCALE   = 0.5
local JUNK_CAP     = 20 * 64 -- items of one kind before the miner stops bringing more of it
local REFILL       = 20000   -- fuel units in one turtle refill (updated live from the miner's tank size)
local BASE         = "tanis-base"   -- network protocol shared by the base computers
local STATUS_EVERY = 3              -- seconds between status broadcasts

-- Fuel value per item, best first. Used to keep the fuel barrel at exactly one refill.
local FUEL_VALUES = {
  { "minecraft:coal_block", 800 },
  { "minecraft:lava_bucket", 1000 },
  { "minecraft:blaze_rod", 120 },
  { "minecraft:coal", 80 },
  { "minecraft:charcoal", 80 },
}

---------------------------------------------------------------------------
-- Config
---------------------------------------------------------------------------
local cfg = {}
local function loadCfg()
  if fs.exists(CONFIG) then
    local f = fs.open(CONFIG, "r")
    cfg = textutils.unserialize(f.readAll()) or {}
    f.close()
  end
  if cfg.input and not cfg.inputs then cfg.inputs = { cfg.input } end -- older config
  cfg.input = nil
  cfg.inputs = cfg.inputs or {}
end
local function saveCfg()
  local f = fs.open(CONFIG, "w")
  f.write(textutils.serialize(cfg))
  f.close()
end

-- Furnaces (incl. Iron Furnaces) are for smelting only, never storage. Blast furnaces and
-- smokers are left alone entirely.
local function isFurnace(n)
  return n:find("furnace") ~= nil and not n:find("blast") and not n:find("smoker")
end
local function isMachine(n)
  return n:find("furnace") ~= nil or n:find("smoker") ~= nil
end

-- Drawers show up on the network as e.g. "functionalstorage:oak_1_0" or "storagedrawers:..."
local function isDrawer(n)
  return (n:find("drawer") or n:find("functionalstorage")) ~= nil
end

local function isSpecial(n)
  if n == cfg.output or n == cfg.fuel or n == cfg.rigger then return true end
  for _, d in ipairs(cfg.docks or {}) do if d == n then return true end end
  if isMachine(n) then return true end
  for _, i in ipairs(cfg.inputs) do if i == n then return true end end
  return false
end

---------------------------------------------------------------------------
-- Peripherals
---------------------------------------------------------------------------
local function inventories()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "inventory") then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end

local function call(name, method, ...)
  local ok, a, b = pcall(peripheral.call, name, method, ...)
  if ok then return a, b end
  return nil, a
end

local function runBatched(fns, size)
  size = size or 32
  for i = 1, #fns, size do
    parallel.waitForAll(table.unpack(fns, i, math.min(i + size - 1, #fns)))
  end
end

---------------------------------------------------------------------------
-- Setup: find chests by watching which one gains an item
---------------------------------------------------------------------------
local function itemTotals()
  local t, fns = {}, {}
  for _, n in ipairs(inventories()) do
    fns[#fns + 1] = function()
      local c = 0
      for _, it in pairs(call(n, "list") or {}) do c = c + it.count end
      t[n] = c
    end
  end
  runBatched(fns)
  return t
end

local function pickChest(label)
  while true do
    print()
    print(("Setting up the %s."):format(label))
    print("Press Enter, then drop ONE item into it.")
    read()
    local before = itemTotals()
    print("Now drop the item in, then press Enter.")
    read()
    local after = itemTotals()
    local found = {}
    for n, c in pairs(after) do
      if c > (before[n] or 0) then found[#found + 1] = n end
    end
    if #found == 1 then
      print(("Got it: %s"):format(found[1]))
      return found[1]
    elseif #found == 0 then
      printError("Didn't see any chest change. Is its modem connected (right-clicked, red ring)?")
    else
      printError("More than one chest changed. Try again and only touch one.")
    end
  end
end

-- Marker setup: put exactly one marker item in each special chest, press Enter.
-- A chest only counts if it holds that single item and nothing else.
local MARKERS = {
  { key = "input",  item = "minecraft:stick",       what = "1 stick",       label = "MAIN INPUT",   need = true },
  { key = "output", item = "minecraft:dirt",        what = "1 dirt",        label = "OUTPUT",       need = true },
  { key = "dump",   item = "minecraft:cobblestone", what = "1 cobblestone", label = "MINER DUMP" },
  { key = "fuel",   item = "minecraft:lava_bucket", what = "1 lava bucket", label = "MINER FUEL" },
  { key = "rigger", item = "minecraft:brick",       what = "1 brick",       label = "RIGGER SUPPLY" },
  { key = "docks",  item = "minecraft:coal",        what = "1 coal",        label = "TURTLE DOCK", many = true },
}

local function markerScan()
  local found, fns = {}, {}
  for _, n in ipairs(inventories()) do
    fns[#fns + 1] = function()
      local only, total = nil, 0
      for _, it in pairs(call(n, "list") or {}) do
        total = total + it.count
        if only == nil or only == it.name then only = it.name else only = false end
      end
      if total ~= 1 or not only then return end
      for _, m in ipairs(MARKERS) do
        if m.item == only then
          found[m.key] = found[m.key] or {}
          table.insert(found[m.key], n)
        end
      end
    end
  end
  runBatched(fns)
  return found
end

local paused = false -- sorting and fuel top-up stop while setup runs

local function setup()
  paused = true
  term.clear(); term.setCursorPos(1, 1)
  print("STORAGE SETUP (sorting paused)")
  print("Put exactly one marker in each chest:")
  for _, m in ipairs(MARKERS) do
    print(("  %-14s %s%s"):format(m.what, m.label, m.many and " (one in each)" or m.need and "" or " (optional)"))
  end
  while true do
    print("Press Enter when they're all in.")
    read()
    local f, ok = markerScan(), true
    for _, m in ipairs(MARKERS) do
      local list = f[m.key] or {}
      if m.many and #list >= 1 then
        for _, n in ipairs(list) do print(("  %-11s %s"):format(m.label, n)) end
      elseif #list == 1 then
        print(("  %-11s %s"):format(m.label, list[1]))
      elseif #list == 0 then
        if m.need then printError("  " .. m.label .. ": not found"); ok = false
        else print(("  %-11s none (skipped)"):format(m.label)) end
      else
        printError(("  %s: %d chests have it. Keep it in one."):format(m.label, #list)); ok = false
      end
    end
    if ok then
      cfg.inputs = { f.input[1] }
      if f.dump then cfg.inputs[2] = f.dump[1] end
      cfg.output = f.output[1]
      cfg.fuel = f.fuel and f.fuel[1] or nil
      cfg.rigger = f.rigger and f.rigger[1] or nil
      cfg.docks = f.docks or {}
      saveCfg()
      break
    end
    print("Fix that and try again.")
  end
  paused = false
  print("Saved. Sorting is back on.")
  print("Stick and cobble get sorted away; the dirt stays in")
  print("the output; leave the lava bucket and dock coal, they're fuel.")
  os.sleep(3)
end

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------
local storage = {}   -- storage inventory names (everything except inputs/output/fuel)
local cache   = {}   -- name -> list() result
local sizes   = {}   -- name -> slot count
local info    = {}   -- item key -> { label, max }
local items   = {}   -- sorted item summaries
local byName  = {}   -- item id -> total count (all variants)
local stats   = { used = 0, total = 0, kinds = 0, inv = 0 }
local overCapList = {}  -- items storage has enough of (sent to Digger via the mainframe)
local minerFuelLimit, riggerBill = nil, {}   -- heard over the network from Digger / Rigger

local function keyOf(it) return it.name .. (it.nbt and ("#" .. it.nbt) or "") end

local function scanInv(n)
  cache[n] = call(n, "list") or {}
  if not sizes[n] then sizes[n] = call(n, "size") or 0 end
end

local furnaces = {}  -- furnaces on the network, used by auto-smelting

local function refreshStorageList()
  storage, furnaces = {}, {}
  local present = {}
  for _, n in ipairs(inventories()) do
    if isFurnace(n) then
      furnaces[#furnaces + 1] = n
    elseif not isSpecial(n) then
      storage[#storage + 1] = n
      present[n] = true
    end
  end
  for n in pairs(cache) do
    if not present[n] then cache[n] = nil; sizes[n] = nil end
  end
end

local function scanAll()
  refreshStorageList()
  local fns = {}
  for _, n in ipairs(storage) do fns[#fns + 1] = function() scanInv(n) end end
  runBatched(fns)
end

local function prettyName(id)
  local s = id:gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end

local function buildItems()
  local map = {}
  local used, total = 0, 0
  local missing, missingFns = {}, {}
  for _, n in ipairs(storage) do
    total = total + (sizes[n] or 0)
    for slot, it in pairs(cache[n] or {}) do
      used = used + 1
      local k = keyOf(it)
      local e = map[k]
      if not e then
        e = { key = k, name = it.name, count = 0 }
        map[k] = e
      end
      e.count = e.count + it.count
      if not info[k] and not missing[k] then
        missing[k] = true
        missingFns[#missingFns + 1] = function()
          local d = call(n, "getItemDetail", slot)
          info[k] = { label = d and d.displayName or prettyName(it.name), max = d and d.maxCount or 64 }
        end
      end
    end
  end
  runBatched(missingFns)
  items, byName = {}, {}
  local overCap = {}
  for _, e in pairs(map) do
    local i = info[e.key] or { label = prettyName(e.name), max = 64 }
    e.label, e.max = i.label, i.max
    items[#items + 1] = e
    byName[e.name] = (byName[e.name] or 0) + e.count
  end
  -- Anything Rigger's build still needs is kept until storage has enough of it
  local bill = riggerBill or {}
  for name, c in pairs(byName) do
    if c >= math.max(JUNK_CAP, bill[name] or 0) then overCap[#overCap + 1] = name end
  end
  overCapList = overCap -- broadcast; the mainframe's miner panel passes it to Digger
  if cfg.sort == "az" then
    table.sort(items, function(a, b)
      local la, lb = a.label:lower(), b.label:lower()
      if la ~= lb then return la < lb end
      return a.count > b.count
    end)
  else
    table.sort(items, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return a.label < b.label
    end)
  end
  stats.used, stats.total, stats.kinds, stats.inv = used, total, #items, #storage
end

local function freeSlots(n)
  local c = 0
  for _ in pairs(cache[n] or {}) do c = c + 1 end
  return (sizes[n] or 0) - c
end

local function holds(n, key)
  for _, s in pairs(cache[n] or {}) do
    if keyOf(s) == key then return true end
  end
  return false
end

-- Where an item should go, best first:
--   1. drawers already holding it          2. barrels/chests already holding it
--   3. barrels/chests with a free slot     4. drawers with a free slot (last resort)
local function targetsFor(key)
  local tiers = { {}, {}, {}, {} }
  for _, n in ipairs(storage) do
    local d = isDrawer(n)
    if holds(n, key) then
      table.insert(tiers[d and 1 or 2], n)
    elseif freeSlots(n) > 0 then
      table.insert(tiers[d and 4 or 3], n)
    end
  end
  local out = {}
  for _, t in ipairs(tiers) do
    for _, n in ipairs(t) do out[#out + 1] = n end
  end
  return out
end

---------------------------------------------------------------------------
-- Moving items
---------------------------------------------------------------------------
-- Empty one input chest into storage (drawers holding the item first, see targetsFor).
local function depositFrom(input, skip)
  local inp = call(input, "list")
  if not inp or not next(inp) then return 0, 0 end
  local movedTotal, leftTotal = 0, 0
  for slot, it in pairs(inp) do
    if not (skip and skip[it.name]) then
      local left = it.count
      for _, n in ipairs(targetsFor(keyOf(it))) do
        if left <= 0 then break end
        local moved = call(input, "pushItems", n, slot, left) or 0
        if moved > 0 then
          left = left - moved
          movedTotal = movedTotal + moved
          scanInv(n)
        end
      end
      leftTotal = leftTotal + math.max(left, 0)
    end
  end
  return movedTotal, leftTotal
end

-- Turtle docks: storage takes everything except fuel, which stays for the turtle
local DOCK_FUELS = { ["minecraft:coal"] = 80, ["minecraft:charcoal"] = 80, ["minecraft:coal_block"] = 800 }
local DOCK_FUEL_UNITS = 2560  -- about 32 coal

local inputStuck = false -- items in an input that storage had no room for
local function deposit()
  local moved, stuck = 0, false
  for _, input in ipairs(cfg.inputs) do
    local m, left = depositFrom(input)
    moved = moved + m
    if left > 0 then stuck = true end
  end
  for _, d in ipairs(cfg.docks or {}) do
    local m, left = depositFrom(d, DOCK_FUELS)
    moved = moved + m
    if left > 0 then stuck = true end
  end
  inputStuck = stuck
  return moved
end

-- Send `amount` of an item to `target` (default: the output chest).
-- Takes from barrels before drawers. Returns how many moved and whether the target filled up.
local function retrieve(key, amount, target, toSlot)
  target = target or cfg.output
  local got, full = 0, false
  local order = {}
  for _, n in ipairs(storage) do if not isDrawer(n) then order[#order + 1] = n end end
  for _, n in ipairs(storage) do if isDrawer(n) then order[#order + 1] = n end end
  for _, n in ipairs(order) do
    if got >= amount or full then break end
    local touched = false
    for slot, s in pairs(cache[n] or {}) do
      if got >= amount then break end
      if keyOf(s) == key then
        -- A drawer slot can hold thousands, so keep pulling from it until done
        local left = s.count
        while got < amount and left > 0 do
          local want = math.min(amount - got, left)
          local moved = call(n, "pushItems", target, slot, want, toSlot) or 0
          if moved <= 0 then full = true; break end
          got, left, touched = got + moved, left - moved, true
        end
        if full then break end
      end
    end
    if touched then scanInv(n) end
  end
  return got, full
end

-- Keep the miner's fuel barrel at (as close as possible to) exactly one refill.
local fuelUnits = 0
-- Keep each turtle dock stocked with ~32 coal worth of fuel (charcoal first, then coal)
local function topUpDocks()
  local changed = false
  for _, d in ipairs(cfg.docks or {}) do
    local have = 0
    local list = call(d, "list")
    if list then
      for _, it in pairs(list) do have = have + (DOCK_FUELS[it.name] or 0) * it.count end
      local deficit = DOCK_FUEL_UNITS - have
      for _, name in ipairs({ "minecraft:charcoal", "minecraft:coal" }) do
        local n = math.floor(deficit / 80)
        if n > 0 and (byName[name] or 0) > 0 then
          local moved = retrieve(name, math.min(n, byName[name]), d)
          if moved > 0 then deficit = deficit - moved * 80; changed = true; byName[name] = byName[name] - moved end
        end
      end
    end
  end
  return changed
end

local function topUpFuel()
  if not cfg.fuel then return false end
  local target = minerFuelLimit or REFILL
  local value = {}
  for _, fv in ipairs(FUEL_VALUES) do value[fv[1]] = fv[2] end
  local have = 0
  local list = call(cfg.fuel, "list")
  if not list then return false end
  for _, it in pairs(list) do have = have + (value[it.name] or 0) * it.count end
  fuelUnits = have
  local deficit = target - have
  local changed = false
  for _, fv in ipairs(FUEL_VALUES) do
    local name, v = fv[1], fv[2]
    local n = math.floor(deficit / v)
    if n > 0 and (byName[name] or 0) > 0 then
      local moved = retrieve(name, math.min(n, byName[name]), cfg.fuel)
      if moved > 0 then
        deficit = deficit - moved * v
        fuelUnits = fuelUnits + moved * v
        changed = true
      end
    end
  end
  return changed
end

---------------------------------------------------------------------------
-- Smelter jobs: the smelter computer decides, storage moves the items
---------------------------------------------------------------------------
-- Move a furnace slot back into storage (drawers holding it first, see targetsFor)
local function storeFrom(fz, slot)
  local d = call(fz, "getItemDetail", slot)
  if not d then return 0 end
  local moved = 0
  for _, n in ipairs(targetsFor(d.name)) do
    if moved >= d.count then break end
    local m = call(fz, "pushItems", n, slot) or 0
    if m > 0 then moved = moved + m; scanInv(n) end
  end
  return moved
end

-- ops: { op = "store", fz, slot } or { op = "fill", fz, slot, item, count }. Returns moved per op.
local function runSmeltOps(ops)
  local results = {}
  for i, o in ipairs(ops or {}) do
    local moved = 0
    if type(o) == "table" and type(o.fz) == "string" and isFurnace(o.fz) then
      if o.op == "store" then
        moved = storeFrom(o.fz, tonumber(o.slot) or 3)
      elseif o.op == "fill" and type(o.item) == "string" then
        moved = retrieve(o.item, math.max(0, math.min(tonumber(o.count) or 0, 64)), o.fz, tonumber(o.slot))
      end
    end
    results[i] = moved
  end
  return results
end

-- Fill Rigger's supply barrel with what he asked for (items + fuel units).
local lastRiggerSeq = nil
local riggerReq = nil            -- latest "need" message from Rigger (set by the network loop)
local function replyRigger(msg)
  if rednet.isOpen() then rednet.broadcast(msg, "tanis-rigger") end
end
local function supplyRigger()
  local req = riggerReq
  if not req or req.seq == lastRiggerSeq then return false end
  lastRiggerSeq = req.seq
  local got, missing = {}, {}
  if not cfg.rigger then
    replyRigger({ type = "supplied", seq = req.seq, got = got, missing = req.items or {} })
    return false
  end
  depositFrom(cfg.rigger)  -- take back whatever he handed in, then load the next batch
  buildItems()
  for _, e in ipairs(req.items or {}) do
    local name, want = e[1], e[2]
    local moved = retrieve(name, want, cfg.rigger)
    if moved > 0 then got[name] = moved end
    if moved < want then missing[#missing + 1] = { name, want - moved } end
  end
  local units = tonumber(req.fuel) or 0
  for _, fv in ipairs(FUEL_VALUES) do
    local name, v = fv[1], fv[2]
    local n = math.floor(units / v)
    if n > 0 and (byName[name] or 0) > 0 then
      local moved = retrieve(name, math.min(n, byName[name]), cfg.rigger)
      units = units - moved * v
      if moved > 0 then got[name] = (got[name] or 0) + moved end
    end
  end
  if units >= 80 then missing[#missing + 1] = { "fuel", units } end
  replyRigger({ type = "supplied", seq = req.seq, got = got, missing = missing })
  return true
end

---------------------------------------------------------------------------
-- Shared UI state
---------------------------------------------------------------------------
local filter   = ""
local page     = 1
local takeMode = 3            -- 1 = x1, 2 = x16, 3 = one stack
local TAKE     = { { "x1", 1 }, { "x16", 16 }, { "Stack", "stack" } }
local notice, noticeUntil = nil, 0

local function shown()
  if filter == "" then return items end
  local q, out = filter:lower(), {}
  for _, e in ipairs(items) do
    if e.label:lower():find(q, 1, true) or e.name:find(q, 1, true) then out[#out + 1] = e end
  end
  return out
end

local function fmt(n)
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e4 then return ("%dk"):format(math.floor(n / 1e3)) end
  return tostring(n)
end

local function amountFor(e)
  local t = TAKE[takeMode][2]
  return t == "stack" and (e.max or 64) or t
end

local function say(msg)
  notice, noticeUntil = msg, os.clock() + 4
end

---------------------------------------------------------------------------
-- Monitor
---------------------------------------------------------------------------
local mon = peripheral.find("monitor")
local touch = mon and mon.isColour() -- only advanced monitors send touch events
local hits = {}                       -- clickable regions for the current frame

local C = {
  bg = colours.black, bar = colours.grey, fg = colours.white, dim = colours.lightGrey,
  accent = colours.cyan, stripe = colours.grey, warn = colours.orange, good = colours.lime,
}

local function region(x1, x2, y, action) hits[#hits + 1] = { x1 = x1, x2 = x2, y = y, action = action } end

local function button(x, y, label, active, action)
  mon.setCursorPos(x, y)
  mon.setBackgroundColour(active and C.accent or C.bar)
  mon.setTextColour(active and colours.black or C.fg)
  mon.write(" " .. label .. " ")
  region(x, x + #label + 1, y, action)
  return x + #label + 3
end

local function draw()
  if not mon then return end
  mon.setTextScale(TEXT_SCALE)
  local w, h = mon.getSize()
  hits = {}
  mon.setBackgroundColour(C.bg); mon.clear()

  -- Header
  mon.setCursorPos(1, 1); mon.setBackgroundColour(C.bar); mon.clearLine()
  mon.setTextColour(C.accent); mon.write(" STORAGE")
  local pct = stats.total > 0 and math.floor(stats.used / stats.total * 100) or 0
  local right = ("%d items  %d/%d slots  %d%% "):format(stats.kinds, stats.used, stats.total, pct)
  if cfg.fuel then right = ("Fuel %d%%  "):format(math.floor(fuelUnits / (minerFuelLimit or REFILL) * 100)) .. right end
  mon.setTextColour(pct >= 90 and C.warn or C.dim)
  mon.setCursorPos(math.max(1, w - #right + 1), 1); mon.write(right)

  -- Search / notice line
  mon.setBackgroundColour(C.bg)
  mon.setCursorPos(2, 2)
  if notice and os.clock() < noticeUntil then
    mon.setTextColour(C.good); mon.write(notice:sub(1, w - 2))
  elseif filter ~= "" then
    mon.setTextColour(C.fg); mon.write(("Search: %s"):format(filter):sub(1, w - 10))
    mon.setCursorPos(w - 8, 2)
    mon.setBackgroundColour(C.bar); mon.write(" Clear ")
    region(w - 8, w - 2, 2, function() filter = ""; page = 1 end)
  else
    mon.setTextColour(C.dim)
    mon.write((touch and "Tap an item to send it to the output chest" or "Search on the computer"):sub(1, w - 2))
  end

  -- Sort switch (row 3)
  if touch then
    mon.setCursorPos(2, 3); mon.setBackgroundColour(C.bg); mon.setTextColour(C.dim); mon.write("Sort")
    local sx = button(7, 3, "Qty", cfg.sort ~= "az", function() cfg.sort = "qty"; saveCfg(); buildItems(); page = 1 end)
    button(sx - 1, 3, "A-Z", cfg.sort == "az", function() cfg.sort = "az"; saveCfg(); buildItems(); page = 1 end)
  end

  -- Item rows
  local list = shown()
  local top, bottom = 4, h - 2
  local rows = math.max(1, bottom - top + 1)
  local pages = math.max(1, math.ceil(#list / rows))
  page = math.min(math.max(page, 1), pages)
  if #list == 0 then
    mon.setCursorPos(2, top); mon.setTextColour(C.dim)
    mon.write(filter ~= "" and "Nothing matches." or "Empty. Drop items in the input chest.")
  end
  for i = 1, rows do
    local e = list[(page - 1) * rows + i]
    if not e then break end
    local y = top + i - 1
    mon.setCursorPos(1, y)
    mon.setBackgroundColour(i % 2 == 0 and C.stripe or C.bg); mon.clearLine()
    local count = fmt(e.count)
    mon.setTextColour(C.fg)
    mon.setCursorPos(2, y); mon.write(e.label:sub(1, w - #count - 4))
    mon.setTextColour(C.accent)
    mon.setCursorPos(w - #count, y); mon.write(count)
    region(1, w, y, function()
      local n, full = retrieve(e.key, amountFor(e))
      buildItems()
      say(n > 0 and ("Sent %d %s%s"):format(n, e.label, full and " (output full)" or "")
                 or ("Output chest is full"))
    end)
  end

  -- Footer: amount + paging
  local y = h
  mon.setCursorPos(1, y); mon.setBackgroundColour(C.bg); mon.clearLine()
  local x = 2
  if touch then
    for i, t in ipairs(TAKE) do
      x = button(x, y, t[1], takeMode == i, function() takeMode = i end)
    end
  end
  local label = ("%d/%d"):format(page, pages)
  local px = w - #label - 11
  if px > x then
    button(px, y, "<", page > 1, function() page = page - 1 end)
    mon.setBackgroundColour(C.bg); mon.setTextColour(C.dim)
    mon.setCursorPos(px + 4, y); mon.write(label)
    button(w - 4, y, ">", page < pages, function() page = page + 1 end)
  end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local jobs = {}                -- smelter requests waiting for the worker: { from, id, ops }
local lastBroadcast = -100

local function statusMsg()
  local avail = 0
  for _, fv in ipairs(FUEL_VALUES) do avail = avail + (byName[fv[1]] or 0) * fv[2] end
  return {
    type = "storage", id = os.getComputerID(), label = os.getComputerLabel(),
    used = stats.used, total = stats.total, kinds = stats.kinds, inputStuck = inputStuck,
    fuelUnits = cfg.fuel and fuelUnits or nil,
    fuelTarget = cfg.fuel and (minerFuelLimit or REFILL) or nil,
    fuelAvailable = avail, overcap = overCapList, items = byName, paused = paused,
  }
end

local function broadcastStatus()
  if rednet.isOpen() then rednet.broadcast(statusMsg(), BASE) end
  lastBroadcast = os.clock()
end

-- Wait for the next tick, waking early when the network hands us work
local function waitTick()
  if not paused and (#jobs > 0 or (riggerReq and riggerReq.seq ~= lastRiggerSeq)) then return end
  local t = os.startTimer(TICK)
  while true do
    local e, id = os.pullEvent()
    if (e == "timer" and id == t) or e == "storage_work" then return end
  end
end

local function workerLoop()
  local lastFull = os.clock()
  while true do
    if not paused then
      local moved = deposit()
      if os.clock() - lastFull >= FULL_SCAN then
        scanAll(); lastFull = os.clock()
        moved = moved + 1
      end
      if moved > 0 then buildItems() end
      if topUpFuel() then buildItems() end
      if topUpDocks() then buildItems() end
      if supplyRigger() then buildItems() end
      if #jobs > 0 then
        while #jobs > 0 do
          local j = table.remove(jobs, 1)
          local results = runSmeltOps(j.ops)
          if rednet.isOpen() then rednet.send(j.from, { type = "smelt_done", id = j.id, results = results }, BASE) end
        end
        buildItems()
        broadcastStatus()   -- the smelter plans its next move from fresh totals
      end
      draw()
    end
    waitTick()
  end
end

local function netLoop()
  local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
  if not modem then
    print("No wireless modem: the mainframe, smelter and turtles can't reach storage.")
    return os.pullEvent("never")
  end
  rednet.open(peripheral.getName(modem))
  while true do
    local from, msg, proto = rednet.receive(1)
    if type(msg) == "table" then
      if proto == "tanis-miner" and msg.type == "status" then
        minerFuelLimit = tonumber(msg.fuelLimit) or minerFuelLimit
      elseif proto == "tanis-rigger" and msg.type == "status" then
        riggerBill = type(msg.bill) == "table" and msg.bill or riggerBill
      elseif proto == "tanis-rigger" and msg.type == "need" then
        riggerReq = msg
        os.queueEvent("storage_work")
      elseif proto == BASE and msg.type == "smelt_ops" and type(msg.ops) == "table" then
        jobs[#jobs + 1] = { from = from, id = msg.id, ops = msg.ops }
        os.queueEvent("storage_work")
      end
    end
    if os.clock() - lastBroadcast >= STATUS_EVERY then broadcastStatus() end
  end
end

local function touchLoop()
  if not touch then return os.pullEvent("never") end
  while true do
    local _, _, x, y = os.pullEvent("monitor_touch")
    for _, r in ipairs(hits) do
      if y == r.y and x >= r.x1 and x <= r.x2 then
        r.action()
        draw()
        break
      end
    end
  end
end

local function help()
  print("Type a word to search, e.g. iron")
  print("Then: <number> [amount]  e.g. 2 32")
  print("/sort      switch between quantity and A-Z")
  print("/setup     pick chests with marker items")
  print("/inputs    show which chest is which")
  print("/addinput  add one more input chest")
  print("/clear /rescan /help")
end

local function terminalLoop()
  term.clear(); term.setCursorPos(1, 1)
  print(("Storage online: %d chests, %d item types."):format(stats.inv, stats.kinds))
  help()
  while true do
    print()
    write("search> ")
    local q = read()
    if q == "/help" then help()
    elseif q == "/clear" or q == "" then filter = ""; page = 1; draw()
    elseif q == "/rescan" then scanAll(); buildItems(); draw(); print("Rescanned.")
    elseif q == "/setup" then setup(); scanAll(); buildItems(); draw()
    elseif q == "/addinput" then
      local n = pickChest("extra INPUT chest (e.g. the miner's dump barrel)")
      if isSpecial(n) then printError("That one's already in use.") else
        cfg.inputs[#cfg.inputs + 1] = n; saveCfg(); scanAll(); buildItems(); draw()
        print("Added. Anything dropped in it gets sorted.")
      end
    elseif q == "/fuel" then
      local n = pickChest("miner FUEL barrel")
      if isSpecial(n) and n ~= cfg.fuel then printError("That one's already in use.") else
        cfg.fuel = n; saveCfg(); scanAll(); buildItems(); draw()
        print("Fuel barrel set. I'll keep one refill in it (coal, coal blocks, lava buckets...).")
      end
    elseif q == "/sort" then
      cfg.sort = cfg.sort == "az" and "qty" or "az"; saveCfg(); buildItems(); page = 1; draw()
      print(cfg.sort == "az" and "Sorted A-Z." or "Sorted by quantity.")
    elseif q == "/inputs" then
      for i, n in ipairs(cfg.inputs) do print(i .. "  " .. n) end
      print("Output: " .. tostring(cfg.output))
      print("Fuel:   " .. tostring(cfg.fuel or "not set"))
      print("Rigger: " .. tostring(cfg.rigger or "not set"))
      print("Docks:  " .. (#(cfg.docks or {}) > 0 and table.concat(cfg.docks, ", ") or "none"))
      local dn = 0
      for _, n in ipairs(storage) do if isDrawer(n) then dn = dn + 1 end end
      print(("Drawers: %d (filled first for items they hold)"):format(dn))
    else
      filter, page = q, 1
      draw()
      local list = shown()
      if #list == 0 then
        print("Nothing matches.")
      else
        local _, th = term.getSize()
        local max = math.min(#list, th - 6)
        for i = 1, max do
          print(("%2d  %-24s %s"):format(i, list[i].label:sub(1, 24), fmt(list[i].count)))
        end
        if #list > max then print(("...and %d more; be more specific."):format(#list - max)) end
        write("take # [amount]> ")
        local pick = read()
        local num, amt = pick:match("^%s*(%d+)%s*(%d*)")
        local e = num and list[tonumber(num)]
        if e then
          local n, full = retrieve(e.key, tonumber(amt) or e.max or 64)
          buildItems(); draw()
          print(n > 0 and ("Sent %d %s to the output chest.%s"):format(n, e.label, full and " Output is full." or "")
                       or "Output chest is full.")
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
loadCfg()
if #cfg.inputs == 0 or not cfg.output then setup() end
if mon then mon.setTextScale(TEXT_SCALE) end
print("Scanning storage...")
scanAll(); buildItems(); draw()
parallel.waitForAny(workerLoop, touchLoop, terminalLoop, netLoop)
