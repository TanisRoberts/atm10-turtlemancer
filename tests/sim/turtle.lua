-- sim/turtle.lua  --  a turtle body in the world's voxel grid, and the `turtle` API for its program.
--
--   local t = w:turtle{ id = 7, label = "Canary-01", x = 0, y = 64, z = 0, facing = 0, fuel = 5000,
--                       left = "minecraft:diamond_pickaxe", right = "computercraft:wireless_modem_advanced" }
--
-- Facing 0 = north (-z), 1 = east (+x), 2 = south (+z), 3 = west (-x). Blocks live in world:setBlock.
local Inv = require("sim.inv")

local Turtle = {}

local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }

-- What a block drops (default: itself). A block table may carry its own `drop`.
Turtle.drops = {
  ["minecraft:stone"] = "minecraft:cobblestone", ["minecraft:deepslate"] = "minecraft:cobbled_deepslate",
  ["minecraft:grass_block"] = "minecraft:dirt",
  ["minecraft:iron_ore"] = "minecraft:raw_iron", ["minecraft:deepslate_iron_ore"] = "minecraft:raw_iron",
  ["minecraft:copper_ore"] = "minecraft:raw_copper", ["minecraft:deepslate_copper_ore"] = "minecraft:raw_copper",
  ["minecraft:gold_ore"] = "minecraft:raw_gold", ["minecraft:deepslate_gold_ore"] = "minecraft:raw_gold",
  ["minecraft:coal_ore"] = "minecraft:coal", ["minecraft:deepslate_coal_ore"] = "minecraft:coal",
  ["minecraft:diamond_ore"] = "minecraft:diamond", ["minecraft:deepslate_diamond_ore"] = "minecraft:diamond",
}
Turtle.unbreakable = { ["minecraft:bedrock"] = true }
-- seconds of smelting a unit of fuel is worth in turtle fuel
Turtle.fuelValue = { ["minecraft:coal"] = 80, ["minecraft:charcoal"] = 80, ["minecraft:lava_bucket"] = 1000,
                     ["minecraft:blaze_rod"] = 120, ["minecraft:stick"] = 5, ["minecraft:oak_planks"] = 15,
                     ["minecraft:coal_block"] = 800, ["mekanism:bio_fuel"] = 5, ["minecraft:oak_log"] = 15 }
-- placed blocks that carry an inventory
Turtle.containers = {
  ["minecraft:barrel"] = function() return Inv.new({ size = 27, types = { "minecraft:barrel", "inventory" } }) end,
  ["minecraft:chest"] = function() return Inv.new({ size = 27 }) end,
}
local NOT_BLOCKS = { "_ingot$", "^minecraft:raw_", "_pickaxe$", "_axe$", "_shovel$", "bucket$", "^minecraft:coal$",
  "^minecraft:diamond$", "^minecraft:stick$", "_dust$", "_nugget$", "modem", "chunk_controller", "^minecraft:charcoal$" }
local function placeable(name)
  for _, p in ipairs(NOT_BLOCKS) do if name:find(p) then return false end end
  return true
end

local function upgradeDevice(name)
  if name:find("modem") then
    return require("sim.cc").wireless({ ender = name:find("advanced") ~= nil or name:find("ender") ~= nil })
  elseif name:find("chunk_controller") then
    return { types = { "chunky" }, peripheralMethods = {} }
  end
end

