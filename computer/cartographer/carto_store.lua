-- carto_store.lua  --  the Cartographer's map: every chunk in memory, saved one file per region.
--
--   regions/<rx>_<rz>.map   shared/mapchunk.lua format (run-length coded), one file per region of 16 x 16 chunks
--
-- A region goes to the computer's own disk first. When that is nearly full (or a region does not fit), it spills
-- over to disk drives: each floppy mounts as /disk, /disk2, ... (125 KB). Every mount is read as one map, so a floppy
-- can come and go: its regions stay in memory and are written somewhere else on the next save.
local mc = require("mapchunk")

local S = {}
S.REGION = 16            -- chunks per region side
S.DIR = "regions"
S.RESERVE = 60000        -- bytes kept free on the computer's disk (the OS, settings, a copy while a file is rewritten)

local Store = {}
Store.__index = Store

function S.regionOf(cx, cz) return math.floor(cx / S.REGION), math.floor(cz / S.REGION) end
function S.rkey(rx, rz) return rx .. "," .. rz end
function S.rpath(mount, rx, rz) return (mount == "" and "" or (mount .. "/")) .. S.DIR .. "/" .. rx .. "_" .. rz .. ".map" end

function S.new(o)
  o = o or {}
  return setmetatable({
    chunks = {},         -- [key "cx,cz"] = { rev, data }
    revs = {},           -- [key] = rev (what `have` sends)
    regions = {},        -- [rkey] = { rx, rz, n = chunks held }
    home = {},           -- [rkey] = the mount its file lives on ("" = the computer)
    size = {},           -- [rkey] = bytes of its file
    dirty = {},          -- [rkey] = true
    reserve = o.reserve or S.RESERVE,
    x0 = nil,            -- chunk bounds of everything held
  }, Store)
end

