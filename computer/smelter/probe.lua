-- probe.lua  --  one-off test of a Mekanism enrichment chamber / enriching factory on the storage cable
--
-- Run it on the smelter computer (hold Ctrl+T to stop the smelter, then type: probe).
--   probe                      finds the chamber/factory itself, picks a raw ore from storage
--   probe <machine> <item>     e.g.  probe mekanism:basic_enriching_factory_0 minecraft:raw_iron
--
-- What it finds out, so the smelter can learn to use the machine:
--   * what the machine looks like to ComputerCraft (peripheral types, methods, slots)
--   * every get.../is... reading it offers (energy, progress, ...)
--   * whether it refuses something it can't enrich (cobblestone)
--   * whether raw ore can be pushed in, and which slot numbers take it
--   * what comes out of 3 raw ore, how many, how long it takes
--   * whether the output can be taken back out over the cable
-- Everything it moves goes back into storage at the end. Full details are written to probe.log.
-- Reboot afterwards (hold Ctrl+R) to start the smelter again.

local LOG        = "probe.log"
local WATCH_TIME = 45        -- seconds to wait for the machine to make something
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
  if #s > 400 then s = s:sub(1, 400) .. " ..." end
  return s
end

local function call(name, method, ...)
  local res = table.pack(pcall(peripheral.call, name, method, ...))
  if not res[1] then return false, tostring(res[2]) end
  return true, table.unpack(res, 2, res.n)
end

local function types(n) return { peripheral.getType(n) } end
local function typeText(n) return table.concat(types(n), ", ") end

---------------------------------------------------------------------------
-- 1. Find the machine
---------------------------------------------------------------------------
local function looksLikeEnricher(n)
  if n:lower():find("enrich") then return true end
  for _, t in ipairs(types(n)) do if tostring(t):lower():find("enrich") then return true end end
  return false
end

