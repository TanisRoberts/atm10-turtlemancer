-- The Cartographer: holds Seagull's map, draws the floor and its own screen, floppy spill-over, orders, the art
-- controller without a World map, and the mainframe row. A stand-in Seagull (tests/demo/seagull_stub.lua) serves chunks.
local cc  = require("sim.cc")
local T   = require("sim.test")
local COL = require("sim.env").colors

local function seagull(w, regions, o)
  o = o or {}
  local s = w:computer{ id = 20, label = "Seagull-01" }
  s:attach("top", cc.wireless{ ender = true })
  s:install("tests/demo/seagull_stub.lua")
  s:install("shared/mapchunk.lua")
  s:writeTable("stub.cfg", { regions = regions, doneRegion = o.done,
    status = { type = "status", role = "cartographer", label = "Seagull-01", state = o.state or "mapping", msg = "Region",
               fuel = 3000, fuelLimit = 20000, home = { x = 100, y = 64, z = 100 }, pos = { x = 120, y = 90, z = 130 },
               scan_region = o.scan, scan_ago = o.ago, scan_secs = o.secs } })
  s:run("seagull_stub")
  return s
end

-- opts.floor = { w, h } (default 164 x 81), opts.mounts = { disk = 125000 }, opts.hdd = bytes of room on the computer's disk
local function room(opts)
  opts = opts or {}
  local w = cc.world()
  local c = w:computer{ id = 10, label = "Cartographer", w = 51, h = 19 }
  if opts.mounts then
    c.mounts = opts.mounts
    for name in pairs(opts.mounts) do c.dirs[name] = true end
  end
  c:attach("top", cc.wireless{ ender = true })
  local floor = opts.floor ~= false and c:monitor("right", opts.floor and opts.floor[1] or 164, opts.floor and opts.floor[2] or 81) or nil
  c:installRole("cartographer")
  c:writeFile("startup.lua", 'shell.run("cartographer")')
  if opts.hdd then       -- the computer's disk: what the programs take, plus this much
    local used = 0
    for _, d in pairs(c.files) do used = used + #d end
    c.hddCapacity = used + opts.hdd
  end
  return w, c, floor
end
local function dbg(c) return c.env._G.CARTO_DEBUG end
local function bgCount(scr, colour)
  local n = 0
  for y = 1, scr.h do for x = 1, scr.w do local _, b = scr:colourAt(x, y); if b == colour then n = n + 1 end end end
  return n
end

