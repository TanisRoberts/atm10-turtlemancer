-- sim/ender.lua  --  Ender Storage chests: every chest with the same dye code is the same inventory.
--
--   local es = w:ender()                                   -- the world's registry (made on first use)
--   es:place(0, 64, 0, {"red","blue","white"})             -- an ender chest block in the world (a turtle can suck/drop at it)
--   es:onNet(net, 0, {"red","blue","white"})               -- the same chest on a wired network as "enderstorage:ender_chest_0"
--   es:inv({"red","blue","white"})                         -- the shared inventory itself (give / count / totals ...)
--   es.delay = 2                                           -- optional: items put in at one end show up after 2 s (default 0)
--
-- The code is three dye colours (a table of 3, or "red,blue,white"). Real Ender Storage has no delay; the switch
-- exists for scenarios that want to see a program cope with items that are "in flight". With a delay, room is
-- checked when the items go in, and they land after `delay` seconds (they are lost if the chest filled up meanwhile).
local Inv = require("sim.inv")

local DYES = { white = 1, orange = 1, magenta = 1, light_blue = 1, yellow = 1, lime = 1, pink = 1, gray = 1,
               light_gray = 1, cyan = 1, purple = 1, blue = 1, brown = 1, green = 1, red = 1, black = 1 }

local Ender = {}
Ender.__index = Ender
Ender.TYPE = { "enderstorage:ender_chest", "inventory" }
Ender.BLOCK = "enderstorage:ender_chest"

-- one end of a chest: shares `slots` with the main inventory
local End = setmetatable({}, { __index = Inv })
End.__index = End
function End:clear() self.main.slots = {}; self.slots = self.main.slots end
function End:insert(name, count, toSlot, extra)
  local d = self.reg.delay
  if not d or d <= 0 then return Inv.insert(self, name, count, toSlot, extra) end
  -- room check on a copy, then deliver later
  local scratch = Inv.new{ size = self.nslots }
  for i, s in pairs(self.main.slots) do scratch.slots[i] = { name = s.name, count = s.count, nbt = s.nbt } end
  local put = scratch:insert(name, count, toSlot, extra)
  if put > 0 then
    self.reg.world:after(d, function() Inv.insert(self.main, name, put, nil, extra) end)
  end
  return put
end

function Ender.new(world)
  return setmetatable({ world = world, chests = {}, delay = 0 }, Ender)
end

function Ender.code(code)
  if type(code) == "string" then
    local t = {}
    for c in code:gmatch("[^,%s]+") do t[#t + 1] = c end
    code = t
  end
  if type(code) ~= "table" or #code ~= 3 then error("an ender chest code is three dye colours", 3) end
  for _, c in ipairs(code) do if not DYES[c] then error("not a dye colour: " .. tostring(c), 3) end end
  return table.concat(code, ",")
end

function Ender:inv(code)
  local k = Ender.code(code)
  local m = self.chests[k]
  if not m then
    m = Inv.new{ size = 27, types = Ender.TYPE }
    m.code = k
    self.chests[k] = m
  end
  return m
end

-- a new end (its own object, the shared slots)
function Ender:endOf(code)
  local m = self:inv(code)
  local e = setmetatable({ slots = m.slots, nslots = m.nslots, types = m.types, main = m, reg = self, code = m.code }, End)
  return e
end

-- the chest as a block in the world: returns the block
function Ender:place(x, y, z, code, facing)
  local e = self:endOf(code)
  local blk = self.world:setBlock(x, y, z, { name = Ender.BLOCK, state = { facing = facing or "north" } }, e)
  return blk
end

-- the chest on a wired network under name `enderstorage:ender_chest_<n>` (or an explicit name)
function Ender:onNet(net, n, code)
  local name = type(n) == "string" and n or ("enderstorage:ender_chest_" .. n)
  return net:add(name, self:endOf(code)), name
end

return Ender
