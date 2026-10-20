-- fm_reg.lua  --  Foreman engine: the registry (numbers, orders, reboots), presets and rules, saved in P.config.
-- A part of fm.lua (one shared environment: see there).
SEND_EVERY = 3     -- seconds between order broadcasts
STALE      = 15    -- seconds without news before a miner greys out
TEXT_SCALE = 0.5
TICK       = 2     -- seconds between barrel passes
HOLD_FOR   = 90    -- seconds a dock stays untouched while its miner takes his supplies
RING_CAP   = 16    -- furthest CHUNK ring (33x33 chunks; matches miner.lua)
NAME_MAX   = 16
REBOOT_WAIT = 600000 -- ms: stop asking a miner to reboot if it hasn't confirmed by then
PROTOCOL, BASE = P.protocol, "tanis-base"
DEF_R2, Y_MIN, Y_MAX = P.defR2, P.yMin, P.yMax
WORK = "fm_work"   -- event: a barrel pass now
ONE = P.one or P.bird   -- "every Firecrest", or "every miner" on the Overworld Foreman

---------------------------------------------------------------------------
-- Registry: every miner ever seen, keyed by computer ID (cfg[P.regKey], also called `reg`)
--   { num, label, retired, want, minY, maxY, r1, r2, seq, pMin, pMax, pR1, pR2 }
--   minY/maxY/r1/r2 = the order it's running; pMin/pMax/pR1/pR2 = picked on screen, sent on START.
-- Presets: list of { name, minY, maxY, r1, r2 }.
---------------------------------------------------------------------------
cfg = { nextNum = 1, retiredNums = {}, presets = nil }
reg = {}
cfg[P.regKey] = reg
local CFG_KEYS = { "docks", "outputs", "stocks", "inputs", "ignored", "factoryIns", "factoryOuts", "overflows",
  "names", "dockFor", "keep", "junk", "hungryAt", "fullAt", "sent" }
LIST_KEYS = { "docks", "outputs", "stocks", "inputs", "ignored", "factoryIns", "factoryOuts", "overflows" }

