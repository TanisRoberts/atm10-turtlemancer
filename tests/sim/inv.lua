-- sim/inv.lua  --  inventory peripherals (chest, barrel, drawer, furnace) with CC:Tweaked semantics:
-- pushItems/pullItems move at most ONE stack per call and return how many actually moved.
local Inv = {}
Inv.__index = Inv

-- Stack sizes. Everything else is 64.
Inv.stack = {
  ["minecraft:bucket"] = 16, ["minecraft:ender_pearl"] = 16, ["minecraft:snowball"] = 16, ["minecraft:egg"] = 16,
  ["minecraft:enchanted_book"] = 1, ["minecraft:water_bucket"] = 1, ["minecraft:lava_bucket"] = 1, ["minecraft:milk_bucket"] = 1,
}
function Inv.stackOf(name)
  local s = Inv.stack[name]
  if s then return s end
  if name:find("_pickaxe$") or name:find("_axe$") or name:find("_shovel$") or name:find("_hoe$")
     or name:find("_sword$") or name:find("shulker_box$") or name:find("_helmet$") or name:find("_boots$") then
    return 1
  end
  return 64
end

local function pretty(name)
  local s = name:gsub("^[^:]*:", ""):gsub("_", " ")
  return (s:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- opts: size, types (peripheral types), slotLimit (fixed limit per slot, like a drawer), net/name set by network:add
function Inv.new(opts)
  opts = opts or {}
  local self = setmetatable({ slots = {}, nslots = opts.size or 27, slotLimit = opts.slotLimit,
                              types = opts.types or { "minecraft:chest", "inventory" } }, Inv)
  return self
end
Inv.peripheralMethods = { "size", "list", "getItemDetail", "getItemLimit", "pushItems", "pullItems" }

function Inv:touch() end                           -- hook for subclasses that change over time (furnaces)
function Inv:limitFor(name) return self.slotLimit or Inv.stackOf(name) end
function Inv:canInsert() return true end            -- (slot, name)

-- Put up to `count` of `name` in, into `toSlot` or the first fitting slots. Returns how many went in.
function Inv:insert(name, count, toSlot, extra)
  self:touch()
  local put = 0
  local function into(i)
    if count - put <= 0 or not self:canInsert(i, name) then return end
    local s = self.slots[i]
    local lim = self:limitFor(name)
    if s then
      if s.name ~= name or s.nbt ~= (extra and extra.nbt) then return end
      local n = math.min(lim - s.count, count - put)
      if n > 0 then s.count = s.count + n; put = put + n end
    else
      local n = math.min(lim, count - put)
      if n > 0 then
        self.slots[i] = { name = name, count = n, displayName = pretty(name), nbt = extra and extra.nbt }
        put = put + n
      end
    end
  end
  if toSlot then
    if toSlot < 1 or toSlot > self.nslots then error("Slot out of range", 3) end
    into(toSlot)
  else
    for i = 1, self.nslots do if self.slots[i] then into(i) end end
    for i = 1, self.nslots do if not self.slots[i] then into(i) end end
  end
  return put
end

-- Take up to `count` out of a slot. Returns name, taken.
function Inv:extract(slot, count)
  self:touch()
  local s = self.slots[slot]
  if not s then return nil, 0 end
  local n = math.min(count or s.count, s.count)
  s.count = s.count - n
  local name = s.name
  if s.count <= 0 then self.slots[slot] = nil end
  return name, n
end

-- peripheral methods
function Inv:size() return self.nslots end
function Inv:list()
  self:touch()
  local out = {}
  for i = 1, self.nslots do
    local s = self.slots[i]
    if s then out[i] = { name = s.name, count = s.count, nbt = s.nbt } end
  end
  return out
end
function Inv:getItemDetail(slot)
  self:touch()
  if slot < 1 or slot > self.nslots then error("Slot out of range", 2) end
  local s = self.slots[slot]
  if not s then return nil end
  return { name = s.name, count = s.count, displayName = s.displayName, nbt = s.nbt, maxCount = self:limitFor(s.name), tags = {} }
end
function Inv:getItemLimit(slot)
  if slot < 1 or slot > self.nslots then error("Slot out of range", 2) end
  local s = self.slots[slot]
  return self:limitFor(s and s.name or "minecraft:stone")
end

local function remote(self, name)
  if not self.net then error("Not on a wired network", 3) end
  local d = self.net:get(name)
  if not d then error("Target '" .. tostring(name) .. "' does not exist", 3) end
  if not d.insert then error("Target '" .. tostring(name) .. "' is not an inventory", 3) end
  return d
end

function Inv:pushItems(toName, fromSlot, limit, toSlot)
  self:touch()
  local to = remote(self, toName)
  local s = self.slots[fromSlot]
  if not s then return 0 end
  local want = math.min(limit or s.count, s.count, self:limitFor(s.name))
  local n = to:insert(s.name, want, toSlot, s)
  self:extract(fromSlot, n)
  return n
end

function Inv:pullItems(fromName, fromSlot, limit, toSlot)
  local from = remote(self, fromName)
  from:touch()
  local s = from.slots[fromSlot]
  if not s then return 0 end
  local want = math.min(limit or s.count, s.count, from:limitFor(s.name))
  local n = self:insert(s.name, want, toSlot, s)
  from:extract(fromSlot, n)
  return n
end

-- test-side helpers (not peripheral methods)
function Inv:give(name, count, slot, extra)  -- extra = { nbt = "..." }; returns what didn't fit
  return count - self:insert(name, count, slot, extra)
end
function Inv:count(name)
  self:touch()
  local c = 0
  for _, s in pairs(self.slots) do if s.name == name then c = c + s.count end end
  return c
end
function Inv:totals()
  self:touch()
  local t = {}
  for _, s in pairs(self.slots) do t[s.name] = (t[s.name] or 0) + s.count end
  return t
end
function Inv:isEmpty() return next(self.slots) == nil end
function Inv:clear() self.slots = {} end

---------------------------------------------------------------------------
-- Furnace: slot 1 input, 2 fuel, 3 output. Cooks lazily: state catches up to the clock on every access.
---------------------------------------------------------------------------
local Furnace = setmetatable({}, { __index = Inv })
Furnace.__index = Furnace
Inv.Furnace = Furnace

Furnace.recipes = {
  ["minecraft:raw_iron"] = "minecraft:iron_ingot", ["minecraft:raw_copper"] = "minecraft:copper_ingot",
  ["minecraft:raw_gold"] = "minecraft:gold_ingot", ["minecraft:iron_ore"] = "minecraft:iron_ingot",
  ["minecraft:cobblestone"] = "minecraft:stone", ["minecraft:sand"] = "minecraft:glass",
  ["minecraft:cobbled_deepslate"] = "minecraft:deepslate", ["minecraft:oak_log"] = "minecraft:charcoal",
  ["minecraft:clay_ball"] = "minecraft:brick",
}
-- seconds of burning per item (a lava bucket leaves an empty bucket)
Furnace.fuels = { ["minecraft:coal"] = 80, ["minecraft:charcoal"] = 80, ["minecraft:lava_bucket"] = 1000,
                  ["minecraft:blaze_rod"] = 120, ["minecraft:oak_planks"] = 15, ["minecraft:stick"] = 5 }

-- opts: clock (function -> seconds), speed (2 = twice as fast), types
function Furnace.new(opts)
  local self = Inv.new({ size = 3, types = opts.types or { "minecraft:furnace", "inventory" } })
  self.clock, self.speed = opts.clock, opts.speed or 1
  self.last, self.burn, self.progress = self.clock(), 0, 0
  return setmetatable(self, Furnace)
end

function Furnace:canInsert(slot, name)
  if slot == 1 then return Furnace.recipes[name] ~= nil end
  if slot == 2 then return Furnace.fuels[name] ~= nil end
  return false
end

function Furnace:touch()
  local now = self.clock()
  local dt = (now - self.last) * self.speed
  self.last = now
  local cookTime = 10
  while dt > 1e-9 do
    local inp, out = self.slots[1], self.slots[3]
    local result = inp and Furnace.recipes[inp.name]
    local can = result and (not out or (out.name == result and out.count < Inv.stackOf(result)))
    if self.burn <= 0 and can and self.slots[2] then
      local fuel = self.slots[2]
      self.burn = Furnace.fuels[fuel.name]
      fuel.count = fuel.count - 1
      if fuel.count <= 0 then self.slots[2] = nil end
      if fuel.name == "minecraft:lava_bucket" then self.slots[2] = { name = "minecraft:bucket", count = 1 } end
    end
    if self.burn <= 0 then self.progress = 0; break end
    if not can then self.burn = math.max(0, self.burn - dt); self.progress = 0; break end
    local step = math.min(dt, self.burn, cookTime - self.progress)
    self.burn, self.progress, dt = self.burn - step, self.progress + step, dt - step
    if self.progress >= cookTime - 1e-9 then
      self.progress = 0
      inp.count = inp.count - 1
      if inp.count <= 0 then self.slots[1] = nil end
      if out then out.count = out.count + 1 else self.slots[3] = { name = result, count = 1, displayName = result } end
    end
  end
end

---------------------------------------------------------------------------
-- Tank: a fluid_storage peripheral (a PneumaticCraft small tank): tanks(), pushFluid(), pullFluid().
-- Like CC:Tweaked it reports name and amount only (no capacity). One fluid at a time, `capacity` mB.
---------------------------------------------------------------------------
local Tank = {}
Tank.__index = Tank
Inv.Tank = Tank
Tank.peripheralMethods = { "tanks", "pushFluid", "pullFluid" }
function Tank.new(opts)
  opts = opts or {}
  return setmetatable({ capacity = opts.capacity or 16000, fluid = opts.fluid, amount = opts.amount or 0,
                        types = opts.types or { "pneumaticcraft:small_tank", "fluid_storage" } }, Tank)
end
function Tank:tanks()
  if self.fluid and self.amount > 0 then return { { name = self.fluid, amount = self.amount } } end
  return { { name = "minecraft:empty", amount = 0 } }
end
function Tank:pushFluid(toName, limit, fluidName)
  if not self.net then error("Not on a wired network", 2) end
  local to = self.net:get(toName)
  if not to or not to.fill then error("Target '" .. tostring(toName) .. "' is not a fluid tank", 2) end
  if not self.fluid or self.amount <= 0 or (fluidName and fluidName ~= self.fluid) then return 0 end
  local n = to:fill(self.fluid, math.min(limit or self.amount, self.amount))
  self.amount = self.amount - n
  return n
end
function Tank:pullFluid(fromName, limit, fluidName)
  if not self.net then error("Not on a wired network", 2) end
  local from = self.net:get(fromName)
  if not from or not from.fill then error("Target '" .. tostring(fromName) .. "' is not a fluid tank", 2) end
  return from:pushFluid(self.netName, limit, fluidName)
end
-- test-side: returns how much was taken in
function Tank:fill(fluid, n)
  if self.fluid and self.amount > 0 and self.fluid ~= fluid then return 0 end
  n = math.min(n, self.capacity - self.amount)
  if n <= 0 then return 0 end
  self.fluid, self.amount = fluid, self.amount + n
  return n
end

return Inv
