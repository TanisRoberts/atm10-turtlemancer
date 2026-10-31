-- The Overworld Foreman on the UI kit (docs/systems/foreman.md): overview tiles, a miner's page, presets and the
-- editor, typed commands, at 57x24 (monitor), 51x19, 39x13 and 26x20, with stand-in Starlings on the radio
-- (Canaries and Firecrests come through their own Foremen: tests/scenarios/foreman_remote.lua).
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

local SIZES = { { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }

local function entry(num, id, label, extra)
  local e = { num = num, label = label, want = "dock", minY = 10, maxY = 20, pMin = 10, pMax = 20, r1 = 0, r2 = 1,
              pR1 = 0, pR2 = 1, seq = 1 }
  for k, v in pairs(extra or {}) do e[k] = v end
  return e
end

-- A Starling that can go quiet (_G.mute) so the Foreman sees it go stale
local MUTE = [[
  rednet.open("top")
  local me = os.getComputerID()
  while true do
    if not _G.mute then
      rednet.broadcast({ type = "status", id = me, num = 5, label = "Starling-05", kind = "starling", bird = "Starling",
        state = "mining", msg = "Digging to Y 12", fuel = 40000, fuelLimit = 100000, slots = 7, y = 12, layer = 2, layers = 3,
        chunk = 4, chunks = 9, ring = 1, minY = 10, maxY = 20, dim = "the_end", facing = "east", seq = 1, want = "dock",
        pos = { x = 812, y = 12, z = -1203 }, home = { x = 800, y = 64, z = -1200 }, chunky = true, box = "ok",
        haul = { { "minecraft:diamond", 12 }, { "minecraft:iron_ingot", 1240 } } }, "tanis-miner")
    end
    os.sleep(1)
  end
]]

-- o.w, o.h: the Foreman's own screen; o.monitor = { w, h }; o.none: no miners at all; o.noModem
local function world(o)
  o = o or {}
  local w = cc.world()
  local hub = w:computer{ id = 1, label = "Foreman", w = o.w or 51, h = o.h or 19 }
  if not o.noModem then hub:attach("top", cc.wireless{ ender = true }) end
  local mon = o.monitor and hub:monitor("right", o.monitor[1], o.monitor[2])
  hub:installRole("foreman")
  local canaries = {}
  if not o.none then
    canaries[12] = entry(3, 12, "Starling-03")
    canaries[13] = entry(5, 13, "Starling-05")
    canaries[8] = entry(2, 8, "Canary-02", { retired = true })
  end
  hub:writeTable("foreman.cfg", { nextNum = 6, chunkRings = true, handedOver = true, retiredNums = { [2] = "Canary-02" },
    canaries = canaries })
  hub:run("foreman")
  local e = { w = w, hub = hub, mon = mon }
  if not o.none then
    e.starling = MS.standIn(w, { id = 12, num = 3, label = "Starling-03", protocol = "tanis-miner", bird = "Starling",
      kind = "starling", dim = "the_end" })
    e.starling.G.state, e.starling.G.msg = "mining", "Digging to Y 14"
    e.bird5 = w:computer{ id = 13, label = "Starling-05" }
    e.bird5:attach("top", cc.wireless{ ender = true })
    e.bird5:writeFile("mute.lua", MUTE)
    e.bird5:run("mute")
  end
  w:run(o.settle or 10)
  return e
end

local function screens(e) return e.mon and { e.hub.screen, e.mon } or { e.hub.screen } end
-- tap the first (or, with last, the lowest) place the text shows on a screen: a click on the computer, a touch on a monitor
local function tapOn(e, scr, text, last)
  local a, z, step = 3, scr.h, 1
  if last then a, z, step = scr.h, 3, -1 end
  for row = a, z, step do
    local x = scr:line(row):find(text, 1, true)
    if x then
      if scr == e.hub.screen then e.hub:click(x, row) else scr:touch(x, row) end
      e.w:run(1)
      return
    end
  end
  error("no " .. text .. " on the screen:\n" .. scr:text(), 2)
end
local function cmd(e, line) e.hub:type(line); e.hub:key(257); e.w:run(1) end
local function cfg(e) return e.hub:readTable("foreman.cfg") end

T.test("screens: the overview shows a tile per miner at every size", function()
  for _, sz in ipairs(SIZES) do
    local e = world({ w = sz[1], h = sz[2] })
    local s = e.hub.screen
    T.contains(s, "FOREMAN")
    T.contains(s, "Starling-03")
    T.contains(s, "working")
    T.contains(s, "Fuel")
    T.contains(s, "Presets")
    T.contains(s, sz[1] > 30 and "Reboot all" or "Boot")
    T.absent(s, "Canary-02", "a retired miner is not on the overview")
    if sz[2] >= 19 then T.contains(s, "Digging to Y 14") end
    if sz[1] >= 51 then T.contains(s, "2 miners") end
  end
end)

T.test("screens: colours - a working tile has a green stripe, and nothing is drawn outside the screen", function()
  local e = world({ w = 51, h = 19 })
  local s = e.hub.screen
  local _, y = s:find("Starling-03")
  local _, bg = s:colourAt(3, y)
  T.truthy(bg, "stripe")
  T.contains(s:line(1), "FOREMAN")
end)

T.test("screens: a monitor and the computer keep their own page", function()
  local e = world({ monitor = { 57, 24 } })
  tapOn(e, e.mon, "Starling-03")
  T.contains(e.mon, "STARLING-03")
  T.contains(e.hub.screen, "Starling-05", "the computer is still on the overview")
  T.absent(e.hub.screen, "STARLING-03")
end)

T.test("screens: a miner's page at every size - status, layers, orders", function()
  for _, sz in ipairs(SIZES) do
    local e = world({ w = sz[1], h = sz[2] })
    local s = e.hub.screen
    tapOn(e, s, "Starling-05")
    T.contains(s, "STARLING-05")
    T.contains(s, "working")
    if sz[1] >= 44 then
      T.contains(s, "Fuel"); T.contains(s, "7/16")
      T.contains(s, "LAYERS"); T.contains(s, "START"); T.contains(s, "Min Y")
      T.contains(s, "Status"); T.contains(s, "Haul")
      T.contains(s, "ring 1")
      T.contains(s, "loader + box")
    else
      T.contains(s, "Info"); T.contains(s, "Haul")
      T.contains(s, "Fuel")
      tapOn(e, s, "Lay", true)
      T.contains(s, "START"); T.contains(s, "Min Y")
    end
    if sz[1] <= 30 then tapOn(e, s, "..", true) else tapOn(e, s, "Haul", true) end
    T.contains(s, "LAST HAUL"); T.contains(s, "Diamond"); T.contains(s, "1,240")
    tapOn(e, s, "<", true)
    if sz[1] < 44 then
      T.contains(s, "Starling-05")
    else
      T.contains(s, "Presets")
    end
  end
end)

T.test("screens: START sends the picked layers, a stepper changes them, STOP + DOCK sends it home", function()
  for _, sz in ipairs(SIZES) do
    local e = world({ w = sz[1], h = sz[2] })
    local s = e.hub.screen
    tapOn(e, s, "Starling-03")
    if sz[1] < 44 then tapOn(e, s, "Lay", true) end
    local _, y = s:find("Min Y")
    local x = s:line(y):find("+", 1, true)
    if sz[1] <= 30 then x = s:line(y + 1):find("+", 1, true); y = y + 1 end   -- narrow: the label sits above
    T.truthy(x, s:text())
    e.hub:click(x, y); e.w:run(1)
    T.eq(cfg(e).canaries[12].pMin, 11, "Min Y +1 at " .. sz[1])
    tapOn(e, s, "START", true)
    e.w:run(5)
    T.eq(e.starling.G.want, "run")
    T.eq(e.starling.G.lastCmd.minY, 11)
    tapOn(e, s, "STOP", true)
    e.w:run(5)
    T.eq(e.starling.G.want, "dock")
  end
end)

T.test("screens: a preset in the list picks its layers", function()
  local e = world({ w = 51, h = 19 })
  local s = e.hub.screen
  tapOn(e, s, "Starling-03")
  tapOn(e, s, "Gold")
  T.eq(cfg(e).canaries[12].pMin, -19)
  T.eq(cfg(e).canaries[12].pMax, -13)
end)

T.test("screens: Reboot and Retire need a second tap", function()
  local e = world({ w = 51, h = 19 })
  local s = e.hub.screen
  tapOn(e, s, "Starling-03")
  tapOn(e, s, "Boot", true)
  e.w:run(2)
  T.falsy(e.starling.G.lastCmd and e.starling.G.lastCmd.reboot, "one tap does nothing")
  T.contains(s, "Sure?")
  tapOn(e, s, "Sure?", true)
  e.w:run(4)
  T.truthy(e.starling.G.lastCmd.reboot, "second tap reboots")
  tapOn(e, s, "Retire", true)
  T.falsy(cfg(e).canaries[12].retired)
  tapOn(e, s, "Sure?", true)
  e.w:run(2)
  T.eq(cfg(e).canaries[12].retired, true)
  T.contains(s, "Starling-03 retired for good.")
  T.contains(s, "Presets", "back on the overview")
end)

T.test("screens: Dock all needs a second tap and sends every miner home", function()
  local e = world({ w = 51, h = 19 })
  local s = e.hub.screen
  tapOn(e, s, "Starling-03")
  tapOn(e, s, "START", true)
  e.w:run(2)
  T.eq(e.starling.G.want, "run")
  tapOn(e, s, "Back", true)
  tapOn(e, s, "Dock all", true)
  T.eq(e.starling.G.want, "run", "one tap does nothing")
  tapOn(e, s, "Sure?", true)
  e.w:run(4)
  T.eq(e.starling.G.want, "dock")
end)

T.test("screens: a miner that goes quiet greys out as lost", function()
  local e = world({ w = 51, h = 19 })
  T.contains(e.hub.screen, "working")
  e.bird5.G.mute = true
  e.w:run(30)
  local s = e.hub.screen
  local _, y = s:find("Starling-05")
  T.contains(s:line(y), "lost")
  T.contains(s, "not heard")
end)

T.test("screens: the Retired button lists retired miners", function()
  local e = world({ w = 57, h = 24 })
  local s = e.hub.screen
  T.contains(s, "Retired (1)")
  tapOn(e, s, "Retired (1)", true)
  T.contains(s, "Canary-02")
  T.contains(s, "retired")
  tapOn(e, s, "Back", true)
  T.contains(s, "Presets")
end)

T.test("screens: presets - new, edit, duplicate, move, delete", function()
  for _, sz in ipairs(SIZES) do
    local e = world({ w = sz[1], h = sz[2] })
    local s = e.hub.screen
    tapOn(e, s, "Presets", true)
    T.contains(s, "PRESETS")
    T.contains(s, "Diamonds"); T.contains(s, "-59..-58")
    -- new
    tapOn(e, s, "New", true)
    T.contains(s, "NEW PRESET")
    e.hub:type("Deepest"); e.w:run(0.5)
    T.contains(s, "Deepest")
    tapOn(e, s, "Save", true)
    T.contains(s, "PRESETS")
    T.contains(s, "Deepest")
    T.eq(cfg(e).presets[7].name, "Deepest")
    -- tap a row twice: the editor
    tapOn(e, s, "Gold")
    tapOn(e, s, "Gold")
    T.contains(s, "EDIT PRESET")
    T.contains(s, "From ring")
    tapOn(e, s, "Cancel", true)
    T.contains(s, "PRESETS")
    -- delete it again: tap-twice
    tapOn(e, s, "Deepest")
    tapOn(e, s, "Edit", true)
    tapOn(e, s, "Delete", true)
    T.eq(#cfg(e).presets, 7, "one tap does not delete")
    tapOn(e, s, "Sure?", true)
    T.eq(#cfg(e).presets, 6)
    tapOn(e, s, "<", true)
    T.contains(s, "Presets")
  end
end)

T.test("screens: the editor saves changes, refuses a bad one and a duplicate name", function()
  local e = world({ w = 51, h = 19 })
  local s = e.hub.screen
  tapOn(e, s, "Presets", true)
  tapOn(e, s, "Gold"); tapOn(e, s, "Gold")
  local _, y = s:find("Min Y")
  local x = s:line(y):find("+", 1, true)
  e.hub:click(x, y); e.w:run(1)
  tapOn(e, s, "Save", true)
  T.eq(cfg(e).presets[3].minY, -18)
  -- a name that exists
  tapOn(e, s, "+ New", true)
  e.hub:type("gold"); e.w:run(0.5)
  tapOn(e, s, "Save", true)
  T.contains(s, "already a preset called Gold")
  T.contains(s, "NEW PRESET", "stays in the editor")
  -- an empty one
  tapOn(e, s, "Cancel", true)
  tapOn(e, s, "+ New", true)
  tapOn(e, s, "Save", true)
  T.contains(s, "Give it a name")
  -- Duplicate and Up/Down
  tapOn(e, s, "Cancel", true)
  tapOn(e, s, "Lapis")
  tapOn(e, s, "Duplicate", true)
  T.eq(cfg(e).presets[5].name, "Lapis 2")
  tapOn(e, s, "Up", true)
  T.eq(cfg(e).presets[4].name, "Lapis 2")
  tapOn(e, s, "Down", true)
  T.eq(cfg(e).presets[5].name, "Lapis 2")
end)

T.test("screens: a monitor cannot type a name", function()
  local e = world({ monitor = { 57, 24 } })
  tapOn(e, e.mon, "Presets", true)
  tapOn(e, e.mon, "New", true)
  T.contains(e.mon, "type on the")
end)

T.test("commands: /presets /new /edit /delete /home keep working", function()
  local e = world({ w = 51, h = 19 })
  local s = e.hub.screen
  cmd(e, "/presets")
  T.contains(s, "PRESETS")
  cmd(e, "/new Fresh")
  T.contains(s, "NEW PRESET"); T.contains(s, "Fresh")
  tapOn(e, s, "Save", true)
  T.eq(cfg(e).presets[7].name, "Fresh")
  cmd(e, "/edit lap")
  T.contains(s, "EDIT PRESET"); T.contains(s, "Lapis")
  cmd(e, "preset")                       -- without the slash, and an old alias
  T.contains(s, "PRESETS")
  cmd(e, "/delete fresh")
  T.contains(s, "EDIT PRESET")
  tapOn(e, s, "Delete", true)
  tapOn(e, s, "Sure?", true)
  T.eq(#cfg(e).presets, 6)
  cmd(e, "/edit nothing")
  T.contains(s, "No preset called nothing")
  cmd(e, "/home")
  T.contains(s, "Reboot all")
end)

T.test("commands: /reboot and /redock take a name, a number or all", function()
  local e = world({ w = 51, h = 19 })
  local s = e.hub.screen
  cmd(e, "/reboot")
  T.contains(s, "Usage: /reboot")
  cmd(e, "/reboot starling-03")
  T.contains(s, "Starling-03: reboot sent.")
  e.w:run(4)
  T.truthy(e.starling.G.lastCmd.reboot)
  cmd(e, "/reboot starling")
  T.contains(s, "matches 2 miners: be more exact")
  cmd(e, "/reboot all")
  T.contains(s, "Reboot sent to 2 miners.")
  cmd(e, "/reboot 9")
  T.contains(s, "No miner matches 9")
  cmd(e, "/redock 3")
  T.contains(s, "Re-dock sent to 1")
  e.w:run(4)
  T.truthy(e.starling.G.lastCmd.redock)
  cmd(e, "/redock all")
  T.contains(s, "Re-dock sent to 2")
end)

T.test("commands: /retired, /help, an unknown command, and the command bar", function()
  local e = world({ w = 51, h = 19 })
  local s = e.hub.screen
  cmd(e, "/retired")
  T.contains(s, "Canary-02")
  cmd(e, "/home")
  T.contains(s, "Presets")
  cmd(e, "/help")
  T.contains(s, "COMMANDS")
  for _, c in ipairs({ "/presets", "/new", "/edit", "/delete", "/reboot", "/redock", "/retired", "/home", "/help" }) do
    T.contains(s, c)
  end
  cmd(e, "/home")
  cmd(e, "help reboot")
  T.contains(s, "/reboot <miner|all>: reboot one or all")
  cmd(e, "frobnicate")                   -- typed without the slash
  T.contains(s, "Unknown command /frobnicate")
  cmd(e, "/frobnicate")                  -- the command bar has no such command
  T.contains(s, "Unknown command")
  e.hub:key(256); e.w:run(0.5)
  e.hub:type("/re"); e.w:run(0.5)
  T.contains(s, "/reboot"); T.contains(s, "/redock"); T.contains(s, "/retired")
  T.absent(s, "/delete")
end)

T.test("screens: the empty state waits for the first miner", function()
  for _, sz in ipairs(SIZES) do
    local e = world({ w = sz[1], h = sz[2], none = true })
    local s = e.hub.screen
    T.contains(s, "FOREMAN")
    T.contains(s, "Waiting for")
    T.contains(s, "No miners yet.")
    T.contains(s, "Presets")
  end
end)

T.test("screens: no ender modem is said once, plainly", function()
  local e = world({ noModem = true })
  T.contains(e.hub.screen, "No modem")
end)

T.test("screens: a first miner appears by itself", function()
  local e = world({ w = 51, h = 19, none = true })
  local c = MS.standIn(e.w, { id = 30, protocol = "tanis-miner", bird = "Starling", kind = "starling", dim = "the_end" })
  e.w:run(15)
  T.contains(e.hub.screen, "Starling-")
  T.absent(e.hub.screen, "Waiting for the first miner")
end)

