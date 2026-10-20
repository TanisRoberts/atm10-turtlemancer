-- Nether Foreman: Firecrest numbers, orders from its screens, the dock barrels (keep or send home, dock_req),
-- OUTPUT FULL, typed commands. A stand-in Firecrest talks on tanis-nether (tests/sim/miners.lua).
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

-- The Nether Foreman with a dock, an output, a stock and an input barrel on its cable, a monitor (57x24) and
-- a stand-in Firecrest. o.out: the output barrel (to make a full one). Returns a table of everything.
local function base(o)
  o = o or {}
  local w = cc.world()
  local net = w:net()
  local b = {
    dock = net:add("minecraft:barrel_0", MS.barrel()),
    out = net:add("minecraft:barrel_1", o.out or MS.barrel()),
    stock = net:add("minecraft:barrel_2", MS.barrel()),
    input = net:add("minecraft:barrel_3", MS.barrel()),
  }
  local c = w:computer{ id = 2, label = "Nether Foreman" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("nether")
  c:writeTable("nether.cfg", { docks = { "minecraft:barrel_0" }, outputs = { "minecraft:barrel_1" },
    stocks = { "minecraft:barrel_2" }, inputs = { "minecraft:barrel_3" } })
  if o.before then o.before(b) end
  c:run("nether")
  local f = o.noFirecrest and nil or MS.standIn(w, { id = 9 })
  w:run(5)
  return { w = w, c = c, mon = mon, f = f, b = b }
end

-- Tap `text` on the monitor (below the header and notice rows; the lowest one when `last`)
local function tap(e, text, last)
  local x, y
  local a, b, step = 3, e.mon.h, 1
  if last then a, b, step = e.mon.h, 3, -1 end
  for row = a, b, step do
    x = e.mon:line(row):find(text, 1, true)
    if x then y = row; break end
  end
  T.truthy(x, "no " .. text .. " on the monitor:\n" .. e.mon:text())
  e.mon:touch(x, y)
  e.w:run(1)
end

T.test("nether: a Firecrest registers, gets Firecrest-01 and shows on the overview", function()
  local e = base()
  T.running(e.c)
  T.eq(e.f.label, "Firecrest-01")
  T.contains(e.mon, "NETHER FOREMAN")
  T.contains(e.mon, "1 firecrest")
  T.contains(e.mon, "Firecrest-01")
  T.contains(e.mon, "DOCKED")
  T.contains(e.mon, "Y 40")
  T.contains(e.c.screen, "Firecrest-01")
  local cfg = e.c:readTable("nether.cfg")
  T.eq(cfg.firecrests[9].num, 1)
  T.eq(cfg.nextNum, 2)
end)

T.test("nether: the dock's haul goes home, buckets and fuel stay in Stock up to their keep counts", function()
  local e = base({ before = function(b)
    b.dock:give("minecraft:diamond", 5)
    b.dock:give("minecraft:bucket", 6)
    b.dock:give("minecraft:coal", 70)
    b.stock:give("minecraft:lava_bucket", 20)
    b.input:give("minecraft:quartz", 10)
  end })
  e.w:run(10)
  local out, stock = e.b.out, e.b.stock
  T.eq(e.b.dock:count("minecraft:diamond"), 0)
  T.eq(out:count("minecraft:diamond"), 5)
  T.eq(out:count("minecraft:quartz"), 10, "the input is sorted like a haul")
  T.eq(stock:count("minecraft:bucket"), 4); T.eq(out:count("minecraft:bucket"), 2)
  T.eq(stock:count("minecraft:coal"), 64); T.eq(out:count("minecraft:coal"), 6)
  T.eq(stock:count("minecraft:lava_bucket"), 16, "Stock above its keep count goes home")
  T.eq(out:count("minecraft:lava_bucket"), 4)
  T.contains(e.mon, "Stock 4 buckets, 16 lava")
  T.contains(e.mon, "Sent home 27")
end)

T.test("nether: a dock_req gets lava and a bucket from Stock, and the dock is left alone until dock_done", function()
  local e = base({ before = function(b)
    b.stock:give("minecraft:lava_bucket", 5)
    b.stock:give("minecraft:bucket", 2)
  end })
  e.f.env._G.ask = { seq = 77, bucket = true, fuel = 2500 }
  e.w:run(5)
  local r = e.f.env._G.replies[1]
  T.truthy(r, "no dock_ready")
  T.eq(r.seq, 77)
  T.eq(r.got["minecraft:lava_bucket"], 3); T.eq(r.got["minecraft:bucket"], 1)
  T.eq(#r.missing, 0)
  T.eq(e.b.dock:count("minecraft:lava_bucket"), 3)
  T.eq(e.b.dock:count("minecraft:bucket"), 1)
  e.w:run(10)
  T.eq(e.b.dock:count("minecraft:lava_bucket"), 3, "held while he takes his supplies")
  e.f.env._G.done = true
  e.w:run(6)
  T.eq(e.b.dock:count("minecraft:lava_bucket"), 0, "emptied after dock_done")
  T.eq(e.b.stock:count("minecraft:lava_bucket"), 5)
end)

T.test("nether: a dock_req with nothing in Stock says so", function()
  local e = base()
  e.f.env._G.ask = { seq = 5, bucket = true, fuel = 1000 }
  e.w:run(5)
  local r = e.f.env._G.replies[1]
  T.truthy(r, "no dock_ready")
  T.eq(r.note, "Stock has no bucket or fuel")
end)

T.test("nether: OUTPUT FULL when the output can't take the haul", function()
  local full = cc.Inv.new{ size = 1, types = { "minecraft:barrel", "inventory" } }
  full:give("minecraft:cobblestone", 64)
  local e = base({ out = full, before = function(b) b.dock:give("minecraft:diamond", 3) end })
  e.w:run(5)
  T.contains(e.mon, "OUTPUT FULL")
  T.contains(e.mon, "Output full: is the hopper into the ender chest flowing")
  T.eq(e.b.dock:count("minecraft:diamond"), 3, "left in the dock")
end)

T.test("nether: START and STOP on a Firecrest's page send the order", function()
  local e = base()
  tap(e, "Firecrest-01")
  T.contains(e.mon, "< Firecrest-01")
  T.contains(e.mon, "Debris")
  T.contains(e.mon, "computer #9")
  tap(e, "START", true)
  e.w:run(3)
  local m = e.f.env._G.lastCmd
  T.eq(m.want, "run"); T.eq(m.minY, 12); T.eq(m.maxY, 17); T.eq(m.c1, 0); T.eq(m.c2, 1)
  T.eq(m.hungryAt, 25); T.eq(m.fullAt, 75)
  T.truthy(type(m.junk) == "table" and #m.junk > 5, "the junk list goes with it")
  T.contains(e.mon, "Firecrest-01: START sent.")
  tap(e, "STOP + DOCK")
  e.w:run(3)
  T.eq(e.f.env._G.lastCmd.want, "dock")
  T.eq(e.c:readTable("nether.cfg").firecrests[9].want, "dock")
end)

T.test("nether: picking a preset and nudging Min Y, then START sends that range", function()
  local e = base()
  tap(e, "Firecrest-01")
  tap(e, "Above lava")
  local x, y = e.mon:find("Min Y")
  T.truthy(x)
  local line = e.mon:line(y)
  local px = line:find("+", 1, true)
  e.mon:touch(px, y); e.w:run(1)
  tap(e, "START", true)
  e.w:run(3)
  local m = e.f.env._G.lastCmd
  T.eq(m.minY, 34); T.eq(m.maxY, 44)
end)

T.test("nether: /keep, /junk and /reboot typed on the computer", function()
  local e = base()
  e.c:type("/keep lava_bucket 8"); e.c:key(257)
  e.w:run(1)
  T.eq(e.c:readTable("nether.cfg").keep["minecraft:lava_bucket"], 8)
  T.contains(e.c.screen, "Keeping 8 Lava bucket in the Nether.")
  T.contains(e.c.screen, "RULES")
  e.c:type("/junk tuff"); e.c:key(257)
  e.w:run(4)
  local junk = e.f.env._G.lastCmd.junk
  T.eq(junk[#junk], "tuff")
  e.c:type("/reboot 1"); e.c:key(257)
  e.w:run(3)
  T.truthy(e.f.env._G.lastCmd.reboot, "reboot token sent")
  T.contains(e.c.screen, "Firecrest-01: reboot sent.")
end)

T.test("nether: the Rules page shows the lava marks and what's kept", function()
  local e = base()
  tap(e, "Rules")
  T.contains(e.mon, "< RULES")
  T.contains(e.mon, "drink under 25%")
  T.contains(e.mon, "until 75%")
  T.contains(e.mon, "KEEP IN THE NETHER")
  T.contains(e.mon, "Lava bucket")
  T.contains(e.mon, "FIRECREST THROWS AWAY")
  tap(e, "+")
  T.eq(e.c:readTable("nether.cfg").hungryAt, 30)
end)

T.test("nether: retire takes two taps and the number is never handed out again", function()
  local e = base()
  tap(e, "Firecrest-01")
  tap(e, "Retire")
  tap(e, "Tap to retire")
  T.contains(e.mon, "Firecrest-01 retired. Number 1 won't be used again.")
  local cfg = e.c:readTable("nether.cfg")
  T.eq(cfg.firecrests[9].retired, true)
  T.eq(cfg.retiredNums[1], "Firecrest-01")
  e.w:run(4)
  T.eq(e.f.env._G.lastCmd.retired, true)
  T.eq(e.f.env._G.lastCmd.want, "dock")
  -- a new Firecrest gets number 2
  local g = MS.standIn(e.w, { id = 10 })
  e.w:run(5)
  T.eq(g.label, "Firecrest-02")
end)

T.test("nether: presets page and editor", function()
  local e = base()
  tap(e, "Presets")
  T.contains(e.mon, "< PRESETS")
  T.contains(e.mon, "Debris deep")
  T.contains(e.mon, "High quartz")
  e.c:type("/new Deep"); e.c:key(257)
  e.w:run(1)
  T.contains(e.c.screen, "< NEW PRESET")
  e.c:key(257)                        -- Enter: save
  e.w:run(1)
  local p = e.c:readTable("nether.cfg").presets
  T.eq(p[#p].name, "Deep")
end)

T.test("nether: the preset editor and a Firecrest's page say how many chunks the rings cover", function()
  local e = base()
  e.c:type("/new Wide"); e.c:key(257); e.w:run(1)
  for _ = 1, 4 do local x, y = e.c.screen:find("From ring"); local l = e.c.screen:line(y); e.c:click(l:find("+", 1, true), y); e.w:run(0.2) end
  for _ = 1, 7 do local x, y = e.c.screen:find("To ring"); local l = e.c.screen:line(y); e.c:click(l:find("+", 1, true), y); e.w:run(0.2) end
  e.w:run(1)
  T.contains(e.c.screen, "240 chunks: 17x17, skipping the middle 7x7")
  tap(e, "Firecrest-01")
  T.contains(e.mon, "9 chunks, 3x3")
end)
