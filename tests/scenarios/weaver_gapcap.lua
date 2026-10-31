-- Weaver at the gap limit: storage is out of a block, the gaps pile up, and he must wait for stock
-- instead of flying home to restock over and over without moving on.
local cc = require("sim.cc")
local T  = require("sim.test")

-- Layer 1 is all mud (storage has none: a gap each), layer 2 is stone over it (waits on those gaps) plus
-- a strip of stone beside it that nothing is waiting on.
local function planText(cols, mudRows, freeRows)
  local L = {}
  L[#L + 1] = "#info " .. require("sim.env").serialize({
    name = "Gap test", palette = { m = "minecraft:mud", s = "minecraft:stone" }, layers = 2, ybase = 1, topY = 2,
    minX = 0, maxX = cols - 1, minZ = 0, maxZ = mudRows + freeRows - 1,
    blocks = cols * (2 * mudRows + freeRows), bill = { ["minecraft:mud"] = cols * mudRows, ["minecraft:stone"] = cols * (mudRows + freeRows) },
  }, { compact = true })
  L[#L + 1] = "#ext"
  L[#L + 1] = "#L 1"
  for z = 0, mudRows - 1 do L[#L + 1] = z .. "|0|" .. cols .. "m" end
  L[#L + 1] = "#L 2"
  for z = 0, mudRows + freeRows - 1 do L[#L + 1] = z .. "|0|" .. cols .. "s" end
  return table.concat(L, "\n") .. "\n"
end

local function base(opts)
  opts = opts or {}
  local w = cc.world()
  w.gpsOn = true
  local net = w:net()
  local function barrel(i) return net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
  local inp, out, sup, s1, s2 = barrel(0), barrel(1), barrel(2), barrel(3), barrel(4)
  for _ = 1, 20 do s1:give("minecraft:stone", 64) end
  for _ = 1, 20 do s2:give("minecraft:stone", 64) end
  if opts.mud then s2:give("minecraft:mud", opts.mud) end
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net))
  st:attach("top", cc.wireless{ ender = true })
  st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1", weaver = "minecraft:barrel_2" })

  -- dock at 0,64,0 facing north, supply barrel in front of it (the same inventory storage fills)
  w:setBlock(0, 64, -1, "minecraft:barrel", sup)
  local t = w:turtle{ id = 7, label = "Weaver-01", x = 0, y = 64, z = 0, facing = 0, fuel = 20000,
                      left = "minecraft:diamond_pickaxe", right = "computercraft:wireless_modem_advanced" }
  t:install("turtle/weaver/weaver.lua"); t:install("shared/weaverplan.lua")
  t:writeFile("gap.plan", planText(70, 44, 3))
  t:writeTable("weaver.cfg", { plan = "gap.plan", dx = 0, dy = 64, dz = 0, dh = 0, cx = -35, cz = -60, sea = 62, seabed = 40,
                               rot = 0, cruise = 80, supplyDir = 0 })
  t:writeTable("weaver.state", { x = 0, y = 64, z = 0, h = 0, want = "build" })

  -- count what he asks storage for
  local spy = w:computer{ id = 3, label = "Spy" }
  spy:attach("top", cc.wireless{ ender = true })
  spy:writeFile("spy.lua", [[
    rednet.open("top")
    _G.needs = 0
    while true do
      local _, msg, proto = rednet.receive("tanis-rigger")
      if type(msg) == "table" and msg.type == "need" and msg.seq ~= _G.lastSeq then _G.needs = _G.needs + 1; _G.lastSeq = msg.seq end
    end
  ]])
  spy:run("spy")
  return w, t, st, spy, { inp = inp, sup = sup, s1 = s1, s2 = s2 }
end

local function placedStone(w)
  return w:count("minecraft:stone", -40, 60, -70, 40, 70, 0)
end

T.test("weaver: at the gap limit he waits for stock instead of restocking in a loop", function()
  local w, t, st, spy = base()
  st:run("storage")
  w:run(5)
  t:run("weaver")
  w:run(900)
  T.running(t)
  local needs = spy.G.needs
  assert(needs <= 8, "he went back to the dock " .. needs .. " times for the same blocks")
end)

T.test("weaver: when the missing block turns up at the gap limit he fills gaps and carries on", function()
  local w, t, st, spy, inv = base()
  st:run("storage")
  w:run(5)
  t:run("weaver")
  w:run(600)
  T.contains(t:readTable("weaver.state").msg, "gaps is my limit")
  local before = w:count("minecraft:mud", -40, 60, -70, 40, 70, 0)
  for _ = 1, 4 do inv.inp:give("minecraft:mud", 64) end      -- storage sorts it in and broadcasts the new count
  w:run(900)
  T.running(t)
  local mud = w:count("minecraft:mud", -40, 60, -70, 40, 70, 0)
  assert(mud >= before + 40, "he never filled the gaps once mud arrived (" .. mud .. " placed)")
end)
