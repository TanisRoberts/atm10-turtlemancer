-- Storage: the screens built from the UI kit (#21): the item list on the monitor and the computer, the search and
-- command bar, report pages, the lock screen and the /assign pages, at the four standard sizes.
local cc = require("sim.cc")
local T = require("sim.test")

local SIZES = { { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }
local B = function(i) return "minecraft:barrel_" .. i end

local function base(w_, h_, mon)
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 4 do
    inv[i] = net:add(B(i), cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  if w_ then c:resize(w_, h_) end
  local m = mon ~= false and c:monitor("right", w_ or 57, h_ or 24) or nil
  c:installRole("storage")
  c:writeTable("storage.cfg", { inputs = { B(0) }, output = B(1) })
  return w, c, inv, m
end

local function stock(inv)
  inv[0]:give("minecraft:iron_ingot", 64)
  inv[0]:give("minecraft:cobblestone", 94)
  inv[0]:give("minecraft:diamond", 3)
end

local function boot(w, c, inv)
  stock(inv)
  c:run("storage")
  T.waitFor(w, function() return inv[0]:isEmpty() end, 60, "input never emptied")
  w:run(8)
end

local function tap(w, c, text)
  local x, y = c.screen:find(text)
  assert(x, "no '" .. text .. "' on screen:\n" .. c.screen:text())
  c:click(x, y)
  w:run(1)
end

local function pill(w, c, label, row)             -- a button on the footer row (the last line of the screen)
  local lines = {}
  for line in (c.screen:text() .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  local y = row or #lines
  while y > 1 and not lines[y]:find(label, 1, true) do y = y - 1 end
  local x = lines[y]:find(label, 1, true)
  assert(x, "no '" .. label .. "' button:\n" .. c.screen:text())
  c:click(x + 1, y); w:run(1)
end

local function widest(screen)
  local n = 0
  for line in screen:text():gmatch("[^\n]+") do n = math.max(n, #line) end
  return n
end

for _, s in ipairs(SIZES) do
  local W, H = s[1], s[2]

  T.test(("storage screens %dx%d: the list on the monitor and the computer, tap sends, take amounts"):format(W, H), function()
    local w, c, inv, mon = base(W, H)
    boot(w, c, inv)
    for _, scr in ipairs({ mon, c.screen }) do
      T.contains(scr, "STORAGE"); T.contains(scr, "Sort")
      T.contains(scr, "Iron Ingot"); T.contains(scr, "Cobblestone"); T.contains(scr, "Diamond")
      T.truthy(widest(scr) <= W, "nothing wider than the screen")
    end
    if W >= 30 then T.contains(mon, "Stack") end
    T.contains(mon, "x16")
    -- the monitor: one stack by default, x1 on request
    mon:touch(3, select(2, mon:find("Iron Ingot"))); w:run(5)
    T.eq(inv[1]:count("minecraft:iron_ingot"), 64, "a tap sends one stack")
    local x, y = mon:find("x1 ")
    mon:touch(x + 1, y); w:run(1)
    mon:touch(3, select(2, mon:find("Cobblestone"))); w:run(1)
    T.contains(c.screen, "Sent 1 Cobblestone")
    w:run(3)
    T.eq(inv[1]:count("minecraft:cobblestone"), 1, "x1 sends one")
    T.running(c)
  end)

  T.test(("storage screens %dx%d: search filters, Enter sends the top item, / lists the commands, Tab completes"):format(W, H), function()
    local w, c, inv = base(W, H, false)
    boot(w, c, inv)
    c:type("dia"); w:run(1)
    T.contains(c.screen, "Diamond"); T.absent(c.screen, "Iron Ingot")
    c:key(257); w:run(5)                              -- Enter
    T.eq(inv[1]:count("minecraft:diamond"), 3)
    c:key(259); c:key(259); c:key(259); w:run(1)      -- Backspace x3
    c:type("/"); w:run(1)
    for _, cmd in ipairs({ "/assign", "/rescan" }) do T.contains(c.screen, cmd) end
    T.absent(c.screen, "Iron Ingot")
    c:type("res"); w:run(1)
    T.contains(c.screen, "/rescan"); T.absent(c.screen, "/assign")
    c:key(258); w:run(1)                              -- Tab completes
    T.contains(c.screen, "/rescan")
    c:key(257); w:run(3)                              -- Enter runs it
    T.contains(c.screen, "Rescanned")
    T.contains(c.screen, "Iron Ingot")
    c:type("/x16"); c:key(257); w:run(1)
    T.contains(c.screen, "Taking x16 per tap")
    T.running(c)
  end)

  T.test(("storage screens %dx%d: /assign list, edit page, Add and Find it"):format(W, H), function()
    local w, c, inv = base(W, H, false)
    boot(w, c, inv)
    c:type("/assign"); c:key(257); w:run(2)
    T.contains(c.screen, "barrel_0"); T.contains(c.screen, "Input")
    T.contains(c.screen, "barrel_1"); T.contains(c.screen, "Output")
    T.contains(c.screen, "+ Add")
    T.truthy(widest(c.screen) <= W)
    tap(w, c, "barrel_1")
    T.contains(c.screen, "Delete")
    T.contains(c.screen, "Save")
    T.truthy(widest(c.screen) <= W)
    c:click(2, H); w:run(1)                           -- the Back pill
    T.contains(c.screen, "+ Add")
    tap(w, c, "+ Add")
    T.contains(c.screen, "Other job")
    tap(w, c, "Other job")
    T.contains(c.screen, "barrel_3")
    T.absent(c.screen, "barrel_0 ", "an input already has a job")
    tap(w, c, "Find it")                              -- drop one item into the barrel you mean
    T.contains(c.screen, "left")
    inv[3]:give("minecraft:cobblestone", 1)
    w:run(4)
    T.contains(c.screen, "step 2 of 2")
    T.contains(c.screen, "Save")
    pill(w, c, "Save")
    w:run(2)
    T.contains(c.screen, "Saved")
    T.truthy(#c:readTable("storage.cfg").inputs + (c:readTable("storage.cfg").docks and 1 or 0) >= 1)
    T.running(c)
  end)
end

T.test("storage screens: a pick on the list assigns the job, Delete takes it away (tap twice)", function()
  local w, c, inv = base(nil, nil, false)
  boot(w, c, inv)
  c:type("/assign"); c:key(257); w:run(2)
  tap(w, c, "+ Add")
  tap(w, c, "Other job")
  tap(w, c, "barrel_4")
  T.contains(c.screen, "ADD")
  tap(w, c, "Ignore")
  tap(w, c, " Save ")
  T.contains(c.screen, "Saved: barrel_4 = Ignore")
  T.eq(c:readTable("storage.cfg").ignored[1], B(4))
  tap(w, c, "Ignore  ")
  local dx, dy = c.screen:find("Save   Delete")
  c:click(dx + 8, dy); w:run(1)
  T.contains(c.screen, "Sure?")
  c:click(dx + 8, dy); w:run(1)
  T.contains(c.screen, "has no job now")
  T.eq(#(c:readTable("storage.cfg").ignored or {}), 0)
  T.running(c)
end)

T.test("storage screens: /lock shows the padlock on the monitor and ignores taps, /unlock brings the list back", function()
  local w, c, inv, mon = base()
  boot(w, c, inv)
  c:type("/lock"); c:key(257); w:run(2)
  T.contains(mon, "LOCKED"); T.contains(mon, "Locked from the computer")
  T.absent(mon, "Iron Ingot")
  T.contains(c.screen, "MONITOR LOCKED"); T.contains(c.screen, "Iron Ingot")
  mon:touch(10, 5); w:run(2)
  T.eq(inv[1]:isEmpty(), true, "a locked monitor ignores taps")
  c:type("/unlock"); c:key(257); w:run(2)
  T.contains(mon, "Iron Ingot"); T.absent(mon, "LOCKED")
  -- the butler says Tanis is away
  c:queue("rednet_message", 9, { type = "presence", known = true, home = false, autoLock = true }, "tanis-base")
  w:run(3)
  T.contains(mon, "You are away from the island")
  T.running(c)
end)

T.test("storage screens: /fuelinfo and /drawers open report pages with Back", function()
  local w, c, inv = base(nil, nil, false)
  c:writeTable("storage.cfg", { inputs = { B(0) }, output = B(1), fuels = { B(4) } })
  inv[4]:give("minecraft:coal", 64)
  boot(w, c, inv)
  c:type("/fuelinfo"); c:key(257); w:run(3)
  T.contains(c.screen, "FUEL INFO")
  T.contains(c.screen, "BARREL_4"); T.contains(c.screen, "IN STORAGE")
  tap(w, c, "Back")
  T.contains(c.screen, "Iron Ingot")
  c:type("/drawers"); c:key(257); w:run(3)
  T.contains(c.screen, "DRAWERS"); T.contains(c.screen, "No drawers")
  tap(w, c, "Back")
  c:type("/tidy"); c:key(257); w:run(5)
  T.contains(c.screen, "TIDY")
  tap(w, c, "Back")
  T.contains(c.screen, "Iron Ingot")
  T.running(c)
end)

T.test("storage screens: old command names still work, /help lists the commands, unknown ones say so", function()
  local w, c, inv = base(nil, nil, false)
  boot(w, c, inv)
  c:type("/inputs"); c:key(257); w:run(2)
  T.contains(c.screen, "ASSIGNED STORAGE")           -- an old name for /assign
  tap(w, c, "Back")
  c:type("/help"); c:key(257); w:run(1)
  T.contains(c.screen, "/assign")
  c:type("/nonsense"); c:key(257); w:run(1)
  T.running(c)
end)

T.test("storage screens: a brand-new storage starts on the /assign page and the monitor keeps working meanwhile", function()
  local w, c, inv, mon = base()
  c:writeFile("storage.cfg", "{}")
  c:run("storage")
  w:run(5)
  T.contains(c.screen, "ASSIGNED STORAGE")
  T.contains(c.screen, "Nothing assigned yet")
  T.contains(mon, "STORAGE")
  inv[2]:give("minecraft:diamond", 5)
  w:run(40)                                           -- the list on the monitor updates while /assign is open
  T.contains(mon, "Diamond")
  T.running(c)
end)
