-- Seagull maps region by region (#68): chunk by chunk with the chunk controller, the region held back until it is
-- whole, handed over with region_ok, forgotten, then the next region (spiral, or the one tapped). Regions are
-- 2 x 2 chunks here (REGION_CHUNKS=2) so a pass takes a few virtual minutes.
local cc = require("sim.cc")
local T = require("sim.test")
local flycheck = require("sim.flycheck")

local BARREL = { "minecraft:barrel", "inventory" }

-- A Geo Scanner that reads the sim's blocks
local function geoScanner(turtleOf)
  local s = { types = { "geo_scanner" }, peripheralMethods = { "scanBlocks" }, scans = 0 }
  function s:scanBlocks(r)
    local b = turtleOf()
    self.scans = self.scans + 1
    local out = {}
    for dx = -r, r do for dy = -r, r do for dz = -r, r do
      local blk = b.world:getBlock(b.x + dx, b.y + dy, b.z + dz)
      if blk then out[#out + 1] = { x = dx, y = dy, z = dz, name = blk.name, tags = {} } end
    end end end
    if self.check then self.check.observe(out, b.x, b.y, b.z, r) end
    return out
  end
  return s
end

-- Cartographer stand-in: asks for chunks, records what arrives, says region_ok once a done region is whole
local STUB = [==[
  rednet.open("top")
  local P = "tanis-carto"
  okSet = {}
  held, early, oks, statuses, scanRegions, doneSeen = {}, 0, {}, 0, {}, {}
  sid, last, cmds = nil, nil, {}
  local lastHave = -100
  function send(msg) rednet.send(sid, msg, P) end
  while true do
    local from, msg = rednet.receive(P, 1)
    if type(msg) == "table" then
      if msg.type == "status" then
        sid, last = from, msg
        statuses = statuses + 1
        if msg.scan_region then scanRegions[msg.scan_region[1] .. "," .. msg.scan_region[2]] = true end
        if msg.done_region then
          local rk = msg.done_region[1] .. "," .. msg.done_region[2]
          doneSeen[rk] = true
          local n = 0
          for k in pairs(held) do
            local cx, cz = k:match("^(-?%d+),(-?%d+)$")
            if math.floor(cx / 2) == msg.done_region[1] and math.floor(cz / 2) == msg.done_region[2] then n = n + 1 end
          end
          if n >= 4 and not hold then
            rednet.send(from, { type = "region_ok", to = from, region = msg.done_region }, P)
            if not okSet[rk] then okSet[rk] = true; oks[#oks + 1] = rk end
          end
        end
      elseif msg.type == "chunks" then
        for k, c in pairs(msg.chunks or {}) do
          -- still scanning (a status can be 3 s old, so the last two chunks don't count)
          if last and last.wp and last.wps and last.wp <= last.wps - 2 and not last.done_region then early = early + 1 end
          held[k] = c
        end
      end
    end
    if sid and os.clock() - lastHave > 10 then
      lastHave = os.clock()
      local revs = {}
      for k, c in pairs(held) do revs[k] = c.rev end
      send({ type = "have", to = sid, revs = revs })
    end
    if order then
      cmds[#cmds + 1] = order
      if sid then send(order) end
      order = nil
    end
  end
]==]

local function setup(envExtra, build, handover)
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 60, -40, 70, 63, 70, "minecraft:stone")
  if build then build(w) end
  local dock = cc.Inv.new{ size = 27, types = BARREL }
  w:setBlock(0, 64, -1, "minecraft:barrel", dock)
  dock:give("minecraft:lava_bucket", 4)
  local t = w:turtle{ id = 7, label = "Seagull-01", x = 0, y = 64, z = 0, facing = 0, fuel = 0,
                      right = "computercraft:wireless_modem_advanced",
                      items = { [1] = { "advancedperipherals:chunk_controller", 1 } } }
  t:installRole("seagull")
  t:attach("right", cc.wireless{ ender = true })
  local scanner = geoScanner(function() return t.body end)
  t:attach("left", scanner)
  -- every scenario runs with the fly check (tests/sim/flycheck.lua); the launch tube is his dock's own wall
  t.scanner = scanner
  scanner.check = flycheck.watch(t, { exempt = function(x, z) return math.abs(x) <= 1 and math.abs(z) <= 1 end })
  t:writeFile("seagull.env", "REGION_CHUNKS=2\nHANDOVER_WAIT=" .. (handover or 0) .. "\n" .. (envExtra or ""))
  local carto = w:computer{ id = 3, label = "Cartographer" }
  carto:attach("top", cc.wireless{ ender = true })
  carto:writeFile("stub.lua", STUB)
  carto:run("stub")
  w:run(1)
  t:run("seagull")
  return w, t, carto, dock, scanner
end

local function G(c) return c.G end
-- He has taken region_ok and forgotten the region (the stub says it as soon as the hand-over is announced, which
-- is while he is still flying home)
local function settled(w, t)
  T.waitFor(w, function() local st = t:readTable("seagull.state"); return st and st.doneRegion == nil end, 600, "he never forgot the region")
end
local function order(c, o) G(c).order = o end

T.test("seagull: MAP maps the home region chunk by chunk, hands it over whole, forgets it", function()
  local w, t, carto, dock, scanner = setup()
  w:run(30)
  T.contains(t.screen:text(), "Ready")
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 1500)
  settled(w, t)
  local g = G(carto)
  T.truthy(g.scanRegions["0,0"], "the status named scan_region 0,0 while he scanned")
  T.truthy(g.doneSeen["0,0"], "the status named done_region 0,0")
  T.eq(g.early, 0, "no chunk of the region reached the Cartographer before it was whole")
  local n = 0
  for _ in pairs(g.held) do n = n + 1 end
  T.eq(n, 4, "all four chunks arrived")
  -- the sea of stone is all LAND at y 63: every column known in every chunk
  local mc = assert(loadfile(cc.ROOT .. "/shared/mapchunk.lua", "t", { string = string, math = math, table = table, pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber, type = type, fs = {}, select = select, pcall = pcall, error = error, setmetatable = setmetatable }))()
  for k, c in pairs(g.held) do
    for _, v in ipairs(mc.toArray(c.data)) do if v == 0 then T.truthy(false, "chunk " .. k .. " has an unseen column"); break end end
  end
  local st = t:readTable("seagull.state")
  T.eq(st.region, nil, "he forgot the region")
  T.eq(st.doneRegion, nil)
  T.truthy(st.done["0,0"], "it is on his done list")
  T.eq(st.mapping, false)
  T.truthy(t.body.fuel > 0)
  T.contains(t.screen:text(), "done")
  local map = t:readFile("seagull.map") or ""
  T.eq(map:find("%d+,%d+") == nil or not map:find("^%d"), true)
  T.truthy(scanner.scans >= 4, "at least one scan per chunk")
end)

T.test("seagull: MAP again goes to the next region in the spiral; a tapped region goes first", function()
  local w, t, carto = setup()
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 1500)
  settled(w, t)
  -- tap region 0,-1 (north of home), then MAP: he goes there, not to the spiral's first pick
  w:run(1)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 2, next = { 0, -1 } })
  T.waitFor(w, function() return #G(carto).oks >= 2 end, 2500)
  T.eq(G(carto).oks[2], "0,-1")
  T.truthy(G(carto).scanRegions["0,-1"])
  settled(w, t)
  local st = t:readTable("seagull.state")
  T.eq(st.nextReg, nil, "the tap is used up")
  -- MAP once more: the spiral's next unmapped region round home (0,0 and 0,-1 are done): ring 1, top edge, (1,-1)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 3 })
  T.waitFor(w, function() return #G(carto).oks >= 3 end, 3500)
  T.eq(G(carto).oks[3], "1,-1")
end)

T.test("seagull: CRUISE_Y: between his dock and the region he flies at that height or higher, inside it low", function()
  local w, t, carto = setup("CRUISE_Y=80\n")
  w:run(30)
  G(carto).hold = true             -- no region_ok yet: he flies home still holding the region, as in game
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1, next = { 1, 0 } })   -- region 1,0: x 32 .. 63
  local outside, inside, leftAt = math.huge, math.huge, nil
  T.waitFor(w, function()
    local b = t.body
    if not leftAt and (b.x ~= 0 or b.z ~= 0) then leftAt = b.y end
    if b.x >= 3 and b.x <= 28 then outside = math.min(outside, b.y) end
    if b.x >= 36 and b.x <= 60 then inside = math.min(inside, b.y) end
    return G(carto).doneSeen["1,0"]
  end, 2500, "region 1,0 was never finished")
  T.eq(leftAt, 80, "straight up from the dock to CRUISE_Y before any sideways move")
  T.eq(outside >= 80, true, "on the way he never went below CRUISE_Y (lowest " .. tostring(outside) .. ")")
  T.eq(inside < 80, true, "over the region he flies low to scan (lowest " .. tostring(inside) .. ")")
  -- home at cruising height the whole way, over the region he finished too, and no dipping to look for ground
  local dips, climbedAt = 0, nil
  for _ = 1, 120 do
    w:run(1)
    local b = t.body
    if not climbedAt and b.y >= 80 then climbedAt = b.x end
    if climbedAt and b.x >= 1 and b.x < climbedAt and b.y < 80 then dips = dips + 1 end
  end
  T.eq(climbedAt ~= nil and climbedAt >= 36, true, "he climbed to CRUISE_Y over the region, not only after leaving it (at x " .. tostring(climbedAt) .. ")")
  T.eq(dips, 0, "on the way home he stayed at CRUISE_Y")
  T.eq(t.body.x .. "," .. t.body.y .. "," .. t.body.z, "0,64,0", "home on his dock")
  G(carto).hold = false
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 300, "region_ok never came")
  T.eq(G(carto).oks[1], "1,0")
