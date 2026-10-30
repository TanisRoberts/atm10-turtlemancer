-- The neural lab's screens on the UI kit (#22): the overview and a column page at the four sizes with a made-up lab
-- (tests/demo/neural_demo.lua: the sim has no Hostile Neural Networks machines), taps on a tile / CHECK / the mode
-- switch / the target stepper, the training column, the typed commands, and the real program booting on an empty cable.
local cc = require("sim.cc")
local T = require("sim.test")

local SIZES = { { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }
local C1 = "hostilenetworks:sim_chamber_1"

local function demo(w, h, cfg, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, label = "Neural", w = w, h = h, colour = opts.colour }
  local mon = opts.monitor and c:monitor("right", opts.monitor[1], opts.monitor[2])
  for _, f in ipairs({ "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua",
                       "shared/slash.lua", "computer/neural/neural_screens.lua", "tests/demo/neural_demo.lua" }) do c:install(f) end
  local t = {}
  for k, v in pairs(cfg or {}) do t[k] = v end
  t.monitor = mon ~= nil
  c:writeTable("neural_demo.cfg", t)
  c:run("neural_demo")
  world:run(0.5)
  return world, c, mon
end
local function nd(c) return c.env._G.nd end
-- Tap a label on a monitor, or (comp given) click it on the computer's own screen
local function tapOn(world, scr, label, comp)
  local x, y = scr:find(label)
  T.truthy(x, "no '" .. label .. "' on screen:\n" .. scr:text())
  if comp then comp:click(x, y) else scr:touch(x, y) end
  world:run(0.6)
end
local function wide(scr, W, H) for y = 1, H do T.truthy(#scr:line(y) <= W, "row " .. y .. " wider than the screen") end end

for _, s in ipairs(SIZES) do
  local W, H = s[1], s[2]
  T.test(("neural screens: overview at %dx%d"):format(W, H), function()
    local world, c = demo(W, H)
    local scr = c.screen
    T.running(c)
    T.contains(scr, "NEURAL"); T.contains(scr, "#1 Zombie"); T.contains(scr, "running"); T.contains(scr, "Pause")
    T.contains(scr, "no fab", "the problem is in words")
    if H > 14 then T.contains(scr, "CHECK"); T.contains(scr, "acc 98%") end
    if W >= 51 then T.contains(scr, "power 68%") end
    T.contains(scr, "1/", "a pager: more columns than fit")
    wide(scr, W, H)
    T.absent(scr, "Screen error")
  end)

  T.test(("neural screens: column page at %dx%d"):format(W, H), function()
    local world, c = demo(W, H)
    tapOn(world, c.screen, "#1 Zombie", c)
    local scr = c.screen
    T.contains(scr, "#1 ZOMBIE"); T.contains(scr, "Fab makes: rotten flesh"); T.contains(scr, "Stock")
    T.contains(scr, "100 / 512"); T.contains(scr, "Target"); T.contains(scr, "AUTO"); T.contains(scr, "ON"); T.contains(scr, "OFF")
    T.contains(scr, "CHECK")
    wide(scr, W, H)
    T.absent(scr, "Screen error")
    c:click(2, H); world:run(0.6)               -- Back
    T.contains(c.screen, "#2 Skeleton")
  end)
end

T.test("neural screens: tiles, CHECK on a tile, Pause, Check all, paging", function()
  local world, c, mon = demo(57, 24, { n = 8 }, { monitor = { 57, 24 } })
  T.contains(mon, "#1 Zombie"); T.contains(mon, "1/2")
  -- a tap on CHECK checks that column and does not open it
  local rows = {}
  for y = 1, mon.h do local x = mon:line(y):find("CHECK", 1, true); if x then rows[#rows + 1] = { x, y } end end
  T.truthy(#rows >= 3, "a CHECK per tile")
  mon:touch(rows[1][1] + 1, rows[1][2]); world:run(0.6)
  T.eq(nd(c).checks[C1], 1)
  T.contains(mon, "#2 Skeleton", "still the overview")
  tapOn(world, mon, "Check all")
  T.truthy(nd(c).checks["hostilenetworks:sim_chamber_2"], "Check all reaches the others")
  tapOn(world, mon, "Pause")
  T.truthy(nd(c).paused, "Pause"); T.contains(mon, "paused"); T.contains(mon, "Run")
  tapOn(world, mon, "Run")
  T.truthy(not nd(c).paused, "Run")
  mon:touch(55, 24); world:run(0.6)           -- next page
  T.contains(mon, "#7 Spider"); T.absent(mon, "#1 Zombie")
end)

T.test("neural screens: the column page controls", function()
  local world, c, mon = demo(57, 24, {}, { monitor = { 57, 24 } })
  tapOn(world, mon, "#1 Zombie")
  T.contains(mon, "Mode")
  tapOn(world, mon, "OFF")
  T.eq(nd(c).forced[C1], "off")
  tapOn(world, mon, "ON")
  T.eq(nd(c).forced[C1], "on")
  tapOn(world, mon, "AUTO")
  T.eq(nd(c).forced[C1], "auto")
  tapOn(world, mon, "CHECK")
  T.eq(nd(c).checks[C1], 1)
  -- the target stepper: steps of 16 below 256, 64 from there
  T.contains(mon, "512")
  local x, y = mon:find("Target")
  T.truthy(x)
  tapOn(world, mon, ">>")                     -- ten steps up: +640 at 64 a step
  T.truthy(nd(c).rules["minecraft:rotten_flesh"] and nd(c).rules["minecraft:rotten_flesh"] > 512, "target raised")
end)

T.test("neural screens: a training column explains what to do next", function()
  local world, c, mon = demo(57, 24, {}, { monitor = { 57, 24 } })
  tapOn(world, mon, "#4 Enderman")
  T.contains(mon, "#4 ENDERMAN"); T.contains(mon, "Training: levels the model"); T.contains(mon, "Inference")
  T.contains(mon, "Keeps 64 matrices spare"); T.contains(mon, "No fab yet"); T.contains(mon, "Mode")
  T.absent(mon, "CHECK", "no fab: nothing to check")
end)

T.test("neural screens: typed commands, with and without the slash", function()
  local world, c = demo(51, 19)
  local function say(line) c:type(line); c:key(257); world:run(1) end
  say("/pause"); T.truthy(nd(c).paused); T.contains(c.screen, "paused")
  say("resume"); T.truthy(not nd(c).paused)
  say("/check 2"); T.eq(nd(c).checks["hostilenetworks:sim_chamber_2"], 1)
  say("off 3"); T.eq(nd(c).forced["hostilenetworks:sim_chamber_3"], "off")
  say("auto 3"); T.eq(nd(c).forced["hostilenetworks:sim_chamber_3"], "auto")
  say("/on 3"); T.eq(nd(c).forced["hostilenetworks:sim_chamber_3"], "on")
  say("/check 99"); T.absent(c.screen, "Screen error"); T.contains(c.screen, "No column 99")
  say("/check"); T.contains(c.screen, "/check <n>")
  say("/target 1 128"); T.eq(nd(c).rules["minecraft:rotten_flesh"], 128)
  say("/column 1"); T.contains(c.screen, "#1 ZOMBIE")
  say("/home"); T.contains(c.screen, "#2 Skeleton")
  say("/list"); T.contains(c.screen, "ON MY CABLE"); T.contains(c.screen, "sim_chamber_1"); T.truthy(nd(c).scans >= 1)
  c:click(2, 19); world:run(0.5)
  T.contains(c.screen, "#2 Skeleton")
  say("/pairs"); T.contains(c.screen, "PAIRS"); T.contains(c.screen, "loot_fabricator_1");
  say("/status"); T.contains(c.screen, "STATUS"); T.contains(c.screen, "Running")
  say("/home")
  say("/help"); T.contains(c.screen, "/pairs")
  T.absent(c.screen, "Screen error")
end)

T.test("neural screens: an empty lab and no colour", function()
  local world, c = demo(51, 19, { n = 0, problems = {} })
  T.contains(c.screen, "No chambers on the cable yet.")
  local world2, c2 = demo(51, 19, {}, { colour = false })
  T.contains(c2.screen, "[NEURAL LAB]"); T.contains(c2.screen, "#1 Zombie")
end)

T.test("neural screens: a column that needs a person says why", function()
  local world, c = demo(57, 24, { attention = 3 })
  T.contains(c.screen, "no fab")
end)

T.test("neural: the real program boots on an empty cable and shows the overview", function()
  local world = cc.world()
  local c = world:computer{ id = 3, label = "Neural", w = 51, h = 19 }
  local mon = c:monitor("top", 57, 24)
  c:installRole("neural")
  c:run("neural"); world:run(10)
  T.running(c)
  T.contains(c.screen, "NEURAL LAB"); T.contains(mon, "NEURAL LAB"); T.contains(mon, "No chambers on the cable yet.")
  tapOn(world, mon, "Pause")
  T.contains(mon, "paused")
  local cfg = c:readTable("neural.cfg")
  T.truthy(cfg and cfg.paused, "the pause is saved")
  c:type("/status"); c:key(257); world:run(1)
  T.contains(c.screen, "STATUS")
end)
