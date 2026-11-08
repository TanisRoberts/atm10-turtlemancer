-- Plan v2 (shared/plan2.lua, plan2place.lua, #85): the writer, the reader, and the placement planner checked end to end:
-- a hand-made .litematic is converted, a scripted turtle places every layer by the planner's list and methods in the
-- sim's world (placement rules of CC:Tweaked), and the world is compared with the file, cell by cell and state by state.
local cc = require("sim.cc")
local T  = require("sim.test")
local W  = require("sim.weaver")

local function load()
  local cache = {}
  local env = setmetatable({}, { __index = _G })
  local function req(name)
    if cache[name] == nil then
      local f = assert(loadfile(cc.ROOT .. "/shared/" .. name .. ".lua", "t", env))
      cache[name] = f() or true
    end
    return cache[name]
  end
  env.require = req
  return req
end
local function slurp(n)
  local f = assert(io.open(cc.ROOT .. "/tests/data/" .. n, "rb")); local s = f:read("*a"); f:close(); return s
end

local function stats(plan)
  local s = plan.info.stats
  return string.format("F=%d T=%d U=%d 2=%d", s.F, s.T, s.U, s["2"])
end

T.test("plan2: the hand-made build converts, with its bill and counts", function()
  local req = load()
  local plan, rep = req("plan2").fromLitematic(slurp("placement.litematic"))
  assert(plan, rep)
  local s = plan.info.stats
  print("placement.litematic: " .. stats(plan))
  T.eq(plan.info.name, "Placement Test")
  T.eq(plan.info.size.x, 12); T.eq(plan.info.size.y, 4 - 1, "empty top layer trimmed"); T.eq(plan.info.size.z, 10)
  T.eq(plan.info.blocks, 152)
  T.eq(s.T, 2, "top stair + top slab over a block"); T.eq(s["2"], 1, "double slab")
  T.eq(s.U, 3, "log row end, top stair on the ground, walled-in top stair")
  -- F: arch stair, bottom slab, torch, three logs, two hay = 8
  T.eq(s.F, 8)
  T.eq(plan.info.bill["minecraft:sandstone_slab"], 3)
  T.eq(plan.info.items["minecraft:sandstone_slab"], 4, "a double slab is two items")
  T.eq(plan.info.items["minecraft:torch"], 1, "a wall torch is a torch")
  T.eq(plan.info.items["minecraft:wall_torch"], nil)
  local reasons = {}
  for _, u in ipairs(plan.ulist) do reasons[u.why] = true end
  T.truthy(reasons["nothing to click"]); T.truthy(reasons["top half on the ground"])
  T.truthy(reasons["no free side to fill the block under it"])
end)

T.test("plan2: write, read back, and the hash catches a changed file", function()
  local req = load()
  local P = req("plan2")
  for _, file in ipairs({ "placement.litematic", "mini.litematic" }) do
    local plan = P.fromLitematic(slurp(file))
    local text = P.text(plan)
    local back, err = P.parse(text)
    assert(back, err)
    T.truthy(back.hashOK, "hash matches")
    T.eq(P.text(back), text, file .. ": the text round-trips")
    for y = 0, plan.info.size.y - 1 do
      for z = 0, plan.info.size.z - 1 do
        for x = 0, plan.info.size.x - 1 do
          if plan.get(x, y, z) ~= back.get(x, y, z) then error("cell differs " .. x .. "," .. y .. "," .. z) end
        end
      end
    end
    local edited = text:gsub("(#L 1\n%d+|%d+|)", "%1" .. "1:1,", 1)
    T.falsy(P.parse(edited).hashOK, "an edited file fails the hash")
    if file == "mini.litematic" then print("mini.litematic: " .. stats(plan)) end
  end
  local back = P.parse(P.text(P.fromLitematic(slurp("placement.litematic"))))
  T.eq(back.marks[2][2 * 12 + 3], "FE", "the arch stair: stand west, face east")
  T.eq(select(2, P.parse("hello")), "not a .plan2 file")
  -- a reloaded .plan2 has no ulist; classify() gives it back with the same marks (the Architect's Simpler list)
  local orig = P.fromLitematic(slurp("placement.litematic"))
  T.eq(back.ulist, nil)
  local saved = {}
  for y, t in pairs(back.marks) do for k, m in pairs(t) do saved[y .. ":" .. k] = m end end
  req("plan2place").classify(back)
  T.eq(#back.ulist, #orig.ulist, "same U cells after a reload")
  T.eq(type(back.ulist[1].why), "string", "with their reasons")
  for y, t in pairs(back.marks) do for k, m in pairs(t) do T.eq(saved[y .. ":" .. k], m, "mark at " .. y .. ":" .. k) end end
end)

-- ---- end to end ----------------------------------------------------------------------------------------------------
local NAMES = { [0] = "north", "east", "south", "west" }
local FIDX = { north = 0, east = 1, south = 2, west = 3 }
local DX, DZ = { [0] = 0, 1, 0, -1 }, { [0] = -1, 0, 1, 0 }
local LIDX = { N = 0, E = 1, S = 2, W = 3 }

-- the expected world, straight from the file's own block states (not from the plan)
local function expectedFrom(req, bytes, rot, ox, oy, oz, uSet)
  local lit = req("litematic")
  local f = lit.read(bytes)
  local t = lit.trim(f)
  local steps = math.floor(rot / 90) % 4
  local exp = {}
  for y = 0, t.size.y - 1 do
    for z = 0, t.size.z - 1 do
      for x = 0, t.size.x - 1 do
        local i = t.get(x, y, z)
        if i and not t.isAir(i) then
          local e = f.palette[i]
          local want = { name = lit.rename(e.name), state = {} }
          local pr = e.props or {}
          if want.name:find("_stairs$") then want.state.facing, want.state.half = pr.facing, pr.half
          elseif want.name:find("_slab$") then want.state.type = pr.type
          elseif want.name:find("_fence_gate$") or want.name:find("chest$") or want.name:find("wall_torch$") then want.state.facing = pr.facing end
          if pr.axis then want.state.axis = pr.axis end
          if want.state.facing then want.state.facing = NAMES[(FIDX[want.state.facing] + steps) % 4] end
          if want.state.axis and want.state.axis ~= "y" and steps % 2 == 1 then want.state.axis = want.state.axis == "x" and "z" or "x" end
          local rx, rz = x, z
          if steps == 1 then rx, rz = -z, x elseif steps == 2 then rx, rz = -x, -z elseif steps == 3 then rx, rz = z, -x end
          local key = (rx + ox) .. "," .. (y + oy) .. "," .. (rz + oz)
          if uSet[x .. "," .. y .. "," .. z] then want = { name = want.name } end   -- placed the default way: name only
          exp[key] = want
        end
      end
    end
  end
  return exp, t
end

-- a scripted turtle (a real turtle program in the sim; it teleports between cells, the placing is the real API): one
-- entry at a time, by the method the planner names. The sim's placement rules decide the state each click gives.
local PROGRAM = [[
while not entries do sleep(0.1) end
for i, e in ipairs(entries) do
  hold(e.item)
  local ok
  if e.how == "F" or e.how == "B" then
    tp(e.sx, e.sy, e.sz, e.face)
    ok = turtle.place()
  elseif e.how == "2" then
    tp(e.sx, e.sy, e.sz, 0)
    ok = turtle.placeDown() and turtle.placeDown()
  else
    tp(e.sx, e.sy, e.sz, e.face)
    ok = turtle.placeDown()
  end
  if not ok then err = "placing " .. e.name .. " at plan " .. e.px .. "," .. e.sy .. "," .. e.pz .. " (" .. tostring(e.how) .. ") failed"; return end
end
done = true
]]

local function runPlan(req, plan, rot, ox, oy, oz)
  local site = W.site{ y = oy - 1, radius = 30 }
  local w, c, b = site.w, site.turtle, site.body
  local place = req("plan2place")
  local entries, counts = {}, { F = 0, T = 0, B = 0, U = 0, ["2"] = 0, default = 0 }
  for y = 0, plan.info.size.y - 1 do
    for _, e in ipairs(place.layer(plan, y, rot)) do
      local x, ey, z = e.x + ox, e.y + oy, e.z + oz
      e.sx, e.sy, e.sz, e.face = x, ey + 1, z, e.turn and LIDX[e.turn] or 0      -- default: hover above, turn, placeDown
      if e.how == "F" then
        local d = LIDX[e.d]
        e.sx, e.sy, e.sz, e.face = x - DX[d], ey, z - DZ[d], d                   -- stand behind, face d
      elseif e.how == "B" then
        local d = LIDX[e.d]                                                      -- the side the Weaver comes down at
        e.sx, e.sy, e.sz, e.face = x + DX[d], ey, z + DZ[d], (d + 2) % 4
      end
      entries[#entries + 1] = e
      counts[e.how or "default"] = counts[e.how or "default"] + 1
    end
  end
  c:writeFile("t.lua", PROGRAM)
  c:run("t")
  w:run(0.5)
  local G = c.G
  G.entries = entries
  G.hold = function(name) b.slots[1] = { name = name, count = 4 }; b.sel = 1 end
  G.tp = function(x, y, z, f) b.x, b.y, b.z, b.facing = x, y, z, f end
  w:runUntil(function() return G.done or G.err or c.error end, 2000)
  if c.error then error("turtle program crashed:\n" .. c.error) end
  if G.err then error(G.err) end
  T.truthy(G.done, "the turtle finished the list")
  return site, #entries, counts
end

for _, rot in ipairs({ 0, 90, 180, 270 }) do
  T.test("plan2: the scripted turtle builds placement.litematic as the file says, turned " .. rot, function()
    local req = load()
    local bytes = slurp("placement.litematic")
    local plan = req("plan2").fromLitematic(bytes)
    local ox, oy, oz = 20, 70, 20
    local uSet = {}
    for _, u in ipairs(plan.ulist) do uSet[u.x .. "," .. u.y .. "," .. u.z] = true end
    local exp = expectedFrom(req, bytes, rot, ox, oy, oz, uSet)
    local site, placed, counts = runPlan(req, plan, rot, ox, oy, oz)
    T.eq(placed, plan.info.blocks, "every cell once (a T fill replaces the cell left out of the layer below)")
    T.eq(counts.B, plan.info.stats.T)
    local ok, bad, total = W.diff(site.w, exp, { box = { 0, oy, 0, 40, oy + 5, 40 }, max = 12 })
    if not ok then error(total .. " cells differ from the file:\n  " .. table.concat(bad, "\n  ")) end
    if rot == 0 then print(("placed %d cells: F=%d T=%d (+%d fills) U=%d 2=%d, all %d match the file"):format(
      placed, counts.F, counts.T, counts.B, counts.U, counts["2"], plan.info.blocks)) end
  end)
end

T.test("plan2: layer order keeps the constraints and each layer lists every cell once", function()
  local req = load()
  local plan = req("plan2").fromLitematic(slurp("placement.litematic"))
  local place = req("plan2place")
  local list = place.layer(plan, 2, 0)
  local pos, seen = {}, {}
  for i, e in ipairs(list) do
    local k = e.px .. "," .. e.pz .. "," .. e.y
    T.falsy(seen[k], "listed once: " .. k); seen[k] = true
    pos[k] = i
  end
  -- the arch stair (3,2) comes before its standing cell (2,2); the torch's wall (0,5) before it (1,5), in layer 2
  T.truthy(pos["3,2,2"] < pos["2,2,2"], "the arch stair before the cell it stands in")
  T.truthy(pos["0,5,2"] < pos["1,5,2"], "the wall before the torch")
  -- T: the top stair is followed at once by the block under it, filled from a side
  local s = pos["6,2,2"]
  T.eq(list[s].how, "T"); T.eq(list[s + 1].how, "B"); T.eq(list[s + 1].y, 1); T.eq(list[s + 1].px, 6)
  T.eq(place.layer(plan, 1, 0)[1].how ~= "B", true)
  -- turned by 90: facings and axes turn, positions turn about the origin
  local r = place.layer(plan, 2, 90)
  for _, e in ipairs(r) do
    if e.px == 3 and e.pz == 2 then T.eq(e.state.facing, "south", "east turned once is south"); T.eq(e.x, -2); T.eq(e.z, 3) end
  end
end)

T.test("plan2: layer 1 leaves out the blocks under the top-half stair and slab (they come with layer 2)", function()
  local req = load()
  local plan = req("plan2").fromLitematic(slurp("placement.litematic"))
  for _, e in ipairs(req("plan2place").layer(plan, 1, 0)) do
    T.falsy((e.px == 6 or e.px == 8) and e.pz == 2, "no filled-from-the-side block in layer 1")
  end
end)

T.test("plan2: an arena-sized build (94 x 28 x 74, 10,000 blocks, stairs everywhere) converts and orders", function()
  local req = load()
  local P = req("plan2")
  local pal = { { name = "minecraft:air" }, { name = "minecraft:sandstone" },
    { name = "minecraft:sandstone_stairs", props = { facing = "north", half = "bottom" } },
    { name = "minecraft:sandstone_stairs", props = { facing = "east", half = "top" } },
    { name = "minecraft:sandstone_slab", props = { type = "top" } },
    { name = "minecraft:sandstone_slab", props = { type = "bottom" } } }
  local r = { size = { x = 94, y = 28, z = 74 }, palette = pal, isAir = function(i) return i == 1 end }
  r.get = function(x, y, z)
    if (x * 7 + z * 13 + y * 5) % 19 > 1 then return 1 end         -- ~10% filled, a mix of every kind
    return 2 + (x + z + y) % 5
  end
  local plan = P.build(r, { name = "arena-sized" })
  print(("arena-sized: %d blocks, F=%d T=%d U=%d 2=%d, %d bytes"):format(plan.info.blocks, plan.info.stats.F, plan.info.stats.T,
    plan.info.stats.U, plan.info.stats["2"], #P.text(plan)))
  local total = 0
  for y = 0, 27 do total = total + #req("plan2place").layer(plan, y, 90) end
  T.eq(total, plan.info.blocks)
  T.truthy(P.parse(P.text(plan)).hashOK)
end)