T.test("cartographer: takes a whole region from Seagull, saves it, says region_ok, draws floor and screen", function()
  local w, c, floor = room()
  c:run("cartographer")
  local s = seagull(w, { { 0, 0, "island" } }, { done = { 0, 0 }, scan = { 1, 0 }, ago = 100, secs = 600 })
  T.waitFor(w, function() return dbg(c) and dbg(c).store:count() == 256 end, 120, "the whole region never arrived")
  T.running(c)
  w:run(10)
  T.eq(dbg(c).store:regionCount(), 1)
  T.truthy(c.files["regions/0_0.map"], "the region is saved as regions/0_0.map")
  T.truthy(#s.env._G.oks >= 1, "Seagull was told region_ok")
  T.eq(s.env._G.oks[1].region[1], 0); T.eq(s.env._G.oks[1].region[2], 0)
  -- the computer's own screen
  local scr = c.screen
  T.contains(scr:text(), "CARTOGRAPHER"); T.contains(scr:text(), "1 region")
  T.contains(scr:text(), "SEAGULL"); T.contains(scr:text(), "Seagull-01"); T.contains(scr:text(), "mapping")
  T.contains(scr:text(), "NEXT"); T.contains(scr:text(), "STORAGE"); T.contains(scr:text(), "regions")
  T.contains(scr:text(), "MAP"); T.contains(scr:text(), "DOCK"); T.contains(scr:text(), "FIT")
  -- the floor: deep water and land are drawn, never-seen is black, nothing but the zoom bar on the right
  T.truthy(bgCount(floor, COL.blue) > 100, "ocean is solid blue")
  T.truthy(bgCount(floor, COL.black) > 100, "ground nobody has seen is black")
  T.truthy(floor:find("+") and floor:find("-") and floor:find("FILL"), "the zoom bar: + - FILL")
  T.truthy(floor:find("16") and floor:find("8"), "one tick per zoom level")
end)

T.test("cartographer: floor taps move the view, zoom bar zooms, FILL makes it a static table", function()
  local w, c, floor = room()
  c:run("cartographer")
  seagull(w, { { 0, 0, "island" } })
  T.waitFor(w, function() return dbg(c) and dbg(c).store:count() == 256 end, 120)
  w:run(5)
  local st = dbg(c).st
  local z0 = st.view.s
  T.truthy(st.view.fit, "starts fitting the explored map")
  -- zoom in with the + button (top of the bar)
  local bx, by = floor:find("+")
  floor:touch(bx, by); w:run(2)
  T.truthy(st.view.s < z0 or z0 == 1, "+ zooms in")
  T.eq(st.view.fit, false)
  -- tap the 16 tick
  local tx, ty = floor:find("16")
  floor:touch(tx, ty); w:run(2)
  T.eq(st.view.s, 16)
  -- a tap on the map centres it there and nothing else
  local before = st.view.cx
  floor:touch(20, 40); w:run(2)
  T.truthy(st.view.cx ~= before, "tap on the map centres the view")
  T.eq(#(dbg(c).sh.act and {} or {}), 0)
  -- FILL
  local fx, fy = floor:find("FILL")
  floor:touch(fx, fy); w:run(3)
  T.eq(st.fill, true)
  T.contains(c:readFile("cartographer.env"), "FLOOR_FILL=true")
  T.absent(floor:text(), "16", "the zoom bar is hidden")
  T.contains(floor:text(), "FILL")
  local px = st.view.cx
  floor:touch(20, 40); w:run(2)
  T.eq(st.view.cx, px, "taps on the map do nothing in Fill")
  local _, b = floor:colourAt(floor.w - 3, floor.h - 3)
  T.eq(b, COL.white, "FILL is lit")
  -- off again, and it survives a reboot
  fx, fy = floor:find("FILL")
  floor:touch(fx, fy); w:run(3)
  T.eq(st.fill, false)
  T.contains(c:readFile("cartographer.env"), "FLOOR_FILL=false")
  T.truthy(floor:find("16"), "the zoom bar is back")
end)

T.test("cartographer: MAP, DOCK, tap-twice next region and typed commands reach Seagull", function()
  local w, c = room({ floor = false })
  c:run("cartographer")
  local s = seagull(w, { { 0, 0, "island" } })
  T.waitFor(w, function() return dbg(c) and dbg(c).store:count() == 256 end, 120)
  w:run(5)
  local scr = c.screen
  local x, y = scr:find("MAP")
  c:click(x + 1, y); w:run(5)
  T.eq(s.env._G.cmds[#s.env._G.cmds].want, "map")
  x, y = scr:find("DOCK")
  c:click(x + 1, y); w:run(5)
  T.eq(s.env._G.cmds[#s.env._G.cmds].want, "dock")
  -- tap an unexplored region on the small map twice (north-east corner of the thumbnail is far from 0,0)
  local tn = #s.env._G.cmds
  c:click(2, 4); w:run(1)
  T.contains(scr:text(), "tap again to map it next")
  c:click(2, 4); w:run(5)
  T.eq(#s.env._G.cmds > tn, true, "the second tap queued the region")
  local cmd = s.env._G.cmds[#s.env._G.cmds]
  T.truthy(type(cmd.next) == "table" and cmd.next[1] and cmd.next[2], "cmd carries next = {rx, rz}")
  T.eq(dbg(c).st.nextRegion.rx, cmd.next[1])
  -- typed
  c:type("/next 3,-2"); c:key(257); w:run(5)
  cmd = s.env._G.cmds[#s.env._G.cmds]
  T.eq(cmd.next[1], 3); T.eq(cmd.next[2], -2)
  c:type("/next clear"); c:key(257); w:run(5)
  cmd = s.env._G.cmds[#s.env._G.cmds]
  T.eq(cmd.next, false, "next = false clears it")
  c:type("/help"); c:key(257); w:run(1)
  T.contains(scr:text(), "/map")
  c:type("/goto 100 200"); c:key(257); w:run(1)
  T.eq(dbg(c).st.view.cx, 100); T.eq(dbg(c).st.view.cz, 200)
  T.eq(dbg(c).st.view.fit, false)
  c:type("/fit"); c:key(257); w:run(1)
  T.eq(dbg(c).st.view.fit, true)
  c:type("/storage"); c:key(257); w:run(1)
  T.contains(scr:text(), "room for")
end)

T.test("cartographer: scanning region shows ~% (or just 'scanning' when Seagull sends no times)", function()
  local w, c, floor = room()
  c:run("cartographer")
  seagull(w, { { 0, 0, "island" } }, { scan = { 1, 0 }, ago = 300, secs = 600 })
  T.waitFor(w, function() return dbg(c) and dbg(c).st.scan end, 60, "no scan estimate")
  w:run(4)
  T.truthy(dbg(c).st.scan.pct and dbg(c).st.scan.pct >= 1, "an estimate from start time and secs")
  T.contains(c.screen:text(), "~")
  T.truthy(bgCount(floor, COL.black) > 0)
  local w2, c2 = room({ floor = false })
  c2:run("cartographer")
  seagull(w2, { { 0, 0, "ocean" } }, { scan = { 1, 0 } })
  T.waitFor(w2, function() return dbg(c2) and dbg(c2).st.scan end, 60)
  T.eq(dbg(c2).st.scan.pct, nil)
  w2:run(3)
  T.contains(c2.screen:text(), "scanning")
end)

T.test("cartographer: spills over to floppies when its own disk fills, and reads every mount as one map", function()
  local w, c = room({ floor = false, mounts = { disk = 125000, disk2 = 125000 }, hdd = 150000 })
  c:run("cartographer")
  seagull(w, { { 0, 0, "noisy" }, { 1, 0, "noisy" }, { 2, 0, "noisy" } })
  T.waitFor(w, function() return dbg(c) and dbg(c).store:count() == 768 end, 600, "the map never arrived")
  w:run(60)
  T.running(c)
  local files = {}
  for _, p in ipairs({ "regions/0_0.map", "regions/1_0.map", "regions/2_0.map", "disk/regions/0_0.map", "disk/regions/1_0.map",
                       "disk/regions/2_0.map", "disk2/regions/0_0.map", "disk2/regions/1_0.map", "disk2/regions/2_0.map" }) do
    if c.files[p] then files[#files + 1] = p end
  end
  T.eq(#files, 3, "each region lives on exactly one mount: " .. table.concat(files, ", "))
  local onDisk = 0
  for _, p in ipairs(files) do if p:find("^disk") then onDisk = onDisk + 1 end end
  T.truthy(onDisk >= 1, "something spilled to a floppy")
  T.truthy(c.screen:text():find("disk") or c.screen:text():find("Disk"), "the storage gauge shows disks")
  -- reboot without Seagull: every mount is read as one map
  c:reboot(); w:run(30)
  T.running(c)
  T.eq(dbg(c).store:regionCount(), 3, "three regions after a reboot from the files alone")
  T.eq(dbg(c).store:count(), 768)
  T.contains(c.screen:text(), "3 regions")
end)

T.test("cartographer: pulling a floppy keeps the map in memory and saves its regions elsewhere", function()
  local w, c = room({ floor = false, mounts = { disk = 125000 }, hdd = 120000 })
  c:run("cartographer")
  seagull(w, { { 0, 0, "noisy" }, { 1, 0, "noisy" } })
  T.waitFor(w, function() return dbg(c) and dbg(c).store:count() == 512 end, 600)
  w:run(60)
  T.truthy(c.files["disk/regions/0_0.map"] or c.files["disk/regions/1_0.map"], "one region went to the floppy")
  T.eq(dbg(c).store:regionCount(), 2)
end)

T.test("cartographer: refuses to ack a region it cannot save", function()
  local w, c = room({ floor = false, hdd = 30000 })     -- a region is about 47 KB: nothing fits
  c:run("cartographer")
  local s = seagull(w, { { 0, 0, "noisy" } }, { done = { 0, 0 } })
  T.waitFor(w, function() return dbg(c) and dbg(c).store:count() == 256 end, 300)
  w:run(30)
  T.running(c)
  T.eq(#s.env._G.oks, 0, "no region_ok when the region is not safe on a disk")
end)

T.test("art controller: no World map screen any more; the others still work", function()
  local w = cc.world()
  local c = w:computer{ id = 3, label = "Art" }
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 164, 81)
  c:installRole("art")
  c:writeFile("art.env", "DEFAULT_VIEW=world\n")      -- an old setting pointing at the gone screen
  c:run("art"); w:run(5)
  T.running(c)
  T.contains(c.screen:text(), "1 Turtles 2 Plasma 3 Rings 4 Aurora")
  T.absent(c.screen:text(), "World")
  T.contains(c.screen:text(), "Showing: turtles")
  -- open the menu (burger bottom-right): Turtle map and the art are there, World map is not
  mon:touch(mon.w - 2, mon.h - 3); w:run(2)
  T.contains(mon:text(), "Turtle map"); T.contains(mon:text(), "Art: Plasma"); T.absent(mon:text(), "World map")
  c:type("2"); w:run(3)
  T.contains(c.screen:text(), "Showing: plasma")
  c:type("5"); w:run(1)
  T.running(c)
end)

T.test("mainframe board: one Cartographer row replaces Seagull's own row", function()
  local w = cc.world()
  local mf = w:computer{ id = 1, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  local mon = mf:monitor("bottom", 90, 20)
  mf:installRole("mainframe")
  mf:writeFile("launch.lua", [[
    local function sandbox(target)
      local e = { require = require }
      e.peripheral = setmetatable({ find = function(kind, ...)
        if kind == "monitor" then return target end
        return peripheral.find(kind, ...)
      end }, { __index = peripheral })
      return e
    end
    parallel.waitForAll(
      function() os.run({ require = require }, "base_link.lua") end,
      function() os.run({ require = require }, "board.lua") end,
      function() require("wall").run(peripheral.wrap("bottom"), "bottom") end)
  ]])
  mf:run("launch")
  local cg = w:computer{ id = 10, label = "Cartographer" }
  cg:attach("top", cc.wireless{ ender = true })
  cg:writeFile("send.lua", [[
    rednet.open("top")
    while true do
      rednet.broadcast({ type = "cartographer", label = "Cartographer", regions = 7, chunks = 1800,
        seagull = { label = "Seagull-01", state = "mapping", fuel = 5000, wp = 11, wps = 20 } }, "tanis-base")
      rednet.broadcast({ type = "carto", label = "Seagull-01", state = "mapping", chunks = 1800, fuel = 5000 }, "tanis-base")
      sleep(2)
    end]])
  cg:run("send"); w:run(8)
  T.running(mf)
  T.contains(mon:text(), "Cartographer"); T.contains(mon:text(), "7 regions")
  T.absent(mon:text(), "Seagull-01", "Seagull's own row is not shown next to it")
end)
