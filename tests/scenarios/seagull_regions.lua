-- Seagull maps region by region (#68): chunk by chunk with the chunk controller, the region held back until it is
-- whole, handed over with region_ok, forgotten, then the next region (spiral, or the one tapped). Regions are
-- 2 x 2 chunks here (REGION_CHUNKS=2) so a pass takes a few virtual minutes.
local cc = require("sim.cc")
local T = require("sim.test")

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

local function setup(envExtra, build)
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 60, -20, 60, 63, 60, "minecraft:stone")
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
  t:writeFile("seagull.env", "REGION_CHUNKS=2\n" .. (envExtra or ""))
  local carto = w:computer{ id = 3, label = "Cartographer" }
  carto:attach("top", cc.wireless{ ender = true })
  carto:writeFile("stub.lua", STUB)
  carto:run("stub")
  w:run(1)
  t:run("seagull")
  return w, t, carto, dock, scanner
end

local function G(c) return c.G end
local function order(c, o) G(c).order = o end

T.test("seagull: MAP maps the home region chunk by chunk, hands it over whole, forgets it", function()
  local w, t, carto, dock, scanner = setup()
  w:run(30)
  T.contains(t.screen:text(), "Ready")
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 1500)
  w:run(20)
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
  w:run(20)
  -- tap region 0,-1 (north of home), then MAP: he goes there, not to the spiral's first pick
  w:run(1)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 2, next = { 0, -1 } })
  T.waitFor(w, function() return #G(carto).oks >= 2 end, 2500)
  T.eq(G(carto).oks[2], "0,-1")
  T.truthy(G(carto).scanRegions["0,-1"])
  w:run(20)
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
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1, next = { 1, 0 } })   -- region 1,0: x 32 .. 63
  local outside, inside = math.huge, math.huge
  T.waitFor(w, function()
    local b = t.body
    if b.x >= 3 and b.x <= 28 then outside = math.min(outside, b.y) end
    if b.x >= 36 and b.x <= 60 then inside = math.min(inside, b.y) end
    return #G(carto).oks >= 1
  end, 2500, "region 1,0 was never finished")
  T.eq(G(carto).oks[1], "1,0")
  T.eq(outside >= 80, true, "on the way he never went below CRUISE_Y (lowest " .. tostring(outside) .. ")")
  T.eq(inside < 80, true, "over the region he flies low to scan (lowest " .. tostring(inside) .. ")")
  -- home at cruising height, no dipping to look for ground the scanner can't reach
  local dips = 0
  for _ = 1, 60 do
    w:run(1)
    local b = t.body
    if b.x >= 3 and b.x <= 28 and b.y < 80 then dips = dips + 1 end
  end
  T.eq(dips, 0, "on the way home he stayed at CRUISE_Y")
  T.eq(t.body.x .. "," .. t.body.y .. "," .. t.body.z, "0,64,0", "home on his dock")
end)

T.test("seagull: a region on his done list is mapped again when the Cartographer names it (re-survey)", function()
  local w, t, carto = setup()
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 1500)
  w:run(20)
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

T.test("seagull: a pit deeper than one scan reaches gets a second scan, so no column stays unseen", function()
  local w, t, carto, dock, scanner = setup()
  -- a 4 x 4 pit in chunk 0,0 down to y 40: the centre scan (y 59..75) cannot see its floor
  w:fill(12, 41, 4, 15, 63, 7, "air")
  w:fill(12, 40, 4, 15, 40, 7, "minecraft:stone")
  w:run(30)
  order(carto, { type = "cmd", to = 7, want = "map", seq = 1 })
  T.waitFor(w, function() return #G(carto).oks >= 1 end, 2000)
  local c = G(carto).held["0,0"]
  T.truthy(c, "chunk 0,0 arrived")
  local mc = assert(loadfile(cc.ROOT .. "/shared/mapchunk.lua", "t", { string = string, math = math, table = table, pairs = pairs, ipairs = ipairs, tostring = tostring, tonumber = tonumber, type = type, fs = {}, select = select, pcall = pcall, error = error, setmetatable = setmetatable }))()
  local unseen = 0
  for _, v in ipairs(mc.toArray(c.data)) do if v == 0 then unseen = unseen + 1 end end
  T.eq(unseen, 0, "every column of the chunk is known")
  local y = mc.unpack(mc.get(c.data, 13, 5))
  T.eq(y, 40, "the pit floor is on the map")
end)
