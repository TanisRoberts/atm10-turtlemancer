-- tests/demo/neural_demo.lua  --  drives computer/neural/neural_screens.lua with a made-up lab (the sim has no Hostile
-- Neural Networks machines). neural_demo.cfg may set: n (columns, default 8), problems (list of {key, text}), monitor.
-- _G.nd records what the screen asked for: paused, forced[c], checks[c], rules[item], scans.
local cfg = { n = 8, problems = { { "dock", "Neural lab: Column 4 has no fab: build one or set it to Training." } } }
if fs.exists("neural_demo.cfg") then
  local f = fs.open("neural_demo.cfg", "r"); for k, v in pairs(textutils.unserialise(f.readAll())) do cfg[k] = v end; f.close()
end
local nd = { paused = false, forced = {}, checks = {}, rules = {}, scans = 0 }
_G.nd = nd

local MOBS = { "Zombie", "Skeleton", "Creeper", "Enderman", "Blaze", "Witch", "Spider", "Slime" }
local ITEMS = { "minecraft:rotten_flesh", "minecraft:bone", "minecraft:gunpowder", nil, "minecraft:blaze_rod",
                "minecraft:glass_bottle", "minecraft:string", "minecraft:slime_ball" }
local L = { chambers = {}, fabs = {}, lamps = {}, furnators = {}, cells = {}, dock = "minecraft:barrel_7" }
local P, stats, links = {}, {}, {}
for i = 1, cfg.n do
  local k = (i - 1) % #MOBS + 1
  local c = "hostilenetworks:sim_chamber_" .. i
  L.chambers[i] = c
  local training = k == 4
  local p = { mob = MOBS[k], item = ITEMS[k], f = (not training) and ("hostilenetworks:loot_fabricator_" .. i) or nil,
              l = "minecraft:redstone_relay_" .. i, stock = 100 * k, cap = 512, training = training or nil,
              state = training and "TRAINING" or (k == 2 and "AT TARGET" or (k == 6 and "OFF" or "RUNNING")),
              bank = 1, fin = 4, matrices = 312, cEnergy = 71, cCap = 100, fEnergy = 64, fCap = 100 }
  if cfg.attention == i then p.state, p.blink = "NO FAB", true end
  P[c] = p
  stats[c] = { runs = 214, preds = 210, made = 5120 }
  links[c] = { f = p.f, l = p.l }
  L.fabs[#L.fabs + 1] = p.f
  L.lamps[#L.lamps + 1] = p.l
end
local problems = {}
for _, pr in ipairs(cfg.problems) do problems[pr[1]] = pr[2] end
local mon = cfg.monitor and peripheral.wrap("right")
local ncfg = { paused = false, force = {}, stats = stats, links = links }

local function pathOf(id) return (tostring(id):match(":(.+)$") or tostring(id)) end
local function shortName(id) if not id then return "?" end return pathOf(id):gsub("_", " ") end
local function stockText(p)
  if p.training then return "training model" end
  if not p.f then return "no fab yet" end
  if not p.item then return "item: learning" end
  return ("%s %s/%s"):format(shortName(p.item), tostring(p.stock), (p.cap or 0) == 0 and "off" or tostring(p.cap))
end
local function accText(st)
  if not st or (st.runs or 0) < 3 then return "acc ?" end
  return ("acc %d%%"):format(math.floor((st.preds or 0) / st.runs * 100 + 0.5))
end

require("neural_screens")({
  snap = function()
    ncfg.paused = nd.paused
    return { L = L, P = P, cfg = ncfg, E = { TRAIN_KEEP = 64 }, problems = problems, power = { pct = 68 }, note = "Furnator fuelled from the dock.",
             state = nd.paused and "paused" or (next(problems) and "waiting" or "running"), dockMatrices = 312, furnatorFuel = 0 }
  end,
  lines = function() return { "Running", "#1 Zombie: RUNNING" } end,
  stockText = stockText, accText = accText, shortName = shortName, pathOf = pathOf,
  setPaused = function(v) nd.paused = v end,
  setForce = function(c, v) ncfg.force[c] = v; nd.forced[c] = v or "auto" end,
  check = function(c) nd.checks[c] = (nd.checks[c] or 0) + 1 end,
  setRule = function(item, n) nd.rules[item] = n; for _, p in pairs(P) do if p.item == item then p.cap = n end end end,
  scan = function() nd.scans = nd.scans + 1 end,
  findMonitor = function() if mon then return mon, "right" end end,
}).run()
