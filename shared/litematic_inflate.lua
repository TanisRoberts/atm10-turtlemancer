-- litematic_inflate: gzip / zlib / raw DEFLATE decompression in plain Lua 5.2.
-- No globals, no peripherals. Works in CraftOS (Cobalt) and under lupa.
-- Decoder follows the structure of zlib's public-domain "puff.c" (Mark Adler):
-- canonical Huffman decoding by code length counts. Stored, fixed and dynamic blocks.
--
--   inflate.gunzip(bytes [, yield]) -> string | nil, err   (gzip header checked, ISIZE checked)
--   inflate.raw(bytes, pos [, yield]) -> string | nil, err (raw DEFLATE starting at byte pos)
-- `yield` is called every few thousand symbols so CraftOS never says "too long without yielding".

local M = {}

local sbyte, schar, concat, unpack = string.byte, string.char, table.concat, table.unpack or unpack

local LBASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXT = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CLORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- Huffman table from code lengths lens[0..n-1] -> { count = {[0..15]}, symbol = {[0..]} }
local function build(lens, n)
  local count, offs, symbol = {}, {}, {}
  for l = 0, 15 do count[l] = 0 end
  for s = 0, n - 1 do count[lens[s]] = count[lens[s]] + 1 end
  offs[1] = 0
  for l = 1, 14 do offs[l + 1] = offs[l] + count[l] end
  for s = 0, n - 1 do
    local l = lens[s]
    if l ~= 0 then
      symbol[offs[l]] = s
      offs[l] = offs[l] + 1
    end
  end
  return { count = count, symbol = symbol }
end

local fixedLit, fixedDist
local function fixed()
  if fixedLit then return fixedLit, fixedDist end
  local l = {}
  for s = 0, 143 do l[s] = 8 end
  for s = 144, 255 do l[s] = 9 end
  for s = 256, 279 do l[s] = 7 end
  for s = 280, 287 do l[s] = 8 end
  fixedLit = build(l, 288)
  local d = {}
  for s = 0, 29 do d[s] = 5 end
  fixedDist = build(d, 30)
  return fixedLit, fixedDist
end

