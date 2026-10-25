-- regionplan.lua  --  Seagull's region maths: which region a chunk is in, the order he scans a region's chunks,
-- the spiral of regions round home, and which quarters of a chunk still need a second scan.
-- A region is SIZE x SIZE chunks (16 by default: the Cartographer expects that), rx = floor(chunkX / SIZE).

local M = { SIZE = 16 }

function M.key(rx, rz) return rx .. "," .. rz end

function M.regionOf(cx, cz, size)
  size = size or M.SIZE
  return math.floor(cx / size), math.floor(cz / size)
end

-- The chunks of a region in scanning order: rows of constant cz, every other row back the other way, so each
-- hop to the next chunk is one chunk long.
function M.chunks(rx, rz, size)
  size = size or M.SIZE
  local out = {}
  for row = 0, size - 1 do
    for col = 0, size - 1 do
      local c = (row % 2 == 0) and col or (size - 1 - col)
      out[#out + 1] = { cx = rx * size + c, cz = rz * size + row }
    end
  end
  return out
end

-- Block at the middle of a chunk: a radius-8 scan from here covers the whole 16 x 16 chunk
function M.centre(cx, cz) return cx * 16 + 8, cz * 16 + 8 end

-- The first region not in `done` (a set of "rx,rz"), in rings round (hx, hz): nearest ring first, clockwise from
-- north. The same order the Cartographer shows as "spiral".
function M.spiral(hx, hz, done, skip)
  for r = 0, 60 do
    local cells = {}
    if r == 0 then cells[1] = { 0, 0 }
    else
      for dx = 0, r do cells[#cells + 1] = { dx, -r } end
      for dz = -r + 1, r do cells[#cells + 1] = { r, dz } end
      for dx = r - 1, -r, -1 do cells[#cells + 1] = { dx, r } end
      for dz = r - 1, -r, -1 do cells[#cells + 1] = { -r, dz } end
      for dx = -r + 1, -1 do cells[#cells + 1] = { dx, -r } end
    end
    for _, c in ipairs(cells) do
      local rx, rz = hx + c[1], hz + c[2]
      local k = M.key(rx, rz)
      if not done[k] and not (skip and skip[k]) then return rx, rz end
    end
  end
end

-- Block positions for extra scans in a chunk whose centre scan left columns unseen (a cliff, deep water, a
-- tall tree): the middle of each quarter that still has an unseen column. `arr` is mapchunk.toArray(chunk).
function M.extras(cx, cz, arr)
  local out = {}
  for qz = 0, 1 do
    for qx = 0, 1 do
      local unseen = false
      for lz = qz * 8, qz * 8 + 7 do
        for lx = qx * 8, qx * 8 + 7 do
          if arr[lz * 16 + lx + 1] == 0 then unseen = true; break end
        end
        if unseen then break end
      end
      if unseen then out[#out + 1] = { x = cx * 16 + qx * 8 + 4, z = cz * 16 + qz * 8 + 4 } end
    end
  end
  return out
end

return M
