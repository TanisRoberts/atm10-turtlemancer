-- mapchunk.lua  --  the world map's storage format, shared by Seagull (the map-making turtle) and the
-- Cartographer computer. Both get this same file, so they always agree.
--
-- The map is a set of 16x16 chunks (same grid as Minecraft's chunks), keyed "cx,cz".
-- Each chunk is a 512-character string: 2 characters per column, columns in rows of x, z = 0..15.
-- A column's value v (0..4095, two base-64 characters):
--   0                       = never seen
--   1 + (y + 64) * 4 + kind = the top block is at height y, of this kind:
--     0 LAND, 1 FOLIAGE (leaves, logs), 2 SHALLOW water (floor within SHALLOW blocks), 3 DEEP water
-- Plain printable characters only, so the strings survive files, rednet and textutils untouched.
--
-- In memory and on rednet a chunk stays that 512-character string. In a map file (save / load) it is
-- run-length coded (M.encode / M.decode): the 256 values in order, each run of equal values written as
--   the value (2 chars)                     a single column
--   the value twice                         a run of 2
--   the value, ".", the length (2 chars)    a run of 3 or more
-- so an all-ocean chunk is 5 characters. Open ocean carries no detail: a DEEP column is saved at
-- OCEAN_Y whatever its height, so it joins the run. A file starts with "#mapv2"; a file without that
-- line (the old format, 512 characters per chunk) still loads, and is rewritten small on the next save.

local M = {}

M.LAND, M.FOLIAGE, M.SHALLOW, M.DEEP = 0, 1, 2, 3
M.SIZE = 512
M.EMPTY = ("AA"):rep(256)
M.OCEAN_Y = 62
M.HEADER = "#mapv2"

local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CH, VAL = {}, {}
for i = 1, 64 do
  local c = ALPHA:sub(i, i)
  CH[i - 1] = c
  VAL[c:byte()] = i - 1
end

function M.key(cx, cz) return cx .. "," .. cz end

function M.parseKey(k)
  local a, b = tostring(k):match("^(%-?%d+),(%-?%d+)$")
  return tonumber(a), tonumber(b)
end

-- Which chunk and which column inside it holds world column (x, z)
function M.locate(x, z)
  local cx, cz = math.floor(x / 16), math.floor(z / 16)
  return cx, cz, x - cx * 16, z - cz * 16
end

function M.pack(y, kind)
  if y == nil then return 0 end
  y = math.max(-64, math.min(959, math.floor(y)))
  return 1 + (y + 64) * 4 + (kind or 0)
end

-- value -> y, kind (nil for an unseen column)
function M.unpack(v)
  if not v or v == 0 then return nil end
  v = v - 1
  return math.floor(v / 4) - 64, v % 4
end

-- Raw value of column (lx, lz) in a chunk string
function M.get(data, lx, lz)
  local i = (lz * 16 + lx) * 2 + 1
  local a, b = VAL[data:byte(i)], VAL[data:byte(i + 1)]
  if not a or not b then return 0 end
  return a * 64 + b
end

-- A chunk string as an array of 256 values (index lz*16 + lx + 1), for editing
function M.toArray(data)
  local t = {}
  data = data or M.EMPTY
  for n = 1, 256 do
    local i = n * 2 - 1
    local a, b = VAL[data:byte(i)], VAL[data:byte(i + 1)]
    t[n] = (a and b) and (a * 64 + b) or 0
  end
  return t
end

function M.fromArray(t)
  local parts = {}
  for n = 1, 256 do
    local v = t[n] or 0
    parts[n] = CH[math.floor(v / 64) % 64] .. CH[v % 64]
  end
  return table.concat(parts)
end

function M.valid(data)
  return type(data) == "string" and #data == M.SIZE and not data:find("[^%w%+/]")
end

-- Merge: take every column `new` knows, keep `old` where `new` has nothing
function M.merge(old, new)
  if not M.valid(old) then return new end
  local a, b = M.toArray(old), M.toArray(new)
  for n = 1, 256 do if b[n] ~= 0 then a[n] = b[n] end end
  return M.fromArray(a)
end

local function pair(v) return CH[math.floor(v / 64) % 64] .. CH[v % 64] end

-- 512-character chunk string -> run-length coded string
function M.encode(data)
  local arr = M.toArray(data)
  for n = 1, 256 do
    local y, kind = M.unpack(arr[n])
    if y and kind == M.DEEP then arr[n] = M.pack(M.OCEAN_Y, M.DEEP) end
  end
  local out, n = {}, 1
  while n <= 256 do
    local v, m = arr[n], n
    while m < 256 and arr[m + 1] == v do m = m + 1 end
    local run = m - n + 1
    local p = pair(v)
    out[#out + 1] = run == 1 and p or run == 2 and p .. p or p .. "." .. pair(run)
    n = m + 1
  end
  return table.concat(out)
end

-- run-length coded string -> 512-character chunk string, or nil when it is not a whole chunk
function M.decode(s)
  if type(s) ~= "string" then return nil end
  local parts, count, i = {}, 0, 1
  while i <= #s do
    local p = s:sub(i, i + 1)
    local a, b = VAL[s:byte(i)], VAL[s:byte(i + 1) or 0]
    if not a or not b then return nil end
    local run = 1
    if s:sub(i + 2, i + 2) == "." then
      local c, d = VAL[s:byte(i + 3) or 0], VAL[s:byte(i + 4) or 0]
      if not c or not d then return nil end
      run = c * 64 + d
      i = i + 5
    else
      i = i + 2
    end
    if run < 1 then return nil end
    count = count + run
    if count > 256 then return nil end
    parts[#parts + 1] = p:rep(run)
  end
  if count ~= 256 then return nil end
  return table.concat(parts)
end

-- Save / load a whole map ({ [key] = { rev = epoch ms, data = string } }) as one plain file
function M.save(path, chunks)
  local f = fs.open(path .. ".new", "w")
  if not f then return false end
  f.writeLine(M.HEADER)
  for k, c in pairs(chunks) do
    if M.valid(c.data) then f.writeLine(k .. " " .. tostring(math.floor(c.rev or 0)) .. " " .. M.encode(c.data)) end
  end
  f.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(path .. ".new", path)
  return true
end

function M.load(path)
  local chunks = {}
  if not fs.exists(path) and fs.exists(path .. ".new") then fs.move(path .. ".new", path) end
  if not fs.exists(path) then return chunks end
  local f = fs.open(path, "r")
  while true do
    local line = f.readLine()
    if not line then break end
    local k, rev, data = line:match("^(%-?%d+,%-?%d+) (%d+) (%S+)$")
    if k and not M.valid(data) then data = M.decode(data) end
    if k and data then chunks[k] = { rev = tonumber(rev), data = data } end
  end
  f.close()
  return chunks
end

return M