local names = peripheral.getNames()
table.sort(names)
detail("== probe.lua  " .. os.date("%Y-%m-%d %H:%M") .. "  computer " .. os.getComputerID())
detail("== Every peripheral this computer can see:")
for _, n in ipairs(names) do detail("  " .. n .. "  [" .. typeText(n) .. "]") end

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
    local mek = {}
    for _, n in ipairs(names) do if n:find("^mekanism") then mek[#mek + 1] = n end end
    if #mek > 0 then say("Mekanism things I can see: " .. table.concat(mek, ", ")) end
    saveLog()
    say("Details in " .. LOG)
    return
  end
  machine = found[1]
  -- A factory is the benchmark: prefer one if there's a chamber as well
  for _, n in ipairs(found) do if n:find("factory") then machine = n; break end end
  if #found > 1 then say("Found " .. #found .. ": " .. table.concat(found, ", ") .. ". Testing " .. machine .. ".", colours.yellow) end
end

local isInv = peripheral.hasType(machine, "inventory")
say("Machine: " .. machine, colours.cyan)
say("Types:   " .. typeText(machine))

---------------------------------------------------------------------------
-- 2. Its methods and every reading
---------------------------------------------------------------------------
local methods = peripheral.getMethods(machine) or {}
table.sort(methods)
detail("== Methods (" .. #methods .. "):")
detail("  " .. table.concat(methods, " "))
say(("Methods: %d%s"):format(#methods, isInv and ", incl. the inventory ones" or ", NOT an inventory"))

local INV_METHODS = { list = true, size = true, getItemDetail = true, getItemLimit = true }
local readings = {}
detail("== Readings (get/is/has methods; no args, then process 0 and 1 if it wants one):")
for _, m in ipairs(methods) do
  if not INV_METHODS[m] and (m:find("^get") or m:find("^is") or m:find("^has")) then
    local res = table.pack(call(machine, m))
    if res[1] then
      readings[m] = res[2]
      local out = {}
      for i = 2, res.n do out[#out + 1] = show(res[i]) end
      detail("  " .. m .. "() = " .. table.concat(out, ", "))
    else
      local tried = false
      for _, a in ipairs({ 0, 1 }) do
        local r2 = table.pack(call(machine, m, a))
        if r2[1] then
          tried = true
          local out = {}
          for i = 2, r2.n do out[#out + 1] = show(r2[i]) end
          detail(("  %s(%d) = %s"):format(m, a, table.concat(out, ", ")))
        end
      end
      if not tried then detail("  " .. m .. "() error: " .. tostring(res[2])) end
    end
  end
end

local function energyLine()
  for _, m in ipairs({ "getEnergyFilledPercentage", "getEnergy", "getEnergyStored" }) do
    if readings[m] ~= nil then
      local v = tonumber(readings[m])
      if m == "getEnergyFilledPercentage" and v then return ("%.0f%% full"):format(v * 100), v > 0 end
      return m .. " = " .. tostring(readings[m]), (v or 0) > 0
    end
  end
  return "no energy reading", nil
end
local eText, powered = energyLine()
say("Energy:  " .. eText, powered == false and colours.orange or nil)
if powered == false then say("  No power in it: it won't make anything until it has some.", colours.orange) end

---------------------------------------------------------------------------
-- 3. Its slots
---------------------------------------------------------------------------
local size = 0
local function slotsNow()
  if not isInv then return {} end
  local ok, l = call(machine, "list")
  return (ok and type(l) == "table") and l or {}
end
if isInv then
  local ok, s = call(machine, "size")
  size = ok and tonumber(s) or 0
  say("Slots:   " .. size)
  detail("== Slots as they are now:")
  for slot = 1, size do
    local _, it = call(machine, "getItemDetail", slot)
    local _, lim = call(machine, "getItemLimit", slot)
    detail(("  slot %d: %s  (limit %s)"):format(slot, it and (it.count .. " " .. it.name) or "empty", tostring(lim)))
  end
else
  say("It isn't an inventory over the cable, so storage can't push items into it directly.", colours.orange)
end

---------------------------------------------------------------------------
-- 4. Find test items in storage
---------------------------------------------------------------------------
local function isOtherMachine(n)
  return n == machine or n:find("furnace") or n:find("smoker") or n:find("^hostilenetworks:") or n:find("^powah:")
    or n:find("^industrialforegoing:") or n:find("^mekanism:.*factory") or n:find("enrich")
end
local function isDrawer(n) return n:find("drawer") or n:find("functionalstorage") end

local stores = {}
for _, n in ipairs(names) do
  if peripheral.hasType(n, "inventory") and not isOtherMachine(n) then stores[#stores + 1] = n end
end

local wantRaw = args[2]
local NEGATIVE = { "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:dirt", "minecraft:oak_planks" }
local rawAt, negAt
for _, n in ipairs(stores) do
  local ok, l = call(n, "list")
  if ok and type(l) == "table" then
    for slot, it in pairs(l) do
      local nm = it.name
      local isRaw
      if wantRaw then isRaw = nm == wantRaw
      else isRaw = nm:find(":raw_[%w_]+$") and not nm:find("_block$") end
      if isRaw and it.count >= 3 then
        -- raw iron if there is any, else the biggest stack
        if not rawAt or (nm == "minecraft:raw_iron" and rawAt.name ~= nm) or
           (rawAt.name ~= "minecraft:raw_iron" and it.count > rawAt.count) then
          rawAt = { inv = n, slot = slot, name = nm, count = it.count }
        end
      end
      if not negAt then
        for _, ng in ipairs(NEGATIVE) do
          if nm == ng then negAt = { inv = n, slot = slot, name = nm, count = it.count } end
        end
      end
    end
  end
end

-- Somewhere to put things back: the inventory it came from, unless that's a drawer controller
-- (items given to one without a target slot can start a new drawer), else any barrel/chest with room
local function homeFor(from)
  local list = {}
  if from and not isDrawer(from) then list[#list + 1] = from end
  for _, n in ipairs(stores) do
    if not isDrawer(n) and n ~= from then
      local ok, s = call(n, "size")
      local ok2, l = call(n, "list")
      local used = 0
      if ok2 and type(l) == "table" then for _ in pairs(l) do used = used + 1 end end
      if ok and s and used < s then list[#list + 1] = n end
    end
  end
  return list
end

local before = slotsNow()
local busyBefore = false
for slot, it in pairs(before) do
  busyBefore = true
  detail(("  already in it: slot %d %d %s"):format(slot, it.count, it.name))
end
if busyBefore then
  say("It already has items in it; I'll leave those alone and only take back what I add.", colours.yellow)
end

-- Count what's in the machine that we put there (anything not there at the start)
local function added()
  local now, out = slotsNow(), {}
  for slot, it in pairs(now) do
    local b = before[slot]
    local extra = (b and b.name == it.name) and (it.count - b.count) or it.count
    if extra > 0 then out[#out + 1] = { slot = slot, name = it.name, count = extra } end
  end
  table.sort(out, function(a, b) return a.slot < b.slot end)
  return out
end
local function addedText(list)
  local t = {}
  for _, a in ipairs(list) do t[#t + 1] = ("slot %d: %d %s"):format(a.slot, a.count, a.name) end
  return #t > 0 and table.concat(t, "; ") or "nothing"
end
-- Only take back what we added (slots that were empty before)
local function takeBackAdded(homes, label)
  if not isInv then return true end
  local allOut = true
  for _, a in ipairs(added()) do
    local left = a.count
    for _, h in ipairs(homes) do
      if left <= 0 then break end
      local ok, n = call(h, "pullItems", machine, a.slot, left)
      if ok and tonumber(n) then left = left - n
      else detail("  pullItems slot " .. a.slot .. " -> " .. h .. ": " .. tostring(n)) end
    end
    if left > 0 then
      for _, h in ipairs(homes) do
        if left <= 0 then break end
        local ok, n = call(machine, "pushItems", h, a.slot, left)
        if ok and tonumber(n) then left = left - n end
      end
    end
    detail(("  %s: took %d of %d %s out of slot %d"):format(label, a.count - left, a.count, a.name, a.slot))
    if left > 0 then allOut = false end
  end
  return allOut
end

-- Push n of an item in: from storage's side first, then the machine pulling
local function pushIn(at, n, toSlot)
  local ok, moved = call(at.inv, "pushItems", machine, at.slot, n, toSlot)
  detail(("  %s.pushItems(machine, %d, %d, %s) -> %s %s"):format(at.inv, at.slot, n, tostring(toSlot), tostring(ok), tostring(moved)))
  if ok and tonumber(moved) and moved > 0 then return moved, "push" end
  local why = not ok and moved or nil
  if isInv then
    local ok2, m2 = call(machine, "pullItems", at.inv, at.slot, n, toSlot)
    detail(("  machine.pullItems(%s, %d, %d, %s) -> %s %s"):format(at.inv, at.slot, n, tostring(toSlot), tostring(ok2), tostring(m2)))
    if ok2 and tonumber(m2) and m2 > 0 then return m2, "pull" end
    why = why or (not ok2 and m2) or nil
  end
  return 0, why
end

local results = {}

---------------------------------------------------------------------------
-- 5. Something it can't enrich should bounce
---------------------------------------------------------------------------
if negAt then
  say("Test 1: can it refuse " .. negAt.name:gsub("^minecraft:", "") .. "?", colours.cyan)
  local n, why = pushIn(negAt, 1)
  if n > 0 then
    results.refuses = false
    say("  It TOOK it (" .. addedText(added()) .. "). Taking it back.", colours.orange)
    takeBackAdded(homeFor(negAt.inv), "test 1")
  else
    results.refuses = true
    say("  Refused, good." .. (why and (" (" .. tostring(why) .. ")") or ""), colours.lime)
  end
else
  say("Test 1 skipped: no cobblestone/deepslate/dirt in storage to try.", colours.yellow)
end

---------------------------------------------------------------------------
-- 6. Raw ore in: where does it go, what comes out
---------------------------------------------------------------------------
if not rawAt then
  say("No raw ore (3 or more of one kind) in storage to test with. Put 3 raw iron in storage and run it again.", colours.red)
  saveLog(); say("Details in " .. LOG); return
end

say("Test 2: 3 " .. rawAt.name .. " in (no slot given)", colours.cyan)
local t0 = os.clock()
local moved, how = pushIn(rawAt, 3)
results.rawIn, results.rawHow = moved, how
if moved == 0 then
  say("  Wouldn't go in" .. (how and (": " .. tostring(how)) or "") .. ".", colours.red)
else
  local where = added()
  say(("  %d went in (%s): %s"):format(moved, how == "push" and "storage pushes" or "machine pulls", addedText(where)), colours.lime)
  results.landed = where
end

if moved > 0 and not isInv then
  say("  I can't look inside it, so those " .. moved .. " are still in it: take them out by hand.", colours.orange)
end

-- Which slot numbers take raw ore (1 at a time into each empty slot, taken straight back out)
if isInv and size > 0 then
  local takes, now = {}, slotsNow()
  for _, a in ipairs(results.landed or {}) do if a.name == rawAt.name then takes[#takes + 1] = a.slot end end
  for slot = 1, size do
    if not now[slot] then
      local ok, n = call(rawAt.inv, "pushItems", machine, rawAt.slot, 1, slot)
      if ok and tonumber(n) and n > 0 then
        takes[#takes + 1] = slot
        local back = false
        for _, h in ipairs(homeFor(rawAt.inv)) do
          local ok2, m = call(h, "pullItems", machine, slot, 1)
          if ok2 and tonumber(m) and m > 0 then back = true; break end
        end
        detail(("  slot %d takes raw ore; taken back out: %s"):format(slot, tostring(back)))
        if not back then results.cantTakeInput = true end
      end
    end
  end
  table.sort(takes)
  results.inputSlots = takes
  say("  Slots that take raw ore: " .. (#takes > 0 and table.concat(takes, ", ") or "none (when given a slot)"),
    #takes > 0 and colours.lime or colours.orange)
  if results.cantTakeInput then say("  ...but I couldn't take it back out of an input slot.", colours.orange) end
end

-- Watch for the product
if moved > 0 and isInv then
  say(("Test 3: waiting up to %d s for it to make something..."):format(WATCH_TIME), colours.cyan)
  local product, lastText
  local deadline = os.clock() + WATCH_TIME
  while os.clock() < deadline do
    local list = added()
    local txt = addedText(list)
    if txt ~= lastText then detail(("  %.1fs: %s"):format(os.clock() - t0, txt)); lastText = txt end
    for _, a in ipairs(list) do
      if a.name ~= rawAt.name then product = product or { slot = a.slot, name = a.name, at = os.clock() - t0 } end
    end
    local rawLeft = 0
    for _, a in ipairs(list) do if a.name == rawAt.name then rawLeft = rawLeft + a.count end end
    if product and rawLeft == 0 then break end
    if product and os.clock() - t0 - product.at > 15 then break end   -- some raw left over (not a full batch)
    os.sleep(0.5)
  end
  if product then
    os.sleep(1)
    local count, rawLeft = 0, 0
    for _, a in ipairs(added()) do
      if a.name == product.name then count = count + a.count; product.slot = a.slot end
      if a.name == rawAt.name then rawLeft = rawLeft + a.count end
    end
    results.product = { name = product.name, count = count, slot = product.slot, secs = product.at, rawLeft = rawLeft }
    say(("  Made %d %s from %d raw in %.1f s (output slot %d)%s"):format(count, product.name, moved - rawLeft,
      product.at, product.slot, rawLeft > 0 and (", " .. rawLeft .. " raw not used") or ""), colours.lime)
  else
    local rawLeft = 0
    for _, a in ipairs(added()) do if a.name == rawAt.name then rawLeft = rawLeft + a.count end end
    results.rawLeftNoProduct = rawLeft
    if rawLeft < moved then
      say(("  It used %d raw, but I can't see what it made: its output slot isn't open on the modem's side."):format(moved - rawLeft), colours.orange)
      say("  (Check the side config of the face the modem is on.)", colours.orange)
    else
      say("  Nothing came out in " .. WATCH_TIME .. " s." .. (powered == false and " (It has no power.)" or ""), colours.orange)
    end
    -- One more look at progress readings, in case it's just slow
    for _, m in ipairs({ "getRecipeProgress", "getTicksRequired", "getActive" }) do
      local ok, v = call(machine, m); if not ok then ok, v = call(machine, m, 0) end
      if ok then detail("  " .. m .. " = " .. show(v)) end
    end
  end
end

---------------------------------------------------------------------------
-- 7. Put everything back
---------------------------------------------------------------------------
if isInv then
  say("Test 4: taking it all back out over the cable", colours.cyan)
  local ok = takeBackAdded(homeFor(rawAt.inv), "test 4")
  results.allBack = ok
  if ok then say("  All back in storage.", colours.lime)
  else say("  Some of it wouldn't come out: " .. addedText(added()) .. ". Take it out by hand.", colours.orange) end
end

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
detail("== Summary")
detail("machine=" .. machine)
detail("types=" .. typeText(machine))
detail("inventory=" .. tostring(isInv) .. " size=" .. size)
detail("energy=" .. eText)
detail("results=" .. show(results))
saveLog()

print()
say("Summary", colours.cyan)
say(" inventory over cable: " .. (isInv and "yes" or "NO"))
if isInv then
  say(" storage counts it as storage: YES unless it's set to Ignore in storage's /assign", colours.orange)
end
say(" refuses cobble: " .. (results.refuses == nil and "?" or (results.refuses and "yes" or "NO")))
say(" raw ore in: " .. (moved > 0 and ("yes, by " .. tostring(how)) or "NO"))
if results.product then
  say((" 3 raw -> %d %s"):format(results.product.count, results.product.name:gsub("^.-:", "")))
end
if results.allBack ~= nil then say(" output comes back out: " .. (results.allBack and "yes" or "NO")) end
say("Full details in " .. LOG .. ". To send them: pastebin put " .. LOG)
say("Hold Ctrl+R to start the smelter again.")
