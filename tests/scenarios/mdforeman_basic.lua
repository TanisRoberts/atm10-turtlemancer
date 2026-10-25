-- MD Foreman: the Mining Dimension's barrels (Factory in/out, Overflow, buckets never go home) and real
-- one-dock Canaries getting lava buckets from it, down to a dock at Y 253 mining at the bottom of the world.
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

local function sized(n) return cc.Inv.new{ size = n, types = { "minecraft:barrel", "inventory" } } end

-- The MD Foreman with a dock, output, overflow, stock, factory in and factory out on its cable, a monitor and
-- (o.canary) a pre-numbered Canary-01 entry for computer 7. o.before(b) fills barrels first; o.out, o.dock:
-- barrels to use; o.w: the world.
local function base(o)
  o = o or {}
  local w = o.w or cc.world()
  local net = w:net()
  local b = {
    dock = net:add("minecraft:barrel_0", o.dock or MS.barrel()),
    out = net:add("minecraft:barrel_1", o.out or MS.barrel()),
    over = net:add("minecraft:barrel_2", MS.barrel()),
    stock = net:add("minecraft:barrel_3", MS.barrel()),
    fin = net:add("minecraft:barrel_4", MS.barrel()),
    fout = net:add("minecraft:barrel_5", MS.barrel()),
  }
  local c = w:computer{ id = 3, label = "MD Foreman" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("mdforeman")
  local cfg = { docks = { "minecraft:barrel_0" }, outputs = { "minecraft:barrel_1" }, overflows = { "minecraft:barrel_2" },
    stocks = { "minecraft:barrel_3" }, factoryIns = { "minecraft:barrel_4" }, factoryOuts = { "minecraft:barrel_5" },
    imported = true }
  if o.canary then
    cfg.nextNum = 2
    cfg.canaries = { [7] = { num = 1, label = "Canary-01", want = "dock", minY = o.minY, maxY = o.maxY, pMin = o.minY, pMax = o.maxY,
      r1 = 0, r2 = 0, pR1 = 0, pR2 = 0, seq = 1 } }
  end
  c:writeTable("mdforeman.cfg", cfg)
  if o.before then o.before(b) end
  c:run("mdforeman")
  w:run(3)
  return { w = w, c = c, mon = mon, b = b }
end

local function tap(e, text, last)
  local a, z, step = 3, e.mon.h, 1
  if last then a, z, step = e.mon.h, 3, -1 end
  for row = a, z, step do
    local x = e.mon:line(row):find(text, 1, true)
    if x then e.mon:touch(x, row); e.w:run(1); return end
  end
  error("no " .. text .. " on the monitor:\n" .. e.mon:text(), 2)
end

T.test("md foreman: Factory out is emptied into Stock (past the keep count), so the factory never stalls", function()
  local e = base({ before = function(b) b.fout:give("minecraft:lava_bucket", 20) end })
  e.w:run(5)
  T.running(e.c)
  T.eq(e.b.stock:count("minecraft:lava_bucket"), 20)
  T.eq(e.b.fout:count("minecraft:lava_bucket"), 0)
  T.eq(e.b.out:count("minecraft:lava_bucket"), 0, "lava never goes home")
  T.contains(e.mon, "MD FOREMAN")
  T.contains(e.mon, "Stock 0 buckets, 20 lava. Factory 0 lava.")
end)

T.test("md foreman: with Stock full, a full Factory out says so", function()
  local e = base({ before = function(b)
    b.stock:give("minecraft:lava_bucket", 27)       -- Stock full of lava (one bucket a slot)
    b.fout:give("minecraft:lava_bucket", 27)
  end })
  e.w:run(5)
  T.eq(e.b.fout:count("minecraft:lava_bucket"), 27)
  T.contains(e.mon, "Factory out full: no room in Stock for more lava")
end)

T.test("md foreman: empty buckets from the docks and Stock go to Factory in, never home", function()
  local e = base({ before = function(b)
    b.dock:give("minecraft:bucket", 5)
    b.dock:give("minecraft:raw_iron", 30)
    b.stock:give("minecraft:bucket", 3)
  end })
  e.w:run(5)
  T.eq(e.b.fin:count("minecraft:bucket"), 8)
  T.eq(e.b.stock:count("minecraft:bucket"), 0)
  T.eq(e.b.out:count("minecraft:bucket"), 0)
  T.eq(e.b.out:count("minecraft:raw_iron"), 30, "the haul goes home")
end)

T.test("md foreman: lava from a dock beyond the keep count stays in the MD", function()
  local e = base({ before = function(b)
    b.stock:give("minecraft:lava_bucket", 16)
    b.dock:give("minecraft:lava_bucket", 3)
  end })
  e.w:run(5)
  T.eq(e.b.out:count("minecraft:lava_bucket"), 0)
  T.eq(e.b.stock:count("minecraft:lava_bucket"), 19)
  T.eq(e.b.dock:count("minecraft:lava_bucket"), 0)
end)

T.test("md foreman: a full Output spills into Overflow, which drains back first once there's room", function()
  local full = sized(1)
  full:give("minecraft:cobblestone", 64)
  local e = base({ out = full, before = function(b) b.dock:give("minecraft:diamond", 7) end })
  e.w:run(5)
  T.eq(e.b.over:count("minecraft:diamond"), 7, "into Overflow")
  T.eq(e.b.dock:count("minecraft:diamond"), 0, "the dock is free for the next haul")
  T.contains(e.mon, "OUTPUT FULL")
  T.contains(e.mon, "Output full: haul waits in Overflow (1/27 slots)")
  full:extract(1, 64)                      -- the hopper takes it home
  e.w:run(5)
  T.eq(full:count("minecraft:diamond"), 7, "drained back into the Output")
  T.eq(e.b.over:count("minecraft:diamond"), 0)
  T.absent(e.mon, "OUTPUT FULL")
end)

T.test("md foreman: the barrel jobs on /assign include the factory's two and Overflow", function()
  local e = base()
  e.c:type("/assign"); e.c:key(257)
  e.w:run(1)
  T.contains(e.c.screen, "MD BARRELS")
  T.contains(e.c.screen, "FACT IN")
  T.contains(e.c.screen, "FACT OUT")
  T.contains(e.c.screen, "OVERFLOW")
end)

T.test("md foreman: the Rules page has the dock top-up and no junk list", function()
  local e = base()
  tap(e, "Rules")
  T.contains(e.mon, "dock tops up to 75%")
  T.contains(e.mon, "KEEP IN THE MINING DIMENSION")
  T.contains(e.mon, "junk.txt on each Canary")
  tap(e, "+")
  T.eq(e.c:readTable("mdforeman.cfg").fullAt, 80)
  T.absent(e.mon, "+ Junk")
end)

-- A real Canary at 0,64,0 whose dock barrel (east) is the MD Foreman's Dock. Stone below; o.lava in Stock.
local function withCanary(o)
  o = o or {}
  local w = cc.world()
  w.gpsOn = true
  w:fill(-20, 40, -20, 20, 63, 20, "minecraft:stone")
  local dock = MS.barrel()
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  local e = base({ w = w, dock = dock, canary = true, minY = 60, maxY = 63,
    before = function(b) b.stock:give("minecraft:lava_bucket", o.lava or 5) end })
  local t = MS.turtle(w, { fuel = 400 })
  MS.setup(w, t)
  w:run(10)
  e.t = t
  return e
end

T.test("md foreman: a one-dock Canary gets lava buckets for START, and the empties go to Factory in", function()
  local e = withCanary()
  T.eq(e.t.label, "Canary-01")
  tap(e, "Canary-01")
  tap(e, "START", true)
  T.waitFor(e.w, function() return e.b.fin:count("minecraft:bucket") == 5 end, 120, "the empties never reached Factory in")
  T.eq(e.b.stock:count("minecraft:lava_bucket"), 0, "all 5 lava buckets went to his dock")
  T.truthy(e.t.body.fuel >= 5000, "drank them: " .. tostring(e.t.body.fuel))
  T.waitFor(e.w, function() return e.b.out:count("minecraft:raw_iron") + e.b.out:count("minecraft:cobblestone") > 0 end,
    1200, "no haul came home")
end)

T.test("md foreman: a Canary ignores an order that isn't for a Canary", function()
  local w = cc.world()
  w.gpsOn = true
  w:fill(-5, 50, -5, 5, 63, 5, "minecraft:stone")
  local dock = MS.barrel()
  dock:give("minecraft:coal", 64)
  w:setBlock(1, 64, 0, "minecraft:barrel", dock)
  local t = MS.turtle(w)
  local f = MS.foreman(w, { kind = "starling" })
  MS.setup(w, t)
  w:run(10)
  MS.order(f)
  w:run(20)
  T.eq(f.env._G.lastStatus.state, "docked")
  T.eq(t.body.y, 64)
end)

-- Dock at Y 253 (the MD's surface), stone all the way down to the bedrock floor at Y -64; ores at the bottom.
-- o.lava: lava buckets in Stock. Returns e (with e.t, e.heard), after START.
local function deep(o)
  local w = cc.world()
  w.gpsOn = true
  w:fill(0, -64, 0, 15, -64, 15, "minecraft:bedrock")
  w:fill(0, -63, 0, 15, 252, 15, "minecraft:stone")
  if o.ores then
    w:setBlock(4, -62, 4, "minecraft:deepslate_diamond_ore")
    w:setBlock(9, -63, 11, "minecraft:deepslate_iron_ore")
  end
  local dock = MS.barrel()
  w:setBlock(9, 253, 8, "minecraft:barrel", dock)
  local e = base({ w = w, dock = dock, canary = true, minY = -63, maxY = o.maxY or -61,
    before = function(b) b.stock:give("minecraft:lava_bucket", o.lava) end })
  local t = w:turtle{ id = 7, x = 8, y = 253, z = 8, facing = 0, fuel = 200,
                      left = "minecraft:diamond_pickaxe", right = "computercraft:wireless_modem_advanced" }
  t:installRole("canary")
  e.heard = MS.listen(w)
  MS.setup(w, t)
  w:run(15)
  tap(e, "Canary-01")
  tap(e, "START", true)
  e.t = t
  return e
end

T.test("md foreman: one lava bucket isn't enough for the bottom: he turns back in time and waits for fuel", function()
  local e = deep({ lava = 1, maxY = -55 })     -- three passes of a whole chunk: more than 1,000 fuel
  local low, wentDown, sawLow = math.huge, false, false
  T.waitFor(e.w, function()
    low = math.min(low, e.t.body.fuel)
    if e.t.body.y < 0 then wentDown = true end
    local s = e.heard(7)
    if s and s.msg and s.msg:find("Low on fuel") then sawLow = true end
    return wentDown and e.t.body.y == 253 and s and s.msg and s.msg:find("Need %d+ fuel") ~= nil
  end, 3000, "never came back to wait for fuel")
  T.truthy(sawLow, "turned back for fuel")
  T.truthy(low > 0, "ran dry")
  T.running(e.t)
end)

T.test("md foreman: a dock at Y 253 mining at Y -63..-61 never runs out of fuel", function()
  local e = deep({ lava = 20, ores = true })
  local low = math.huge
  T.waitFor(e.w, function()
    low = math.min(low, e.t.body.fuel)
    local s = e.heard(7)
    return s and s.state == "docked" and s.msg and s.msg:find("Range finished") ~= nil
  end, 4000, "never finished the bottom layer")
  T.running(e.t)
  T.truthy(low > 0, "ran dry")
  T.eq(e.t.body.y, 253); T.eq(e.t.body.x, 8); T.eq(e.t.body.z, 8)
  e.w:run(6)                                     -- the MD Foreman empties his dock
  T.eq(e.b.out:count("minecraft:diamond"), 1)
  T.eq(e.b.out:count("minecraft:raw_iron"), 1)
end)

T.test("md foreman: barrels on two separate cables can't swap items, and the screen says why (not 'Output full')", function()
  local w = cc.world()
  local a, b = w:net("a"), w:net("b")
  local dock = a:add("minecraft:barrel_0", MS.barrel())
  b:add("minecraft:barrel_1", MS.barrel())                      -- the Output, on a second cable
  dock:give("minecraft:diamond", 5)
  local c = w:computer{ id = 3, label = "MD Foreman" }
  c:attach("back", cc.wired(a)); c:attach("left", cc.wired(b))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("mdforeman")
  c:writeTable("mdforeman.cfg", { docks = { "minecraft:barrel_0" }, outputs = { "minecraft:barrel_1" }, imported = true })
  c:run("mdforeman")
  w:run(5)
  T.running(c)
  T.contains(mon, "barrel_0 can't reach barrel_1: are both on my cable?")
  T.contains(mon, "0 canaries  CAN'T MOVE")
  T.absent(mon, "OUTPUT FULL")
end)

T.test("md foreman: /assign answers at once even with full docks and barrels it can't reach; errors go to fm_errors.txt", function()
  local w = cc.world()
  local a, b = w:net("a"), w:net("b")
  local docks = {}
  for i = 0, 3 do
    local d = a:add("minecraft:barrel_" .. i, MS.barrel())
    for k = 1, 27 do d:give("minecraft:raw_iron", 64) end
    docks[#docks + 1] = "minecraft:barrel_" .. i
  end
  b:add("minecraft:barrel_9", MS.barrel())                      -- the Output, out of reach
  local c = w:computer{ id = 3, label = "MD Foreman" }
  c:attach("back", cc.wired(a)); c:attach("left", cc.wired(b))
  c:attach("top", cc.wireless{ ender = true })
  c:installRole("mdforeman")
  c:writeTable("mdforeman.cfg", { docks = docks, outputs = { "minecraft:barrel_9" }, imported = true })
  c:run("mdforeman")
  w:run(20)
  T.contains(c:readFile("fm_errors.txt") or "", "minecraft:barrel_0 -> minecraft:barrel_9")
  c:type("/assign"); c:key(257)
  w:run(2)
  T.contains(c.screen, "MD BARRELS")
  local x, y = c.screen:find("barrel_1")
  c:click(x, y); w:run(1)
  local function button(text)   -- the buttons are on the second-last row
    local row = c.screen.h - 1
    return c.screen:line(row):find(text, 1, true), row
  end
  x, y = button("Delete"); c:click(x, y); w:run(1)
  T.contains(c.screen, "Sure? Delete")
  x, y = button("Sure? Delete"); c:click(x, y); w:run(2)
  T.contains(c.screen, "has no job now")
  x, y = c.screen:find("barrel_2"); c:click(x, y); w:run(1)
  x, y = button("Cancel"); c:click(x, y); w:run(2)
  T.contains(c.screen, "MD BARRELS", "back on the list, not stuck")
  T.running(c)
end)

T.test("md foreman: an empty bucket that comes out of the factory goes back into Factory in", function()
  local e = base({ before = function(b)
    b.fout:give("minecraft:lava_bucket", 3)
    b.fout:give("minecraft:bucket", 5)
  end })
  e.w:run(5)
  T.eq(e.b.fout:count("minecraft:bucket"), 0)
  T.eq(e.b.fin:count("minecraft:bucket"), 5)
  T.eq(e.b.stock:count("minecraft:lava_bucket"), 3)
end)
