-- opdrivers.lua  --  reactor drivers: one small interface per kind of reactor, so the control loop never changes.
--   driver.kind                    "passive" | "active"
--   driver:status()                a table of readings (a field is nil when the reactor didn't answer)
--   driver:setActive(on)           true if the call went through
--   driver:setOutput(level)        control rod insertion 0..100 for every rod (guarded; used by a later issue)
--   driver:rods()                  number of control rods, or nil
-- Every device call is guarded: a missing method or a failing call gives nil, never an error.
-- Passive = FE straight from the power tap. Active (coolant -> turbines) reads the same plus coolant/steam; its
-- control (turbines, steam) is a later driver and plugs in here without touching the loop.
local D = {}

local function call(p, m, ...)
  local f = p and p[m]
  if type(f) ~= "function" then return nil end
  local ok, a = pcall(f, ...)
  if ok then return a end
  return nil
end
D.call = call

local Base = {}
Base.__index = Base

function Base:status()
  local p = self.p
  local s = {
    active   = call(p, "getActive"),
    stored   = call(p, "getEnergyStored"),
    cap      = call(p, "getEnergyCapacity"),
    fe       = call(p, "getEnergyProducedLastTick"),
    fuel     = call(p, "getFuelAmount"),
    fuelMax  = call(p, "getFuelAmountMax"),
    waste    = call(p, "getWasteAmount"),
    fuelTemp = call(p, "getFuelTemperature"),
    casing   = call(p, "getCasingTemperature"),
    burn     = call(p, "getFuelConsumedLastTick"),
  }
  s.answers = s.active ~= nil or s.stored ~= nil or s.cap ~= nil
  if s.stored and s.cap and s.cap > 0 then s.buf = s.stored / s.cap end
  if self.kind == "active" then
    s.coolant = call(p, "getCoolantAmount")
    s.hot     = call(p, "getHotFluidAmount")
  end
  return s
end

function Base:setActive(on)
  if type(self.p.setActive) ~= "function" then return false end
  return (pcall(self.p.setActive, on and true or false))
end

function Base:setOutput(level)
  if type(self.p.setAllControlRodLevels) ~= "function" then return false end
  return (pcall(self.p.setAllControlRodLevels, level))
end

function Base:rods()
  local n = call(self.p, "getNumberOfControlRods")
  if type(n) == "number" then return n end
  if type(self.p.getControlRodLevel) ~= "function" then return nil end
  local c = 0
  while c < 64 do
    local ok, lvl = pcall(self.p.getControlRodLevel, c)
    if not ok or lvl == nil then break end
    c = c + 1
  end
  return c > 0 and c or nil
end

function Base:has(method) return type(self.p[method]) == "function" end

-- Pick the driver for a reactor peripheral. Anything that says it is actively cooled gets the active driver.
function D.pick(name)
  local p = peripheral.wrap(name)
  if not p then return nil end
  local kind = call(p, "isActivelyCooled") == true and "active" or "passive"
  return setmetatable({ kind = kind, name = name, p = p }, Base)
end

return D
