-- Weaver v2 (#86): pairs with a stub Architect, builds two layers from the cell lists it sends, restocks from an
-- ender chest that fills slowly (stub storage), leaves gaps for a block storage lacks and fills them when it turns
-- up, and carries on after a reboot mid-layer.
local cc = require("sim.cc")
local T  = require("sim.test")
local W  = require("sim.weaver")

local PROTO = "tanis-weaver"
local TYPES = { "stone", "cobblestone", "sandstone", "smooth_sandstone", "cut_sandstone", "bricks", "stone_bricks",
                "oak_planks", "spruce_planks", "birch_planks", "glass", "white_wool", "orange_wool", "red_wool" }
local RED = "minecraft:red_wool"

-- layer 1: 7 x 6 cells at y 0, layer 2: 7 x 4 at y 1, x 3..9, z 3..8. Cell = { x, y, z, name }.
local function plan()
  local layers, expected = { {}, {} }, {}
  local k = 0
  for z = 3, 8 do for x = 3, 9 do
    k = k + 1
    local name = "minecraft:" .. TYPES[(k - 1) % #TYPES + 1]
    table.insert(layers[1], { x, 0, z, name }); expected[x .. ",0," .. z] = name
  end end
  for z = 3, 6 do for x = 3, 9 do
    k = k + 1
    local name = "minecraft:" .. TYPES[(k - 1) % #TYPES + 1]
    table.insert(layers[2], { x, 1, z, name }); expected[x .. ",1," .. z] = name
  end end
  return layers, expected
end

local ARCHITECT = [[
  rednet.open("top")
  local P = "tanis-weaver"
  local data = textutils.unserialize(fs.open("layers.dat", "r").readAll())
  local N = 2
  _G.acks, _G.done, _G.filled, _G.last = 0, {}, nil, nil
  local function sendLayer(k)
    local cells = data.layers[k]
    if not cells then return end
    local parts = math.ceil(#cells / 20)
    for p = 1, parts do
      local chunk = {}
      for i = (p - 1) * 20 + 1, math.min(#cells, p * 20) do chunk[#chunk + 1] = cells[i] end
      rednet.broadcast({ type = "layer", n = N, hash = data.hash, layer = k, total = #data.layers, part = p, parts = parts, cells = chunk }, P)
    end
  end
  local paired = false
  while not paired do
    local id, m = rednet.receive(P, 2)
    if type(m) == "table" and m.type == "hello" then
      rednet.send(id, { type = "pair", n = N }, P)
    elseif type(m) == "table" and m.type == "paired" then paired = true end
  end
  _G.paired = true
  rednet.broadcast({ type = "build", n = N, name = "Test", hash = data.hash, total = #data.layers }, P)
  sendLayer(1); sendLayer(2)
  rednet.broadcast({ type = "order", n = N, want = "build", seq = 1 }, P)
  while true do
    local id, m = rednet.receive(P, 1)
    if type(m) == "table" and m.n == N then
      if m.type == "layer_ack" then _G.acks = _G.acks + 1
      elseif m.type == "layer_done" then
        if not _G.done[m.layer] then _G.done[m.layer] = m.skipped; sendLayer(m.layer + 2) end
      elseif m.type == "gaps_filled" then _G.filled = m.cells
      elseif m.type == "dock_req" then
        _G.dockReqs = (_G.dockReqs or 0) + 1
        if _G.dock then rednet.broadcast({ type = "site", n = N, dock = _G.dock, dh = 0 }, P) end
      elseif m.type == "status" then _G.last = m; _G.nstat = (_G.nstat or 0) + 1 end
    end
    if _G.sendGaps then rednet.broadcast({ type = "gaps", n = N, cells = _G.sendGaps }, P); _G.sendGaps = nil end
  end
]]

local STORAGE = [[
  rednet.open("top")
  local P = "tanis-weaver"
  local CH = "enderstorage:ender_chest_0"
  local chest, stock = peripheral.wrap(CH), peripheral.wrap("minecraft:barrel_0")
  local replies = {}
  _G.requests = 0
  while true do
    local id, m = rednet.receive(P)
    if type(m) == "table" and m.type == "supply" then
      local key = m.n .. ":" .. m.seq
      if replies[key] then rednet.broadcast(replies[key], P)
      else
        _G.requests = _G.requests + 1
        for slot in pairs(chest.list()) do stock.pullItems(CH, slot) end        -- the clear
        local have = {}
        for _, it in pairs(stock.list()) do have[it.name] = (have[it.name] or 0) + it.count end
        local want, sent, missing = {}, {}, {}
        for name, n in pairs(m.items) do want[name] = n end
        if (m.fuel or 0) > 0 then want["minecraft:lava_bucket"] = math.ceil(m.fuel / 1000) end
        for name, n in pairs(want) do
          local g = math.min(n, have[name] or 0)
          if g > 0 then sent[name] = g end
          if g < n then missing[name] = n - g end
        end
        replies[key] = { type = "supplied", n = m.n, seq = m.seq, sent = sent, missing = missing }
        rednet.broadcast(replies[key], P)
        for name, g in pairs(sent) do               -- the chest fills slowly: a stack every 2 s
          while g > 0 do
            for slot, it in pairs(stock.list()) do
              if it.name == name and g > 0 then g = g - stock.pushItems(CH, slot, g); sleep(2) end
            end
          end
        end
      end
    end
  end
]]

local function setup(opts)
  opts = opts or {}
  local layers, expected = plan()
  if opts.layers then layers, expected = opts.layers, opts.expected end
  local site = W.site{ code = { "red", "blue", "white" }, label = "Weaver-tmp", fuel = opts.fuel or 20000 }
  local w = site.w
  site:home(0)
  local stock = site.net:add("minecraft:barrel_0", cc.Inv.new{ size = 54, types = { "minecraft:barrel", "inventory" } })
  for _, t in ipairs(TYPES) do if "minecraft:" .. t ~= RED or opts.red then stock:give("minecraft:" .. t, 64) end end
  stock:give("minecraft:lava_bucket", 4)
  stock:give("minecraft:sandstone_slab", 8)
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(site.net)); st:attach("top", cc.wireless{ ender = true })
  st:writeFile("s.lua", STORAGE); st:run("s")
  local ar = w:computer{ id = 2, label = "Architect" }
  ar:attach("top", cc.wireless{ ender = true })
  ar:writeTable("layers.dat", { hash = "h1", layers = layers })
  ar:writeFile("a.lua", ARCHITECT); ar:run("a")
  local t = site.turtle
  t.label = nil
  t:installRole("weaver")
  w.gpsOn = opts.gps or false
  t:writeTable("weaver.cfg", opts.cfg or { dh = 0 })
  t:writeFile("startup.lua", 'shell.run("weaver")\n')
  return site, w, t, ar, st, stock, expected, layers
end

local function check(w, expected, missing)
  local exp = {}
  for k, v in pairs(expected) do if not (missing and missing[k]) then exp[k] = v end end
  W.expect(w, exp, { oy = 65, box = { 0, 65, 0, 12, 68, 12 } })
end

local function redCells(expected)
  local m = {}
  for k, v in pairs(expected) do if v == RED then m[k] = true end end
  return m
end

T.test("weaver v2: pairs, builds two layers, restocks from a slow chest, leaves and fills gaps", function()
  local site, w, t, ar, st, stock, expected = setup()
  t:reboot()
  T.waitFor(w, function() return ar.G.paired end, 60, "never paired")
  T.eq(t:readTable("weaver.state").n, 2)
  T.eq(t.label, "Weaver-02")
  T.waitFor(w, function() return ar.G.done and ar.G.done[2] end, 4000, "layer 2 never finished")
  T.truthy(st.G.requests >= 2, "he should have restocked more than once")
  T.truthy(ar.G.acks > 0, "layers were never acknowledged")
  local red = redCells(expected)
  check(w, expected, red)                                   -- everything but the red wool
  local skipped = #ar.G.done[1] + #ar.G.done[2]
  local n = 0; for _ in pairs(red) do n = n + 1 end
  T.eq(skipped, n)
  -- the wool turns up: the Architect sends the gap list and he fills it
  stock:give(RED, 64)
  local cells = {}
  for _, g in ipairs(ar.G.done[1]) do cells[#cells + 1] = g end
  for _, g in ipairs(ar.G.done[2]) do cells[#cells + 1] = g end
  table.sort(cells, function(a, b) return a[2] < b[2] end)
  ar.G.sendGaps = cells
  T.waitFor(w, function() return ar.G.filled end, 2000, "gaps never filled")
  check(w, expected)
  T.eq(#ar.G.filled, n)
end)

T.test("weaver v2: a reboot mid-layer resumes at the same cell and finishes the build", function()
  local site, w, t, ar, st, stock, expected = setup({ red = true })
  t:reboot()
  T.waitFor(w, function() local s = t:readTable("weaver.state"); return s and s.layer == 1 and s.idx and s.idx > 15 and not s.turning end, 3000, "never got going")
  t:reboot()                                                -- cut off mid-layer
  w:run(2)
  T.waitFor(w, function() return ar.G.done and ar.G.done[2] end, 4000, "never finished after the reboot")
  check(w, expected)
  T.eq(#ar.G.done[1] + #ar.G.done[2], 0)
end)

T.test("weaver v2: a reboot while waiting for a delivery picks the request up again", function()
  local site, w, t, ar, st, stock, expected = setup({ red = true })
  t:reboot()
  T.waitFor(w, function() local s = t:readTable("weaver.state"); return s and s.sup and s.sup.reply and not s.turning end, 600, "never asked")
  t:reboot()
  T.waitFor(w, function() return ar.G.done and ar.G.done[2] end, 4000, "never finished after the reboot")
  check(w, expected)
end)

T.test("weaver v2: a double slab goes down twice", function()
  local layers = { { { 3, 0, 3, "minecraft:sandstone_slab", how = "2", n = 2 }, { 4, 0, 3, "minecraft:sandstone_slab" } },
                   { { 5, 1, 5, "minecraft:stone" } } }
  local expected = { ["3,0,3"] = { name = "minecraft:sandstone_slab", state = { type = "double" } },
                     ["4,0,3"] = { name = "minecraft:sandstone_slab", state = { type = "bottom" } },
                     ["5,1,5"] = "minecraft:stone" }
  local site, w, t, ar = setup({ red = true, layers = layers, expected = expected })
  t:reboot()
  T.waitFor(w, function() return ar.G.done and ar.G.done[2] end, 2000, "never finished")
  W.expect(w, expected, { oy = 65, box = { 0, 65, 0, 12, 68, 12 } })
end)

-- #87: block state. Cells are the planner's entries (docs/systems/weaver.md section 8).
local DIR = { "north", "east", "south", "west" }
local L = { north = "N", east = "E", south = "S", west = "W" }
local function stairsPlan()
  local L1, L2, exp = {}, {}, {}
  local ST = "minecraft:sandstone_stairs"
  -- add(list, x, y, z, name, extra fields, expected block (default: name + state))
  local function add(Ls, x, y, z, name, f, want)
    f = f or {}
    f[1], f[2], f[3], f[4] = x, y, z, name
    table.insert(Ls, f)
    exp[x .. "," .. y .. "," .. z] = want or { name = name, state = f.state }
  end
  for i, f in ipairs(DIR) do
    add(L1, 2 + i, 0, 3, ST, { turn = L[f], state = { facing = f, half = "bottom" } })   -- block under: bottom
    add(L2, 2 + i, 1, 5, ST, { turn = L[f], how = "T", state = { facing = f, half = "top" } })  -- air under: top
  end
  add(L2, 8, 1, 3, ST, { how = "F", d = "S", turn = "S", state = { facing = "south", half = "bottom" } })
  -- top slab over a block: slab first, then the block from its east side
  add(L2, 10, 1, 5, "minecraft:sandstone_slab", { how = "T", state = { type = "top" } })
  add(L2, 10, 0, 5, "minecraft:stone", { how = "B", d = "E" }, "minecraft:stone")
  -- slabs
  add(L1, 4, 0, 8, "minecraft:sandstone_slab", { how = "2", n = 2, state = { type = "double" } })
  add(L1, 5, 0, 8, "minecraft:sandstone_slab", { state = { type = "bottom" } })
  add(L2, 6, 1, 8, "minecraft:sandstone_slab", { how = "T", state = { type = "top" } })
  -- wall torch on stone, from the side; stone first
  add(L1, 8, 0, 8, "minecraft:stone", nil, "minecraft:stone")
  add(L2, 8, 1, 8, "minecraft:stone", nil, "minecraft:stone")
  add(L2, 8, 1, 7, "minecraft:wall_torch", { how = "F", d = "S", turn = "S", item = "minecraft:torch", state = { facing = "north" } },
      { name = "minecraft:wall_torch", state = { facing = "north" } })
  -- gate faces the heading, chest faces back at him
  add(L1, 3, 0, 10, "minecraft:oak_fence_gate", { turn = "S", state = { facing = "south" } })
  add(L1, 5, 0, 10, "minecraft:chest", { turn = "W", state = { facing = "east" } })
  add(L1, 7, 0, 10, "minecraft:chest", { turn = "S", state = { facing = "north" } })
  return { L1, L2 }, exp
end

T.test("weaver v2 (#87): stairs in all 8 states, slabs, wall torch, gate and chest come out as the plan says", function()
  local layers, expected = stairsPlan()
  local site, w, t, ar, st, stock = setup({ layers = layers, expected = expected })
  for _, n in ipairs({ "sandstone_stairs", "sandstone_slab", "oak_fence_gate", "chest", "torch" }) do
    stock:give("minecraft:" .. n, 16)
  end
  t:reboot()
  T.waitFor(w, function() return ar.G.done and ar.G.done[2] end, 6000, "never finished")
  T.eq(#ar.G.done[1] + #ar.G.done[2], 0, "nothing should be skipped")
  check(w, expected)
end)

T.test("weaver v2 (#87): a reboot in the middle of a turn: sorted out by the block ahead, else lost", function()
  for _, case in ipairs({ { block = true, h = 1 }, { block = false, lost = true } }) do
    local site, w, t, ar = setup({ layers = { { { 3, 0, 3, "minecraft:stone" } }, {} }, expected = {} })
    t:reboot()
    T.waitFor(w, function() return ar.G.paired end, 60, "never paired")
    t:_stop()                                               -- cut off; he faces north, the turn was to the east
    local s = t:readTable("weaver.state")
    s.h, s.turning = 0, { from = 0, to = 1, ahead = false }
    s.want = nil
    t:writeTable("weaver.state", s)
    if case.block then w:setBlock(0, 65, -1, "minecraft:stone") end  -- what he now sees ahead differs from before the turn
    t:reboot()
    w:run(5)                                               -- boot waits for a GPS answer that never comes
    local r = t:readTable("weaver.state")
    T.eq(r.turning, nil)
    if case.lost then T.truthy(r.lost, "same block ahead: heading unknown") else T.eq(r.h, case.h); T.falsy(r.lost) end
  end
end)

T.test("weaver v2: old island-Weaver files (world coordinates) never send him off; he starts fresh at his dock", function()
  local site, w, t = setup()
  t:writeTable("weaver.cfg", { dx = 40, dy = 64, dz = -30, dh = 0, plan = "mossy.plan" })
  t:writeTable("weaver.state", { x = 40, y = 64, z = -30, h = 0, want = "idle" })
  local x, y, z = site.body.x, site.body.y, site.body.z
  t:reboot()
  w:run(5)
  T.contains(t.screen, "WEAVER SETUP")
  T.eq(site.body.x, x); T.eq(site.body.y, y); T.eq(site.body.z, z)
  T.eq(t:readTable("weaver.state"), nil)
  -- off his dock (no chest under him): setup stops with an error and he doesn't move at all
  local site2, w2, t2 = setup()
  t2:writeTable("weaver.cfg", { dx = 40, dy = 64, dz = -30, dh = 0 })
  t2:writeTable("weaver.state", { x = 40, y = 64, z = -30, h = 0, want = "idle" })
  w2:setBlock(site2.body.x, site2.body.y - 1, site2.body.z, nil)
  local x2, z2 = site2.body.x, site2.body.z
  t2:reboot(); w2:run(10)
  T.contains(t2.error or "", "No chest or barrel under me")
  t2.error = nil                                            -- the expected stop, not a failure of the test
  T.eq(t2:readTable("weaver.state"), nil, "stopped in setup, nothing saved")
  T.eq(site2.body.x, x2); T.eq(site2.body.z, z2)
end)

T.test("weaver v2 (#139): far from the dock with no build he stays put and reports lost, still sending status", function()
  local site, w, t, ar = setup({ layers = { {}, {} }, expected = {} })
  t:reboot()
  T.waitFor(w, function() return ar.G.paired end, 60, "never paired")
  t:_stop()
  local s = t:readTable("weaver.state")
  s.x, s.z, s.want, s.build, s.hash, s.total = 900, -700, "idle", nil, nil, nil
  t:writeTable("weaver.state", s)
  local x, y, z = site.body.x, site.body.y, site.body.z
  t:reboot()
  w:run(20)
  T.eq(site.body.x, x); T.eq(site.body.y, y); T.eq(site.body.z, z)
  local r = t:readTable("weaver.state")
  T.truthy(r.lost, "should be lost")
  T.eq(r.x, 900)
  T.eq(ar.G.last.state, "lost")
  T.eq(ar.G.last.x, 900); T.eq(ar.G.last.h, 0)
end)

T.test("weaver v2 (#139): idle off the dock with no Architect and no build: stays where he is", function()
  local site, w, t = setup({ layers = { {}, {} }, expected = {} })
  t:writeTable("weaver.state", { x = 5, y = 0, z = 5, h = 0, n = 2, want = "idle", short = {}, skip = {}, orderSeq = 0, supSeq = 0, topY = -1 })
  local x, z = site.body.x, site.body.z
  t:reboot()
  w:run(20)
  T.eq(site.body.x, x); T.eq(site.body.z, z)
  T.falsy(t:readTable("weaver.state").lost)
end)

T.test("weaver v2 (#139): waiting at an unloaded chunk border keeps sending status", function()
  local site, w, t, ar = setup({ layers = { { { 3, 0, 3, "minecraft:stone" } }, {} }, expected = {} })
  local loaded = false
  site.body.chunkGate = function(x, z) return loaded or z > site.body.z - 1 + 1 end   -- nothing north of the dock
  t:reboot()
  T.waitFor(w, function() return ar.G.paired end, 60, "never paired")
  T.waitFor(w, function() return ar.G.last and ar.G.last.state == "waiting" end, 600, "never waited at the border")
  local n = ar.G.nstat
  w:run(60)
  T.truthy(ar.G.nstat >= n + 10, "status should keep coming while he waits")
  T.eq(ar.G.last.state, "waiting")
  loaded = true
end)

T.test("weaver v2: the island's old plan file is deleted at boot, so a full 1 MB disk builds again", function()
  local site, w, t, ar = setup()
  t.hddCapacity = 1000000
  t:writeFile("mossy.plan", string.rep("x", 900000))
  t:writeFile("weaver.gaps.new", "old")
  t:reboot()
  T.waitFor(w, function() return ar.G.done and ar.G.done[1] end, 3000, "layer 1 never finished")
  T.eq(t.files["mossy.plan"], nil); T.eq(t.files["weaver.gaps.new"], nil)
end)

T.test("weaver v2: a full disk stops him with a clear message and leaves weaver.state readable", function()
  local site, w, t, ar = setup()
  t:reboot()
  T.waitFor(w, function() return ar.G.paired end, 60, "never paired")
  t.hddCapacity = 1000000
  local n = 0; for _, d in pairs(t.files) do n = n + #d end
  t:writeFile("junk.dat", string.rep("x", 1000000 - n - 40))   -- room for almost nothing
  w:run(60)
  T.contains(t.error or "", "Disk full")
  t.error = nil
  T.truthy(type(t:readTable("weaver.state")) == "table", "weaver.state must survive a failed write")
end)

-- #140: GPS. The sim's dock is at world (0, 65, 0): the turtle's own cell on the ender chest.
local WORLD_DOCK = { x = 0, y = 65, z = 0 }
local function midBuild(w, t)
  T.waitFor(w, function() local s = t:readTable("weaver.state"); return s and s.layer == 1 and s.idx and s.idx > 6
    and not s.turning and not s.pending end, 3000, "never got going")
  t:_stop()
  return t:readTable("weaver.state")
end

T.test("weaver v2 (#140): GPS puts a wrong saved position and heading right, and he builds in the right place", function()
  local site, w, t, ar, st, stock, expected = setup({ red = true, gps = true, cfg = { dh = 0, wx = 0, wy = 65, wz = 0 } })
  t:reboot()
  local s = midBuild(w, t)
  local good = { s.x, s.y, s.z, s.h }
  s.x, s.z, s.h = s.x + 3, s.z - 2, (s.h + 2) % 4                 -- carried off: wrong position, wrong heading
  s.want = "build"; t:writeTable("weaver.state", s)
  t:reboot()
  T.waitFor(w, function() return ar.G.done and ar.G.done[2] end, 6000, "never finished")
  check(w, expected)
  T.eq(#ar.G.done[1] + #ar.G.done[2], 0)
  T.truthy(ar.G.last.gps, "status should say GPS is ok")
  T.truthy(ar.G.last.fix, "status should carry the last fix")
  T.truthy(t:readTable("weaver.state").gnote, "the correction should be noted")
end)

T.test("weaver v2 (#140): no dock position saved: he asks the Architect, gets it, and carries on building", function()
  local site, w, t, ar, st, stock, expected = setup({ red = true, gps = true })
  ar.G.dock = WORLD_DOCK
  t:reboot()
  local s = midBuild(w, t)
  s.h = (s.h + 2) % 4                                              -- wrong heading; GPS knows without a dock position
  s.want = "build"; t:writeTable("weaver.state", s)
  t:reboot()
  T.waitFor(w, function() return ar.G.done and ar.G.done[2] end, 6000, "never finished")
  check(w, expected)
  T.truthy(ar.G.dockReqs and ar.G.dockReqs >= 1, "he should have asked for the dock position")
  local c = t:readTable("weaver.cfg")
  T.eq(c.wx, 0); T.eq(c.wy, 65); T.eq(c.wz, 0)
end)

T.test("weaver v2 (#140): no GPS: dead reckoning as before, status says no GPS and he still builds", function()
  local site, w, t, ar, st, stock, expected = setup({ red = true })
  t:reboot()
  T.waitFor(w, function() return ar.G.done and ar.G.done[2] end, 4000, "never finished")
  check(w, expected)
  T.eq(ar.G.last.gps, false)
end)

T.test("weaver v2 (#140): lost with a fix, he works out where he is and gets home himself", function()
  local site, w, t, ar = setup({ red = true, gps = true, cfg = { dh = 0, wx = 0, wy = 65, wz = 0 } })
  t:reboot()
  T.waitFor(w, function() return ar.G.paired end, 60, "never paired")
  local s = t:readTable("weaver.state")
  s.lost, s.x, s.z, s.want = true, 400, 400, "stop"                -- an impossible saved position
  t:_stop(); t:writeTable("weaver.state", s)
  t:reboot()
  w:run(60)
  local r = t:readTable("weaver.state")
  T.falsy(r.lost, "with a fix he is never lost")
  T.eq(r.x, 0); T.eq(r.z, 0)
end)
