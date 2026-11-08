-- plan2: Weaver plan format v2 (`.plan2`): build one from a trimmed Litematica region, write it, read it back.
-- Pure Lua 5.2 (also CraftOS): no peripherals, no globals. Loaded with require("plan2"); needs plan2place and plan2order (the
-- placement planner, which writes the #M lines) and litematic for fromLitematic. Format: docs/systems/weaver.md s.3.
--
--   plan2.build(trimmed, {name=, author=, yield=f}) -> plan
--   plan2.fromLitematic(bytes, {name=, yield=f}) -> plan, report | nil, err
--       report = { renamed, unknown, modded (lit.check), note (several regions), bill (lit.bill of the file) }
--   plan2.text(plan) -> string          the .plan2 file
--   plan2.parse(text) -> plan | nil, err        plan.hashOK says if the body matches info.hash
--   plan2.save(path, plan) / plan2.load(path)   with the fs API
--
--   plan = { info = { name, author, size={x,y,z}, blocks, types, hash, bill={[name]=n}, items={[item]=n},
--                     palette={{name=,state=}...}, stats={F=,T=,U=,["2"]=}, ureasons={[why]=n}, ver=2 },
--            get(x,y,z) -> palette index | nil (0-based plan coordinates, y up),
--            marks = { [y] = { [z*size.x + x] = "FN" | "TE" | "2" | "U" } },    -- the #M lines (plan2place)
--            ulist = {{x,y,z,name,why}...} (only after build: why each U could not be done as asked) }
--   Placement lists per layer and rotation: plan2place.layer(plan, y, rot).

local M = {}

-- ---------------------------------------------------------------- tiny serializer (sorted keys: same text every time)
local function ser(v)
  local t = type(v)
  if t == "number" then
    if v % 1 == 0 then return string.format("%d", v) end
    return string.format("%.14g", v)
  elseif t == "string" then
    return (string.format("%q", v):gsub("\\\n", "\\n"))
  elseif t == "boolean" then
    return tostring(v)
  elseif t == "table" then
    local parts = {}
    if #v > 0 or next(v) == nil then
      for i = 1, #v do parts[i] = ser(v[i]) end
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      for _, k in ipairs(keys) do parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(v[k]) end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end
M.ser = ser

local function eval(s)
  local f, e
  if setfenv then
    f, e = loadstring("return " .. s)
    if f then setfenv(f, {}) end
  else
    f, e = load("return " .. s, "=info", "t", {})
  end
  if not f then return nil, e end
  local ok, v = pcall(f)
  if not ok then return nil, v end
  return v
end

-- 32-bit multiplicative hash (doubles stay exact: h < 2^32, times 33 < 2^38)
local function hash(s)
  local h = 5381
  for i = 1, #s, 100 do
    local bytes = { s:byte(i, math.min(i + 99, #s)) }
    for j = 1, #bytes do h = (h * 33 + bytes[j]) % 4294967296 end
  end
  return string.format("%08x", h)
end
M.hash = hash

-- ---------------------------------------------------------------- the plan object
local function new(info, grid, marks)
  local plan = { info = info, grid = grid, marks = marks or {} }
  local sx, sy, sz = info.size.x, info.size.y, info.size.z
  function plan.get(x, y, z)
    if x < 0 or z < 0 or x >= sx or z >= sz then return nil end
    local g = grid[y]
    return g and g[z * sx + x]
  end
  return plan
end
M.new = new

-- Properties the builder must reproduce, per kind of block. Everything else fixes itself (fence/wall connections,
-- stair shape, waterlogged, leaf distance, powered, open, chest type, door half ...).
local function keep(name, props)
  if not props then return nil end
  local id = name:match("^[^:]*:(.*)$") or name
  local s = {}
  if id:find("_stairs$") then s.facing, s.half = props.facing, props.half
  elseif id:find("_slab$") then s.type = props.type
  elseif id:find("_fence_gate$") or id:find("chest$") or id:find("wall_torch$") then s.facing = props.facing end
  if props.axis then s.axis = props.axis end
  if next(s) == nil then return nil end
  return s
end

-- What the Weaver has to carry for a block: wall torches are torches, a double slab is two slabs.
local function itemOf(name, state)
  local item = name:gsub("wall_torch$", "torch")
  return item, (state and state.type == "double") and 2 or 1
end

-- trimmed: lit.trim() result (or any {size, get, palette, isAir}). Needs plan2place for the #M marks.
function M.build(r, opts)
  opts = opts or {}
  local lit = require("litematic")
  local sx, sy, sz = r.size.x, r.size.y, r.size.z
  local palette, key2p, remap, grid = {}, {}, {}, {}
  local counts, blocks = {}, 0
  local n = 0
  for y = 0, sy - 1 do
    local g = {}
    grid[y] = g
    for z = 0, sz - 1 do
      for x = 0, sx - 1 do
        local i = r.get(x, y, z)
        if i and not r.isAir(i) then
          local p = remap[i]
          if not p then
            local e = r.palette[i]
            local name = lit.rename(e.name)
            local state = keep(name, e.props)
            local k = name .. "|" .. ser(state or {})
            p = key2p[k]
            if not p then
              p = #palette + 1
              palette[p] = { name = name, state = state }
              key2p[k] = p
              counts[p] = 0
            end
            remap[i] = p
          end
          g[z * sx + x] = p
          counts[p] = counts[p] + 1
          blocks = blocks + 1
        end
      end
      n = n + sx
      if n > 4000 then n = 0; if opts.yield then opts.yield() end end
    end
  end
  local bill, items, types = {}, {}, 0
  for p, e in ipairs(palette) do
    if bill[e.name] == nil then types = types + 1 end
    bill[e.name] = (bill[e.name] or 0) + counts[p]
    local item, per = itemOf(e.name, e.state)
    items[item] = (items[item] or 0) + counts[p] * per
  end
  local info = {
    ver = 2, name = opts.name or "build", author = opts.author, size = { x = sx, y = sy, z = sz },
    blocks = blocks, types = types, bill = bill, items = items, palette = palette,
    original = r.original, offset = r.offset,
  }
  local plan = new(info, grid)
  plan.yield = opts.yield
  require("plan2place").classify(plan)
  return plan
end

-- ---------------------------------------------------------------- writing
local function body(plan)
  local info = plan.info
  local sx, sy, sz = info.size.x, info.size.y, info.size.z
  local out = {}
  for y = 0, sy - 1 do
    out[#out + 1] = "#L " .. y
    local g = plan.grid[y]
    for z = 0, sz - 1 do
      local x0, x1
      for x = 0, sx - 1 do
        if g[z * sx + x] then x0 = x0 or x; x1 = x end
      end
      if x0 then
        local runs, cur, cnt = {}, nil, 0
        for x = x0, x1 do
          local p = g[z * sx + x] or "."
          if p == cur then cnt = cnt + 1 else
            if cur then runs[#runs + 1] = cnt .. ":" .. cur end
            cur, cnt = p, 1
          end
        end
        runs[#runs + 1] = cnt .. ":" .. cur
        out[#out + 1] = z .. "|" .. x0 .. "|" .. table.concat(runs, ",")
      end
    end
    local m = plan.marks[y]
    if m then
      local ks = {}
      for k in pairs(m) do ks[#ks + 1] = k end
      table.sort(ks)
      if #ks > 0 then
        out[#out + 1] = "#M " .. y
        for _, k in ipairs(ks) do out[#out + 1] = (k % sx) .. "," .. math.floor(k / sx) .. "," .. m[k] end
      end
    end
  end
  return table.concat(out, "\n")
end

local function bodyHash(b, palette) return hash(b .. "\n" .. ser(palette)) end

function M.text(plan)
  local b = body(plan)
  plan.info.hash = bodyHash(b, plan.info.palette)
  return "#plan2 " .. ser(plan.info) .. "\n" .. b .. "\n"
end

-- ---------------------------------------------------------------- reading
function M.parse(text)
  local head, rest = text:match("^#plan2 ([^\n]*)\n?(.*)$")
  if not head then return nil, "not a .plan2 file" end
  local info, err = eval(head)
  if type(info) ~= "table" or not info.size or not info.palette then return nil, "bad plan2 header: " .. tostring(err) end
  local sx = info.size.x
  local grid, marks = {}, {}
  for y = 0, info.size.y - 1 do grid[y] = {} end
  local cy, section
  local lines = rest:gsub("\n+$", "")
  for line in (lines .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    local tag, n = line:match("^#([LM]) (%d+)$")
    if tag then
      cy, section = tonumber(n), tag
      if cy >= info.size.y then return nil, "layer " .. cy .. " is outside the plan" end
      if tag == "M" then marks[cy] = marks[cy] or {} end
    elseif section == "L" and line ~= "" then
      local z, x0, runs = line:match("^(%d+)|(%d+)|(.+)$")
      if not z then return nil, "bad row in layer " .. tostring(cy) .. ": " .. line end
      z = tonumber(z)
      local x = tonumber(x0)
      local g = grid[cy]
      for cnt, p in runs:gmatch("(%d+):([%d%.]+)") do
        cnt = tonumber(cnt)
        if p ~= "." then
          p = tonumber(p)
          for i = 0, cnt - 1 do g[z * sx + x + i] = p end
        end
        x = x + cnt
      end
    elseif section == "M" and line ~= "" then
      local x, z, how = line:match("^(%d+),(%d+),(%w+)$")
      if not x then return nil, "bad mark in layer " .. tostring(cy) .. ": " .. line end
      marks[cy][tonumber(z) * sx + tonumber(x)] = how
    end
  end
  local plan = new(info, grid, marks)
  plan.hashOK = info.hash == bodyHash(rest:gsub("\n+$", ""), info.palette)
  return plan
end

function M.save(path, plan)
  local f = fs.open(path, "w")
  if not f then return false, "cannot write " .. path end
  f.write(M.text(plan))
  f.close()
  return true
end

function M.load(path)
  local f = fs.open(path, "r")
  if not f then return nil, "no such file: " .. path end
  local s = f.readAll()
  f.close()
  return M.parse(s)
end

-- bytes of a .litematic -> plan + what Tanis should hear about it
function M.fromLitematic(bytes, opts)
  opts = opts or {}
  local lit = require("litematic")
  local file, err = lit.read(bytes, { yield = opts.yield })
  if not file then return nil, err end
  local t = lit.trim(file)
  if t.empty then return nil, "the file has no blocks" end
  local chk = lit.check(file)
  local plan = M.build(t, { name = file.name or opts.name, author = file.author, yield = opts.yield })
  return plan, { renamed = chk.renamed, unknown = chk.unknown, modded = chk.modded, note = file.note, bill = lit.bill(t) }
end

return M
