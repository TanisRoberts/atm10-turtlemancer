-- server_layout.lua  --  the server room's layout, worked out from where the ME drives are (docs/design/server.md).
-- Pure: no peripherals, no screen. `build(drives, cfg)` takes AP's getDrives() list and returns the room:
--   { axis = "x"|"z", walls = { wall... }, racks = { rack... } (board order, R1..), outside = N,
--     drives, cells, used, total (bytes of the sized cells), noSize = { Infinity = n, ["MEGA Bulk"] = n, other = n },
--     tiers = { { prio, racks = {names}, sizes = {bytes...}, used, total, full }... } (highest priority first) }
--   wall = { n, bank, side ("West" "East" "North" "South"), reversed, racks = { rack... } }
--   rack = { name, wall, idx, grid = { [row 1..rows, top first] = { [col 1..cols] = drive } }, built, prio, mixed,
--            used, total, full, sizes = { bytes... } }
--   cell = a getDrives cell: maxBytes/usedBytes, or no maxBytes for an Infinity / Bulk cell (no size)
-- cfg: banks wallsPerBank racksPerWall rackCols rackRows, flip = { [wallNumber] = true }.
local L = {}

L.FULL = 0.9           -- over this a cell is "full"
L.FAR = 64             -- a drive further than this from the middle of the room is "outside the room"

local SIDES = { x = { "West", "East" }, z = { "North", "South" } }

-- the fill of a cell as 0..1, or nil when the bridge gives it no size
function L.fill(c)
  if not c.maxBytes or c.maxBytes <= 0 then return nil end
  return math.min(1, (c.usedBytes or 0) / c.maxBytes)
end

-- "Infinity", "MEGA Bulk" or "other" for a cell with no size
function L.noSizeKind(c)
  local n = ((c.item and c.item.name) or ""):lower()
  if n:find("infinity", 1, true) then return "Infinity" end
  if n:find("bulk", 1, true) then return "MEGA Bulk" end
  return "other"
end

