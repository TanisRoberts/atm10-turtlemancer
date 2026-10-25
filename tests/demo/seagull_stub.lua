-- tests/demo/seagull_stub.lua  --  a stand-in Seagull for Cartographer scenarios.
-- Reads stub.cfg = { regions = { { rx, rz, kind } }, status = {...}, doneRegion = { rx, rz } }. kind "island" is
-- mostly ocean with an island in the middle, "noisy" is land whose height changes every 8 columns (about 47 KB a region), "ocean" is all deep water.
-- Serves `have` in batches of 24 like Seagull, broadcasts a status every 3 s, keeps every order in _G.cmds and every
-- region_ok in _G.oks, and clears done_region once the Cartographer has said region_ok.
local mc = require("mapchunk")
local f = fs.open("stub.cfg", "r"); local cfg = textutils.unserialise(f.readAll()); f.close()
peripheral.find("modem", function(n) rednet.open(n); return false end)
local P = "tanis-carto"
local me = os.getComputerID()

local function chunk(kind, cx, cz, i)
  local t = {}
  for n = 1, 256 do
    local x, z = (n - 1) % 16, math.floor((n - 1) / 16)
    local v
    if kind == "ocean" then v = mc.pack(62, mc.DEEP)
    elseif kind == "noisy" then v = mc.pack(60 + (math.floor(x / 8) * 7 + z * 13 + cx * 5 + cz * 3) % 60, mc.LAND)
    else
      local d = math.abs(cx % 16 - 8) + math.abs(cz % 16 - 8)
      if d > 4 then v = mc.pack(62, mc.DEEP)
      elseif d > 2 then v = mc.pack(61, mc.SHALLOW)
      else v = mc.pack(64 + (x + z) % 4 + (3 - d) * 4, ((x * z + n) % 9 == 0) and mc.FOLIAGE or mc.LAND) end
    end
    t[n] = v
  end
  return mc.fromArray(t)
end

local chunks = {}
for _, r in ipairs(cfg.regions) do
  for dz = 0, 15 do for dx = 0, 15 do
    local cx, cz = r[1] * 16 + dx, r[2] * 16 + dz
    chunks[cx .. "," .. cz] = { rev = 1000 + (cx * 31 + cz) % 500 + 500, data = chunk(r[3], cx, cz) }
  end end
end

local status = cfg.status
status.id = me
status.done_region = cfg.doneRegion
if status.scan_ago then status.scan_started = os.epoch('utc') - status.scan_ago * 1000 end
_G.cmds, _G.oks, _G.haves = {}, {}, 0
local last = -100
while true do
  local from, msg = rednet.receive(P, 1)
  if type(msg) == "table" and msg.to == me then
    if msg.type == "have" then
      _G.haves = _G.haves + 1
      local want = {}
      for k, c in pairs(chunks) do
        local r = tonumber(msg.revs[k])
        if not r or r < c.rev then want[#want + 1] = k end
      end
      table.sort(want)
      local out = {}
      for i = 1, math.min(24, #want) do out[want[i]] = chunks[want[i]] end
      rednet.send(from, { type = "chunks", from = me, chunks = out, more = #want > 24 }, P)
    elseif msg.type == "cmd" then
      _G.cmds[#_G.cmds + 1] = msg
      status.seq = msg.seq
    elseif msg.type == "region_ok" then
      _G.oks[#_G.oks + 1] = msg
      if status.done_region and msg.region[1] == status.done_region[1] and msg.region[2] == status.done_region[2] then
        status.done_region = nil
      end
    end
  end
  if os.clock() - last >= 3 then rednet.broadcast(status, P); last = os.clock() end
end