end)

T.test("seagull: a region on his done list is mapped again when the Cartographer names it (re-survey)", function()
  local w, t, carto = setup()
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 1500)
  settled(w, t)
  T.truthy(t:readTable("seagull.state").done["0,0"])
  G(carto).scanRegions = {}
  order(carto, { type = "cmd", to = 7, want = "map", seq = 2, next = { 0, 0 } })
  T.waitFor(w, function() return G(carto).scanRegions["0,0"] end, 300, "he never scanned 0,0 again")
  T.waitFor(w, function()
    local st = t:readTable("seagull.state")
    return st and st.region == nil and st.mapping == false
  end, 1500, "the re-survey never finished")
  T.truthy(t:readTable("seagull.state").done["0,0"])
end)

-- A launch tube: stone walls round his spot from y 64 to 75 (the dock barrel is the north wall at y 64), open sky above
local function tube(w)
  for y = 64, 75 do
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if not (y == 64 and d[1] == 0 and d[2] == -1) then w:setBlock(d[1], y, d[2], "minecraft:stone") end
    end
  end
end

T.test("seagull: in a launch tube he finds his facing at the top, climbs straight out, and comes home down it", function()
  local w, t, carto = setup(nil, tube)          -- no CRUISE_Y: the tube's walls alone decide how high he climbs
  w:run(60)
  T.contains(t.screen:text(), "Ready")
  T.eq(t.body.x .. "," .. t.body.y .. "," .. t.body.z, "0,64,0", "back on his dock after finding his facing")
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1, next = { 1, 0 } })
  local leftLow = false
  T.waitFor(w, function()
    local b = t.body
    if (b.x ~= 0 or b.z ~= 0) and math.abs(b.x) <= 1 and math.abs(b.z) <= 1 and b.y <= 75 then leftLow = true end
    return #G(carto).oks >= 1
  end, 2500, "region 1,0 was never finished")
  T.eq(leftLow, false, "he never moved sideways inside the tube")
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
  w:run(90)
  T.eq(t.body.x .. "," .. t.body.y .. "," .. t.body.z, "0,64,0", "home down the tube")
