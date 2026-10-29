-- The training furnace (#12): a finished run is kept on disk the moment it is confirmed, and a reboot or a
-- power cut at any stage ends clean: nothing half-learned, nothing stranded in the trainer.
local cc = require("sim.cc")
local T = require("sim.test")

local RAW, INGOT = "create:raw_zinc", "create:zinc_ingot"
cc.Inv.Furnace.recipes[RAW] = INGOT

local function setup(opts)
  opts = opts or {}
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 3 do inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
  for i = 0, 1 do net:add("minecraft:furnace_" .. i, w:furnace()) end
  local tr = net:add("minecraft:furnace_9", w:furnace())
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net))
  st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  local sm = w:computer{ id = 2, label = "Smelter" }
  sm:attach("back", cc.wired(net))
  sm:installRole("smelter")
  sm:writeFile("smelt.txt", "")
  local mon = sm:monitor("top", 57, 24)
  local cfg = { trainer = "minecraft:furnace_9" }
  for k, v in pairs(opts.cfg or {}) do cfg[k] = v end
  sm:writeTable("smelter.cfg", cfg)
  inv[2]:give("minecraft:coal", 32)
  tr:give(RAW, 1)
  return w, st, sm, inv, tr, mon
end

local function learned(sm) local c = sm:readTable("smelter.cfg"); return c and c.learned and next(c.learned) and c.learned end
local function startTrain(sm) sm:type("train"); sm:key(257); sm:key(257) end
local function stored(inv, name) local n = 0; for i = 0, 3 do n = n + inv[i]:count(name) end return n end

T.test("train: a finished run is on disk at once and known after a reboot", function()
  local w, st, sm, inv, tr, mon = setup()
  st:run("storage"); sm:run("smelter"); w:run(10)
  startTrain(sm)
  T.waitFor(w, function() return learned(sm) end, 300, "never learned")
  local l = learned(sm)
  local _, rec = next(l)
  T.eq(rec.out, INGOT)
  sm:reboot(); sm:run("smelter"); w:run(30)
  T.truthy(learned(sm), "still learned after reboot")
  T.eq(stored(inv, INGOT) + tr:count(INGOT), 1, "cooked item kept")
  T.running(sm)
end)

-- Cut power (reboot) at each stage of a run
for _, stage in ipairs{ "starting", "fuelling", "cooking" } do
  T.test("train: power cut while " .. stage .. " ends clean", function()
    local w, st, sm, inv, tr = setup()
    st:run("storage"); sm:run("smelter"); w:run(10)
    startTrain(sm)
    local hit = false
    if stage == "starting" then w:run(0.2)
    elseif stage == "fuelling" then T.waitFor(w, function() return tr:count("minecraft:coal") > 0 end, 60, "no fuel")
    else T.waitFor(w, function() return tr:count("minecraft:coal") > 0 or tr:count("minecraft:charcoal") > 0 end, 60); w:run(1) end
    sm:reboot(); sm:run("smelter")
    w:run(120)
    T.running(sm)
    -- nothing stranded: trainer holds no ore or cooked item
    T.eq(tr:count(RAW), 0, "ore left in the trainer")
    T.eq(tr:count(INGOT), 0, "cooked item left in the trainer")
    T.eq(stored(inv, RAW) + stored(inv, INGOT) , 1, "items back in storage")
    local c = sm:readTable("smelter.cfg")
    local n = 0; for _, r in pairs(c.learned or {}) do if r.out ~= INGOT or #r.inputs ~= 1 then n = n + 100 end n = n + 1 end
    T.truthy(n == 0 or n == 1, "no half-learned recipe")
  end)
end

T.test("train: a torn config write (power cut between delete and move) loses nothing", function()
  local w, st, sm, inv, tr = setup()
  sm:writeTable("smelter.cfg.new", { trainer = "minecraft:furnace_9", learned = { zinc_ingot = { out = INGOT, inputs = { RAW }, per = { [RAW] = 1 }, at = 1 } } })
  -- the old file is gone, as after a cut between fs.delete and fs.move
  sm.files["smelter.cfg"] = nil
  st:run("storage"); sm:run("smelter"); w:run(10)
  T.running(sm)
  sm:type("recipes"); sm:key(257); w:run(2)
  T.truthy(learned(sm), "learned recipe recovered from smelter.cfg.new")
end)

T.test("train: an unreadable smelter.cfg is never overwritten by an empty one", function()
  local w, st, sm, inv, tr = setup()
  sm:writeFile("smelter.cfg", "{ trainer = \"minecraft:furnace_9\", learned = { zinc_ingot = { out = ")   -- torn write
  st:run("storage"); sm:run("smelter"); w:run(70)
  T.running(sm)
  local s = sm:readFile("smelter.cfg") or ""
  T.truthy(s:find("zinc_ingot", 1, true) or sm:readFile("smelter.cfg.bad"), "torn file kept for recovery")
end)
