-- sim/me.lua  --  an Advanced Peripherals 0.8.1a ME Bridge (`me_bridge`) on a simulated AE2 grid.
--
-- Modelled on AP `release/0.8-1.21.1` (MEBridgePeripheral, AbstractStorageSystemPeripheral, AEApi) and
-- AE2 (BasicCellInventory, NetworkStorage). Make one with `w:meBridge{}` and put it on a cable:
--
--   local me = w:meBridge{}
--   net:add("me_bridge_0", me)
--   local racks = me:addRack{ priority = 10, cell = "256M" }       -- 8 drives x 10 cells
--   me:addRack{ priority = 0, cell = "1k" }
--   me:addBus{ priority = 9999, capacity = 256000, void = true }    -- a drawer with a void upgrade
--   me:fill(cell, "minecraft:cobblestone", 500)                     -- set up fragmentation directly
--   me:where("minecraft:cobblestone")                               -- { {drive=, slot=, count=}, ... }
--
-- AE2 facts it follows (checked against the source):
--   * A cell's usedBytes = types * bytesPerType + ceil(totalItems / 8). It is the WHOLE cell's item total
--     that is rounded up, not each type (BasicCellInventory.getUsedBytes / getUnusedItemCount).
--   * bytesPerType = maxBytes / 128 (1k: 8, 4k: 32, 16k: 128, 64k: 512, 256k: 2048); maxTypes = 63.
--     A new type is refused when freeBytes <= bytesPerType (unless the last byte still has spare slots),
--     or 63 types are held; and it must leave room for at least one item after the bytesPerType.
--   * Insert: highest priority first. Inside one priority, cells that already hold the item first, then the
--     rest (in the order they were built). Extract: lowest priority first.
--   * A storage bus (e.g. on a drawer) has its own priority. With `void = true` it takes everything offered and
--     destroys what doesn't fit.
-- AP quirks it keeps: getDrives() reports a drive's own usedBytes/totalBytes as 0 and leaves out empty slots
-- (`cells` is keyed by 1-based slot); getCells()/getDrives() don't list storage buses, but getItems() counts them;
-- exportItem/importItem move up to `count` (default: everything that fits) in ONE call over many stacks
-- and return the moved count, or nil,"INVENTORY_NOT_FOUND" / nil,"NOT_CONNECTED".
--
-- Not verified against the MEGA Cells source: the MEGA item names (`megacells:item_cell_1m` ...) and
-- bytesPerType (assumed maxBytes/128 like AE2's own cells; only totals and ordering matter to the programs).
-- Items are keyed by name alone (nbtHash / components are accepted and ignored).
local Inv = require("sim.inv")

local ME = {}
ME.__index = ME
ME.mainThread = true      -- every call costs a game tick (when world.ticks is on), like other inventory calls
ME.peripheralMethods = {
  "isConnected", "isOnline", "getItems", "getItem", "getFluids", "exportItem", "importItem",
  "getCells", "getDrives", "getUsedItemStorage", "getAvailableItemStorage", "getMaxItemStorage",
  "getStoredEnergy", "getEnergyCapacity", "getEnergyUsage",
}

-- name -> maxBytes. AE2 cells, then MEGA Cells.
ME.sizes = {
  ["1k"] = 1024, ["4k"] = 4096, ["16k"] = 16384, ["64k"] = 65536, ["256k"] = 262144,
  ["1M"] = 1048576, ["4M"] = 4194304, ["16M"] = 16777216, ["64M"] = 67108864, ["256M"] = 268435456,
}
ME.cellItems = {
  ["1k"] = "ae2:item_storage_cell_1k", ["4k"] = "ae2:item_storage_cell_4k", ["16k"] = "ae2:item_storage_cell_16k",
  ["64k"] = "ae2:item_storage_cell_64k", ["256k"] = "ae2:item_storage_cell_256k",
  ["1M"] = "megacells:item_cell_1m", ["4M"] = "megacells:item_cell_4m", ["16M"] = "megacells:item_cell_16m",
  ["64M"] = "megacells:item_cell_64m", ["256M"] = "megacells:item_cell_256m",
}
local PER_BYTE, MAX_TYPES = 8, 63

local function pretty(name)
  local s = name:gsub("^[^:]*:", ""):gsub("_", " ")
  return (s:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

---------------------------------------------------------------------------
-- Storage handlers: cells and storage buses share holds / room / add / take / count
---------------------------------------------------------------------------
local Cell = {}
Cell.__index = Cell

local function newCell(size)
  local maxBytes = ME.sizes[size]
  if not maxBytes then error("unknown cell size " .. tostring(size), 3) end
  return setmetatable({ kind = "cell", size = size, maxBytes = maxBytes, bytesPerType = math.floor(maxBytes / 128),
                        maxTypes = MAX_TYPES, piles = {} }, Cell)
end

function Cell:total() local t = 0; for _, n in pairs(self.piles) do t = t + n end; return t end
function Cell:types() local t = 0; for _ in pairs(self.piles) do t = t + 1 end; return t end
function Cell:unused() local r = self:total() % PER_BYTE; return r == 0 and 0 or PER_BYTE - r end
function Cell:usedBytes() return self:types() * self.bytesPerType + math.floor((self:total() + self:unused()) / PER_BYTE) end
function Cell:freeBytes() return self.maxBytes - self:usedBytes() end
function Cell:count(name) return self.piles[name] or 0 end
function Cell:holds(name) return (self.piles[name] or 0) > 0 end
function Cell:canHoldNewItem()
  local free = self:freeBytes()
  return (free > self.bytesPerType or (free == self.bytesPerType and self:unused() > 0))
     and math.min(math.floor(free / self.bytesPerType), self.maxTypes - self:types()) > 0
end
-- how many more of `name` this cell would accept (BasicCellInventory.innerInsert)
function Cell:room(name)
  local remaining = math.max(0, self:freeBytes() * PER_BYTE + self:unused())
  if not self:holds(name) then
    if not self:canHoldNewItem() then return 0 end
    remaining = remaining - self.bytesPerType * PER_BYTE
    if remaining <= 0 then return 0 end
  end
  return remaining
end
function Cell:add(name, n) self.piles[name] = (self.piles[name] or 0) + n; return n end
function Cell:take(name, n)
  local have = self.piles[name] or 0
  n = math.min(n, have)
  if n >= have then self.piles[name] = nil else self.piles[name] = have - n end
  return n
end
function Cell:priority() return self.drive and self.drive.priority or 0 end

local Bus = {}
Bus.__index = Bus
function Bus:count(name) return self.piles[name] or 0 end
function Bus:holds(name) return (self.piles[name] or 0) > 0 end
function Bus:room(name)
  if self.void then return math.huge end
  if not self.capacity then return math.huge end
  return math.max(0, self.capacity - (self.piles[name] or 0))
end
function Bus:add(name, n)       -- returns how many were accepted (a void bus accepts all, keeps what fits)
  local keep = math.min(n, self.capacity and math.max(0, self.capacity - (self.piles[name] or 0)) or n)
  if keep > 0 then self.piles[name] = (self.piles[name] or 0) + keep end
  return self.void and n or keep
end
Bus.take = Cell.take
function Bus:priority() return self.prio end

---------------------------------------------------------------------------
-- The bridge
---------------------------------------------------------------------------
function ME.new(opts)
  opts = opts or {}
  return setmetatable({
    types = opts.types or { "me_bridge", "multi_drive" },
    drives = {}, buses = {}, nextSeq = 0,
    connected = true, online = true,
    energy = { stored = opts.stored or 100000, capacity = opts.capacity or 200000, usage = opts.usage or 20 },
  }, ME)
end

function ME:_seq() self.nextSeq = self.nextSeq + 1; return self.nextSeq end

-- ---- scenario helpers (not peripheral methods)
function ME:setConnected(b) self.connected = b and true or false end
function ME:setOnline(b) self.online = b and true or false end

-- opts: name, x, y, z, priority, slots (10)
function ME:addDrive(opts)
  opts = opts or {}
  local n = #self.drives + 1
  local d = { type = "ae2:drive", name = opts.name or ("ME Drive " .. n), priority = opts.priority or 0,
              position = { x = opts.x or n, y = opts.y or 64, z = opts.z or 0 }, slots = opts.slots or 10,
              cells = {}, seq = self:_seq() }
  self.drives[#self.drives + 1] = d
  return d
end
-- put a new cell of `size` ("1k".."256M") in `slot` (or the first empty slot) of `drive`
function ME:addCell(drive, size, slot)
  if not slot then
    for i = 1, drive.slots do if not drive.cells[i] then slot = i; break end end
    if not slot then error("drive " .. drive.name .. " is full", 2) end
  end
  if drive.cells[slot] then error("slot " .. slot .. " of " .. drive.name .. " is taken", 2) end
  local c = newCell(size)
  c.drive, c.slot, c.seq = drive, slot, self:_seq()
  drive.cells[slot] = c
  return c
end
-- a rack: `n` drives (8) sharing one priority, each filled with cells of `cell` (nil = empty drives)
function ME:addRack(opts)
  opts = opts or {}
  local out = {}
  for i = 1, opts.n or 8 do
    local d = self:addDrive{ name = opts.name and (opts.name .. " " .. i) or nil, priority = opts.priority,
                             x = (opts.x or 0) + i - 1, y = opts.y, z = opts.z, slots = opts.slots }
    if opts.cell then for _ = 1, d.slots do self:addCell(d, opts.cell) end end
    out[i] = d
  end
  return out
end
-- a storage bus on an external inventory: priority, capacity (per item, nil = unlimited), void
function ME:addBus(opts)
  opts = opts or {}
  local b = setmetatable({ kind = "bus", prio = opts.priority or 0, capacity = opts.capacity, void = opts.void,
                           piles = {}, seq = self:_seq() }, Bus)
  self.buses[#self.buses + 1] = b
  return b
end
-- put items straight into a cell or bus, ignoring priority (sets up fragmentation). Returns what was stored.
function ME:fill(target, name, count)
  if target.kind == "cell" then
    local n = math.min(count, target:room(name))
    if n > 0 then target:add(name, n) end
    return n
  end
  return target:add(name, count)
end
-- where an item sits: list of { kind, drive, slot, cell, count } for cells, { kind = "bus", bus, count } for buses
function ME:where(name)
  local out = {}
  for _, h in ipairs(self:_handlers()) do
    local n = h:count(name)
    if n > 0 then
      out[#out + 1] = h.kind == "cell" and { kind = "cell", drive = h.drive, slot = h.slot, cell = h, count = n }
                                         or { kind = "bus", bus = h, count = n }
    end
  end
  return out
end
function ME:total(name)
  local t = 0
  for _, h in ipairs(self:_handlers()) do t = t + h:count(name) end
  return t
end
function ME:cells()
  local out = {}
  for _, d in ipairs(self.drives) do
    for i = 1, d.slots do if d.cells[i] then out[#out + 1] = d.cells[i] end end
  end
  return out
end

-- ---- grid internals
function ME:_handlers()           -- every cell and bus, in the order they were built
  local out = {}
  for _, c in ipairs(self:cells()) do out[#out + 1] = c end
  for _, b in ipairs(self.buses) do out[#out + 1] = b end
  table.sort(out, function(a, b) return a.seq < b.seq end)
  return out
end
function ME:_insert(name, n)      -- AE2 order: priority high -> low; inside one priority, holders first
  local hs, left = self:_handlers(), n
  local prios, seen = {}, {}
  for _, h in ipairs(hs) do local p = h:priority(); if not seen[p] then seen[p] = true; prios[#prios + 1] = p end end
  table.sort(prios, function(a, b) return a > b end)
  for _, p in ipairs(prios) do
    for pass = 1, 2 do
      for _, h in ipairs(hs) do
        if left <= 0 then break end
        if h:priority() == p and h:holds(name) == (pass == 1) then
          local put = math.min(left, h:room(name))
          if put > 0 then left = left - h:add(name, put) end
        end
      end
    end
  end
  return n - left
end
function ME:_extractFrom(name, want)   -- AE2 order: priority low -> high, then build order
  local hs = {}
  for _, h in ipairs(self:_handlers()) do if h:holds(name) then hs[#hs + 1] = h end end
  table.sort(hs, function(a, b)
    local pa, pb = a:priority(), b:priority()
    if pa ~= pb then return pa < pb end
    return a.seq < b.seq
  end)
  return hs
end
function ME:_names()
  local set, out = {}, {}
  for _, h in ipairs(self:_handlers()) do
    for name in pairs(h.piles) do if not set[name] then set[name] = true; out[#out + 1] = name end end
  end
  table.sort(out)
  return out
end
function ME:_off()
  if not self.connected or not self.online then return "NOT_CONNECTED" end
end

local function cellInfo(c)
  local item = ME.cellItems[c.size]
  return { item = { name = item, displayName = pretty(item), count = 1 }, type = "ae2:i",
           bytesPerType = c.bytesPerType, maxBytes = c.maxBytes, maxTypes = c.maxTypes, usedBytes = c:usedBytes() }
end

-- ---- peripheral methods
function ME:isConnected() return self.connected end
function ME:isOnline() return self.online end

local function stackOf(self, name)
  return { name = name, count = self:total(name), displayName = pretty(name), tags = {}, nbt = nil,
           components = {}, isCraftable = false }
end
function ME:getItems(filter)
  local off = self:_off(); if off then return nil, off end
  local out = {}
  for _, name in ipairs(self:_names()) do
    if not (filter and filter.name and filter.name ~= name) then out[#out + 1] = stackOf(self, name) end
  end
  return out
end
function ME:getItem(filter)
  local off = self:_off(); if off then return nil, off end
  if type(filter) ~= "table" or not filter.name then return nil, "FILTER_ERROR" end
  return stackOf(self, filter.name)
end
function ME:getFluids() local off = self:_off(); if off then return nil, off end; return {} end

function ME:exportItem(toName, filter)
  local off = self:_off(); if off then return nil, off end
  local to = self.net and self.net:get(toName)
  if not to or not to.insert then return nil, "INVENTORY_NOT_FOUND" end
  filter = filter or {}
  local want, moved = filter.count or math.huge, 0
  local names = filter.name and { filter.name } or self:_names()
  for _, name in ipairs(names) do
    for _, h in ipairs(self:_extractFrom(name)) do
      local ask = math.min(h:count(name), want - moved)
      if ask <= 0 then break end
      local put = to:insert(name, ask, filter.toSlot)
      if put > 0 then h:take(name, put); moved = moved + put end
      if put < ask then break end              -- target full for this item
    end
    if moved >= want then break end
  end
  return moved
end

function ME:importItem(fromName, filter)
  local off = self:_off(); if off then return nil, off end
  local from = self.net and self.net:get(fromName)
  if not from or not from.insert then return nil, "INVENTORY_NOT_FOUND" end
  filter = filter or {}
  local want, moved = filter.count or math.huge, 0
  local first, last = 1, from.nslots
  if filter.fromSlot then first, last = filter.fromSlot, filter.fromSlot end
  for slot = first, last do
    local s = from.slots[slot]
    if s and not (filter.name and filter.name ~= s.name) then
      local ask = math.min(s.count, want - moved)
      if ask > 0 then
        local put = self:_insert(s.name, ask)
        if put > 0 then from:extract(slot, put); moved = moved + put end
      end
      if moved >= want then break end
    end
  end
  return moved
end

function ME:getCells()
  local off = self:_off(); if off then return nil, off end
  local out = {}
  for _, c in ipairs(self:cells()) do out[#out + 1] = cellInfo(c) end
  return out
end
function ME:getDrives()
  local off = self:_off(); if off then return nil, off end
  local out = {}
  for _, d in ipairs(self.drives) do
    local cells = {}
    for i = 1, d.slots do if d.cells[i] then cells[i] = cellInfo(d.cells[i]) end end
    out[#out + 1] = { type = d.type, name = d.name, position = { x = d.position.x, y = d.position.y, z = d.position.z },
                      priority = d.priority, usedBytes = 0, totalBytes = 0, cells = cells,   -- AP's bug: both 0
                      menuIcon = { name = "ae2:drive", count = 1 } }
  end
  return out
end

local function sumCells(self, f)
  local t = 0
  for _, c in ipairs(self:cells()) do t = t + f(c) end
  return t
end
function ME:getUsedItemStorage() local off = self:_off(); if off then return nil, off end; return sumCells(self, Cell.usedBytes) end
function ME:getAvailableItemStorage() local off = self:_off(); if off then return nil, off end; return sumCells(self, Cell.freeBytes) end
function ME:getMaxItemStorage() local off = self:_off(); if off then return nil, off end; return sumCells(self, function(c) return c.maxBytes end) end
function ME:getStoredEnergy() local off = self:_off(); if off then return nil, off end; return self.energy.stored end
function ME:getEnergyCapacity() local off = self:_off(); if off then return nil, off end; return self.energy.capacity end
function ME:getEnergyUsage() local off = self:_off(); if off then return nil, off end; return self.energy.usage end

return ME
