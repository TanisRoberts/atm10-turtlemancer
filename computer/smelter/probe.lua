-- probe.lua  --  one-off test of a Mekanism enrichment chamber / enriching factory on the storage cable
--
-- Run it on the smelter computer (hold Ctrl+T to stop the smelter, then type: probe).
--   probe                      finds the chamber/factory itself, tries raw ores from storage
--   probe <machine> <item>     e.g.  probe mekanism:basic_enriching_factory_1 minecraft:raw_iron
--
-- Round 2 (Oct 15 2026). Round 1 showed the factory is NOT an inventory over the cable: Mekanism
-- gives it its own peripheral (getInput(p) / getOutput(p) per process, energy, side config), and a
-- push into it returned 0 for raw tungsten. This round finds out why:
--   * the ITEM side config on every face (the modem's face decides what storage can do)
--   * which ores go in (iron/copper/gold first: Mekanism surely enriches those)
--   * what 3 raw ore makes, read with getInput/getOutput, and how long it takes
--   * whether the dust (and leftovers) can be pulled back out over the cable, and from which slot
-- Everything it moves goes back into storage at the end. Full details are written to probe.log.
-- Reboot afterwards (hold Ctrl+R) to start the smelter again.

local LOG        = "probe.log"
local WATCH_TIME = 45        -- seconds to wait for the machine to make something
local MAX_KINDS  = 5         -- different ores to try before giving up
local args       = { ... }

local logLines = {}
local function detail(s) logLines[#logLines + 1] = tostring(s) end
local function say(s, col)
  detail(s)
  if col and term.isColour() then term.setTextColour(col) end
  print(s)
  term.setTextColour(colours.white)
end
local function saveLog()
  local f = fs.open(LOG, "w")
  f.write(table.concat(logLines, "\n") .. "\n")
  f.close()
end

local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local ok, s = pcall(textutils.serialize, v, { compact = true })
  if not ok then ok, s = pcall(textutils.serialize, v) end
  if not ok then return "<table>" end
  s = s:gsub("%s+", " ")
  if #s > 300 then s = s:sub(1, 300) .. " ..." end
  return s
end

local function call(name, method, ...)
  local res = table.pack(pcall(peripheral.call, name, method, ...))
  if not res[1] then return false, tostring(res[2]) end
  return true, table.unpack(res, 2, res.n)
end

local function typeText(n) return table.concat({ peripheral.getType(n) }, ", ") end
local function short(id) return (tostring(id):gsub("^[^:]*:", "")) end

---------------------------------------------------------------------------
-- 1. Find the machine
---------------------------------------------------------------------------
local names = peripheral.getNames()
table.sort(names)
detail("== probe.lua round 2  " .. os.date("%Y-%m-%d %H:%M") .. "  computer " .. os.getComputerID())
detail("== Peripherals on my cable:")
for _, n in ipairs(names) do detail("  " .. n .. "  [" .. typeText(n) .. "]") end

local function looksLikeEnricher(n)
  if n:lower():find("enrich") then return true end
  for _, t in ipairs({ peripheral.getType(n) }) do if tostring(t):lower():find("enrich") then return true end end
  return false
end

-- "probe minecraft:raw_iron" (just an item) works too: a first word that isn't on the cable but looks
-- like an item id is the item
if args[1] and not args[2] and not peripheral.isPresent(args[1]) and args[1]:find(":") then
  args[2], args[1] = args[1], nil
end
local machine = args[1]
if machine and not peripheral.isPresent(machine) then
  say("I can't see '" .. machine .. "' on my cable.", colours.red)
  machine = nil
end
if not machine then
  local found = {}
  for _, n in ipairs(names) do if looksLikeEnricher(n) then found[#found + 1] = n end end
  if #found == 0 then
    say("No enrichment chamber or factory on my cable.", colours.red)
    say("Put a wired modem on it (on the storage cable) and right-click the modem so its ring goes red.")
    saveLog(); say("Details in " .. LOG)
    return
  end
  machine = found[1]
  for _, n in ipairs(found) do if n:find("[Ff]actory") then machine = n; break end end
  if #found > 1 then say("Found " .. #found .. ": " .. table.concat(found, ", ") .. ". Testing " .. machine .. ".", colours.yellow) end
end
local isInv = peripheral.hasType(machine, "inventory")
say("Machine: " .. machine .. "  [" .. typeText(machine) .. "]", colours.cyan)

local methods = peripheral.getMethods(machine) or {}
table.sort(methods)
local has = {}
for _, m in ipairs(methods) do has[m] = true end
detail("== Methods (" .. #methods .. "): " .. table.concat(methods, " "))

---------------------------------------------------------------------------
-- 2. Energy and the ITEM side config
---------------------------------------------------------------------------
local function one(m, ...)
  if not has[m] then return nil end
  local ok, v = call(machine, m, ...)
  detail(("  %s(%s) = %s"):format(m, table.concat({ ... }, ", "), ok and show(v) or ("error: " .. tostring(v))))
  if ok then return v end
end
detail("== Readings")
local pct = one("getEnergyFilledPercentage")
one("getEnergy"); one("getMaxEnergy"); one("getEnergyUsage")
local ticks = one("getTicksRequired")
one("getDirection"); one("getInstalledUpgrades"); one("isAutoSortEnabled"); one("hasStrictInput")
one("getRedstoneMode"); one("getSecurityMode")
if has.getConfigurableTypes then one("getConfigurableTypes") end
local powered = pct == nil and nil or (tonumber(pct) or 0) > 0
say(("Energy: %s   Ticks per op: %s"):format(pct and ("%.0f%%"):format(pct * 100) or "?", tostring(ticks or "?")),
  powered == false and colours.orange or nil)
if powered == false then say("  It has no power: it won't make anything.", colours.orange) end

local SIDES = { "FRONT", "BACK", "LEFT", "RIGHT", "TOP", "BOTTOM" }
local sideModes = {}
if has.getMode then
  detail("== ITEM side config")
  local modes = one("getSupportedModes", "ITEM")
  local ej = one("isEjecting", "ITEM")
  local parts = {}
  for _, s in ipairs(SIDES) do
    local ok, v = call(machine, "getMode", "ITEM", s)
    sideModes[s] = ok and tostring(v) or "?"
    detail(("  getMode(ITEM, %s) = %s"):format(s, ok and show(v) or ("error: " .. tostring(v))))
    parts[#parts + 1] = s:sub(1, 1) .. s:sub(2):lower() .. "=" .. sideModes[s]
  end
  say("Item sides: " .. table.concat(parts, " "))
  if modes then say("  modes it allows: " .. (show(modes):gsub("[{}\"]", ""))) end
  if ej ~= nil then say("  auto-eject items: " .. tostring(ej)) end
else
  say("No side config methods.", colours.yellow)
end

---------------------------------------------------------------------------
-- 3. Reading what's inside: getInput(p) / getOutput(p) (or list() if it's an inventory)
---------------------------------------------------------------------------
local PROCS = 0
if has.getInput then
  for p = 0, 15 do
    local ok = call(machine, "getInput", p)
    if not ok then break end
    PROCS = p + 1
  end
end
local function insideNow()
  local out = {}
  local function add(where, it)
    if type(it) == "table" and it.name and it.name ~= "minecraft:air" and (it.count or 0) > 0 then
      out[#out + 1] = { where = where, name = it.name, count = it.count }
    end
  end
  if PROCS > 0 then
    for p = 0, PROCS - 1 do
      local _, i = call(machine, "getInput", p); add("in" .. p, i)
      local _, o = call(machine, "getOutput", p); add("out" .. p, o)
    end
  elseif isInv then
    local ok, l = call(machine, "list")
    if ok and type(l) == "table" then for s, it in pairs(l) do add("slot" .. s, it) end end
  end
  return out
end
local function count(list, name)
  local n = 0
  for _, a in ipairs(list) do if a.name == name then n = n + a.count end end
  return n
end
local function insideText(list)
  local t = {}
  for _, a in ipairs(list) do t[#t + 1] = ("%s: %d %s"):format(a.where, a.count, short(a.name)) end
  return #t > 0 and table.concat(t, "; ") or "empty"
end
local startInside = insideNow()
say(("Processes: %d   Inside now: %s"):format(PROCS, insideText(startInside)))

---------------------------------------------------------------------------
-- 4. Ores in storage to try (Mekanism surely enriches vanilla raw iron/copper/gold)
---------------------------------------------------------------------------
local function isMachineName(n)
  return n == machine or n:find("furnace") or n:find("smoker") or n:find("^hostilenetworks:") or n:find("^powah:")
    or n:find("^industrialforegoing:") or looksLikeEnricher(n) or n:find("^mekanism:")
end
local function isDrawer(n) return n:find("drawer") or n:find("functionalstorage") end
local stores = {}
for _, n in ipairs(names) do
  if peripheral.hasType(n, "inventory") and not isMachineName(n) then stores[#stores + 1] = n end
end

local PREFER = { "minecraft:raw_iron", "minecraft:raw_copper", "minecraft:raw_gold", "mekanism:raw_osmium",
  "mekanism:raw_tin", "mekanism:raw_lead", "mekanism:raw_uranium", "minecraft:iron_ore", "minecraft:deepslate_iron_ore",
  "minecraft:copper_ore", "minecraft:deepslate_copper_ore", "minecraft:gold_ore", "minecraft:deepslate_gold_ore" }
local rank = {}
for i, n in ipairs(PREFER) do rank[n] = i end
local function oreish(nm)
  if args[2] then return nm == args[2] end
  if rank[nm] then return true end
  return (nm:find(":raw_[%w_]+$") and not nm:find("_block$")) or nm:find("_ore$")
end
local kinds, byKind = {}, {}
local negAt
for _, n in ipairs(stores) do
  local ok, l = call(n, "list")
  if ok and type(l) == "table" then
    for slot, it in pairs(l) do
      if oreish(it.name) and it.count >= 3 then
        local cur = byKind[it.name]
        if not cur then kinds[#kinds + 1] = it.name end
        if not cur or (isDrawer(cur.inv) and not isDrawer(n)) then
          byKind[it.name] = { inv = n, slot = slot, name = it.name, count = it.count }
        end
      end
      if not negAt and (it.name == "minecraft:dirt" or it.name == "minecraft:cobblestone" or it.name == "minecraft:cobbled_deepslate") then
        negAt = { inv = n, slot = slot, name = it.name }
      end
    end
  end
end
table.sort(kinds, function(a, b)
  local ra, rb = rank[a] or 999, rank[b] or 999
  if ra ~= rb then return ra < rb end
  return a < b
end)
detail("== Ores in storage (3+ in one slot): " .. table.concat(kinds, ", "))
if #kinds == 0 then
  say("No raw ore or ore blocks (3+ in one slot) in storage. Put 3 raw iron in and run it again.", colours.red)
  saveLog(); say("Details in " .. LOG); return
end

-- Where things go back: a barrel/chest with room (not a drawer controller: items given to one
-- without a target slot can start a new drawer)
local homes = {}
for _, n in ipairs(stores) do
  if not isDrawer(n) then
    local ok, s = call(n, "size")
    local ok2, l = call(n, "list")
    local used = 0
    if ok2 and type(l) == "table" then for _ in pairs(l) do used = used + 1 end end
    if ok and s and used < s then homes[#homes + 1] = n end
    if #homes >= 4 then break end
  end
end
detail("== Homes for things coming back: " .. table.concat(homes, ", "))

local results = { sides = sideModes, procs = PROCS }

---------------------------------------------------------------------------
-- 5. Push tests
---------------------------------------------------------------------------
local function push(at, n, toSlot)
  local ok, moved = call(at.inv, "pushItems", machine, at.slot, n, toSlot)
  detail(("  %s.pushItems(machine, %d, %d, %s) -> %s"):format(at.inv, at.slot, n, tostring(toSlot),
    ok and tostring(moved) or ("error: " .. tostring(moved))))
  return ok and tonumber(moved) or 0, not ok and moved or nil
end

if negAt then
  local n = push(negAt, 1)
  results.refusesJunk = n == 0
  say(("Junk (%s): %s"):format(short(negAt.name), n == 0 and "refused" or "TOOK IT"), n == 0 and colours.lime or colours.orange)
end

local used, moved, err
local tried = {}
for i = 1, math.min(#kinds, MAX_KINDS) do
  local at = byKind[kinds[i]]
  local n, e = push(at, 3)
  if n == 0 then
    -- maybe it wants a slot number
    for s = 1, 9 do
      local n2 = push(at, 3, s)
      if n2 > 0 then n = n2; results.needsSlot = s; break end
    end
  end
  tried[#tried + 1] = short(at.name) .. (n > 0 and " IN" or " no")
  if n > 0 then used, moved = at, n; break end
  err = err or e
end
results.tried = tried
say("Ores tried: " .. table.concat(tried, ", "), used and colours.lime or colours.orange)
if err then say("  error: " .. tostring(err), colours.orange) end

if not used then
  results.verdict = "nothing goes in"
  say("Nothing went in. Most likely the face the modem is on isn't set to Input for items", colours.orange)
  say("(open the factory, Side Config, Items tab: that face should be red / Input).", colours.orange)
else
  say(("%d %s went in%s. Inside: %s"):format(moved, short(used.name),
    results.needsSlot and (" (only with slot " .. results.needsSlot .. ")") or "", insideText(insideNow())), colours.lime)

  -------------------------------------------------------------------------
  -- 6. Watch for the product
  -------------------------------------------------------------------------
  say(("Waiting up to %d s for it to make something..."):format(WATCH_TIME), colours.cyan)
  local t0, product, last = os.clock(), nil, nil
  local before = {}
  for _, a in ipairs(startInside) do before[a.name] = (before[a.name] or 0) + a.count end
  while os.clock() - t0 < WATCH_TIME do
    local now = insideNow()
    local txt = insideText(now)
    if txt ~= last then detail(("  %.1fs: %s"):format(os.clock() - t0, txt)); last = txt end
    for _, a in ipairs(now) do
      if a.name ~= used.name and a.count > (before[a.name] or 0) and not product then
        product = { name = a.name, at = os.clock() - t0, where = a.where }
      end
    end
    if product and count(now, used.name) <= (before[used.name] or 0) then break end
    if product and os.clock() - t0 - product.at > 15 then break end
    os.sleep(0.5)
  end
  if product then
    os.sleep(1)
    local now = insideNow()
    local made = count(now, product.name) - (before[product.name] or 0)
    local rawLeft = count(now, used.name) - (before[used.name] or 0)
    results.product = { name = product.name, count = made, from = moved - rawLeft, secs = product.at, where = product.where }
    say(("Made %d %s from %d %s in %.1f s (%s)"):format(made, short(product.name), moved - rawLeft, short(used.name),
      product.at, product.where), colours.lime)
  else
    say("Nothing came out in " .. WATCH_TIME .. " s." .. (powered == false and " (No power.)" or ""), colours.orange)
  end

  -------------------------------------------------------------------------
  -- 7. Pull everything back out, slot by slot (shows which slot numbers this face offers)
  -------------------------------------------------------------------------
  say("Taking it back out over the cable...", colours.cyan)
  local pulledFrom = {}
  for slot = 1, 16 do
    for _, h in ipairs(homes) do
      local ok, n = call(h, "pullItems", machine, slot, 64)
      if ok and tonumber(n) and n > 0 then
        pulledFrom[#pulledFrom + 1] = ("slot %d: %d"):format(slot, n)
        detail(("  %s.pullItems(machine, %d) -> %d"):format(h, slot, n))
      else
        if not ok then detail(("  %s.pullItems(machine, %d) error: %s"):format(h, slot, tostring(n))) end
        break
      end
    end
  end
  results.pulled = pulledFrom
  local stuck = {}
  for _, a in ipairs(insideNow()) do
    local extra = a.count
    for _, b in ipairs(startInside) do if b.where == a.where and b.name == a.name then extra = a.count - b.count end end
    if extra > 0 then stuck[#stuck + 1] = ("%d %s"):format(extra, short(a.name)) end
  end
  results.stuck = stuck
  say("Pulled out: " .. (#pulledFrom > 0 and table.concat(pulledFrom, ", ") or "nothing"),
    #pulledFrom > 0 and colours.lime or colours.orange)
  if #stuck > 0 then
    say("Still in it: " .. table.concat(stuck, ", ") .. ". Take them out by hand.", colours.orange)
    say("(This face doesn't let items out: it needs Output, or Input/Output if it's offered.)", colours.orange)
  else
    say("All back in storage.", colours.lime)
  end
end

---------------------------------------------------------------------------
detail("== Summary")
detail("machine=" .. machine .. " types=" .. typeText(machine) .. " inventory=" .. tostring(isInv))
detail("results=" .. show(results))
saveLog()
print()
say("Done. Details in " .. LOG .. ". To send them: pastebin put " .. LOG, colours.cyan)
say("Also tell me which face of the factory the modem is on. Hold Ctrl+R to restart the smelter.")
