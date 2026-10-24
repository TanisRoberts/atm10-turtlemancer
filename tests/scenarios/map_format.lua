-- World map format (shared/mapchunk.lua): run-length chunks, old files still load.
local cc = require("sim.cc")
local T  = require("sim.test")

local function pure()
  local env = setmetatable({ os = os }, { __index = _G })
  return assert(loadfile(cc.ROOT .. "/shared/mapchunk.lua", "t", env))()
end

local function filled(mc, f)
  local t = {}
  for n = 1, 256 do t[n] = f(n) end
  return mc.fromArray(t)
end

local OCEAN = function(mc) return filled(mc, function() return mc.pack(62, mc.DEEP) end) end
-- a made-up island chunk: sand rim, hills, a few trees, shallow shore, one unseen strip
local function island(mc, seed)
  return filled(mc, function(n)
    local x, z = (n - 1) % 16, math.floor((n - 1) / 16)
    if z == 15 then return 0 end
    local d = math.abs(x - 8) + math.abs(z - 8)
    if d > 12 then return mc.pack(62, mc.DEEP) end
    if d > 10 then return mc.pack(61, mc.SHALLOW) end
    if (x * 7 + z * 3 + seed) % 11 == 0 then return mc.pack(70 + d % 3, mc.FOLIAGE) end
    return mc.pack(64 + math.floor((12 - d) / 3) + (x + z) % 2, mc.LAND)
  end)
end

T.test("map: an all-ocean chunk is a few characters and round-trips", function()
  local mc = pure()
  local o = OCEAN(mc)
  local e = mc.encode(o)
  T.eq(#e < 10, true)
  T.eq(mc.decode(e), o)
end)

T.test("map: never-seen columns stay never-seen, not ocean", function()
  local mc = pure()
  T.eq(mc.decode(mc.encode(mc.EMPTY)), mc.EMPTY)
  local d = island(mc, 1)
  local back = mc.decode(mc.encode(d))
  T.eq(mc.get(back, 3, 15), 0)                       -- unseen strip
  T.eq(mc.get(back, 0, 0), mc.pack(62, mc.DEEP))
  for n = 1, 256 do
    local a, b = mc.unpack(mc.toArray(d)[n]), mc.unpack(mc.toArray(back)[n])
    T.eq(a, b)
  end
end)

T.test("map: runs of every length, and deep water of any height, round-trip", function()
  local mc = pure()
  for _, len in ipairs{ 1, 2, 3, 4, 63, 64, 65, 255, 256 } do
    local d = filled(mc, function(n) return n <= len and mc.pack(70, mc.LAND) or mc.pack(65, mc.SHALLOW) end)
    T.eq(mc.decode(mc.encode(d)), d)
  end
  local lake = filled(mc, function() return mc.pack(90, mc.DEEP) end)
  T.eq(mc.decode(mc.encode(lake)), OCEAN(mc))        -- open water keeps no height
  T.eq(mc.decode("AA.EB"), nil)                      -- 257 columns
  T.eq(mc.decode("AA.AB"), nil)                      -- 1 column
  T.eq(mc.decode("A"), nil)
end)

T.test("map: save and load, old files load, sizes", function()
  local w = cc.world()
  local c = w:computer{ id = 1, label = "Art" }
  c:install("shared/mapchunk.lua")
  c:writeFile("t.lua", [[
    local mc = dofile("mapchunk.lua")
    local function fill(f) local t = {} for n = 1, 256 do t[n] = f(n) end return mc.fromArray(t) end
    local ocean = fill(function() return mc.pack(62, mc.DEEP) end)
    local isle = fill(function(n)
      local x, z = (n - 1) % 16, math.floor((n - 1) / 16)
      local d = math.abs(x - 8) + math.abs(z - 8)
      if z == 15 then return 0 end
      if d > 12 then return mc.pack(62, mc.DEEP) end
      if d > 10 then return mc.pack(61, mc.SHALLOW) end
      return mc.pack(64 + math.floor((12 - d) / 3) + (x + z) % 2, mc.LAND)
    end)
    -- a 16x16-chunk region: the middle 4x4 is island, the rest ocean
    local chunks, old = {}, {}
    for cx = 0, 15 do for cz = 0, 15 do
      local d = (cx >= 6 and cx < 10 and cz >= 6 and cz < 10) and isle or ocean
      chunks[cx .. "," .. cz] = { rev = 1729785600000 + cx, data = d }
    end end
    mc.save("new.map", chunks)
    local f = fs.open("old.map", "w")          -- the old format: 512 characters per chunk
    for k, ch in pairs(chunks) do f.writeLine(k .. " " .. ch.rev .. " " .. ch.data) end
    f.close()
    local a, b = mc.load("new.map"), mc.load("old.map")
    local same = true
    for k, ch in pairs(chunks) do
      if not a[k] or a[k].data ~= ch.data or a[k].rev ~= ch.rev then same = false end
      if not b[k] or b[k].data ~= ch.data then same = false end
    end
    mc.save("converted.map", b)
    RESULT = { same = same, new = fs.getSize("new.map"), old = fs.getSize("old.map"),
               conv = fs.getSize("converted.map"), ocean = #mc.encode(ocean), isle = #mc.encode(isle) }
    local allOcean = {}
    for cx = 0, 15 do for cz = 0, 15 do allOcean[cx .. "," .. cz] = { rev = 1729785600000, data = ocean } end end
    mc.save("ocean.map", allOcean)
    RESULT.oceanFile = fs.getSize("ocean.map")
  ]])
  c:run("t")
  w:run(1)
  local r = c.env._G.RESULT
  T.eq(r.same, true)
  T.eq(r.conv, r.new)
  T.eq(r.ocean < 10, true)
  T.eq(r.new * 3 < r.old, true)
  print(("map sizes: ocean chunk %d B, island chunk %d B; 16x16 region old %d B, new %d B, all-ocean file %d B")
    :format(r.ocean, r.isle, r.old, r.new, r.oceanFile))
end)