-- The places a map can live: the computer's disk, then every floppy. { mount, path, free, capacity, used }
function Store:mounts()
  local out = {}
  local function add(mount)
    local p = mount == "" and "" or ("/" .. mount)
    local ok, free = pcall(fs.getFreeSpace, p == "" and "/" or p)
    local ok2, cap = pcall(fs.getCapacity, p == "" and "/" or p)
    free, cap = ok and free or 0, ok2 and cap or 0
    out[#out + 1] = { mount = mount, free = free, capacity = cap, used = math.max(0, cap - free),
                      name = mount == "" and "Computer" or mount }
  end
  add("")
  local names = {}
  for _, n in ipairs(fs.list("/")) do
    if n:match("^disk%d*$") and fs.isDir(n) then names[#names + 1] = n end
  end
  table.sort(names, function(a, b) return (tonumber(a:match("%d+")) or 1) < (tonumber(b:match("%d+")) or 1) end)
  for _, n in ipairs(names) do add(n) end
  return out
end

local function bump(self, cx, cz)
  self.x0 = math.min(self.x0 or cx, cx); self.x1 = math.max(self.x1 or cx, cx)
  self.z0 = math.min(self.z0 or cz, cz); self.z1 = math.max(self.z1 or cz, cz)
end

-- Take a chunk if it is newer than ours (a column the new copy has never seen keeps our old value).
-- Returns true when the chunk changed.
function Store:put(key, rev, data)
  local cx, cz = mc.parseKey(key)
  if not cx or not mc.valid(data) then return false end
  rev = tonumber(rev) or 0
  local old = self.chunks[key]
  if old and rev <= (old.rev or 0) then return false end
  local merged = old and mc.merge(old.data, data) or data
  self.chunks[key] = { rev = rev, data = merged }
  self.revs[key] = rev
  bump(self, cx, cz)
  local rx, rz = S.regionOf(cx, cz)
  local rk = S.rkey(rx, rz)
  local r = self.regions[rk]
  if not r then r = { rx = rx, rz = rz, n = 0, keys = {} }; self.regions[rk] = r end
  if not old then r.n = r.n + 1; r.keys[key] = true end
  self.dirty[rk] = true
  return true
end

function Store:get(cx, cz) return self.chunks[cx .. "," .. cz] end
function Store:count() local n = 0 for _ in pairs(self.chunks) do n = n + 1 end return n end
function Store:regionCount() local n = 0 for _ in pairs(self.regions) do n = n + 1 end return n end
function Store:complete(rx, rz)
  local r = self.regions[S.rkey(rx, rz)]
  return r ~= nil and r.n >= S.REGION * S.REGION
end
function Store:has(rx, rz) return self.regions[S.rkey(rx, rz)] ~= nil end

-- Everything held, as block bounds: x0, z0, x1, z1 (nil when empty)
function Store:bounds()
  if not self.x0 then return nil end
  return self.x0 * 16, self.z0 * 16, self.x1 * 16 + 15, self.z1 * 16 + 15
end

-- Read every region file on every mount (again = a floppy came or went: keep what still needs saving).
-- `step` is called now and then so a big map never hogs the computer.
function Store:load(step, again)
  local keep = again and self.dirty or {}
  for _, m in ipairs(self:mounts()) do
    local dir = (m.mount == "" and "" or (m.mount .. "/")) .. S.DIR
    if fs.isDir(dir) then
      for _, f in ipairs(fs.list(dir)) do
        local rx, rz = f:match("^(%-?%d+)_(%-?%d+)%.map$")
        if rx then
          local rk = S.rkey(tonumber(rx), tonumber(rz))
          local path = dir .. "/" .. f
          for key, c in pairs(mc.load(path)) do self:put(key, c.rev, c.data) end
          if not self.home[rk] then self.home[rk] = m.mount end
          self.size[rk] = fs.getSize(path)
          if step then step() end
        end
      end
    end
  end
  self.dirty = keep
end

-- Try to write one region's file on a mount. Returns true when it is safely there.
local function writeRegion(self, rk, mount)
  local r = self.regions[rk]
  local sub = {}
  for key in pairs(r.keys) do sub[key] = self.chunks[key] end
  local path = S.rpath(mount, r.rx, r.rz)
  fs.makeDir((mount == "" and "" or ("/" .. mount)) .. "/" .. S.DIR)
  local ok, res = pcall(mc.save, path, sub)
  if not ok or not res then
    pcall(fs.delete, path .. ".new")
    return false
  end
  self.size[rk] = fs.getSize(path)
  return true
end

-- How many bytes a region's file takes (the same lines mapchunk.save writes)
function Store:estimate(rk)
  local r = self.regions[rk]
  local n = 0
  for key in pairs(r.keys) do n = n + #key + 16 + #mc.encode(self.chunks[key].data) end
  return n
end

-- Save the regions that changed. Returns the number saved. Each goes where it already lives if that still works,
-- else the computer's disk (while it has room), else the floppy with the most room.
function Store:save()
  local n = 0
  local mounts = self:mounts()
  local byName = {}
  for _, m in ipairs(mounts) do byName[m.mount] = m end
  for rk in pairs(self.dirty) do
    local r = self.regions[rk]
    if r then
      local need = self:estimate(rk) + 1000
      local order, seen = {}, {}
      local function try(m) if m and not seen[m.mount] then seen[m.mount] = true; order[#order + 1] = m end end
      local home = byName[self.home[rk]]
      if home and (home.free >= need) then try(home) end
      local comp = byName[""]
      if comp.free - self.reserve >= need then try(comp) end
      local floppies = {}
      for _, m in ipairs(mounts) do if m.mount ~= "" and m.free >= need then floppies[#floppies + 1] = m end end
      table.sort(floppies, function(a, b) return a.free > b.free end)
      for _, m in ipairs(floppies) do try(m) end
      try(home); try(comp)
      for _, m in ipairs(order) do
        if writeRegion(self, rk, m.mount) then
          local old = self.home[rk]
          if old and old ~= m.mount and byName[old] then pcall(fs.delete, S.rpath(old, r.rx, r.rz)) end
          self.home[rk] = m.mount
          self.dirty[rk] = nil
          n = n + 1
          m.free = math.max(0, m.free - (self.size[rk] or 0))
          break
        end
      end
    else
      self.dirty[rk] = nil
    end
  end
  return n
end

-- What is left: per mount used/capacity, and roughly how many more regions fit.
function Store:gauge()
  local mounts = self:mounts()
  local total, n = 0, 0
  for _, s in pairs(self.size) do total = total + s; n = n + 1 end
  local avg = n > 0 and math.max(4000, total / n) or 20000
  local free = 0
  for i, m in ipairs(mounts) do
    free = free + math.max(0, m.free - (i == 1 and self.reserve or 0))
  end
  return mounts, math.floor(free / avg)
end

return S