end)

T.test("seagull: boxed in (nothing open, not even up) he says so and skips nothing", function()
  local w, t, carto = setup()
  w:run(30)
  tube(w); w:setBlock(0, 65, 0, "minecraft:stone")       -- a lid right above him
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1, next = { 1, 0 } })
  w:run(120)
  T.contains(t.screen:text(), "Can't climb straight up")
  local st = t:readTable("seagull.state")
  T.eq(st.skipped or 0, 0, "no chunk skipped while he can't move")
  T.eq(st.ci, 1, "still on the first chunk")
end)

T.test("seagull: chunks with no map after the first pass get one more try before the region is handed over", function()
  local w, t, carto = setup()
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() local st = t:readTable("seagull.state"); return st and st.region and (st.ci or 0) >= 3 end, 1500)
  -- as if chunks 1 and 2 had been skipped: no map for them, and the first pass carries on from chunk 3
  t:_stop()
  local st = t:readTable("seagull.state")
  st.cp, st.ci = 3, 3
  t:writeTable("seagull.state", st)
  t.files["seagull.map"] = nil
  t:reboot(); t:run("seagull")
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 2500, "the region was never handed over")
  local n = 0
  for _ in pairs(G(carto).held) do n = n + 1 end
  T.eq(n, 4, "all four chunks arrived, the two missing ones from the second try")
end)

T.test("seagull: a cliff taller than a scan with a ledge sticking out: he backs out from under it and goes over", function()
  local w, t, carto = setup(nil, function(w)
    w:fill(10, 64, -20, 12, 95, 40, "minecraft:stone")      -- a cliff across his way east, up to y 95
    w:fill(9, 72, -20, 9, 72, 40, "minecraft:stone")        -- a one-block ledge sticking out of it at y 72
  end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1, next = { 1, 0 } })   -- region 1,0: over the cliff
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 4000, "region 1,0 was never finished")
  local st = t:readTable("seagull.state")
  T.eq(st.skipped or 0, 0, "no chunk skipped")
  w:run(200)
  T.eq(t.body.x .. "," .. t.body.y .. "," .. t.body.z, "0,64,0", "and home again, back over the cliff")
