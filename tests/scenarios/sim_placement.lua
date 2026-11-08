-- The simulator's turtle placement: block states from the clicked face and heading (sim/placement.lua).
-- Rules read from CC:Tweaked mc-1.21.x TurtlePlaceCommand / TurtlePlayer; see tests/README.md.
local cc = require("sim.cc")
local T  = require("sim.test")

local NAMES = { [0] = "north", "east", "south", "west" }
local OPP   = { [0] = "south", "west", "north", "east" }

-- The turtle hangs in air at (0,70,0) facing `heading` (0 north). Forward target = (dx,70,dz); below it (dx,69,dz).
-- `setup(w)` builds the surroundings; `body` is the Lua the turtle runs (slot 1 = `item` x `count`, slot 2 = stone).
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local function trial(item, heading, setup, body, count)
  local w = cc.world()
  if setup then setup(w, DX[heading], DZ[heading]) end
  local c = w:turtle{ id = 1, label = "Weaver-01", x = 0, y = 70, z = 0, facing = heading, fuel = 1000,
                      left = "minecraft:diamond_pickaxe",
                      items = { [1] = { item, count or 8 }, [2] = { "minecraft:stone", 8 } } }
  c:writeFile("t.lua", "turtle.select(1)\n_G.res = {}\n" .. body)
  c:run("t")
  w:run(60)
  if c.error then error("turtle program crashed:\n" .. c.error, 2) end
  return w, c
end
local function state(w, x, y, z)
  local b = w:getBlock(x, y, z)
  T.truthy(b, ("no block at %d,%d,%d"):format(x, y, z))
  return b
end
local function stairs(w, x, y, z, name, facing, half)
  local b = state(w, x, y, z)
  T.eq(b.name, name, "block name")
  T.eq(b.state.facing, facing, "stair facing")
  T.eq(b.state.half, half, "stair half")
end
local ST = "minecraft:sandstone_stairs"

T.test("placement: stairs placeDown with a block under the target are bottom half, all four facings", function()
  for h = 0, 3 do
    local w = trial(ST, h, function(w) w:setBlock(0, 68, 0, "minecraft:stone") end, "res.ok = turtle.placeDown()")
    stairs(w, 0, 69, 0, ST, NAMES[h], "bottom")
  end
end)

T.test("placement: stairs placeDown over air are top half (clicks the turtle's underside), all four facings", function()
  for h = 0, 3 do
    local w = trial(ST, h, nil, "res.ok = turtle.placeDown()")
    stairs(w, 0, 69, 0, ST, NAMES[h], "top")
  end
end)

