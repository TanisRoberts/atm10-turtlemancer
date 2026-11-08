-- litematic_nbt: big-endian NBT reader in plain Lua 5.2 (CraftOS has no 64-bit integers).
--
--   nbt.parse(bytes [, yield]) -> rootName, rootValue      (bytes = uncompressed NBT)
-- Values: Byte/Short/Int -> number, Float/Double -> number, String -> string,
--   List -> array table, Compound -> table by key, Byte_Array / Int_Array -> array table.
--   Long -> a double (approximate above 2^53; nothing here relies on exact values).
--   Long_Array -> { longs = <8*n raw bytes>, n = n }  never converted to numbers: use nbt.bits().
--
--   nbt.bits(longArray, bitpos, width) -> number  reads `width` (<=24) bits starting at bit `bitpos`
--     of the array seen as one little-endian bit stream (Litematica's packing, entries may straddle longs).

local M = {}
local sbyte, ssub = string.byte, string.sub

local function bigint(s, p, n) -- unsigned big-endian, n <= 6 exact
  local v = 0
  for i = p, p + n - 1 do v = v * 256 + sbyte(s, i) end
  return v
end

local function signed(v, bitsn)
  local half = 2 ^ (bitsn - 1)
  if v >= half then return v - 2 * half end
  return v
end

local function f32(s, p)
  local b1, b2, b3, b4 = sbyte(s, p, p + 3)
  local sign = b1 >= 128 and -1 or 1
  local e = (b1 % 128) * 2 + math.floor(b2 / 128)
  local m = (b2 % 128) * 65536 + b3 * 256 + b4
  if e == 0 then return sign * m * 2 ^ -149 end
  if e == 255 then return m == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + m / 8388608) * 2 ^ (e - 127)
end

local function f64(s, p)
  local b1, b2 = sbyte(s, p, p + 1)
  local sign = b1 >= 128 and -1 or 1
  local e = (b1 % 128) * 16 + math.floor(b2 / 16)
  local hi = (b2 % 16) * 2 ^ 32 + bigint(s, p + 2, 4)
  local lo = bigint(s, p + 6, 2)
  local frac = (hi * 65536 + lo) / 2 ^ 52
  if e == 0 then return sign * frac * 2 ^ -1022 end
  if e == 2047 then return frac == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + frac) * 2 ^ (e - 1023)
end

function M.parse(s, yield)
  local pos = 1
  local work = 0
  local readers = {}

  local function tick(n)
    work = work + n
    if work >= 3000 then
      work = 0
      if yield then yield() end
    end
  end

  local function need(n)
    if pos + n - 1 > #s then error("nbt: file ends early", 0) end
  end

  local function str()
    need(2)
    local n = bigint(s, pos, 2)
    pos = pos + 2
    need(n)
    local v = ssub(s, pos, pos + n - 1)
    pos = pos + n
    return v
  end

  local function payload(t)
    local r = readers[t]
    if not r then error("nbt: unknown tag type " .. tostring(t), 0) end
    return r()
  end

  readers[1] = function() need(1); pos = pos + 1; return signed(sbyte(s, pos - 1), 8) end
  readers[2] = function() need(2); pos = pos + 2; return signed(bigint(s, pos - 2, 2), 16) end
  readers[3] = function() need(4); pos = pos + 4; return signed(bigint(s, pos - 4, 4), 32) end
  readers[4] = function()
    need(8)
    local hi, lo = signed(bigint(s, pos, 4), 32), bigint(s, pos + 4, 4)
    pos = pos + 8
    return hi * 4294967296 + lo
  end
  readers[5] = function() need(4); pos = pos + 4; return f32(s, pos - 4) end
  readers[6] = function() need(8); pos = pos + 8; return f64(s, pos - 8) end
  readers[7] = function()
    need(4)
    local n = bigint(s, pos, 4)
    pos = pos + 4
    need(n)
    local t = {}
    for i = 1, n do t[i] = signed(sbyte(s, pos + i - 1), 8) end
    pos = pos + n
    tick(n)
    return t
  end
  readers[8] = str
  readers[9] = function()
    need(5)
    local t = sbyte(s, pos)
    local n = bigint(s, pos + 1, 4)
    pos = pos + 5
    local out = {}
    for i = 1, n do
      out[i] = payload(t)
      tick(1)
    end
    return out
  end
  readers[10] = function()
    local out = {}
    while true do
      need(1)
      local t = sbyte(s, pos)
      pos = pos + 1
      if t == 0 then return out end
      local k = str()
      out[k] = payload(t)
      tick(1)
    end
  end
  readers[11] = function()
    need(4)
    local n = bigint(s, pos, 4)
    pos = pos + 4
    need(n * 4)
    local t = {}
    for i = 1, n do
      t[i] = signed(bigint(s, pos, 4), 32)
      pos = pos + 4
    end
    tick(n)
    return t
  end
  readers[12] = function()
    need(4)
    local n = bigint(s, pos, 4)
    pos = pos + 4
    need(n * 8)
    local raw = ssub(s, pos, pos + n * 8 - 1)
    pos = pos + n * 8
    return { longs = raw, n = n }
  end

  need(1)
  local t = sbyte(s, pos)
  pos = pos + 1
  if t ~= 10 then error("nbt: root is not a compound (is this a .litematic?)", 0) end
  local name = str()
  return name, payload(10)
end

-- bit k of the stream lives in long floor(k/64), at bit k%64 from the least significant end;
-- the longs are stored big-endian, so stream byte j sits at raw offset 8*floor(j/8) + 7 - j%8.
function M.bits(arr, bitpos, width)
  local raw = arr.longs
  local j0 = math.floor(bitpos / 8)
  local sh = bitpos - j0 * 8
  local nb = math.floor((sh + width + 7) / 8)
  local v, mul = 0, 1
  for k = 0, nb - 1 do
    local j = j0 + k
    local off = (j - j % 8) + 8 - j % 8 -- 1-based: 8*floor(j/8) + 7 - j%8 + 1
    local b = sbyte(raw, off)
    if not b then return 0 end -- past the end: reads as air-like zero
    v = v + b * mul
    mul = mul * 256
  end
  return math.floor(v / 2 ^ sh) % 2 ^ width
end

return M
