-- sim/reactor.lua  --  an Extreme Reactors 2 reactor (peripheral type BigReactors-Reactor) with a power buffer that
-- fills while it is on and drains with demand, burns fuel, and makes cyanite into its output port.
-- Lazy like the furnace: state catches up to the clock on every call.
--   w:reactor{ prod = FE/t while on, demand = FE/t drained, cap, stored, active, rods, inPort, outPort,
--              rodScale = true (output follows 100 - rod insertion), rodLevel = starting insertion,
--              activelyCooled = true, without = { "getControlRodLevel", ... } methods the device lacks }
local Reactor = {}
Reactor.__index = Reactor

local ALL = { "getActive", "setActive", "getEnergyStored", "getEnergyCapacity", "getEnergyProducedLastTick",
  "getFuelAmount", "getFuelAmountMax", "getWasteAmount", "getFuelTemperature", "getCasingTemperature",
  "getFuelConsumedLastTick", "getControlRodLevel", "setAllControlRodLevels", "getNumberOfControlRods" }

function Reactor.new(opts)
  local self = setmetatable({
    clock = opts.clock, types = { "BigReactors-Reactor" }, prod = opts.prod or 2000, demand = opts.demand or 1000,
    cap = opts.cap or 1000000, stored = opts.stored or 500000, on = opts.active or false, rods = opts.rods or 5,
    inPort = opts.inPort, outPort = opts.outPort, fuel = opts.fuel or 0, fuelMax = opts.fuelMax or 4000, waste = 0,
    cooled = opts.activelyCooled, rodLevel = opts.rodLevel or 100, rodScale = opts.rodScale, wasteAcc = 0, burnAcc = 0, made = 0,
  }, Reactor)
  self.last = self.clock()
  local skip = {}
  for _, m in ipairs(opts.without or {}) do skip[m] = true end
  local ms = {}
  for _, m in ipairs(ALL) do if not skip[m] then ms[#ms + 1] = m end end
  if opts.activelyCooled ~= nil then ms[#ms + 1] = "isActivelyCooled"; ms[#ms + 1] = "getCoolantAmount"; ms[#ms + 1] = "getHotFluidAmount" end
  self.peripheralMethods = ms
  return self
end

function Reactor:output() return self.rodScale and self.prod * (100 - self.rodLevel) / 100 or self.prod end

function Reactor:touch()
  local now = self.clock()
  local dt = now - self.last
  self.last = now
  if dt <= 0 then return end
  -- take fuel from the input port
  if self.inPort then
    for slot, it in pairs(self.inPort.slots) do
      local worth = (it.tags and it.tags["c:storage_blocks/uranium"] and 9) or (it.tags and it.tags["c:ingots/uranium"] and 1)
        or (it.name:find("uranium") and it.name:find("block") and 9) or (it.name:find("uranium") and it.name:find("ingot") and 1) or 0
      if worth > 0 then
        while it.count > 0 and self.fuel + worth * 1000 <= self.fuelMax do it.count = it.count - 1; self.fuel = self.fuel + worth * 1000 end
        if it.count <= 0 then self.inPort.slots[slot] = nil end
      end
    end
  end
  local net = (self.on and self.fuel > 0 and self:output() or 0) - self.demand
  self.stored = math.max(0, math.min(self.cap, self.stored + net * 20 * dt))
  if self.on and self.fuel > 0 then
    self.fuel = math.max(0, self.fuel - 2 * dt)
    self.wasteAcc = self.wasteAcc + dt
    while self.wasteAcc >= 10 do
      self.wasteAcc = self.wasteAcc - 10
      self.made = self.made + 1
      if self.outPort then self.outPort:insert("bigreactors:cyanite_ingot", 1) else self.waste = self.waste + 1000 end
    end
  end
end

function Reactor:getActive() self:touch(); return self.on end
function Reactor:setActive(b) self:touch(); self.on = b and true or false end
function Reactor:getEnergyStored() self:touch(); return self.stored end
function Reactor:getEnergyCapacity() self:touch(); return self.cap end
function Reactor:getEnergyProducedLastTick() self:touch(); return (self.on and self.fuel > 0) and self:output() or 0 end
function Reactor:getFuelAmount() self:touch(); return self.fuel end
function Reactor:getFuelAmountMax() return self.fuelMax end
function Reactor:getWasteAmount() self:touch(); return self.waste end
function Reactor:getFuelTemperature() self:touch(); return self.on and 600 or 20 end
function Reactor:getCasingTemperature() self:touch(); return self.on and 300 or 20 end
function Reactor:getFuelConsumedLastTick() return self.on and 0.1 or 0 end
function Reactor:getControlRodLevel(i)
  if type(i) ~= "number" or i < 0 or i >= self.rods then error("Control rod index out of range", 2) end
  return self.rodLevel
end
function Reactor:setAllControlRodLevels(n) self.rodLevel = n end
function Reactor:getNumberOfControlRods() return self.rods end
function Reactor:isActivelyCooled() return self.cooled == true end
function Reactor:getCoolantAmount() return 1000 end
function Reactor:getHotFluidAmount() return 0 end

return Reactor
