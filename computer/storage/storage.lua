-- storage.lua  --  touch-screen storage system for CC:Tweaked (ATM10 / MC 1.21.1)
--
-- Hardware:
--   * An Advanced Computer
--   * Storage: any chests/barrels/drawers, each with a wired modem, joined with networking cable
--   * INPUT chest(s) and one OUTPUT chest, also on the network
--   * Optional: a FUEL barrel for each Canary (each kept at exactly one refill)
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
--     (/assign /setup /rescan /drawers /tidy /fuelinfo /lock /unlock)
--   * /assign: the list of inventories that have a job (input, output, dock, Canary fuel, Weaver supply,
--     pocket dump/restock, drawers, ignore), picked by network name (type to narrow it down, e.g.
--     "barrel_74" or "drawer") or by dropping one item in. Add, edit (type + nickname) or delete them.
--     ANY number of inputs. Everything not on the list is storage. (/dock /fuel /pocket /addinput
--     /inputs still work: they open /assign.)
-- Junk (cobble, deepslate, ...) is capped at JUNK_CAP; the miner is told to stop bringing more.
--
-- Storage is the only computer that moves items in or out of storage. Over the network it:
--   * broadcasts its status (fill level, item totals, junk caps) for the mainframe and smelter
--   * fills Weaver's supply barrel when he asks, and keeps each Canary fuel barrel at one stack of coal's worth
--   * carries out the smelter's moves (furnace output back to storage, inputs and fuel in)
--   * the mainframe's butler: empties the POCKET DUMP chest ($dump) and fills the POCKET RESTOCK chest
--     (torch top-ups). Both chests touch the mainframe's Inventory Manager and sit on this cable.
--
-- Screen lock: the monitor shows a big padlock (and ignores taps) while the butler says you're away
-- from the island, or after /lock. The computer's own screen always works. /unlock lifts a /lock.
--
-- Drawers (Functional Storage / Storage Drawers) come first: a drawer already holding the item
-- (with room), then an empty drawer (smallest that fits the pile), then barrels. /tidy reshuffles
-- the drawers so the biggest piles (in STACKS: 100 lava buckets beat 101 cobble) get the biggest
-- drawers, and sends the small fry to the barrels when drawers run out.
-- Claim a drawer by putting one of the item in it (and lock it). Taking items out empties
-- barrels before drawers, so loose stock drains away over time.

