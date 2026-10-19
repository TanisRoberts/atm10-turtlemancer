-- The turtle core (shared/turtlecore*.lua): fuel table and priority, lava buckets, the dock, GPS, the dock report,
-- and farmbot (Woodpecker / Partridge) running on it. See docs/systems/turtle.md.
local cc = require("sim.cc")
local T = require("sim.test")

local BARREL = { "minecraft:barrel", "inventory" }

-- A Woodpecker's files on a turtle at 0,64,0 facing north with a dock barrel in front (0,64,-1).
-- `body` is a probe program (Lua source) run on the turtle; it can use `core` and leaves answers in `result`.
local function setup(opts)
  opts = opts or {}
  local w = cc.world()
  w.gpsOn = opts.gps ~= false
  local dock = cc.Inv.new{ size = 27, types = BARREL }
  w:setBlock(0, 64, -1, "minecraft:barrel", dock)
  local t = w:turtle{ id = 5, x = 0, y = 64, z = 0, facing = 0, fuel = opts.fuel or 100, items = opts.items,
                      right = "computercraft:wireless_modem_advanced" }
  t:installRole("woodpecker")
  t:writeFile("probe.lua", 'local core = dofile("turtlecore.lua")\nresult = {}\n' .. (opts.body or ""))
  return w, t, dock
end
local function slotsOf(t, name)
  local n = 0
  for _, s in pairs(t.body.slots) do if s.name == name then n = n + s.count end end
  return n
end

T.test("turtle core: drinks a lava bucket from the dock and puts the empty bucket back", function()
  local w, t, dock = setup({ body = 'core.fuel.refuelFromDock("front", 1000)' })
  dock:give("minecraft:lava_bucket", 1)
  t:run("probe"); w:run(5)
  T.eq(t.body.fuel, 1100, "lava is worth 1000")
  T.eq(dock:count("minecraft:bucket"), 1, "the empty bucket is back in the dock")
  T.eq(dock:count("minecraft:lava_bucket"), 0)
  T.eq(slotsOf(t, "minecraft:bucket"), 0, "no bucket left in the turtle")
end)

T.test("turtle core: no lava, so coal from the dock (and only up to the target)", function()
  local w, t, dock = setup({ body = 'core.fuel.refuelFromDock("front", 300)' })
  dock:give("minecraft:coal", 64)
  t:run("probe"); w:run(5)
  T.eq(t.body.fuel, 340, "three coal gets from 100 to 300 or more: 100 + 3 x 80")
  T.eq(dock:count("minecraft:coal"), 61, "the rest stays in the dock")
end)

T.test("turtle core: carried fuel burns best first, and logs and planks are never burned", function()
  local items = { [1] = { "minecraft:oak_log", 16 }, [2] = { "minecraft:stick", 20 }, [3] = { "minecraft:coal", 10 },
                  [4] = { "minecraft:coal_block", 2 }, [5] = { "mekanism:bio_fuel", 8 }, [6] = { "minecraft:oak_planks", 8 } }
  local w, t = setup({ items = items, body = 'result.gained = core.fuel.refuelFromInventory(1000)' })
  t:run("probe"); w:run(5)
  T.eq(t.body.fuel, 1700, "from 100 to 1000 takes two coal blocks (the best fuel), nothing else")
  T.eq(slotsOf(t, "minecraft:coal_block"), 0)
  T.eq(slotsOf(t, "minecraft:coal"), 10, "coal is only burned once the blocks are gone")
  T.eq(slotsOf(t, "mekanism:bio_fuel"), 8); T.eq(slotsOf(t, "minecraft:stick"), 20)
  T.eq(slotsOf(t, "minecraft:oak_log"), 16, "logs are never burned"); T.eq(slotsOf(t, "minecraft:oak_planks"), 8)
end)

T.test("turtle core: sticks and biofuel are the last resort, after coal", function()
  local items = { [1] = { "minecraft:stick", 20 }, [2] = { "mekanism:bio_fuel", 4 }, [3] = { "minecraft:charcoal", 1 } }
  local w, t = setup({ items = items, fuel = 0, body = 'core.fuel.refuelFromInventory(100)' })
  t:run("probe"); w:run(5)
  -- order: biofuel (5 each) comes before charcoal (80) and sticks (5): 4 x 5 = 20, charcoal 80 -> 100
  T.eq(slotsOf(t, "mekanism:bio_fuel"), 0); T.eq(slotsOf(t, "minecraft:charcoal"), 0)
  T.eq(slotsOf(t, "minecraft:stick"), 20, "target reached before the sticks")
end)

