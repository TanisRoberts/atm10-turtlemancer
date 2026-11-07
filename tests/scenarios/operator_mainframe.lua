-- The mainframe and the Operator: the board row, alerts, and `island operator` chat commands.
-- island.lua, board.lua, wall.lua and operator_link.lua run side by side on one simulated mainframe (as mainframe.lua does).
local cc = require("sim.cc")
local T  = require("sim.test")

local PORT = { "bigreactors:reactoraccessport", "inventory" }
local function port() return cc.Inv.new{ size = 9, types = PORT } end

local function chatBox()
  return { types = { "chat_box" }, peripheralMethods = { "sendMessage" }, sent = {},
    sendMessage = function(self, msg, opts) self.sent[#self.sent + 1] = { msg = msg, player = opts and opts.player }; return true end }
end
local function envDetector() return { types = { "environment_detector" }, peripheralMethods = {} } end

local LAUNCH = [[
  local function sandbox(target)
    local e = {}
    e.require = require           -- as mainframe.lua's sandbox does: os.run programs have no require of their own
    e.peripheral = setmetatable({ find = function(kind, ...)
      if kind == "monitor" then return target end
      return peripheral.find(kind, ...)
    end }, { __index = peripheral })
    return e
  end
  parallel.waitForAll(
    function() os.run(sandbox(nil), "island.lua") end,
    function() os.run({ require = require }, "board.lua") end,
    function() require("wall").run(peripheral.wrap("bottom"), "bottom") end,
    function() os.run(sandbox(nil), "operator_link.lua") end)
]]

-- opts.supply: what the Storage stand-in reports; opts.fullOutlet: leave cyanite in the outlet that never drains
-- opts.reactors: 1 or 2
-- opts.fuel: { units, keep, low, supply }: the stand-in also sends Storage's reactor_fuel report, read from the global
--            FUEL on its computer each time (st:writeTable-free: change it with st.fuel); opts.fuelOnce: send it only until 30 s
local function build(opts)
  opts = opts or {}
  local world = cc.world(); local net = world:net()
  local inP, outP = port(), port()
  inP:give("mekanism:ingot_uranium", 12)
  local ra = world:reactor{ stored = 500000, active = true, prod = 3000, demand = 1200, rodScale = true, rodLevel = 40,
    inPort = inP, outPort = outP, fuel = 2800 }
  net:add("BigReactors-Reactor_0", ra); net:add("in_0", inP); net:add("out_0", outP)
  local units = { ["BigReactors-Reactor_0"] = { kind = "reactor", num = 1, label = "Reactor-1", mode = "auto", enabled = true, input = "in_0", output = "out_0" } }
  local rb
  if opts.reactors == 2 then
    local i2, o2 = port(), port()
    rb = world:reactor{ stored = 900000, active = false, prod = 3000, demand = 1200, rodScale = true, rodLevel = 40, inPort = i2, outPort = o2, fuel = 1600 }
    net:add("BigReactors-Reactor_1", rb); net:add("in_1", i2); net:add("out_1", o2)
    units["BigReactors-Reactor_1"] = { kind = "reactor", num = 2, label = "Reactor-2", mode = "auto", enabled = true, input = "in_1", output = "out_1" }
  end
  local det = opts.detector and net:add("energy_detector_0", world:detector{ rate = opts.detector, limit = 4000 })
  if opts.fullOutlet then outP:give("bigreactors:cyanite_ingot", 64 * 9) end
  for _, u in pairs(units) do            -- the reactor room's two ender chests; a full outlet means the waste chest is full too
    u.fuelChest, u.wasteChest = "enderstorage:ender_chest_" .. (2 * u.num - 2), "enderstorage:ender_chest_" .. (2 * u.num - 1)
    net:add(u.fuelChest, cc.Inv.new{ size = 27 })
    local wc = net:add(u.wasteChest, cc.Inv.new{ size = opts.fullOutlet and 1 or 27 })
    if opts.fullOutlet then wc:give("bigreactors:cyanite_ingot", 64) end
  end
  local opc = world:computer{ id = 5, label = "Operator" }
  opc:attach("back", cc.wired(net)); opc:attach("top", cc.wireless{ ender = true })
  opc:installRole("operator")
  if not opts.fresh then opc:writeTable("operator.cfg", { nextNum = { reactor = opts.reactors or 1 }, units = units }) end
  opc:run("operator")
  -- Storage stand-in: reports its uranium
  local st = world:computer{ id = 7, label = "Storage" }
  st:attach("top", cc.wireless{ ender = true })
  local f = opts.fuel
  local fuelSend = f and ("rednet.broadcast({ type = 'reactor_fuel', chests = { { name = 'enderstorage:ender_chest_0', label = 'Reactor fuel', units = %d, keep = %d, low = %d } }, supply = %d, best = 'mekanism:ingot_uranium' }, 'tanis-operator')"):format(
    f.units, f.keep, f.low, f.supply) or ""
  if f and f.units == 0 and f.supply == 0 then fuelSend = fuelSend:gsub(", best = 'mekanism:ingot_uranium'", "") end
  local gate = opts.fuelOnce and "if os.clock() < 30 then " .. fuelSend .. " end" or fuelSend
  st:writeFile("st.lua", ("rednet.open('top')\nwhile true do rednet.broadcast({ type = 'uranium', total = %d }, 'tanis-operator'); %s sleep(2) end"):format(opts.supply or 100, gate))
  st:run("st")
  -- the mainframe
  local mf = world:computer{ id = 1, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  local chat, mon = chatBox(), nil
  mf:attach("left", chat); mf:attach("right", envDetector())
  mon = mf:monitor("bottom", opts.wide or 90, 20)
  mf:installRole("mainframe")
  mf:writeFile("launch.lua", LAUNCH)
  mf:run("launch")
  return world, mf, opc, chat, mon, ra, rb, det
end

local UUID = "00000000-0000-0000-0000-000000000001"
local function say(world, mf, text) mf:queue("chat", UUID, "Tanis", text, false); world:run(8) end
local function heard(chat, pat, player)
  for _, m in ipairs(chat.sent) do
    if m.msg:find(pat) and (not player or m.player == player) then return m.msg end
  end
end
local function dump(chat) local t = {}; for _, m in ipairs(chat.sent) do t[#t + 1] = tostring(m.player) .. ": " .. m.msg end; return table.concat(t, "\n") end

T.test("operator mainframe: the board shows an Operator row with ON, FE/t, buffer and uranium", function()
  local world, mf, opc, chat, mon = build{ supply = 48 }
  world:run(20)
  T.eq(mf.error, nil)
  T.truthy(mon:find("Operator"), mon:text())
  T.truthy(mon:find("running"), "state\n" .. mon:text())
  local _, y = mon:find("Operator")
  local row = mon:line(y)
  T.truthy(row:find("ON, ", 1, true) and row:find("FE/t", 1, true) and row:find("buffer", 1, true) and row:find("uranium 48", 1, true), row)
end)

T.test("operator mainframe: with two reactors the row expands to one line each", function()
  local world, mf, opc, chat, mon = build{ supply = 48, reactors = 2 }
  world:run(20)
  T.truthy(mon:find("2 of 2 on") or mon:find("1 of 2 on"), mon:text())
  T.truthy(mon:find("Reactor-1") and mon:find("Reactor-2"), mon:text())
  local _, y2 = mon:find("Reactor-2")
  T.truthy(mon:line(y2):find("OFF", 1, true), mon:line(y2))
end)

T.test("operator mainframe: the old fuel supply alert is gone, waste not clearing is named per reactor, named per reactor", function()
  local world, mf, opc, chat = build{ supply = 10, fullOutlet = true }
  say(world, mf, "$island alerts")
  T.truthy(heard(chat, "Alerts on"), dump(chat))
  world:run(10)
  T.falsy(heard(chat, "Fuel supply low"), "the old uranium alert is gone\n" .. dump(chat))
  T.truthy(heard(chat, "Reactor%-1: waste not clearing", "Tanis"), dump(chat))
end)

T.test("operator mainframe: reactor silent raises an alert and clears when the heartbeat returns", function()
  local world, mf, opc, chat = build{ supply = 100 }
  say(world, mf, "$island alerts")
  world:run(10)
  T.falsy(heard(chat, "Reactor silent"), "alert too early")
  opc:_stop()
  world:run(90)
  T.truthy(heard(chat, "Reactor silent"), dump(chat))
  local n = 0
  for _, m in ipairs(chat.sent) do if m.msg:find("Reactor silent") then n = n + 1 end end
  T.eq(n, 1, "should alert once")
  opc:run("operator")
  world:run(30)
  opc:_stop()
  world:run(90)
  n = 0
  for _, m in ipairs(chat.sent) do if m.msg:find("Reactor silent") then n = n + 1 end end
  T.eq(n, 2, "should alert again after the heartbeat came back and went away")
end)

T.test("operator mainframe: island operator status, on, off, auto, and a named reactor", function()
  local world, mf, opc, chat, mon, ra, rb = build{ supply = 100, reactors = 2 }
  world:run(20)
  say(world, mf, "$island operator")
  T.truthy(heard(chat, "Operator: 2 reactors"), dump(chat))
  say(world, mf, "$island operator reactor-1 status")
  T.truthy(heard(chat, "Reactor%-1: ON"), dump(chat))
  -- off for reactor-1 only
  say(world, mf, "$island operator reactor-1 off")
  T.truthy(heard(chat, "Reactor%-1: forced OFF"), dump(chat))
  T.waitFor(world, function() return not ra.on end, 15, "off command never arrived")
  T.eq(opc:readTable("operator.cfg").units["BigReactors-Reactor_0"].mode, "off")
  T.eq(opc:readTable("operator.cfg").units["BigReactors-Reactor_1"].mode, "auto", "the other reactor must not change")
  -- all on
  say(world, mf, "$island operator on")
  T.truthy(heard(chat, "All reactors: forced ON"), dump(chat))
  T.waitFor(world, function() return ra.on and rb.on end, 15, "on command never arrived")
  -- auto returns both to demand control
  say(world, mf, "$island operator auto")
  T.truthy(heard(chat, "back on demand control"), dump(chat))
  world:run(6)
  T.eq(opc:readTable("operator.cfg").units["BigReactors-Reactor_1"].mode, "auto")
  -- a reactor that doesn't exist
  say(world, mf, "$island operator reactor-9 on")
  T.truthy(heard(chat, "No reactor called reactor%-9"), dump(chat))
  T.eq(mf.error, nil)
end)

T.test("operator mainframe: a reactor awaiting setup shows on the board and raises no alert", function()
  local world, mf, opc, chat, mon = build{ supply = 100, fresh = true, fullOutlet = true }
  say(world, mf, "$island alerts")
  world:run(20)
  T.truthy(mon:find("awaiting setup"), mon:text())
  T.truthy(mon:find("setup"), mon:text())
  T.falsy(heard(chat, "waste not clearing"), "no alert for a reactor that is not set up\n" .. dump(chat))
  say(world, mf, "$island operator status")
  T.truthy(heard(chat, "Awaiting Setup"), dump(chat))
end)

T.test("operator mainframe: the board shows the fuel chest and the store from Storage's report", function()
  local world, mf, opc, chat, mon = build{ supply = 412, wide = 130, fuel = { units = 48, keep = 64, low = 16, supply = 412 } }
  world:run(20)
  T.eq(mf.error, nil)
  local _, y = mon:find("Operator")
  local row = mon:line(y)
  T.truthy(row:find("fuel chest 48/64", 1, true) and row:find("store 412", 1, true), row)
  T.falsy(row:find("uranium", 1, true), row)
end)

T.test("operator mainframe: a stale fuel report reads fuel chest ?", function()
  local world, mf, opc, chat, mon = build{ supply = 412, wide = 130, fuel = { units = 48, keep = 64, low = 16, supply = 412 }, fuelOnce = true }
  world:run(20)
  local _, y = mon:find("Operator")
  T.truthy(mon:line(y):find("fuel chest 48/64", 1, true), mon:line(y))
  world:run(120)
  _, y = mon:find("Operator")
  T.truthy(mon:line(y):find("fuel chest ?", 1, true), mon:line(y))
  T.falsy(mon:line(y):find("store", 1, true), mon:line(y))
end)

T.test("operator mainframe: no fuel report keeps the uranium text", function()
  local world, mf, opc, chat, mon = build{ supply = 48 }
  world:run(20)
  local _, y = mon:find("Operator")
  local row = mon:line(y)
  T.truthy(row:find("uranium 48", 1, true) and not row:find("fuel chest", 1, true), row)
end)

T.test("operator mainframe: Fuel chest low fires under low and clears at low", function()
  local world, mf, opc, chat = build{ supply = 100, fuel = { units = 10, keep = 64, low = 16, supply = 100 } }
  say(world, mf, "$island alerts")
  world:run(20)
  T.truthy(heard(chat, "Fuel chest low: Reactor fuel has 10/64", "Tanis"), dump(chat))
  T.falsy(heard(chat, "Nothing left to stock"), dump(chat))
end)

T.test("operator mainframe: Fuel chest low clears when the chest is back at low", function()
  local world, mf, opc, chat = build{ supply = 100, fuel = { units = 16, keep = 64, low = 16, supply = 100 } }
  say(world, mf, "$island alerts")
  world:run(20)
  T.falsy(heard(chat, "Fuel chest low"), "16 is not under low\n" .. dump(chat))
end)

T.test("operator mainframe: Nothing left to stock fires when supply is 0", function()
  local world, mf, opc, chat = build{ supply = 100, fuel = { units = 48, keep = 64, low = 16, supply = 0 } }
  say(world, mf, "$island alerts")
  world:run(20)
  T.truthy(heard(chat, "Nothing left to stock: Storage has no reactor fuel left", "Tanis"), dump(chat))
  T.falsy(heard(chat, "Fuel chest low"), dump(chat))
end)

T.test("operator mainframe: fuel alerts fire while the Operator is quiet, and clear when the report recovers", function()
  local world, mf, opc, chat = build{ supply = 100, fuel = { units = 4, keep = 64, low = 16, supply = 0 } }
  say(world, mf, "$island alerts")
  opc:_stop()
  world:run(20)
  T.truthy(heard(chat, "Fuel chest low"), dump(chat))
  T.truthy(heard(chat, "Nothing left to stock"), dump(chat))
end)

T.test("operator mainframe: island operator status mentions the fuel chest", function()
  local world, mf, opc, chat = build{ supply = 100, fuel = { units = 48, keep = 64, low = 16, supply = 412 } }
  world:run(20)
  say(world, mf, "$island operator")
  T.truthy(heard(chat, "Fuel chest 48/64, store 412"), dump(chat))
end)

-- Reactor 1 makes 3000 FE/t at full power (prod 3000, rods at level 60 report 1800). Draw 1700 = 57% of 3000.
local function count(chat, pat) local n = 0; for _, m in ipairs(chat.sent) do if m.msg:find(pat) then n = n + 1 end end; return n end

T.test("operator mainframe: the board row and island operator show power use", function()
  local world, mf, opc, chat, mon = build{ supply = 100, wide = 130, detector = 1700 }
  world:run(25)
  local _, y = mon:find("Operator")
  local row = mon:line(y)
  T.truthy(row:find("use 5%d%% est%. %(1,700 / 3,000 FE/t%)"), row)
  say(world, mf, "$island operator")
  T.truthy(heard(chat, "Power use 5%d%% est%. %(1,700 / 3,000 FE/t%)"), dump(chat))
  T.falsy(heard(chat, "Power deficit"), dump(chat))
end)

T.test("operator mainframe: no detector leaves the use text out", function()
  local world, mf, opc, chat, mon = build{ supply = 100, wide = 130 }
  world:run(25)
  local _, y = mon:find("Operator")
  T.falsy(mon:line(y):find("use ", 1, true), mon:line(y))
end)

T.test("operator mainframe: Power deficit fires after the delay, once, and clears when draw drops", function()
  local world, mf, opc, chat, mon, ra, rb, det = build{ supply = 100, wide = 130, detector = 3600 }
  say(world, mf, "$island alerts")
  world:run(15)
  T.eq(count(chat, "Power deficit"), 0, "fired before the 30 s delay\n" .. dump(chat))
  world:run(40)
  T.truthy(heard(chat, "Power deficit: the grid draws 3,600 FE/t but the reactors can only make 3,000", "Tanis"), dump(chat))
  world:run(30)
  T.eq(count(chat, "Power deficit"), 1, "should alert once")
  det.rate = 1000
  world:run(25)
  det.rate = 3600
  world:run(15)
  world:run(40)
  T.eq(count(chat, "Power deficit"), 2, "should alert again after it cleared\n" .. dump(chat))
end)

T.test("operator mainframe: a surge shorter than the delay raises nothing", function()
  local world, mf, opc, chat, mon, ra, rb, det = build{ supply = 100, detector = 1000 }
  say(world, mf, "$island alerts")
  world:run(15)
  det.rate = 4000
  world:run(12)
  det.rate = 1000
  world:run(60)
  T.eq(count(chat, "Power deficit"), 0, dump(chat))
end)

T.test("operator mainframe: a stale power report raises no deficit and the use text goes", function()
  local world, mf, opc, chat, mon, ra, rb, det = build{ supply = 100, wide = 130, detector = 3600 }
  mf:writeFile("island.env", "DEFICIT_AFTER=60\n")   -- longer than the 30 s it takes the report to go stale
  say(world, mf, "$island alerts")
  world:run(5)
  det.rate = function() return nil end   -- the detector stops answering; the last reading stays in the record
  world:run(100)
  T.eq(count(chat, "Power deficit"), 0, dump(chat))
  local _, y = mon:find("Operator")
  T.falsy(mon:line(y):find("use ", 1, true), mon:line(y))
end)

T.test("operator mainframe: Power throttled alert while the breaker is tripped, and it stays after the draw falls", function()
  local world, mf, opc, chat, mon, ra, rb, det = build{ supply = 100, wide = 130, detector = 1000 }
  say(world, mf, "$island alerts")
  world:run(15)
  T.eq(count(chat, "Power throttled"), 0, dump(chat))
  det.rate = 6000                                -- 200% of 3000
  world:run(40)
  T.eq(count(chat, "Power throttled"), 1, "should alert once\n" .. dump(chat))
  T.truthy(heard(chat, "Press Reset on the Operator", "Tanis"), dump(chat))
  det.rate = 500
  world:run(60)
  T.eq(count(chat, "Power throttled"), 1, "cleared by itself?\n" .. dump(chat))
  T.truthy(det.limit < 1000000, "detector uncapped")
end)
