-- Litematica reader (shared/litematic*.lua): inflate (stored/fixed/dynamic), NBT, trim, bill, check.
local cc = require("sim.cc")
local T  = require("sim.test")

-- Load the modules the way a device does: shared files land flat, and `require` is the program's own.
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

local WORDS = { "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf" }
local function text(n)
  local t = {}
  for i = 1, 400 do t[#t + 1] = string.format("line %d: %s %s\n", i, WORDS[i * i % 7 + 1], WORDS[(i * 3) % 7 + 1]) end
  local s = table.concat(t)
  return n and s:sub(1, n) or s
end

T.test("litematic: inflate handles stored, fixed and dynamic Huffman blocks", function()
  local inf = load()("litematic_inflate")
  local want = { dynamic = text(), fixed = text(300), stored = text(300) }
  local btype = { dynamic = 2, fixed = 1, stored = 0 }
  for name, expect in pairs(want) do
    local gz = slurp("inflate_" .. name .. ".gz")
    T.eq(math.floor(gz:byte(11) / 2) % 4, btype[name], name .. " stream has the block type it should")
    local out, err = inf.gunzip(gz)
    T.eq(err, nil, name .. " error")
    T.eq(out == expect, true, name .. " decompresses to the original text")
  end
  local yields = 0
  inf.gunzip(slurp("inflate_dynamic.gz"), function() yields = yields + 1 end)
  T.eq(yields > 0, true, "yield callback is called")
  T.eq(select(2, inf.gunzip("not gzip at all, really not gzip")) ~= nil, true, "bad header is refused")
  local bad = slurp("inflate_dynamic.gz"):sub(1, 400)
  T.eq(inf.gunzip(bad), nil, "a truncated stream is refused")
end)

T.test("litematic: read the hand-made file", function()
  local lit = load()("litematic")
  local f, err = lit.read(slurp("mini.litematic"))
  assert(f, err)
  T.eq(f.name, "Mini Test"); T.eq(f.author, "tests"); T.eq(f.nregions, 1)
  T.eq(#f.palette, 26); T.eq(f.bits, 5, "26 entries -> 5 bits")
  T.eq(f.size.x, 6); T.eq(f.size.y, 8); T.eq(f.size.z, 5)
  T.eq(f.origin.x, 5, "negative X size: box grows down from Position 10")
  local function name(x, y, z) return f.palette[f.get(x, y, z)].name end
  T.eq(name(0, 1, 0), "minecraft:stone")
  T.eq(name(4, 4, 4), "minecraft:sandstone")
  T.eq(name(5, 2, 2), "minecraft:air", "empty edge column")
  T.eq(name(3, 6, 1), "minecraft:air", "empty top layer")
  local st = f.palette[f.get(0, 4, 4)]
  T.eq(st.name, "minecraft:sandstone_stairs"); T.eq(st.props.facing, "north"); T.eq(st.props.half, "bottom")
  local w = f.palette[f.get(1, 1, 1)]
  T.eq(w.props.facing, "west"); T.eq(w.props.shape, "inner_left")
  T.eq(f.get(6, 0, 0), nil, "outside the box")
end)

T.test("litematic: trim drops empty layers and the empty edge column", function()
  local lit = load()("litematic")
  local f = lit.read(slurp("mini.litematic"))
  local t = lit.trim(f)
  T.eq(t.original.x, 6); T.eq(t.original.y, 8); T.eq(t.original.z, 5)
  T.eq(t.size.x, 5); T.eq(t.size.y, 4); T.eq(t.size.z, 5)
  T.eq(t.offset.x, 0); T.eq(t.offset.y, 1); T.eq(t.offset.z, 0)
  T.eq(f.palette[t.get(0, 0, 0)].name, "minecraft:stone", "trimmed (0,0,0) is the old (0,1,0)")
  T.eq(f.palette[t.get(4, 3, 4)].name, "minecraft:sandstone")
  T.eq(lit.bill(t).total, 82, "bill of the trimmed view is the same")
end)

T.test("litematic: bill counts blocks and direction-sensitive states", function()
  local lit = load()("litematic")
  local b = lit.bill(lit.read(slurp("mini.litematic")))
  T.eq(b.total, 82); T.eq(b.types, 19)
  T.eq(b.byName["minecraft:sandstone_stairs"], 15)
  T.eq(b.byName["minecraft:sandstone_slab"], 9)
  T.eq(b.byName["minecraft:oak_log"], 6)
  T.eq(b.byName["minecraft:air"], nil, "air is not counted")
  T.eq(b.list[1].name, "minecraft:sandstone_stairs", "list is sorted by count")
  local s = b.states["minecraft:sandstone_stairs"]
  T.eq(s["facing=north,half=bottom"], 5); T.eq(s["facing=east,half=bottom"], 3)
  T.eq(s["facing=south,half=top"], 4); T.eq(s["facing=west,half=top"], 3, "shape is dropped")
  local sl = b.states["minecraft:sandstone_slab"]
  T.eq(sl["type=bottom"], 1); T.eq(sl["type=top"], 4); T.eq(sl["type=double"], 4)
  local lg = b.states["minecraft:oak_log"]
  T.eq(lg["axis=y"], 3); T.eq(lg["axis=x"], 3)
  T.eq(b.states["minecraft:oak_fence"], nil, "fence connections are dropped")
  T.eq(b.states["minecraft:stone"], nil)
  T.eq(b.states["minecraft:wall_torch"]["facing=south"], 4)
end)

T.test("litematic: check reports renamed, unknown and modded blocks", function()
  local lit = load()("litematic")
  local c = lit.check(lit.read(slurp("mini.litematic")))
  T.eq(#c.renamed, 1); T.eq(c.renamed[1].from, "minecraft:grass_path"); T.eq(c.renamed[1].to, "minecraft:dirt_path")
  T.eq(c.renamed[1].count, 3); T.eq(c.renamed[1].known, true)
  T.eq(#c.unknown, 1); T.eq(c.unknown[1].name, "minecraft:fancy_unknown_block")
  T.eq(#c.modded, 1); T.eq(c.modded[1].name, "create:andesite_casing"); T.eq(c.modded[1].note, "modded, not checked")
  T.eq(lit.rename("minecraft:grass"), "minecraft:short_grass"); T.eq(lit.rename("minecraft:stone"), "minecraft:stone")
end)

T.test("litematic: bad input gives an error, not a crash", function()
  local lit = load()("litematic")
  local f, err = lit.read("hello")
  T.eq(f, nil); T.eq(type(err), "string")
  local f2 = lit.read(slurp("inflate_dynamic.gz"))
  T.eq(f2, nil, "a gzip of plain text is not NBT")
end)
