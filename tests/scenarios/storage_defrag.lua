-- /defrag in ME mode (#126): piles move out of small cells into the top-priority rack by round trips through the buffer.
local cc = require("sim.cc")
local T = require("sim.test")

local BARREL = { "minecraft:barrel", "inventory" }
local B = function(i) return "minecraft:barrel_" .. i end
local CHEST = 3                       -- the Defrag buffer

-- barrels: 0 input, 1 output, 2 dock, 3 defrag buffer. Racks: two small ones at priority 0, one big at 10.
local function base(opts)
  opts = opts or {}
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 3 do inv[i] = net:add(B(i), cc.Inv.new{ size = i == CHEST and (opts.bufferSize or 4) or 27, types = BARREL }) end
  local me = net:add("me_bridge_0", w:meBridge{ stale = opts.stale })
  local small, big
  if opts.room then
    -- a list of { priority, cell } (cell "infinity" = Infinity cells only, nil = empty drives); lowest tier is `small`
    for _, r in ipairs(opts.room) do
      local rack
      if r[2] == "infinity" then
        rack = { me:addDrive{ priority = r[1] } }
        me:addInfinity(rack[1], "minecraft:cobblestone")
      else rack = me:addRack{ n = 1, priority = r[1], cell = r[2] } end
      if r[1] == 0 then small = { rack, me:addRack{ n = 1, priority = 0, cell = "1k" } } end
    end
  else
    small = { me:addRack{ n = 1, priority = 0, cell = "1k" }, me:addRack{ n = 1, priority = 0, cell = "1k" } }
    big = me:addRack{ n = 1, priority = opts.samePrio and 0 or 10, cell = opts.bigCell or "256M" }
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  local mon = c:monitor("right", 57, 24)
  c:installRole("storage")
  local cfg = { inputs = { B(0) }, output = B(1), docks = { B(2) }, defragBuffer = (not opts.noBuffer) and B(CHEST) or nil }
  c:writeTable("storage.cfg", cfg)
  if opts.env then c:writeFile("storage.env", opts.env) end
  return w, c, inv, me, mon, small, big
end

-- the cells of a rack's first drive
local function cellsOf(rack) local out = {}; for i = 1, 10 do out[i] = rack[1].cells[i] end; return out end

-- fragment `n` of `item` over the first cells of both small racks
local function scatter(me, small, item, n)
  local a, b = cellsOf(small[1]), cellsOf(small[2])
  local h, q = math.floor(n / 2), math.floor(n / 4)
  me:fill(a[1], item, h); me:fill(b[1], item, q); me:fill(a[2], item, n - h - q)
end

local function open(w, c)
  c:run("storage"); w:run(10)
  c:type("/defrag"); c:key(257); w:run(2)
end
local function tap(c, w, text)
  local x, y = c.screen:find(text)
  assert(x, "no '" .. text .. "' on the screen:\n" .. c.screen:text())
  c:click(x + 1, y); w:run(1)
end
local function lowBytes(me)
  local u = 0
  for _, d in ipairs(me.drives) do
    if d.priority < 10 then for i = 1, d.slots do local cl = d.cells[i]; if cl then u = u + cl:usedBytes() end end end
  end
  return u
end
local function allIn(me, item, prio)
  for _, h in ipairs(me:where(item)) do
    local p = h.kind == "cell" and h.drive.priority or h.bus.prio
    if p ~= prio then return false end
  end
  return true
end

T.test("storage defrag: fragmented piles end up in the big cells, nothing lost, low cells emptied", function()
  local w, c, inv, me, mon, small, big = base()
  scatter(me, small, "minecraft:cobblestone", 1000)
  scatter(me, small, "minecraft:iron_ingot", 300)
  me:fill(cellsOf(small[1])[3], "minecraft:gold_ingot", 20)          -- under a stack: left alone
  local before = lowBytes(me)
  open(w, c)
  T.contains(c.screen, "DEFRAG")
  T.contains(c.screen, "P10")
  T.contains(c.screen, "P0")
  T.contains(c.screen, "Cobblestone")
  T.absent(c.screen, "Gold Ingot")
  tap(c, w, "Start")
  T.waitFor(w, function() return allIn(me, "minecraft:cobblestone", 10) and allIn(me, "minecraft:iron_ingot", 10) end, 300, "piles never moved")
  w:run(20)
  T.eq(me:total("minecraft:cobblestone"), 1000)
  T.eq(me:total("minecraft:iron_ingot"), 300)
  T.eq(me:total("minecraft:gold_ingot"), 20)
  T.eq(#me:where("minecraft:gold_ingot"), 1, "small pile untouched")
  assert(lowBytes(me) < before, "low tiers freed bytes")
  T.eq(#me:where("minecraft:cobblestone"), 1, "one pile in one cell")
  T.contains(c.screen, "Moved")
  T.contains(c.screen, "Finished")
  assert(inv[CHEST]:isEmpty(), "buffer empty")
end)

T.test("storage defrag: all drives at one priority warns and moves nothing", function()
  local w, c, inv, me, mon, small = base({ samePrio = true })
  scatter(me, small, "minecraft:cobblestone", 1000)
  open(w, c)
  T.contains(c.screen, "Nothing to defrag towards")
  local x, y = c.screen:find("Start")
  if x then c:click(x + 1, y); w:run(30) end
  T.eq(#me:where("minecraft:cobblestone"), 3, "still spread")
  assert(inv[CHEST]:isEmpty())
end)

T.test("storage defrag: no buffer assigned is said, and Start does nothing", function()
  local w, c, inv, me, mon, small = base({ noBuffer = true })
  scatter(me, small, "minecraft:cobblestone", 1000)
  open(w, c)
  T.contains(c.screen, "No Defrag buffer")
  local x, y = c.screen:find("Start")
  if x then c:click(x + 1, y); w:run(30) end
  T.eq(#me:where("minecraft:cobblestone"), 3)
end)

T.test("storage defrag: a void drawer is announced and only its overflow is lost", function()
  local w, c, inv, me, mon, small = base({ env = "DEFRAG_VOID=minecraft:deepslate=256\n" })
  local drawer = me:addBus{ priority = 9999, capacity = 256, void = true, item = "minecraft:deepslate" }
  me:fill(drawer, "minecraft:deepslate", 256)                         -- the drawer is already full
  scatter(me, small, "minecraft:deepslate", 1000)
  scatter(me, small, "minecraft:iron_ingot", 300)
  open(w, c)
  T.contains(c.screen, "drawer keeps 256, rest voided")
  tap(c, w, "Start")
  T.waitFor(w, function() return c.screen:find("Finished") end, 300, "never finished")
  T.eq(me:total("minecraft:deepslate"), 256, "drawer keeps 256")
  T.eq(me:total("minecraft:iron_ingot"), 300, "everything else kept")
  assert(allIn(me, "minecraft:deepslate", 9999))
  assert(inv[CHEST]:isEmpty())
end)

T.test("storage defrag: an unlisted void is noticed and that item is left alone afterwards", function()
  local w, c, inv, me, mon, small = base()
  me:addBus{ priority = 9999, capacity = 100, void = true, item = "minecraft:cobblestone" }
  scatter(me, small, "minecraft:cobblestone", 1000)
  open(w, c)
  tap(c, w, "Start")
  T.waitFor(w, function() return c.screen:find("Finished") end, 300, "never finished")
  T.contains(c.screen, "voided")
  assert(me:total("minecraft:cobblestone") >= 100)
end)

T.test("storage defrag: stopping leaves the buffer empty, and a leftover buffer is emptied at boot", function()
  local w, c, inv, me, mon, small = base({ bufferSize = 1 })
  w.ticks = true
  inv[CHEST]:give("minecraft:diamond", 5)
  scatter(me, small, "minecraft:cobblestone", 2000)
  scatter(me, small, "minecraft:iron_ingot", 3000)
  c:run("storage"); w:run(10)
  T.eq(me:total("minecraft:diamond"), 5, "leftover buffer emptied into AE2")
  assert(inv[CHEST]:isEmpty())
  c:type("/defrag"); c:key(257); w:run(2)
  tap(c, w, "Start")
  w:run(8)
  T.contains(c.screen, "Stop")
  tap(c, w, "Stop")
  w:run(15)
  assert(inv[CHEST]:isEmpty(), "buffer empty after Stop")
  T.eq(me:total("minecraft:cobblestone"), 2000)
  T.eq(me:total("minecraft:iron_ingot"), 3000)
  T.contains(c.screen, "stopped")
end)

T.test("storage defrag: a dock is still refilled on time and progress is broadcast", function()
  local w, c, inv, me, mon, small, big = base({ bufferSize = 1 })
  w.ticks = true
  for i, item in ipairs({ "minecraft:cobblestone", "minecraft:dirt", "minecraft:sand", "minecraft:gravel", "minecraft:netherrack" }) do
    scatter(me, small, item, 2000)
  end
  me:fill(big[1].cells[1], "minecraft:lava_bucket", 10)
  local mf = w:computer{ id = 9, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  mf:writeFile("listen.lua", [[
    rednet.open("top")
    heard = {}
    local deadline = os.clock() + 120
    while os.clock() < deadline do
      local _, m = rednet.receive("tanis-base", 2)
      if type(m) == "table" and m.type == "defrag" then heard[#heard + 1] = m end
    end
  ]])
  mf:run("listen")
  open(w, c)
  tap(c, w, "Start")
  T.waitFor(w, function() return inv[2]:count("minecraft:lava_bucket") == 4 end, 30, "dock never got its lava while defragging")
  T.contains(c.screen, "Stop")        -- still running
  w:run(10)
  tap(c, w, "Stop")
  w:run(15)
  assert(inv[CHEST]:isEmpty(), "buffer empty")
  w:run(100)
  local h = mf.G.heard
  assert(h and #h >= 2, "defrag progress heard")
  T.eq(h[1].type, "defrag")
  local sawRunning, last = false, h[#h]
  for _, m in ipairs(h) do if m.running then sawRunning = true end end
  assert(sawRunning, "a running report")
  T.eq(last.running, false)
  assert(last.moved > 0, "moved reported")
  assert(last.toMove >= last.moved, "moved never passes the total")
  T.eq(last.freedTypes, nil)
end)

T.test("storage defrag: DEFRAG_SKIP keeps an item where it is", function()
  local w, c, inv, me, mon, small = base({ env = "DEFRAG_SKIP=minecraft:cobblestone\n" })
  scatter(me, small, "minecraft:cobblestone", 1000)
  scatter(me, small, "minecraft:iron_ingot", 300)
  open(w, c)
  T.absent(c.screen, "Cobblestone")
  tap(c, w, "Start")
  T.waitFor(w, function() return c.screen:find("Finished") end, 300, "never finished")
  T.eq(#me:where("minecraft:cobblestone"), 3, "skipped item untouched")
  T.eq(#me:where("minecraft:iron_ingot"), 1)
end)

T.test("storage defrag: infinity cells are skipped and listed; stale cell bytes do not end an item early", function()
  local w, c, inv, me, mon, small, big = base({ stale = true })
  me:save()                                                           -- bytes as of an empty grid
  me:addInfinity(me:addDrive{ priority = 10 }, "minecraft:cobblestone")
  scatter(me, small, "minecraft:cobblestone", 1000)                   -- real copies in small cells too
  scatter(me, small, "minecraft:iron_ingot", 3000)
  scatter(me, small, "minecraft:copper_ingot", 2000)
  -- bytes stay stale for the whole run (nobody calls me:save)
  open(w, c)
  T.contains(c.screen, "1 items from infinity cells: skipped")
  T.contains(c.screen, "min")
  T.absent(c.screen, "Cobblestone")
  tap(c, w, "Start")
  T.waitFor(w, function() return c.screen:find("Finished") end, 600, "never finished")
  T.eq(me:total("minecraft:iron_ingot"), 3000)
  T.eq(me:total("minecraft:copper_ingot"), 2000)
  assert(allIn(me, "minecraft:iron_ingot", 10), "iron fully moved up")
  assert(allIn(me, "minecraft:copper_ingot", 10), "copper fully moved up")
  T.eq(#me:where("minecraft:iron_ingot"), 1)
  T.eq(me:total("minecraft:cobblestone") - 2147483647, 1000, "cobblestone untouched")
  T.contains(c.screen, "Moved")
  T.contains(c.screen, "5k of 5k")
  assert(inv[CHEST]:isEmpty(), "buffer empty")
end)

-- #137: tiers with no sized cells never count as the top tier
local function movesUp(w, c, me, small)
  scatter(me, small, "minecraft:iron_ingot", 3000)
  open(w, c)
  T.contains(c.screen, "no sized cells: ignored")
  tap(c, w, "Start")
  T.waitFor(w, function() return c.screen:find("Finished") end, 600, "never finished")
  T.contains(c.screen, "Finished")
  T.absent(c.screen, "nearly full")
  assert(allIn(me, "minecraft:iron_ingot", 10), "iron moved up to the sized top tier")
  T.eq(me:total("minecraft:iron_ingot"), 3000)
end

T.test("storage defrag: an Infinity-only drive at the highest priority is ignored, not 'full'", function()
  local w, c, inv, me, mon, small = base()
  me:addInfinity(me:addDrive{ priority = 20 }, "minecraft:cobblestone")
  movesUp(w, c, me, small)
end)

T.test("storage defrag: an empty drive at the highest priority is ignored", function()
  local w, c, inv, me, mon, small = base()
  me:addDrive{ priority = 20 }
  movesUp(w, c, me, small)
end)

T.test("storage defrag: only ignored tiers above one sized tier: Start is off", function()
  local w, c, inv, me, mon, small = base({ samePrio = true })
  me:addDrive{ priority = 20 }
  scatter(me, small, "minecraft:cobblestone", 1000)
  open(w, c)
  T.contains(c.screen, "Nothing to defrag towards")
  T.contains(c.screen, "no sized cells: ignored")
  local x, y = c.screen:find("Start")
  if x then c:click(x + 1, y); w:run(30) end
  T.eq(#me:where("minecraft:cobblestone"), 3, "still spread")
end)

T.test("storage defrag: all upper tiers full stops with the numbers before moving anything", function()
  local w, c, inv, me, mon, small, big = base({ bigCell = "1k" })
  for _, cl in ipairs(cellsOf(big)) do me:fill(cl, "minecraft:dirt", cl.maxBytes * 8) end
  scatter(me, small, "minecraft:iron_ingot", 300)
  open(w, c)
  tap(c, w, "Start")
  T.waitFor(w, function() return c.screen:find("Finished") end, 300, "never finished")
  T.contains(c.screen, "upper tiers nearly full")
  T.contains(c.screen, "p10:")
  T.eq(#me:where("minecraft:iron_ingot"), 3, "nothing moved")
  assert(inv[CHEST]:isEmpty())
end)

-- Tanis's room (#137): 5000 Infinity only, 4000 empty drives, then 3000 (64k), 2000 (16k), 1000 (4k), 0 (1k)
local ROOM = { { 5000, "infinity" }, { 4000, nil }, { 3000, "64k" }, { 2000, "16k" }, { 1000, "4k" }, { 0, "1k" } }

T.test("storage defrag: Tanis's room: 5000 and 4000 ignored, 3000+2000+1000 take the piles", function()
  local w, c, inv, me, mon, small = base({ room = ROOM })
  scatter(me, small, "minecraft:iron_ingot", 3000)
  open(w, c)
  T.contains(c.screen, "p5000: 1 drive, no sized cells: ignored")
  T.contains(c.screen, "p4000: 1 drive, no sized cells: ignored")
  T.contains(c.screen, "p4000 has drives but no cells")
  tap(c, w, "Start")
  T.waitFor(w, function() return c.screen:find("Finished") end, 600, "never finished")
  T.absent(c.screen, "nearly full")
  T.eq(me:total("minecraft:iron_ingot"), 3000)
  for _, h in ipairs(me:where("minecraft:iron_ingot")) do assert(h.drive.priority >= 1000, "iron left in the 1k tier") end
end)

T.test("storage defrag: Tanis's room with 3000+2000+1000 nearly full stops before moving", function()
  local w, c, inv, me, mon, small = base({ room = ROOM })
  for _, d in ipairs(me.drives) do
    if d.priority >= 1000 and d.priority <= 3000 then
      for _, cl in pairs(d.cells) do if cl.maxBytes then me:fill(cl, "minecraft:dirt", cl.maxBytes * 8) end end
    end
  end
  scatter(me, small, "minecraft:iron_ingot", 300)
  open(w, c)
  tap(c, w, "Start")
  T.waitFor(w, function() return c.screen:find("Finished") end, 300, "never finished")
  T.contains(c.screen, "upper tiers nearly full")
  T.contains(c.screen, "(p3000: 0% free")
  T.contains(c.screen, "p1000:")
  T.eq(#me:where("minecraft:iron_ingot"), 3, "nothing moved")
end)