function copyPreset(p) return { name = p.name, minY = p.minY, maxY = p.maxY, r1 = p.r1, r2 = p.r2 } end
function loadCfg()
  if fs.exists(P.config) then
    local f = fs.open(P.config, "r"); local t = textutils.unserialize(f.readAll()); f.close()
    if type(t) == "table" then
      cfg.nextNum = tonumber(t.nextNum) or 1
      reg = type(t[P.regKey]) == "table" and t[P.regKey]
        or P.oldKey and type(t[P.oldKey]) == "table" and t[P.oldKey] or {}  -- saved before the Oct 2026 rename
      cfg.retiredNums = type(t.retiredNums) == "table" and t.retiredNums or {}
      -- Labels from before the rename (Pigger-04 -> Firecrest-04)
      if P.oldPrefix then
        local function rename(l) return type(l) == "string" and (l:gsub("^" .. P.oldPrefix .. "%-", P.bird .. "-")) or l end
        for _, dd in pairs(reg) do dd.label = rename(dd.label) end
        for n, l in pairs(cfg.retiredNums) do cfg.retiredNums[n] = rename(l) end
      end
      cfg.presets = type(t.presets) == "table" and t.presets or nil
      cfg.chunkRings = t.chunkRings
      for _, k in ipairs(CFG_KEYS) do cfg[k] = t[k] end
      cfg.handedOver, cfg.imported = t.handedOver, t.imported
    end
  end
  cfg[P.regKey] = reg
  if P.oldKey then cfg[P.oldKey] = nil end
  for _, k in ipairs(LIST_KEYS) do cfg[k] = type(cfg[k]) == "table" and cfg[k] or {} end
  cfg.names = type(cfg.names) == "table" and cfg.names or {}
  cfg.dockFor = type(cfg.dockFor) == "table" and cfg.dockFor or {}
  cfg.sent = type(cfg.sent) == "table" and cfg.sent or {}
  if type(cfg.keep) ~= "table" then cfg.keep = {}; for k, v in pairs(P.keep or {}) do cfg.keep[k] = v end end
  if type(cfg.junk) ~= "table" then cfg.junk = {}; for i, v in ipairs(P.junk or {}) do cfg.junk[i] = v end end
  cfg.hungryAt, cfg.fullAt = tonumber(cfg.hungryAt) or 25, tonumber(cfg.fullAt) or 75
  if not cfg.presets then
    cfg.presets = {}
    for _, p in ipairs(P.presets) do cfg.presets[#cfg.presets + 1] = copyPreset(p) end
  end
  for _, p in ipairs(cfg.presets) do p.r1, p.r2 = p.r1 or 1, p.r2 or DEF_R2 end
  for _, dd in pairs(reg) do  -- entries from before rings were adjustable (or with no range at all)
    dd.r1, dd.r2 = dd.r1 or 1, dd.r2 or DEF_R2
    dd.pR1, dd.pR2 = dd.pR1 or dd.r1, dd.pR2 or dd.r2
    dd.pMin, dd.pMax = dd.pMin or dd.minY or P.newEntry.minY, dd.pMax or dd.maxY or P.newEntry.maxY
    dd.minY, dd.maxY = dd.minY or dd.pMin, dd.maxY or dd.pMax
  end
  -- Oct 2026: rings are CHUNK rings now (miners work chunk by chunk: ring 0 = the dock's chunk).
  -- Saved block rings are converted once (50 blocks -> 3 chunk rings, "from ring 1" -> 0).
  if not cfg.chunkRings then
    local function toC(r) return math.max(0, math.min(RING_CAP, math.floor((tonumber(r) or 0) / 16))) end
    local function fix(t, a, b)
      local x, y = toC(t[a]), toC(t[b])
      if (tonumber(t[a]) or 1) <= 1 then x = 0 end
      t[a], t[b] = math.min(x, y), y
    end
    for _, p in ipairs(cfg.presets) do fix(p, "r1", "r2") end
    for _, dd in pairs(reg) do fix(dd, "r1", "r2"); fix(dd, "pR1", "pR2") end
    cfg.chunkRings = true
  end
end
function saveCfg()
  local f = fs.open(P.config, "w"); f.write(textutils.serialize(cfg)); f.close()
end

function newEntry(num)
  local a, b = P.newEntry.minY, P.newEntry.maxY
  return { num = num, want = "dock", minY = a, maxY = b, pMin = a, pMax = b,
           r1 = 0, r2 = DEF_R2, pR1 = 0, pR2 = DEF_R2, seq = os.epoch("utc") }
end
function numTaken(num, exceptId)
  if cfg.retiredNums[num] then return true end
  for id, d in pairs(reg) do
    if id ~= exceptId and d.num == num and not d.retired then return true end
  end
  return false
end
-- Firecrest-01; a Foreman that numbers more than one bird (the Overworld Foreman: Canary, Starling) names
-- each after the bird it says it is
function nameOf(num, bird) return ("%s-%02d"):format(P.birdNames[bird] and bird or P.bird, num) end

live = {}        -- id -> { s = last status, seen = os.clock() }
radioOK = nil    -- false = no ender/wireless modem on this computer: the miners can't hear it
capped = {}      -- junk storage has plenty of (from the storage computer, or the Overworld Foreman)
storageSeen = nil
sendNow = {}     -- id -> true: send its order on the next pass

-- A miner asks for a number. Same computer keeps its number; a hint (its old label) is honoured
-- if free; otherwise the next number. Retired numbers are never reused.
function assign(id, hint, bird)
  local d = reg[id]
  if d and not d.retired then return d.num end
  local num = tonumber(hint)
  if not num or num < 1 or numTaken(num, id) then
    num = cfg.nextNum
    while numTaken(num, id) do num = num + 1 end
  end
  reg[id] = newEntry(num)
  reg[id].label = nameOf(num, bird)
  cfg.nextNum = math.max(cfg.nextNum, num + 1)
  saveCfg()
  return num
end

-- Every change to a miner's entry ends here: saved, sent to him at once, and shown on the remote
function changed(id)
  saveCfg()
  if id then sendNow[id] = true end
  if remoteChanged then remoteChanged() end
end

function retire(id)
  local d = reg[id]
  if not d then return end
  d.retired, d.want, d.seq = true, "dock", os.epoch("utc")
  cfg.retiredNums[d.num] = d.label or nameOf(d.num)
  changed(id)
end

function order(id, want)
  local d = reg[id]
  if not d or d.retired then return end
  d.want = want
  if want == "run" then d.minY, d.maxY, d.r1, d.r2 = d.pMin, d.pMax, d.pR1, d.pR2 end
  d.seq = os.epoch("utc") -- unique id for this order
  changed(id)
end

-- Ask a miner to reboot (it does so between blocks, then carries on). One fresh token per press.
function requestReboot(id)
  local d = reg[id]
  if not d then return end
  d.reboot, d.rebootAt = os.epoch("utc"), os.epoch("utc")
  d.rebootSeen = nil
  changed(id)
end

-- Who's who. The Overworld Foreman (fm_remote.lua) adds the miners it mirrors from the dimension Foremans.
function entry(id) return reg[id] end
function allIds()
  local out = {}
  for id in pairs(reg) do out[#out + 1] = id end
  return out
end
function sortKey(id) return entry(id).num end
-- A status heard on my protocol that's for me (the Overworld Foreman also hears other birds on tanis-miner)
function ownsStatus(s) return not P.ownKinds or P.ownKinds[s and s.kind or ""] == true end

-- The presets a miner's page offers, and the list the presets page edits (the Overworld Foreman: per Foreman)
function presetsOf(id) return cfg.presets end
function presetSetOf(id) return nil end
function presetList() return cfg.presets end
function presetsChanged()
  saveCfg()
  if remoteChanged then remoteChanged() end
end

-- Pick the layers a miner runs on his next START (not sent until then)
function pick(id, minY, maxY, r1, r2)
  local d = reg[id]
  if not d then return end
  d.pMin, d.pMax, d.pR1, d.pR2 = minY, maxY, r1, r2
  saveCfg()
  if remoteChanged then remoteChanged() end
end

-- A miner I don't know that already has a number (e.g. the config was lost): adopt it from its status
function adopt(from, msg)
  local dd = newEntry(tonumber(msg.num))
  dd.label = msg.label or nameOf(dd.num)
  if msg.minY then dd.minY, dd.maxY, dd.pMin, dd.pMax = msg.minY, msg.maxY, msg.minY, msg.maxY end
  if msg.maxRing then
    dd.r1, dd.r2 = msg.minRing or 0, msg.maxRing
    dd.pR1, dd.pR2 = dd.r1, dd.r2
  end
  if msg.want then dd.want = msg.want end
  if msg.seq then dd.seq = msg.seq end
  if msg.retired then dd.retired = true; cfg.retiredNums[dd.num] = dd.label end
  reg[from] = dd
  cfg.nextNum = math.max(cfg.nextNum, dd.num + 1)
  saveCfg()
  return dd
end