local CONFIG       = "storage.cfg"
local TICK         = 2       -- seconds between input-chest checks
local FULL_SCAN    = 30      -- seconds between full rescans (catches things you move by hand)
local TEXT_SCALE   = 0.5
local JUNK_CAP     = 20 * 64 -- items of one kind before the miner stops bringing more of it
local REFILL       = 20000   -- fuel units in one turtle refill (updated live from the miner's tank size)
local CANARY_FUEL  = 64 * 80 -- fuel units kept in each Canary fuel barrel: one stack of coal's worth
                             -- (6 coal blocks, 5 lava buckets ...). Anything over that goes back to storage.
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
-- Canary fuel barrels never take the last of these: the smelter burns them in the furnaces
local SMELTER_RESERVE = { ["minecraft:coal"] = 64, ["minecraft:charcoal"] = 64 }

---------------------------------------------------------------------------
-- Config
---------------------------------------------------------------------------
local cfg = {}
local RULES   -- depot rules (storage_rules.lua), set up below
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
  cfg.drawers = cfg.drawers or {}   -- assigned as drawers (bulk storage) by hand, besides those found by name
  cfg.ignored = cfg.ignored or {}   -- never touched or counted
  cfg.fluidDepots = cfg.fluidDepots or {}   -- tank -> the fluid storage keeps it filled with ("" = not chosen yet)
  cfg.depots = cfg.depots or {}     -- container -> its rule { item, tag, mod, enchanted, priority, added } ("" = not chosen yet; an item id string = { item = it })
  if RULES then RULES.upgrade() end
  cfg.names = cfg.names or {}       -- network name -> nickname, shown in /assign
  -- The smelter's factory barrels (from its broadcast): feeds are filled for it and never storage,
  -- outs are emptied into storage like inputs
  cfg.smelterFeeds = cfg.smelterFeeds or {}
  cfg.smelterOuts = cfg.smelterOuts or {}
  -- Saved before the turtles were renamed (Oct 2026)
  if cfg.rigger and not cfg.weaver then cfg.weaver = cfg.rigger end
  cfg.rigger = nil
  if cfg.diggerBarrels and not cfg.canaryBarrels then cfg.canaryBarrels = cfg.diggerBarrels end
  cfg.diggerBarrels = nil
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
-- (or assigned as Drawers in /assign)
local function isDrawer(n)
  if (n:find("drawer") or n:find("functionalstorage")) ~= nil then return true end
  for _, d in ipairs(cfg.drawers or {}) do if d == n then return true end end
  return false
end

local function sortedSet(t)
  local out = {}
  for k, v in pairs(t or {}) do if v then out[#out + 1] = k end end
  table.sort(out)
  return out
end

local function listRemove(list, n)
  for i = #list, 1, -1 do if list[i] == n then table.remove(list, i) end end
end
local function listAdd(list, n)
  for _, x in ipairs(list) do if x == n then return end end
  list[#list + 1] = n
end

local smelterHold = {}   -- out barrels the smelter is counting (trying an ore): not emptied meanwhile
local function isSmelterFeed(n) return cfg.smelterFeeds and cfg.smelterFeeds[n] == true end
local function isSmelterOut(n) return cfg.smelterOuts and cfg.smelterOuts[n] == true end

-- Fluid tanks on the cable (a PneumaticCraft small tank, a Mekanism tank...). Some also have item slots
-- (PneumaticCraft tanks have bucket slots), so they can show up as inventories too: a tank is never
-- storage, only a fluid depot or the source for one.
local function hasFluid(n)
  if peripheral.hasType(n, "fluid_storage") then return true end
  for _, m in ipairs(peripheral.getMethods(n) or {}) do
    if m == "pullFluid" then return true end
  end
  return false
end

local function isTank(n)
  if not hasFluid(n) then return false end
  -- Something with item slots as well is a tank only if it says so by name (PneumaticCraft's small_tank):
  -- a Functional Storage drawer controller also offers fluids and must stay storage.
  if peripheral.hasType(n, "inventory") then return n:find("tank") ~= nil end
  return true
end

local function isSpecial(n)
  if isTank(n) then return true end
  if isSmelterFeed(n) or isSmelterOut(n) then return true end
  if n == cfg.output or n == cfg.weaver or n == cfg.pocketIn or n == cfg.pocketOut then return true end
  for _, d in ipairs(cfg.docks or {}) do if d == n then return true end end
  for _, d in ipairs(cfg.fuels) do if d == n then return true end end
  if cfg.depots and cfg.depots[n] ~= nil then return true end
  for _, d in ipairs(cfg.ignored or {}) do if d == n then return true end end
  if isMachine(n) then return true end
  for _, i in ipairs(cfg.inputs) do if i == n then return true end end
  return false
end

-- Assigned storage: every inventory has at most one job. Lists can hold any number, singles one.
local TYPES = {
  { key = "input",     label = "Input",          short = "Input",   tag = "INPUT",  col = colours.lime,
    about = "Emptied into storage every 2 s. Have as many as you like." },
  { key = "output",    label = "Output",         short = "Output",  tag = "OUTPUT", col = colours.cyan,
    about = "Where items you take from the screens go. Only one." },
  { key = "dock",      label = "Dock",           short = "Dock",    tag = "DOCK",   col = colours.yellow,
    about = "Turtle/machine dock: a few lava buckets kept in it (coal if there is no lava, plus its keep list), everything else taken." },
  { key = "fuel",      label = "Canary fuel",    short = "Fuel",    tag = "FUEL",   col = colours.orange,
    about = "Kept at one Canary refill (lava, coal blocks, coal...). One per Canary." },
  { key = "weaver",    label = "Weaver supply",  short = "Weaver",  tag = "WEAVER", col = colours.purple,
    about = "Filled with what Weaver asks for. Only one." },
  { key = "pocketIn",  label = "Pocket dump",    short = "P.dump",  tag = "P.DUMP", col = colours.pink,
    about = "The butler's $dump lands here and gets sorted. Only one." },
  { key = "pocketOut", label = "Pocket restock", short = "P.stock", tag = "P.STCK", col = colours.magenta,
    about = "The butler's top-ups wait here. Only one." },
  { key = "drawer",    label = "Drawers",        short = "Drawers", tag = "DRAWER", col = colours.lightBlue,
    about = "Bulk storage (a drawer controller): items it holds go there first. Still storage." },
  { key = "depot",     label = "Depot",          short = "Depot",   tag = "DEPOT",  col = colours.brown,
    about = "Kept full of one item from storage (buckets for a factory...). Not storage itself." },
  { key = "fluidDepot", label = "Fluid depot",   short = "Fluid",   tag = "FLUID",  col = colours.blue,
    about = "A tank kept full of one fluid, pulled from the other tanks on the cable. Not storage." },
  { key = "ignore",    label = "Ignore",         short = "Ignore",  tag = "IGNORE", col = colours.lightGrey,
    about = "Never touched or counted: storage pretends it isn't there." },
}
local TYPE_BY = {}
for _, t in ipairs(TYPES) do TYPE_BY[t.key] = t end
local LISTS   = { input = "inputs", dock = "docks", fuel = "fuels", drawer = "drawers", ignore = "ignored" }
local SINGLES = { output = "output", weaver = "weaver", pocketIn = "pocketIn", pocketOut = "pocketOut" }

local function typeOf(n)
  if cfg.fluidDepots and cfg.fluidDepots[n] ~= nil then return "fluidDepot" end
  if cfg.depots and cfg.depots[n] ~= nil then return "depot" end
  for key, field in pairs(SINGLES) do if cfg[field] == n then return key end end
  for key, field in pairs(LISTS) do
    for _, x in ipairs(cfg[field] or {}) do if x == n then return key end end
  end
end

local function unassign(n)
  if cfg.fluidDepots then cfg.fluidDepots[n] = nil end
  if cfg.depots then cfg.depots[n] = nil end
  for _, field in pairs(SINGLES) do if cfg[field] == n then cfg[field] = nil end end
  for _, field in pairs(LISTS) do if cfg[field] then listRemove(cfg[field], n) end end
  if cfg.dockKeep then cfg.dockKeep[n] = nil end
  if cfg.dockLink then cfg.dockLink[n] = nil end
  for _, b in pairs(cfg.canaryBarrels or {}) do
    if b.fuel == n then b.fuel = nil end
    if b.dump == n then b.dump = nil end
  end
end

-- Give n a job (taking any old one away). Returns the inventory it pushed out of a single job.
local function assign(n, key)
  unassign(n)
  if key == "fluidDepot" then cfg.fluidDepots = cfg.fluidDepots or {}; cfg.fluidDepots[n] = ""; return end
  if key == "depot" then cfg.depots = cfg.depots or {}; cfg.depots[n] = ""; return end
  local single = SINGLES[key]
  if single then
    local bumped = cfg[single]
    cfg[single] = n
    return bumped
  end
  cfg[LISTS[key]] = cfg[LISTS[key]] or {}
  listAdd(cfg[LISTS[key]], n)
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

local function tankNames()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do if isTank(n) then out[#out + 1] = n end end
  table.sort(out)
  return out
end

-- Where fluid comes from for a fluid depot: the other tanks on the cable and the fluid drawers of the
-- drawer network (the controller shows their fluids). Never an industrial machine or another depot.
local function fluidSources()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if hasFluid(n) and not (cfg.fluidDepots or {})[n] and not isMachine(n) and (isTank(n) or isDrawer(n)) then
      out[#out + 1] = n
    end
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

-- While /assign watches for a dropped item, sorting holds off: otherwise an input (or dock) would
-- have the test item sorted out of it before the second count, and the wrong chest would be picked.
local picking, workerBusy = false, false   -- workerBusy: a sorting pass is running (also for barrel probes)

-- Marker setup: put exactly one marker item in each special chest, press Enter.
-- A chest only counts if it holds that single item and nothing else. Markers ADD to what's
-- assigned (a single job like the output moves to the new chest); /assign changes or removes them.
local MARKERS = {
  { key = "input",  item = "minecraft:stick",       what = "1 stick",       label = "INPUT",        need = true, many = true },
  { key = "output", item = "minecraft:dirt",        what = "1 dirt",        label = "OUTPUT",       need = true },
  { key = "dump",   item = "minecraft:cobblestone", what = "1 cobblestone", label = "CANARY DUMP", many = true },
  { key = "fuel",   item = "minecraft:lava_bucket", what = "1 lava bucket", label = "CANARY FUEL", many = true },
  { key = "weaver", item = "minecraft:brick",       what = "1 brick",       label = "WEAVER SUPPLY" },
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
  print("MARKER SETUP (sorting paused)")
  print("One marker in each chest you want to assign:")
  for _, m in ipairs(MARKERS) do
    print(("  %-14s %s%s"):format(m.what, m.label, m.many and " (one in each)" or ""))
  end
  print("Adds to /assign; nothing gets removed.")
  while true do
    print("Press Enter when they're in.")
    read()
    local f, ok = markerScan(), true
    for _, m in ipairs(MARKERS) do
      local list = f[m.key] or {}
      local have = (m.key == "input" and #cfg.inputs > 0) or (m.key == "output" and cfg.output)
      if #list >= 1 and (m.many or #list == 1) then
        for _, n in ipairs(list) do print(("  %-14s %s"):format(m.label, n)) end
      elseif #list > 1 then
        printError(("  %s: %d chests have it. Keep it in one."):format(m.label, #list)); ok = false
      elseif m.need and not have then
        printError("  " .. m.label .. ": not found"); ok = false
      end
    end
    if ok then
      local types = { input = "input", output = "output", dump = "input", fuel = "fuel", weaver = "weaver",
        docks = "dock", pocketIn = "pocketIn", pocketOut = "pocketOut" }
      for _, m in ipairs(MARKERS) do
        for _, n in ipairs(f[m.key] or {}) do assign(n, types[m.key]) end
      end
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
local limits  = {}   -- drawer name -> { slot -> size in stacks } (see slotStacks)
local info    = {}   -- item key -> { label, max, tags, enchanted }
local items   = {}   -- sorted item summaries
local byName  = {}   -- item id -> total count (all variants)
local stats   = { used = 0, total = 0, kinds = 0, inv = 0 }
local overCapList = {}  -- items storage has enough of (sent to Canary via the mainframe)
local minerFuelLimit, weaverBill = nil, {}   -- heard over the network from Canary / Weaver

local function keyOf(it) return it.name .. (it.nbt and ("#" .. it.nbt) or "") end

RULES = dofile("storage_rules.lua")({ cfg = function() return cfg end, info = info, items = function() return items end })

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
  -- (drawer slot sizes are only re-read when an inventory's size changes, or by /tidy)
  for _, n in ipairs(storage) do
    fns[#fns + 1] = function()
      local old = sizes[n]
      sizes[n] = nil; scanInv(n)
      if sizes[n] ~= old then limits[n] = nil end
    end
  end
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
      if not (info[k] and info[k].tags) and not missing[k] then
        missing[k] = true
        missingFns[#missingFns + 1] = function()
          local d = call(n, "getItemDetail", slot)
          info[k] = RULES.fill({ label = d and d.displayName or prettyName(it.name), max = d and d.maxCount or 64 }, d or {})
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
  -- Anything Weaver's build still needs is kept until storage has enough of it
  local bill = weaverBill or {}
  for name, c in pairs(byName) do
    if c >= math.max(JUNK_CAP, bill[name] or 0) then overCap[#overCap + 1] = name end
  end
  overCapList = overCap -- broadcast; the mainframe's miner panel passes it to Canary
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

-- How big one drawer slot is, in STACKS (a 1x1 drawer = 32, upgrades multiply it). Functional
-- Storage reports a slot's limit for the item in it (32 lava buckets but 2,048 cobble in the same
-- drawer), so the size is kept in stacks: room for any item = stacks x that item's stack size.
-- 0 = never put anything there: a void upgrade's extra slot and creative drawers say "unlimited".
-- Cached in `limits`; cleared when an inventory changes size (drawers linked/unlinked) and by /tidy.
local VOID_LIMIT = 2 ^ 30
local function maxOf(key, n, slot)
  local i = info[key]
  if i and i.tags then return i.max end
  if n then
    local d = call(n, "getItemDetail", slot)
    if d then
      info[key] = RULES.fill({ label = d.displayName or prettyName(d.name), max = d.maxCount or 64 }, d)
      return info[key].max
    end
  end
  return 64
end

local function slotStacks(n, s)
  limits[n] = limits[n] or {}
  local c = limits[n][s]
  if not c then
    local l = call(n, "getItemLimit", s) or 0
    if l >= VOID_LIMIT then
      c = 0
    else
      local it = (cache[n] or {})[s]
      c = l / (it and maxOf(keyOf(it), n, s) or 64)
    end
    limits[n][s] = c
  end
  return c
end

-- How many of `key` (default: whatever is in it) one drawer slot holds
local function slotLimit(n, s, key)
  if not key then
    local it = (cache[n] or {})[s]
    key = it and keyOf(it)
  end
  return math.floor(slotStacks(n, s) * (key and maxOf(key) or 64))
end

-- Read every unknown slot size of a drawer inventory at once (one tick instead of one per slot)
local function readSizes(n)
  limits[n] = limits[n] or {}
  local fns = {}
  for s = 1, sizes[n] or 0 do
    if not limits[n][s] then fns[#fns + 1] = function() slotStacks(n, s) end end
  end
  if #fns > 0 then runBatched(fns) end
end

-- A drawer inventory's slots holding `key`, biggest drawer first (then fullest)
local function drawerSlotsFor(n, key)
  local slots = {}
  for s, it in pairs(cache[n] or {}) do if keyOf(it) == key then slots[#slots + 1] = s end end
  table.sort(slots, function(a, b)
    local la, lb = slotStacks(n, a), slotStacks(n, b)
    if la ~= lb then return la > lb end
    return cache[n][a].count > cache[n][b].count
  end)
  return slots
end

-- Empty drawers that turned an item away (locked to another item, compacting drawer...) are
-- skipped for a while so deposits don't keep knocking on them.
local refused = {}   -- "name#slot" -> os.clock() of the refusal
local REFUSE_FOR = 300
local function refusedNow(n, s)
  local t = refused[n .. "#" .. s]
  return t and os.clock() - t < REFUSE_FOR
end

-- A drawer inventory's empty slots for an item that will need about `want` stacks: the smallest
-- drawers big enough for it first (smallest first), then the bigger-is-better rest. Big drawers
-- stay free for big piles; one ring never lands in a 16k drawer.
local function emptyDrawerSlots(n, want)
  readSizes(n)
  want = want or 0
  local c, out = cache[n] or {}, {}
  for s = 1, sizes[n] or 0 do
    if not c[s] and slotStacks(n, s) > 0 and not refusedNow(n, s) then out[#out + 1] = s end
  end
  table.sort(out, function(a, b)
    local la, lb = slotStacks(n, a), slotStacks(n, b)
    local fa, fb = la >= want, lb >= want
    if fa ~= fb then return fa end
    if la ~= lb then
      if fa then return la < lb end   -- big enough: smallest first
      return la > lb                  -- too small: biggest first
    end
    return a < b
  end)
  return out
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

-- Where an item should go, best first (Tanis's order, Oct 14 2026):
--   1. drawers already holding it, with room     2. empty drawers (smallest that fits the pile)
--   3. barrels/chests already holding it         4. barrels/chests with a free slot
-- /tidy later hands the drawers to the items with the most stacks (see planDrawers).
-- Each target is { n = inventory, mode = "held" | "empty" | "barrel" }.
local function targetsFor(key)
  local tiers = { {}, {}, {}, {} }
  for _, n in ipairs(storage) do
    if isDrawer(n) then
      if holds(n, key) then table.insert(tiers[1], { n = n, mode = "held" }) end
      if freeSlots(n) > 0 then table.insert(tiers[2], { n = n, mode = "empty" }) end
    elseif holds(n, key) then
      table.insert(tiers[3], { n = n, mode = "barrel" })
    elseif freeSlots(n) > 0 then
      table.insert(tiers[4], { n = n, mode = "barrel" })
    end
  end
  local out = {}
  for _, t in ipairs(tiers) do
    for _, x in ipairs(t) do out[#out + 1] = x end
  end
  return out
end

-- Just the barrels/chests for an item: holding it first, then ones with a free slot
local function barrelTargets(key)
  local out = {}
  for _, t in ipairs(targetsFor(key)) do
    if t.mode == "barrel" then out[#out + 1] = t.n end
  end
  return out
end

---------------------------------------------------------------------------
-- Moving items
---------------------------------------------------------------------------
-- Put up to `count` items from (from, slot) into storage target t (from targetsFor). Drawers are
-- always aimed at an exact slot: a drawer controller left to choose drops items into any empty
-- drawer it likes (duplicate drawers).
--   held:  the drawer slots already holding the item, biggest first, skipping full ones
--   empty: empty drawer slots, the smallest that fits the item's whole pile first (see emptyDrawerSlots;
--          gives up after a few refusals: locked drawers)
local function moveInto(from, slot, count, t, key)
  local n = t.n
  if t.mode == "held" then
    local moved = 0
    for _, s in ipairs(drawerSlotsFor(n, key)) do
      if moved >= count then break end
      local it = cache[n][s]
      if not it or it.count < slotLimit(n, s, key) then
        moved = moved + (call(from, "pushItems", n, slot, count - moved, s) or 0)
      end
    end
    return moved
  elseif t.mode == "empty" then
    local moved, misses = 0, 0
    local name = key:gsub("#.*$", "")
    local want = ((byName[name] or 0) + count) / maxOf(key, from, slot)
    for _, s in ipairs(emptyDrawerSlots(n, want)) do
      if moved >= count or misses >= 3 then break end
      local m = call(from, "pushItems", n, slot, count - moved, s) or 0
      if m > 0 then
        moved = moved + m
        cache[n][s] = { name = key:gsub("#.*$", ""), count = m }   -- until the caller rescans
      else
        misses = misses + 1
        refused[n .. "#" .. s] = os.clock()
      end
    end
    return moved
  end
  return call(from, "pushItems", n, slot, count) or 0
end

-- Empty one input chest into storage (see targetsFor for the order).
-- skip: item ids left alone. leave: { [id] = n } leaves n of that item (a dock's Keeps) and takes the rest.
local function depositFrom(input, skip, leave)
  local inp = call(input, "list")
  if not inp or not next(inp) then return 0, 0 end
  local movedTotal, leftTotal = 0, 0
  local allow = {}
  if leave then for k, v in pairs(leave) do allow[k] = v end end
  for slot, it in pairs(inp) do
    local spare = it.count
    if allow[it.name] then
      local stay = math.min(spare, allow[it.name])
      allow[it.name] = allow[it.name] - stay
      spare = spare - stay
    end
    if not (skip and skip[it.name]) and spare > 0 then
      local left = spare
      local key = keyOf(it)
      maxOf(key, input, slot)   -- learn its stack size (and tags) before it lands in a drawer
      -- A depot that wins this item gets it first; when it's full the item goes to storage as usual
      local depot = RULES.winner(key, it.name)
      if depot and depot ~= input and peripheral.isPresent(depot) then
        local moved = call(input, "pushItems", depot, slot, left) or 0
        if moved > 0 then left = left - moved; movedTotal = movedTotal + moved end
      end
      for _, t in ipairs(left > 0 and targetsFor(key) or {}) do
        if left <= 0 then break end
        local moved = moveInto(input, slot, left, t, key)
        if moved > 0 then
          left = left - moved
          movedTotal = movedTotal + moved
          scanInv(t.n)
        end
      end
      leftTotal = leftTotal + math.max(left, 0)
    end
  end
  return movedTotal, leftTotal
end

-- An empty barrel slot to stage a move through
local function emptyBarrelSlot()
  for _, b in ipairs(storage) do
    if not isDrawer(b) and freeSlots(b) > 0 then
      for j = 1, sizes[b] do if not cache[b][j] then return b, j end end
    end
  end
end

-- Long pure-Lua loops must yield now and then, or CraftOS kills them ("Too long without yielding")
local function breathe()
  os.queueEvent("storage_breathe")
  os.pullEvent("storage_breathe")
end

---------------------------------------------------------------------------
-- /tidy: who gets the drawers
---------------------------------------------------------------------------
-- Items are ranked by STACKS, not count: 100 lava buckets = 100 stacks beats 101 cobble (< 2).
-- The biggest drawers go to the biggest piles: walking the items from most stacks to fewest, each
-- takes the biggest drawers still free until its whole pile fits (where two drawers are the same
-- size it keeps the one it's already in, so nothing moves for nothing). When the drawers run out,
-- the smallest piles go to the barrels.
-- Returns the plan in rank order: { { key, name, stacks, slots = { {n, s, cap, key} ... } } ... }
-- and every usable drawer slot.
local function planDrawers()
  local slots, totals, keys, names, where = {}, {}, {}, {}, {}
  for _, n in ipairs(storage) do
    for s, it in pairs(cache[n] or {}) do
      local k = keyOf(it)
      if not totals[k] then totals[k] = 0; keys[#keys + 1] = k; names[k] = it.name; where[k] = { n, s } end
      totals[k] = totals[k] + it.count
    end
    if isDrawer(n) then
      for s = 1, sizes[n] or 0 do
        local cap = slotStacks(n, s)
        local it = cache[n][s]
        -- an empty drawer that turned something away is locked to another item: leave it out
        if cap > 0 and (it or not refusedNow(n, s)) then
          slots[#slots + 1] = { n = n, s = s, cap = cap, key = it and keyOf(it) }
        end
      end
    end
  end
  local stacks = {}
  for _, k in ipairs(keys) do stacks[k] = totals[k] / maxOf(k, where[k][1], where[k][2]) end
  table.sort(keys, function(a, b)
    if stacks[a] ~= stacks[b] then return stacks[a] > stacks[b] end
    return a < b
  end)
  local rank = {}
  for i, k in ipairs(keys) do rank[k] = i end
  -- Size classes, biggest first. In each: slots by holder, empty slots, other items' slots
  -- (lowest-ranked holder first)
  local byCap, caps = {}, {}
  for _, sl in ipairs(slots) do
    local c = byCap[sl.cap]
    if not c then c = { own = {}, empty = {}, other = {}, left = 0 }; byCap[sl.cap] = c; caps[#caps + 1] = sl.cap end
    c.left = c.left + 1
    if sl.key then
      c.own[sl.key] = c.own[sl.key] or {}
      table.insert(c.own[sl.key], sl)
      table.insert(c.other, sl)
    else
      table.insert(c.empty, sl)
    end
  end
  table.sort(caps, function(a, b) return a > b end)
  for _, cap in ipairs(caps) do
    table.sort(byCap[cap].other, function(a, b) return rank[a.key] > rank[b.key] end)
  end
  local claimed = {}
  local function pop(list)
    while list and #list > 0 do
      local sl = table.remove(list)
      if not claimed[sl] then return sl end
    end
  end
  -- `other` is popped from the end, so reverse it: lowest rank at the end
  for _, cap in ipairs(caps) do
    local o, r = byCap[cap].other, {}
    for i = #o, 1, -1 do r[#r + 1] = o[i] end
    byCap[cap].other = r
  end
  local plan, ci = {}, 1
  for i, k in ipairs(keys) do
    if i % 100 == 0 then breathe() end
    local need, mine = stacks[k], {}
    while need > 0 do
      while ci <= #caps and byCap[caps[ci]].left <= 0 do ci = ci + 1 end
      if ci > #caps then break end
      local c = byCap[caps[ci]]
      local sl = pop(c.own[k]) or pop(c.empty) or pop(c.other)
      if not sl then c.left = 0 else
        claimed[sl] = true
        c.left = c.left - 1
        mine[#mine + 1] = sl
        need = need - sl.cap
      end
    end
    plan[#plan + 1] = { key = k, name = names[k], stacks = stacks[k], slots = mine }
  end
  return plan, slots
end

-- Keep the cache in step with our own moves (re-listing a big controller after every move is slow)
local function bump(n, s, tmpl, delta)
  local c = cache[n][s]
  if c then
    c.count = c.count + delta
    if c.count <= 0 then cache[n][s] = nil end
  elseif delta > 0 then
    cache[n][s] = { name = tmpl.name, nbt = tmpl.nbt, count = delta }
  end
end

-- Move up to `count` from (fromN, fromS) to (toN, toS); toS nil = anywhere in toN (a barrel).
-- One stack per call. Drawer to drawer on the same controller goes direct; if that's refused,
-- it goes through an empty barrel slot instead.
local noSelfMove = false
local function transfer(fromN, fromS, toN, toS, count)
  local it = cache[fromN][fromS]
  if not it then return 0 end
  local tmpl = { name = it.name, nbt = it.nbt }
  local moved = 0
  while moved < count and cache[fromN][fromS] do
    if fromN == toN and noSelfMove then
      local b, bs = emptyBarrelSlot()
      if not b then break end
      local out = call(b, "pullItems", fromN, fromS, count - moved, bs) or 0
      if out <= 0 then break end
      bump(fromN, fromS, tmpl, -out)
      bump(b, bs, tmpl, out)
      local back = call(b, "pushItems", toN, bs, out, toS) or 0
      bump(b, bs, tmpl, -back)
      bump(toN, toS, tmpl, back)
      moved = moved + back
      if back < out then break end      -- the rest stays safely in the barrel
    else
      local m, err = call(fromN, "pushItems", toN, fromS, count - moved, toS)
      if m == nil and fromN == toN then
        noSelfMove = true               -- this server won't move within one inventory: stage it
      else
        m = m or 0
        if m <= 0 then break end
        bump(fromN, fromS, tmpl, -m)
        if toS then bump(toN, toS, tmpl, m) end
        moved = moved + m
      end
    end
  end
  if not toS and moved > 0 then scanInv(toN) end
  return moved
end

-- Carry out planDrawers. progress(text) now and then. Returns
-- { moved = stacks moved, evicted = {id=n}, blocked = drawers left holding the wrong item,
--   locked = drawers that turned their new item away, waiting = kinds still in barrels }
local function rebalanceDrawers(progress)
  local plan, all = planDrawers()
  local res = { moved = 0, evicted = {}, blocked = 0, locked = 0, waiting = 0 }
  local function id(sl) return sl.n .. "#" .. sl.s end
  local target, slotsOf, locked = {}, {}, {}
  for _, p in ipairs(plan) do
    if #p.slots > 0 then slotsOf[p.key] = p.slots end
    for _, sl in ipairs(p.slots) do target[id(sl)] = p.key end
  end
  local function cur(sl) return cache[sl.n][sl.s] end
  local function room(sl, key)
    local c = cur(sl)
    if c and keyOf(c) ~= key then return 0 end
    if not c and locked[id(sl)] then return 0 end
    return slotLimit(sl.n, sl.s, key) - (c and c.count or 0)
  end
  local function count(sl) local c = cur(sl); return c and c.count or 0 end
  local function tally(sl, key, m)
    res.moved = res.moved + math.ceil(m / maxOf(key))
  end
  -- Into one of key's own drawers (sl); marks it locked if it turns the item away while empty
  local function into(fromN, fromS, sl, key, n)
    local wasEmpty = cur(sl) == nil
    local m = transfer(fromN, fromS, sl.n, sl.s, n)
    if m == 0 and wasEmpty then
      locked[id(sl)] = true
      refused[id(sl)] = os.clock()
      res.locked = res.locked + 1
    end
    if m > 0 then tally(sl, key, m) end
    return m
  end
  -- Contents of sl (not its own item) into their item's drawers that have room
  local function relocate(sl)
    local c = cur(sl); if not c then return 0 end
    local key, moved = keyOf(c), 0
    for _, t in ipairs(slotsOf[key] or {}) do
      if not cur(sl) then break end
      if t ~= sl then
        local r = room(t, key)
        if r > 0 then moved = moved + into(sl.n, sl.s, t, key, math.min(r, count(sl))) end
      end
    end
    return moved
  end
  local function hasRoom(key)
    for _, t in ipairs(slotsOf[key] or {}) do if room(t, key) > 0 then return true end end
    return false
  end
  local function toBarrels(sl)
    local c = cur(sl); if not c then return 0 end
    local key, name, moved = keyOf(c), c.name, 0
    for _, b in ipairs(barrelTargets(key)) do
      if not cur(sl) then break end
      moved = moved + transfer(sl.n, sl.s, b, nil, count(sl))
    end
    if moved > 0 then
      res.evicted[name] = (res.evicted[name] or 0) + moved
      tally(sl, key, moved)
    end
    return moved
  end
  -- Where each item sits, rebuilt every pass (entries are re-checked before use)
  local inDrawers, inBarrels = {}, {}
  local function index()
    inDrawers, inBarrels = {}, {}
    for _, sl in ipairs(all) do
      local c = cur(sl)
      if c then
        local k = keyOf(c)
        inDrawers[k] = inDrawers[k] or {}
        table.insert(inDrawers[k], sl)
      end
    end
    for _, b in ipairs(storage) do
      if not isDrawer(b) then
        local seen = {}
        for _, it in pairs(cache[b] or {}) do
          local k = keyOf(it)
          if not seen[k] then
            seen[k] = true
            inBarrels[k] = inBarrels[k] or {}
            table.insert(inBarrels[k], b)
          end
        end
      end
    end
  end
  -- Fill sl with its item from wherever it sits outside its own drawers
  local function gather(sl, key)
    local moved = 0
    for _, o in ipairs(inDrawers[key] or {}) do
      if room(sl, key) <= 0 then return moved end
      local c = cur(o)
      if o ~= sl and c and keyOf(c) == key and target[id(o)] ~= key then
        moved = moved + into(o.n, o.s, sl, key, math.min(room(sl, key), c.count))
        if locked[id(sl)] then return moved end
      end
    end
    for _, b in ipairs(inBarrels[key] or {}) do
      if holds(b, key) then
        for bs, it in pairs(cache[b]) do
          local r = room(sl, key)
          if r <= 0 then return moved end
          if keyOf(it) == key then
            moved = moved + into(b, bs, sl, key, math.min(r, it.count))
            if locked[id(sl)] then return moved end
          end
        end
      end
    end
    return moved
  end

  for pass = 1, 60 do
    local before = res.moved
    index()
    for i, sl in ipairs(all) do
      if i % 50 == 0 then
        breathe()
        if progress then progress(("Pass %d: drawer %d/%d, %d stacks moved"):format(pass, i, #all, res.moved)) end
      end
      local want, c = target[id(sl)], cur(sl)
      if c and keyOf(c) ~= want then
        local key = keyOf(c)
        relocate(sl)
        -- Its own drawers are all full (or it got none): the rest goes to the barrels,
        -- but only when this drawer belongs to another item
        if cur(sl) and want and not hasRoom(key) then toBarrels(sl) end
      end
      if want and room(sl, want) > 0 then gather(sl, want) end
    end
    if res.moved == before then
      -- Stuck: two items each waiting for the other's drawer. Park one drawer's contents in a
      -- spare empty drawer or the barrels, and go round again.
      local parked = false
      for _, sl in ipairs(all) do
        local want, c = target[id(sl)], cur(sl)
        if want and c and keyOf(c) ~= want then
          local key = keyOf(c)
          for _, sp in ipairs(all) do
            if not cur(sl) then break end
            if not target[id(sp)] and not cur(sp) and not locked[id(sp)] then
              if into(sl.n, sl.s, sp, key, count(sl)) > 0 then parked = true end
            end
          end
          if cur(sl) and toBarrels(sl) > 0 then parked = true end
          if parked then break end
        end
      end
      if not parked then break end
    end
  end
  for _, sl in ipairs(all) do
    local want, c = target[id(sl)], cur(sl)
    if want and c and keyOf(c) ~= want then res.blocked = res.blocked + 1 end
  end
  -- What's still loose in barrels for want of a drawer
  local loose = {}
  for _, b in ipairs(storage) do
    if not isDrawer(b) then
      scanInv(b)
      for _, it in pairs(cache[b] or {}) do loose[keyOf(it)] = true end
    end
  end
  for _ in pairs(loose) do res.waiting = res.waiting + 1 end
  return res
end

-- Turtle docks: storage takes everything except fuel, which stays for the turtle (storage_docks.lua, set up below)
local DOCKS

local inputStuck = false -- items in an input that storage had no room for
local function deposit()
  local moved, stuck = 0, false
  for _, input in ipairs(cfg.inputs) do
    local m, left = depositFrom(input)
    moved = moved + m
    if left > 0 then stuck = true end
  end
  -- The smelter's factory out barrels: the dust goes into storage like any input
  for _, o in ipairs(sortedSet(cfg.smelterOuts)) do
    if peripheral.isPresent(o) and not smelterHold[o] then
      local m, left = depositFrom(o)
      moved = moved + m
      if left > 0 then stuck = true end
    end
  end
  for _, d in ipairs(cfg.docks or {}) do
    -- Its Keeps (the neural lab's matrices, Woodpecker's saplings...) stay up to their count;
    -- anything over that is taken like the rest, so a turtle unloading spares can't fill the dock.
    local keep = cfg.dockKeep and cfg.dockKeep[d]
    local m, left = depositFrom(d, DOCKS.KEEP, keep)
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

-- Emptiest Canary fuel barrel, in fuel units (see topUpFuel)
local fuelUnits = 0
DOCKS = dofile("storage_docks.lua")({
  cfg = function() return cfg end, byName = function() return byName end, call = call, retrieve = retrieve,
  saveCfg = saveCfg, env = require("envfile"),
})

-- Keep each turtle dock stocked with lava buckets (coal only when there is no lava), best fuel in slot 1
local function topUpDocks()
  local changed = false
  for _, d in ipairs(cfg.docks or {}) do
    local list = call(d, "list")
    if list then
      if DOCKS.stock(d, list) then changed = true; list = call(d, "list") or list end
      if DOCKS.order(d, list) then changed = true end
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

-- Keep every depot full of what its rule wins, as far as storage has it. Anything else in a depot is left alone.
local function topUpDepots()
  local changed = false
  local won = RULES.winners()
  local names = {}
  for d in pairs(won) do names[#names + 1] = d end
  table.sort(names)
  for _, d in ipairs(names) do
    if peripheral.isPresent(d) then
      local list = call(d, "list")
      local size = call(d, "size") or 0
      if list then
        local used, room = 0, false
        for _, it in pairs(list) do
          used = used + 1
          local max = (info[keyOf(it)] and info[keyOf(it)].max) or 64
          if it.count < max then room = true end
        end
        if used < size or room then
          for _, e in ipairs(won[d]) do
            local moved, full = retrieve(e.key, e.count, d)
            if moved > 0 then changed = true; byName[e.name] = byName[e.name] - moved end
            if full then break end
          end
        end
      end
    end
  end
  return changed
end

-- Keep every fluid depot full of its fluid, pulled from the other tanks on the cable (never from another depot).
local function topUpFluidDepots()
  local changed = false
  for d, fluid in pairs(cfg.fluidDepots or {}) do
    if fluid ~= "" and peripheral.isPresent(d) then
      for _, src in ipairs(fluidSources()) do
        if src ~= d then
          local has = 0
          for _, f in pairs(call(src, "tanks") or {}) do
            if f.name == fluid then has = has + (f.amount or 0) end
          end
          if has > 0 then
            local moved = call(d, "pullFluid", src, nil, fluid) or 0
            if moved > 0 then changed = true else break end   -- nothing moved: the depot is full
          end
        end
      end
    end
  end
  return changed
end

-- Fuel kept in each Canary fuel barrel: one stack of coal's worth (never more than a Canary's tank)
local function canaryFuelTarget()
  return math.min(CANARY_FUEL, minerFuelLimit or REFILL)
end

-- Keep every Canary fuel barrel at (as close as possible to) one stack of coal's worth, and hand
-- anything over that back to storage so the smelter and the neural lab get it.
-- fuelUnits = the emptiest barrel, for the screen and the mainframe's "running dry" alert.
local function topUpFuel()
  if #cfg.fuels == 0 then return false end
  local target = canaryFuelTarget()
  local value = {}
  for _, fv in ipairs(FUEL_VALUES) do value[fv[1]] = fv[2] end
  local changed, lowest = false, nil
  for _, barrel in ipairs(cfg.fuels) do
    local list = call(barrel, "list")
    if list then
      local have = 0
      for _, it in pairs(list) do have = have + (value[it.name] or 0) * it.count end
      -- Too much in there (filled to a whole tank by an older version): take the extra back
      if have > target then
        for slot, it in pairs(list) do
          local v = value[it.name]
          local n = v and math.min(it.count, math.floor((have - target) / v)) or 0
          if n > 0 then
            local key, moved = keyOf(it), 0
            for _, t in ipairs(targetsFor(key)) do
              if moved >= n then break end
              local m = moveInto(barrel, slot, n - moved, t, key)
              if m > 0 then moved = moved + m; scanInv(t.n) end
            end
            if moved > 0 then
              have = have - moved * v
              byName[it.name] = (byName[it.name] or 0) + moved
              changed = true
            end
          end
        end
      end
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
  maxOf(d.name, fz, slot)
  for _, t in ipairs(targetsFor(d.name)) do
    if moved >= d.count then break end
    local m = moveInto(fz, slot, d.count - moved, t, d.name)
    if m > 0 then moved = moved + m; scanInv(t.n) end
  end
  return moved
end

-- ops: { op = "store", fz, slot } or { op = "fill", fz, slot, item, count }. Returns moved per op.
local function runSmeltOps(ops)
  local results = {}
  for i, o in ipairs(ops or {}) do
    local moved = 0
    if type(o) == "table" and type(o.fz) == "string" and (isFurnace(o.fz) or isSmelterFeed(o.fz)) then
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

-- Fill Weaver's supply barrel with what he asked for (items + fuel units).
local lastWeaverseq = nil
local weaverReq = nil            -- latest "need" message from Weaver (set by the network loop)
local function replyWeaver(msg)
  if rednet.isOpen() then rednet.broadcast(msg, "tanis-rigger") end
end
local function supplyWeaver()
  local req = weaverReq
  if not req or req.seq == lastWeaverseq then return false end
  lastWeaverseq = req.seq
  local got, missing = {}, {}
  if not cfg.weaver then
    replyWeaver({ type = "supplied", seq = req.seq, got = got, missing = req.items or {} })
    return false
  end
  depositFrom(cfg.weaver)  -- take back whatever he handed in, then load the next batch
  buildItems()
  for _, e in ipairs(req.items or {}) do
    local name, want = e[1], e[2]
    local moved = retrieve(name, want, cfg.weaver)
    if moved > 0 then got[name] = moved end
    if moved < want then missing[#missing + 1] = { name, want - moved } end
  end
  local units = tonumber(req.fuel) or 0
  for _, fv in ipairs(FUEL_VALUES) do
    local name, v = fv[1], fv[2]
    local n = math.floor(units / v)
    if n > 0 and (byName[name] or 0) > 0 then
      local moved = retrieve(name, math.min(n, byName[name]), cfg.weaver)
      units = units - moved * v
      if moved > 0 then got[name] = (got[name] or 0) + moved end
    end
  end
  if units >= 80 then missing[#missing + 1] = { "fuel", units } end
  replyWeaver({ type = "supplied", seq = req.seq, got = got, missing = missing })
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
  { "/assign",   "inputs, output, docks, fuel...: add/edit/delete" },
  { "/setup",    "assign chests with marker items" },
  { "/rescan",   "re-read every chest now" },
  { "/drawers",  "what storage sees in the drawers" },
  { "/tidy",     "biggest piles into biggest drawers" },
  { "/fuelinfo", "Canary fuel barrels and fuel stock" },
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
  if not cfg.output then say(v, "No output chest yet: /assign on the computer", C.warn); return end
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
  if #cfg.fuels > 0 then right = ("Fuel %d%%  "):format(math.floor(fuelUnits / canaryFuelTarget() * 100)) .. right end
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
    fuelTarget = #cfg.fuels > 0 and canaryFuelTarget() or nil,
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
  if not paused and not picking and (#jobs > 0 or (weaverReq and weaverReq.seq ~= lastWeaverseq)
    or (pocketReq and pocketReq.seq ~= lastPocketSeq)) then return end
  local t = os.startTimer(TICK)
  while true do
    local e, id = os.pullEvent()
    if (e == "timer" and id == t) or e == "storage_work" then return end
  end
end

-- workerBusy (declared with picking): a sorting pass is running (a barrel probe waits for it to finish)

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
      if topUpDepots() then buildItems() end
      topUpFluidDepots()
      if supplyWeaver() then buildItems() end
      if fillPocket() then buildItems() end
      if #jobs > 0 then
        while #jobs > 0 do
          local j = table.remove(jobs, 1)
          local neural = j.kind == "neural"
          local results = neural and runNeuralOps(j.ops) or runSmeltOps(j.ops)
          if rednet.isOpen() then
            local counts
            if neural and type(j.want) == "table" then
              counts = {}
              for _, id in ipairs(j.want) do if type(id) == "string" then counts[id] = byName[id] or 0 end end
            end
            rednet.send(j.from, { type = neural and "neural_done" or "smelt_done", id = j.id, results = results, counts = counts }, BASE)
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
-- Canary barrel probe: a Canary takes 1 item from its fuel barrel and drops it in its dump barrel
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

local function registerCanaryBarrels(id, fuel, dump)
  cfg.canaryBarrels = cfg.canaryBarrels or {}
  if fuel then
    listRemove(cfg.inputs, fuel); listRemove(cfg.docks or {}, fuel)
    listAdd(cfg.fuels, fuel)
  end
  if dump and dump ~= fuel then
    listRemove(cfg.fuels, dump); listRemove(cfg.docks or {}, dump)
    listAdd(cfg.inputs, dump)
  end
  cfg.canaryBarrels[tostring(id)] = { fuel = fuel, dump = dump }
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
    registerCanaryBarrels(from, fuel, dump)
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
    if probe and os.clock() > probe.untilT then probe = nil; paused = false end -- Canary never finished
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
        weaverBill = type(msg.bill) == "table" and msg.bill or weaverBill
      elseif proto == "tanis-rigger" and msg.type == "need" then
        weaverReq = msg
        os.queueEvent("storage_work")
      elseif proto == BASE and msg.type == "pocket_fill" and msg.seq then
        pocketReq = msg
        os.queueEvent("storage_work")
      elseif proto == BASE and msg.type == "presence" then
        local was = isLocked()
        presence = { known = msg.known == true, home = msg.home, autoLock = msg.autoLock ~= false, at = os.clock() }
        if isLocked() ~= was then os.queueEvent("storage_work") end   -- redraw now, not next tick
      elseif proto == BASE and msg.type == "smelter" and type(msg.factories) == "table" then
        -- The smelter's factory barrels: keep our copy (saved, so a reboot without the smelter keeps them safe)
        local feeds, outs = {}, {}
        smelterHold = {}
        for _, f in ipairs(msg.factories) do
          if type(f) == "table" and type(f.feed) == "string" and type(f.out) == "string" and f.feed ~= f.out then
            feeds[f.feed], outs[f.out] = true, true
            if f.hold == true then smelterHold[f.out] = true end
          end
        end
        local same = true
        for k in pairs(feeds) do if not cfg.smelterFeeds[k] then same = false end end
        for k in pairs(cfg.smelterFeeds) do if not feeds[k] then same = false end end
        for k in pairs(outs) do if not cfg.smelterOuts[k] then same = false end end
        for k in pairs(cfg.smelterOuts) do if not outs[k] then same = false end end
        if not same then
          cfg.smelterFeeds, cfg.smelterOuts = feeds, outs
          -- A barrel that becomes a factory barrel loses any job it had here
          for k in pairs(feeds) do unassign(k) end
          for k in pairs(outs) do unassign(k) end
          saveCfg()
          refreshStorageList()
          os.queueEvent("storage_work")
        end
      elseif proto == BASE and msg.type == "dock_report" and msg.id == from then
        rednet.send(from, DOCKS.report(msg), BASE)
      elseif proto == BASE and msg.type == "smelt_ops" and type(msg.ops) == "table" then
        jobs[#jobs + 1] = { from = from, id = msg.id, ops = msg.ops }
        os.queueEvent("storage_work")
      elseif proto == BASE and msg.type == "neural_ops" and type(msg.ops) == "table" then
        if #msg.ops == 0 then
          -- Just asking for counts: answer straight away, no need to wait for the worker
          local counts = {}
          for _, id in ipairs(type(msg.want) == "table" and msg.want or {}) do
            if type(id) == "string" then counts[id] = byName[id] or 0 end
          end
          rednet.send(from, { type = "neural_done", id = msg.id, results = {}, counts = counts }, BASE)
        else
          jobs[#jobs + 1] = { from = from, id = msg.id, ops = msg.ops, want = msg.want, kind = "neural" }
          os.queueEvent("storage_work")
        end
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

-- A dock's keep list ("<item> <count>" lines besides its coal, e.g. the neural lab's matrices).
-- Edits `keep` ({ [item id] = count }) in place.
local function editDockKeep(keep)
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
end

---------------------------------------------------------------------------
-- /assign: which inventory on the cable does what (the screen lives in assignui.lua, shared with
-- the Nether Foreman). Everything that isn't on the list is storage.
---------------------------------------------------------------------------
local AUI = dofile("assignui.lua")

local function assignScreen()
  AUI.run({
    title = "ASSIGNED STORAGE",
    hint = "Click one to change it. The rest is storage.",
    emptyText = "Nothing assigned yet. + Add, or /setup (markers).",
    types = TYPES, names = cfg.names, call = call,
    rules = RULES,
    typeOf = typeOf, assign = assign, unassign = unassign,
    inventories = function()
      local out, seen = inventories(), {}
      for _, n in ipairs(out) do seen[n] = true end
      for _, n in ipairs(tankNames()) do if not seen[n] then out[#out + 1] = n end end
      return out
    end,
    describe = function(n)
      if not isTank(n) then return nil end
      local tanks = call(n, "tanks") or {}
      local best, kinds, total = nil, 0, 0
      for _, t in pairs(tanks) do
        if t.name and (t.amount or 0) > 0 then
          kinds, total = kinds + 1, total + t.amount
          if not best or t.amount > best.amount then best = t end
        end
      end
      return { count = total, size = 0, text = best
        and ((total >= 1000 and (math.floor(total / 100) / 10 .. " B") or (total .. " mB")) .. " " .. prettyName(best.name)
          .. (kinds > 1 and (" +" .. (kinds - 1) .. " more") or ""))
        or "empty tank" }
    end,
    assignedNames = function()
      local out = {}
      for _, field in pairs(SINGLES) do if cfg[field] then out[#out + 1] = cfg[field] end end
      for _, field in pairs(LISTS) do for _, n in ipairs(cfg[field] or {}) do out[#out + 1] = n end end
      for n in pairs(cfg.depots or {}) do out[#out + 1] = n end
      for n in pairs(cfg.fluidDepots or {}) do out[#out + 1] = n end
      return out
    end,
    depots = {
      { key = "depot", kind = "Depot", title = "DEPOT", what = "item", tank = false,
        about = "keeps a container topped up with one item",
        items = function(n)
          local seen, out = {}, {}
          for _, it in ipairs(items) do
            if not seen[it.name] then
              seen[it.name] = #out + 1
              out[#out + 1] = { name = it.name, label = it.label, count = it.count }
            else
              out[seen[it.name]].count = out[seen[it.name]].count + it.count
            end
          end
          -- what the container holds now may not be in storage at all
          for _, it in pairs(call(n, "list") or {}) do
            if not seen[it.name] then
              seen[it.name] = #out + 1
              out[#out + 1] = { name = it.name, label = prettyName(it.name), count = 0 }
            end
          end
          table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
          return out
        end,
        get = function(n) local d = RULES.normalize(cfg.depots and cfg.depots[n]); return d and d.item or nil end,
        set = function(n, item)
          local r = RULES.normalize(cfg.depots[n]) or { priority = 0 }
          r.item, r.added = item, r.added or RULES.nextAdded()
          cfg.depots[n] = r
        end,
      },
      { key = "fluidDepot", kind = "Fluid depot", title = "FLUID DEPOT", what = "fluid", tank = true,
        about = "keeps a tank full of one fluid from the other tanks",
        owns = isTank,
        diagnose = function()   -- shown when no tank is found: what the cable has that looks like one
          local out = {}
          for _, n in ipairs(peripheral.getNames()) do
            if n:find("^pneumaticcraft:small_tank") then
              out[#out + 1] = n
              out[#out + 1] = "  type: " .. table.concat({ peripheral.getType(n) }, ",")
              out[#out + 1] = "  methods: " .. table.concat(peripheral.getMethods(n) or {}, " ")
            end
          end
          if #out == 0 then out[1] = "no pneumaticcraft:small_tank on the cable" end
          return out
        end,
        items = function(n)
          local total, out = {}, {}
          for _, t in ipairs(fluidSources()) do
            for _, f in pairs(call(t, "tanks") or {}) do
              if f.name and (f.amount or 0) > 0 then total[f.name] = (total[f.name] or 0) + f.amount end
            end
          end
          for _, f in pairs(call(n, "tanks") or {}) do
            if f.name and f.name ~= "minecraft:empty" and not total[f.name] then total[f.name] = 0 end
          end
          for name, amount in pairs(total) do out[#out + 1] = { name = name, label = prettyName(name), count = amount } end
          table.sort(out, function(a, b) return a.label:lower() < b.label:lower() end)
          return out
        end,
        get = function(n) local d = cfg.fluidDepots and cfg.fluidDepots[n]; return d ~= "" and d or nil end,
        set = function(n, fluid) cfg.fluidDepots[n] = fluid end,
      },
    },
    candidate = function(n) return not isMachine(n) and not isSmelterFeed(n) and not isSmelterOut(n) end,
    auto = function(n) if isDrawer(n) then return "drawer" end end,   -- drawers found by their name
    single = function(key) return SINGLES[key] and cfg[SINGLES[key]] or nil end,
    defaultKey = function() return not cfg.output and "output" or "input" end,
    problem = function()
      if not cfg.output then return "No OUTPUT yet: taken items have nowhere to go." end
      if #cfg.inputs == 0 then return "No INPUT yet: nothing gets sorted in." end
    end,
    warn = function(e, d)
      if e.key ~= e.orig and not e.orig and (d.count or 0) > 0 and e.key ~= "drawer" then
        return e.key == "input" and ("Its %d items get sorted into storage."):format(d.count)
          or ("Its %d items stop counting as storage."):format(d.count)
      end
    end,
    extra = {
      key = "dock", plain = true,
      init = function(n)
        local keep = {}
        for k, v in pairs((cfg.dockKeep or {})[n] or {}) do keep[k] = v end
        local link = cfg.dockLink and cfg.dockLink[n]
        return { keep = keep, link = link and { label = link.label, x = link.x, y = link.y, z = link.z } or nil }
      end,
      show = function(st)
        local parts = {}
        for name, c in pairs(st.keep) do parts[#parts + 1] = c .. " " .. name:gsub("^[^:]+:", "") end
        table.sort(parts)
        return "Dock", (st.link and st.link.label or "no turtle") .. (#parts > 0 and (", keeps " .. table.concat(parts, ", ")) or "")
      end,
      click = function(n, st)
        print("Dock " .. n)
        st.link = DOCKS.pick(n, st.link)
        editDockKeep(st.keep)
      end,
      save = function(n, st)
        cfg.dockKeep = cfg.dockKeep or {}
        cfg.dockKeep[n] = next(st.keep) and st.keep or nil
        cfg.dockLink = cfg.dockLink or {}
        cfg.dockLink[n] = st.link
      end,
    },
    hold = function() picking = true; while workerBusy do os.sleep(0.2) end end,
    release = function() picking = false; os.queueEvent("storage_work") end,
    beforeSave = function() while workerBusy do os.sleep(0.1) end end,
    afterSave = function() saveCfg(); scanAll(); buildItems() end,
    itemTotals = itemTotals,
  })
end

local ALIASES = { ["/addinput"] = "/assign", ["/fuel"] = "/assign", ["/dock"] = "/assign",
  ["/pocket"] = "/assign", ["/inputs"] = "/assign" }   -- the old commands: all of that lives in /assign now

function runCommand(cmd)
  cmd = cmd:lower():match("^%s*(%S+)") or ""
  cmd = ALIASES[cmd] or cmd
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
      -- Sorting waits while the drawers are reshuffled
      picking = true
      while workerBusy do os.sleep(0.2) end
      print("Rescanning (and re-reading drawer sizes)...")
      limits = {}
      scanAll()
      for _, n in ipairs(storage) do if isDrawer(n) then readSizes(n) end end
      buildItems()
      print("Biggest piles into the biggest drawers. This can take a")
      print("few minutes the first time; sorting waits until it's done.")
      local _, py = term.getCursorPos()
      local res = rebalanceDrawers(function(text)
        term.setCursorPos(1, py); term.clearLine(); write(text)
      end)
      print()
      picking = false
      scanAll()
      buildItems()
      os.queueEvent("storage_work")
      print(("Moved %d stacks."):format(res.moved))
      local order, total = {}, 0
      for name, c in pairs(res.evicted) do order[#order + 1] = name; total = total + c end
      if total > 0 then
        table.sort(order, function(x, y) return res.evicted[x] > res.evicted[y] end)
        print(("Moved %d items out to barrels (smallest piles):"):format(total))
        for i = 1, math.min(5, #order) do print(("  %6d %s"):format(res.evicted[order[i]], order[i])) end
        if #order > 5 then print(("  ...and %d more kinds"):format(#order - 5)) end
      end
      if res.moved == 0 then print("Nothing to move: the drawers already hold the biggest piles.") end
      if res.locked > 0 then
        printError(("%d drawer(s) are locked to another item: unlock them and /tidy again."):format(res.locked))
      end
      if res.blocked > 0 then
        printError(("%d drawer(s) still hold the wrong item: barrels too full to swap. /tidy again after freeing space."):format(res.blocked))
      end
      if res.waiting > 0 then
        print(("%d kinds still in barrels (no drawer left for them)."):format(res.waiting))
      end
      waitEnter()
    elseif found == "/fuelinfo" then
      print("Rescanning..."); scanAll(); buildItems()
      local target = canaryFuelTarget()
      print(("Each Canary fuel barrel is kept at %d fuel"):format(target))
      print("(one stack of coal's worth; extra goes back to storage).")
      if not minerFuelLimit then
        printError("Storage hasn't heard a Canary: it needs a wireless or ender modem on it.")
      end
      local value = {}
      for _, fv in ipairs(FUEL_VALUES) do value[fv[1]] = fv[2] end
      if #cfg.fuels == 0 then printError("No fuel barrels set: /assign one as Canary fuel.") end
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
      DOCKS.info(print)
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
    elseif found == "/assign" then
      assignScreen()
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
print("Scanning storage...")
scanAll(); buildItems(); draw()
local firstRun = #cfg.inputs == 0 and not cfg.output
parallel.waitForAny(workerLoop, touchLoop, function()
  if firstRun then runCommand("/assign") end   -- brand-new storage: start on the assign screen
  terminalLoop()
end, netLoop)
