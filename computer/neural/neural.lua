-- neural.lua  --  Neural lab: a wall of Hostile Neural Networks columns (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- The wall: one COLUMN per mob = a Simulation Chamber on top, its Loot Fabricator underneath, and
-- optionally a Redstone Relay (or AP Redstone Integrator) with a lamp touching it. Everything on the
-- lab's OWN wired cable (keep it apart from the storage cable: storage would treat the chambers as
-- storage barrels). Full-block wired modems work well: one between/behind each chamber and fab.
-- Also on the lab cable: the DOCK barrel (a second modem joins it to the storage cable, then /dock on
-- storage, with a keep line for prediction matrices), optional energy cell(s) and Powah Furnator(s).
--
-- What the computer does (it can't open the machines' screens, so a few things stay by hand):
--   * The data model lives in its chamber for good (the mod won't let anything take it back out).
--   * The drop is picked in each FAB's own screen. The lab learns what a fab makes from its output.
--   * ON = it drips prediction matrices into the chamber (1 at a time, MATRIX_HOLD) and feeds the
--     predictions to its fab. OFF = it stops adding matrices: the chamber finishes its run and idles.
--     Idle chambers and fabs use no power.
--   * neural.txt says how many of each item to keep: a column runs until storage has that many,
--     then stops, and starts again below RESTART_AT% of it. Items with no line: DEFAULT_KEEP.
--   * Switch a fab to another drop: it's noticed on its next batch. A column that's stopped keeps
--     one prediction banked; tap CHECK and it sends it through to see what the fab makes now. It
--     also checks by itself: after PROBE_EVERY minutes, then twice as long each time nothing has
--     changed (up to PROBE_MAX). Each check costs one batch.
--   * New columns are found by themselves (and every 30 s). Chambers, fabs and lamps are paired in
--     the order they were connected; a pair sticks once made. PAIRS= in neural.env overrides it.
--   * Lamps: steady = running, off = stopped (cap reached / switched off), blinking = needs you.
--   * Power: solar etc. first. The Furnator only gets charcoal/coal from the dock while stored
--     power is under FUEL_BELOW%. Under LOW_POWER% only the column furthest below its target runs.
--   * Training mode (set in the chamber's screen) is spotted by itself: matrices get used and
--     nothing comes out. A training column is fed regardless of targets, as long as more than
--     TRAIN_KEEP matrices are spare, and needs no fab (build the chamber, set it to Training, add
--     the fab later). When it stops taking matrices the model is probably Self Aware: switch the
--     chamber back to Inference. A chamber with no fab is fed one matrix to find out its mode.
--
-- Needs a wireless/ender modem too: it gets item counts from storage's broadcast and reports to
-- the mainframe (board row, alerts, "island neural"). Monitor touching the computer: tap a column
-- for its page. Terminal: the same screens with a command bar (/status /list /pairs /check <n> /on|off|auto <n>
-- /target <n> <count> /column <n> /pause /resume /help, slash optional).

local ENV_FILE   = "neural.env"
local RULES_FILE = "neural.txt"
local CFG_FILE   = "neural.cfg"
local BASE       = "tanis-base"

local MATRIX = "hostilenetworks:prediction_matrix"
-- Chamber slots (CC numbering): 1 model, 2 matrix, 3 generalized prediction ("base drop"), 4 mob prediction
local C_MODEL, C_INPUT, C_BASE, C_PRED = 1, 2, 3, 4
-- Fab slots: 1 prediction in, 2..17 out
local F_IN = 1
local NO_POWER_FE = 20000   -- a chamber/fab holding less than this is out of power (their buffers are 1-2M)

-- Furnator fuels from the dock, best for the job first (never blaze rods: that's burning the product)
local FUELS = { "minecraft:charcoal", "minecraft:coal", "minecraft:coal_block" }
-- Storage never hands out its last stack of these: the smelter burns them
local SMELTER_RESERVE = { ["minecraft:charcoal"] = 64, ["minecraft:coal"] = 64 }
local IS_FUEL = {}
for _, f in ipairs(FUELS) do IS_FUEL[f] = true end

local DEFAULTS = {
  { "TICK", 2, "Seconds between passes." },
  { "DEFAULT_KEEP", 256, "Items with no line in neural.txt: keep this many in storage." },
  { "RESTART_AT", 90, "A column that stopped at its target starts again when storage drops below this % of it." },
  { "MATRIX_HOLD", 1, "Prediction matrices kept in a running chamber. Low = it stops quickly when switched off." },
  { "FAB_HOLD", 2, "Predictions kept in a fab's input. The rest wait in the chamber, so a fab can't overshoot." },
  { "PROBE_EVERY", 15, "Minutes before a stopped column first checks its fab (one batch, to spot a changed drop). 0 = only on CHECK." },
  { "PROBE_MAX", 240, "Each check that finds no change doubles the wait, up to this many minutes. A change resets it." },
  { "STALL_AFTER", 90, "Seconds a running chamber may go without using a matrix before it's flagged stuck." },
  { "LOW_POWER", 10, "Stored power % under which only the column furthest below its target runs." },
  { "FUEL_BELOW", 30, "Feed the Furnator while the cells, or ANY one chamber, are under this %. Solar first." },
  { "FURNATOR_KEEP", 8, "Fuel items kept in each Furnator while it's being fed." },
  { "TRAIN_KEEP", 64, "Columns on Training mode only take matrices while more than this many are spare (the rest are for the fabs)." },
  { "WITHOUT_STORAGE", "stop", "No item counts from storage (storage silent): stop = hold every column, run = keep making." },
  { "DOCK", "", "The dock barrel's name on this cable. Blank = find it: the one chest/barrel on the cable." },
  { "PAIRS", "", "Fix a pairing by hand: chamber:fab[:lamp] by their numbers, comma separated, e.g. 3:5:2, 4:7" },
}

---------------------------------------------------------------------------
-- Settings (neural.env): same rules as butler.env
---------------------------------------------------------------------------
local E, envStamp = {}, nil

local function stampOf(path)
  if not fs.exists(path) or not fs.attributes then return nil end
  local ok, a = pcall(fs.attributes, path)
  return ok and a and (tostring(a.modified) .. ":" .. tostring(a.size)) or nil
end

local function readEnv()
  local vals = {}
  if fs.exists(ENV_FILE) then
    local f = fs.open(ENV_FILE, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then vals[k:upper()] = v end
    end
    f.close()
  end
  local missing = {}
  for _, d in ipairs(DEFAULTS) do
    if vals[d[1]] == nil then missing[#missing + 1] = d; vals[d[1]] = tostring(d[2]) end
  end
  if #missing > 0 then
    local new = not fs.exists(ENV_FILE)
    local f = fs.open(ENV_FILE, new and "w" or "a")
    if new then f.writeLine("# Neural lab settings. Edit and save: picked up within a few seconds.") end
    for _, d in ipairs(missing) do
      f.writeLine("")
      f.writeLine("# " .. d[3])
      f.writeLine(d[1] .. "=" .. tostring(d[2]))
    end
    f.close()
  end
  for _, d in ipairs(DEFAULTS) do
    local v = vals[d[1]]
    if type(d[2]) == "number" then E[d[1]] = tonumber(v) or d[2] else E[d[1]] = v end
  end
  envStamp = stampOf(ENV_FILE)
end

local function refreshEnv()
  if stampOf(ENV_FILE) ~= envStamp then readEnv() end
end

---------------------------------------------------------------------------
-- Keep rules (neural.txt): "<item> <count>" or "<item> off"
---------------------------------------------------------------------------
local RULES_HEADER = {
  "# Neural lab: how many of each item to keep in storage.",
  "# A column runs until storage has this many of what its fab makes, then stops. It starts again",
  "# below RESTART_AT% of it (neural.env). Items without a line here: DEFAULT_KEEP (neural.env).",
  "# One line per item:  <item> <count>   or   <item> off   (never make it). The monitor's - / +",
  "# buttons edit these lines. The \"minecraft:\" part is optional.",
}
local rules, rulesStamp = {}, nil

local function readRules()
  if not fs.exists(RULES_FILE) then
    local f = fs.open(RULES_FILE, "w")
    for _, l in ipairs(RULES_HEADER) do f.writeLine(l) end
    f.writeLine("blaze_rod 512")
    f.writeLine("ender_pearl 256")
    f.close()
  end
  rules = {}
  local f = fs.open(RULES_FILE, "r")
  while true do
    local line = f.readLine()
    if not line then break end
    line = line:gsub("#.*$", "")
    local item, val = line:match("^%s*([%w_:%.%-/]+)%s+(%w+)%s*$")
    if item then
      item = item:lower()
      if val:lower() == "off" or val:lower() == "never" then rules[item] = 0
      elseif tonumber(val) then rules[item] = math.max(0, math.floor(tonumber(val))) end
    end
  end
  f.close()
  rulesStamp = stampOf(RULES_FILE)
end

local function refreshRules()
  if stampOf(RULES_FILE) ~= rulesStamp then readRules() end
end

local function pathOf(id) return (tostring(id):match(":(.+)$") or tostring(id)) end

-- The rule that applies to an item id (full id first, then without the mod part)
local function ruleKey(id)
  if rules[id] then return id end
  if rules[pathOf(id)] then return pathOf(id) end
  return nil
end

local function capFor(id)
  local k = ruleKey(id)
  if k then return rules[k] end
  return math.max(0, math.floor(E.DEFAULT_KEEP or 256))
end

-- Change one item's target in neural.txt (the monitor's - / + buttons). Keeps every other line.
local function setRule(id, value)
  local key = ruleKey(id) or (id:match("^minecraft:") and pathOf(id) or id)
  local lines, done = {}, false
  if fs.exists(RULES_FILE) then
    local f = fs.open(RULES_FILE, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local item = line:gsub("#.*$", ""):match("^%s*([%w_:%.%-/]+)%s+%w+%s*$")
      if item and item:lower() == key then
        if not done then lines[#lines + 1] = key .. " " .. (value == 0 and "off" or tostring(value)) end
        done = true
      else
        lines[#lines + 1] = line
      end
    end
    f.close()
  else
    for _, l in ipairs(RULES_HEADER) do lines[#lines + 1] = l end
  end
  if not done then lines[#lines + 1] = key .. " " .. (value == 0 and "off" or tostring(value)) end
  local f = fs.open(RULES_FILE, "w")
  for _, l in ipairs(lines) do f.writeLine(l) end
  f.close()
  readRules()
end

---------------------------------------------------------------------------
-- Saved state (neural.cfg)
---------------------------------------------------------------------------
-- links[chamber] = { f = fab, l = lamp }; items[chamber] = what its fab makes; on[chamber] = running?
-- force[chamber] = "on" | "off" (nil = auto); stats[chamber] = { runs, preds, made }
-- train[chamber] = true while the chamber is on Training mode (spotted: matrices used, nothing made)
local cfg = { paused = false, links = {}, items = {}, on = {}, force = {}, stats = {}, made = {}, train = {} }
local function loadCfg()
  if not fs.exists(CFG_FILE) then return end
  local f = fs.open(CFG_FILE, "r")
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
  for _, k in ipairs({ "links", "items", "on", "force", "stats", "made", "train" }) do
    if type(cfg[k]) ~= "table" then cfg[k] = {} end
  end
end
local dirty, lastSave = false, -100
local function saveCfg(now)
  if not now and (not dirty or os.clock() - lastSave < 30) then return end
  local f = fs.open(CFG_FILE, "w")
  f.write(textutils.serialize(cfg))
  f.close()
  lastSave, dirty = os.clock(), false
end

---------------------------------------------------------------------------
-- Peripherals
---------------------------------------------------------------------------
local function call(name, method, ...)
  local ok, a, b = pcall(peripheral.call, name, method, ...)
  if ok then return a, b end
  return nil, a
end

local function isChamber(n)  return n:find("sim_chamber") ~= nil end
local function isFab(n)      return n:find("loot_fabricator") ~= nil end
local function isLamp(n)
  local l = n:lower()
  return l:find("redstone_relay") ~= nil or l:find("redstone_integrator") ~= nil or l:find("redstoneintegrator") ~= nil
end
local function isFurnator(n) return n:find("furnator") ~= nil end
local function numOf(n) return tonumber(n:match("_(%d+)$")) end
local function byNum(a, b)
  local x, y = numOf(a) or -1, numOf(b) or -1
  if x ~= y then return x < y end
  return a < b
end

local storageDocks = {}   -- storage's dock barrels (from its broadcast): finds ours if the cables are joined
local storageId, storageInput = nil, nil
local lastCountAsk = nil   -- storage computer's id and main input chest (from its broadcast)
-- L.out = where drops go (dock, or storage's input chest). L.direct = on storage's cable: no dock needed,
-- drops go straight into storage's input chest and storage delivers matrices and Furnator fuel itself.
local L = { chambers = {}, fabs = {}, lamps = {}, furnators = {}, cells = {}, dock = nil, dockNote = nil }

local function scan()
  local l = { chambers = {}, fabs = {}, lamps = {}, furnators = {}, cells = {}, dock = nil, dockNote = nil }
  local chests = {}
  local sides = {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, n in ipairs(peripheral.getNames()) do
    if not sides[n] then   -- only the cable: the monitor and modems sit on the computer's sides
      if isChamber(n) then l.chambers[#l.chambers + 1] = n
      elseif isFab(n) then l.fabs[#l.fabs + 1] = n
      elseif isLamp(n) then l.lamps[#l.lamps + 1] = n
      elseif isFurnator(n) then l.furnators[#l.furnators + 1] = n
      elseif n:find("hostilenetworks") then -- data center etc.: hands off
      elseif peripheral.hasType(n, "energy_storage") then l.cells[#l.cells + 1] = n
      elseif peripheral.hasType(n, "inventory") then chests[#chests + 1] = n
      end
    end
  end
  for _, k in ipairs({ "chambers", "fabs", "lamps", "furnators", "cells" }) do table.sort(l[k], byNum) end
  table.sort(chests)
  local want = tostring(E.DOCK or "")
  if want ~= "" then
    if peripheral.isPresent(want) then l.dock = want
    else l.dockNote = "DOCK=" .. want .. " isn't on the cable" end
  elseif storageInput and peripheral.isPresent(storageInput) then
    -- Same network as storage: no dock. Drops into its input chest, supplies asked for over rednet.
    l.direct = true
    l.dockNote = "On storage's network: drops go straight into storage"
  elseif #chests == 1 then
    l.dock = chests[1]
  elseif #chests > 1 then
    -- More than one: the lab cable is probably joined to the storage cable. Use the one storage
    -- treats as a dock (/dock); never guess a storage barrel.
    local docks = {}
    for _, c in ipairs(chests) do if storageDocks[c] then docks[#docks + 1] = c end end
    if #docks == 1 then
      l.dock = docks[1]
      l.dockNote = ("Lab cable joined to storage? Using storage's dock %s"):format(docks[1])
    elseif not storageSeen then
      l.dockNote = "Waiting to hear from storage"
    else
      l.dockNote = ("%d chests on the cable (joined to storage?): set DOCK= in neural.env"):format(#chests)
    end
  end
  l.out = l.direct and storageInput or l.dock
  L = l
end

-- Pair chambers with fabs (and lamps): manual PAIRS first, then sticky links, then new ones in order.
local function pairUp()
  local present = {}
  for _, k in ipairs({ "chambers", "fabs", "lamps" }) do for _, n in ipairs(L[k]) do present[n] = true end end
  local function find(list, num)
    for _, n in ipairs(list) do if numOf(n) == num then return n end end
  end
  local fixed = {}
  for entry in tostring(E.PAIRS or ""):gmatch("[^,;]+") do
    local c, f, l = entry:match("^%s*(%d+)%s*:%s*(%d+)%s*:?%s*(%d*)%s*$")
    local cn = c and find(L.chambers, tonumber(c))
    if cn then
      fixed[cn] = { f = find(L.fabs, tonumber(f)), l = l ~= "" and find(L.lamps, tonumber(l)) or nil, fixed = true }
    end
  end
  local links = {}
  for c, lk in pairs(cfg.links) do
    if present[c] then
      links[c] = { f = lk.f and present[lk.f] and lk.f or nil, l = lk.l and present[lk.l] and lk.l or nil }
    end
  end
  for c, lk in pairs(fixed) do
    links[c] = links[c] or {}
    if lk.f then links[c].f = lk.f end
    if lk.l then links[c].l = lk.l end
  end
  -- A fab or lamp claimed by a manual pair leaves any other chamber
  for c, lk in pairs(links) do
    for fc, fl in pairs(fixed) do
      if c ~= fc then
        if fl.f and lk.f == fl.f then lk.f = nil end
        if fl.l and lk.l == fl.l then lk.l = nil end
      end
    end
  end
  local usedF, usedL = {}, {}
  for _, lk in pairs(links) do
    if lk.f then usedF[lk.f] = true end
    if lk.l then usedL[lk.l] = true end
  end
  local freeF, freeL = {}, {}
  for _, f in ipairs(L.fabs) do if not usedF[f] then freeF[#freeF + 1] = f end end
  for _, l in ipairs(L.lamps) do if not usedL[l] then freeL[#freeL + 1] = l end end
  for _, c in ipairs(L.chambers) do
    links[c] = links[c] or {}
    if not links[c].f and #freeF > 0 then links[c].f = table.remove(freeF, 1); dirty = true end
  end
  for _, c in ipairs(L.chambers) do
    if not links[c].l and #freeL > 0 then links[c].l = table.remove(freeL, 1); dirty = true end
  end
  cfg.links = links
  for c in pairs(cfg.items) do if not present[c] then cfg.items[c] = nil end end
  for c in pairs(cfg.train) do if not present[c] then cfg.train[c] = nil end end
end

-- The monitor: the biggest one touching the computer, else one picked from the cable (shared/screens.lua,
-- docs/systems/screens.md). Asked once at boot; findMonitor only re-reads it. The kit's view gets its peripheral
-- name, so this is the one place that looks.
local scr = require("screens").new({ slots = { { id = "wall", label = "the neural lab screen", required = false, scale = 0.5 } } })
scr:open()
local function findMonitor() return scr:current("wall") end
local function repickMonitor() scr:repick("wall"); os.reboot() end

---------------------------------------------------------------------------
-- Storage's item counts (heard on tanis-base)
---------------------------------------------------------------------------
local storageItems, storageSeen = nil, nil
local function countsFresh() return storageSeen and os.clock() - storageSeen < 60 end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
-- P[chamber] = per-column state for the screen, the lamps and the network
local P = {}
local problems = {}
local note = "Starting"
local dockList, dockMatrices, dockFuel = {}, 0, 0
-- pct = what decisions use: the lower of the cells and the chambers' own buffers
local power = { pct = nil, cellPct = nil, simPct = nil, have = 0, cap = 0, source = "none" }
local furnatorFuel = 0

local function problem(key, on, msg)
  if on then problems[key] = msg else problems[key] = nil end
end

-- Drops still sitting in a fab's output slots (couldn't reach the dock): chamber -> { item = n }
local heldOut = {}
local function stockOf(id)
  local n = 0
  if storageItems then n = tonumber(storageItems[id]) or 0 end
  for _, it in pairs(dockList) do if it.name == id then n = n + it.count end end
  for _, t in pairs(heldOut) do n = n + (t[id] or 0) end   -- made, just not moved yet: still counts
  return n
end

local function shortName(id)
  if not id then return "?" end
  return pathOf(id):gsub("_", " ")
end

local function colNum(c)
  for i, x in ipairs(L.chambers) do if x == c then return i end end
  return 0
end

---------------------------------------------------------------------------
-- Moving things
---------------------------------------------------------------------------
local function readDock()
  dockList, dockMatrices, dockFuel = {}, 0, 0
  if L.direct then
    -- Drops still in storage's input chest count as stock; matrices and fuel are whatever storage has
    dockList = call(L.out, "list") or {}
    dockMatrices = storageItems and tonumber(storageItems[MATRIX]) or 0
    for _, f in ipairs(FUELS) do   -- only what storage will actually give (not the smelter's last stack)
      dockFuel = dockFuel + math.max(0, (storageItems and tonumber(storageItems[f]) or 0) - (SMELTER_RESERVE[f] or 0))
    end
    return
  end
  if not L.dock then return end
  dockList = call(L.dock, "list") or {}
  for _, it in pairs(dockList) do
    if it.name == MATRIX then dockMatrices = dockMatrices + it.count end
    if IS_FUEL[it.name] then dockFuel = dockFuel + it.count end
  end
end

-- Matrices we could hand out (nil = no idea: storage silent and nothing in a dock)
local function matrixSpare()
  local stored = countsFresh() and storageItems and (tonumber(storageItems[MATRIX]) or 0) or nil
  if L.direct then return stored end
  return dockMatrices + (stored or 0)
end

-- Bowerbird (the matrix-crafting turtle) reports what he's short of
local bird, birdSeen = nil, nil

local dockFull = false
-- Push a slot of a machine into the dock. Returns how many moved.
local function toDock(from, slot, count)
  if not L.out or count <= 0 then return 0 end
  local moved = call(from, "pushItems", L.out, slot, count) or 0
  if moved < count then dockFull = true end
  return moved
end

-- On storage's network: storage does the moves (it's the only computer that takes from storage).
-- Requests are collected during a pass and sent together; one outstanding ask per target.
local ops, asked = {}, {}
local firstUnanswered, lastAnswer = nil, nil   -- storage replying to our requests? (old storage script ignores them)
local ASK_AGAIN = 8      -- seconds before asking again for the same target
local function ask(to, item, count, slot)
  if count <= 0 or (asked[to] and os.clock() - asked[to] < ASK_AGAIN) then return end
  ops[#ops + 1] = { op = "fill", to = to, item = item, count = math.min(64, count), slot = slot }
  asked[to] = os.clock()
  firstUnanswered = firstUnanswered or os.clock()
end

-- Matrices from the dock into a chamber's input slot
local function feedMatrices(c, n)
  local moved = 0
  if n <= 0 then return 0 end
  if L.direct then
    if dockMatrices > 0 then ask(c, MATRIX, n, C_INPUT) end
    return 0   -- they arrive next pass
  end
  if not L.dock then return 0 end
  for slot, it in pairs(dockList) do
    if moved >= n then break end
    if it.name == MATRIX and it.count > 0 then
      local m = call(L.dock, "pushItems", c, slot, math.min(n - moved, it.count), C_INPUT) or 0
      it.count = it.count - m
      dockMatrices = dockMatrices - m
      moved = moved + m
      if m == 0 then break end   -- chamber refuses (no model, or the wrong kind of input)
    end
  end
  return moved
end

local function powerRead(n)
  local e, c = call(n, "getEnergy"), call(n, "getEnergyCapacity")
  return tonumber(e) or 0, tonumber(c) or 0
end

---------------------------------------------------------------------------
-- One column
---------------------------------------------------------------------------
local function column(c, lk, now)
  local p = P[c]
  local first = not p
  if not p then
    p = { lastUse = now, lastFab = now, usedSinceOut = 0, lastProbe = now }
    P[c] = p
  end
  p.c, p.f, p.l = c, lk.f, lk.l
  local st = cfg.stats[c] or { runs = 0, preds = 0, made = 0 }
  cfg.stats[c] = st
  local paused = cfg.paused

  local cl = call(c, "list") or {}
  local model, inp, base, pred = cl[C_MODEL], cl[C_INPUT], cl[C_BASE], cl[C_PRED]
  local matrices = inp and inp.count or 0

  -- Matrices used since last pass = runs started
  if p.mAfter and matrices < p.mAfter then
    local used = p.mAfter - matrices
    st.runs = st.runs + used
    p.usedSinceOut = p.usedSinceOut + used
    p.lastUse = now
    dirty = true
  end

  -- Inference makes a base drop every run (and usually predictions); Training makes neither.
  -- (First pass after a boot: what's sitting there may be old, so it proves nothing.)
  if first then p.bankAfter, p.baseAfter = pred and pred.count or 0, base and base.count or 0 end
  local made = not first and ((base ~= nil and base.count > (p.baseAfter or 0))
    or (pred ~= nil and pred.count > (p.bankAfter or 0)))
  if made then
    p.usedSinceOut = 0
    if cfg.train[c] then cfg.train[c] = nil; dirty = true end   -- back on Inference
    if not lk.f then p.noFabInfer, p.noFabAt = true, now end    -- Inference with nowhere to send predictions
  end
  if p.usedSinceOut >= 4 and not cfg.train[c] then
    cfg.train[c] = true; dirty = true                           -- matrices going in, nothing coming out
  end
  if cfg.train[c] then p.noFabInfer = nil end
  -- No fab and on Inference: try one matrix again now and then, in case it's been set to Training
  if p.noFabInfer and lk.f then p.noFabInfer = nil end
  if p.noFabInfer and (E.PROBE_EVERY or 0) > 0 and now - (p.noFabAt or now) > E.PROBE_EVERY * 60 then
    p.noFabInfer = nil
  end

  -- Generalized predictions go straight to the dock
  p.baseAfter = base and base.count or 0
  if base and not paused then p.baseAfter = base.count - toDock(c, C_BASE, base.count) end

  -- The model: who lives here
  if model then
    if model.name ~= p.modelName or not p.mob then
      local d = call(c, "getItemDetail", C_MODEL)
      local dn = d and d.displayName or "?"
      p.mob = dn:gsub("%s*[Dd]ata [Mm]odel%s*$", "")
      if p.mob == "" then p.mob = dn end
      p.modelName = model.name
    end
  else
    p.mob, p.modelName = nil, nil
  end
  p.bank = pred and pred.count or 0
  p.matrices = matrices
  p.cEnergy, p.cCap = powerRead(c)

  -- The fab: empty its outputs into the dock, learn what it makes
  local f = lk.f
  p.fin, p.fEnergy, p.fCap = 0, 0, 0
  local outNow = nil
  if f then
    local fl = call(f, "list") or {}
    p.fin = fl[F_IN] and fl[F_IN].count or 0
    p.fEnergy, p.fCap = powerRead(f)
    local held = {}
    for slot = 2, 17 do
      local it = fl[slot]
      if it then
        outNow = it.name
        local m = 0
        if not paused then
          m = toDock(f, slot, it.count)
          if m > 0 then
            st.made = st.made + m
            cfg.made[it.name] = (cfg.made[it.name] or 0) + m
            dirty = true
          end
        end
        if it.count - m > 0 then held[it.name] = (held[it.name] or 0) + it.count - m end
      end
    end
    heldOut[c] = held
    local left = 0
    for _, n in pairs(held) do left = left + n end
    -- Drops the fab couldn't hand over: no dock, or the dock is full (a full fab stops making more)
    p.outStuck = (left >= 32 and not paused) and (not L.out and "NO DOCK" or "DOCK FULL") or nil
    p.outLeft = left
    if p.finPrev and p.fin < p.finPrev then p.lastFab = now end
    if outNow then
      p.lastFab = now
      if p.probing then
        -- Same drop as before: wait twice as long next time. A change: back to the short wait.
        local gap = p.probeGap or E.PROBE_EVERY
        p.probeGap = (cfg.items[c] == outNow) and math.min(gap * 2, math.max(E.PROBE_EVERY, E.PROBE_MAX or 240))
          or E.PROBE_EVERY
      end
      p.probing = nil
      if cfg.items[c] and cfg.items[c] ~= outNow then
        p.switched = { from = cfg.items[c], to = outNow, at = now }
      end
      if cfg.items[c] ~= outNow then cfg.items[c] = outNow; dirty = true end
    end
  end
  local item = cfg.items[c]
  p.item = item
  p.cap = item and capFor(item) or nil
  p.stock = item and stockOf(item) or nil
  p.force = cfg.force[c]

  -- Decide: does this column want to run?
  local training = cfg.train[c] == true
  p.training = training
  local want, why = false, nil
  if not model then why = "nomodel"
  elseif paused then why = "paused"
  elseif p.force == "off" then why = "off"
  elseif training then
    -- Makes nothing, so no target: runs while there are spare matrices (TRAIN_KEEP stay for the fabs)
    local spare = matrixSpare()
    if p.force == "on" or (spare and spare > math.max(0, E.TRAIN_KEEP or 64)) then want, why = true, "training"
    else why = "trainwait" end
  elseif not f then
    -- No fab: one matrix tells us the mode (Training is fed, Inference just banks predictions)
    if p.noFabInfer then why = "nofab" else want, why = true, "findmode" end
  elseif p.force == "on" then want = true
  elseif not item then want, why = true, "learning"
  elseif not countsFresh() then
    want = tostring(E.WITHOUT_STORAGE):lower() == "run"
    why = "nocounts"
  else
    local cap = p.cap
    if cap <= 0 then want = false
    elseif p.stock >= cap then want = false
    elseif p.stock < cap * math.max(0, math.min(100, E.RESTART_AT)) / 100 then want = true
    else want = cfg.on[c] == true end
  end
  if model and f and not paused and not training and p.force == nil and item and countsFresh() then
    if cfg.on[c] ~= want then cfg.on[c] = want; dirty = true end
  end
  if p.checkReq and model and not paused then
    if f then p.probeWanted = true else p.noFabInfer = nil end   -- no fab: try a matrix to see its mode
    p.checkReq = nil
  end
  p.want, p.why = want, why
  return p
end

-- Second half of a column, after power priority is known: feed matrices and predictions.
local function act(p, allowed, now)
  local c, f = p.c, p.f
  if not p.mob or cfg.paused or (not f and not p.training and p.why ~= "findmode") then
    p.mAfter, p.running, p.needRuns, p.bankAfter = p.matrices, false, false, p.bank
    return
  end
  local run = p.want and allowed
  local learning = p.why == "learning"
  p.running = run
  if run then p.probeGap = nil end    -- after a run, start with the short wait again
  if run then p.probeWanted = nil end   -- a running column checks its fab with every batch anyway

  -- Predictions into the fab: while running, while learning, or one for a check
  if f and p.bank > 0 then
    local room = math.max(0, math.floor(E.FAB_HOLD or 2) - p.fin)
    local probeDue = not run and p.item and (E.PROBE_EVERY or 0) > 0 and p.fin == 0
      and (now - (p.lastProbe or now)) > math.min(p.probeGap or E.PROBE_EVERY, math.max(E.PROBE_EVERY, E.PROBE_MAX or 240)) * 60
    if (run or learning) and room > 0 then
      local m = call(c, "pushItems", f, C_PRED, math.min(room, p.bank), F_IN) or 0
      if m > 0 then
        cfg.stats[c].preds = cfg.stats[c].preds + m; dirty = true
        if p.fin == 0 then p.lastFab = now end   -- the fab's clock starts now, not when it last worked
        p.fin = p.fin + m
      end
      p.bank = p.bank - m
    elseif (p.probeWanted or probeDue) and p.fin == 0 then
      local m = call(c, "pushItems", f, C_PRED, 1, F_IN) or 0
      if m > 0 then
        cfg.stats[c].preds = cfg.stats[c].preds + 1
        p.bank, p.probing, p.probeWanted, p.lastProbe = p.bank - 1, now, nil, now
        p.lastFab, p.fin = now, p.fin + 1
      end
    end
  end

  -- Matrices into the chamber. Learning/checking with banked predictions needs no new runs.
  local needRuns = run and not (learning and (p.bank > 0 or p.fin > 0))
  if p.probeWanted and p.bank == 0 and p.fin == 0 then needRuns = true end   -- CHECK with nothing banked
  -- A stopped column keeps one prediction banked, so its periodic check can spot a changed fab
  p.banking = false
  if not run and not needRuns and f and not p.training and p.item and p.why ~= "off" and p.why ~= "nocounts" and (E.PROBE_EVERY or 0) > 0
    and p.bank == 0 and p.fin == 0 and allowed then
    needRuns, p.banking = true, true
  end
  if needRuns and p.matrices < math.max(1, math.floor(E.MATRIX_HOLD or 1)) then
    local m = feedMatrices(c, math.max(1, math.floor(E.MATRIX_HOLD or 1)) - p.matrices)
    p.matrices = p.matrices + m
  end
  if not needRuns then p.lastUse = now end
  p.mAfter = p.matrices
  p.needRuns = needRuns
  p.bankAfter = p.bank
end

-- How far a column is from its target, for the low-power pick (lowest runs first)
local function urgency(p)
  if p.force == "on" then return -1 end
  if p.training then return 2 end   -- levelling up can wait for the sun
  return (p.cap and p.cap > 0 and p.stock) and p.stock / p.cap or 0
end

---------------------------------------------------------------------------
-- Column state words (screen, lamps, network)
---------------------------------------------------------------------------
-- state, blink?, lamp on?
local function stateOf(p, now)
  if cfg.paused then return "PAUSED", false, false end
  if not p.mob then return "NO MODEL", true, false end
  if p.outStuck then return p.outStuck, true, false end
  if p.fabStuck then return p.fabStuck, true, false end
  if p.stuck then return p.stuck, true, false end
  if p.needRuns and not p.banking and p.matrices == 0 and dockMatrices <= 0 then return "NO MATRICES", true, false end
  if p.training then
    if p.running then return "TRAINING", false, true end
    if p.want then return "WAIT POWER", false, false end
    if p.why == "off" then return "OFF", false, false end
    return "TRAIN WAIT", false, false   -- saving the last TRAIN_KEEP matrices for the fabs
  end
  if not p.f then
    if p.why == "findmode" then return "CHECKING", true, false end   -- one matrix to see its mode
    if p.why == "off" then return "OFF", false, false end
    return "NO FAB", true, false
  end
  if p.why == "learning" or p.probing then return p.why == "learning" and "LEARNING" or "CHECKING", true, false end
  if p.running then return "RUNNING", false, true end
  if p.want and not p.running then return "WAIT POWER", false, false end
  if p.why == "off" then return "OFF", false, false end
  if p.why == "nocounts" then return "NO COUNTS", true, false end
  return "AT TARGET", false, false
end

---------------------------------------------------------------------------
-- One pass
---------------------------------------------------------------------------
local function pass()
  refreshEnv()
  refreshRules()
  scan()
  pairUp()
  readDock()
  dockFull = false
  local now = os.clock()

  -- Columns: read, empty outputs, decide
  local cols = {}
  local seen = {}
  for _, c in ipairs(L.chambers) do
    seen[c] = true
    cols[#cols + 1] = column(c, cfg.links[c] or {}, now)
  end
  for c in pairs(P) do if not seen[c] then P[c] = nil end end
  for c in pairs(heldOut) do if not seen[c] then heldOut[c] = nil end end
  readDock()   -- outputs just landed

  -- Power: every energy cell on the cable added up, and the chambers' own buffers (the chambers are
  -- what drains; fabs only draw while working, so they sit full and would hide a shortage).
  -- Decisions use the lower of the two: empty chambers mean low power even with full cells.
  local have, cap = 0, 0
  for _, n in ipairs(L.cells) do local e, x = powerRead(n); have, cap = have + e, cap + x end
  power.have, power.cap = have, cap
  power.cellPct = cap > 0 and math.floor(have / cap * 100 + 0.5) or nil
  -- Power doesn't spread evenly (machines nearer the generators fill first), so the FURNATOR
  -- watches the emptiest chamber; the overall figure uses all of them together.
  local sh, sc, low, lowName = 0, 0, nil, nil
  for _, p in ipairs(cols) do
    if p.mob and (p.cCap or 0) > 0 then
      sh, sc = sh + (p.cEnergy or 0), sc + p.cCap
      local pc = math.floor((p.cEnergy or 0) / p.cCap * 100 + 0.5)
      if not low or pc < low then low, lowName = pc, p.c end
    end
  end
  power.simPct = sc > 0 and math.floor(sh / sc * 100 + 0.5) or nil
  power.lowSim, power.lowSimName = low, lowName
  power.source = #L.cells > 0 and (#L.cells .. " cell" .. (#L.cells == 1 and "" or "s")) or "no cell on the cable"
  if power.cellPct and power.simPct then power.pct = math.min(power.cellPct, power.simPct)
  else power.pct = power.cellPct or power.simPct end

  -- Low power: only the column furthest below its target runs
  local only = nil
  if power.pct and power.pct < (E.LOW_POWER or 10) then
    local best, bestFrac = nil, nil
    for _, p in ipairs(cols) do
      if p.want then
        local frac = urgency(p)
        if not bestFrac or frac < bestFrac then best, bestFrac = p, frac end
      end
    end
    only = best
  end
  for _, p in ipairs(cols) do act(p, only == nil or only == p, now) end

  -- Stuck detection
  for _, p in ipairs(cols) do
    p.stuck, p.fabStuck = nil, nil
    if p.mob and not cfg.paused then
      local cNoPower = (p.cCap or 0) > 0 and (p.cEnergy or 0) < NO_POWER_FE
      local fNoPower = (p.fCap or 0) > 0 and (p.fEnergy or 0) < NO_POWER_FE
      if p.needRuns and p.matrices > 0 and now - p.lastUse > E.STALL_AFTER then
        -- Training stops taking matrices once the model is maxed (Self Aware)
        p.stuck = cNoPower and "NO POWER" or (p.training and "TRAINED?" or "STUCK")
      end
      if p.f and p.fin > 0 and now - p.lastFab > 30 then
        p.fabStuck = fNoPower and "FAB NO POWER" or (dockFull and "DOCK FULL" or "PICK A DROP")
      end
    end
    p.finPrev = p.fin
  end

  -- Furnator: backup power only. Fed while stored power is low.
  furnatorFuel = 0
  -- Fed while the cells OR any single chamber is under FUEL_BELOW
  local fuelBelow = E.FUEL_BELOW or 30
  local feeding = (power.pct ~= nil and power.pct < fuelBelow) or (power.lowSim ~= nil and power.lowSim < fuelBelow)
  for _, fz in ipairs(L.furnators) do
    local have = 0
    for _, it in pairs(call(fz, "list") or {}) do if IS_FUEL[it.name] then have = have + it.count end end
    if feeding and not cfg.paused and L.direct and have < (E.FURNATOR_KEEP or 8) then
      for _, name in ipairs(FUELS) do
        if storageItems and (tonumber(storageItems[name]) or 0) - (SMELTER_RESERVE[name] or 0) > 0 then
          ask(fz, name, (E.FURNATOR_KEEP or 8) - have); break
        end
      end
    elseif feeding and not cfg.paused and L.dock and have < (E.FURNATOR_KEEP or 8) then
      for _, name in ipairs(FUELS) do
        for slot, it in pairs(dockList) do
          if have >= (E.FURNATOR_KEEP or 8) then break end
          if it.name == name and it.count > 0 then
            local m = call(L.dock, "pushItems", fz, slot, math.min(it.count, (E.FURNATOR_KEEP or 8) - have)) or 0
            it.count, have, dockFuel = it.count - m, have + m, dockFuel - m
          end
        end
      end
    end
    furnatorFuel = furnatorFuel + have
  end

  -- Problems (alerts on the mainframe): rebuilt every pass, so nothing stale lingers
  for k in pairs(problems) do if k ~= "error" then problems[k] = nil end end
  local live = {}
  local anyWantsMatrix = false
  for _, p in ipairs(cols) do
    local n = colNum(p.c)
    local s, blink, on = stateOf(p, now)
    p.state, p.blink, p.lampOn = s, blink, on
    local who = ("Neural lab column %d (%s)"):format(n, p.mob or "empty")
    local key
    if s == "STUCK" then
      key = "stuck:" .. p.c
      problems[key] = who .. (p.f and ": the chamber has stopped. Check its redstone is Ignored, the model isn't Faulty and its output slots aren't full."
        or ": the chamber has stopped. No fab yet: is its prediction slot full? Take them out, or set it to Training.")
    elseif s == "NO POWER" then
      key = "power:" .. p.c
      if power.cellPct and power.cellPct >= 20 then
        problems[key] = who .. (": the chamber has no power, but the cells are at %d%%. Is it on the power line?"):format(power.cellPct)
      else
        problems[key] = who .. ": the chamber has no power."
      end
    elseif s == "TRAINED?" then
      key = "trained:" .. p.c
      problems[key] = who .. ": Training has stopped taking matrices, so the model is probably Self Aware. Switch the chamber to Inference"
        .. (p.f and "." or " once it has a fab.")
    elseif s == "NO FAB" then
      key = "nofab:" .. p.c
      problems[key] = who .. ": no fab yet, and the chamber is on Inference so it only banks predictions. Set it to Training to level the model while you wait (I'll feed it), or add a fab."
    elseif s == "FAB NO POWER" then
      key = "fabpower:" .. p.c
      problems[key] = who .. ": the fabricator has no power."
    elseif s == "PICK A DROP" then
      key = "pick:" .. p.c
      problems[key] = who .. ": the fabricator isn't making anything. Pick a drop in its screen."
    elseif s == "DOCK FULL" then
      key = "dockfull"
      problems[key] = L.direct and "Neural lab: storage's input chest won't take the drops (full?), they're piling up in the fabs."
        or "Neural lab: dock full, drops piling up in the fabs. Is the barrel a dock on storage (/dock)?"
    elseif s == "NO DOCK" then
      key = "dock"
      problems[key] = "Neural lab: no dock, drops piling up in the fabs. " .. (L.dockNote or "Put a barrel with a modem on the lab cable.")
    end
    if key then live[key] = true end
    if p.needRuns then anyWantsMatrix = true end
  end
  for k in pairs(problems) do
    if (k:match("^stuck:") or k:match("^power:") or k:match("^training:") or k:match("^trained:")
        or k:match("^nofab:") or k:match("^fabpower:")
        or k:match("^pick:") or k == "dockfull" or k == "dock") and not live[k] then
      problems[k] = nil
    end
  end
  local starving = false
  for _, p in ipairs(cols) do if p.state == "NO MATRICES" then starving = true end end
  local birdNote = ""
  if bird and birdSeen and os.clock() - birdSeen < 30 then
    if type(bird.missing) == "table" and #bird.missing > 0 then
      birdNote = " Bowerbird is short of " .. table.concat(bird.missing, ", ") .. "."
    elseif bird.state then
      birdNote = " Bowerbird: " .. tostring(bird.note or bird.state) .. "."
    end
  end
  problem("matrices", starving, (L.direct and "Neural lab: out of prediction matrices. Craft some and put them in storage."
    or "Neural lab: out of prediction matrices. Craft some: storage keeps the dock topped up (/dock on storage, pick the dock, keep prediction_matrix 64).") .. birdNote)
  if not live.dock then
    problem("dock", not L.out and #L.chambers > 0, L.dockNote and ("Neural lab: " .. L.dockNote)
      or "Neural lab: no dock barrel on the lab cable, so drops have nowhere to go.")
  end
  problem("counts", #L.chambers > 0 and not countsFresh() and tostring(E.WITHOUT_STORAGE):lower() ~= "run",
    storageSeen and ("Neural lab: haven't heard from storage for %ds, so every column is on hold. Is the storage computer running?"):format(math.floor(os.clock() - storageSeen))
    or "Neural lab: no item counts from storage yet, so every column is on hold. It needs a wireless/ender modem.")
  problem("fuel", feeding and #L.furnators > 0 and furnatorFuel == 0 and dockFuel <= 0,
    L.direct and ("Neural lab: power is at %s%% and storage has no spare charcoal or coal for the Furnator (it keeps the last 64 of each for the smelter)."):format(tostring(power.pct))
    or ("Neural lab: power is at %s%% and there's no charcoal or coal in the dock for the Furnator."):format(tostring(power.pct)))
  problem("ops", L.direct and firstUnanswered ~= nil and os.clock() - firstUnanswered > 20,
    "Neural lab: storage isn't answering my requests for matrices and fuel. Reboot the storage computer to update it.")

  -- Note
  local running, atTarget, attention, trainingN = 0, 0, 0, 0
  for _, p in ipairs(cols) do
    if p.state == "RUNNING" then running = running + 1
    elseif p.state == "AT TARGET" then atTarget = atTarget + 1
    elseif p.state == "TRAINING" or p.state == "TRAIN WAIT" then trainingN = trainingN + 1
    elseif p.state ~= "OFF" and p.state ~= "WAIT POWER" and p.state ~= "CHECKING" then attention = attention + 1 end
  end
  if #L.chambers == 0 then note = "No Simulation Chambers on my cable yet"
  elseif cfg.paused then note = "Paused"
  else
    note = ("%d running, %s%d at target%s"):format(running, trainingN > 0 and (trainingN .. " training, ") or "",
      atTarget, attention > 0 and (", " .. attention .. " need you") or "")
    if only then note = note .. ", low power" end
  end
  saveCfg()
end

---------------------------------------------------------------------------
-- Status lines (terminal, mainframe)
---------------------------------------------------------------------------
local function accText(st)
  if not st or (st.runs or 0) < 3 then return "acc ?" end
  return ("acc %d%%"):format(math.floor((st.preds or 0) / st.runs * 100 + 0.5))
end

local function stockText(p)
  if p.training then return "training model" end
  if not p.f then return "no fab yet" end
  if not p.item then return "item: learning" end
  local s = p.stock and tostring(p.stock) or "?"
  return ("%s %s/%s"):format(shortName(p.item), s, (p.cap or 0) == 0 and "off" or tostring(p.cap))
end

local function statusLines()
  local out = { note }
  out[#out + 1] = ("Power: cells %s (%s), chambers %s (lowest %s)%s. Matrices: %d %s"):format(
    power.cellPct and (power.cellPct .. "%") or "-", power.source, power.simPct and (power.simPct .. "%") or "-",
    power.lowSim and ("#" .. colNum(power.lowSimName) .. " " .. power.lowSim .. "%") or "-",
    #L.furnators > 0 and (", Furnator fuel " .. furnatorFuel) or "",
    dockMatrices, L.direct and "in storage" or ("in the dock" .. (storageItems and (", " .. (tonumber(storageItems[MATRIX]) or 0) .. " in storage") or "")))
  for i, c in ipairs(L.chambers) do
    local p = P[c]
    if p then
      out[#out + 1] = ("#%d %s: %s, %s, %s"):format(i, p.mob or "no model", p.state or "?", stockText(p),
        accText(cfg.stats[c]))
    end
  end
  if L.dockNote then out[#out + 1] = L.dockNote end
  return out
end

local function stateWord()
  if cfg.paused then return "paused" end
  if next(problems) then return "waiting" end
  return "running"
end

---------------------------------------------------------------------------
-- Lamps: steady = running, off = stopped, blinking = needs you
---------------------------------------------------------------------------
local lampWas = {}
local function setLamp(l, on)
  if lampWas[l] == on then return end
  for _, s in ipairs(rs.getSides()) do call(l, "setOutput", s, on) end
  lampWas[l] = on
end

local function lampLoop()
  local phase = false
  while true do
    phase = not phase
    local used = {}
    for _, c in ipairs(L.chambers) do
      local p = P[c]
      local lk = cfg.links[c]
      if p and lk and lk.l then
        used[lk.l] = true
        setLamp(lk.l, (p.blink and phase) or (not p.blink and p.lampOn == true))
      end
    end
    for _, l in ipairs(L.lamps) do if not used[l] then setLamp(l, false) end end
    os.sleep(0.75)
  end
end

---------------------------------------------------------------------------
-- What the screens and the typed commands can do (screens: neural_screens.lua)
---------------------------------------------------------------------------
local function setPaused(v)
  cfg.paused = v; dirty = true; saveCfg(true)
  note = v and "Paused" or "Running"
  os.queueEvent("neural_work")
end

local function setForce(c, v)
  cfg.force[c] = v; dirty = true; saveCfg(true)
  os.queueEvent("neural_work")
end

local function check(c)
  if P[c] then P[c].checkReq = true end
  os.queueEvent("neural_work")
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function workLoop()
  while true do
    local ok, err = pcall(pass)
    if not ok then note = "Error: " .. tostring(err); problem("error", true, "Neural lab error: " .. tostring(err))
    else problem("error", false) end
    os.queueEvent("neural_draw")
    local t = os.startTimer(math.max(1, E.TICK or 2))
    while true do
      local ev, a = os.pullEvent()
      if (ev == "timer" and a == t) or ev == "neural_work" then break end
    end
  end
end

local netOn = false
local function netLoop()
  if not netOn then return os.pullEvent("never") end
  local lastSend = -100
  while true do
    if os.clock() - lastSend >= 3 then
      local probs = {}
      for k, v in pairs(problems) do probs[k] = v end
      local cols = {}
      for i, c in ipairs(L.chambers) do
        local p = P[c] or {}
        cols[i] = { mob = p.mob, state = p.state, item = p.item, stock = p.stock, cap = p.cap, training = p.training }
      end
      rednet.broadcast({ type = "neural", id = os.getComputerID(), label = os.getComputerLabel() or "Neural lab",
        state = stateWord(), note = note, lines = statusLines(), problems = probs, columns = cols,
        power = power.pct, paused = cfg.paused }, BASE)
      lastSend = os.clock()
    end
    -- Supplies asked for this pass: one message to storage
    -- Supplies, plus a direct ask for the counts we need every 10 s: storage's status broadcast
    -- can go quiet for a while on a busy network, and without counts every column holds.
    if #ops > 0 or os.clock() - (lastCountAsk or -100) >= 10 then
      local want = { MATRIX }
      for _, f in ipairs(FUELS) do want[#want + 1] = f end
      for _, id in pairs(cfg.items) do want[#want + 1] = id end
      local req = { type = "neural_ops", id = os.epoch("utc"), ops = ops, want = want }
      if storageId then rednet.send(storageId, req, BASE)
      elseif #ops == 0 then rednet.broadcast(req, BASE) end   -- storage not heard yet: just ask for counts
      ops, lastCountAsk = {}, os.clock()
    end
    local from, msg = rednet.receive(BASE, 1)
    if type(msg) == "table" then
      if msg.type == "storage" and type(msg.items) == "table" then
        storageItems, storageSeen = msg.items, os.clock()
        storageId, storageInput = from, type(msg.mainInput) == "string" and msg.mainInput or nil
        if type(msg.docks) == "table" then
          storageDocks = {}
          for _, d in ipairs(msg.docks) do storageDocks[d] = true end
        end
      elseif msg.type == "neural_done" then
        firstUnanswered, lastAnswer = nil, os.clock()
        if type(msg.counts) == "table" then
          storageItems = storageItems or {}
          for id, n in pairs(msg.counts) do storageItems[id] = tonumber(n) or 0 end
          storageSeen = os.clock()
          storageId = storageId or from
        end
      elseif msg.type == "bowerbird" then
        bird, birdSeen = msg, os.clock()
      elseif msg.type == "neural_cmd" and (msg.to == nil or msg.to == os.getComputerID()) then
        if msg.want == "pause" then setPaused(true) elseif msg.want == "go" then setPaused(false) end
      end
    end
  end
end

-- The screens (neural_screens.lua): overview, column pages, reports and the typed commands
local screens = require("neural_screens")({
  snap = function()
    return { L = L, P = P, cfg = cfg, E = E, problems = problems, power = power, note = note, state = stateWord(),
             dockMatrices = dockMatrices, storageItems = storageItems, furnatorFuel = furnatorFuel }
  end,
  lines = statusLines, stockText = stockText, accText = accText, shortName = shortName, pathOf = pathOf,
  setPaused = setPaused, setForce = setForce, check = check, setRule = setRule, scan = scan, findMonitor = findMonitor, repickMonitor = repickMonitor, handle = function(...) scr:handle(...) end,
})

-- A wireless/ender modem reaches storage and the mainframe (the wired one is the lab cable)
peripheral.find("modem", function(name, m)
  if m.isWireless and m.isWireless() then rednet.open(name); netOn = true end
  return false
end)
readEnv()
readRules()
loadCfg()
scan()
scr:get("wall")
note = cfg.paused and "Paused" or "Starting"
parallel.waitForAny(workLoop, netLoop, lampLoop, screens.run)
