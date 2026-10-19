-- turtlecore_fuel.lua  --  core.fuel: the one fuel table, refuelling from his slots and from the dock.
-- Only items in the table are ever burned: never logs, planks or saplings.
return function(core)
local F = {}
core.fuel = F

-- Best first: a coal block is 800 in one slot item (64 to a stack), a lava bucket is 1000 but stacks to 1.
F.order = {
  { "minecraft:coal_block", 800 }, { "minecraft:lava_bucket", 1000 }, { "minecraft:blaze_rod", 120 },
  { "mekanism:bio_fuel", 5 }, { "minecraft:coal", 80 }, { "minecraft:charcoal", 80 }, { "minecraft:stick", 5 },
}
F.value, F.rank = {}, {}
for i, e in ipairs(F.order) do F.value[e[1]] = e[2]; F.rank[e[1]] = i end
local BUCKET = "minecraft:bucket"

function F.isFuel(name) return F.value[name] ~= nil end
function F.level() local f = turtle.getFuelLevel(); return f == "unlimited" and math.huge or f end
function F.limit() local l = turtle.getFuelLimit(); return l == "unlimited" and math.huge or l end
function F.needFuel(low) return F.level() < low end

-- Burn as many of the slot's items as it takes to reach `target` (never past the tank). Returns items burned.
function F.burnSlot(slot, target)
  local d = turtle.getItemDetail(slot)
  local v = d and F.value[d.name]
  local level = F.level()
  if not v or level == math.huge then return 0 end
  local goal = math.min(target, F.limit())
  local n = math.min(d.count, math.ceil((goal - level) / v), math.floor((F.limit() - level) / v))
  if n < 1 then return 0 end
  turtle.select(slot)
  turtle.refuel(n)
  return n
end

-- Burn what he carries, best fuel first, until `target`. Returns the fuel gained. An empty bucket left by
-- lava stays in his slots until the next dock visit (core.fuel.returnEmpties).
function F.refuelFromInventory(target)
  local before, slots = F.level(), {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and F.rank[d.name] then slots[#slots + 1] = { s, F.rank[d.name] } end
  end
  table.sort(slots, function(a, b) if a[2] ~= b[2] then return a[2] < b[2] end return a[1] < b[1] end)
  for _, e in ipairs(slots) do
    if F.level() >= target then break end
    F.burnSlot(e[1], target)
  end
  turtle.select(1)
  return before == math.huge and 0 or F.level() - before
end

-- Put every empty bucket he carries into the dock (drop = the drop function for that side).
function F.returnEmpties(drop)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and d.name == BUCKET then turtle.select(s); drop(d.count) end
  end
  turtle.select(1)
end

-- Take what he needs out of the dock: fuel up to `target`, plus want(name, have) more of anything he
-- restocks from it (saplings, say). suck() always hands over the barrel's FIRST stack, so the dock's slot
-- order decides which fuel comes first; things he doesn't want are held in spare slots and only put back at
-- the end (dropping them straight back would just get them sucked again). Empty buckets go back too.
-- Returns { [name] = taken } for the restocked items.
function F.refuelFromDock(dir, target, want)
  local drop, suck = core.dock.ops(dir)
  local got = {}
  local function fuelNeeded() return target > 0 and F.level() < target end
  local function wantsFromDock()
    if not want then return false end
    local l = core.dock.list(dir)
    if not l then return true end              -- can't see in: have a look anyway
    for _, it in pairs(l) do if want(it.name, core.dock.holding(it.name)) > 0 then return true end end
    return false
  end
  local function fuelInDock()
    local l = core.dock.list(dir)
    if not l then return true end
    for _, it in pairs(l) do if F.value[it.name] then return true end end
    return false
  end
  local held = {}
  for _ = 1, 27 do
    local needFuel = fuelNeeded() and fuelInDock()
    if not needFuel and not wantsFromDock() then break end
    local free
    for s = 16, 1, -1 do if turtle.getItemCount(s) == 0 then free = s; break end end
    if not free then break end
    turtle.select(free)
    if not suck() then break end
    local d = turtle.getItemDetail(free)
    if d and F.value[d.name] and fuelNeeded() then F.burnSlot(free, target) end
    local count = turtle.getItemCount(free)
    if d and count > 0 then
      local keep = want and math.max(0, math.min(count, want(d.name, core.dock.holding(d.name, free)))) or 0
      if keep > 0 then
        got[d.name] = (got[d.name] or 0) + keep
        if count > keep then drop(count - keep) end   -- he has enough now, so it won't be taken again
        if turtle.getItemCount(free) > keep then held[#held + 1] = free end   -- dock full: hand it back later
      else
        held[#held + 1] = free
      end
    end
  end
  for _, s in ipairs(held) do
    turtle.select(s)
    local d = turtle.getItemDetail(s)
    if d then
      local keep = want and math.max(0, math.min(d.count, want(d.name, core.dock.holding(d.name, s)))) or 0
      if d.count > keep then drop(d.count - keep) end
    end
  end
  F.returnEmpties(drop)
  turtle.select(1)
  return got
end
end
