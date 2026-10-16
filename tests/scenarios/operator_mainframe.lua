-- The mainframe and the Operator: the board row, alerts, and `island operator` chat commands.
-- island.lua, board.lua and operator_link.lua run side by side on one simulated mainframe (as mainframe.lua does).
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
    function() os.run(sandbox(nil), "operator_link.lua") end)
]]

-- opts.supply: what the Storage stand-in reports; opts.fullOutlet: leave cyanite in the outlet that never drains
-- opts.reactors: 1 or 2
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
  if opts.fullOutlet then outP:give("bigreactors:cyanite_ingot", 64 * 9) end
  local opc = world:computer{ id = 5, label = "Operator" }
  opc:attach("back", cc.wired(net)); opc:attach("top", cc.wireless{ ender = true })
  opc:installRole("operator")
  if not opts.fresh then opc:writeTable("operator.cfg", { nextNum = { reactor = opts.reactors or 1 }, units = units }) end
  opc:run("operator")
  -- Storage stand-in: reports its uranium
  local st = world:computer{ id = 7, label = "Storage" }
  st:attach("top", cc.wireless{ ender = true })
  st:writeFile("st.lua", ("rednet.open('top')\nwhile true do rednet.broadcast({ type = 'uranium', total = %d }, 'tanis-operator'); sleep(2) end"):format(opts.supply or 100))
  st:run("st")
  -- the mainframe
  local mf = world:computer{ id = 1, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  local chat, mon = chatBox(), nil
  mf:attach("left", chat); mf:attach("right", envDetector())
  mon = mf:monitor("bottom", 90, 20)
  mf:installRole("mainframe")
  mf:writeFile("launch.lua", LAUNCH)
  mf:run("launch")
  return world, mf, opc, chat, mon, ra, rb
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
  T.truthy(mon:find("RUNNING"), "state\n" .. mon:text())
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

T.test("operator mainframe: alerts for fuel supply low and waste not clearing, named per reactor", function()
  local world, mf, opc, chat = build{ supply = 10, fullOutlet = true }
  say(world, mf, "$island alerts")
  T.truthy(heard(chat, "Alerts on"), dump(chat))
  world:run(10)
  T.truthy(heard(chat, "Fuel supply low: only 10 uranium", "Tanis"), dump(chat))
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
  T.truthy(mon:find("SETUP"), mon:text())
  T.falsy(heard(chat, "waste not clearing"), "no alert for a reactor that is not set up\n" .. dump(chat))
  say(world, mf, "$island operator status")
  T.truthy(heard(chat, "Awaiting Setup"), dump(chat))
end)
