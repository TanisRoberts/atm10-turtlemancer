-- sim/weaver.lua  --  helpers for Weaver scenarios.
--
--   local W = require("sim.weaver")
--   local site = W.site{ y = 64, code = {"red","blue","white"}, radius = 20 }
--   site.w, site.turtle (the computer), site.body, site.chest (shared ender inv), site.net, site.dockX/Y/Z
--   site:home(n)         -- put the home end of the chest on the wired net as enderstorage:ender_chest_<n>
--   W.diff(w, expected, opts)  /  W.expect(w, expected, opts)
--
-- site opts: y = ground level (default 64), radius = half-width of the flat ground (default 12), ground = block name
-- (default "minecraft:sand"), code = ender code (default red/blue/white), fuel (default 20000), heading (0..3, default 0),
-- id/label (default 7, "Weaver-01"), delay = ender delivery delay. The ground fills y-1..y; the dock chest replaces the
-- ground block at (0, y, 0) and the turtle sits at (0, y+1, 0) on top of it, with a pickaxe, an ender modem and a
-- chunk controller (slot 16) in its inventory, and the ender chest under it (suckDown / dropDown).
local cc = require("sim.cc")
local Placement = require("sim.placement")

local W = {}

local site_mt = {}
site_mt.__index = site_mt
function site_mt:home(n)
  self.net = self.net or self.w:net()
  return self.w:ender():onNet(self.net, n or 0, self.code)
end

function W.site(opts)
  opts = opts or {}
  local y, r = opts.y or 64, opts.radius or 12
  local w = cc.world()
  w.gpsOn = false                          -- no GPS out here: the Weaver dead-reckons from the dock
  local code = opts.code or { "red", "blue", "white" }
  local es = w:ender()
  es.delay = opts.delay or 0
  w:fill(-r, y - 1, -r, r, y - 1, r, opts.ground or "minecraft:sand")
  w:fill(-r, y, -r, r, y, r, opts.ground or "minecraft:sand")
  local chest = es:inv(code)
  es:place(0, y, 0, code)
  local t = w:turtle{ id = opts.id or 7, label = opts.label or "Weaver-01", x = 0, y = y + 1, z = 0, facing = opts.heading or 0,
                      fuel = opts.fuel or 20000, left = "minecraft:diamond_pickaxe", right = "computercraft:wireless_modem_advanced",
                      items = { [16] = { "advancedperipherals:chunk_controller", 1 } } }
  return setmetatable({ w = w, turtle = t, body = t.body, chest = chest, code = code,
                        groundY = y, dockX = 0, dockY = y, dockZ = 0, radius = r }, site_mt)
end

-- Compare the world with an expected map. `expected` maps "x,y,z" -> "minecraft:name" or { name =, state = { ... } }
-- (only the listed state keys are compared). opts: box = {x1,y1,z1,x2,y2,z2}: inside it every cell not listed must be
-- air (or `opts.fill` = a block name, e.g. the ground); ox/oy/oz offset every expected key; max = mismatches reported (10).
-- Returns ok, list of mismatch strings (first `max`), total mismatches.
function W.diff(w, expected, opts)
  opts = opts or {}
  local ox, oy, oz, max = opts.ox or 0, opts.oy or 0, opts.oz or 0, opts.max or 10
  local bad, total = {}, 0
  local function report(msg) total = total + 1; if #bad < max then bad[#bad + 1] = msg end end
  local function show(blk)
    if not blk then return "air" end
    local parts = {}
    for k, v in pairs(blk.state or {}) do parts[#parts + 1] = k .. "=" .. tostring(v) end
    table.sort(parts)
    return blk.name .. (#parts > 0 and ("[" .. table.concat(parts, ",") .. "]") or "")
  end
  local listed = {}
  local keys = {}
  for k in pairs(expected) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local x, y, z = k:match("^(-?%d+),(-?%d+),(-?%d+)$")
    x, y, z = tonumber(x) + ox, tonumber(y) + oy, tonumber(z) + oz
    listed[x .. "," .. y .. "," .. z] = true
    local want = expected[k]
    if type(want) == "string" then want = { name = want } end
    local got = w:getBlock(x, y, z)
    local ok = got and got.name == want.name
    if ok and want.state then
      for sk, sv in pairs(want.state) do
        if (got.state or {})[sk] ~= sv then ok = false end
      end
    end
    if not ok then
      local ws = {}
      for sk, sv in pairs(want.state or {}) do ws[#ws + 1] = sk .. "=" .. tostring(sv) end
      table.sort(ws)
      report(("(%d,%d,%d) wanted %s%s, found %s"):format(x, y, z, want.name,
        #ws > 0 and ("[" .. table.concat(ws, ",") .. "]") or "", show(got)))
    end
  end
  if opts.box then
    local b = opts.box
    for x = math.min(b[1], b[4]), math.max(b[1], b[4]) do
      for y = math.min(b[2], b[5]), math.max(b[2], b[5]) do
        for z = math.min(b[3], b[6]), math.max(b[3], b[6]) do
          if not listed[x .. "," .. y .. "," .. z] then
            local got = w:getBlock(x, y, z)
            local fine = (opts.fill == nil and got == nil) or (got and got.name == opts.fill)
            if not fine then report(("(%d,%d,%d) should be %s, found %s"):format(x, y, z, opts.fill or "air", show(got))) end
          end
        end
      end
    end
  end
  return total == 0, bad, total
end

-- like diff, but raises an error listing the first mismatches
function W.expect(w, expected, opts)
  local ok, bad, total = W.diff(w, expected, opts)
  if not ok then
    error(("%d block(s) differ from the plan; first %d:\n  %s"):format(total, #bad, table.concat(bad, "\n  ")), 2)
  end
end

W.facing = Placement.facingName
return W
