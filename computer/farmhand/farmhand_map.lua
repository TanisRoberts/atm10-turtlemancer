-- farmhand_map.lua  --  the farm map for the Farmhand screens: what a map character looks like, what a tap on it
-- says, the key under the map, the small shrunk-to-fit copy on an overview tile. All colours are the UI kit's
-- roles (see shared/ui.lua); the map itself is drawn by the kit's v:map, the thumbnail through v:cells.
-- A map message comes from farmbot.lua (B.mapMsg): { w, h, rows[], states[], crops[], role, north, stamp }.
local M = {}

local ARROW = { [0] = "\30", "\16", "\31", "\17" }      -- facing north / east / south / west
local SPADE = "\6"                                        -- looks like a little tree
M.ARROW, M.SPADE = ARROW, SPADE

-- Crop colours (by the seed/crop id); anything else gets one from the spare list
local CROP_COLOURS = {
  { "wheat", "fg" }, { "carrot", "warn" }, { "potato", "dim" }, { "beetroot", "bad" },
  { "nether_wart", "bad" }, { "melon", "good" }, { "pumpkin", "warn" }, { "hemp", "good" },
  { "immersiveengineering", "good" }, { "mysticalagriculture", "mark" }, { "berr", "soft" },
  { "sugar_cane", "good" }, { "cotton", "fg" }, { "flax", "idle" },
}
local SPARE = { "info", "soft", "idle", "busy", "fg", "good", "gold" }
function M.cropColour(name, i)
  name = tostring(name)
  for _, c in ipairs(CROP_COLOURS) do if name:find(c[1], 1, true) then return c[2] end end
  return SPARE[((i or 1) - 1) % #SPARE + 1]
end
function M.cropName(id)
  local n = tostring(id):gsub("^.-:", ""):gsub("_seeds?$", ""):gsub("_crop$", ""):gsub("_", " ")
  if n == "seed" then n = "hemp" end
  return (n:gsub("^%l", string.upper))
end
local cropName, cropColour = M.cropName, M.cropColour

-- One map cell -> character, text role, background role
function M.look(m, c, st)
  if c == " " or c == "" then return " ", "bg", "bg" end
  if c == "#" then return " ", "bar", "bar" end                            -- slab border
  if c == "@" then return "D", "bg", "gold" end                            -- dock barrel
  if c == "%" then return "\127", "bar", "bg" end                          -- something solid
  if c == "," then return "~", "idle", "water" end                         -- water / path
  if c == "&" then return "o", "warn", "soil" end                          -- pumpkin/melon spot
  if m.role == "lumberjack" then
    if c == "." then return " ", "good2", "good2" end                      -- lane
    if c == "!" then return SPADE, "good", "soil" end                      -- wild tree, gets chopped
    if c == "+" then
      if st == "h" then return SPADE, "gold", "good2" end                  -- chopped + replanted
      if st == "g" then return SPADE, "good", "good2" end                  -- sapling growing
      if st == "e" then return "+", "bad", "good2" end                     -- nothing planted
      return "+", "dim", "good2"                                           -- not visited yet
    end
  end
  if c == "." then return " ", "bar", "bg" end
  if c == "*" then return ".", "dim", "soil" end
  local i = c:byte() - 96
  if i >= 1 and i <= 26 then
    local name = m.crops and m.crops[i]
    local letter = cropName(name or "?"):sub(1, 1)
    if st == "e" then return ".", "bad", "soil" end                        -- empty: no seed
    local col = cropColour(name, i)
    if st == "h" then return letter:upper(), col, "soil" end               -- harvested last round
    return letter:lower(), col, "soil"                                     -- growing
  end
  return "?", "fg", "bg"
end

-- What a tap on a cell says
function M.describe(m, ch, st)
  local what = ({ ["#"] = "the slab border", ["@"] = "the dock barrel", ["%"] = "something solid",
    [","] = "water or a path (skipped)", ["&"] = "pumpkin/melon spot", ["."] = "lane",
    ["!"] = "a wild tree (gets chopped, then it's a lane)", ["*"] = "a plot (crop not known yet)", [" "] = "outside the farm" })[ch]
  if ch == "+" then
    what = "tree spot: " .. (({ h = "chopped last round, replanted", g = "sapling growing", e = "nothing planted (no sapling)" })[st] or "not visited yet")
  end
  local i = ch ~= "" and ch:byte() - 96 or 0
  if i >= 1 and i <= 26 then
    what = cropName(m.crops[i] or "?") .. ": " .. (({ h = "harvested last round, replanted", g = "growing", e = "empty (no seeds)" })[st] or "not visited yet")
  end
  return what or "?"
end

function M.stats(m)
  local n = { cells = 0 }
  local perCrop = {}
  for r = 1, m.h do
    local row, srow = m.rows[r], m.states[r] or ""
    for c = 1, m.w do
      local ch, st = row:sub(c, c), srow:sub(c, c)
      if ch ~= " " and ch ~= "#" and ch ~= "%" then n.cells = n.cells + 1 end
      n[ch] = (n[ch] or 0) + 1
      local key = ch .. st
      n[key] = (n[key] or 0) + 1
      local i = ch:byte() - 96
      if i >= 1 and i <= 26 then
        perCrop[i] = perCrop[i] or { all = 0, h = 0, g = 0, e = 0 }
        perCrop[i].all = perCrop[i].all + 1
        if st ~= " " then perCrop[i][st] = (perCrop[i][st] or 0) + 1 end
      end
    end
  end
  return n, perCrop
end

-- The kit's v:map `get` for this map: (column, row) -> { background role, character, text, text role }
function M.getter(m)
  return function(c, r)
    if c < 1 or r < 1 or c > m.w or r > m.h then return nil end
    local ch, f, b = M.look(m, m.rows[r]:sub(c, c), (m.states[r] or ""):sub(c, c))
    return { b, ch, nil, f }
  end
end

-- The key under the map: { glyph, text role, background role, text, text role of the words }
function M.key(m, s, stale, onMap)
  local n, perCrop = M.stats(m)
  local lines = {}
  local function add(ch, f, b, text, colour) lines[#lines + 1] = { ch, f, b, text, colour } end
  add(ARROW[s and s.mp and s.mp.h or 0], "fg", stale and "bar" or "mark",
    stale and "not heard" or (onMap and "here" or "off the map"), stale and "bar" or "fg")
  if m.role == "lumberjack" then
    add(SPADE, "gold", "good2", ("replanted %d"):format(n["+h"] or 0))
    add(SPADE, "good", "good2", ("saplings %d"):format(n["+g"] or 0))
    if (n["+e"] or 0) > 0 then add("+", "bad", "good2", ("empty %d"):format(n["+e"]), "warn") end
    if (n["+ "] or 0) > 0 then add("+", "dim", "good2", ("unvisited %d"):format(n["+ "])) end
    if (n["!"] or 0) > 0 then add(SPADE, "good", "soil", ("wild %d"):format(n["!"])) end
  else
    for i, name in ipairs(m.crops or {}) do
      local pc = perCrop[i] or { all = 0, e = 0 }
      add(cropName(name):sub(1, 1):upper(), cropColour(name, i), "soil", ("%s %d"):format(cropName(name), pc.all))
    end
    add("A", "fg", "soil", "harvested")
    add("a", "fg", "soil", "growing")
    local empty = 0
    for _, pc in pairs(perCrop) do empty = empty + (pc.e or 0) end
    add(".", "bad", "soil", ("empty %d"):format(empty), empty > 0 and "warn" or nil)
    if (n[","] or 0) > 0 then add("~", "idle", "water", "water") end
    if (n["&"] or 0) > 0 then add("o", "warn", "soil", "gourd") end
  end
  add("D", "bg", "gold", "dock")
  return lines
end

-- Lay the key out in rows of width w; draw = false just counts the rows
function M.drawKey(v, lines, x, y, w, maxRows, draw)
  local row, cx = 1, x
  for _, e in ipairs(lines) do
    local len = #e[4] + 3
    if cx + len - 1 > x + w and cx > x then row, cx = row + 1, x end
    if row > maxRows then break end
    if draw then
      v:put(cx, y + row - 1, e[1], e[2], e[3])
      v:put(cx + 1, y + row - 1, " " .. e[4]:sub(1, w - 2), e[5] or "dim", "bg")
    end
    cx = cx + len
  end
  return math.min(row, maxRows)
end

-- When a map is shrunk to fit, each screen cell stands for a block of cells: show the one that
-- matters most (an empty spot beats a crop beats a lane), so sparse tree spots don't vanish.
local PRIORITY = { [" "] = -1, ["."] = 0, ["%"] = 1, ["#"] = 2, [","] = 3, ["&"] = 4, ["*"] = 5, ["+"] = 5, ["!"] = 5, ["@"] = 9 }
local function priority(ch, st)
  local p = PRIORITY[ch] or 5                      -- crop letters
  if p == 5 and st == "e" then p = 8 end
  return p
end
local shrinkCache = {}   -- id -> { key, grid }
local function shrunk(id, m, k, dw, dh)
  local key = ("%s/%s/%d/%d"):format(tostring(m.stamp), tostring(k), dw, dh)
  local c = shrinkCache[id]
  if c and c.key == key then return c.grid end
  local grid = {}
  for j = 1, dh do
    grid[j] = {}
    local r1, r2 = math.floor((j - 1) * k) + 1, math.min(m.h, math.floor(j * k))
    for i = 1, dw do
      local c1, c2 = math.floor((i - 1) * k) + 1, math.min(m.w, math.floor(i * k))
      local best, bc, bs = -2, " ", " "
      for r = r1, math.max(r1, r2) do
        local row, srow = m.rows[r] or "", m.states[r] or ""
        for cc = c1, math.max(c1, c2) do
          local ch, st = row:sub(cc, cc), srow:sub(cc, cc)
          if ch == "" then ch = " " end
          local p = priority(ch, st)
          if p > best then best, bc, bs = p, ch, st end
        end
      end
      grid[j][i] = { bc, bs }
    end
  end
  shrinkCache[id] = { key = key, grid = grid }
  return grid
end

-- The farm drawn small in the box (x, y, bw, bh): 1 character per cell, 2 when it fits, shrunk when it doesn't,
-- with the turtle's arrow where it is. tc, tr, th: the turtle's cell and heading (nil when off the map).
function M.thumb(v, id, m, x, y, bw, bh, tc, tr, th, stale)
  if bw < 3 or bh < 2 then return end
  local cw = (m.w * 2 <= bw) and 2 or 1
  local cols = math.floor(bw / cw)
  local function cell(ch, st, isTurtle)
    if isTurtle then return ARROW[th] or "@", "fg", stale and "bar" or "mark" end
    return M.look(m, ch, st)
  end
  local function row(px, py, cells)
    local out = {}
    for _, c in ipairs(cells) do
      out[#out + 1] = c
      if cw == 2 then out[#out + 1] = { c[1] == "\127" and c[1] or " ", c[2], c[3] } end
    end
    v:cells(px, py, out)
  end
  if m.w <= cols and m.h <= bh then                      -- fits 1:1 (or 2:1): centred
    local ox, oy = x + math.floor((cols - m.w) / 2) * cw, y + math.floor((bh - m.h) / 2)
    for r = 1, m.h do
      local cells = {}
      for c = 1, m.w do
        local ch, f, b = cell(m.rows[r]:sub(c, c), (m.states[r] or ""):sub(c, c), tc == c and tr == r)
        cells[c] = { ch, f, b }
      end
      row(ox, oy + r - 1, cells)
    end
    return
  end
  cw = 1
  local k = math.max(m.w / bw, m.h / bh)
  local dw, dh = math.min(math.max(1, math.ceil(m.w / k)), bw), math.min(math.max(1, math.ceil(m.h / k)), bh)
  local grid = shrunk(id, m, k, dw, dh)
  local ti = tc and math.min(dw, math.floor((tc - 1) / k) + 1)
  local tj = tr and math.min(dh, math.floor((tr - 1) / k) + 1)
  local ox, oy = x + math.floor((bw - dw) / 2), y + math.floor((bh - dh) / 2)
  for j = 1, dh do
    local cells = {}
    for i = 1, dw do
      local g = grid[j][i]
      local ch, f, b = cell(g[1], g[2], ti == i and tj == j)
      cells[i] = { ch, f, b }
    end
    row(ox, oy + j - 1, cells)
  end
end

return M