local function groupBy(list, key)
  local groups, order = {}, {}
  for _, d in ipairs(list) do
    local k = d.position[key]
    if not groups[k] then groups[k] = { key = k, drives = {} }; order[#order + 1] = groups[k] end
    local g = groups[k]
    g.drives[#g.drives + 1] = d
  end
  return order
end

local function isDrive(d)
  return type(d) == "table" and type(d.position) == "table" and d.position.x and d.position.z
     and (d.type == nil or tostring(d.type):find("drive", 1, true) ~= nil)
end

function L.build(drives, cfg)
  local banks, wpb, rpw = cfg.banks or 2, cfg.wallsPerBank or 2, cfg.racksPerWall or 3
  local rcols, rrows = cfg.rackCols or 2, cfg.rackRows or 5
  local maxWalls = banks * wpb
  local list = {}
  for _, d in ipairs(drives or {}) do if isDrive(d) then list[#list + 1] = d end end

  -- an odd drive far from the rest (more than FAR blocks from the middle of the room) is outside, not a wall
  local far, farList = 0, {}
  if #list > 2 then
    local function median(key)
      local v = {}
      for i, d in ipairs(list) do v[i] = d.position[key] end
      table.sort(v)
      return v[math.ceil(#v / 2)]
    end
    local mx, my, mz = median("x"), median("y"), median("z")
    local near = {}
    for _, d in ipairs(list) do
      local p = d.position
      if math.abs(p.x - mx) > L.FAR or math.abs(p.y - my) > L.FAR or math.abs(p.z - mz) > L.FAR then far = far + 1; farList[#farList + 1] = d
      else near[#near + 1] = d end
    end
    list = near
  end

  -- 1. walls: drives sharing a plane; the axis that leaves the fewest groups
  local gx, gz = groupBy(list, "x"), groupBy(list, "z")
  local axis, groups = "x", gx
  if #gz < #gx then axis, groups = "z", gz end
  local colKey = axis == "x" and "z" or "x"
  table.sort(groups, function(a, b) if #a.drives ~= #b.drives then return #a.drives > #b.drives end return a.key < b.key end)
  local kept, outside = {}, 0
  for i, g in ipairs(groups) do
    if i <= maxWalls then kept[#kept + 1] = g else outside = outside + #g.drives end
  end
  table.sort(kept, function(a, b) return a.key < b.key end)

  -- 2/3/5. banks, sides, empty walls and racks
  local room = { axis = axis, walls = {}, racks = {}, outside = 0, farDrives = far, drives = #list + far, cells = 0, used = 0, total = 0,
                 noSize = {}, banks = banks, wallsPerBank = wpb, racksPerWall = rpw, rackCols = rcols, rackRows = rrows }
  for n = 1, maxWalls do
    local side = (n - 1) % wpb + 1
    local reversed = (axis == "x" and side == 1) or (axis == "z" and side == 2)
    if cfg.flip and cfg.flip[n] then reversed = not reversed end
    local wall = { n = n, bank = math.ceil(n / wpb), side = SIDES[axis][side] or ("Wall " .. side), reversed = reversed, racks = {} }
    for ri = 1, rpw do
      local grid = {}
      for r = 1, rrows do grid[r] = {} end
      local rack = { name = "R" .. ((n - 1) * rpw + ri), wall = n, idx = ri, grid = grid, built = 0,
                     used = 0, total = 0, full = 0, sizes = {}, cells = 0 }
      wall.racks[ri] = rack
      room.racks[#room.racks + 1] = rack
    end
    room.walls[n] = wall
  end

  -- 4. columns and rows inside each built wall
  for n, g in ipairs(kept) do
    local wall = room.walls[n]
    local cmin, cmax, ymin = math.huge, -math.huge, math.huge
    for _, d in ipairs(g.drives) do
      local c = d.position[colKey]
      if c < cmin then cmin = c end
      if c > cmax then cmax = c end
      if d.position.y < ymin then ymin = d.position.y end
    end
    for _, d in ipairs(g.drives) do
      local c = d.position[colKey]
      local col = wall.reversed and (cmax - c) or (c - cmin)
      local row = d.position.y - ymin                    -- 0 = bottom
      local ri = math.floor(col / rcols) + 1
      if col < 0 or row < 0 or row >= rrows or ri > rpw or math.floor(col) ~= col or math.floor(row) ~= row then
        outside = outside + 1
      else
        local rack = wall.racks[ri]
        local rr, rc = rrows - row, col % rcols + 1
        if rack.grid[rr][rc] then outside = outside + 1 else
          rack.grid[rr][rc] = d
          rack.built = rack.built + 1
          if rack.prio == nil then rack.prio = d.priority or 0
          elseif rack.prio ~= (d.priority or 0) then rack.mixed = true end
        end
      end
    end
  end
  room.outside = outside + far

  -- cell totals (a drive's own usedBytes/totalBytes are 0 in AP: sum the cells)
  local everything = {}
  for _, d in ipairs(list) do everything[#everything + 1] = d end
  for _, d in ipairs(farList) do everything[#everything + 1] = d end
  for _, d in ipairs(everything) do
    for _, c in pairs(d.cells or {}) do
      room.cells = room.cells + 1
      if c.maxBytes and c.maxBytes > 0 then
        room.used = room.used + (c.usedBytes or 0); room.total = room.total + c.maxBytes
      else
        local k = L.noSizeKind(c)
        room.noSize[k] = (room.noSize[k] or 0) + 1
      end
    end
  end
  for _, rack in ipairs(room.racks) do
    local seen = {}
    for r = 1, rrows do
      for col = 1, rcols do
        local d = rack.grid[r][col]
        if d then
          for _, c in pairs(d.cells or {}) do
            rack.cells = rack.cells + 1
            if c.maxBytes and c.maxBytes > 0 then
              rack.used = rack.used + (c.usedBytes or 0); rack.total = rack.total + c.maxBytes
              if L.fill(c) > L.FULL then rack.full = rack.full + 1 end
              seen[c.maxBytes] = true
            end
          end
        end
      end
    end
    for b in pairs(seen) do rack.sizes[#rack.sizes + 1] = b end
    table.sort(rack.sizes)
  end

  -- tiers: one per priority, highest first
  local byPrio, tiers = {}, {}
  for _, rack in ipairs(room.racks) do
    if rack.built > 0 then
      local t = byPrio[rack.prio]
      if not t then t = { prio = rack.prio, racks = {}, sizes = {}, used = 0, total = 0, full = 0, seen = {} }; byPrio[rack.prio] = t; tiers[#tiers + 1] = t end
      t.racks[#t.racks + 1] = rack.name
      t.used, t.total, t.full = t.used + rack.used, t.total + rack.total, t.full + rack.full
      for _, b in ipairs(rack.sizes) do
        if not t.seen[b] then t.seen[b] = true; t.sizes[#t.sizes + 1] = b end
      end
    end
  end
  for _, t in ipairs(tiers) do table.sort(t.sizes); t.seen = nil end
  table.sort(tiers, function(a, b) return a.prio > b.prio end)
  room.tiers = tiers
  return room
end

return L