T.test("turtle core: GPS falls back to the last fix on a timeout, and says it's stale", function()
  local w, t = setup({ body = [[
    local ok, x, y, z, stale = core.gps.locate(1)
    result.first = { ok, x, y, z, stale }
    GPS_ON_NEXT = true
    os.sleep(2)
    local ok2, x2, y2, z2, stale2 = core.gps.locate(1, 1)
    result.second = { ok2, x2, y2, z2, stale2 }
  ]] })
  t:run("probe"); w:run(1)
  w.gpsOn = false                      -- the GPS goes away after the first fix
  w:run(5)
  local r = t.env._G.result
  T.eq(r.first[1], true); T.eq(r.first[5], false); T.eq(r.first[2], 0); T.eq(r.first[3], 64)
  T.eq(r.second[1], true, "the last fix is still returned"); T.eq(r.second[5], true, "but marked stale")
  T.eq(r.second[4], 0)
end)

T.test("turtle core: no GPS and no earlier fix is ok = false", function()
  local w, t = setup({ gps = false, body = 'result.r = { core.gps.locate(1) }' })
  t:run("probe"); w:run(3)
  T.eq(t.env._G.result.r[1], false)
end)

-- A stand-in Storage: answers a dock_report with an ack
local function storage(w, silent)
  local s = w:computer{ id = 1, label = "Storage" }
  s:attach("top", cc.wireless{ ender = true })
  s:writeFile("storage.lua", ([[
    rednet.open("top")
    reports = {}
    while true do
      local from, msg = rednet.receive("tanis-base", 1)
      if type(msg) == "table" and msg.type == "dock_report" then
        reports[#reports + 1] = msg
        if not %s then rednet.send(from, { type = "dock_ack", id = msg.id, assigned = "minecraft:barrel_3" }, "tanis-base") end
      end
    end
  ]]):format(tostring(silent == true)))
  s:run("storage")
  return s
end

T.test("turtle core: reports its dock to Storage and gets the assigned barrel back", function()
  local w, t = setup({ body = [[
    rednet.open("right")
    core.dock.set({ x = 0, y = 64, z = -1 }, "north")
    result.ack = core.dock.report({ role = "lumberjack" })
  ]] })
  t:attach("right", cc.wireless{ ender = true })
  local s = storage(w)
  w:run(1)
  t:run("probe"); w:run(10)
  local rep = s.env._G.reports[1]
  T.truthy(rep, "storage got the report")
  T.eq(rep.type, "dock_report"); T.eq(rep.id, 5); T.eq(rep.x, 0); T.eq(rep.y, 64); T.eq(rep.z, -1); T.eq(rep.dir, "north")
  T.eq(rep.role, "lumberjack")
  T.eq(t.env._G.result.ack.assigned, "minecraft:barrel_3")
end)

T.test("turtle core: a silent Storage only costs a short wait, no error", function()
  local w, t = setup({ body = [[
    rednet.open("right")
    core.dock.set({ x = 0, y = 64, z = -1 }, "north")
    local ack, why = core.dock.report({ timeout = 1, tries = 2 })
    result.ack, result.why, result.t = ack, why, os.clock()
  ]] })
  t:attach("right", cc.wireless{ ender = true })
  storage(w, true)
  t:run("probe"); w:run(10)
  local r = t.env._G.result
  T.eq(r.ack, nil); T.eq(r.why, "no answer")
  T.truthy(r.t < 5, "gave up after two short tries")
end)

T.test("turtle core: dock.visit runs the way back even if the job fails", function()
  local w, t = setup({ body = [[
    local log = {}
    core.dock.setHooks({ go = function() log[#log + 1] = "go" end, back = function() log[#log + 1] = "back" end })
    local ok = core.dock.visit(function() log[#log + 1] = "job"; error("boom") end)
    result.log, result.ok = table.concat(log, ","), ok
  ]] })
  t:run("probe"); w:run(2)
  T.eq(t.env._G.result.log, "go,job,back"); T.eq(t.env._G.result.ok, false)
end)

T.test("farmbot (Woodpecker, Partridge) runs on the core: GPS fixes, dock position, no old copies", function()
  local w, t = setup({ body = [[
    local B = dofile("farmbot.lua")
    result.core = B.core == core or type(B.core) == "table"
    result.x, result.y, result.z = B.locate(1)
    B.Z = { anchor = { x = 100, y = 64, z = 200, f = 1 }, home = "2,3", dockDir = 0 }
    result.dock = { B.dockPos() }
    B.Z.dockDir = "up"; result.up = { B.dockPos() }
    result.fuel = B.fuel()
  ]] })
  t:run("probe"); w:run(2)
  local r = t.env._G.result
  T.truthy(r.core); T.eq(r.x, 0); T.eq(r.y, 64); T.eq(r.fuel, 100)
  -- home 2,3 facing north is z-1: local (2,0,2); anchor turned one quarter: (x,z) -> (-z,x) = (-2, 2)
  T.eq(r.dock[1], 98); T.eq(r.dock[2], 64); T.eq(r.dock[3], 202)
  T.eq(r.up[2], 65, "an up dock is one block higher")
  for _, f in ipairs({ "shared/farmbot.lua", "turtle/woodpecker/lumberjack.lua", "turtle/partridge/farmer.lua" }) do
    local fh = io.open(cc.ROOT .. "/" .. f); local src = fh:read("*a"); fh:close()
    T.falsy(src:find("DOCK_FUEL", 1, true), f .. " still has a fuel table")
    T.falsy(src:find("pcall(gps.locate", 1, true), f .. " still calls gps.locate itself")
    T.falsy(src:find("turtle.refuel", 1, true), f .. " still calls turtle.refuel")
  end
end)

T.test("turtle core: every turtle role gets the core files from the manifest", function()
  local manifest = assert(load(io.open(cc.ROOT .. "/manifest.lua"):read("*a"), "@manifest.lua", "t", {}))()
  for _, id in ipairs(manifest.types.turtle.order) do
    local have = {}
    for _, f in ipairs(manifest.types.turtle.roles[id].files) do have[f] = true end
    for _, f in ipairs(manifest.types.turtle.core) do T.truthy(have[f], id .. " is missing " .. f) end
  end
end)

T.test("Woodpecker on the core: low on fuel it goes to its dock, drinks the lava bucket, bucket goes back, dock reported", function()
  local w = cc.world()
  w.gpsOn = true
  local dock = cc.Inv.new{ size = 27, types = BARREL }
  dock:give("minecraft:lava_bucket", 1)
  w:setBlock(0, 64, -1, "minecraft:barrel", dock)
  w:fill(-3, 63, -3, 3, 63, 3, "minecraft:grass_block")
  local t = w:turtle{ id = 5, label = "Woodpecker-01", x = 0, y = 64, z = 0, facing = 0, fuel = 120,
                      left = "minecraft:diamond_axe", right = "computercraft:wireless_modem_advanced" }
  t:installRole("woodpecker")
  -- a map the turtle already made: one lane cell next to its dock, pinned to GPS (farm 0,0 = world 0,64,0, north up)
  t:writeTable("lumberjack.zone", { cells = { ["0,0"] = "lane", ["0,-1"] = "dock" }, spots = {}, dockDir = 0, count = 1,
                                   home = "0,0", v = 2, anchor = { x = 0, y = 64, z = 0, f = 0 } })
  local s = storage(w)
  t:run("lumberjack")
  w:run(60)
  T.running(t)
  T.truthy(t.body.fuel >= 1000, "he drank the lava: fuel " .. tostring(t.body.fuel))
  T.eq(dock:count("minecraft:lava_bucket"), 0)
  T.eq(dock:count("minecraft:bucket"), 1, "the empty bucket is back in the dock")
  T.eq(slotsOf(t, "minecraft:bucket"), 0)
  local rep = s.env._G.reports and s.env._G.reports[1]
  T.truthy(rep, "Storage was told where his dock is")
  T.eq(rep.label, "Woodpecker-01"); T.eq(rep.x, 0); T.eq(rep.y, 64); T.eq(rep.z, -1)
end)