end)

T.test("seagull: a reboot mid-region carries on with the same region; nothing is skipped", function()
  local w, t, carto = setup()
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function()
    local st = t:readTable("seagull.state")
    return st and st.region and (st.ci or 0) >= 3
  end, 1500)
  local before = t:readTable("seagull.state")
  T.eq(before.region[1], 0); T.eq(before.region[2], 0)
  t:reboot()
  w:run(10)
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 2500)
  T.eq(G(carto).oks[1], "0,0", "the same region finished")
  T.eq(G(carto).early, 0)
  local n = 0
  for _ in pairs(G(carto).held) do n = n + 1 end
  T.eq(n, 4)
end)

T.test("seagull: without region_ok he keeps the region and says it again", function()
  local w, t, carto = setup()
  G(carto).hold = true
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() return G(carto).doneSeen["0,0"] end, 1500)
  w:run(200)
  local st = t:readTable("seagull.state")
  T.truthy(st.doneRegion, "still holding the region")
  T.contains(t.screen:text(), "WAITING")
  -- MAP while waiting does nothing
  order(carto, { type = "cmd", to = 7, want = "map", seq = 2 })
  w:run(30)
  T.truthy(t:readTable("seagull.state").doneRegion)
  G(carto).hold = false
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 300)
  w:run(10)
  T.eq(t:readTable("seagull.state").doneRegion, nil)
end)

local MCENV = { string = string, math = math, table = table, pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber, type = type, fs = {}, select = select, pcall = pcall, error = error, setmetatable = setmetatable }
local function loadMC() return assert(loadfile(cc.ROOT .. "/shared/mapchunk.lua", "t", MCENV))() end

-- Anything solid above (x, y, z) up to 40 blocks: he is under a roof
local function roofed(w, b)
  for k = 1, 40 do
    local blk = w:getBlock(b.x, b.y + k, b.z)
    if blk and blk.name ~= "minecraft:air" then return true end
  end
  return false
end

