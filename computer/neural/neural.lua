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
--
-- Needs a wireless/ender modem too: it gets item counts from storage's broadcast and reports to
-- the mainframe (board row, alerts, "island neural"). Monitor touching the computer: tap a column
-- for its page. Terminal: status | list | pairs | check <n> | on/off/auto <n> | pause | resume.

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
local cfg = { paused = false, links = {}, items = {}, on = {}, force = {}, stats = {}, made = {} }
local function loadCfg()
  if not fs.exists(CFG_FILE) then return end
  local f = fs.open(CFG_FILE, "r")
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
  for _, k in ipairs({ "links", "items", "on", "force", "stats", "made" }) do
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
local storageId, storageInput = nil, nil   -- storage computer's id and main input chest (from its broadcast)
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
end

-- Only a monitor touching the computer
local mon
local function findMonitor()
  mon = nil
  for _, side in ipairs(rs.getSides()) do
    if not mon and peripheral.hasType(side, "monitor") then mon = peripheral.wrap(side); mon.setTextScale(0.5) end
  end
end

---------------------------------------------------------------------------
-- Storage's item counts (heard on tanis-base)
---------------------------------------------------------------------------
local storageItems, storageSeen = nil, nil
local function countsFresh() return storageSeen and os.clock() - storageSeen < 30 end

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

  -- Generalized predictions go straight to the dock
  if base and not paused then
    local m = toDock(c, C_BASE, base.count)
    if m > 0 then p.usedSinceOut = 0 end
  end
  if base then p.usedSinceOut = 0 end

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
  if pred then p.usedSinceOut = 0 end

  local item = cfg.items[c]
  p.item = item
  p.cap = item and capFor(item) or nil
  p.stock = item and stockOf(item) or nil
  p.force = cfg.force[c]

  -- Decide: does this column want to run?
  local want, why = false, nil
  if not model then why = "nomodel"
  elseif not f then why = "nofab"
  elseif paused then why = "paused"
  elseif p.force == "off" then why = "off"
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
  if model and f and not paused and p.force == nil and item and countsFresh() then
    if cfg.on[c] ~= want then cfg.on[c] = want; dirty = true end
  end
  if p.checkReq and model and f and not paused then p.probeWanted = true; p.checkReq = nil end
  p.want, p.why = want, why
  return p
end

-- Second half of a column, after power priority is known: feed matrices and predictions.
local function act(p, allowed, now)
  local c, f = p.c, p.f
  if not p.mob or not f or cfg.paused then
    p.mAfter, p.running, p.needRuns = p.matrices, false, false
    return
  end
  local run = p.want and allowed
  local learning = p.why == "learning"
  p.running = run
  if run then p.probeGap = nil end    -- after a run, start with the short wait again
  if run then p.probeWanted = nil end   -- a running column checks its fab with every batch anyway

  -- Predictions into the fab: while running, while learning, or one for a check
  if p.bank > 0 then
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
  if not run and not needRuns and p.item and p.why ~= "off" and p.why ~= "nocounts" and (E.PROBE_EVERY or 0) > 0
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
end

---------------------------------------------------------------------------
-- Column state words (screen, lamps, network)
---------------------------------------------------------------------------
-- state, blink?, lamp on?
local function stateOf(p, now)
  if cfg.paused then return "PAUSED", false, false end
  if not p.mob then return "NO MODEL", true, false end
  if not p.f then return "NO FAB", true, false end
  if p.outStuck then return p.outStuck, true, false end
  if p.fabStuck then return p.fabStuck, true, false end
  if p.stuck then return p.stuck, true, false end
  if p.needRuns and not p.banking and p.matrices == 0 and dockMatrices <= 0 then return "NO MATRICES", true, false end
  if p.why == "learning" or p.probing then return p.why == "learning" and "LEARNING" or "CHECKING", true, false end
  if p.running then return "RUNNING", false, true end
  if p.want and not p.running then return "WAIT POWER", false, false end
  if p.why == "off" then return "OFF", false, false end
  if p.why == "nocounts" then return "NO COUNTS", true, false end
  return "AT TARGET", false, false
