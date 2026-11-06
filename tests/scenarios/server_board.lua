-- Server room board (#127, docs/design/server.md): a partly built room from the ME mock at 79x67, the layout read
-- from drive positions, defrag progress from storage's broadcast, the bridge going offline, and the smaller screens.
local cc = require("sim.cc")
local T = require("sim.test")
local COLOURS = colours or colors

local DOT = "\183"

-- Stand-in for storage: broadcasts whatever is in defrag.msg (the scenario writes it) on the base protocol.
local STORAGE = [[
  rednet.open("top")
  while true do
    if fs.exists("defrag.msg") then
      local f = fs.open("defrag.msg", "r"); local m = textutils.unserialize(f.readAll()); f.close()
      if m then rednet.broadcast(m, "tanis-base") end
    end
    sleep(2)
  end
]]

-- The room: bank 1 west wall (x=0, columns run along z) holds R1+R2 at priority 0 (1k and 4k cells) and R3 at 5 (64k);
-- bank 1 east wall (x=4) holds R4 at 10 (256M, three drives). Seen from the aisle the west wall runs from high z to low z,
-- so R1 is the highest z.
local function room(opts)
  opts = opts or {}
  local w = cc.world()
  local net = w:net()
  local me = net:add("me_bridge_0", w:meBridge{})
  local r1 = me:addRackAt{ axis = "x", at = 0, col0 = 4, priority = 0, cell = "1k" }
  local r2 = me:addRackAt{ axis = "x", at = 0, col0 = 2, priority = 0, cell = "4k" }
  me:addRackAt{ axis = "x", at = 0, col0 = 0, priority = 5, cell = "64k", skip = 4 }
  -- R4: three drives; the second holds an Infinity and a MEGA Bulk cell (no size), the third only three cells
  local r4 = me:addRackAt{ axis = "x", at = 4, col0 = 0, priority = 10, skip = 7 }
  for s = 1, 10 do me:addCell(r4[1], "256M") end
  for s = 1, 8 do me:addCell(r4[2], "256M") end
  me:addCell(r4[2], "infinity"); me:addCell(r4[2], "bulk")
  for s = 1, 3 do me:addCell(r4[3], "256M") end
  if opts.odd then me:addDrive{ x = 300, y = 64, z = 300, priority = 0 } end
  -- fill: R1's first cell nearly full (red), second at ~75% (orange), a few more with a little
  local cells = {}
  for _, d in ipairs(r1) do for s = 1, 10 do cells[#cells + 1] = d.cells[s] end end
  me:fill(cells[1], "minecraft:cobblestone", 7800)
  me:fill(cells[2], "minecraft:cobblestone", 6200)
  for i = 3, 12 do me:fill(cells[i], "minecraft:cobbled_deepslate", 500) end
  me:fill(r2[1].cells[1], "minecraft:netherrack", 20000)
  me:fill(r4[1].cells[1], "minecraft:raw_copper", 301000)
  local srv = w:computer{ id = 2, label = "Server", w = opts.w or 51, h = opts.h or 19 }
  srv:attach("back", cc.wired(net))
  srv:attach("top", cc.wireless{ ender = true })
  local mon = (opts.monitor ~= false) and srv:monitor("right", opts.mw or 79, opts.mh or 67) or nil
  srv:installRole("server")
  if opts.env then srv:writeFile("server.env", opts.env) end
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("top", cc.wireless{ ender = true })
  st:writeFile("stand.lua", STORAGE)
  return w, srv, mon, me, st, net
end

local function boot(opts)
  local w, srv, mon, me, st, net = room(opts)
  st:run("stand")
  srv:run("server")
  w:run(opts and opts.run or 8)
  return w, srv, mon, me, st, net
end

local function say(st, msg) st:writeTable("defrag.msg", msg) end

T.test("server: a partly built room at 79x67", function()
  local w, srv, mon = boot()
  T.running(srv)
  T.contains(mon, "SERVER ROOM"); T.contains(mon, "ok")
  T.contains(mon, "BANK 1 " .. DOT .. " West"); T.contains(mon, "BANK 1 " .. DOT .. " East")
  T.contains(mon, "BANK 2 " .. DOT .. " West"); T.contains(mon, "BANK 2 " .. DOT .. " East")
  -- 10 + 10 + 6 + 3 drives, 10 cells each
  T.contains(mon, "29 drives " .. DOT .. " 283 cells")
  T.contains(mon, "Bytes"); T.contains(mon, "Slots"); T.contains(mon, "283 of 1200 cells")
  -- rack names and priorities in board order, left to right
  local x1, y1 = mon:find("R1 0")
  local x2, y2 = mon:find("R2 0")
  local x3 = mon:find("R3 5")
  local x4 = mon:find("R4 10")
  T.truthy(x1 and x2 and x3 and x4, "rack names with priorities")
  T.eq(y1, 8, "rack row"); T.eq(x1, 1); T.eq(x2, 7); T.eq(x3, 13); T.eq(x4, 22)
  T.contains(mon, "R12", "unbuilt racks are named too")
  T.falsy(mon:line(8):find("R5 %d"), "an unbuilt rack has no priority")
  T.eq(mon.h, 67)
  for y = 1, 67 do T.truthy(#mon:line(y) <= 79, "row " .. y .. " wider than the screen") end
  T.absent(mon, "Screen error")
end)

T.test("server: cells are coloured by fill, empty slots and missing drives are dots", function()
  local w, srv, mon, me = boot()
  local P = function(name) return COLOURS[name] end
  -- R1 is the top-left rack. Its first drive in board order is the top row of the grid; the bottom row (y0) is built first.
  -- The mock fills drives bottom row first, so R1's first drive sits in the rack's bottom-left: drive row 5, col 1.
  local x0, y0 = 4, 9 + 4 * 6       -- (R1's first drive is the right-hand one: the west wall reads from high z to low z)
  local _, bg1 = mon:colourAt(x0, y0)             -- slot 1: 7800 items in a 1k cell = about 96%
  local _, bg2 = mon:colourAt(x0 + 1, y0)         -- slot 2: 6200 items = about 76%
  local _, bg3 = mon:colourAt(x0, y0 + 1)         -- slot 3: 500 items = small
  T.eq(bg1, 2 ^ 14, "over 90% is red")
  T.eq(bg2, 2 ^ 1, "70-90% is orange")
  T.eq(bg3, 2 ^ 5, "under 70% is lime")
  -- R3 is built to 6 drives: the top of its grid is empty (a dot on black); R4 has 3 drives
  local _, y_ = mon:find("R3 5")
  local top = mon:line(9):sub(13, 17)
  T.eq(top, DOT .. DOT .. " " .. DOT .. DOT, "R3's top drive row is not built")
  local fgc, bgc = mon:colourAt(13, 9)
  T.eq(bgc, 2 ^ 15, "no drive is on black")
end)

T.test("server: the tiers, byte totals and the biggest piles", function()
  local w, srv, mon = boot()
  T.contains(mon, "TIERS  items fill the top tier first")
  local _, ty = mon:find("TIERS")
  T.eq(ty, 40, "tiers start under the room")
  local row10, row5, row0 = mon:find("p10"), mon:find("p5 "), mon:find("p0 ")
  local _, y10 = mon:find("p10"); local _, y5 = mon:find("p5 "); local _, y0 = mon:find("p0 ")
  T.truthy(y10 < y5 and y5 < y0, "highest priority first")
  T.contains(mon, "R1+R2"); T.contains(mon, "1k/4k"); T.contains(mon, "256M"); T.contains(mon, "64k")
  T.contains(mon, "free")
  T.contains(mon, "BIGGEST PILES")
  T.contains(mon, "Netherrack"); T.contains(mon, "Raw Copper"); T.contains(mon, "Cobblestone")
  T.contains(mon, "Energy"); T.contains(mon, "AE/t"); T.contains(mon, "kinds")
  T.contains(mon, "no drive"); T.contains(mon, "no size")      -- the legend
  local cy = select(2, mon:find("Fill "))
  T.eq(cy, 67, "legend on the last row")
end)

T.test("server: storage's defrag news: running, idle, never run, not heard", function()
  local w, srv, mon, me, st = boot()
  T.contains(mon, "storage not heard")
  say(st, { type = "defrag", running = true, item = "Cobbled Deepslate", done = 13, left = 28, freedBytes = 41984 })
  w:run(6)
  T.contains(mon, "running"); T.contains(mon, "Cobbled Deepslate"); T.contains(mon, "item 14 of 41")
  T.contains(mon, "p0 freed 41k bytes")
  say(st, { type = "defrag", running = false, done = 41, left = 0, freedBytes = 2 * 1048576 })
  w:run(6)
  T.contains(mon, "idle"); T.contains(mon, "last run: 41 items, freed 2M bytes"); T.absent(mon, "storage not heard")
  say(st, { type = "defrag", running = false, done = 0, left = 0, freedBytes = 0 })
  w:run(6)
  T.contains(mon, "never run")
  st:run("stand")   -- (already running) nothing
  st:writeFile("defrag.msg", "")
  w:run(40)
  T.contains(mon, "storage not heard", "no news for 30 s")
end)

T.test("server: the bridge going offline keeps the last data, dimmed, and comes back", function()
  local w, srv, mon, me = boot()
  T.contains(mon, "R3 5"); T.contains(mon, " ok")
  local _, bg = mon:colourAt(4, 33)
  T.eq(bg, 2 ^ 14, "red cell while online")
  me:setOnline(false)
  w:run(12)
  T.contains(mon, "ME offline"); T.contains(mon, "R3 5"); T.contains(mon, "283 cells")
  _, bg = mon:colourAt(4, 33)
  T.eq(bg, 2 ^ 8, "dimmed (light grey) while offline")
  T.running(srv)
  me:setOnline(true)
  w:run(12)
  T.contains(mon, " ok"); T.absent(mon, "ME offline")
  _, bg = mon:colourAt(4, 33)
  T.eq(bg, 2 ^ 14)
end)

T.test("server: the screen follows the bridge within a few seconds", function()
  local w, srv, mon, me = boot()
  T.contains(mon, "283 cells")
  me:addDrive{ x = 4, y = 69, z = 3, priority = 10 }          -- R4's 4th drive slot... a new drive appears
  w:run(7)
  T.contains(mon, "30 drives")
end)

T.test("server: a drive that fits no wall is counted, not dropped", function()
  local w, srv, mon = boot({ odd = true })
  T.contains(mon, "1 drive outside the room")
  T.contains(mon, "30 drives")
end)

T.test("server: FLIP_1=1 mirrors the first wall", function()
  local w, srv, mon = boot({ env = "FLIP_1=1\n" })
  T.contains(mon, "R1 5"); T.contains(mon, "R3 0")
  T.absent(mon, "R1 0")
end)

-- Tanis's real room (#131): 4 walls (x = 0, 4, 8, 12) x 3 racks of 2x5 drives; racks stand `gap` blocks apart. Each rack
-- on a wall gets a priority of its place along the coordinate (offset 0 = 1, next = 2, ...) so the board shows where it landed.
local function gapRoom(gap, skipRack, extraEnv)
  local w = cc.world()
  local net = w:net()
  local me = net:add("me_bridge_0", w:meBridge{})
  for wall = 0, 3 do
    for rk = 0, 2 do
      if not (skipRack and wall == skipRack.wall and rk == skipRack.rack) then
        me:addRackAt{ axis = "x", at = wall * 4, col0 = rk * (2 + gap), priority = rk + 1, cell = "1k" }
      end
    end
  end
  local srv = w:computer{ id = 2, label = "Server" }
  srv:attach("back", cc.wired(net))
  srv:attach("top", cc.wireless{ ender = true })
  local mon = srv:monitor("right", 79, 67)
  srv:installRole("server")
  if extraEnv then srv:writeFile("server.env", extraEnv) end
  srv:run("server")
  w:run(8)
  return w, srv, mon
end

T.test("server: racks one block apart: all 120 drives land in their racks, none outside (#131)", function()
  local w, srv, mon = gapRoom(1, nil, "FLIP_2=1\n")
  T.running(srv)
  T.contains(mon, "120 drives"); T.contains(mon, "1200 cells")
  T.absent(mon, "outside the room")
  -- the west walls read high to low z (3 2 1), the east walls low to high (1 2 3); FLIP_2 turns wall 2 round
  for _, n in ipairs({ "R1 3", "R2 2", "R3 1", "R4 3", "R5 2", "R6 1", "R7 3", "R10 1", "R12 3" }) do T.contains(mon, n) end
  for _, n in ipairs({ "R1 1", "R4 1" }) do T.absent(mon, n) end
  T.falsy(mon:line(9):find(DOT .. DOT .. " " .. DOT .. DOT), "every rack is fully built")
end)

T.test("server: racks with no gap and with a 2-block gap still fit", function()
  local w, srv, mon = gapRoom(0)
  T.contains(mon, "120 drives"); T.absent(mon, "outside the room")
  T.contains(mon, "R1 3"); T.contains(mon, "R3 1")
  local w2, srv2, mon2 = gapRoom(2)
  T.contains(mon2, "120 drives"); T.absent(mon2, "outside the room")
  T.contains(mon2, "R1 3"); T.contains(mon2, "R3 1")
end)

T.test("server: an unbuilt rack between built ones keeps the others in place (#131)", function()
  local w, srv, mon = gapRoom(1, { wall = 0, rack = 1 })
  T.contains(mon, "110 drives"); T.absent(mon, "outside the room")
  T.contains(mon, "R1 3"); T.contains(mon, "R3 1")
  T.falsy(mon:line(8):find("R2 %d"), "the middle rack is not built")
end)

T.test("server: RACK_GAP overrides, for a wall with one built rack", function()
  -- only the far rack of a wall exists: no gap can be seen, so the offset says it is rack 1 unless RACK_GAP is set
  local function one(env)
    local w = cc.world()
    local net = w:net()
    local me = net:add("me_bridge_0", w:meBridge{})
    me:addRackAt{ axis = "x", at = 0, col0 = 0, priority = 7, cell = "1k" }
    local srv = w:computer{ id = 2, label = "Server" }
    srv:attach("back", cc.wired(net))
    local mon = srv:monitor("right", 79, 67)
    srv:installRole("server")
    if env then srv:writeFile("server.env", env) end
    srv:run("server"); w:run(8)
    return mon
  end
  local m = one("RACK_GAP=1\n")
  T.contains(m, "10 drives"); T.absent(m, "outside the room"); T.contains(m, "R1 7")
end)

T.test("server: an empty room draws every rack as no drive", function()
  local w = cc.world()
  local net = w:net()
  net:add("me_bridge_0", w:meBridge{})
  local srv = w:computer{ id = 2, label = "Server" }
  srv:attach("back", cc.wired(net))
  local mon = srv:monitor("right", 79, 67)
  srv:installRole("server")
  srv:run("server")
  w:run(8)
  T.running(srv)
  T.contains(mon, "0 drives"); T.contains(mon, "0 of 1200 cells"); T.contains(mon, "R12")
  T.absent(mon, "Screen error")
end)

T.test("server: the room size comes from server.env", function()
  local w, srv, mon = boot({ env = "BANKS=1\nWALLS_PER_BANK=2\n" })
  T.contains(mon, "BANK 1 " .. DOT .. " East"); T.absent(mon, "BANK 2")
  T.contains(mon, "R6"); T.absent(mon, "R7")
end)

T.test("server: smaller monitors stack the banks, then fall back to rack lines", function()
  local w, srv, mon = boot({ mw = 60, mh = 80 })
  T.contains(mon, "BANK 2 " .. DOT .. " West")
  local _, y1 = mon:find("BANK 1"); local _, y2 = mon:find("BANK 2")
  T.truthy(y2 > y1 + 30, "bank 2 sits under bank 1")
  for y = 1, 80 do T.truthy(#mon:line(y) <= 60, "row " .. y .. " wider than the screen") end
  local w2, srv2, mon2 = boot({ mw = 30, mh = 30 })
  T.contains(mon2, "R1 "); T.contains(mon2, "R4 "); T.contains(mon2, "racks not built yet")
  for y = 1, 30 do T.truthy(#mon2:line(y) <= 30, "row " .. y .. " wider than the screen") end
  T.absent(mon2, "Screen error")
end)

for _, s in ipairs({ { 51, 19 }, { 39, 13 }, { 26, 20 } }) do
  T.test(("server: the computer's own screen at %dx%d"):format(s[1], s[2]), function()
    local w, srv = boot({ monitor = false, w = s[1], h = s[2] })
    T.running(srv)
    T.contains(srv.screen, "SERVER ROOM")
    T.absent(srv.screen, "Screen error")
    for y = 1, s[2] do T.truthy(#srv.screen:line(y) <= s[1], "row " .. y .. " wider than the screen") end
  end)
end

T.test("server: it never moves items", function()
  local w, srv, mon, me = boot()
  local before = me:total("minecraft:cobblestone")
  w:run(30)
  T.eq(me:total("minecraft:cobblestone"), before)
end)
