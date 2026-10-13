-- storage.lua  --  touch-screen storage system for CC:Tweaked (ATM10 / MC 1.21.1)
--
-- Hardware:
--   * An Advanced Computer
--   * Storage: any chests/barrels/drawers, each with a wired modem, joined with networking cable
--   * INPUT chest(s) and one OUTPUT chest, also on the network
--   * Optional: a FUEL barrel for each Digger (each kept at exactly one refill)
--   * Optional: an advanced monitor wall (touch screen). Normal monitors work as display-only.
--   * A wireless or ender modem, so it can talk to the mainframe and the turtles. The smelter can use the
--     wired cable instead: storage talks on every modem and passes the smelter's news on to the mainframe
--     (and the mainframe's smelt orders back).
--
-- Use:
--   * Dump items into any INPUT chest. They get sorted into storage automatically.
--   * Tap an item on the monitor to send it to the OUTPUT chest (tap x1 / x16 / Stack to choose how many).
--   * Or use the computer's own screen: type in the search bar at the bottom and the list filters
--     as you type; click an item (or press Enter for the top one) to send it. Qty / A-Z sorting,
--     x1 / x16 / Stack buttons and paging (scroll wheel, arrow keys) work the same as on the monitor.
--   * Commands: type / in the search bar to see them
--     (/setup /addinput /fuel /pocket /inputs /rescan /drawers /tidy /fuelinfo /lock /unlock)
-- Junk (cobble, deepslate, ...) is capped at JUNK_CAP; the miner is told to stop bringing more.
--
-- Storage is the only computer that moves items in or out of storage. Over the network it:
--   * broadcasts its status (fill level, item totals, junk caps) for the mainframe and smelter
--   * fills Rigger's supply barrel when he asks, and keeps each Digger fuel barrel at one refill
--   * carries out the smelter's moves (furnace output back to storage, inputs and fuel in)
--   * the mainframe's butler: empties the POCKET DUMP chest ($dump) and fills the POCKET RESTOCK chest
--     (torch top-ups). Both chests touch the mainframe's Inventory Manager and sit on this cable.
--
-- Screen lock: the monitor shows a big padlock (and ignores taps) while the butler says you're away
-- from the island, or after /lock. The computer's own screen always works. /unlock lifts a /lock.
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
local PRESENCE_STALE = 60           -- seconds without news from the butler before auto-lock lets go

-- Fuel value per item, best first. Used to keep the fuel barrel at exactly one refill.
local FUEL_VALUES = {
  { "minecraft:coal_block", 800 },
  { "minecraft:lava_bucket", 1000 },
  { "minecraft:blaze_rod", 120 },
  { "minecraft:coal", 80 },
  { "minecraft:charcoal", 80 },
}
-- Digger fuel barrels never take the last of these: the smelter burns them in the furnaces
local SMELTER_RESERVE = { ["minecraft:coal"] = 64, ["minecraft:charcoal"] = 64 }

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
  if cfg.fuel and not cfg.fuels then cfg.fuels = { cfg.fuel } end -- older config: one fuel barrel
  cfg.fuel = nil
  cfg.fuels = cfg.fuels or {}
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
-- Machines from these mods are never storage, even when their cable touches ours (the neural lab's
-- chambers and fabs, Powah's Furnator, the plastic factory's IF machines): nothing gets put in or
-- counted from them.
local MACHINE_MODS = { "hostilenetworks:", "powah:", "industrialforegoing:" }
local function isMachine(n)
  if n:find("furnace") ~= nil or n:find("smoker") ~= nil then return true end
  for _, m in ipairs(MACHINE_MODS) do if n:sub(1, #m) == m then return true end end
  return false
end

-- Drawers show up on the network as e.g. "functionalstorage:oak_1_0" or "storagedrawers:..."
local function isDrawer(n)
  return (n:find("drawer") or n:find("functionalstorage")) ~= nil
end

local function listRemove(list, n)
  for i = #list, 1, -1 do if list[i] == n then table.remove(list, i) end end
end
local function listAdd(list, n)
  for _, x in ipairs(list) do if x == n then return end end
  list[#list + 1] = n
end

local function isSpecial(n)
  if n == cfg.output or n == cfg.rigger or n == cfg.pocketIn or n == cfg.pocketOut then return true end
  for _, d in ipairs(cfg.docks or {}) do if d == n then return true end end
  for _, d in ipairs(cfg.fuels) do if d == n then return true end end
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

-- While a chest is being picked, sorting holds off: otherwise a dock (or input) would have the test
-- item sorted out of it before the second count, and the wrong chest would be picked.
local picking, workerBusy = false, false   -- workerBusy: a sorting pass is running (also for barrel probes)
local function pickChest(label)
  picking = true
  while workerBusy do os.sleep(0.2) end
  local function done(n) picking = false; return n end
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
      return done(found[1])
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
  { key = "dump",   item = "minecraft:cobblestone", what = "1 cobblestone", label = "DIGGER DUMP", many = true },
  { key = "fuel",   item = "minecraft:lava_bucket", what = "1 lava bucket", label = "DIGGER FUEL", many = true },
  { key = "rigger", item = "minecraft:brick",       what = "1 brick",       label = "RIGGER SUPPLY" },
  { key = "docks",  item = "minecraft:coal",        what = "1 coal",        label = "TURTLE DOCK", many = true },
  { key = "pocketIn",  item = "minecraft:flint",   what = "1 flint",       label = "POCKET DUMP",    keep = true },
  { key = "pocketOut", item = "minecraft:feather", what = "1 feather",     label = "POCKET RESTOCK", keep = true },
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
        elseif m.keep and cfg[m.key] then print(("  %-11s kept: %s"):format(m.label, cfg[m.key]))
        else print(("  %-11s none (skipped)"):format(m.label)) end
      else
        printError(("  %s: %d chests have it. Keep it in one."):format(m.label, #list)); ok = false
      end
    end
    if ok then
      cfg.inputs = { f.input[1] }
      for _, n in ipairs(f.dump or {}) do cfg.inputs[#cfg.inputs + 1] = n end
      cfg.output = f.output[1]
      cfg.fuels = f.fuel or {}
      for _, b in pairs(cfg.diggerBarrels or {}) do  -- barrels Diggers registered themselves
        if b.fuel then listAdd(cfg.fuels, b.fuel) end
        if b.dump then listAdd(cfg.inputs, b.dump) end
      end
      cfg.rigger = f.rigger and f.rigger[1] or nil
      cfg.docks = f.docks or {}
      cfg.pocketIn = f.pocketIn and f.pocketIn[1] or cfg.pocketIn     -- no marker: keep the old one
      cfg.pocketOut = f.pocketOut and f.pocketOut[1] or cfg.pocketOut
      saveCfg()
      break
    end
    print("Fix that and try again.")
  end
  paused = false
  print("Saved. Sorting is back on.")
  print("Stick and cobble get sorted away; the dirt stays in")
  print("the output; leave the lava bucket and dock coal, they're fuel.")
  print("The flint gets sorted away; the feather can stay.")
  os.sleep(3)
end

---------------------------------------------------------------------------
-- Index
---------------------------------------------------------------------------
local storage = {}   -- storage inventory names (everything except inputs/output/fuel)
local cache   = {}   -- name -> list() result
local sizes   = {}   -- name -> slot count
local limits  = {}   -- drawer name -> { slot -> how many it holds } (cleared on full scans)
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
  -- Sizes are re-read too: a drawer controller grows when you link more drawers to it
  for _, n in ipairs(storage) do fns[#fns + 1] = function() sizes[n] = nil; limits[n] = nil; scanInv(n) end end
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

-- How much one drawer slot holds (bigger drawers and upgrades hold more). Cached in `limits`.
local function slotLimit(n, s)
  limits[n] = limits[n] or {}
  local l = limits[n][s]
  if not l then
    l = call(n, "getItemLimit", s) or 64
    limits[n][s] = l
  end
  return l
end

-- A drawer inventory's slots holding `key`, biggest drawer first (then fullest)
local function drawerSlotsFor(n, key)
  local slots = {}
  for s, it in pairs(cache[n] or {}) do if keyOf(it) == key then slots[#slots + 1] = s end end
  table.sort(slots, function(a, b)
    local la, lb = slotLimit(n, a), slotLimit(n, b)
    if la ~= lb then return la > lb end
    return cache[n][a].count > cache[n][b].count
  end)
  return slots
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
-- Put up to `count` items from (from, slot) into storage inventory n. Into drawers that already
-- hold the item, aim at exactly those drawer slots, biggest drawer first until it's full: a drawer
-- controller left to choose drops items into any empty drawer it likes (duplicate drawers).
local function moveInto(from, slot, count, n, key)
  if isDrawer(n) then
    local slots = drawerSlotsFor(n, key)
    if #slots > 0 then
      local moved = 0
      for _, s in ipairs(slots) do
        if moved >= count then break end
        moved = moved + (call(from, "pushItems", n, slot, count - moved, s) or 0)
      end
      return moved
    end
  end
  return call(from, "pushItems", n, slot, count) or 0
end
-- Empty one input chest into storage (drawers holding the item first, see targetsFor).
local function depositFrom(input, skip)
  local inp = call(input, "list")
  if not inp or not next(inp) then return 0, 0 end
  local movedTotal, leftTotal = 0, 0
  for slot, it in pairs(inp) do
    if not (skip and skip[it.name]) then
      local left = it.count
      local key = keyOf(it)
      for _, n in ipairs(targetsFor(key)) do
        if left <= 0 then break end
        local moved = moveInto(input, slot, left, n, key)
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

-- One item spread over several drawers: fill its biggest drawer first, then the next biggest,
-- taking from the smallest. Moves go one stack at a time through an empty barrel slot.
-- Returns { [item id] = moved }.
local function emptyBarrelSlot()
  for _, b in ipairs(storage) do
    if not isDrawer(b) and freeSlots(b) > 0 then
      for j = 1, sizes[b] do if not cache[b][j] then return b, j end end
    end
  end
end

local function mergeDrawers(progress)
  local merged = {}
  for _, n in ipairs(storage) do
    if isDrawer(n) then
      local keys = {}
      for _, it in pairs(cache[n] or {}) do keys[keyOf(it)] = true end
      for key in pairs(keys) do
        local slots = drawerSlotsFor(n, key)   -- biggest first
        if #slots > 1 then
          local name = cache[n][slots[1]].name
          if progress then progress(name) end
          local dst, src = 1, #slots
          while dst < src do
            local d, sl = slots[dst], slots[src]
            local room = slotLimit(n, d) - ((cache[n][d] or {}).count or 0)
            local have = (cache[n][sl] or {}).count or 0
            if room <= 0 then dst = dst + 1
            elseif have <= 0 then src = src - 1
            else
              local b, bslot = emptyBarrelSlot()
              if not b then break end
              local out = call(b, "pullItems", n, sl, math.min(64, have, room), bslot) or 0
              if out <= 0 then break end
              local back = call(b, "pushItems", n, bslot, out, d) or 0
              merged[name] = (merged[name] or 0) + back
              scanInv(b); scanInv(n)
              if back < out then break end -- couldn't go back in: it stays safely in the barrel
            end
          end
        end
      end
    end
  end
  return merged
end

-- Move everything sitting in barrels into the drawers that already hold that item.
-- Returns { [item id] = moved }, and the items that didn't all fit (drawers full).
local function tidyDrawers(progress)
  local drawers, barrels = {}, {}
  for _, n in ipairs(storage) do
    if isDrawer(n) then drawers[#drawers + 1] = n else barrels[#barrels + 1] = n end
  end
  local moved, stuck = {}, {}
  for bi, b in ipairs(barrels) do
    if progress then progress(bi, #barrels) end
    local touched = false
    for slot, it in pairs(cache[b] or {}) do
      local key, left = keyOf(it), it.count
      for _, d in ipairs(drawers) do
        if left <= 0 then break end
        if holds(d, key) then
          local m = moveInto(b, slot, left, d, key)
          if m > 0 then
            left = left - m
            moved[it.name] = (moved[it.name] or 0) + m
            touched = true
            scanInv(d)
          end
        end
      end
      if left > 0 and left < it.count then stuck[it.name] = true end
    end
    if touched then scanInv(b) end
  end
  return moved, stuck
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
    local skip = DOCK_FUELS
    local keep = cfg.dockKeep and cfg.dockKeep[d]
    if keep and next(keep) then       -- this dock also keeps some of its own items (e.g. the neural lab's matrices)
      skip = {}
      for k, v in pairs(DOCK_FUELS) do skip[k] = v end
      for k in pairs(keep) do skip[k] = true end
    end
    local m, left = depositFrom(d, skip)
    moved = moved + m
    if left > 0 then stuck = true end
  end
  if cfg.pocketIn then                -- the butler's $dump lands here
    local m, left = depositFrom(cfg.pocketIn)
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
    local slots = {}
    if isDrawer(n) then
      local big = drawerSlotsFor(n, key)            -- smallest drawers are emptied first
      for i = #big, 1, -1 do slots[#slots + 1] = big[i] end
    else
      for slot, s in pairs(cache[n] or {}) do if keyOf(s) == key then slots[#slots + 1] = slot end end
    end
    for _, slot in ipairs(slots) do
      local s = cache[n][slot]
      if got >= amount then break end
      if s and keyOf(s) == key then
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

-- Emptiest Digger fuel barrel, in fuel units (see topUpFuel)
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
      -- Keep list (/dock): top each item up to its amount
      for name, want in pairs((cfg.dockKeep or {})[d] or {}) do
        local here = 0
        for _, it in pairs(list) do if it.name == name then here = here + it.count end end
        local n = math.min(want - here, byName[name] or 0)
        if n > 0 then
          local moved = retrieve(name, n, d)
          if moved > 0 then changed = true; byName[name] = byName[name] - moved end
        end
      end
    end
  end
  return changed
end

-- Keep every Digger fuel barrel at (as close as possible to) one refill.
-- fuelUnits = the emptiest barrel, for the screen and the mainframe's "running dry" alert.
local function topUpFuel()
  if #cfg.fuels == 0 then return false end
  local target = minerFuelLimit or REFILL
  local value = {}
  for _, fv in ipairs(FUEL_VALUES) do value[fv[1]] = fv[2] end
  local changed, lowest = false, nil
  for _, barrel in ipairs(cfg.fuels) do
    local list = call(barrel, "list")
    if list then
      local have = 0
      for _, it in pairs(list) do have = have + (value[it.name] or 0) * it.count end
      local deficit = target - have
      for _, fv in ipairs(FUEL_VALUES) do
        local name, v = fv[1], fv[2]
        local n = math.floor(deficit / v)
        local spare = (byName[name] or 0) - (SMELTER_RESERVE[name] or 0)
        if n > 0 and spare > 0 then
          local moved = retrieve(name, math.min(n, spare), barrel)
          if moved > 0 then
            deficit = deficit - moved * v
            have = have + moved * v
            byName[name] = byName[name] - moved
            changed = true
          end
        end
      end
      lowest = math.min(lowest or have, have)
    end
  end
  fuelUnits = lowest or 0
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
    local m = moveInto(fz, slot, d.count - moved, n, d.name)
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

-- The neural lab, when it's on this cable: matrices into its chambers, fuel into its Furnators.
-- ops: { op = "fill", to, item, count, slot }. Only those two targets and those items are allowed.
local NEURAL_FUEL = { ["minecraft:charcoal"] = true, ["minecraft:coal"] = true, ["minecraft:coal_block"] = true }
local function runNeuralOps(ops)
  local results = {}
  for i, o in ipairs(ops or {}) do
    local moved = 0
    if type(o) == "table" and o.op == "fill" and type(o.to) == "string" and type(o.item) == "string"
        and peripheral.isPresent(o.to) then
      local n = math.max(0, math.min(tonumber(o.count) or 0, 64))
      if o.to:find("^hostilenetworks:sim_chamber") and o.item == "hostilenetworks:prediction_matrix" then
        moved = retrieve(o.item, n, o.to, 2)
      elseif o.to:find("furnator") and NEURAL_FUEL[o.item] then
        n = math.min(n, (byName[o.item] or 0) - (SMELTER_RESERVE[o.item] or 0))   -- the smelter's last stack stays
        if n > 0 then moved = retrieve(o.item, n, o.to) end
      end
      if moved > 0 then byName[o.item] = (byName[o.item] or 0) - moved end
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

-- The butler's restock: make the POCKET RESTOCK chest (or, if none is set, the output chest) hold
-- `count` of an item (counting what's already in it), then tell it how many are waiting there.
-- It pulls them into your inventory.
local pocketReq, lastPocketSeq = nil, nil
local function fillPocket()
  local req = pocketReq
  if not req or req.seq == lastPocketSeq then return false end
  lastPocketSeq = req.seq
  local item = tostring(req.item)
  local want = math.max(0, math.min(tonumber(req.count) or 0, 27 * 64))
  if req.stack then want = (info[item] and info[item].max) or 64 end   -- $get with no number: one stack
  local have = 0
  local chest = cfg.pocketOut or cfg.output   -- no restock chest set: the normal output chest
  if chest then
    for _, it in pairs(call(chest, "list") or {}) do
      if it.name == item then have = have + it.count end
    end
    if have < want and (byName[item] or 0) > 0 then
      local moved = retrieve(item, math.min(want - have, byName[item]), chest)
      have = have + moved
    end
  end
  if rednet.isOpen() then
    rednet.broadcast({ type = "pocket_filled", seq = req.seq, item = item, got = math.min(have, want),
      ready = chest ~= nil }, BASE)
  end
  return true
end

---------------------------------------------------------------------------
-- Screen lock (the monitor only)
---------------------------------------------------------------------------
local presence = nil   -- latest news from the butler: { known, home, autoLock, at }
local function isLocked()
  if cfg.manualLock then return true, "manual" end
  local p = presence
  if p and p.known and p.autoLock and p.home == false and os.clock() - p.at < PRESENCE_STALE then
    return true, "away"
  end
  return false
end

---------------------------------------------------------------------------
-- Screens: the monitor wall and the computer's own screen share one item-list design.
-- Each screen ("view") has its own search, page and buttons.
---------------------------------------------------------------------------
local takeMode = 3            -- 1 = x1, 2 = x16, 3 = one stack (shared: same buttons on both screens)
local TAKE     = { { "x1", 1 }, { "x16", 16 }, { "Stack", "stack" } }
local uiBusy   = false        -- a command (/setup...) is using the computer's screen

local COMMANDS = {
  { "/setup",    "pick chests with marker items" },
  { "/addinput", "add one more input chest" },
  { "/fuel",     "add a Digger fuel barrel" },
  { "/dock",     "add a dock (turtle, plastic factory, neural lab) or set what it keeps" },
  { "/inputs",   "show which chest is which" },
  { "/rescan",   "re-read every chest now" },
  { "/drawers",  "what storage sees in the drawers" },
  { "/tidy",     "fill big drawers first; barrels in" },
  { "/fuelinfo", "Digger fuel barrels and fuel stock" },
  { "/pocket",   "pick the butler's dump + restock chests" },
  { "/lock",     "lock the monitor (padlock screen)" },
  { "/unlock",   "lift a /lock" },
}

local mon
local monView  = { kind = "monitor", filter = "", page = 1, hits = {} }

-- (Re)find the monitor: only one touching the computer (screens out on the cable belong to other
-- computers). Re-found when the wall re-forms or a monitor is added/removed.
local function findMonitor()
  mon = nil
  for _, side in ipairs(rs.getSides()) do
    if not mon and peripheral.hasType(side, "monitor") then
      local m = peripheral.wrap(side)
      local ok, w = pcall(m.getSize)
      if ok and w then mon = m end
    end
  end
  monView.dev, monView.touch, monView.hits = mon, mon and mon.isColour() or false, {}
  -- No setTextScale here: changing it fires monitor_resize, which calls this again. draw() sets it.
end
findMonitor()
local termView = { dev = term, kind = "term", touch = term.isColour(), filter = "", page = 1, hits = {} }

local C = {
  bg = colours.black, bar = colours.grey, fg = colours.white, dim = colours.lightGrey,
  accent = colours.cyan, stripe = colours.grey, warn = colours.orange, good = colours.lime,
}

local function shown(v)
  if v.filter == "" then return items end
  local q, out = v.filter:lower(), {}
  for _, e in ipairs(items) do
    if e.label:lower():find(q, 1, true) or e.name:find(q, 1, true) then out[#out + 1] = e end
  end
  return out
end

local function commandMatches(v)
  local out = {}
  for _, c in ipairs(COMMANDS) do
    if c[1]:sub(1, #v.filter) == v.filter:lower() then out[#out + 1] = c end
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

local function say(v, msg, colour)
  v.notice, v.noticeColour, v.noticeUntil = msg, colour or C.good, os.clock() + 4
end

local function take(v, e)
  local n, full = retrieve(e.key, amountFor(e))
  buildItems()
  say(v, n > 0 and ("Sent %d %s%s"):format(n, e.label, full and " (output full)" or "") or "Output chest is full",
    n > 0 and C.good or C.warn)
end

local function region(v, x1, x2, y, action) v.hits[#v.hits + 1] = { x1 = x1, x2 = x2, y = y, action = action } end

local function button(v, x, y, label, active, action)
  local d = v.dev
  d.setCursorPos(x, y)
  d.setBackgroundColour(active and C.accent or C.bar)
  d.setTextColour(active and colours.black or C.fg)
  d.write(" " .. label .. " ")
  region(v, x, x + #label + 1, y, action)
  return x + #label + 3
end

local runCommand -- defined further down (needs the terminal)

local function drawView(v)
  local d = v.dev
  if not d then return end
  if v.kind == "monitor" then d.setTextScale(TEXT_SCALE) end
  local w, h = d.getSize()
  if not w then -- the screen went away (see findMonitor)
    if v.kind == "monitor" then findMonitor() end
    return
  end
  local isTerm = v.kind == "term"
  v.hits = {}
  d.setCursorBlink(false)
  d.setBackgroundColour(C.bg); d.clear()

  -- Header
  d.setCursorPos(1, 1); d.setBackgroundColour(C.bar); d.clearLine()
  d.setTextColour(C.accent); d.write(" STORAGE")
  local pct = stats.total > 0 and math.floor(stats.used / stats.total * 100) or 0
  local right = ("%d items  %d/%d slots  %d%% "):format(stats.kinds, stats.used, stats.total, pct)
  if #cfg.fuels > 0 then right = ("Fuel %d%%  "):format(math.floor(fuelUnits / (minerFuelLimit or REFILL) * 100)) .. right end
  if #right > w - 9 then right = ("%d/%d slots %d%% "):format(stats.used, stats.total, pct) end
  if isTerm and isLocked() and #right + 9 <= w - 9 then right = "MONITOR LOCKED  " .. right end
  d.setTextColour(pct >= 90 and C.warn or C.dim)
  d.setCursorPos(math.max(1, w - #right + 1), 1); d.write(right)

  -- Notice / hint line
  d.setBackgroundColour(C.bg)
  d.setCursorPos(2, 2)
  if v.notice and os.clock() < v.noticeUntil then
    d.setTextColour(v.noticeColour or C.good); d.write(v.notice:sub(1, w - 2))
  elseif not isTerm and v.filter ~= "" then
    d.setTextColour(C.fg); d.write(("Search: %s"):format(v.filter):sub(1, w - 10))
    d.setCursorPos(w - 8, 2)
    d.setBackgroundColour(C.bar); d.write(" Clear ")
    region(v, w - 8, w - 2, 2, function() v.filter = ""; v.page = 1 end)
  else
    d.setTextColour(C.dim)
    local hint = isTerm and (v.touch and "Click an item to send it to the output chest" or "Type to search, Enter sends the top item")
      or (v.touch and "Tap an item to send it to the output chest" or "Search on the storage computer")
    d.write(hint:sub(1, w - 2))
  end

  -- Row 3: sort switch, and on the computer screen the take buttons too
  if v.touch then
    d.setCursorPos(2, 3); d.setBackgroundColour(C.bg); d.setTextColour(C.dim); d.write("Sort")
    local sx = button(v, 7, 3, "Qty", cfg.sort ~= "az", function() cfg.sort = "qty"; saveCfg(); buildItems(); v.page = 1 end)
    button(v, sx - 1, 3, "A-Z", cfg.sort == "az", function() cfg.sort = "az"; saveCfg(); buildItems(); v.page = 1 end)
    if isTerm then
      local tw = 0
      for _, t in ipairs(TAKE) do tw = tw + #t[1] + 3 end
      local x = w - tw + 1
      for i, t in ipairs(TAKE) do x = button(v, x, 3, t[1], takeMode == i, function() takeMode = i end) end
    end
  end

  -- List: items, or commands while the search starts with "/"
  local cmdMode = isTerm and v.filter:sub(1, 1) == "/"
  local list = cmdMode and commandMatches(v) or shown(v)
  local top = 4
  local bottom = isTerm and h - 2 or h - 2
  local rows = math.max(1, bottom - top + 1)
  local pages = math.max(1, math.ceil(#list / rows))
  v.page = math.min(math.max(v.page, 1), pages)
  v.first = list[(v.page - 1) * rows + 1]
  v.cmdMode = cmdMode
  if #list == 0 then
    d.setCursorPos(2, top); d.setTextColour(C.dim); d.setBackgroundColour(C.bg)
    d.write((cmdMode and "No command starts with that." or v.filter ~= "" and "Nothing matches."
      or "Empty. Drop items in the input chest."):sub(1, w - 2))
  end
  for i = 1, rows do
    local e = list[(v.page - 1) * rows + i]
    if not e then break end
    local y = top + i - 1
    d.setCursorPos(1, y)
    d.setBackgroundColour(i % 2 == 0 and C.stripe or C.bg); d.clearLine()
    if cmdMode then
      d.setTextColour(C.accent); d.setCursorPos(2, y); d.write(e[1])
      d.setTextColour(C.dim); d.setCursorPos(13, y); d.write(e[2]:sub(1, w - 14))
      region(v, 1, w, y, function() runCommand(e[1]) end)
    else
      local count = fmt(e.count)
      d.setTextColour(C.fg)
      d.setCursorPos(2, y); d.write(e.label:sub(1, w - #count - 4))
      d.setTextColour(C.accent)
      d.setCursorPos(w - #count, y); d.write(count)
      region(v, 1, w, y, function() take(v, e) end)
    end
  end

  -- Paging (+ take buttons on the monitor) on the second-to-last row (terminal) or last row (monitor)
  local y = isTerm and h - 1 or h
  d.setCursorPos(1, y); d.setBackgroundColour(C.bg); d.clearLine()
  local x = 2
  if not isTerm and v.touch then
    for i, t in ipairs(TAKE) do x = button(v, x, y, t[1], takeMode == i, function() takeMode = i end) end
  elseif isTerm then
    d.setTextColour(C.dim); d.setCursorPos(2, y)
    local tip = v.touch and "Enter: send top   / commands" or "Enter: send top  Arrows: page  / commands"
    d.write(tip:sub(1, math.max(0, w - 16)))
    x = math.min(w, 2 + #tip + 1)
  end
  local label = ("%d/%d"):format(v.page, pages)
  local px = w - #label - 11
  if px > x or (isTerm and pages > 1) then
    px = math.max(px, 1)
    button(v, px, y, "<", v.page > 1, function() v.page = v.page - 1 end)
    d.setBackgroundColour(C.bg); d.setTextColour(C.dim)
    d.setCursorPos(px + 4, y); d.write(label)
    button(v, w - 4, y, ">", v.page < pages, function() v.page = v.page + 1 end)
  end

  -- Search bar (computer screen only), with the typing cursor
  if isTerm then
    d.setCursorPos(1, h); d.setBackgroundColour(C.bar); d.clearLine()
    d.setTextColour(C.dim); d.write(" Search: ")
    local room = w - 10 - (v.filter ~= "" and 4 or 0)
    local shownText = #v.filter > room and v.filter:sub(-room) or v.filter
    d.setTextColour(C.fg); d.write(shownText)
    local cx = 10 + #shownText
    if v.filter ~= "" then
      d.setCursorPos(w - 2, h); d.setTextColour(C.dim); d.write(" x ")
      region(v, w - 2, w, h, function() v.filter = ""; v.page = 1 end)
    end
    d.setCursorPos(cx, h)
    d.setTextColour(C.fg)
    d.setCursorBlink(true)
  end
end

-- The padlock. Drawn at the biggest text scale it fits (worked out from the current size, so the
-- scale is only set once per lock: every scale change fires a monitor_resize).
local LOCK_ART = {
  "   .-----.   ",
  "  / .---. \\  ",
  "  | |   | |  ",
  "  | |   | |  ",
  ".-'-'---'-'-.",
  "|           |",
  "|    .-.    |",
  "|    '-'    |",
  "|     |     |",
  "|     |     |",
  "'-----------'",
}
local LOCK_W, LOCK_H = 13, #LOCK_ART + 4

local function drawLock(d, why)
  local cur = d.getTextScale and d.getTextScale() or TEXT_SCALE
  local w, h = d.getSize()
  local scale = 0.5
  for _, sc in ipairs({ 3, 2.5, 2, 1.5, 1, 0.5 }) do
    if math.floor(w * cur / sc) >= LOCK_W + 2 and math.floor(h * cur / sc) >= LOCK_H + 1 then scale = sc; break end
  end
  if scale ~= cur then d.setTextScale(scale) end
  w, h = d.getSize()
  monView.hits = {}
  d.setCursorBlink(false)
  d.setBackgroundColour(colours.black); d.clear()
  local function centre(y, text, colour)
    if y < 1 or y > h then return end
    d.setCursorPos(math.max(1, math.floor((w - #text) / 2) + 1), y)
    d.setTextColour(colour); d.write(text)
  end
  if h < LOCK_H or w < LOCK_W then           -- tiny monitor: just the word
    centre(math.floor(h / 2) + 1, "LOCKED", colours.red)
    return
  end
  local top = math.floor((h - LOCK_H) / 2) + 1
  local x = math.floor((w - LOCK_W) / 2) + 1
  for i, line in ipairs(LOCK_ART) do
    d.setCursorPos(x, top + i - 1)
    d.setTextColour(i <= 4 and colours.lightGrey or colours.yellow)
    d.write(line)
  end
  centre(top + #LOCK_ART + 1, "L O C K E D", colours.red)
  centre(top + #LOCK_ART + 3, why == "manual" and "locked from the computer" or "owner away", colours.grey)
end

local function draw()
  -- A broken screen must never stop the sorting, so each one is drawn on its own
  if mon then
    local locked, why = isLocked()
    local ok
    if locked then ok = pcall(drawLock, mon, why) else ok = pcall(drawView, monView) end
    if not ok then findMonitor() end
  end
  if not uiBusy then
    local ok, err = pcall(drawView, termView)
    if not ok then
      term.setBackgroundColour(colours.black); term.setTextColour(colours.red)
      term.setCursorPos(1, 1); term.clearLine(); term.write(("Screen error: " .. tostring(err)):sub(1, 51))
    end
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
    fuelUnits = #cfg.fuels > 0 and fuelUnits or nil,
    fuelTarget = #cfg.fuels > 0 and (minerFuelLimit or REFILL) or nil,
    fuelBarrels = #cfg.fuels,
    fuelAvailable = avail, overcap = overCapList, items = byName, paused = paused,
    locked = (isLocked()), pocketDump = cfg.pocketIn ~= nil, pocketRestock = cfg.pocketOut ~= nil,
    mainInput = cfg.inputs[1], restockChest = cfg.pocketOut or cfg.output,   -- the butler uses these over the cable
    docks = cfg.docks,                       -- the neural lab finds its dock among these if the cables are joined
  }
end

local function broadcastStatus()
  if rednet.isOpen() then rednet.broadcast(statusMsg(), BASE) end
  lastBroadcast = os.clock()
end

-- Wait for the next tick, waking early when the network hands us work
local function waitTick()
  if not paused and (#jobs > 0 or (riggerReq and riggerReq.seq ~= lastRiggerSeq)
    or (pocketReq and pocketReq.seq ~= lastPocketSeq)) then return end
  local t = os.startTimer(TICK)
  while true do
    local e, id = os.pullEvent()
    if (e == "timer" and id == t) or e == "storage_work" then return end
  end
end

-- workerBusy (declared with pickChest): a sorting pass is running (a barrel probe waits for it to finish)

local function workerLoop()
  local lastFull = os.clock()
  while true do
    if not paused and not picking then
      workerBusy = true
      local moved = deposit()
      if os.clock() - lastFull >= FULL_SCAN then
        scanAll(); lastFull = os.clock()
        moved = moved + 1
      end
      if moved > 0 then buildItems() end
      if topUpFuel() then buildItems() end
      if topUpDocks() then buildItems() end
      if supplyRigger() then buildItems() end
      if fillPocket() then buildItems() end
      if #jobs > 0 then
        while #jobs > 0 do
          local j = table.remove(jobs, 1)
          local neural = j.kind == "neural"
          local results = neural and runNeuralOps(j.ops) or runSmeltOps(j.ops)
          if rednet.isOpen() then
            rednet.send(j.from, { type = neural and "neural_done" or "smelt_done", id = j.id, results = results }, BASE)
          end
        end
        buildItems()
        broadcastStatus()   -- the smelter plans its next move from fresh totals
      end
      workerBusy = false
      draw()
    end
    waitTick()
  end
end

---------------------------------------------------------------------------
-- Digger barrel probe: a Digger takes 1 item from its fuel barrel and drops it in its dump barrel
-- while sorting is paused. The barrel that lost it is its fuel barrel, the one that gained it its
-- dump barrel; both get registered (fuel barrel kept topped up, dump barrel emptied like an input).
---------------------------------------------------------------------------
local probe = nil   -- { id, snap, untilT }

local function snapshotAll()
  local snap, fns = {}, {}
  for _, n in ipairs(inventories()) do
    fns[#fns + 1] = function()
      local t = {}
      for _, it in pairs(call(n, "list") or {}) do t[it.name] = (t[it.name] or 0) + it.count end
      snap[n] = t
    end
  end
  runBatched(fns)
  return snap
end

local function registerDiggerBarrels(id, fuel, dump)
  cfg.diggerBarrels = cfg.diggerBarrels or {}
  if fuel then
    listRemove(cfg.inputs, fuel); listRemove(cfg.docks or {}, fuel)
    listAdd(cfg.fuels, fuel)
  end
  if dump and dump ~= fuel then
    listRemove(cfg.fuels, dump); listRemove(cfg.docks or {}, dump)
    listAdd(cfg.inputs, dump)
  end
  cfg.diggerBarrels[tostring(id)] = { fuel = fuel, dump = dump }
  saveCfg()
  scanAll(); buildItems()
end

local function probeFinish(from, item)
  local after = snapshotAll()
  local fuel, dump, fuelN, dumpN = nil, nil, 0, 0
  if item then
    for n, before in pairs(probe.snap) do
      local delta = ((after[n] or {})[item] or 0) - (before[item] or 0)
      if delta == -1 then fuel, fuelN = n, fuelN + 1 end
      if delta == 1 then dump, dumpN = n, dumpN + 1 end
    end
  end
  probe = nil
  local ok, msg = false, nil
  if not item then
    msg = "Fuel barrel empty: put one coal in it and try again"
  elseif fuelN ~= 1 or dumpN ~= 1 then
    msg = "Couldn't tell which barrels moved. Are both on the storage cable with modems on?"
  else
    registerDiggerBarrels(from, fuel, dump)
    ok, msg = true, "Storage knows my barrels: fuel " .. fuel .. ", dump " .. dump
  end
  paused = false
  rednet.send(from, { type = "probe_result", id = from, ok = ok, msg = msg, fuel = fuel, dump = dump }, "tanis-miner")
  os.queueEvent("storage_work")
end

local function netLoop()
  -- Every modem: wireless for the mainframe/turtles, the wired cable for the smelter
  local wireless = false
  peripheral.find("modem", function(name, m)
    rednet.open(name)
    if m.isWireless() then wireless = true end
    return false
  end)
  if not wireless then print("No wireless modem: the mainframe and turtles can't reach storage.") end
  while true do
    local from, msg, proto = rednet.receive(1)
    if probe and os.clock() > probe.untilT then probe = nil; paused = false end -- Digger never finished
    if type(msg) == "table" and proto == "tanis-miner" and msg.type == "barrel_probe" and msg.id == from then
      if msg.step == "start" and not probe then
        paused = true
        local t = os.clock() + 20
        while workerBusy and os.clock() < t do os.sleep(0.2) end
        probe = { id = from, snap = snapshotAll(), untilT = os.clock() + 30 }
        rednet.send(from, { type = "probe_ready", id = from }, "tanis-miner")
      elseif msg.step == "done" and probe and probe.id == from then
        probeFinish(from, msg.item)
      end
    elseif type(msg) == "table" then
      if proto == "tanis-miner" and msg.type == "status" then
        minerFuelLimit = tonumber(msg.fuelLimit) or minerFuelLimit
      elseif proto == "tanis-rigger" and msg.type == "status" then
        riggerBill = type(msg.bill) == "table" and msg.bill or riggerBill
      elseif proto == "tanis-rigger" and msg.type == "need" then
        riggerReq = msg
        os.queueEvent("storage_work")
      elseif proto == BASE and msg.type == "pocket_fill" and msg.seq then
        pocketReq = msg
        os.queueEvent("storage_work")
      elseif proto == BASE and msg.type == "presence" then
        local was = isLocked()
        presence = { known = msg.known == true, home = msg.home, autoLock = msg.autoLock ~= false, at = os.clock() }
        if isLocked() ~= was then os.queueEvent("storage_work") end   -- redraw now, not next tick
      elseif proto == BASE and msg.type == "smelt_ops" and type(msg.ops) == "table" then
        jobs[#jobs + 1] = { from = from, id = msg.id, ops = msg.ops }
        os.queueEvent("storage_work")
      elseif proto == BASE and msg.type == "neural_ops" and type(msg.ops) == "table" then
        jobs[#jobs + 1] = { from = from, id = msg.id, ops = msg.ops, kind = "neural" }
        os.queueEvent("storage_work")
      end
      -- Relay between the cable and the air, so a wired-only smelter still reaches the mainframe
      if proto == BASE and (msg.type == "smelter" or msg.type == "smelt_cmd") and not msg.relayed then
        local copy = {}
        for k, v in pairs(msg) do copy[k] = v end
        copy.relayed = true
        rednet.broadcast(copy, BASE)
      end
    end
    if os.clock() - lastBroadcast >= STATUS_EVERY then broadcastStatus() end
  end
end

local function clickIn(v, x, y)
  for _, r in ipairs(v.hits) do
    if y == r.y and x >= r.x1 and x <= r.x2 then
      r.action()
      return true
    end
  end
end

local function touchLoop()
  while true do
    local e, side, x, y = os.pullEvent()
    if e == "monitor_touch" then
      if monView.touch and mon and not isLocked() and side == peripheral.getName(mon) and clickIn(monView, x, y) then draw() end
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      findMonitor(); draw()
    end
  end
end

-- Commands take over the computer's screen for a moment (they print and ask questions)
local function waitEnter()
  print()
  write("Press Enter to go back.")
  read()
end

function runCommand(cmd)
  cmd = cmd:lower():match("^%s*(%S+)") or ""
  local found
  for _, c in ipairs(COMMANDS) do if c[1] == cmd then found = c[1] end end
  if not found then
    local m = commandMatches(termView)
    if #m == 1 then found = m[1][1] end
  end
  if not found then say(termView, "Unknown command. Type / to see them all.", C.warn); return end
  uiBusy = true
  termView.filter, termView.page = "", 1
  term.setCursorBlink(false)
  term.setBackgroundColour(colours.black); term.setTextColour(colours.white)
  term.clear(); term.setCursorPos(1, 1)
  local ok, err = pcall(function()
    if found == "/setup" then
      setup(); scanAll(); buildItems()
    elseif found == "/drawers" then
      print("Rescanning..."); scanAll(); buildItems()
      local any = false
      for _, n in ipairs(storage) do
        if isDrawer(n) then
          any = true
          local list = cache[n] or {}
          local used, totals, order = 0, {}, {}
          for _, it in pairs(list) do
            used = used + 1
            if not totals[it.name] then order[#order + 1] = it.name; totals[it.name] = 0 end
            totals[it.name] = totals[it.name] + it.count
          end
          table.sort(order, function(a, b) return totals[a] > totals[b] end)
          print(("%s: %d slots, %d in use"):format(n, sizes[n] or 0, used))
          if (sizes[n] or 0) == 0 then
            printError("  No slots: no drawers are linked to it (Linking Tool).")
          end
          for i = 1, math.min(6, #order) do print(("  %6d %s"):format(totals[order[i]], order[i])) end
          if #order > 6 then print(("  ...and %d more"):format(#order - 6)) end
        end
      end
      if not any then printError("No drawers or drawer controller found on the cable.") end
      print("Items held here get stored here first.")
      waitEnter()
    elseif found == "/tidy" then
      print("Rescanning..."); scanAll()
      local merged = mergeDrawers(function(name) print("Merging duplicate drawers: " .. name) end)
      local mtotal = 0
      for _, c in pairs(merged) do mtotal = mtotal + c end
      if mtotal > 0 then print(("Moved %d items into bigger drawers."):format(mtotal)) end
      local _, py = term.getCursorPos()
      local moved, stuck = tidyDrawers(function(i, n)
        term.setCursorPos(1, py); term.clearLine(); write(("Checking barrels %d/%d"):format(i, n))
      end)
      print()
      buildItems()
      local order, total = {}, 0
      for name, c in pairs(moved) do order[#order + 1] = name; total = total + c end
      table.sort(order, function(a, b) return moved[a] > moved[b] end)
      if total == 0 then
        print("Nothing to move: no barrel holds anything your drawers hold.")
      else
        print(("Moved %d items into the drawers:"):format(total))
        for i = 1, math.min(8, #order) do print(("  %6d %s"):format(moved[order[i]], order[i])) end
        if #order > 8 then print(("  ...and %d more kinds"):format(#order - 8)) end
      end
      local full = {}
      for name in pairs(stuck) do full[#full + 1] = name end
      if #full > 0 then printError("Drawer full, some left in barrels: " .. table.concat(full, ", ")) end
      waitEnter()
    elseif found == "/fuelinfo" then
      print("Rescanning..."); scanAll(); buildItems()
      local target = minerFuelLimit or REFILL
      print(("Each Digger fuel barrel is kept at %d fuel"):format(target))
      print(minerFuelLimit and "(a Digger's full tank)." or "(default: no Digger heard yet).")
      if not minerFuelLimit then
        printError("Storage hasn't heard a Digger: it needs a wireless or ender modem on it.")
      end
      local value = {}
      for _, fv in ipairs(FUEL_VALUES) do value[fv[1]] = fv[2] end
      if #cfg.fuels == 0 then printError("No fuel barrels set: use /fuel or /setup (lava bucket).") end
      for _, b in ipairs(cfg.fuels) do
        local have, parts = 0, {}
        for _, it in pairs(call(b, "list") or {}) do
          have = have + (value[it.name] or 0) * it.count
          parts[it.name] = (parts[it.name] or 0) + it.count
        end
        local txt = {}
        for name, c in pairs(parts) do txt[#txt + 1] = c .. " " .. name:gsub("^minecraft:", "") end
        print(("%s: %d fuel (%d%%)"):format(b, have, math.floor(have / target * 100)))
        print("  " .. (#txt > 0 and table.concat(txt, ", ") or "empty"))
      end
      print("In storage (best first):")
      for _, fv in ipairs(FUEL_VALUES) do
        local c = byName[fv[1]] or 0
        local keep = SMELTER_RESERVE[fv[1]]
        print(("  %5d %s%s"):format(c, fv[1]:gsub("^minecraft:", ""), keep and (" (last " .. keep .. " kept for the smelter)") or ""))
      end
      waitEnter()
    elseif found == "/rescan" then
      print("Rescanning..."); scanAll(); buildItems()
      say(termView, "Rescanned.")
    elseif found == "/addinput" then
      local n = pickChest("extra INPUT chest (e.g. the miner's dump barrel)")
      if isSpecial(n) then printError("That one's already in use."); waitEnter() else
        cfg.inputs[#cfg.inputs + 1] = n; saveCfg(); scanAll(); buildItems()
        say(termView, "Input added. Anything dropped in it gets sorted.")
      end
    elseif found == "/fuel" then
      local n = pickChest("Digger FUEL barrel (pick one that's already a fuel barrel to remove it)")
      local idx
      for i, f in ipairs(cfg.fuels) do if f == n then idx = i end end
      if idx then
        table.remove(cfg.fuels, idx); saveCfg(); scanAll(); buildItems()
        say(termView, "Fuel barrel removed. It's normal storage again.", C.warn)
      elseif isSpecial(n) then printError("That one's already in use."); waitEnter() else
        cfg.fuels[#cfg.fuels + 1] = n; saveCfg(); scanAll(); buildItems()
        say(termView, ("Fuel barrel added (%d now). I'll keep one refill in each."):format(#cfg.fuels))
      end
    elseif found == "/dock" then
      local n = pickChest("DOCK barrel: I keep ~32 coal in it and take everything else (pick a dock again to change or remove it)")
      cfg.docks = cfg.docks or {}
      cfg.dockKeep = cfg.dockKeep or {}
      local idx
      for i, d in ipairs(cfg.docks) do if d == n then idx = i end end
      -- "<item> <count>" lines: what this dock keeps besides coal (the neural lab: prediction_matrix 64)
      local function editKeep()
        local keep = cfg.dockKeep[n] or {}
        print("Besides coal, this dock keeps:")
        local any = false
        for name, c in pairs(keep) do print(("  %d %s"):format(c, name)); any = true end
        if not any then print("  nothing") end
        print("Type <item> <count> to keep some (0 = stop),")
        print("e.g. prediction_matrix 64. Blank line = done.")
        while true do
          write("> ")
          local line = read()
          if not line or line:match("^%s*$") then break end
          local item, cnt = line:match("^%s*(%S+)%s+(%d+)%s*$")
          if not item then printError("Like this: prediction_matrix 64")
          else
            item = item:lower()
            local id = item:find(":") and item or nil
            if not id then
              local hits, seen = {}, {}
              for name in pairs(byName) do
                if name:match(":(.+)$") == item and not seen[name] then hits[#hits + 1] = name; seen[name] = true end
              end
              if #hits == 0 then   -- none in storage: look in every chest on the cable (the dock itself, say)
                for _, inv in ipairs(inventories()) do
                  for _, it in pairs(call(inv, "list") or {}) do
                    if it.name:match(":(.+)$") == item and not seen[it.name] then hits[#hits + 1] = it.name; seen[it.name] = true end
                  end
                end
              end
              if #hits == 1 then id = hits[1]
              elseif #hits > 1 then printError("Which one? " .. table.concat(hits, ", "))
              else printError("None of that on the cable. Use its full id, like hostilenetworks:prediction_matrix") end
            end
            if id then
              cnt = tonumber(cnt)
              keep[id] = cnt > 0 and cnt or nil
              print(cnt > 0 and ("Keeping %d %s in it."):format(cnt, id) or ("Not keeping %s any more."):format(id))
            end
          end
        end
        cfg.dockKeep[n] = next(keep) and keep or nil
      end
      if idx then
        print("That's already a dock. 1 = change what it keeps, 2 = remove it")
        write("> ")
        local ch = read()
        if ch and ch:match("^%s*2") then
          table.remove(cfg.docks, idx); cfg.dockKeep[n] = nil; saveCfg(); scanAll(); buildItems()
          say(termView, "Dock removed. It's normal storage again.", C.warn)
        else
          editKeep(); saveCfg(); scanAll(); buildItems()
          say(termView, "Dock keep list saved.")
        end
      elseif isSpecial(n) then printError("That one's already in use."); waitEnter() else
        cfg.docks[#cfg.docks + 1] = n
        print("Dock added. Keep anything else in it? (blank = just coal)")
        editKeep(); saveCfg(); scanAll(); buildItems()
        say(termView, ("Dock added (%d now). The test item gets sorted away."):format(#cfg.docks))
      end
    elseif found == "/lock" then
      cfg.manualLock = true; saveCfg()
      say(termView, "Monitor locked. /unlock to open it again.", C.warn)
    elseif found == "/unlock" then
      cfg.manualLock = false; saveCfg()
      if isLocked() then
        say(termView, "Unlocked, but the butler says you're away so it stays locked (AUTO_LOCK).", C.warn)
      else
        say(termView, "Monitor unlocked.")
      end
    elseif found == "/pocket" then
      print("The butler's pocket chests, each with a wired modem on")
      print("this storage cable: touching the mainframe's Inventory")
      print("Manager, or anywhere if the mainframe is on this cable.")
      local function free(n) return not isSpecial(n) or n == cfg.pocketIn or n == cfg.pocketOut end
      local a = pickChest("POCKET DUMP chest ($dump sends your stuff here)")
      if not free(a) then printError("That one's already in use."); waitEnter(); return end
      local b = pickChest("POCKET RESTOCK chest (torch top-ups wait here)")
      if not free(b) then printError("That one's already in use."); waitEnter(); return end
      if a == b then printError("That's the same chest twice. Use two."); waitEnter(); return end
      cfg.pocketIn, cfg.pocketOut = a, b
      saveCfg(); scanAll(); buildItems()
      say(termView, "Pocket chests set. Take the test items back out of the restock chest.")
    elseif found == "/inputs" then
      for i, n in ipairs(cfg.inputs) do print(i .. "  " .. n) end
      print("Output: " .. tostring(cfg.output))
      print("Fuel:   " .. (#cfg.fuels > 0 and table.concat(cfg.fuels, ", ") or "not set"))
      print("Rigger: " .. tostring(cfg.rigger or "not set"))
      print("Docks:  " .. (#(cfg.docks or {}) > 0 and table.concat(cfg.docks, ", ") or "none"))
      for d, keep in pairs(cfg.dockKeep or {}) do
        local t = {}
        for name, c in pairs(keep) do t[#t + 1] = c .. " " .. name:gsub("^[^:]+:", "") end
        print(("  %s keeps %s"):format(d, table.concat(t, ", ")))
      end
      print("Pocket: dump " .. tostring(cfg.pocketIn or "not set") .. ", restock " .. tostring(cfg.pocketOut or "not set"))
      local dn = 0
      for _, n in ipairs(storage) do if isDrawer(n) then dn = dn + 1 end end
      print(("Drawers: %d (filled first for items they hold)"):format(dn))
      waitEnter()
    end
  end)
  uiBusy = false
  picking = false   -- in case a command stopped halfway through picking a chest
  if not ok then say(termView, "Error: " .. tostring(err), C.warn) end
  draw()
end

-- The computer's own screen: type to filter, click (advanced) or Enter to take, scroll/arrows to page
local function terminalLoop()
  local v = termView
  draw()
  while true do
    local e, a, b, c = os.pullEvent()
    local redraw = true
    if uiBusy then
      redraw = false
    elseif e == "char" then
      v.filter, v.page = v.filter .. a, 1
    elseif e == "paste" then
      v.filter, v.page = v.filter .. a:gsub("[\r\n]", ""), 1
    elseif e == "key" then
      if a == keys.backspace then
        v.filter, v.page = v.filter:sub(1, -2), 1
      elseif a == keys.delete then
        v.filter, v.page = "", 1
      elseif a == keys.enter or a == keys.numPadEnter then
        if v.filter:sub(1, 1) == "/" then
          runCommand(v.filter)
        elseif v.first then
          take(v, v.first)
        end
      elseif a == keys.up or a == keys.pageUp then
        v.page = v.page - 1
      elseif a == keys.down or a == keys.pageDown then
        v.page = v.page + 1
      else
        redraw = false
      end
    elseif e == "mouse_click" then
      redraw = clickIn(v, b, c) or false
    elseif e == "mouse_scroll" then
      v.page = v.page + a
    elseif e == "term_resize" then
      redraw = true
    else
      redraw = false
    end
    if redraw and not uiBusy then draw() end
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
loadCfg()
if #cfg.inputs == 0 or not cfg.output then setup() end
print("Scanning storage...")
scanAll(); buildItems(); draw()
parallel.waitForAny(workerLoop, touchLoop, terminalLoop, netLoop)