function M.raw(data, pos, yield)
  local len = #data
  local bitbuf, bitcnt = 0, 0
  local out, on = {}, 0
  local work = 0

  local function bits(need)
    local val = bitbuf
    while bitcnt < need do
      local b = sbyte(data, pos)
      if not b then error("inflate: ran out of input", 0) end
      pos = pos + 1
      val = val + b * 2 ^ bitcnt
      bitcnt = bitcnt + 8
    end
    bitbuf = math.floor(val / 2 ^ need)
    bitcnt = bitcnt - need
    return val % 2 ^ need
  end

  local function decode(h)
    local code, first, index = 0, 0, 0
    local count, symbol = h.count, h.symbol
    for l = 1, 15 do
      code = code + bits(1)
      local c = count[l]
      if code - c < first then return symbol[index + (code - first)] end
      index = index + c
      first = (first + c) * 2
      code = code * 2
    end
    error("inflate: bad Huffman code", 0)
  end

  local function tick(n)
    work = work + n
    if work >= 4000 then
      work = 0
      if yield then yield() end
    end
  end

  local function codes(lit, dist)
    while true do
      local sym = decode(lit)
      if sym < 256 then
        on = on + 1
        out[on] = sym
        tick(1)
      elseif sym == 256 then
        return
      else
        sym = sym - 257
        if sym >= 29 then error("inflate: bad length symbol", 0) end
        local length = LBASE[sym + 1] + bits(LEXT[sym + 1])
        local ds = decode(dist)
        if ds >= 30 then error("inflate: bad distance symbol", 0) end
        local d = DBASE[ds + 1] + bits(DEXT[ds + 1])
        if d > on then error("inflate: distance too far back", 0) end
        for i = 1, length do
          out[on + i] = out[on + i - d]
        end
        on = on + length
        tick(length)
      end
    end
  end

  local function stored()
    bitbuf, bitcnt = 0, 0
    if pos + 3 > len then error("inflate: ran out of input", 0) end
    local n = sbyte(data, pos) + sbyte(data, pos + 1) * 256
    local nn = sbyte(data, pos + 2) + sbyte(data, pos + 3) * 256
    if n ~= 65535 - nn then error("inflate: stored block length mismatch", 0) end
    pos = pos + 4
    if pos + n - 1 > len then error("inflate: ran out of input", 0) end
    for i = 0, n - 1 do out[on + i + 1] = sbyte(data, pos + i) end
    on = on + n
    pos = pos + n
    tick(n)
  end

  local function dynamic()
    local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
    if nlen > 286 or ndist > 30 then error("inflate: bad dynamic counts", 0) end
    local lens = {}
    for i = 0, 18 do lens[i] = 0 end
    for i = 1, ncode do lens[CLORDER[i]] = bits(3) end
    local clh = build(lens, 19)
    local all, idx = {}, 0
    while idx < nlen + ndist do
      local sym = decode(clh)
      if sym < 16 then
        all[idx] = sym
        idx = idx + 1
      else
        local prev, rep = 0, 0
        if sym == 16 then
          if idx == 0 then error("inflate: repeat with no previous length", 0) end
          prev = all[idx - 1]
          rep = 3 + bits(2)
        elseif sym == 17 then
          rep = 3 + bits(3)
        else
          rep = 11 + bits(7)
        end
        if idx + rep > nlen + ndist then error("inflate: too many code lengths", 0) end
        for _ = 1, rep do
          all[idx] = prev
          idx = idx + 1
        end
      end
    end
    if all[256] == 0 then error("inflate: no end-of-block code", 0) end
    local ll, dl = {}, {}
    for i = 0, nlen - 1 do ll[i] = all[i] end
    for i = 0, ndist - 1 do dl[i] = all[nlen + i] end
    codes(build(ll, nlen), build(dl, ndist))
  end

  local ok, err = pcall(function()
    local last
    repeat
      last = bits(1)
      local t = bits(2)
      if t == 0 then
        stored()
      elseif t == 1 then
        local l, d = fixed()
        codes(l, d)
      elseif t == 2 then
        dynamic()
      else
        error("inflate: bad block type", 0)
      end
    until last == 1
  end)
  if not ok then return nil, tostring(err) end

  local parts, pn = {}, 0
  for i = 1, on, 4000 do
    pn = pn + 1
    parts[pn] = schar(unpack(out, i, math.min(i + 3999, on)))
    if yield and pn % 8 == 0 then yield() end
  end
  return concat(parts), pos
end

-- gzip: 10-byte header, optional extra/name/comment/hcrc, DEFLATE, CRC32, ISIZE.
function M.gunzip(data, yield)
  if #data < 18 or sbyte(data, 1) ~= 0x1f or sbyte(data, 2) ~= 0x8b then
    return nil, "not a gzip file (a .litematic is gzipped)"
  end
  if sbyte(data, 3) ~= 8 then return nil, "gzip: unknown compression method" end
  local flg = sbyte(data, 4)
  local pos = 11
  if flg % 8 >= 4 then -- FEXTRA
    pos = pos + 2 + sbyte(data, pos) + sbyte(data, pos + 1) * 256
  end
  if flg % 16 >= 8 then -- FNAME
    while sbyte(data, pos) ~= 0 do pos = pos + 1 end
    pos = pos + 1
  end
  if flg % 32 >= 16 then -- FCOMMENT
    while sbyte(data, pos) ~= 0 do pos = pos + 1 end
    pos = pos + 1
  end
  if flg % 4 >= 2 then pos = pos + 2 end -- FHCRC
  local s, p = M.raw(data, pos, yield)
  if not s then return nil, p end
  local t = { sbyte(data, p + 4, p + 7) }
  if #t == 4 then
    local isize = t[1] + t[2] * 256 + t[3] * 65536 + t[4] * 16777216
    if isize ~= #s % 4294967296 then return nil, "gzip: size check failed (file damaged?)" end
  end
  return s
end

return M