T.test("seagull: a pit and a ravine deeper than a scan: he flies over, never sinks in, and the hole is low ground on the map", function()
  local w, t, carto, dock, scanner = setup(nil, function(w)
    w:fill(12, 41, 4, 15, 63, 7, "air")          -- a 4 x 4 pit down to y 41 (floor y 40, below)
    w:fill(12, 40, 4, 15, 40, 7, "minecraft:stone")
    w:fill(3, 41, 0, 4, 63, 15, "air")           -- a ravine 2 wide across the whole chunk
    w:fill(3, 40, 0, 4, 40, 15, "minecraft:stone")
  end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local lowest = math.huge
  T.waitFor(w, function()
    lowest = math.min(lowest, t.body.y)
    return #G(carto).oks >= 1
  end, 2500)
  T.truthy(lowest >= 64, "he never went below the surface round the holes (lowest y " .. lowest .. ")")
  local c = G(carto).held["0,0"]
  T.truthy(c, "chunk 0,0 arrived")
  local mc = loadMC()
  for _, v in ipairs(mc.toArray(c.data)) do if v == 0 then T.truthy(false, "an unseen column"); break end end
  local y = mc.unpack(mc.get(c.data, 13, 5))
  T.truthy(y < 60, "the pit shows as low ground (y " .. tostring(y) .. ")")
  local r = mc.unpack(mc.get(c.data, 3, 8))
  T.truthy(r < 60, "so does the ravine (y " .. tostring(r) .. ")")
  T.eq(mc.unpack(mc.get(c.data, 8, 8)), 63, "ground beside them is still ground")
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
end)

T.test("seagull: a cave mouth under a cliff: he maps round it without ever going under the rock", function()
  local w, t, carto = setup(nil, function(w)
    w:fill(8, 64, 8, 11, 75, 11, "minecraft:stone")   -- a cliff standing on the ground
    w:fill(5, 50, 9, 11, 63, 10, "air")               -- a cave under it, open to the sky at x 5..7
  end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local under, lowest = 0, math.huge
  T.waitFor(w, function()
    if roofed(w, t.body) then under = under + 1 end
    lowest = math.min(lowest, t.body.y)
    return #G(carto).oks >= 1
  end, 2500)
  T.eq(under, 0, "never a roof above him")
  T.truthy(lowest >= 64, "never below the surface (lowest y " .. lowest .. ")")
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
  local mc = loadMC()
  T.truthy(mc.unpack(mc.get(G(carto).held["0,0"].data, 6, 9)) < 60, "the cave mouth is low ground")
  T.eq(mc.unpack(mc.get(G(carto).held["0,0"].data, 9, 9)), 75, "the cliff top is on the map")
end)

T.test("seagull: rebooted deep in a cave he climbs out to open sky, says so, and goes home", function()
  local w, t, carto, _, scanner = setup(nil, function(w)
    w:fill(20, 64, -4, 44, 78, 12, "minecraft:stone")    -- a hill with the dock side open to the west
    w:fill(20, 65, 4, 40, 67, 4, "air")                  -- a tunnel from its west face into the hill, dead end at x 40
  end)
  w:run(30)
  t:_stop()
  scanner.check.off = true       -- he starts in the rock on purpose: backing out of a tunnel is under a known roof
  t.body.x, t.body.y, t.body.z = 38, 66, 4
  t:reboot(); t:run("seagull")
  local sawMsg, roof = false, false
  local ok = pcall(T.waitFor, w, function()
    if t.screen:text():find("Underground") then sawMsg = true end
    return t.body.x == 0 and t.body.y == 64 and t.body.z == 0
  end, 1500)
  T.truthy(ok, "he never got home: at " .. t.body.x .. "," .. t.body.y .. "," .. t.body.z .. " " .. t.screen:text():sub(1, 300))
  T.truthy(sawMsg, "the screen said he was underground")
  w:run(30)
  T.contains(t.screen:text(), "Ready")
end)

---------------------------------------------------------------------------
-- #114: over everything, never through
---------------------------------------------------------------------------
local function lowestWhile(w, t, carto, max, extra)
  local lowest = math.huge
  local ok, err = pcall(T.waitFor, w, function()
    lowest = math.min(lowest, t.body.y)
    if extra then extra() end
    return #G(carto).oks >= 1
  end, max or 3000, "the region was never handed over")
  if not ok then
    error(tostring(err) .. "\n  he is at " .. t.body.x .. "," .. t.body.y .. "," .. t.body.z .. " fuel " .. tostring(t.body.fuel) .. " moves " .. t.scanner.check.moves .. " scans " .. t.scanner.scans
      .. "\n" .. t.screen:text() .. "\n" .. tostring(t:readFile("seagull.state")):sub(1, 400), 0)
  end
  return lowest
end

T.test("seagull: a ravine deeper than a scan: mapped, saved as pits, a reboot over it, and he never sinks in", function()
  local w, t, carto = setup(nil, function(w)
    w:fill(11, 31, 0, 13, 63, 31, "air")          -- 3 wide, 33 deep, across the whole region
    w:fill(11, 30, 0, 13, 30, 31, "minecraft:stone")
  end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local lowest, rebooted = math.huge, false
  T.waitFor(w, function()
    lowest = math.min(lowest, t.body.y)
    if not rebooted then
      local pits = t:readFile("seagull.pits")
      if pits and pits:find('"12,', 1, true) and t.body.x >= 11 and t.body.x <= 13 then
        rebooted = true
        t:reboot()          -- right over the ravine
      end
    end
    return #G(carto).oks >= 1
  end, 3000, "the region was never handed over")
  T.truthy(rebooted, "the pits were saved while he was over the ravine")
  T.truthy(lowest >= 64, "he never went below the surface (lowest y " .. lowest .. ")")
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
  local mc = loadMC()
  local c = G(carto).held["0,0"]
  T.truthy(mc.unpack(mc.get(c.data, 12, 8)) < 60, "the ravine is low ground on the map")
  T.eq(mc.unpack(mc.get(c.data, 8, 8)), 63, "ground beside it is still ground")
  w:run(30)
  T.absent(t:readFile("seagull.pits") or "", '"12,', "the pits go with the region at hand-over")
end)

T.test("seagull: a cave mouth in a hillside on his hop line: he goes over the hill, not into it", function()
  local w, t, carto = setup(nil, function(w)
    w:fill(12, 64, 0, 21, 82, 31, "minecraft:stone")      -- a hill across the line from chunk 1 to chunk 2 (z 8)
    w:fill(12, 65, 8, 20, 67, 8, "air")                  -- a tunnel into it from the west, dead end at x 20
  end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local inTunnel = 0
  local lowest = lowestWhile(w, t, carto, 3000, function()
    local b = t.body
    if b.x >= 12 and b.x <= 21 and b.y <= 67 then inTunnel = inTunnel + 1 end
  end)
  T.eq(inTunnel, 0, "he never went into the hill")
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
  local mc = loadMC()
  T.eq(mc.unpack(mc.get(G(carto).held["0,0"].data, 14, 8)), 82, "the hill's top is on the map where the tunnel runs under it")
end)

T.test("seagull: a cliff taller than a scan, climbed in steps, then dropped from: nothing below the surface", function()
  local w, t, carto = setup(nil, function(w)
    w:fill(17, 64, -10, 19, 110, 50, "minecraft:stone")   -- 47 high, 3 thick, across his way east
  end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local lowest = lowestWhile(w, t, carto, 4000)
  T.truthy(lowest >= 64, "lowest y " .. lowest)
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
  w:run(200)
  T.eq(t.body.x .. "," .. t.body.y .. "," .. t.body.z, "0,64,0", "and home again")
end)

T.test("seagull: an overhang over his line (a slab he flies under) is found by the next scan: out the way he came, up, over", function()
  local w, t, carto = setup(nil, function(w) end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local placed, backed = false, false
  lowestWhile(w, t, carto, 4000, function()
    local b = t.body
    -- as he passes x 18 on his way east, a slab appears over the line (from the scans' point of view: from nowhere)
    if not placed and b.x >= 18 and b.z == 8 and b.y <= 70 then
      placed = true
      w:fill(16, b.y + 1, 7, 30, b.y + 1, 9, "minecraft:stone")
    end
    if t.screen:text():find("Underground", 1, true) then backed = true end
  end)
  T.truthy(placed, "the slab was placed")
  T.truthy(backed, "the scan found the roof and he said so")
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
  local mc = loadMC()
  local c = G(carto).held["1,0"]
  T.truthy(c, "chunk 1,0 arrived")
  local top = mc.unpack(mc.get(c.data, 2, 8))
  T.truthy(top >= 63, "nothing mapped from underneath it: the column under the slab reads " .. tostring(top))
end)

T.test("seagull: blocked ahead out of sight: up, then forward, and a roof over the blocked column is backed out of", function()
  local w, t, carto = setup(nil, function(w) end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local placed = false
  lowestWhile(w, t, carto, 4000, function()
    local b = t.body
    if not placed and b.x == 20 and b.z == 8 and b.y <= 70 then
      placed = true
      w:fill(21, b.y - 1, 6, 21, b.y + 1, 10, "minecraft:stone")      -- a wall that wasn't there a moment ago
      w:setBlock(20, b.y + 1, 8, "minecraft:stone")                    -- and a ledge right over him
    end
  end)
  T.truthy(placed)
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
end)

T.test("seagull: dropping from cruise onto a sinkhole: he stops over it, moves sideways to ground he can see, then drops", function()
  local w, t, carto = setup("CRUISE_Y=90\n", function(w)
    w:fill(21, 41, 5, 26, 63, 10, "air")            -- a 6 x 6 sinkhole right at chunk 2's middle (24, 8)
    w:fill(21, 40, 5, 26, 40, 10, "minecraft:stone")
  end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local sunk = false
  local lowest = lowestWhile(w, t, carto, 4000, function()
    if t.body.y < 60 then sunk = true end
  end)
  T.eq(sunk, false, "he never went into the sinkhole")
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
  local mc = loadMC()
  local c = G(carto).held["1,0"]
  T.truthy(mc.unpack(mc.get(c.data, 8, 8)) < 60, "the sinkhole is low ground (its middle is 8,8 in chunk 1,0)")
end)

T.test("seagull: a wall higher than MAX_Y: the chunks behind it are skipped (not mapped from below), and he gets home", function()
  local w, t, carto = setup("MAX_Y=80\n", function(w)
    w:fill(20, 64, -30, 22, 110, 60, "minecraft:stone")
  end)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local okp, errp = pcall(T.waitFor, w, function() return G(carto).doneSeen["0,0"] end, 4000, "he never finished the pass")
  if not okp then error(tostring(errp) .. " at " .. t.body.x .. "," .. t.body.y .. "," .. t.body.z .. " fuel " .. tostring(t.body.fuel) .. "\n" .. t.screen:text() .. tostring(t:readFile("seagull.state")):sub(1, 300), 0) end
  w:run(300)
  local st = t:readTable("seagull.state")
  T.truthy((st.skipped or 0) >= 1 or st.doneRegion, "the chunks behind the wall were skipped")
  T.eq(t.body.x .. "," .. t.body.y .. "," .. t.body.z, "0,64,0", "home again")
end)

T.test("seagull: first boot of this way of flying restarts the unfinished region at chunk 1 and drops its old chunks", function()
  local w, t, carto = setup()
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() local st = t:readTable("seagull.state"); return st and st.region and (st.ci or 0) >= 3 end, 1500)
  t:_stop()
  -- as if the state and map were left by the old version: no version mark, cave-level tops in a chunk
  local mcm = loadMC()
  local bad = mcm.fromArray((function() local a = {} for i = 1, 256 do a[i] = mcm.pack(50, mcm.LAND) end return a end)())
  local st = t:readTable("seagull.state")
  st.flyV, st.cp, st.ci, st.mapping = nil, 3, 3, true
  t:writeTable("seagull.state", st)
  t:writeFile("seagull.map", "#mapv2\n0,0 1000 " .. mcm.encode(bad) .. "\n")
  t:reboot()
  w:run(8)
  local st2 = t:readTable("seagull.state")
  T.eq(st2.flyV, 1, "version mark set")
  T.eq(st2.cp, 1, "checkpoint back at chunk 1")
  T.truthy((st2.ci or 1) <= 2, "restarted at chunk 1 (ci " .. tostring(st2.ci) .. ")")
  T.absent(t:readFile("seagull.map") or "", "0,0 1000", "the old chunk is gone from his map")
  -- and it finishes, with the real tops
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 3000, "the region never finished")
  local c = G(carto).held["0,0"]
  T.eq(mcm.unpack(mcm.get(c.data, 8, 8)), 63, "real tops in the chunk")
  -- a second boot does not restart it again
  w:run(5)
end)

T.test("seagull: the fly check itself: a hover too low over a known top is caught", function()
  local w, t, carto, _, scanner = setup()
  w:run(30)
  t:_stop()
  scanner:scanBlocks(8)                                      -- he has seen the ground at y 63 under him
  t.body.x, t.body.y = 5, 64
  local ok, err = pcall(function() t.body.onMove("forward") end)
  T.eq(ok, false, "a move at y 64 over a top at 63 is a violation")
  T.contains(err, "flycheck")
end)

-- #115: every flight keeps his chunk loaded. The sim refuses a move into a chunk more than one chunk from the last
-- one a controller swap loaded (the home chunks start loaded, as if a player stood there).
local function chunkWorld(w, t)
  local swaps, last = 0, { 0, 0 }
  t.body.onChunkLoad = function(x, z) swaps = swaps + 1; last = { math.floor(x / 16), math.floor(z / 16) } end
  t.body.chunkGate = function(x, z)
    local cx, cz = math.floor(x / 16), math.floor(z / 16)
    if t.body.failOnce and x >= 8 and x <= 28 then t.body.failOnce = nil; return false end
    if math.abs(cx) <= 1 and math.abs(cz) <= 1 and not t.body.homeOff then return true end
    return math.abs(cx - last[1]) <= 1 and math.abs(cz - last[2]) <= 1
  end
  return function() return swaps end
end

T.test("seagull: far region: chunks between are unloaded unless his controller loaded them; he maps, flies home, docks", function()
  local w, t, carto = setup("CRUISE_Y=80\n")
  w:run(30)
  local swaps = chunkWorld(w, t)
  t.body.homeOff = true
  G(carto).hold = true
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1, next = { 2, 0 } })   -- region 2,0: x 64 .. 95
  T.waitFor(w, function() return G(carto).doneSeen["2,0"] end, 3000, "region 2,0 was never finished")
  local before = swaps()
  T.truthy(before >= 4, "swaps while flying out and mapping")
  T.waitFor(w, function() local b = t.body; return b.x == 0 and b.z == 0 and b.y == 64 end, 600, "never got home")
  T.truthy(swaps() > before + 3, "controller swaps on the way home (" .. before .. " -> " .. swaps() .. ")")
  T.absent(t.screen:text(), "unloaded", "no unloaded stop")
  G(carto).hold = false
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 300, "region_ok never came")
  T.eq(t:readTable("seagull.state").skipped or 0, 0, "no chunk skipped")
end)

T.test("seagull: one forced 'unloaded' on the way home: he retries and gets home", function()
  local w, t, carto = setup("CRUISE_Y=80\n")
  w:run(30)
  chunkWorld(w, t)
  t.body.homeOff = true
  G(carto).hold = true
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1, next = { 2, 0 } })
  T.waitFor(w, function() return G(carto).doneSeen["2,0"] end, 3000, "region 2,0 was never finished")
  t.body.failOnce = true
  T.waitFor(w, function() return t.body.x == 0 and t.body.z == 0 and t.body.y == 64 end, 600, "never got home")
  T.eq(t.body.failOnce, nil, "the forced failure happened")
  T.absent(t.screen:text(), "Can't get home", "no stop")
end)

-- Hand-over where he is (#116): the Cartographer is told by radio, so he waits right over his last chunk for
-- region_ok (HANDOVER_WAIT) and, with fuel for it, carries straight on to the next region.
local function isHome(t) return t.body.x == 0 and t.body.y == 64 and t.body.z == 0 end
-- Run until the first hand-over is announced and he is still out over the region
local function hoverOver(w, t, carto)
  T.waitFor(w, function()
    local st = t:readTable("seagull.state")
    return st and st.doneRegion and not isHome(t)
  end, 2500, "region never finished")
end

T.test("seagull: hand-over in place: the next region follows with no dock visit between", function()
  local w, t, carto = setup(nil, nil, 120)
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  local first, home, forgotten, second = nil, false, nil, nil
  T.waitFor(w, function()
    local st = t:readTable("seagull.state")
    if not st then return false end
    first = first or (st.region and st.region[1] .. "," .. st.region[2])
    if G(carto).oks[1] and isHome(t) then home = true end
    if st.doneRegion then T.contains(t.screen:text(), "Handing over") end
    if first and st.region and (st.region[1] .. "," .. st.region[2]) ~= first then
      second = st.region[1] .. "," .. st.region[2]
      forgotten = st.done and st.done[first]
      return true
    end
  end, 3000, "he never started a second region")
  T.eq(forgotten, true, "region 1 was handed over and forgotten before region 2 began")
  T.eq(home, false, "no dock visit between the regions")
  T.eq(G(carto).oks[1], first)
  T.waitFor(w, function() return #G(carto).oks >= 2 end, 3000, "the second region was never handed over")
  T.eq(G(carto).oks[2], second)
end)

T.test("seagull: hand-over in place, low fuel: home to refuel first, then out to the next region", function()
  local w, t, carto, dock = setup(nil, nil, 120)
  w:run(30)
  G(carto).hold = true                    -- no region_ok yet: he hovers over his last chunk
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  hoverOver(w, t, carto)
  w:run(5)
  T.truthy(not isHome(t), "he waits where he is")
  dock:give("minecraft:lava_bucket", 10)   -- Storage brought fuel
  t.body.fuel = 150                       -- not enough for the next region and back
  G(carto).hold = false
  local visited, second = false, nil
  T.waitFor(w, function()
    local st = t:readTable("seagull.state")
    if isHome(t) and G(carto).oks[1] then visited = true end
    if st and st.region and st.done and st.done["0,0"] then second = true; return visited end
  end, 3000, "he never reached the second region")
  T.truthy(visited, "he went home to refuel before region 2")
  T.waitFor(w, function() return not isHome(t) and t.body.fuel > 1000 end, 600, "he never set out again with fuel")
  T.eq(t:readTable("seagull.state").mapping, true, "out to region 2")
end)

T.test("seagull: hand-over in place with no Cartographer: he waits HANDOVER_WAIT, then goes home and waits there", function()
  local w, t, carto = setup(nil, nil, 40)
  w:run(30)
  G(carto).hold = true
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  hoverOver(w, t, carto)
  local x, y, z = t.body.x, t.body.y, t.body.z
  w:run(30)
  T.eq(t.body.x .. "," .. t.body.y .. "," .. t.body.z, x .. "," .. y .. "," .. z, "still hovering inside HANDOVER_WAIT")
  T.waitFor(w, function() return isHome(t) end, 600, "he never went home")
  w:run(30)
  local st = t:readTable("seagull.state")
  T.truthy(st.doneRegion, "he still holds the region: never two unconfirmed")
  T.contains(t.screen:text(), "Waiting for the")
  G(carto).hold = false
  settled(w, t)
  st = t:readTable("seagull.state")
  T.eq(st.region, nil)
  T.eq(st.mapping, false, "handed over at home: he idles, no next region")
  T.truthy(isHome(t))
end)

T.test("seagull: DOCK while he hovers for the hand-over: home, hands over there, no next region", function()
  local w, t, carto = setup(nil, nil, 120)
  w:run(30)
  G(carto).hold = true
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  hoverOver(w, t, carto)
  order(carto, { type = "cmd", to = 7, want = "dock", seq = 2 })
  T.waitFor(w, function() return isHome(t) end, 600, "he never went home")
  G(carto).hold = false
  settled(w, t)
  w:run(60)
  local st = t:readTable("seagull.state")
  T.eq(st.region, nil)
  T.eq(st.mapping, false)
  T.truthy(isHome(t))
end)
