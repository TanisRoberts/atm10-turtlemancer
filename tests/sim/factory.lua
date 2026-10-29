-- sim/factory.lua  --  a Mekanism factory (enriching) behind a feed barrel + hopper, read-only over the cable like the real one.
--   w:factory{ procs = 3|5, feed = <Inv>, out = <Inv>, recipes = { [item] = { n = items per op, out = name, made = count, ticks = 200 } },
--              progress = "rises" (getRecipeProgress > 0 as soon as the input is enough) | "end" (stays 0 until the op is done),
--              energy = 1 (fraction), eject = true, autoSort = true }
-- The hopper moves one item from the feed barrel every 0.4 s into a one-slot hopper and from there into
-- the factory (auto-sort off: process 0's slot first, then the next; on: spread over the slots). An item no
-- recipe takes stays in the hopper for good (`f.hopper`). Lazy like the furnace: state catches up on every call.
local Factory = {}
Factory.__index = Factory

Factory.peripheralMethods = { "getInput", "getOutput", "getRecipeProgress", "getTicksRequired", "getEnergyFilledPercentage",
  "isEjecting", "setEjecting", "isAutoSort", "setAutoSort", "getMode" }
Factory.mainThread = true
local STEP = 0.1

local function slot(it) return it and { name = it.name, count = it.count } or { name = "minecraft:air", count = 0 } end

function Factory.new(opts)
  local self = setmetatable({
    clock = opts.clock, types = opts.types or { "mekanism:advanced_enriching_factory" }, procs = opts.procs or 5,
    feed = opts.feed, out = opts.out, recipes = opts.recipes or {}, progressMode = opts.progress or "rises",
    energy = opts.energy or 1, eject = opts.eject ~= false, autoSort = opts.autoSort ~= false,
    inputs = {}, outputs = {}, prog = {}, hopper = nil, hopperAcc = 0, last = opts.clock(), log = {},
  }, Factory)
  for p = 0, self.procs - 1 do self.prog[p] = 0 end
  return self
end

function Factory:_hop()
  if self.hopper then
    local r = self.recipes[self.hopper.name]
    if r then
      -- choose a slot
      local best
      for p = 0, self.procs - 1 do
        local s = self.inputs[p]
        if not s or s.name == self.hopper.name then
          if not self.autoSort then best = p; break end
          local c = s and s.count or 0
          if not best or c < (self.inputs[best] and self.inputs[best].count or 0) then best = p end
        end
      end
      if best and (not self.inputs[best] or self.inputs[best].count < 64) then
        local s = self.inputs[best] or { name = self.hopper.name, count = 0 }
        s.count = s.count + 1
        self.inputs[best] = s
        self.hopper.count = self.hopper.count - 1
        if self.hopper.count <= 0 then self.hopper = nil end
      end
    end
  end
  if not self.hopper and self.feed then
    for i, it in pairs(self.feed.slots) do
      self.hopper = { name = it.name, count = 1 }
      it.count = it.count - 1
      if it.count <= 0 then self.feed.slots[i] = nil end
      break
    end
  end
end

function Factory:touch()
  local now = self.clock()
  while self.last + STEP <= now + 1e-9 do
    self.last = self.last + STEP
    self.hopperAcc = self.hopperAcc + STEP
    if self.hopperAcc >= 0.4 - 1e-9 then self.hopperAcc = 0; self:_hop() end
    for p = 0, self.procs - 1 do
      local s = self.inputs[p]
      local r = s and self.recipes[s.name]
      local o = self.outputs[p]
      local can = r and s.count >= r.n and (not o or (o.name == r.out and o.count + r.made <= 64))
      if can and self.energy > 0 then
        self.prog[p] = self.prog[p] + STEP * 20
        if self.prog[p] >= (r.ticks or 200) then
          self.prog[p] = 0
          s.count = s.count - r.n
          if s.count <= 0 then self.inputs[p] = nil end
          self.outputs[p] = { name = r.out, count = (o and o.count or 0) + r.made }
        end
      elseif not can then
        self.prog[p] = 0
      end
    end
    if self.eject and self.out then
      for p = 0, self.procs - 1 do
        local o = self.outputs[p]
        if o then
          local n = self.out:insert(o.name, o.count)
          o.count = o.count - n
          if o.count <= 0 then self.outputs[p] = nil end
        end
      end
    end
  end
end

local function check(self, p)
  if type(p) ~= "number" or p < 0 or p >= self.procs or p % 1 ~= 0 then error("Process index out of range", 3) end
end
function Factory:getInput(p) self:touch(); check(self, p); return slot(self.inputs[p]) end
function Factory:getOutput(p) self:touch(); check(self, p); return slot(self.outputs[p]) end
function Factory:getRecipeProgress(p)
  self:touch(); check(self, p)
  local s = self.inputs[p]
  local r = s and self.recipes[s.name]
  if not r or s.count < r.n or self.energy <= 0 then return 0 end
  if self.progressMode == "end" then return 0 end
  return self.prog[p] / (r.ticks or 200) + 0.001      -- "rises at once": above 0 as soon as the input is enough
end
function Factory:getTicksRequired() self:touch(); return 200 end
function Factory:getEnergyFilledPercentage() self:touch(); return self.energy end
function Factory:isEjecting(ty) self:touch(); return self.eject end
function Factory:setEjecting(ty, b) self:touch(); self.eject = b and true or false end
function Factory:isAutoSort() self:touch(); return self.autoSort end
function Factory:setAutoSort(b) self:touch(); self.autoSort = b and true or false end
function Factory:getMode() return "NONE" end

-- test-side: everything in the factory (inputs and outputs) as a total
function Factory:total()
  local n = 0
  for _, s in pairs(self.inputs) do n = n + s.count end
  for _, s in pairs(self.outputs) do n = n + s.count end
  return n
end

return Factory
