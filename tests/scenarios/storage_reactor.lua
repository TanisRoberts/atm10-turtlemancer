-- Storage: the Reactor fuel job (#104). Chest kept at REACTOR_FUEL_KEEP units, blocks first then ingots, never emptied,
-- reported on "tanis-operator".
local cc = require("sim.cc")
local T = require("sim.test")

local BARREL = { "minecraft:barrel", "inventory" }
local CHEST = "enderstorage:ender_chest_0"
local BLOCK, INGOT = "bigreactors:uranium_block", "bigreactors:uranium_ingot"
local BTAGS, ITAGS = { ["c:storage_blocks/uranium"] = true }, { ["c:ingots/uranium"] = true }

-- Storage with an input (0), output (1), a store (2) and an ender chest assigned as Reactor fuel; a listener on rednet
local function base(opts)
  opts = opts or {}
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 2 do inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = BARREL }) end
  local chest = net:add(CHEST, cc.Inv.new{ size = 27, types = { "enderstorage:ender_chest", "inventory" } })
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:monitor("right", 57, 24)
  c:installRole("storage")
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1", reactorFuels = { CHEST },
    names = { [CHEST] = "Reactor 1" } })
  if opts.env then c:writeFile("storage.env", opts.env) end
  local l = w:computer{ id = 2, label = "Listener" }
  l:attach("top", cc.wireless{ ender = true })
  l:writeFile("l.lua", "rednet.open('top')\nn = 0\nwhile true do local _, m = rednet.receive('tanis-operator'); last = m; n = n + 1 end")
  l:run("l")
  return w, c, inv, chest, l
end
local function last(l) return l.env._G.last end

T.test("reactor fuel: filled to 64 units from blocks first, then ingots when the blocks run out", function()
  local w, c, inv, chest = base()
  inv[2]:give(BLOCK, 3, nil, { tags = BTAGS })
  inv[2]:give(INGOT, 100, nil, { tags = ITAGS })
  c:run("storage")
  T.waitFor(w, function() return chest:count(INGOT) > 0 end, 60, "chest never got ingots")
  w:run(10)
  T.eq(chest:count(BLOCK), 3, "all three blocks first")
  T.eq(chest:count(INGOT), 37, "ingots for the rest: 27 + 37 = 64")
  T.eq(inv[2]:count(INGOT), 63)
  T.eq(inv[2]:count(BLOCK), 0)
end)

T.test("reactor fuel: blocks alone fill it, overshooting by less than one block", function()
  local w, c, inv, chest = base()
  inv[2]:give(BLOCK, 20, nil, { tags = BTAGS })
  inv[2]:give(INGOT, 100, nil, { tags = ITAGS })
  c:run("storage")
  T.waitFor(w, function() return chest:count(BLOCK) > 0 end, 60, "chest never got blocks")
  w:run(10)
  T.eq(chest:count(BLOCK), 8, "8 blocks = 72 units, the first whole count at or over 64")
  T.eq(chest:count(INGOT), 0)
end)

T.test("reactor fuel: topped up after the reactor takes some, and nothing is pulled out of it", function()
  local w, c, inv, chest = base()
  inv[2]:give(INGOT, 200, nil, { tags = ITAGS })
  c:run("storage")
  T.waitFor(w, function() return chest:count(INGOT) == 64 end, 60, "never reached 64")
  chest:extract(1, 30)                                  -- the Operator feeds the reactor
  chest:give("minecraft:dirt", 5)                       -- something that is not fuel stays put
  T.waitFor(w, function() return chest:count(INGOT) == 64 end, 60, "never topped up")
  T.eq(chest:count("minecraft:dirt"), 5, "non-fuel left alone")
  -- a full re-sort and /tidy must not touch it either
  c:type("/tidy"); c:key(257); w:run(20)
  c:type("/rescan"); c:key(257); w:run(20)
  T.eq(chest:count(INGOT), 64)
  T.eq(inv[2]:count(INGOT), 106, "200 - 64 - the 30 refilled")
end)

T.test("reactor fuel: more in the chest than keep is left alone, never taken back", function()
  local w, c, inv, chest = base()
  chest:give(INGOT, 200, nil, { tags = ITAGS })        -- 4 stacks' worth: well over 64 units
  inv[2]:give(INGOT, 50, nil, { tags = ITAGS })
  c:run("storage")
  w:run(40)
  T.eq(chest:count(INGOT), 200)
  T.eq(inv[2]:count(INGOT), 50)
end)

T.test("reactor fuel: no fuel left means supply 0, best nil, and the chest is left as it is", function()
  local w, c, inv, chest, l = base()
  chest:give(INGOT, 10, nil, { tags = ITAGS })
  c:run("storage")
  w:run(25)
  local m = last(l)
  T.eq(m.type, "reactor_fuel")
  T.eq(m.supply, 0)
  T.eq(m.best, nil)
  T.eq(chest:count(INGOT), 10)
  T.eq(#m.chests, 1)
  T.eq(m.chests[1].name, CHEST)
  T.eq(m.chests[1].label, "Reactor 1")
  T.eq(m.chests[1].units, 10)
  T.eq(m.chests[1].keep, 64)
  T.eq(m.chests[1].low, 16)
end)

T.test("reactor fuel: the report counts what is left in storage and names the fuel it stocks with", function()
  local w, c, inv, chest, l = base()
  inv[2]:give(BLOCK, 3, nil, { tags = BTAGS })
  inv[2]:give(INGOT, 400, nil, { tags = ITAGS })
  c:run("storage")
  w:run(25)
  local m = last(l)
  -- 3 blocks + 37 ingots went in; 363 ingots remain
  T.eq(m.supply, 363)
  T.eq(m.best, INGOT)
  T.eq(m.chests[1].units, 64)
  local n1 = l.env._G.n
  w:run(30)
  T.eq(l.env._G.n - n1 >= 2 and true or false, true, "reported again every 10 s")
end)

T.test("reactor fuel: REACTOR_FUEL and REACTOR_FUEL_KEEP take effect live", function()
  local w, c, inv, chest = base()
  inv[2]:give(INGOT, 200, nil, { tags = ITAGS })
  inv[2]:give("minecraft:coal", 100)
  c:run("storage")
  T.waitFor(w, function() return chest:count(INGOT) == 64 end, 60, "never reached 64")
  local env = c:readFile("storage.env")
  T.eq(env:find("REACTOR_FUEL_KEEP=64", 1, true) ~= nil, true, "storage.env got the keys")
  c:writeFile("storage.env", (env:gsub("REACTOR_FUEL_KEEP=64", "REACTOR_FUEL_KEEP=100"):gsub("REACTOR_FUEL=[^\n]*", "REACTOR_FUEL=minecraft:coal=2,#c:ingots/uranium=1")))
  T.waitFor(w, function() return chest:count("minecraft:coal") > 0 end, 60, "never stocked coal after the list changed")
  w:run(10)
  T.eq(chest:count("minecraft:coal"), 18, "coal is worth 2: 64 + 36 = 100")
  T.eq(chest:count(INGOT), 64)
end)

T.test("reactor fuel: with no Reactor fuel chest assigned, nothing is reported", function()
  local w, c, inv, chest, l = base()
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  inv[2]:give(INGOT, 20, nil, { tags = ITAGS })
  c:run("storage")
  w:run(30)
  T.eq(l.env._G.n, 0)
  T.eq(chest:count(INGOT), 0)
end)