function Turtle.attach(world, c, opts)
  local b = { world = world, comp = c, x = opts.x or 0, y = opts.y or 64, z = opts.z or 0, facing = opts.facing or 0,
              fuel = opts.fuel or 0, fuelLimit = opts.fuelLimit or 20000, slots = {}, sel = 1, up = {} }
  c.body = b
  c.pos = nil
  world.turtles[#world.turtles + 1] = b
  b.inv = Inv.new({ size = 16 })
  -- b.slots is b.inv.slots: stacks are { name, count }
  b.slots = b.inv.slots
  function b:equip(side, name)
    self.up[side] = name
    local dev = name and upgradeDevice(name)
    if dev then c:attach(side, dev) elseif c.sides[side] then c:detach(side) end
  end
  b:equip("left", opts.left)
  b:equip("right", opts.right)
  for slot, st in pairs(opts.items or {}) do b.slots[slot] = { name = st[1], count = st[2] } end
  -- the turtle's terminal is the small one; position is available to GPS through c.body
  return b
end

-- Game time each action takes (seconds). Anything else is instant, like turtle.select.
Turtle.cost = { forward = 0.4, back = 0.4, up = 0.4, down = 0.4, turnLeft = 0.4, turnRight = 0.4,
                dig = 0.4, digUp = 0.4, digDown = 0.4, default = 0.05 }
local INSTANT = { select = true, getSelectedSlot = true, getItemCount = true, getItemSpace = true,
                  getItemDetail = true, getFuelLevel = true, getFuelLimit = true }

function Turtle.api(world, c)
  local b = c.body
  local T = {}
  local function ahead(dir)
    if dir == "up" then return b.x, b.y + 1, b.z end
    if dir == "down" then return b.x, b.y - 1, b.z end
    local f = dir == "back" and (b.facing + 2) % 4 or b.facing
    return b.x + DX[f], b.y, b.z + DZ[f]
  end
  local function blockAt(dir)
    local x, y, z = ahead(dir)
    local t = world:turtleAt(x, y, z)
    if t then return { name = "computercraft:turtle_advanced", turtle = t } end
    return world:getBlock(x, y, z)
  end
  local function tool()
    for _, side in ipairs({ "left", "right" }) do
      local u = b.up[side]
      if u and (u:find("_pickaxe$") or u:find("_axe$") or u:find("_shovel$")) then return u end
    end
  end
  local function give(name, count)
    local left = count - b.inv:insert(name, count)
    return left
  end

  local function move(dir)
    return function()
      if b.fuel ~= "unlimited" and b.fuel <= 0 then return false, "Out of fuel" end
      local x, y, z = ahead(dir)
      if blockAt(dir) then return false, "Movement obstructed" end
      b.x, b.y, b.z = x, y, z
      if b.fuel ~= "unlimited" then b.fuel = b.fuel - 1 end
      return true
    end
  end
  T.forward, T.back, T.up, T.down = move("forward"), move("back"), move("up"), move("down")
  function T.turnLeft() b.facing = (b.facing + 3) % 4; return true end
  function T.turnRight() b.facing = (b.facing + 1) % 4; return true end

  local function detect(dir) return function() return blockAt(dir) ~= nil end end
  T.detect, T.detectUp, T.detectDown = detect("forward"), detect("up"), detect("down")
  local function inspect(dir)
    return function()
      local blk = blockAt(dir)
      if not blk then return false, "No block to inspect" end
      return true, { name = blk.name, state = blk.state or {}, tags = blk.tags or {} }
    end
  end
  T.inspect, T.inspectUp, T.inspectDown = inspect("forward"), inspect("up"), inspect("down")

  local function dig(dir)
    return function()
      local blk = blockAt(dir)
      if not blk then return false, "Nothing to dig here" end
      if blk.turtle then return false, "Cannot break block" end
      if not tool() then return false, "No tool to dig with" end
      if blk.unbreakable or Turtle.unbreakable[blk.name] then return false, "Unbreakable block detected" end
      local x, y, z = ahead(dir)
      world:setBlock(x, y, z, nil)
      local drop = blk.drop or Turtle.drops[blk.name] or blk.name
      b.dug = (b.dug or 0) + 1
      give(drop, 1)
      if blk.inv then for _, s in pairs(blk.inv.slots) do give(s.name, s.count) end end
      return true
    end
  end
  T.dig, T.digUp, T.digDown = dig("forward"), dig("up"), dig("down")

  local function attack() return false, "Nothing to attack here" end
  T.attack, T.attackUp, T.attackDown = attack, attack, attack

  function T.select(n)
    if type(n) ~= "number" or n < 1 or n > 16 then error("Slot number " .. tostring(n) .. " out of range", 2) end
    b.sel = n
    return true
  end
  function T.getSelectedSlot() return b.sel end
  local function slotArg(n)
    n = n or b.sel
    if n < 1 or n > 16 then error("Slot number " .. n .. " out of range", 3) end
    return n
  end
  function T.getItemCount(n) local s = b.slots[slotArg(n)]; return s and s.count or 0 end
  function T.getItemSpace(n)
    local s = b.slots[slotArg(n)]
    if not s then return 64 end
    return Inv.stackOf(s.name) - s.count
  end
  function T.getItemDetail(n)
    local s = b.slots[slotArg(n)]
    if not s then return nil end
    return { name = s.name, count = s.count }
  end
  function T.transferTo(to, count)
    local from = b.slots[b.sel]
    if not from then return true end
    local dest = b.slots[to]
    if dest and dest.name ~= from.name then return false end
    local n = math.min(count or from.count, from.count, Inv.stackOf(from.name) - (dest and dest.count or 0))
    if n <= 0 then return false end
    if dest then dest.count = dest.count + n else b.slots[to] = { name = from.name, count = n } end
    from.count = from.count - n
    if from.count <= 0 then b.slots[b.sel] = nil end
    return true
  end
  function T.getFuelLevel() return b.fuel end
  function T.getFuelLimit() return b.fuel == "unlimited" and "unlimited" or b.fuelLimit end
  function T.refuel(count)
    local s = b.slots[b.sel]
    if not s then return false, "No items to combust" end
    local v = Turtle.fuelValue[s.name]
    if not v then return false, "Items not combustible" end
    if b.fuel == "unlimited" then return true end
    local n = math.min(count or s.count, s.count)
    local used = 0
    while used < n and b.fuel + v <= b.fuelLimit do b.fuel = b.fuel + v; used = used + 1 end
    s.count = s.count - used
    local name = s.name
    if s.count <= 0 then b.slots[b.sel] = nil end
    if name == "minecraft:lava_bucket" and used > 0 then give("minecraft:bucket", used) end
    return true
  end

  local function container(dir)
    local blk = blockAt(dir)
    return blk and blk.inv
  end
  local function drop(dir)
    return function(count)
      local s = b.slots[b.sel]
      if not s then return false, "No items to drop" end
      local inv = container(dir)
      local n = math.min(count or s.count, s.count)
      if inv then
        local put = inv:insert(s.name, n)
        if put == 0 then return false, "No space for items" end
        s.count = s.count - put
      elseif blockAt(dir) == nil then
        s.count = s.count - n                      -- on the ground
        b.dropped = (b.dropped or 0) + n
      else
        return false, "No space for items"
      end
      if s.count <= 0 then b.slots[b.sel] = nil end
      return true
    end
  end
  T.drop, T.dropUp, T.dropDown = drop("forward"), drop("up"), drop("down")
  local function suck(dir)
    return function(count)
      local inv = container(dir)
      if not inv then return false, "No items to take" end
      inv:touch()
      for i = 1, inv.nslots do
        local s = inv.slots[i]
        if s then
          local want = math.min(count or s.count, s.count, Inv.stackOf(s.name))
          -- like CC: the selected slot fills first, then any other
          local put = b.inv:insert(s.name, want, b.sel)
          if put < want then put = put + b.inv:insert(s.name, want - put) end
          if put > 0 then inv:extract(i, put); return true end
        end
      end
      return false, "No items to take"
    end
  end
  T.suck, T.suckUp, T.suckDown = suck("forward"), suck("up"), suck("down")

  local function place(dir)
    return function()
      local s = b.slots[b.sel]
      if not s then return false, "No items to place" end
      local x, y, z = ahead(dir)
      local blk = blockAt(dir)
      if s.name == "minecraft:bucket" then
        if blk and blk.name == "minecraft:lava" then
          world:setBlock(x, y, z, nil)
          s.count = s.count - 1
          if s.count <= 0 then b.slots[b.sel] = nil end
          give("minecraft:lava_bucket", 1)
          return true
        end
        return false, "Cannot place item here"
      end
      if blk then return false, "Cannot place block here" end
      if not placeable(s.name) then return false, "Cannot place item here" end
      local made = Turtle.containers[s.name]
      world:setBlock(x, y, z, { name = s.name }, made and made() or nil)
      s.count = s.count - 1
      if s.count <= 0 then b.slots[b.sel] = nil end
      return true
    end
  end
  T.place, T.placeUp, T.placeDown = place("forward"), place("up"), place("down")

  local function equip(side)
    return function()
      local s = b.slots[b.sel]
      local old = b.up[side]
      if not s and not old then return false, "Nothing to equip" end
      local new
      if s then
        new = s.name
        s.count = s.count - 1
        if s.count <= 0 then b.slots[b.sel] = nil end
      end
      b:equip(side, new)
      if old then give(old, 1) end
      return true
    end
  end
  T.equipLeft, T.equipRight = equip("left"), equip("right")
  function T.compare() return false end
  T.compareUp, T.compareDown, T.compareTo = T.compare, T.compare, T.compare

  -- Every action takes game time: wait for it (events for other coroutines keep flowing), then act.
  local seq = 0
  local api = {}
  for name, fn in pairs(T) do
    if INSTANT[name] then
      api[name] = fn
    else
      local cost = Turtle.cost[name] or Turtle.cost.default
      api[name] = function(...)
        seq = seq + 1
        local mine, gen = seq, c.gen
        world:after(cost, function()
          if c.alive and c.gen == gen then c:_queue("turtle_response", mine) end
        end)
        repeat
          local ev = table.pack(coroutine.yield("turtle_response"))
          if ev[1] == "terminate" then error("Terminated", 0) end
        until ev[2] == mine
        return fn(...)
      end
    end
  end
  return api
end

return Turtle
