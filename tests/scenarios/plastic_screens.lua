-- The plastic factory's screens on the UI kit (#22): the dashboard at the four sizes with a made-up factory
-- (tests/demo/plastic_demo.lua: the sim has no fluid machines), the paused state, Pause/Run by touch on the monitor
-- and on the computer, the typed commands, and the real program booting on an empty cable.
local cc = require("sim.cc")
local T = require("sim.test")

local SIZES = { { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }

local function demo(w, h, cfg, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, label = "Plastic", w = w, h = h, colour = opts.colour }
  local mon = opts.monitor and c:monitor("right", opts.monitor[1], opts.monitor[2])
  for _, f in ipairs({ "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua",
                       "shared/slash.lua", "computer/plastic/plastic_screens.lua", "tests/demo/plastic_demo.lua" }) do c:install(f) end
  local t = {}
  for k, v in pairs(cfg or {}) do t[k] = v end
  t.monitor = mon ~= nil
  c:writeTable("plastic_demo.cfg", t)
  c:run("plastic_demo")
  world:run(0.5)
  return world, c, mon
end
local function pd(c) return c.env._G.pd end

for _, s in ipairs(SIZES) do
  local W, H = s[1], s[2]
  T.test(("plastic screens: dashboard at %dx%d"):format(W, H), function()
    local world, c = demo(W, H)
    local scr = c.screen
    T.running(c)
    T.contains(scr, "PLASTIC"); T.contains(scr, "Pause"); T.contains(scr, "Made 1,204")
    T.contains(scr, "Tap #4", "the problem")
    T.contains(scr, "DRY", "the dry tap, in words")
    if W >= 39 then T.contains(scr, "waiting") end
    if H >= 19 then
      T.contains(scr, "LATEX UNIT 1"); T.contains(scr, "TAPS"); T.contains(scr, "FURNACES AND DOCK")
      T.contains(scr, "latex"); T.contains(scr, "72%")
    else
      T.contains(scr, "Unit 1 L72 W90 P55"); T.contains(scr, "Furnace")
    end
    for y = 1, H do T.truthy(#scr:line(y) <= W, "row " .. y .. " wider than the screen") end
    T.absent(scr, "Screen error")
  end)
end

T.test("plastic screens: Pause and Run by touch on the monitor and the header follows", function()
  local world, c, mon = demo(57, 24, {}, { monitor = { 57, 24 } })
  T.contains(mon, "Pause")
  local x, y = mon:find("Pause")
  mon:touch(x, y); world:run(1)
  T.truthy(pd(c).paused, "Pause tapped")
  T.contains(mon, "paused"); T.contains(mon, "Run"); T.absent(mon, "Pause")
  x, y = mon:find("Run")
  mon:touch(x, y); world:run(1)
  T.truthy(not pd(c).paused, "Run tapped")
  T.contains(mon, "Pause")
end)

T.test("plastic screens: typed commands, with and without the slash", function()
  local world, c = demo(51, 19)
  c:type("/pause"); c:key(257); world:run(1)
  T.truthy(pd(c).paused, "/pause")
  T.contains(c.screen, "paused")
  c:type("resume"); world:run(0.3); c:key(257); world:run(1)
  T.truthy(not pd(c).paused, "resume without a slash")
  c:type("/list"); c:key(257); world:run(1)
  T.truthy(pd(c).scans >= 1, "/list scans")
  T.contains(c.screen, "ON MY CABLE"); T.contains(c.screen, "fluid_extractor_1")
  c:click(2, 19); world:run(0.5)               -- Back
  T.contains(c.screen, "Made 1,204")
  c:type("/status"); c:key(257); world:run(1)
  T.contains(c.screen, "Made: 1204 plastic"); T.contains(c.screen, "Tap #4")
  c:type("/home"); c:key(257); world:run(1)
  T.contains(c.screen, "Made 1,204")
  c:type("/help"); c:key(257); world:run(1)
  T.absent(c.screen, "Screen error")
end)

T.test("plastic screens: no machines, no problems, no dock", function()
  local world, c = demo(51, 19, { taps = {}, units = 0, furnaces = 0, dock = false, problems = {} })
  T.contains(c.screen, "No latex unit"); T.contains(c.screen, "No furnace"); T.contains(c.screen, "Dock: none found")
  T.absent(c.screen, "Screen error")
end)

T.test("plastic screens: no colour still reads", function()
  local world, c = demo(51, 19, {}, { colour = false })
  T.contains(c.screen, "[PLASTIC FACTORY]"); T.contains(c.screen, "Pause")
end)

T.test("plastic: the real program boots on an empty cable and shows the dashboard", function()
  local world = cc.world()
  local c = world:computer{ id = 3, label = "Plastic", w = 51, h = 19 }
  local mon = c:monitor("top", 57, 24)
  c:installRole("plastic")
  c:run("plastic"); world:run(10)
  T.running(c)
  T.contains(c.screen, "PLASTIC FACTORY"); T.contains(mon, "PLASTIC FACTORY")
  T.contains(mon, "No latex unit")
  local x, y = mon:find("Pause")
  mon:touch(x, y); world:run(1)
  T.contains(mon, "paused")
  local cfg = c:readTable("plastic.cfg")
  T.truthy(cfg and cfg.paused, "the pause is saved")
end)
