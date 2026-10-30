-- opchests.lua  --  the Operator's item moves at one reactor: its two Ender Storage chests and its two access ports.
--   fuel chest -> inlet port  when the reactor has room, best fuel first (uranium blocks, worth 9, before ingots, worth 1)
--   outlet port -> waste chest  everything, every pass
-- Storage keeps the fuel chest stocked and empties the waste chest from the far end (issues #103, #104).
-- Fuel is held back while waste can't clear. A unit's chests are `fuelChest` / `wasteChest` in its operator.cfg entry,
-- or worked out when there is exactly one reactor and the ender chests tell themselves apart; otherwise "unknown".
local plantlib = require("opplant")

local M = {}
local STACK = 64                              -- the inlet may hold less than this many fuel units before we push more
local TAG_BLOCK, TAG_INGOT = "c:storage_blocks/uranium", "c:ingots/uranium"
local cache = {}                              -- item name -> fuel units it is worth

local function isEnder(name) return tostring(name):lower():find("ender_chest", 1, true) ~= nil end

local function tagged(tags, t) return tags[t] or tags["#" .. t] end

-- Fuel units one item is worth. Tags come from getItemDetail (read once per item name); a name that carries neither
-- tag falls back to the name rules in opplant.
function M.worth(inv, slot, name)
  local w = cache[name]
  if w ~= nil then return w end
  local ok, d = pcall(peripheral.call, inv, "getItemDetail", slot)
  if not ok or type(d) ~= "table" then return plantlib.fuelValue(name) end
  local tags = type(d.tags) == "table" and d.tags or {}
  w = (tagged(tags, TAG_BLOCK) and 9) or (tagged(tags, TAG_INGOT) and 1) or plantlib.fuelValue(name)
  cache[name] = w
  return w
end

-- Fuel units in an inventory (nil when it can't be read)
function M.units(inv)
  local l = plantlib.listOf(inv)
  if not l then return nil end
  local n = 0
  for slot, it in pairs(l) do n = n + M.worth(inv, slot, it.name) * (it.count or 0) end
  return n
end

-- Chests ------------------------------------------------------------------
-- Called at the end of the plant's port resolution (reactors in plant.units, u.cfg, u.awaiting set).
function M.resolve(plant)
  local reactors, enders, claimed = {}, {}, {}
  for _, u in ipairs(plant.units) do
    if u.kind == "reactor" and u.present then reactors[#reactors + 1] = u end
    if u.cfg.fuelChest then claimed[u.cfg.fuelChest] = true end
    if u.cfg.wasteChest then claimed[u.cfg.wasteChest] = true end
  end
  for _, n in ipairs(peripheral.getNames()) do if isEnder(n) then enders[#enders + 1] = n end end
  table.sort(enders)
  for _, u in ipairs(reactors) do
    local c = u.cfg
    u.fuelChest, u.wasteChest, u.chestNote = c.fuelChest, c.wasteChest, nil
    if not (c.fuelChest and c.wasteChest) and #reactors == 1 and not u.awaiting then
      local free = {}
      for _, n in ipairs(enders) do if not claimed[n] then free[#free + 1] = n end end
      local newly = false
      if not c.fuelChest then
        local holding = {}
        for _, n in ipairs(free) do if (M.units(n) or 0) > 0 then holding[#holding + 1] = n end end
        if #holding == 1 then c.fuelChest = holding[1]; claimed[holding[1]] = true; u.fuelChest = holding[1]; newly = true end
      end
      if c.fuelChest and not c.wasteChest then
        local others = {}
        for _, n in ipairs(enders) do if not claimed[n] then others[#others + 1] = n end end
        if #others == 1 then c.wasteChest = others[1]; claimed[others[1]] = true; u.wasteChest = others[1]; newly = true end
      end
      if newly then
        plant.log(("%s chests: fuel %s, waste %s (worked out from what they hold; assign them on the Needs tab to pin them)")
          :format(u.label, tostring(c.fuelChest), tostring(c.wasteChest)))
        plant:save()
      end
    end
    if not (u.fuelChest and u.wasteChest) then
      u.chestNote = (#enders == 0 and "no ender chest on the cable")
        or (#reactors > 1 and "several reactors: assign its chests on the Needs tab")
        or "can't tell which ender chest is which: assign them on the Needs tab"
    end
    u.fuelChestGone = (u.fuelChest and not peripheral.isPresent(u.fuelChest)) or nil
    u.wasteChestGone = (u.wasteChest and not peripheral.isPresent(u.wasteChest)) or nil
  end
end

-- Moves ---------------------------------------------------------------------
local function call(inv, method, ...)
  local ok, r = pcall(peripheral.call, inv, method, ...)
  if ok then return r end
end

-- Is the chest unable to take cyanite? Every slot used, and no part-filled cyanite stack to top up.
local function full(chest)
  local size, l = call(chest, "size"), plantlib.listOf(chest)
  if type(size) ~= "number" or size <= 0 or not l then return false end
  local used = 0
  for slot, it in pairs(l) do
    used = used + 1
    if plantlib.isWaste(it.name) and (it.count or 0) < (tonumber(call(chest, "getItemLimit", slot)) or STACK) then return false end
  end
  return used >= size
end

local function wasteOut(u)
  local l = plantlib.listOf(u.output)
  local failed = false
  for slot, it in pairs(l or {}) do
    local left = it.count or 0
    while left > 0 do
      local n = tonumber(call(u.output, "pushItems", u.wasteChest, slot)) or 0
      if n <= 0 then failed = true; break end
      left = left - n
    end
  end
  u.wasteChestFull = failed or full(u.wasteChest)
end

local function fuelIn(u)
  local s = u.status or {}
  if not (u.input and not u.inputGone and s.fuelMax and s.fuel) then return end
  local inlet = M.units(u.input)
  if inlet == nil or inlet >= STACK then return end
  local budget = math.floor((s.fuelMax - s.fuel) / 1000) - inlet      -- whole fuel units the reactor can still take
  if budget < 1 then return end
  local l = plantlib.listOf(u.fuelChest)
  if not l then return end
  local items = {}
  for slot, it in pairs(l) do
    local w = M.worth(u.fuelChest, slot, it.name)
    if w > 0 then items[#items + 1] = { slot = slot, w = w, count = it.count or 0 } end
  end
  table.sort(items, function(a, b) if a.w ~= b.w then return a.w > b.w end return a.slot < b.slot end)
  local pushed = 0
  for _, it in ipairs(items) do
    local n = math.min(it.count, math.floor(budget / it.w))
    if n >= 1 then
      local moved = tonumber(call(u.fuelChest, "pushItems", u.input, it.slot, n)) or 0
      budget, pushed = budget - moved * it.w, pushed + moved * it.w
    end
    if budget < 1 then break end
  end
  if pushed > 0 then u.fedAt = os.clock() end
end

-- One pass for one reactor. Returns true when something the Needs list shows changed.
function M.step(u, hooks)
  local was = u.holdFuel or false
  u.fuelChestUnits, u.wasteChestFull = nil, false
  if u.fuelChest and not u.fuelChestGone then u.fuelChestUnits = M.units(u.fuelChest) end
  if u.output and not u.outputGone and u.wasteChest and not u.wasteChestGone then wasteOut(u) end
  u.holdFuel = (u.wasteStuck or u.wasteChestFull or u.wasteChestGone) and true or false
  if u.fuelChest and not u.fuelChestGone and not u.holdFuel then fuelIn(u) end
  if u.holdFuel and not was and u.fuelChest then
    hooks.log(u.label .. ": fuel held back, waste is not clearing")
    hooks.event(u.label, "fuel held back, waste not clearing")
  elseif was and not u.holdFuel then
    hooks.log(u.label .. ": waste clearing again, fuel feed resumed")
  end
  return was ~= u.holdFuel
end

return M
