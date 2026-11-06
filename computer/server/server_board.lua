-- server_board.lua  --  draws the server room board (docs/design/server.md) on a UI-kit view.
-- Pure drawing: `board.draw(v, M, o)` reads a model and writes into the view's buffer; it never calls a peripheral.
--   M = { room (server_layout.build), online (bool), seen (any data yet), energy = { stored, cap, usage } or nil,
--         kinds, items (counts from getItems), piles = { { name, count } } (biggest first),
--         defrag = { msg = {type="defrag",...}, at = os.clock() } or nil, now = os.clock() }
--   o.reserve = rows left free at the bottom (the computer's own screen keeps its input row there)
local layout = require("server_layout")
local ui = require("ui")
local fit = ui.text.fit

local B = {}
local DOT = "\183"
local STALE_S = 30           -- no defrag news for this long: "storage not heard"

---------------------------------------------------------------------------
-- Formats
---------------------------------------------------------------------------
local function trim(n) local s = ("%.1f"):format(n); return (s:gsub("%.0$", "")) end
function B.bytes(n)                      -- 1024-based, like the cell names (1k, 4k, 256M)
  if n >= 2 ^ 30 then return trim(n / 2 ^ 30) .. "G" end
  if n >= 2 ^ 20 then return trim(n / 2 ^ 20) .. "M" end
  if n >= 2 ^ 10 then return trim(n / 2 ^ 10) .. "k" end
  return tostring(math.floor(n))
end
function B.count(n)                      -- 1000-based, for item counts
  if n >= 1e9 then return trim(n / 1e9) .. "G" end
  if n >= 1e6 then return trim(n / 1e6) .. "M" end
  if n >= 1e3 then return trim(n / 1e3) .. "k" end
  return tostring(math.floor(n))
end
local function commas(n) return (tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
local function pct(a, b) if not b or b <= 0 then return 0 end return math.floor(a / b * 100 + 0.5) end
local function sizes(list)
  local out = {}
  for _, b in ipairs(list) do out[#out + 1] = B.bytes(b) end
  return table.concat(out, "/")
end
-- lime under 70%, orange 70-90%, red over 90%
local function fillRole(f) if f > layout.FULL then return "bad" elseif f >= 0.7 then return "warn" end return "good" end

-- a section rule: dim caps title, a lower-case hint, then the rule
local function section(v, y, title, hint)
  local x = v:put(1, y, title, "dim", "bg")
  if hint then x = v:put(x + 2, y, hint, "dim", "bg") end
  if x + 1 <= v.W then v:put(x + 1, y, ("\140"):rep(v.W - x), "bar", "bg") end
  return y + 1
end

local function bar(v, x, y, w, frac, role)
  if w < 1 then return end
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  if frac > 0 and n < 1 then n = 1 end
  v:fill(x, y, n, role)
  v:fill(x + n, y, w - n, "bar")
end

---------------------------------------------------------------------------
-- The room
---------------------------------------------------------------------------
local function cellRole(c, stale)
  if stale then return "dim" end
  local f = layout.fill(c)
  if not f then return "idle" end
  return fillRole(f)
end

-- one rack at x0,y0 (5 cell rows per drive row, a blank row between)
local function drawRack(v, rack, x0, y0, room, stale)
  local rcols, rrows = room.rackCols, room.rackRows
  v:put(x0, y0 - 1, fit(rack.built > 0 and (rack.name .. " " .. tostring(rack.prio)) or rack.name, rcols * 3 - 1),
        rack.built > 0 and "fg" or "dim", "bg")
  for r = 1, rrows do
    for c = 1, rcols do
      local d = rack.grid[r][c]
      local dx, dy = x0 + (c - 1) * 3, y0 + (r - 1) * 6
      for slot = 1, 10 do
        local cx, cy = dx + (slot - 1) % 2, dy + math.floor((slot - 1) / 2)
        local cell = d and d.cells and d.cells[slot]
        if cell then v:put(cx, cy, " ", "fg", cellRole(cell, stale))
        elseif d then v:put(cx, cy, DOT, "dim", "bar")
        else v:put(cx, cy, DOT, "bar", "bg") end
      end
    end
  end
  if rack.built > 0 then v:put(x0, y0 + rrows * 6 - 1, fit(sizes(rack.sizes), rcols * 3 - 1), "dim", "bg") end
end

local function wallLabel(wall) return ("BANK %d %s %s"):format(wall.bank, DOT, wall.side) end

local function roomRows(room) return room.rackRows * 6 + 1 end        -- name row + rack row + drives + sizes
local function wallWidth(room) return room.racksPerWall * (room.rackCols * 3) - 1 end

-- Draw the walls; returns the next free row, or nil when they do not fit. mode "row" (all walls side by side) or "stack"
local function drawRoom(v, room, y, last, stale, mode)
  local ww = wallWidth(room)
  local nWalls = #room.walls
  local height = 1 + roomRows(room)
  local xs = {}
  if mode == "row" then
    if nWalls == 4 and ww == 17 and v.W >= 79 then xs = { 1, 22, 42, 63 }
    else
      local pitch = nWalls > 1 and math.min(ww + 4, math.floor((v.W - ww) / (nWalls - 1))) or 0
      for n = 1, nWalls do xs[n] = 1 + (n - 1) * pitch end
    end
    if y + height - 1 > last then return nil end
    for n, wall in ipairs(room.walls) do
      v:put(xs[n], y, fit(wallLabel(wall), ww), "gold", "bg")
      for _, rack in ipairs(wall.racks) do drawRack(v, rack, xs[n] + (rack.idx - 1) * (room.rackCols * 3), y + 2, room, stale) end
    end
    return y + height
  end
  -- stacked: a bank's walls side by side, one bank under the next
  local per = room.wallsPerBank
  local bankW = per * ww + (per - 1) * 4
  if bankW > v.W - 1 then return nil end
  local banks = room.banks
  if y + banks * (height + 1) - 2 > last then return nil end
  for n, wall in ipairs(room.walls) do
    local inBank = (n - 1) % per
    local bx, by = 1 + inBank * (ww + 4), y + (wall.bank - 1) * (height + 1)
    v:put(bx, by, fit(wallLabel(wall), ww), "gold", "bg")
    for _, rack in ipairs(wall.racks) do drawRack(v, rack, bx + (rack.idx - 1) * (room.rackCols * 3), by + 2, room, stale) end
  end
  return y + banks * (height + 1) - 1
end

-- narrow or short: one line per built rack
local function drawTiles(v, room, y, last, stale)
  local W = v.W
  local unbuilt = 0
  for _, rack in ipairs(room.racks) do
    if rack.built == 0 then unbuilt = unbuilt + 1
    elseif y <= last then
      local f = rack.total > 0 and rack.used / rack.total or 0
      v:put(2, y, fit(rack.name, 3), "fg", "bg")
      v:put(6, y, fit("p" .. tostring(rack.prio), 4), "dim", "bg")
      local sz = fit(sizes(rack.sizes), 7)
      local bw = W - 12 - 6 - 8
      if bw >= 4 then
        bar(v, 11, y, bw, f, stale and "dim" or fillRole(f))
        v:put(11 + bw + 1, y, ("%3d%%"):format(pct(rack.used, rack.total)), "fg", "bg")
        v:put(11 + bw + 6, y, sz, "dim", "bg")
      else
        v:put(11, y, ("%3d%%"):format(pct(rack.used, rack.total)), "fg", "bg")
      end
      y = y + 1
    end
  end
  if unbuilt > 0 and y <= last then v:put(2, y, ("%d racks not built yet"):format(unbuilt), "dim", "bg"); y = y + 1 end
  return y
end

---------------------------------------------------------------------------
-- The rest of the board. The bottom block sits in fixed rows counted up from the last row (docs/design/server.md,
-- UI kit 10.11): nothing in it moves when a tier is added.
---------------------------------------------------------------------------
local TIER_SLOTS = 7

-- `slots` fixed rows from y: one per priority, highest first, blank when unused; too many: the last says `+N more tiers`
local function tiers(v, M, y, slots)
  local room, W = M.room, v.W
  local bw = math.max(4, W - 24 - 33)
  local list = room.tiers
  local shown = #list > slots and slots - 1 or #list
  for i = 1, shown do
    local t = list[i]
    local f = t.total > 0 and t.used / t.total or 0
    local row = y + i - 1
    v:put(2, row, fit("p" .. tostring(t.prio), 4), "fg", "bg")
    v:put(7, row, fit(table.concat(t.racks, "+"), 7), "fg", "bg")
    v:put(15, row, fit(sizes(t.sizes), 8), "dim", "bg")
    bar(v, 24, row, bw, f, M.online and fillRole(f) or "dim")
    local x = 24 + bw + 1
    v:put(x, row, ("%3d%% %s free"):format(pct(t.used, t.total), B.bytes(math.max(0, t.total - t.used))), "fg", "bg")
    local full = ("%d full"):format(t.full)
    v:put(W - #full, row, full, t.full > 0 and "bad" or "dim", "bg")
  end
  if #list > slots then v:put(2, y + slots - 1, ("+%d more tiers"):format(#list - shown), "dim", "bg") end
end

-- the no-size / outside line
local function noSize(v, M, y)
  local room, W = M.room, v.W
  local n, parts = 0, {}
  for _, kind in ipairs({ "Infinity", "MEGA Bulk", "other" }) do
    local c = room.noSize[kind]
    if c then n = n + c; parts[#parts + 1] = c .. " " .. kind end
  end
  local x = 4
  if n > 0 then
    local full = ("%d cell%s with no size: %s. Not in the byte totals."):format(n, n == 1 and "" or "s", table.concat(parts, ", "))
    local outside = room.outside > 0 and (", %d drive%s outside the room"):format(room.outside, room.outside == 1 and "" or "s") or ""
    -- the outside count shares the line: shorten the no-size text when both do not fit
    if 3 + #full + #outside > W then full = full:gsub("%. Not in the byte totals%.$", "") end
    v:put(2, y, " ", "fg", "idle")
    x = v:put(4, y, fit(full, W - 4), "fg", "bg")
    if #outside > 0 then v:put(x, y, fit(outside, W - x), "warn", "bg") end
  elseif room.outside > 0 then
    v:put(x, y, fit(("%d drive%s outside the room"):format(room.outside, room.outside == 1 and "" or "s"), W - x), "warn", "bg")
  end
end

local function defrag(v, M, y)
  local W = v.W
  y = section(v, y, "DEFRAG")
  local d = M.defrag
  local msg = d and d.msg
  if not msg or (M.now - d.at) > STALE_S then
    v:put(2, y, "storage not heard", "warn", "bg")
    return y + 1
  end
  if msg.running then
    local total = (msg.done or 0) + (msg.left or 0)
    v:put(2, y, "running", "info", "bg")
    local right = ("item %d of %d"):format((msg.done or 0) + 1, math.max(total, (msg.done or 0) + 1))
    v:put(W - #right - 1, y, right, "fg", "bg")
    v:put(11, y, fit(tostring(msg.item or "?"), W - 11 - #right - 3), "fg", "bg")
    local freed = ("p0 freed %s bytes"):format(B.bytes(msg.freedBytes or 0))
    local bw = W - #freed - 4
    bar(v, 2, y + 1, bw, total > 0 and (msg.done or 0) / total or 0, "info")
    v:put(W - #freed - 1, y + 1, freed, "dim", "bg")
    return y + 2
  end
  v:put(2, y, "idle", "idle", "bg")
  if (msg.done or 0) > 0 or (msg.freedBytes or 0) > 0 then
    v:put(9, y, fit(("last run: %d items, freed %s bytes"):format(msg.done or 0, B.bytes(msg.freedBytes or 0)), W - 10), "fg", "bg")
  else
    v:put(9, y, "never run", "dim", "bg")
  end
  return y + 1
end

local function energy(v, M, y)
  local W, e = v.W, M.energy
  if not e then return y end
  local f = e.cap and e.cap > 0 and e.stored / e.cap or 0
  local role = f < 0.1 and "bad" or f < 0.3 and "warn" or "good"
  v:put(2, y, "Energy", "dim", "bg")
  bar(v, 9, y, 20, f, M.online and role or "dim")
  v:put(30, y, ("%3d%%  %s AE/t"):format(pct(e.stored, e.cap), commas(e.usage or 0)), "fg", "bg")
  if M.kinds then
    local right = ("%s kinds  %s items"):format(commas(M.kinds), B.count(M.items or 0))
    v:put(W - #right - 1, y, right, "dim", "bg")
  end
  return y + 1
end

local function piles(v, M, y)
  local W = v.W
  if not M.piles or #M.piles == 0 then return y end
  y = section(v, y, "BIGGEST PILES", "defrag moves these first")
  local colW = math.floor((W - 3) / 2)
  for i = 1, 4 do
    for col = 0, 1 do
      local p = M.piles[i + col * 4]
      if p then
        local x = 2 + col * (colW + 1)
        local n = B.count(p.count)
        v:put(x, y, fit(p.name, colW - #n - 1), "fg", "bg")
        v:put(x + colW - #n, y, n, "info", "bg")
      end
    end
    y = y + 1
  end
  return y
end

local function legend(v, y)
  v:fill(1, y, v.W, "bg")
  local x = v:put(2, y, "Fill ", "dim", "bg")
  local function sw(role, text, fg, bg, ch)
    v:put(x, y, ch or " ", fg or "fg", bg or role); x = v:put(x + 2, y, text .. "  ", "dim", "bg")
  end
  sw("good", "<70%"); sw("warn", "70-90%"); sw("bad", ">90%"); sw("idle", "no size (infinity, bulk)")
  v:put(x, y, DOT, "dim", "bar"); x = v:put(x + 2, y, "empty  ", "dim", "bg")
  v:put(x, y, DOT, "bar", "bg"); v:put(x + 2, y, "no drive", "dim", "bg")
end

---------------------------------------------------------------------------
-- The board
---------------------------------------------------------------------------
function B.header(v, M)
  local room = M.room
  local state, color = "ok", "good"
  if not M.seen then state, color = "?", "dim"
  elseif not M.online then state, color = "ME offline", "bad" end
  local right = room and ("%d drives %s %d cells"):format(room.drives, DOT, room.cells) or nil
  return v:header("Server room", { state = state, color = color, right = right })
end

-- Bytes and Slots: the last two rows, under a CAPACITY rule at y
local function capacity(v, M, y, stale)
  local room, W = M.room, v.W
  y = section(v, y, "CAPACITY")
  local bw = math.max(4, W - 9 - 27)
  local f = room.total > 0 and room.used / room.total or 0
  v:put(2, y, "Bytes", "dim", "bg")
  bar(v, 9, y, bw, f, stale and "dim" or fillRole(f))
  v:put(9 + bw + 1, y, fit(("%3d%% %s of %s"):format(pct(room.used, room.total), B.bytes(room.used), B.bytes(room.total)), W - bw - 10), "fg", "bg")
  local slotsTotal = #room.racks * room.rackCols * room.rackRows * 10
  v:put(2, y + 1, "Slots", "dim", "bg")
  bar(v, 9, y + 1, bw, room.cells / math.max(slotsTotal, 1), stale and "dim" or "info")
  v:put(9 + bw + 1, y + 1, fit(("%3d%% %d of %d cells"):format(pct(room.cells, slotsTotal), room.cells, slotsTotal), W - bw - 10), "fg", "bg")
end

-- Rows, counted up from `last` (the board's last row). With S tier slots:
--   last Slots, last-1 Bytes, last-2 CAPACITY, last-4 no size / outside, last-4-S .. last-5 tier slots,
--   last-5-S TIERS, last-9-S .. last-7-S DEFRAG, last-11-S energy.
local function blockRows(last, S)
  return { cap = last - 2, nosize = last - 4, tiers = last - 4 - S, tiersHead = last - 5 - S,
           defrag = last - 9 - S, energy = last - 11 - S }
end

function B.draw(v, M, o)
  o = o or {}
  local W, H = v.W, v.H
  local last = H - (o.reserve or 0)
  local y = B.header(v, M)
  local room = M.room
  if not room then return end
  local stale = M.seen and not M.online
  local big = H >= 50
  -- legend on row 3 under the header, its rule on 4: reference text lives at the top
  if big then
    legend(v, 3)
    v:put(1, 4, ("\140"):rep(W), "bar", "bg")
    y = 6
  else
    y = y + 1
  end

  -- The bottom block. A tall board keeps 7 tier slots whatever the tiers are; a short one only as many as it has.
  local S = big and TIER_SLOTS or math.max(1, math.min(TIER_SLOTS, #room.tiers))
  local R = blockRows(last, S)
  local top = y + 4                                    -- the room (or rack lines) keeps at least a few rows
  -- short boards drop what does not fit: energy first, then defrag, then the tier list
  local showEnergy, showDefrag, showTiers = R.energy - 2 >= top, R.defrag - 2 >= top, R.tiersHead - 2 >= top
  if not showDefrag then showEnergy = false end
  if not showTiers then showDefrag, showEnergy = false, false end
  local roomLast = (showEnergy and R.energy or showDefrag and R.defrag or showTiers and R.tiersHead or R.cap) - 2
  roomLast = math.max(roomLast, y)

  capacity(v, M, R.cap, stale)
  noSize(v, M, R.nosize)
  if showTiers then
    section(v, R.tiersHead, "TIERS", "items fill the top tier first")
    tiers(v, M, R.tiers, S)
  end
  if showDefrag then defrag(v, M, R.defrag) end
  if showEnergy then energy(v, M, R.energy) end

  -- the room: walls side by side, banks stacked, or one line per rack
  local after
  if W >= #room.walls * wallWidth(room) + (#room.walls - 1) * 3 + 1 then after = drawRoom(v, room, y, roomLast, stale, "row")
  elseif W >= 39 then after = drawRoom(v, room, y, roomLast, stale, "stack") end
  if after then
    -- the biggest piles go right under the room while there is space above the energy line
    if big and showEnergy and after + 1 + 5 <= R.energy - 1 then piles(v, M, after + 1, R.energy - 1) end
  else
    drawTiles(v, room, y, roomLast, stale)
  end
end

return B
