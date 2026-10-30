-- The Farmhand on the UI kit: overview tiles, one turtle's page (map, info, haul, settings, orders), at the four
-- screen sizes, with stand-in farm turtles (tests/demo/farm_stub.lua) on the radio.
local cc  = require("sim.cc")
local T   = require("sim.test")
local COL = require("sim.env").colors

local function partridge() return {
  type = "status", role = "farmer", label = "Partridge-01", state = "working", msg = "Planting row 3", fuel = 3200,
  fuelLimit = 20000, paused = false, nextRound = 420, rounds = 12, lastRound = { harvested = 40, planted = 38 },
  settings = { EVERY = 10, KEEP_SEEDS = 64, RESURVEY_EVERY = 5 }, mapStamp = 7, mp = { x = 5, z = 4, h = 1 },
  mapped = true, plots = 8, crop = "minecraft:wheat_seeds", seeds = 120, pos = { x = 100, y = 64, z = 200 },
  facing = "east", gps = true, anchored = true, home = { x = 96, y = 64, z = 196 },
  lastHaul = { { "minecraft:wheat", 40 } }, totals = { { "minecraft:wheat", 900 }, { "minecraft:carrot", 300 } } } end
local function woodpecker() return {
  type = "status", role = "lumberjack", label = "Woodpecker-01", state = "waiting", msg = "Out of saplings", fuel = 500,
  fuelLimit = 20000, paused = false, nextRound = 60, rounds = 3, lastRound = { chopped = 30, planted = 28, picked = 4 },
  settings = { EVERY = 30, KEEP_SAPLINGS = 16, RESURVEY_EVERY = 0, SWEEPS = 2 }, mapStamp = 3, mp = { x = 3, z = 3, h = 0 },
  mapped = true, cells = 500, spots = 64, saplings = 10, pos = { x = 10, y = 64, z = 20 }, facing = "north", gps = false,
  anchored = false } end
-- A farm map: border, two crops (a, b) or tree spots (+) and lanes, a dock barrel
local function farmMap(id, role, w, h)
  w, h = w or 16, h or 10
  local rows, st = {}, {}
  for r = 1, h do
    local row, s = {}, {}
    for c = 1, w do
      local ch = (r == 1 or r == h or c == 1 or c == w) and "#"
        or (role == "farmer" and (c < w / 2 and "a" or "b") or ((r + c) % 3 == 0 and "+" or "."))
      row[c] = ch; s[c] = (ch == "a" or ch == "b" or ch == "+") and ((r + c) % 2 == 0 and "h" or "g") or " "
    end
    rows[r] = table.concat(row); st[r] = table.concat(s)
  end
  rows[5] = rows[5]:sub(1, 3) .. "@" .. rows[5]:sub(5)
  return { type = "map", id = id, role = role, stamp = (role == "farmer" and 7 or 3), w = w, h = h, x0 = 0, z0 = 0,
           rows = rows, states = st, crops = { "minecraft:wheat_seeds", "minecraft:carrot" }, north = true,
           home = { x = 3, z = 4 } }
end

