-- The Operator moves the items at the reactor: fuel chest -> inlet port (blocks before ingots, never more than the
-- reactor has room for), outlet port -> waste chest, fuel held back while waste can't clear; chests worked out for
-- one reactor; Storage's reactor_fuel report in the status broadcast.
local cc = require("sim.cc")
local T  = require("sim.test")

local PORT = { "bigreactors:reactoraccessport", "inventory" }
local ENDER = { "enderstorage:ender_chest", "inventory" }
local BLOCK, INGOT = "mekanism:block_uranium", "mekanism:ingot_uranium"
local TB, TI = { tags = { ["c:storage_blocks/uranium"] = true } }, { tags = { ["c:ingots/uranium"] = true } }
local function port() return cc.Inv.new{ size = 9, types = PORT } end
local function ender(size) return cc.Inv.new{ size = size or 27, types = ENDER } end

-- One reactor, its two ports and two ender chests (fuel_0, waste_1). opts.fuelMax, opts.fuel, opts.wasteSize, opts.cfg = false (no saved config)
local function room(opts)
  opts = opts or {}
  local w = cc.world(); local net = w:net()
  local inP, outP = port(), port()
  local r = w:reactor{ stored = 100000, active = true, demand = 5000, inPort = inP, outPort = outP, fuel = opts.fuel or 0, fuelMax = opts.fuelMax or 20000 }
  local fuelC, wasteC = ender(), ender(opts.wasteSize)
  net:add("BigReactors-Reactor_0", r); net:add("port_in", inP); net:add("port_out", outP)
  net:add("enderstorage:ender_chest_0", fuelC); net:add("enderstorage:ender_chest_1", wasteC)
  local c = w:computer{ id = 5, label = "Operator" }
  c:attach("back", cc.wired(net)); c:attach("top", cc.wireless{ ender = true })
  c:installRole("operator")
  c:writeFile("operator.env", "SETUP_WIZARD=no\n")
  if opts.cfg ~= false then
    c:writeTable("operator.cfg", { nextNum = { reactor = 1 }, units = { ["BigReactors-Reactor_0"] = { kind = "reactor", num = 1,
      label = "Reactor-1", mode = "auto", enabled = true, input = "port_in", output = "port_out",
      fuelChest = "enderstorage:ender_chest_0", wasteChest = "enderstorage:ender_chest_1" } } })
  end
  local mf = w:computer{ id = 9, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  mf:writeFile("mon.lua", [[
    rednet.open("top"); _G.last = nil
    while true do local _, m = rednet.receive("tanis-operator"); if m.type == "operator" then _G.last = m end end]])
  mf:run("mon")
  return { w = w, net = net, r = r, inP = inP, outP = outP, fuelC = fuelC, wasteC = wasteC, c = c, mf = mf }
end
local function unit(R) return R.mf.env._G.last and R.mf.env._G.last.units[1] end
local function need(u, key) for _, n in ipairs(u.needs or {}) do if n.key == key then return n end end end

T.test("operator chests: blocks go in before ingots, the reactor is never overfilled, cyanite goes to the waste chest", function()
  local R = room()                                         -- room for 20 fuel units
  R.fuelC:give(BLOCK, 2, nil, TB); R.fuelC:give(INGOT, 30, nil, TI)
  R.c:run("operator")
  R.w:run(6)
  T.eq(R.fuelC:count(BLOCK), 0, "blocks should go first")
  T.eq(R.fuelC:count(INGOT), 28, "two ingots fill the last two units, no more")
  T.truthy(R.r.fuel <= R.r.fuelMax and R.r.fuel > 19000, "reactor fuel " .. tostring(R.r.fuel))
  T.truthy(R.inP:isEmpty(), "nothing may pile up in the inlet")
  -- cyanite made by the reactor lands in the waste chest, the outlet stays empty
  R.w:run(60)
  T.truthy(R.wasteC:count("bigreactors:cyanite_ingot") >= 3, "no waste in the waste chest: " .. R.wasteC:count("bigreactors:cyanite_ingot") .. " / made " .. R.r.made)
  T.truthy(R.outP:isEmpty(), "the outlet was not emptied")
  T.eq(R.fuelC:count(INGOT), 28, "no more fuel while the reactor is full")
  -- the reactor burns some fuel, then there is room for a whole unit again and one ingot goes in
  R.w:run(900)
  T.truthy(R.fuelC:count(INGOT) < 28, "never topped up as the reactor burned")
  T.truthy(R.r.fuel <= R.r.fuelMax, "overfilled")
  local u = unit(R)
  T.eq(u.wasteStuck, false)
  T.eq(need(u, "fuelChest").state, "ok"); T.eq(need(u, "wasteChest").state, "ok")
  T.truthy(u.fuelChest and u.fuelChest > 0, "fuel chest units not in the status")
end)

T.test("operator chests: a block never goes in when the reactor only has room for ingots", function()
  local R = room{ fuelMax = 8000 }
  R.fuelC:give(BLOCK, 3, nil, TB); R.fuelC:give(INGOT, 10, nil, TI)
  R.c:run("operator"); R.w:run(6)
  T.eq(R.fuelC:count(BLOCK), 3, "a block does not fit in 8 units")
  T.eq(R.fuelC:count(INGOT), 2)
  T.truthy(R.r.fuel > 7000, tostring(R.r.fuel))
end)

T.test("operator chests: fuel is held back while the waste chest is full, and flows again once it clears", function()
  local R = room{ wasteSize = 1 }
  R.wasteC:give("bigreactors:cyanite_ingot", 64)           -- full
  R.outP:give("bigreactors:cyanite_ingot", 3)
  R.fuelC:give(INGOT, 30, nil, TI)
  R.c:run("operator"); R.w:run(10)
  local u = unit(R)
  T.eq(u.wasteStuck, true, "a full waste chest must read as waste not clearing")
  T.eq(need(u, "wasteTo").state, "missing")
  T.truthy(need(u, "wasteTo").why:find("waste chest is full"), need(u, "wasteTo").why)
  T.eq(R.fuelC:count(INGOT), 30, "fuel went in while waste could not clear")
  T.eq(R.outP:count("bigreactors:cyanite_ingot"), 3, "waste was voided")
  T.truthy(need(u, "fuelChest").why:find("held back"), "needs does not say fuel is held back: " .. need(u, "fuelChest").why)
  T.truthy(R.c:readFile("operator.log"):find("fuel held back", 1, true), "held back was not logged")
  -- Storage empties the waste chest
  R.wasteC:clear()
  R.w:run(10)
  u = unit(R)
  T.eq(u.wasteStuck, false)
  T.truthy(R.fuelC:count(INGOT) < 30, "fuel never resumed")
  T.truthy(R.outP:isEmpty(), "outlet not emptied")
end)

T.test("operator chests: a missing waste chest reads as waste not clearing", function()
  local R = room()
  R.outP:give("bigreactors:cyanite_ingot", 2)
  R.net:remove("enderstorage:ender_chest_1")
  R.c:run("operator"); R.w:run(10)
  local u = unit(R)
  T.eq(u.wasteStuck, true)
  T.eq(need(u, "wasteChest").state, "missing")
end)

T.test("operator chests: worked out for one reactor, saved, and unknown when they can't be told apart", function()
  local R = room{ cfg = false }
  R.fuelC:give(INGOT, 10, nil, TI)
  R.c:run("operator"); R.w:run(8)
  local cfg = R.c:readTable("operator.cfg").units["BigReactors-Reactor_0"]
  T.eq(cfg.fuelChest, "enderstorage:ender_chest_0")
  T.eq(cfg.wasteChest, "enderstorage:ender_chest_1")
  -- two chests both holding uranium: never guess
  local A = room{ cfg = false }
  A.fuelC:give(INGOT, 10, nil, TI); A.wasteC:give(INGOT, 5, nil, TI)
  A.c:run("operator"); A.w:run(8)
  local u = unit(A)
  T.eq(A.c:readTable("operator.cfg").units["BigReactors-Reactor_0"].fuelChest, nil, "guessed")
  T.eq(need(u, "fuelChest").state, "unknown"); T.eq(need(u, "wasteChest").state, "unknown")
  T.eq(A.fuelC:count(INGOT), 10, "moved fuel without knowing the chests")
  -- one ender chest, nothing in it: the fuel chest can't be told, let alone the waste chest
  local B = room{ cfg = false }
  B.net:remove("enderstorage:ender_chest_1")
  B.c:run("operator"); B.w:run(8)
  T.eq(need(unit(B), "fuelChest").state, "unknown")
  -- no ender chest at all: missing, and the reactor still runs
  local N = room{ cfg = false }
  N.net:remove("enderstorage:ender_chest_0"); N.net:remove("enderstorage:ender_chest_1")
  N.c:run("operator"); N.w:run(8)
  u = unit(N)
  T.eq(need(u, "fuelChest").state, "missing"); T.eq(need(u, "wasteChest").state, "missing")
  T.eq(u.active, true, "a reactor without chests still runs")
end)

T.test("operator chests: Storage's reactor_fuel report fills plant.supply and plant.fuelChest", function()
  local R = room()
  local st = R.w:computer{ id = 7, label = "Storage" }
  st:attach("top", cc.wireless{ ender = true })
  st:writeFile("st.lua", [[rednet.open('top')
    while true do
      rednet.broadcast({ type = 'reactor_fuel', chests = { { name = 'a', label = 'A', units = 48, keep = 64, low = 16 },
        { name = 'b', label = 'B', units = 10, keep = 64, low = 16 } }, supply = 412, best = 'x:y' }, 'tanis-operator')
      sleep(2) end]])
  st:run("st")
  R.fuelC:give(INGOT, 30, nil, TI)                           -- 20 go into the reactor, 10 stay
  R.c:run("operator"); R.w:run(12)
  local p = R.mf.env._G.last.plant
  T.eq(p.supply, 412)
  T.eq(p.fuelChest.units, 58); T.eq(p.fuelChest.keep, 128); T.eq(p.fuelChest.low, 32)
  T.eq(unit(R).fuelChest, 10, "per-unit chest units")
end)
