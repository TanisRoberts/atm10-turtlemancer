-- Miner (Canary): first-run setup at the dock, a number from the Foreman, then one order to mine.
-- A tiny stand-in Foreman answers on the radio; the real one has its own scenarios.
local cc = require("sim.cc")
local T = require("sim.test")

-- Dock at 0,64,0 facing north; dump barrel east, fuel barrel west; stone below (Y 40..63) with some ore.
local function base()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:stone")
  local dump = cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }
  local fuel = cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }
  fuel:give("minecraft:coal", 64)
  w:setBlock(1, 64, 0, "minecraft:barrel", dump)
  w:setBlock(-1, 64, 0, "minecraft:barrel", fuel)
  local t = w:turtle{ id = 7, x = 0, y = 64, z = 0, facing = 0, fuel = 400,
                      left = "minecraft:diamond_pickaxe", right = "computercraft:wireless_modem_advanced" }
  t:installRole("canary")
  return w, t, dump, fuel
end

-- A Foreman that numbers every miner that registers and, once `order` is set, sends it to every miner it has heard.
local function foreman(w)
  local f = w:computer{ id = 1, label = "Foreman" }
  f:attach("top", cc.wireless{ ender = true })
  f:writeFile("foreman.lua", [[
    rednet.open("top")
    local seen, nextNum = {}, 1
    while true do
      local from, msg = rednet.receive("tanis-miner", 1)
      if type(msg) == "table" and msg.type == "register" then
        rednet.send(from, { type = "assigned", id = from, num = nextNum, label = "Canary-0" .. nextNum }, "tanis-miner")
        nextNum = nextNum + 1
      elseif type(msg) == "table" and msg.type == "status" then
        seen[from] = msg
        _G.lastStatus = msg
      end
      if _G.order then
        for id in pairs(seen) do
          rednet.send(id, { type = "cmd", to = id, want = _G.order.want, minY = _G.order.minY, maxY = _G.order.maxY,
                            c1 = 0, c2 = 0, r1 = 1, r2 = 8, seq = _G.order.seq, capped = {} }, "tanis-miner")
        end
      end
    end
  ]])
  f:run("foreman")
  return f
end

T.test("miner: first-run setup finds the barrels and ends up docked", function()
  local w, t, dump, fuel = base()
  t:run("miner")
  w:run(1)
  T.contains(t.screen, "Dimension")
  t:type("1"); t:key(257)                         -- Overworld
  w:run(20)
  T.running(t)
  T.contains(t:output(), "GPS says I'm at 0 64 0")
  T.contains(t:output(), "I'm facing north")
  T.contains(t:output(), "Fuel barrel: on my left. Dump barrel: on my right")
  T.contains(t:output(), "I'm a Canary (overworld)")
  local st = t:readTable("miner.state")
  T.eq(st.dockY, 64); T.eq(st.dumpDir, 1); T.eq(st.fuelDir, 3)
  T.eq(t.body.x, 0, "back on the dock"); T.eq(t.body.y, 64); T.eq(t.body.z, 0)
end)

T.test("miner: the Foreman names it and it writes startup.lua for auto-resume", function()
  local w, t = base()
  foreman(w)
  t:run("miner"); w:run(1)
  t:type("1"); t:key(257)
  w:run(30)
  T.eq(t.label, "Canary-01")
  T.eq(t:readFile("startup.lua"), 'shell.run("miner")\n')
  T.eq(t:readTable("miner.state").num, 1)
end)

-- A dock chunk with three ores in it and the Foreman's order to mine Y 60..63.
local function mineWorld()
  local w, t, dump, fuel = base()
  local f = foreman(w)
  w:setBlock(3, 62, 3, "minecraft:iron_ore")
  w:setBlock(5, 61, 7, "minecraft:diamond_ore")
  w:setBlock(9, 62, 12, "minecraft:coal_ore")
  t:run("miner"); w:run(1)
  t:type("1"); t:key(257)
  w:run(10)
  return w, t, dump, fuel, f
end
local function order(f) f.env._G.order = { want = "run", minY = 60, maxY = 63, seq = 1 } end
local function finished(f) return function() local s = f.env._G.lastStatus; return s and s.state == "docked" and s.msg and s.msg:find("Range finished") end end

T.test("miner: mines its chunk, brings the ore home and leaves the barrels alone", function()
  local w, t, dump, fuel, f = mineWorld()
  order(f)
  T.waitFor(w, finished(f), 1200, "never finished the range")
  T.running(t)
  T.eq(dump:count("minecraft:diamond"), 1)
  T.eq(dump:count("minecraft:raw_iron"), 1)
  T.eq(dump:count("minecraft:coal"), 1)
  T.eq(w:count("minecraft:iron_ore", 0, 40, 0, 15, 63, 15), 0, "iron ore left behind")
  T.eq(w:count("minecraft:diamond_ore", 0, 40, 0, 15, 63, 15), 0, "diamond ore left behind")
  T.truthy(w:getBlock(1, 64, 0) and w:getBlock(-1, 64, 0), "dock barrels still standing")
  T.eq(t.body.x, 0); T.eq(t.body.y, 64); T.eq(t.body.z, 0)
  T.truthy(t.body.fuel > 400, "refuelled from the fuel barrel")
  for _, s in pairs(t.body.slots) do T.falsy(s.name == "minecraft:diamond", "nothing valuable left in the bag") end
end)

T.test("miner: a reboot in the middle of a run resumes where it was", function()
  local w, t, dump, fuel, f = mineWorld()
  order(f)
  w:run(150)
  T.eq(f.env._G.lastStatus.state, "mining")
  t:reboot()                                      -- chunk unload / server restart: startup.lua runs the miner again
  w:run(5)
  T.running(t)
  T.waitFor(w, finished(f), 1500, "never finished after the reboot")
  T.eq(dump:count("minecraft:diamond"), 1)
  T.eq(dump:count("minecraft:raw_iron"), 1)
end)