-- opts: lost = true makes the Woodpecker report it is lost; w, h (the Farmhand's own screen), monitor = {w, h}, colour, noModem, big = {w, h} for a large farm map,
--       only = 1 for just the Partridge
local function farm(opts)
  opts = opts or {}
  local w = cc.world()
  local fh = w:computer{ id = 1, label = "Farmhand", w = opts.w or 51, h = opts.h or 19, colour = opts.colour }
  if not opts.noModem then fh:attach("top", cc.wireless{ ender = true }) end
  local mon = opts.monitor and fh:monitor("right", opts.monitor[1], opts.monitor[2])
  fh:installRole("farmhand")
  fh:run("farmhand")
  local stubs = {}
  local wood = woodpecker()
  if opts.lost then wood.state, wood.msg = "lost", "Lost: no GPS" end
  local specs = { { 11, partridge(), "farmer" }, { 12, wood, "lumberjack" } }
  for i, spec in ipairs(specs) do
    if not (opts.only and i > opts.only) then
      local t = w:computer{ id = spec[1], label = "T" .. i }
      t:attach("top", cc.wireless{ ender = true })
      t:install("tests/demo/farm_stub.lua")
      local big = opts.big and spec[3] == "farmer" and opts.big
      t:writeTable("stub.cfg", { status = spec[2], map = farmMap(spec[1], spec[3], big and big[1], big and big[2]) })
      t:run("farm_stub")
      stubs[spec[1]] = t
    end
  end
  w:run(10)
  return w, fh, mon, stubs
end

local function inRow(scr, y, s) return scr:line(y):find(s, 1, true) end
local function fg(scr, x, y) local f = scr:colourAt(x, y); return f end
local function bg(scr, x, y) local _, b = scr:colourAt(x, y); return b end
local function tap(scr, w, x, y) scr:touch(x, y); w:run(1) end
local function tapQ(scr, w, x, y) scr:touch(x, y); w:run(0.2) end
local function click(w, c, x, y) c:click(x, y); w:run(1) end
local function cmds(stub) return stub.env._G.cmds or {} end
local function lastCmd(stub) local l = cmds(stub); return l[#l] end
-- first cell with this background colour
local function findBg(scr, colour, x1, x2)
  for y = 1, scr.h do for x = x1 or 1, x2 or scr.w do if bg(scr, x, y) == colour then return x, y end end end
end

---------------------------------------------------------------------------------------------------------
T.test("farmhand: overview on a 3x2 monitor: tiles, states, fuel, farm drawn small, buttons", function()
  local w, fh, mon = farm({ monitor = { 57, 24 } })
  T.running(fh)
  T.contains(mon:line(1), "FARMHAND"); T.contains(mon:line(1), "2 turtles"); T.contains(mon:line(1), "1 needs you")
  T.eq(fg(mon, mon.w - 3, 1), COL.orange, "the header says someone needs you, in orange")
  T.eq(mon.ch[2][1], "\140", "the rule")
  T.truthy(inRow(mon, 3, "Partridge-01") and inRow(mon, 3, "Woodpecker-01"), "two tiles side by side")
  T.eq(bg(mon, 2, 3), COL.lime, "Partridge is working: lime stripe"); T.eq(bg(mon, 30, 3), COL.orange, "Woodpecker is waiting")
  T.truthy(inRow(mon, 3, "working") and inRow(mon, 3, "waiting"))
  T.truthy(inRow(mon, 4, "Planting row 3") and inRow(mon, 4, "Out of saplings"))
  T.truthy(inRow(mon, 5, "16%")); T.eq(bg(mon, 9, 5), COL.orange, "16% fuel is orange")
  T.truthy(inRow(mon, 5, "3%")); T.eq(fg(mon, 37, 5), COL.red, "3% fuel is red")
  T.truthy(inRow(mon, 6, "Next in 7 min") and inRow(mon, 6, "Next in 1 min"))
  T.truthy(inRow(mon, 7, "seen "))
  T.truthy(findBg(mon, COL.brown), "the farm is drawn small on the tile (soil)")
  T.truthy(findBg(mon, COL.magenta), "with an arrow where the turtle is")
  local ax, ay = findBg(mon, COL.magenta, 1, 29)
  T.eq(mon.ch[ay][ax], "\16", "heading east")
  local wx, wy = findBg(mon, COL.magenta, 30)
  T.eq(mon.ch[wy][wx], "\30", "the Woodpecker faces north")
  T.truthy(inRow(mon, 22, "Last: harvested 40") and inRow(mon, 22, "Last: chopped 30"), "last round on the bottom row")
  local rx = inRow(mon, 23, " Rounds all ")
  T.truthy(rx and inRow(mon, 23, " Pause all ") and inRow(mon, 23, " Reboot all "), "buttons for every turtle")
  T.eq(bg(mon, rx, 23), COL.yellow, "Rounds all is the primary button")
  T.eq(mon.ch[24][1], " ", "no pager with one page")
end)

for _, s in ipairs({ { 51, 19 }, { 39, 13 }, { 26, 20 } }) do
  local W, H = s[1], s[2]
  T.test(("farmhand: overview on the computer's own %dx%d screen"):format(W, H), function()
    local w, fh = farm({ w = W, h = H })
    T.running(fh)
    local scr = fh.screen
    T.contains(scr:line(1), "FARMHAND")
    T.contains(scr:text(), "Partridge-01"); T.contains(scr:text(), "Woodpecker-01")
    T.contains(scr:text(), "working"); T.contains(scr:text(), "waiting")
    T.truthy(findBg(scr, COL.lime) and findBg(scr, COL.orange), "state stripes")
    T.contains(scr:line(H - 2), W > 30 and "Rounds all" or "Rounds")
    -- tap the first tile: its page opens, Back returns
    click(w, fh, 6, 4)
    T.contains(scr:line(1), "PARTRIDGE-01")
    T.truthy(inRow(scr, H, " < "), "footer with Back")
    click(w, fh, 2, H)
    T.contains(scr:line(1), "FARMHAND"); T.contains(scr:text(), "Woodpecker-01")
  end)
end

T.test("farmhand: overview with no turtles says how to get one", function()
  local w, fh = farm({ only = 0 })
  T.contains(fh.screen:text(), "No farm turtles heard yet.")
  T.contains(fh.screen:line(1), "0 turtles")
end)

---------------------------------------------------------------------------------------------------------
T.test("farmhand: orders to every turtle at once", function()
  local w, fh, mon, stubs = farm({ monitor = { 57, 24 } })
  local rx = inRow(mon, 23, " Rounds all ")
  tap(mon, w, rx + 2, 23)
  T.contains(mon:line(2), "off on its rounds")
  w:run(8)
  for id, t in pairs(stubs) do T.eq(cmds(t)[1] and cmds(t)[1].want, "rounds", "turtle " .. id .. " got ROUNDS") end
  tap(mon, w, inRow(mon, 23, " Pause all ") + 2, 23)
  w:run(8)
  for id, t in pairs(stubs) do T.eq(lastCmd(t).want, "stop", "turtle " .. id .. " got STOP") end
  T.contains(mon:text(), "paused", "the tiles say paused once the turtles confirm")
  tap(mon, w, inRow(mon, 23, " Reboot all ") + 2, 23)
  for id, t in pairs(stubs) do w:runUntil(function() return lastCmd(t).reboot end, 8) end
  for id, t in pairs(stubs) do T.truthy(lastCmd(t).reboot, "turtle " .. id .. " got the reboot") end
  T.truthy(w:runUntil(function() return mon:text():find("is back up", 1, true) end, 10), "the Farmhand notices them coming back")
end)

---------------------------------------------------------------------------------------------------------
T.test("farmhand: one turtle's page: map, state, order buttons, tabs", function()
  local w, fh, mon, stubs = farm({ monitor = { 57, 24 } })
  tap(mon, w, 10, 6)                                    -- Partridge's tile
  T.contains(mon:line(1), "PARTRIDGE-01"); T.contains(mon:line(1), "north is up"); T.contains(mon:line(1), "working")
  local ft = mon:line(24)
  T.truthy(ft:find(" Map ", 1, true) and ft:find(" Info ", 1, true) and ft:find(" Haul ", 1, true)
    and ft:find(" Settings ", 1, true), "tabs")
  T.eq(bg(mon, inRow(mon, 24, " Map "), 24), COL.yellow, "Map is the active tab")
  T.contains(mon:text(), "Planting row 3"); T.contains(mon:text(), "Seeds"); T.contains(mon:text(), "120")
  T.truthy(inRow(mon, 6, "16%") or inRow(mon, 7, "16%") or inRow(mon, 5, "16%"), "fuel bar on the side")
  -- the map: soil cells, the arrow on magenta, and the key
  T.truthy(findBg(mon, COL.brown)); local ax, ay = findBg(mon, COL.magenta)
  T.truthy(ax, "the turtle's arrow"); T.eq(mon.ch[ay][ax], "\16")
  T.contains(mon:text(), "Wheat 47"); T.contains(mon:text(), "dock"); T.contains(mon:text(), "here")
  -- no pan buttons: the whole 16x10 farm fits
  T.absent(mon:text(), "Follow")
  -- tap a block: what is there, with world coordinates (the map is pinned to north)
  tap(mon, w, ax - 2, ay)
  T.contains(mon:line(2), "Wheat"); T.contains(mon:line(2), "99, 200")
  -- orders from the side buttons
  local bx = inRow(mon, 12, " Rounds now ") or inRow(mon, 11, " Rounds now ") or inRow(mon, 10, " Rounds now ")
  local function pressButton(label)
    for y = 6, 22 do
      local x = mon:line(y):find(" " .. label .. " ", 1, true)
      if x and x > 30 then tap(mon, w, x + 2, y); return true end
    end
  end
  T.truthy(pressButton("Rounds now")); w:run(6)
  T.eq(lastCmd(stubs[11]).want, "rounds"); T.eq(cmds(stubs[12])[1], nil, "only this turtle")
  T.truthy(pressButton("Pause")); w:run(6)
  T.eq(lastCmd(stubs[11]).want, "stop")
  T.contains(mon:text(), "Go", "Pause becomes Go once it is paused")
  T.truthy(pressButton("Go")); w:run(6)
  T.eq(lastCmd(stubs[11]).want, "go")
  T.truthy(pressButton("Re-map")); w:run(6)
  T.eq(lastCmd(stubs[11]).want, "survey")
  T.absent(mon:text(), " Found ", "Found only appears when it is lost")
  T.truthy(pressButton("Reboot")); w:run(2)
  T.truthy(lastCmd(stubs[11]).reboot, "reboot order")
  T.truthy(w:runUntil(function() return mon:text():find("is back up", 1, true) end, 10), "and it is noticed coming back")
  -- Back to the overview
  tap(mon, w, 2, 24)
  T.contains(mon:line(1), "FARMHAND")
end)

T.test("farmhand: info and haul tabs", function()
  local w, fh, mon = farm({ monitor = { 57, 24 } })
  tap(mon, w, 10, 6)
  tap(mon, w, inRow(mon, 24, " Info ") + 1, 24)
  T.eq(bg(mon, inRow(mon, 24, " Info "), 24), COL.yellow)
  for _, want in ipairs({ "Seen", "Fuel", "3,200 / 20,000", "Farm", "8 plots, Wheat", "Seeds", "Last", "harvested 40, planted 38",
                          "Rounds done", "100, 64, 200", "east", "96, 64, 196", "pinned: never lost", "#11" }) do
    T.contains(mon:text(), want)
  end
  T.absent(mon:text(), "Forget", "a turtle that is talking can't be forgotten")
  tap(mon, w, inRow(mon, 24, " Haul ") + 1, 24)
  T.contains(mon:text(), "LAST HAUL"); T.contains(mon:text(), "Wheat"); T.contains(mon:text(), "BROUGHT IN SO FAR")
  T.contains(mon:text(), "900"); T.contains(mon:text(), "Carrot")
end)

T.test("farmhand: settings are steppers, sent to the turtle, gold until it confirms", function()
  local w, fh, mon, stubs = farm({ monitor = { 57, 24 } })
  tap(mon, w, 10, 6)
  tap(mon, w, inRow(mon, 24, " Settings ") + 1, 24)
  T.contains(mon:text(), "SETTINGS (changed live)")
  T.contains(mon:text(), "Rounds every (min)"); T.contains(mon:text(), "Keep seeds"); T.contains(mon:text(), "Re-map every (rounds)")
  local _, y = mon:find("Rounds every")
  T.truthy(inRow(mon, y, " - ") and inRow(mon, y, " + ") and inRow(mon, y, "<<") and inRow(mon, y, ">>"), "stepper with big steps")
  local vx = inRow(mon, y, "10")
  T.truthy(vx); T.eq(fg(mon, vx, y), COL.white)
  tapQ(mon, w, inRow(mon, y, " + ") + 1, y)
  T.eq(fg(mon, inRow(mon, y, "11"), y), COL.yellow, "sent, not confirmed: gold")
  w:run(8)
  T.eq(lastCmd(stubs[11]).set.EVERY, 11, "the turtle got EVERY=11")
  T.eq(fg(mon, inRow(mon, y, "11"), y), COL.white, "confirmed: white")
  tap(mon, w, inRow(mon, y, ">>") + 1, y); w:run(8)
  T.eq(lastCmd(stubs[11]).set.EVERY, 21)
  tap(mon, w, inRow(mon, y, "<<") + 1, y); tap(mon, w, inRow(mon, y, "<<") + 1, y); w:run(8)
  T.eq(lastCmd(stubs[11]).set.EVERY, 1, "clamped at the minimum")
  T.eq(fg(mon, inRow(mon, y, " - ") + 1, y), COL.grey, "- is disabled at the minimum")
  -- the Woodpecker's own settings
  tap(mon, w, 2, 24)
  tap(mon, w, 40, 6)
  tap(mon, w, inRow(mon, 24, " Settings ") + 1, 24)
  T.contains(mon:text(), "Keep saplings"); T.contains(mon:text(), "Sapling sweeps")
end)

T.test("farmhand: a lost turtle gets a Found button", function()
  local w, fh, mon, stubs = farm({ monitor = { 57, 24 }, lost = true })
  T.contains(mon:text(), "lost")
  T.eq(bg(mon, 30, 3), COL.red, "lost is a red stripe")
  tap(mon, w, 40, 6)
  T.contains(mon:line(1), "WOODPECKER-01"); T.contains(mon:line(1), "lost")
  local found
  for y = 6, 22 do local x = mon:line(y):find(" Found ", 1, true); if x then found = { x, y } end end
  T.truthy(found, "Found button")
  tapQ(mon, w, found[1] + 2, found[2])
  T.contains(mon:line(2), "home spot")
  w:run(6)
  T.eq(lastCmd(stubs[12]).want, "found")
end)

T.test("farmhand: Forget needs a turtle silent for 2 minutes, and two taps", function()
  local w, fh, mon, stubs = farm({ monitor = { 57, 24 } })
  stubs[11]:detach("top")                               -- the Partridge stops being heard
  w:run(130)
  T.contains(mon:text(), "not heard 2m")
  T.eq(bg(mon, 2, 3), COL.grey, "stale: grey stripe")
  tap(mon, w, 10, 6)
  tap(mon, w, inRow(mon, 24, " Info ") + 1, 24)
  local fx = inRow(mon, 19, " Forget this turtle ") or (function() for y = 8, 22 do local x = inRow(mon, y, " Forget this turtle "); if x then return x end end end)()
  T.truthy(fx, "Forget button")
  local fy; for y = 8, 22 do if inRow(mon, y, " Forget this turtle ") then fy = y end end
  tap(mon, w, fx + 2, fy)
  T.contains(mon:text(), "Sure?")
  T.contains(mon:line(1), "PARTRIDGE-01", "still there after one tap")
  tap(mon, w, inRow(mon, fy, "Sure?") + 1, fy)
  T.contains(mon:line(1), "FARMHAND"); T.absent(mon:text(), "Partridge-01"); T.contains(mon:text(), "Woodpecker-01")
  T.eq(fh:readTable("farmhand.cfg").turtles[11], nil, "saved")
  T.contains(mon:line(2), "Forgotten")
end)

---------------------------------------------------------------------------------------------------------
T.test("farmhand: a big farm follows the turtle; pan buttons, Follow, keys and the wheel", function()
  local w, fh, mon = farm({ monitor = { 57, 24 }, big = { 90, 70 } })
  tap(mon, w, 10, 6)
  T.eq(mon.ch[7][7], "\16", "the turtle at farm cell 6,5 sits at the top left of the view")
  T.eq(bg(mon, 7, 7), COL.magenta)
  T.absent(mon:text(), "Follow", "following: no Follow button")
  local py
  for y = 6, 23 do if mon:line(y):find(" ^ ", 1, true) and mon:line(y):find(" > ", 1, true) then py = y end end
  T.truthy(py, "the pan row")
  tap(mon, w, inRow(mon, py, " > ") + 1, py)             -- half a view to the right
  T.contains(mon:text(), "Follow")
  T.truthy(mon.ch[7][7] ~= "\16", "the view moved: the arrow is gone from where it was")
  tap(mon, w, inRow(mon, py, "Follow") + 1, py)
  T.eq(mon.ch[7][7], "\16", "Follow snaps back to the turtle"); T.absent(mon:text(), "Follow")
  -- keys and wheel on the computer's own screen
  click(w, fh, 6, 4)
  T.contains(fh.screen:line(1), "PARTRIDGE-01"); T.absent(fh.screen:text(), "Follow")
  fh:key(264); w:run(0.3)                               -- Down
  T.contains(fh.screen:text(), "Follow", "an arrow key pans")
  fh:key(268); w:run(0.3)                               -- Home
  T.absent(fh.screen:text(), "Follow", "Home follows")
  fh:scroll(1); w:run(0.3)
  T.contains(fh.screen:text(), "Follow", "the wheel pans")
  fh:type("f"); w:run(0.3)
  T.absent(fh.screen:text(), "Follow", "f follows")
  -- the monitor was not affected by the computer's own page
  T.contains(mon:line(1), "PARTRIDGE-01")
  -- opening a big farm's tile draws it shrunk to fit
  tap(mon, w, 2, 24)
  T.truthy(findBg(mon, COL.brown), "the overview still draws the big farm, shrunk")
end)

T.test("farmhand: the monitor and the computer's own screen keep separate pages", function()
  local w, fh, mon = farm({ monitor = { 57, 24 } })
  tap(mon, w, 10, 6)
  T.contains(mon:line(1), "PARTRIDGE-01"); T.contains(fh.screen:line(1), "FARMHAND")
  click(w, fh, 30, 4)
  T.contains(fh.screen:line(1), "WOODPECKER-01"); T.contains(mon:line(1), "PARTRIDGE-01")
end)

T.test("farmhand: no modem: says so in red", function()
  local w, fh = farm({ noModem = true })
  T.contains(fh.screen:text(), "No modem!")
  T.eq(fg(fh.screen, 3, 2), COL.red)
end)

T.test("farmhand: remembers its turtles across a reboot", function()
  local w, fh = farm({})
  local saved = fh:readTable("farmhand.cfg")
  T.truthy(saved.turtles[11] and saved.turtles[12])
  T.eq(saved.turtles[11].label, "Partridge-01")
  fh:reboot(); fh:run("farmhand"); w:run(0.5)
  T.contains(fh.screen:text(), "Partridge", "known before a single status arrives")
  T.contains(fh.screen:text(), "no signal")
end)

T.test("farmhand: no colour: still draws and works", function()
  local w, fh = farm({ colour = false })
  T.running(fh)
  T.contains(fh.screen:text(), "Partridge-01")
  T.truthy(inRow(fh.screen, 17, "[ Rounds all ]"))
  click(w, fh, 6, 4)
  T.contains(fh.screen:line(1), "[PARTRIDGE-01]")
end)

T.test("farmhand: a busy radio does not make the screens flicker", function()
  local w, fh, mon = farm({ monitor = { 57, 24 } })
  local noisy = w:computer{ id = 30, label = "Noisy" }
  noisy:attach("top", cc.wireless{ ender = true })
  noisy:writeFile("n.lua", [[
    peripheral.find("modem", function(n) rednet.open(n); return false end)
    while true do rednet.broadcast({ type = "status", role = "miner", id = 99, n = os.clock() }, "tanis-dig"); sleep(0.05) end
  ]])
  noisy:run("n")
  w:run(5)
  local m0, t0, c0 = mon.writes, fh.screen.writes, mon.clears or 0   -- screens.lua clears the monitor once at boot
  w:run(10)
  T.eq((mon.clears or 0) - c0, 0, "the monitor is never cleared"); T.eq(fh.screen.clears or 0, 0, "nor the computer's own screen")
  -- Only the 'seen Ns ago' / countdown rows change, once a second or so: about 20 radio messages a second must
  -- not turn into 20 screen rewrites a second
  T.truthy(mon.writes - m0 <= 10 * 12, "monitor writes in 10 s: " .. (mon.writes - m0))
  T.truthy(fh.screen.writes - t0 <= 10 * 12, "terminal writes in 10 s: " .. (fh.screen.writes - t0))
end)
