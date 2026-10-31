-- Seagull (cartographer) and Bowerbird (crafter) on the turtle core: lava from the dock, the empty bucket back,
-- and the dock report to Storage. See docs/systems/turtle.md.
local cc = require("sim.cc")
local T = require("sim.test")

local BARREL = { "minecraft:barrel", "inventory" }

-- A stand-in Storage that answers dock reports
local function storage(w)
  local s = w:computer{ id = 1, label = "Storage" }
  s:attach("top", cc.wireless{ ender = true })
  s:writeFile("storage.lua", [[
    rednet.open("top")
    reports = {}
    while true do
      local from, msg = rednet.receive("tanis-base", 1)
      if type(msg) == "table" and msg.type == "dock_report" then
        reports[#reports + 1] = msg
        rednet.send(from, { type = "dock_ack", id = msg.id, assigned = "minecraft:barrel_3" }, "tanis-base")
      end
    end
  ]])
  s:run("storage")
  return s
end

T.test("Seagull: drinks the lava bucket at his dock, hands the empty back, and reports the dock", function()
  local w = cc.world()
  w.gpsOn = true
  local dock = cc.Inv.new{ size = 27, types = BARREL }
  w:setBlock(0, 64, -1, "minecraft:barrel", dock)
  dock:give("minecraft:lava_bucket", 2)
  local t = w:turtle{ id = 7, label = "Seagull-01", x = 0, y = 64, z = 0, facing = 0, fuel = 0,
                      right = "computercraft:wireless_modem_advanced" }
  t:installRole("seagull")
  t:attach("right", cc.wireless{ ender = true })
  local s = storage(w)
  w:run(1)
  t:run("seagull"); w:run(30)
  T.eq(t.body.fuel >= 1900, true, "he drank both lava buckets at boot (fuel " .. tostring(t.body.fuel) .. ")")
  T.eq(dock:count("minecraft:lava_bucket"), 0)
  T.eq(dock:count("minecraft:bucket"), 2, "the empties are back in the dock")
  local rep = s.G.reports and s.G.reports[1]
  T.eq(rep ~= nil, true, "Storage heard a dock report")
  if rep then
    T.eq(rep.label, "Seagull-01"); T.eq(rep.x, 0); T.eq(rep.y, 64); T.eq(rep.z, -1)
  end
end)

T.test("Seagull: tops up to FUEL_PCT (90%) of his limit while the dock is refilled, and stops there", function()
  local w = cc.world()
  w.gpsOn = true
  local dock = cc.Inv.new{ size = 27, types = BARREL }
  w:setBlock(0, 64, -1, "minecraft:barrel", dock)
  dock:give("minecraft:lava_bucket", 27)
  local t = w:turtle{ id = 7, label = "Seagull-01", x = 0, y = 64, z = 0, facing = 0, fuel = 0, fuelLimit = 100000,
                      right = "computercraft:wireless_modem_advanced" }
  t:installRole("seagull")
  t:attach("right", cc.wireless{ ender = true })
  storage(w)
  w:run(1)
  t:run("seagull"); w:run(60)
  T.eq(t.body.fuel >= 26000, true, "he drank the first barrel (fuel " .. tostring(t.body.fuel) .. ")")
  for _ = 1, 3 do               -- Storage refills the barrel three times: 108 buckets in all, more than he wants
    dock:clear()                -- (Storage takes the empties back)
    dock:give("minecraft:lava_bucket", 27)
    w:run(60)
  end
  T.eq(t.body.fuel >= 90000, true, "he reached 90% (fuel " .. tostring(t.body.fuel) .. ")")
  T.eq(t.body.fuel < 91000, true, "and stopped there (fuel " .. tostring(t.body.fuel) .. ")")
  T.eq(dock:count("minecraft:lava_bucket") > 0, true, "the rest stays in the dock")
end)

T.test("Bowerbird: reports a bottom dock to Storage, from his GPS fix", function()
  local w = cc.world()
  w.gpsOn = true
  local dock = cc.Inv.new{ size = 27, types = BARREL }
  w:setBlock(10, 63, 10, "minecraft:barrel", dock)
  local t = w:turtle{ id = 8, label = "Bowerbird-01", x = 10, y = 64, z = 10, facing = 0, fuel = 0,
                      right = "computercraft:wireless_modem_advanced" }
  t:installRole("bowerbird")
  t:attach("right", cc.wireless{ ender = true })
  t:attach("bottom", dock)
  local s = storage(w)
  w:run(1)
  t:run("crafter"); w:run(20)
  local rep = s.G.reports and s.G.reports[1]
  T.eq(rep ~= nil, true, "Storage heard a dock report")
  if rep then
    T.eq(rep.x, 10); T.eq(rep.y, 63); T.eq(rep.z, 10); T.eq(rep.role, "crafter")
  end
end)
