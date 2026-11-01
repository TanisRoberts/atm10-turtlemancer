-- seagull_nav.lua: the 3D picture of his scans and the A* path round things (caves, ledges, overhangs).
local cc = require("sim.cc")
local T = require("sim.test")

local function newNav()
  local mk = assert(loadfile(cc.ROOT .. "/turtle/seagull/seagull_nav.lua", "t", {
    math = math, table = table, string = string, ipairs = ipairs, pairs = pairs, type = type, tostring = tostring,
    setmetatable = setmetatable }))()
  return mk()
end

-- A scan result from a set of solid cells round (ox, oy, oz)
local function scanOf(cells, ox, oy, oz)
  local out = {}
  for _, c in ipairs(cells) do out[#out + 1] = { x = c[1] - ox, y = c[2] - oy, z = c[3] - oz, name = "minecraft:stone" } end
  return out
end

T.test("nav: in a pocket closed on top and on three sides he plans back out and round, never through stone", function()
  local nav = newNav()
  local cells = {}
  for y = 60, 70 do for z = -3, 3 do cells[#cells + 1] = { 5, y, z } end end          -- the wall ahead (east)
  for x = 0, 4 do for z = -1, 1 do cells[#cells + 1] = { x, 66, z } end end         -- a roof just over him
  for x = 0, 4 do cells[#cells + 1] = { x, 65, -1 }; cells[#cells + 1] = { x, 65, 1 } end   -- the pocket's sides
  for x = -2, 8 do for z = -4, 4 do cells[#cells + 1] = { x, 63, z } end end        -- the ground
  nav.observe(scanOf(cells, 3, 65, 0), 3, 65, 0, 8)
  local path = nav.path({ x = 3, y = 65, z = 0 }, { x = 8, y = 67, z = 0 }, { maxY = 300 })
  T.truthy(path, "a way out was found")
  for _, st in ipairs(path) do T.eq(nav.isSolid(st.x, st.y, st.z), false, "never through stone at " .. st.x .. "," .. st.y .. "," .. st.z) end
  T.eq(path[#path].x .. "," .. path[#path].y .. "," .. path[#path].z, "8,67,0")
end)

T.test("nav: a block the scans missed is marked when he bumps into it, and he plans round it", function()
  local nav = newNav()
  nav.observe({}, 0, 64, 0, 8)
  local at = { x = 0, y = 64, z = 0 }
  local hidden = { ["2,64,0"] = true }
  local io = {
    pos = function() return at end,
    move = function(dir)
      local x, y, z = at.x, at.y, at.z
      if dir == "up" then y = y + 1 elseif dir == "down" then y = y - 1 else x, z = x + nav.DX[dir], z + nav.DZ[dir] end
      if hidden[x .. "," .. y .. "," .. z] then return false, "Movement obstructed" end
      at = { x = x, y = y, z = z }
      return true
    end,
  }
  local ok, why = nav.go({ x = 4, y = 64, z = 0 }, io)
  T.eq(ok, true, tostring(why))
  T.eq(nav.isSolid(2, 64, 0), true, "the hidden block is remembered")
end)
