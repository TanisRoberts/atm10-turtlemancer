-- MD Foreman: a miner's last status survives a Foreman reboot (issue #95), saved throttled, not on every status.
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

local function setup()
  local w = cc.world()
  local c = w:computer{ id = 3, label = "MD Foreman" }
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("mdforeman")
  c:writeTable("mdforeman.cfg", { nextNum = 2, imported = true,
    canaries = { [7] = { num = 1, label = "Canary-01", want = "dock", minY = 0, maxY = 250, pMin = 0, pMax = 250,
      r1 = 0, r2 = 0, pR1 = 0, pR2 = 0, seq = 1 } } })
  c:run("mdforeman")
  local m = MS.standIn(w, { id = 7, num = 1, label = "Canary-01", protocol = "tanis-miner", bird = "Canary", kind = "canary",
    dim = "allthemodium:mining" })
  m.G.y, m.G.state, m.G.msg = 253, "mining", "Chunk 3"
  w:run(5)
  return w, c, mon, m
end

T.test("md foreman: a silent miner's last position is still there after the Foreman reboots", function()
  local w, c, mon, m = setup()
  T.contains(mon, "Canary-01")
  m:_stop()                          -- Canary-11 goes quiet
  w:run(40)                          -- past the save throttle
  local saved = c:readTable("mdforeman.cfg").canaries[7].last
  T.eq(saved.s.pos.y, 253)
  T.eq(saved.s.state, "mining")
  c:_stop(); c:run("mdforeman")      -- the Foreman reboots; the miner stays silent
  w:run(70)
  T.contains(mon, "not heard for")
  T.contains(mon, "1, 253, 2")
  T.contains(mon, "Canary-01")
end)

T.test("md foreman: statuses are saved at most every 30 s, not each time", function()
  local w, c, _, m = setup()
  w:run(35)                          -- the first save
  local f1 = c:readTable("mdforeman.cfg").canaries[7].last
  m.G.y = 200; w:run(10)       -- moved, but inside the throttle
  local f2 = c:readTable("mdforeman.cfg").canaries[7].last
  T.eq(f2.s.pos.y, f1.s.pos.y, "no write inside 30 s")
  w:run(25)
  T.eq(c:readTable("mdforeman.cfg").canaries[7].last.s.pos.y, 200, "written after the throttle")
end)
