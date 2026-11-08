-- litematic: read a Litematica .litematic file (gzipped NBT) in plain Lua 5.2. Pure functions, no peripherals,
-- no globals. Loaded with require("litematic"); needs litematic_inflate, litematic_nbt, mcblocks_1211 beside it.
-- Runs in CraftOS (doubles only, no zlib) and under lupa. Pass `yield` (e.g. function() sleep(0) end) in opts
-- so CraftOS never says "too long without yielding"; the sim and lupa pass nothing.
--
--   lit.read(bytes, {yield=f}) -> file | nil, err
--       file = { name, author, enclosing={x,y,z}, nregions, note, regions={r...}, + the first region's fields }
--       region r = { name, origin={x,y,z}, size={x,y,z} (abs), palette={{name=,props={}}...},
--                    get(x,y,z) -> palette index (1-based into r.palette; x,y,z are 0-based inside the box),
--                    isAir(i) -> bool, yield }
--       A multi-region file reports nregions>1 and note "N regions, only the first is read".
--   lit.trim(r) -> { size, offset={x,y,z}, original={x,y,z}, get, palette, isAir, empty }  (all-air layers/rows/columns dropped)
--   lit.bill(r) -> { total, types, byName={name=n}, list={{name,count}...} sorted, states={name={["facing=north,half=top"]=n}} }
--   lit.check(r) -> { renamed={{from,to,count}}, unknown={{name,count}}, modded={{name,count}} }; lit.rename(name) -> new name
--
-- r and trim() results both work with bill/check/trim. Block states are never guessed: unknown stays unknown.

local inflate = require("litematic_inflate")
local nbt = require("litematic_nbt")

local M = {}

local AIR = { ["minecraft:air"] = true, ["minecraft:cave_air"] = true, ["minecraft:void_air"] = true }

-- Names that changed between the Litematica file's version and 1.21.1 (each checked against minecraft-data).
M.RENAMES = {
  ["minecraft:grass_path"] = "minecraft:dirt_path", -- 1.17
  ["minecraft:grass"] = "minecraft:short_grass",     -- 1.20.3
}
function M.rename(name) return M.RENAMES[name] or name end

-- Properties the builder must reproduce. Everything else (fence/wall connections, stair shape, waterlogged,
-- leaf distance, powered, open, ...) fixes itself or doesn't matter and is dropped.
local KEEP = { "facing", "half", "type", "axis" }

local function stateKey(props)
  if not props then return nil end
  local parts = {}
  for _, k in ipairs(KEEP) do
    if props[k] then parts[#parts + 1] = k .. "=" .. tostring(props[k]) end
  end
  if #parts == 0 then return nil end
  return table.concat(parts, ",")
end
M.stateKey = stateKey

local function counter(r)
  local n = 0
  return function(k)
    n = n + k
    if n >= 4000 then
      n = 0
      if r.yield then r.yield() end
    end
  end
end

local function buildRegion(name, reg, yield)
  local sz = reg.Size or {}
  local sx, sy, sz_ = math.abs(sz.x or 0), math.abs(sz.y or 0), math.abs(sz.z or 0)
  local pos = reg.Position or { x = 0, y = 0, z = 0 }
  local function lo(p, s) return (p or 0) + (s < 0 and s + 1 or 0) end -- negative size: box grows from Position downwards
  local rs = { x = sz.x or 0, y = sz.y or 0, z = sz.z or 0 }
  local palette = {}
  for i, e in ipairs(reg.BlockStatePalette or {}) do
    local props
    if e.Properties then
      props = {}
      for k, v in pairs(e.Properties) do props[k] = v end
    end
    palette[i] = { name = e.Name or "?", props = props }
  end
  if #palette == 0 then error("region '" .. name .. "' has no block palette", 0) end
  local air = {}
  for i, e in ipairs(palette) do air[i] = AIR[e.name] or false end
  local width = 2
  while 2 ^ width < #palette do width = width + 1 end
  local arr = reg.BlockStates or { longs = "", n = 0 }
  local cells = sx * sy * sz_
  if arr.n * 64 < cells * width then
    error(string.format("region '%s': %d cells x %d bits need %d longs, file has %d", name, cells, width, math.ceil(cells * width / 64), arr.n), 0)
  end
  local r = {
    name = name,
    origin = { x = lo(pos.x, rs.x), y = lo(pos.y, rs.y), z = lo(pos.z, rs.z) },
    size = { x = sx, y = sy, z = sz_ },
    palette = palette,
    bits = width,
    yield = yield,
  }
  function r.get(x, y, z)
    if x < 0 or y < 0 or z < 0 or x >= sx or y >= sy or z >= sz_ then return nil end
    return nbt.bits(arr, (x + z * sx + y * sx * sz_) * width, width) + 1
  end
  function r.isAir(i) return air[i] == true end
  return r
end

function M.read(bytes, opts)
  local yield = opts and opts.yield
  local ok, res = pcall(function()
    local raw = bytes
    if bytes:byte(1) == 0x1f and bytes:byte(2) == 0x8b then
      local s, err = inflate.gunzip(bytes, yield)
      if not s then error(err, 0) end
      raw = s
    end
    local _, root = nbt.parse(raw, yield)
    local regs = root.Regions
    if not regs then error("no Regions in this file (is it a .litematic?)", 0) end
    local names = {}
    for k in pairs(regs) do names[#names + 1] = k end
    table.sort(names)
    if #names == 0 then error("the file has no regions", 0) end
    local meta = root.Metadata or {}
    local f = {
      name = meta.Name, author = meta.Author,
      enclosing = meta.EnclosingSize and { x = meta.EnclosingSize.x, y = meta.EnclosingSize.y, z = meta.EnclosingSize.z },
      totalBlocks = meta.TotalBlocks, version = root.Version, dataVersion = root.MinecraftDataVersion,
      nregions = #names, regions = {},
    }
    -- Region order in NBT is not kept by pairs(); sort by name so "the first" is stable.
    for i, n in ipairs(names) do f.regions[i] = buildRegion(n, regs[n], yield) end
    if #names > 1 then f.note = #names .. " regions, only the first is read" end
    local r1 = f.regions[1]
    f.size, f.origin, f.palette, f.get, f.isAir, f.bits = r1.size, r1.origin, r1.palette, r1.get, r1.isAir, r1.bits
    f.yield = yield
    return f
  end)
  if not ok then return nil, tostring(res) end
  return res
end

-- One pass over every cell: bounds of the non-air cells and the count per palette index. Cached on the region.
local function scan(r)
  if r._scan then return r._scan end
  local sx, sy, sz = r.size.x, r.size.y, r.size.z
  local tick = counter(r)
  local counts = {}
  for i = 1, #r.palette do counts[i] = 0 end
  local x0, y0, z0, x1, y1, z1 = sx, sy, sz, -1, -1, -1
  local get, isAir = r.get, r.isAir
  for y = 0, sy - 1 do
    for z = 0, sz - 1 do
      for x = 0, sx - 1 do
        local i = get(x, y, z)
        counts[i] = counts[i] + 1
        if not isAir(i) then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
          if z < z0 then z0 = z end
          if z > z1 then z1 = z end
        end
      end
      tick(sx)
    end
  end
  r._scan = { counts = counts, x0 = x0, y0 = y0, z0 = z0, x1 = x1, y1 = y1, z1 = z1 }
  return r._scan
end

function M.trim(r)
  local s = scan(r)
  local out = { _src = r._src or r, original = r.original or { x = r.size.x, y = r.size.y, z = r.size.z }, palette = r.palette, isAir = r.isAir, yield = r.yield }
  if s.x1 < 0 then
    out.empty, out.size, out.offset = true, { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 }
    out.get = function() return nil end
    return out
  end
  out.size = { x = s.x1 - s.x0 + 1, y = s.y1 - s.y0 + 1, z = s.z1 - s.z0 + 1 }
  out.offset = { x = s.x0, y = s.y0, z = s.z0 }
  local get, ox, oy, oz = r.get, s.x0, s.y0, s.z0
  local w, h, d = out.size.x, out.size.y, out.size.z
  out.get = function(x, y, z)
    if x < 0 or y < 0 or z < 0 or x >= w or y >= h or z >= d then return nil end
    return get(x + ox, y + oy, z + oz)
  end
  return out
end

local function sortedList(map)
  local l = {}
  for k, v in pairs(map) do l[#l + 1] = { name = k, count = v } end
  table.sort(l, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
  end)
  return l
end

-- Counts blocks (air excluded) of the whole region, or of a trim() result (only its non-air cells exist either way).
function M.bill(r)
  local s = scan(r._src or r)
  local counts = s.counts
  local byName, states, total, types = {}, {}, 0, 0
  for i, e in ipairs(r.palette) do
    local n = counts[i]
    if n > 0 and not r.isAir(i) then
      byName[e.name] = (byName[e.name] or 0) + n
      total = total + n
      local k = stateKey(e.props)
      if k then
        states[e.name] = states[e.name] or {}
        states[e.name][k] = (states[e.name][k] or 0) + n
      end
    end
  end
  for _ in pairs(byName) do types = types + 1 end
  return { total = total, types = types, byName = byName, list = sortedList(byName), states = states }
end

local VANILLA
function M.check(r)
  VANILLA = VANILLA or require("mcblocks_1211")
  local s = scan(r._src or r)
  local renamed, unknown, modded = {}, {}, {}
  for i, e in ipairs(r.palette) do
    local n = s.counts[i]
    if n > 0 and not r.isAir(i) then
      local ns, id = e.name:match("^([^:]+):(.+)$")
      if ns ~= "minecraft" then
        modded[#modded + 1] = { name = e.name, count = n, note = "modded, not checked" }
      elseif M.RENAMES[e.name] then
        renamed[#renamed + 1] = { from = e.name, to = M.RENAMES[e.name], count = n, known = VANILLA[M.RENAMES[e.name]:sub(11)] == true }
      elseif not VANILLA[id] then
        unknown[#unknown + 1] = { name = e.name, count = n }
      end
    end
  end
  local function byName(a, b) return (a.name or a.from) < (b.name or b.from) end
  table.sort(renamed, byName); table.sort(unknown, byName); table.sort(modded, byName)
  return { renamed = renamed, unknown = unknown, modded = modded }
end

return M
