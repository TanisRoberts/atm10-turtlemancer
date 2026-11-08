-- sim/placement.lua  --  what block state a turtle's place/placeUp/placeDown gives a block.
--
-- Follows CC:Tweaked 1.21 (branch mc-1.21.x, TurtlePlaceCommand.deploy + TurtlePlayer.setPosition). The turtle acts
-- like a player whose yaw is its heading, and tries these clicks in order, the first that places wins:
--   1. the block in the target cell, clicked on its face toward the turtle   (only places if it is replaceable:
--      a single slab of the same kind becomes a double slab)
--   2. the block one beyond the target, clicked on its face toward the turtle   -> face = opposite of the direction
--   3. (forward only) the block under the target, clicked on top               -> face = up
--   4. the turtle's own cell, clicked on the face toward the target            -> face = the direction
-- A horizontal click is at height 0.45 (the lower half). The clicked face and heading then decide the state.
-- If nothing can be clicked at all (cases 2-4 always have something: the turtle itself), nothing fails here;
-- a plain failure comes from an occupied target cell.
local P = {}

local NAMES = { [0] = "north", "east", "south", "west" }
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
P.facingName = NAMES

-- blocks a torch/wall cannot hang on or be clicked as "solid" support
local SOFT = { "torch$", "_sign$", "^minecraft:water$", "^minecraft:lava$", "_pressure_plate$", "_carpet$", "^minecraft:vine$" }
local function solid(world, x, y, z)
  local blk = world:getBlock(x, y, z)
  if not blk then return world:turtleAt(x, y, z) ~= nil end
  for _, p in ipairs(SOFT) do if blk.name:find(p) then return false end end
  return true
end
local function present(world, x, y, z) return world:getBlock(x, y, z) ~= nil or world:turtleAt(x, y, z) ~= nil end

-- The rule table: first matching pattern wins. rule(ctx) -> state table (and optionally a new block name).
-- ctx = { name, face = "up"|"down"|"north"|"east"|"south"|"west", hitY, heading (0..3), horizontal (bool),
--         canHang(heading) (a solid block beyond the target cell in `heading`), floorOk, ceilOk }
local function half(ctx)
  if ctx.face == "down" then return "top" end
  if ctx.face == "up" then return "bottom" end
  return ctx.hitY > 0.5 and "top" or "bottom"
end
local function axisOf(ctx)
  if ctx.face == "up" or ctx.face == "down" then return "y" end
  return (ctx.heading % 2 == 0) and "z" or "x"
end

P.rules = {
  { "_stairs$",     function(c) return { facing = NAMES[c.heading], half = half(c) } end },
  { "_slab$",       function(c) return { type = half(c) } end },
  { "_fence_gate$", function(c) return { facing = NAMES[c.heading], open = false } end },
  { "hay_block$",   function(c) return { axis = axisOf(c) } end },
  { "_log$",        function(c) return { axis = axisOf(c) } end },
  { "_wood$",       function(c) return { axis = axisOf(c) } end },
  { "chest$",       function(c) return { facing = NAMES[(c.heading + 2) % 4], type = "single" } end },
  { "torch$",       function(c, blk)
      -- forward against a solid block beyond: wall torch, its facing points back at the turtle
      if not c.vertical and c.canHang then
        return { facing = NAMES[(c.heading + 2) % 4] }, (blk.name:gsub("torch$", "wall_torch"))
      end
      if c.floorOk and c.dir ~= "up" then return {} end     -- floor torch on a solid block below
      return nil                                            -- cannot survive here
    end },
}

local function find(name)
  for _, r in ipairs(P.rules) do if name:find(r[1]) then return r[2] end end
end

-- Decide the placement. Returns nil, message (nothing placed) or a table
--   { name =, state =, replace = true (placed into an existing single slab -> double) }
-- b = turtle body (x y z facing), dir = "forward"|"up"|"down", ahead = target x,y,z, existing = block there or nil
function P.place(world, b, dir, itemName, x, y, z, existing)
  local rule = find(itemName)
  local vertical = dir ~= "forward"
  local sx, sy, sz = 0, 0, 0                                  -- step from the turtle toward the target
  if dir == "up" then sy = 1 elseif dir == "down" then sy = -1 else sx, sz = DX[b.facing], DZ[b.facing] end

  -- slab onto a single slab of the same item: a double slab (every click order ends in this)
  if existing then
    if rule and itemName:find("_slab$") and existing.name == itemName and existing.state and existing.state.type ~= "double" then
      return { name = itemName, state = { type = "double" }, replace = true }
    end
    return nil, "Cannot place block here"
  end

  -- which click places it
  local face, hitY
  if present(world, x + sx, y + sy, z + sz) then                          -- 2: block beyond the target
    hitY = 0.45
    face = (dir == "down") and "up" or (dir == "up") and "down" or NAMES[(b.facing + 2) % 4]
  elseif not vertical and present(world, x, y - 1, z) then                -- 3: top of the block under the target
    face, hitY = "up", 1.0
  else                                                                    -- 4: the turtle's own cell
    face = (dir == "down") and "down" or (dir == "up") and "up" or NAMES[b.facing]
    hitY = vertical and (dir == "down" and 0.0 or 1.0) or 0.45
  end

  if not rule then return { name = itemName, state = nil } end
  local ctx = { name = itemName, face = face, hitY = hitY, heading = b.facing, vertical = vertical, dir = dir,
                canHang = (not vertical) and solid(world, x + sx, y + sy, z + sz),
                floorOk = solid(world, x, y - 1, z) }
  local state, newName = rule(ctx, { name = itemName })
  if not state then return nil, "Cannot place block here" end
  return { name = newName or itemName, state = state }
end

return P