end

local STATE_COL = {
  RUNNING = colours.lime, LEARNING = colours.cyan, CHECKING = colours.cyan, ["AT TARGET"] = colours.lightBlue,
  OFF = colours.lightGrey, PAUSED = colours.orange, ["WAIT POWER"] = colours.yellow,
}

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
        local frac = (p.cap and p.cap > 0 and p.stock) and p.stock / p.cap or 0
        if p.force == "on" then frac = -1 end
        if not bestFrac or frac < bestFrac then best, bestFrac = p, frac end
      end
    end
    only = best
  end
  for _, p in ipairs(cols) do act(p, only == nil or only == p, now) end

  -- Stuck detection
  for _, p in ipairs(cols) do
    p.stuck, p.fabStuck = nil, nil
    if p.mob and p.f and not cfg.paused then
      local cNoPower = (p.cCap or 0) > 0 and (p.cEnergy or 0) < NO_POWER_FE
      local fNoPower = (p.fCap or 0) > 0 and (p.fEnergy or 0) < NO_POWER_FE
      if p.needRuns and p.matrices > 0 and now - p.lastUse > E.STALL_AFTER then
        p.stuck = cNoPower and "NO POWER" or "STUCK"
      elseif p.usedSinceOut >= 4 then
        p.stuck = "TRAINING?"   -- using matrices, making nothing
      end
      if p.fin > 0 and now - p.lastFab > 30 then
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

  -- Problems (alerts on the mainframe)
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
      problems[key] = who .. ": the chamber has stopped. Check it's on Inference (not Training), redstone Ignored, and the model isn't Faulty."
    elseif s == "NO POWER" then
      key = "power:" .. p.c
      if power.cellPct and power.cellPct >= 20 then
        problems[key] = who .. (": the chamber has no power, but the cells are at %d%%. Is it on the power line?"):format(power.cellPct)
      else
        problems[key] = who .. ": the chamber has no power."
      end
    elseif s == "TRAINING?" then
      key = "training:" .. p.c
      problems[key] = who .. ": using matrices but making nothing. Is the chamber on Training mode? Switch it to Inference."
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
    if (k:match("^stuck:") or k:match("^power:") or k:match("^training:") or k:match("^fabpower:")
        or k:match("^pick:") or k == "dockfull" or k == "dock") and not live[k] then
      problems[k] = nil
    end
  end
  local starving = false
  for _, p in ipairs(cols) do if p.state == "NO MATRICES" then starving = true end end
  problem("matrices", starving, L.direct and "Neural lab: out of prediction matrices. Craft some and put them in storage."
    or "Neural lab: out of prediction matrices. Craft some: storage keeps the dock topped up (/dock on storage, pick the dock, keep prediction_matrix 64).")
  if not live.dock then
    problem("dock", not L.out and #L.chambers > 0, L.dockNote and ("Neural lab: " .. L.dockNote)
      or "Neural lab: no dock barrel on the lab cable, so drops have nowhere to go.")
  end
  problem("counts", #L.chambers > 0 and not countsFresh() and tostring(E.WITHOUT_STORAGE):lower() ~= "run",
    "Neural lab: no item counts from storage, so every column is on hold. It needs a wireless/ender modem.")
  problem("fuel", feeding and #L.furnators > 0 and furnatorFuel == 0 and dockFuel <= 0,
    L.direct and ("Neural lab: power is at %s%% and storage has no spare charcoal or coal for the Furnator (it keeps the last 64 of each for the smelter)."):format(tostring(power.pct))
    or ("Neural lab: power is at %s%% and there's no charcoal or coal in the dock for the Furnator."):format(tostring(power.pct)))
  problem("ops", L.direct and firstUnanswered ~= nil and os.clock() - firstUnanswered > 20,
    "Neural lab: storage isn't answering my requests for matrices and fuel. Reboot the storage computer to update it.")

  -- Note
  local running, atTarget, attention = 0, 0, 0
  for _, p in ipairs(cols) do
    if p.state == "RUNNING" then running = running + 1
    elseif p.state == "AT TARGET" then atTarget = atTarget + 1
    elseif p.state ~= "OFF" and p.state ~= "WAIT POWER" then attention = attention + 1 end
  end
  if #L.chambers == 0 then note = "No Simulation Chambers on my cable yet"
  elseif cfg.paused then note = "Paused"
  else
    note = ("%d running, %d at target%s"):format(running, atTarget, attention > 0 and (", " .. attention .. " need you") or "")
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
-- Monitor
---------------------------------------------------------------------------
local hits = {}
local view = { page = nil, list = 1 }   -- page = chamber name, or nil for the overview

