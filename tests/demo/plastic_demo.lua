-- tests/demo/plastic_demo.lua  --  drives computer/plastic/plastic_screens.lua with a made-up factory (the sim has no
-- fluid machines). plastic_demo.cfg may set: taps (list of "ok"|"full"|"dry"), units (n), power (bool), furnaces (n),
-- dock (bool), paused, problems (list), monitor (bool). _G.pd records what the screen asked for.
local cfg = { taps = { "ok", "ok", "full", "dry", "ok", "ok", "ok", "full" }, units = 1, power = true, furnaces = 1,
              dock = true, paused = false, problems = { "Tap #4 is dry: its log is used up." } }
if fs.exists("plastic_demo.cfg") then
  local f = fs.open("plastic_demo.cfg", "r"); for k, v in pairs(textutils.unserialise(f.readAll())) do cfg[k] = v end; f.close()
end
local pd = { paused = cfg.paused, scans = 0 }
_G.pd = pd

local F = { taps = {}, units = {}, water = {}, buffers = {}, furnaces = {}, dock = cfg.dock and "minecraft:barrel_1" or nil }
local tapState, unitState, furnState = {}, {}, {}
for i, w in ipairs(cfg.taps) do
  local n = "industrialforegoing:fluid_extractor_" .. i
  F.taps[i] = n; tapState[n] = { stalled = w == "dry", full = w == "full", amount = 400 }
end
for i = 1, cfg.units do
  local n = "industrialforegoing:latex_processing_unit_" .. i
  F.units[i] = n
  unitState[n] = { latex = 11500, water = 14400, energy = cfg.power and 550 or nil, cap = cfg.power and 1000 or nil }
end
for i = 1, cfg.furnaces do
  local n = "minecraft:furnace_" .. i
  F.furnaces[i] = n; furnState[n] = { cooking = 3, fuel = 40 }
end

local problems = {}
for i, m in ipairs(cfg.problems) do problems[tostring(i)] = "Plastic factory: " .. m end
local mon = cfg.monitor and peripheral.wrap("right")

require("plastic_screens")({
  snap = function()
    local state = pd.paused and "paused" or (next(problems) and "waiting" or "running")
    return { cfg = { paused = pd.paused, plastic = 1204 }, F = F, tapState = tapState, unitState = unitState,
             furnState = furnState, problems = problems, note = "Running", dockFuel = 280, dockPlastic = 64,
             state = state, rate = 14.2, furnaceOn = true }
  end,
  lines = function() return { "Running", "Made: 1204 plastic", "Unit 1: latex 72%, water 90%" } end,
  setPaused = function(p) pd.paused = p end,
  scan = function() pd.scans = pd.scans + 1 end,
  findMonitor = function() if mon then return mon, "right" end end,
  unitCap = 16000,
}).run()