T.test("placement: stairs placed forward are always bottom half, whatever is under, beyond or nowhere", function()
  for h = 0, 3 do
    local dx, dz = DX[h], DZ[h]
    -- air under the target, nothing beyond: bottom (the turtle's own cell is clicked)
    local w = trial(ST, h, nil, "res.ok = turtle.place()")
    stairs(w, dx, 70, dz, ST, NAMES[h], "bottom")
    -- block under the target
    w = trial(ST, h, function(w, dx, dz) w:setBlock(dx, 69, dz, "minecraft:stone") end, "res.ok = turtle.place()")
    stairs(w, dx, 70, dz, ST, NAMES[h], "bottom")
    -- block beyond the target
    w = trial(ST, h, function(w, dx, dz) w:setBlock(2 * dx, 70, 2 * dz, "minecraft:stone") end, "res.ok = turtle.place()")
    stairs(w, dx, 70, dz, ST, NAMES[h], "bottom")
  end
end)

T.test("placement: stairs placeUp: top half under a block, bottom half over air (mirror image)", function()
  for h = 0, 3 do
    local w = trial(ST, h, function(w) w:setBlock(0, 72, 0, "minecraft:stone") end, "res.ok = turtle.placeUp()")
    stairs(w, 0, 71, 0, ST, NAMES[h], "top")
    w = trial(ST, h, nil, "res.ok = turtle.placeUp()")
    stairs(w, 0, 71, 0, ST, NAMES[h], "bottom")
  end
end)

T.test("placement: top-half stair with a block under it: place the stair first, fill below from the side", function()
  -- the stair goes down at (0,69,0) over air (top half); then the turtle walks round and puts stone at (0,68,0)
  local w, c = trial(ST, 1, nil, [[
    turtle.placeDown()            -- top half stair at 0,69,0
    turtle.select(2)
    turtle.forward() turtle.down() turtle.down()   -- now at 1,68,0 facing east
    turtle.turnLeft() turtle.turnLeft()            -- face west
    res.ok = turtle.place()                        -- stone at 0,68,0
    res.insp = { turtle.up() }
  ]])
  stairs(w, 0, 69, 0, ST, "east", "top")
  T.eq(state(w, 0, 68, 0).name, "minecraft:stone")
end)

T.test("placement: turtle.inspect returns the state", function()
  local w, c = trial(ST, 3, nil, [[
    turtle.placeDown()
    local ok, d = turtle.inspectDown()
    res.name, res.facing, res.half = d.name, d.state.facing, d.state.half
  ]])
  T.eq(c.G.res.name, ST)
  T.eq(c.G.res.facing, "west")
  T.eq(c.G.res.half, "top")
end)

local SLAB = "minecraft:sandstone_slab"
T.test("placement: slabs - bottom over a block, top over air, forward is bottom", function()
  local w = trial(SLAB, 0, function(w) w:setBlock(0, 68, 0, "minecraft:stone") end, "turtle.placeDown()")
  T.eq(state(w, 0, 69, 0).state.type, "bottom")
  w = trial(SLAB, 0, nil, "turtle.placeDown()")
  T.eq(state(w, 0, 69, 0).state.type, "top")
  w = trial(SLAB, 0, nil, "turtle.place()")
  T.eq(state(w, 0, 69 + 1, -1).state.type, "bottom")
  w = trial(SLAB, 0, function(w) w:setBlock(0, 72, 0, "minecraft:stone") end, "turtle.placeUp()")
  T.eq(state(w, 0, 71, 0).state.type, "top")
  w = trial(SLAB, 0, nil, "turtle.placeUp()")
  T.eq(state(w, 0, 71, 0).state.type, "bottom")
end)

T.test("placement: a second slab placed into a single slab makes a double (and costs one more item)", function()
  for _, setup in ipairs({ function(w) w:setBlock(0, 68, 0, "minecraft:stone") end, false }) do
    local w, c = trial(SLAB, 0, setup or nil, "turtle.placeDown() turtle.placeDown() res.left = turtle.getItemCount(1)", 8)
    T.eq(state(w, 0, 69, 0).state.type, "double")
    T.eq(c.G.res.left, 6)
  end
  -- forward, onto a bottom slab and a top slab
  local w = trial(SLAB, 0, nil, "turtle.place() turtle.place()")
  T.eq(state(w, 0, 70, -1).state.type, "double")
  -- a third one does not fit, nor does a different slab
  local w2, c2 = trial(SLAB, 0, nil, "turtle.placeDown() turtle.placeDown() res.third = turtle.placeDown() res.left = turtle.getItemCount(1)")
  T.falsy(c2.G.res.third)
  T.eq(c2.G.res.left, 6)
  local w3, c3 = trial("minecraft:stone_slab", 0, function(w) w:setBlock(0, 69, 0, { name = "minecraft:sandstone_slab", state = { type = "bottom" } }) end,
    "res.ok = turtle.placeDown()")
  T.falsy(c3.G.res.ok)
  T.eq(state(w3, 0, 69, 0).state.type, "bottom")
  -- digging a double slab gives two
  local w4, c4 = trial(SLAB, 0, nil, "turtle.placeDown() turtle.placeDown() turtle.digDown() res.n = turtle.getItemCount(1)", 8)
  T.eq(c4.G.res.n, 8)
end)

T.test("placement: hay and logs - axis from the clicked face", function()
  for _, item in ipairs({ "minecraft:hay_block", "minecraft:oak_log", "minecraft:stripped_oak_log" }) do
    -- placeDown / placeUp: y
    local w = trial(item, 1, function(w) w:setBlock(0, 68, 0, "minecraft:stone") end, "turtle.placeDown()")
    T.eq(state(w, 0, 69, 0).state.axis, "y")
    w = trial(item, 1, nil, "turtle.placeDown()")
    T.eq(state(w, 0, 69, 0).state.axis, "y")
    w = trial(item, 1, nil, "turtle.placeUp()")
    T.eq(state(w, 0, 71, 0).state.axis, "y")
    for h = 0, 3 do
      local want = (h % 2 == 0) and "z" or "x"
      -- forward with a block beyond: clicks its side face: the heading's axis
      w = trial(item, h, function(w, dx, dz) w:setBlock(2 * dx, 70, 2 * dz, "minecraft:stone") end, "turtle.place()")
      T.eq(state(w, DX[h], 70, DZ[h]).state.axis, want, item .. " beyond, heading " .. h)
      -- nothing beyond and nothing below: the turtle's own cell is clicked: the heading's axis
      w = trial(item, h, nil, "turtle.place()")
      T.eq(state(w, DX[h], 70, DZ[h]).state.axis, want, item .. " nothing around, heading " .. h)
      -- nothing beyond but a block under the target: it is clicked on top, so the pillar stands upright
      w = trial(item, h, function(w, dx, dz) w:setBlock(dx, 69, dz, "minecraft:stone") end, "turtle.place()")
      T.eq(state(w, DX[h], 70, DZ[h]).state.axis, "y", item .. " block under, heading " .. h)
    end
  end
end)

T.test("placement: fence gates face the heading, chests face back at the turtle", function()
  for h = 0, 3 do
    local w = trial("minecraft:oak_fence_gate", h, function(w) w:setBlock(0, 68, 0, "minecraft:stone") end, "turtle.placeDown()")
    T.eq(state(w, 0, 69, 0).state.facing, NAMES[h], "gate")
    w = trial("minecraft:oak_fence_gate", h, nil, "turtle.place()")
    T.eq(state(w, DX[h], 70, DZ[h]).state.facing, NAMES[h], "gate forward")
    w = trial("minecraft:chest", h, nil, "turtle.place()")
    local b = state(w, DX[h], 70, DZ[h])
    T.eq(b.state.facing, OPP[h], "chest")
    T.truthy(b.inv, "a chest placed by a turtle still has its inventory")
    w = trial("minecraft:chest", h, nil, "turtle.placeDown()")
    T.eq(state(w, 0, 69, 0).state.facing, OPP[h], "chest down")
  end
end)

T.test("placement: wall torches hang on the block beyond, facing back at the turtle; floor torches stay floor", function()
  for h = 0, 3 do
    local w, c = trial("minecraft:torch", h, function(w, dx, dz) w:setBlock(2 * dx, 70, 2 * dz, "minecraft:stone") end, "turtle.place()")
    local b = state(w, DX[h], 70, DZ[h])
    T.eq(b.name, "minecraft:wall_torch")
    T.eq(b.state.facing, OPP[h], "wall torch facing")
    -- digging it gives the torch item back
    w, c = trial("minecraft:torch", h, function(w, dx, dz) w:setBlock(2 * dx, 70, 2 * dz, "minecraft:stone") end,
      "turtle.place() turtle.dig() res.n = turtle.getItemCount(1)")
    T.eq(c.G.res.n, 8)
    -- nothing to hang on: floor torch if there is floor, else it fails
    w = trial("minecraft:torch", h, function(w, dx, dz) w:setBlock(dx, 69, dz, "minecraft:stone") end, "turtle.place()")
    T.eq(state(w, DX[h], 70, DZ[h]).name, "minecraft:torch")
    w, c = trial("minecraft:torch", h, nil, "res.ok = turtle.place()")
    T.falsy(c.G.res.ok)
  end
  local w = trial("minecraft:torch", 0, function(w) w:setBlock(0, 68, 0, "minecraft:stone") end, "turtle.placeDown()")
  T.eq(state(w, 0, 69, 0).name, "minecraft:torch")
  local w2, c2 = trial("minecraft:torch", 0, function(w) w:setBlock(0, 72, 0, "minecraft:stone") end, "res.ok = turtle.placeUp()")
  T.falsy(c2.G.res.ok, "a torch cannot hang from a ceiling")
end)