local function hit(x1, x2, y1, y2, fn) hits[#hits + 1] = { x1 = x1, x2 = x2, y1 = y1, y2 = y2 or y1, fn = fn } end

local function bar(m, x, y, w, frac, col)
  if w <= 0 then return end
  local fill = math.max(0, math.min(w, math.floor(w * frac + 0.5)))
  m.setCursorPos(x, y)
  m.setBackgroundColour(col); m.write((" "):rep(fill))
  m.setBackgroundColour(colours.grey); m.write((" "):rep(w - fill))
  m.setBackgroundColour(colours.black)
end

local function btn(m, x, y, label, bg, fn)
  m.setCursorPos(x, y); m.setBackgroundColour(bg); m.setTextColour(colours.black); m.write(label)
  m.setBackgroundColour(colours.black)
  hit(x, x + #label - 1, y, y, fn)
  return x + #label + 1
end

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

local function header(m, w, title, back)
  m.setCursorPos(1, 1); m.setBackgroundColour(colours.grey); m.clearLine()
  m.setTextColour(colours.white)
  if back then
    m.setBackgroundColour(colours.lightGrey); m.setTextColour(colours.black); m.write(" < ")
    hit(1, 3, 1, 1, function() view.page = nil end)
    m.setBackgroundColour(colours.grey); m.setTextColour(colours.white)
  end
  m.write(" " .. title:sub(1, math.max(0, w - 12)))
  local label = cfg.paused and " RUN " or " PAUSE "
  local bx = w - #label + 1
  m.setCursorPos(bx, 1)
  m.setBackgroundColour(cfg.paused and colours.green or colours.orange); m.setTextColour(colours.black)
  m.write(label)
  hit(bx, w, 1, 1, function() setPaused(not cfg.paused) end)
  m.setBackgroundColour(colours.black)
end

local function powerLine(m, w, y)
  m.setCursorPos(2, y); m.setTextColour(colours.lightGrey)
  local txt = "Power " .. (power.pct and (power.pct .. "%") or "?") .. " "
  if power.lowSim and power.lowSim < (E.FUEL_BELOW or 30) and (not power.pct or power.lowSim < power.pct) then
    txt = ("Sim #%d %d%% "):format(colNum(power.lowSimName), power.lowSim)   -- one chamber is starving: say which
  elseif power.cellPct and power.simPct and power.simPct + 10 < power.cellPct then
    txt = ("Sims %d%% "):format(power.simPct)   -- the chambers are the bottleneck: say so
  end
  m.write(txt)
  local tail = #L.furnators > 0 and (" Furnator " .. furnatorFuel) or ""
  local bw = math.max(0, w - 2 - #txt - #tail - 1)
  local frac = (power.pct or 0) / 100
  bar(m, 2 + #txt, y, bw, frac, (power.pct or 0) < (E.LOW_POWER or 10) and colours.red or colours.lime)
  m.setCursorPos(2 + #txt + bw, y); m.setTextColour(colours.lightGrey); m.write(tail)
end

local function drawOverview(m, w, h)
  header(m, w, w >= 30 and "NEURAL LAB" or "NEURAL", false)
  powerLine(m, w, 2)
  m.setCursorPos(2, 3); m.setTextColour(colours.lightGrey)
  m.write((L.direct and ("Matrices %d in storage"):format(dockMatrices) or ("Matrices %d here%s"):format(dockMatrices,
    storageItems and (", " .. (tonumber(storageItems[MATRIX]) or 0) .. " stored") or "")):sub(1, w - 2))
  m.setCursorPos(2, 4); m.setTextColour(next(problems) and colours.yellow or colours.white)
  m.write(note:sub(1, w - 2))
  -- The most useful problem, in words (the cards only have room for a state)
  local first
  for _, k in ipairs({ "ops", "dock", "dockfull", "counts", "fuel", "matrices", "error" }) do
    if problems[k] then first = problems[k]; break end
  end
  if not first then for _, v in pairs(problems) do first = v; break end end
  if first then
    m.setCursorPos(2, 5); m.setTextColour(colours.red)
    m.write((first:gsub("^Neural lab:? ?", "")):sub(1, w - 2))
  end

  local top = 6
  if #L.chambers == 0 then
    m.setCursorPos(2, top); m.setTextColour(colours.yellow)
    m.write(("No chambers on the cable yet."):sub(1, w - 2))
    return
  end
  -- As many cards per row as fit at 17+ characters each (a long wall needs a dense overview)
  local perRow = math.max(1, math.floor((w - 1) / 18))
  local cardW = math.min(24, math.max(12, math.floor((w - 1) / perRow) - 1))
  local cardH = 5
  local rowsFit = math.max(1, math.floor((h - top) / cardH))
  local perPage = perRow * rowsFit
  local pages = math.max(1, math.ceil(#L.chambers / perPage))
  if view.list > pages then view.list = pages end
  local first = (view.list - 1) * perPage + 1
  for i = first, math.min(#L.chambers, first + perPage - 1) do
    local c = L.chambers[i]
    local p = P[c] or {}
    local k = i - first
    local x = 2 + (k % perRow) * (cardW + 1)
    local y = top + math.floor(k / perRow) * cardH
    local s = p.state or "?"
    local col = STATE_COL[s] or colours.red
    m.setCursorPos(x, y); m.setTextColour(colours.white)
    m.write(("#%d %s"):format(i, p.mob or "empty"):sub(1, cardW))
    m.setCursorPos(x, y + 1); m.setTextColour(col); m.write(s:sub(1, cardW))
    m.setCursorPos(x, y + 2); m.setTextColour(colours.lightGrey); m.write(stockText(p):sub(1, cardW))
    m.setCursorPos(x, y + 3); m.setTextColour(colours.grey); m.write(accText(cfg.stats[c]):sub(1, cardW - 8))
    hit(x, x + cardW - 1, y, y + 2, function() view.page = c end)
    if p.mob and p.f then
      btn(m, x + cardW - 7, y + 3, " CHECK ", colours.cyan, function() check(c) end)
    end
  end
  if pages > 1 then
    local y = h
    m.setCursorPos(2, y); m.setTextColour(colours.lightGrey)
    btn(m, 2, y, " < ", colours.lightGrey, function() view.list = math.max(1, view.list - 1) end)
    m.setCursorPos(6, y); m.setTextColour(colours.white); m.write(("%d/%d"):format(view.list, pages))
    btn(m, 12, y, " > ", colours.lightGrey, function() view.list = math.min(pages, view.list + 1) end)
  end
end

local function drawPage(m, w, h, c)
  local p = P[c]
  if not p then view.page = nil; return drawOverview(m, w, h) end
  local i = colNum(c)
  header(m, w, ("#%d %s"):format(i, p.mob or "empty"), true)
  local y = 3
  local function line(text, col)
    if y > h then return end
    m.setCursorPos(2, y); m.setTextColour(col or colours.lightGrey); m.write(tostring(text):sub(1, w - 2)); y = y + 1
  end
  local s = p.state or "?"
  line(s, STATE_COL[s] or colours.red)
  if p.item then
    line("Fab makes: " .. shortName(p.item), colours.white)
  else
    line("Fab makes: not seen yet", colours.white)
  end
  if p.switched and os.clock() - p.switched.at < 120 then
    line(("Switched from %s"):format(shortName(p.switched.from)), colours.cyan)
  end
  line("Pick it in the fab's screen", colours.grey)
  y = y + 1
  if p.item then
    local cap = p.cap or 0
    line(("Stock %s / %s"):format(p.stock and tostring(p.stock) or "?", cap == 0 and "off" or tostring(cap)), colours.white)
    if y <= h then
      bar(m, 2, y, math.max(4, w - 4), cap > 0 and math.min(1, (p.stock or 0) / cap) or 0, colours.lightBlue); y = y + 1
    end
    if y <= h then
      m.setCursorPos(2, y); m.setTextColour(colours.lightGrey); m.write("Target ")
      local x = 9
      local step = cap >= 256 and 64 or 16
      x = btn(m, x, y, " - ", colours.lightGrey, function() setRule(p.item, math.max(0, cap - step)) end)
      m.setCursorPos(x, y); m.setTextColour(colours.white)
      local t = cap == 0 and "off" or tostring(cap)
      m.write(t); x = x + #t + 1
      btn(m, x, y, " + ", colours.lightGrey, function() setRule(p.item, cap + step) end)
      y = y + 2
    end
  end
  if y <= h then
    m.setCursorPos(2, y); m.setTextColour(colours.lightGrey); m.write("Mode ")
    local x = 7
    local cur = cfg.force[c]
    x = btn(m, x, y, " AUTO ", cur == nil and colours.lime or colours.lightGrey, function() setForce(c, nil) end)
    x = btn(m, x, y, " ON ", cur == "on" and colours.lime or colours.lightGrey, function() setForce(c, "on") end)
    x = btn(m, x, y, " OFF ", cur == "off" and colours.orange or colours.lightGrey, function() setForce(c, "off") end)
    if p.mob and p.f then
      if x + 7 > w then y = y + 2; x = 7 end   -- narrow screen: CHECK on its own row
      btn(m, x, y, " CHECK ", colours.cyan, function() check(c) end)
    end
    y = y + 2
  end
  local st = cfg.stats[c] or {}
  line(("Runs %d, preds %d, %s"):format(st.runs or 0, st.preds or 0, accText(st)))
  line(("Made %d, banked %d, in fab %d"):format(st.made or 0, p.bank or 0, p.fin or 0))
  line(("Matrices %d, C%d%% F%d%%"):format(p.matrices or 0,
    (p.cCap or 0) > 0 and math.floor(p.cEnergy / p.cCap * 100) or 0, (p.fCap or 0) > 0 and math.floor(p.fEnergy / p.fCap * 100) or 0))
  y = y + 1
  line(c, colours.grey)
  line(p.f or "no fab paired", colours.grey)
  line(p.l or "no lamp", colours.grey)
  for k, msg in pairs(problems) do
    if k:match("^[^:]+:(.*)$") == c then line((msg:gsub("^Neural lab column %d+ %b(): ", "")), colours.red) end
  end
end

local function draw()
  if not mon then return end
  local w, h = mon.getSize()
  if not w then findMonitor(); return end
  hits = {}
  mon.setBackgroundColour(colours.black); mon.clear()
  if view.page then drawPage(mon, w, h, view.page) else drawOverview(mon, w, h) end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function workLoop()
  while true do
    local ok, err = pcall(pass)
    if not ok then note = "Error: " .. tostring(err); problem("error", true, "Neural lab error: " .. tostring(err))
    else problem("error", false) end
    pcall(draw)
    local t = os.startTimer(math.max(1, E.TICK or 2))
    while true do
      local ev, a = os.pullEvent()
      if (ev == "timer" and a == t) or ev == "neural_work" then break end
    end
  end
end

local function eventLoop()
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" and mon and peripheral.getName(mon) == a then
      for _, hz in ipairs(hits) do
        if b >= hz.x1 and b <= hz.x2 and c >= hz.y1 and c <= hz.y2 then pcall(hz.fn); break end
      end
      pcall(draw)
    elseif ev == "peripheral" or ev == "peripheral_detach" then
      findMonitor()
      os.queueEvent("neural_work")   -- a new column (or a removed one): pick it up now
    elseif ev == "monitor_resize" then
      findMonitor(); pcall(draw)
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
        cols[i] = { mob = p.mob, state = p.state, item = p.item, stock = p.stock, cap = p.cap }
      end
      rednet.broadcast({ type = "neural", id = os.getComputerID(), label = os.getComputerLabel() or "Neural lab",
        state = stateWord(), note = note, lines = statusLines(), problems = probs, columns = cols,
        power = power.pct, paused = cfg.paused }, BASE)
      lastSend = os.clock()
    end
    -- Supplies asked for this pass: one message to storage
    if #ops > 0 and storageId then
      rednet.send(storageId, { type = "neural_ops", id = os.epoch("utc"), ops = ops }, BASE)
      ops = {}
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
      elseif msg.type == "neural_cmd" and (msg.to == nil or msg.to == os.getComputerID()) then
        if msg.want == "pause" then setPaused(true) elseif msg.want == "go" then setPaused(false) end
      end
    end
  end
end

local function help()
  print("status          what's going on")
  print("list            what I found on my cable")
  print("pairs           which fab and lamp go with each chamber")
  print("check <n>       send one prediction through column n's fab")
  print("on|off|auto <n> force column n on / off, or back to its target")
  print("pause | resume")
  print("Settings: neural.env  Targets: neural.txt")
end

local function terminalLoop()
  term.clear(); term.setCursorPos(1, 1)
  print("Neural lab online.")
  help()
  while true do
    print()
    write("neural> ")
    local q = read():lower()
    local cmd, arg = q:match("^%s*(%a+)%s*(%d*)")
    local n = tonumber(arg)
    local c = n and L.chambers[n]
    if cmd == "list" then
      scan()
      print("Chambers:  " .. (#L.chambers > 0 and table.concat(L.chambers, ", ") or "none"))
      print("Fabs:      " .. (#L.fabs > 0 and table.concat(L.fabs, ", ") or "none"))
      print("Lamps:     " .. (#L.lamps > 0 and table.concat(L.lamps, ", ") or "none"))
      print("Furnators: " .. (#L.furnators > 0 and table.concat(L.furnators, ", ") or "none"))
      print("Power:     " .. (#L.cells > 0 and table.concat(L.cells, ", ") or "none (using the machines' own)"))
      print("Drops to:  " .. (L.direct and ("storage's input chest " .. tostring(L.out)) or tostring(L.dock or "no dock")))
      if L.dockNote then printError(L.dockNote) end
    elseif cmd == "pairs" then
      for i, ch in ipairs(L.chambers) do
        local lk = cfg.links[ch] or {}
        print(("#%d %s"):format(i, ch))
        print(("   fab %s, lamp %s"):format(tostring(lk.f or "none"), tostring(lk.l or "none")))
      end
      print("Wrong? PAIRS= in neural.env, e.g. PAIRS=3:5:2")
    elseif cmd == "check" and c then
      check(c); print("Checking column " .. n .. ".")
    elseif (cmd == "on" or cmd == "off") and c then
      setForce(c, cmd); print(("Column %d forced %s."):format(n, cmd))
    elseif cmd == "auto" and c then
      setForce(c, nil); print(("Column %d back on its target."):format(n))
    elseif cmd == "pause" or cmd == "stop" then
      setPaused(true); print("Paused.")
    elseif cmd == "resume" or cmd == "go" or cmd == "run" then
      setPaused(false); print("Running.")
    elseif cmd == "status" or q:match("^%s*$") then
      for _, l in ipairs(statusLines()) do print(l) end
      for _, msg in pairs(problems) do printError(msg) end
    else
      if (cmd == "check" or cmd == "on" or cmd == "off" or cmd == "auto") and not c then
        printError("Which column? e.g. " .. cmd .. " 1")
      end
      help()
    end
  end
end

-- A wireless/ender modem reaches storage and the mainframe (the wired one is the lab cable)
peripheral.find("modem", function(name, m)
  if m.isWireless and m.isWireless() then rednet.open(name); netOn = true end
  return false
end)
readEnv()
readRules()
loadCfg()
findMonitor()
scan()
note = cfg.paused and "Paused" or "Starting"
parallel.waitForAny(workLoop, eventLoop, netLoop, lampLoop, terminalLoop)
