-- nether.lua  --  the Nether Foreman: Pigger control + the Nether dock barrels (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Lives in the Nether, next to Pigger's dock. Needs: an advanced computer with an ender (or wireless)
-- modem for the Piggers, a WIRED modem on the Nether cable, and an advanced monitor touching it
-- (optional: the computer's own screen works too, click with the mouse). Force-load its chunk.
--
-- Barrels on the Nether cable, each given a job with /assign (the same screen as storage's):
--   Dock    one per Pigger: he empties into it; I take everything out and put in what he asks for
--   Output  goes home: barrel > hopper > ender chest (its twin at home feeds storage's input)
--   Stock   what stays in the Nether (spare buckets, lava buckets, coal...): see Rules
--   Input   drop things in by hand: sorted like Pigger's haul
--   Ignore  never touched
-- Everything Pigger brings (and anything in an Input) goes to Stock if the Rules keep some of it and
-- Stock is short, else home through the Output. Stock above its keep count goes home too.
--
-- Pigger: one card each on the overview (state, depth, fuel, cargo); tap one for its layers
-- (presets or Min/Max/rings), START, STOP + DOCK, reboot, retire. Numbers Pigger-01, -02... like
-- the Foreman's Diggers (a retired number is never handed out again). Saved in nether.cfg.
-- Rules page: when Piggers drink lava (under 25% until 75% by default), what the Nether keeps and
-- what Pigger throws away underground. Typed on the computer: /keep /junk /unjunk /assign /presets
-- (/help lists them all).

local PROTOCOL   = "tanis-nether"
local BASE       = "tanis-base"
local CONFIG     = "nether.cfg"
local SEND_EVERY = 3     -- seconds between order broadcasts
local STALE      = 15    -- seconds without news before a Pigger greys out
local TEXT_SCALE = 0.5
local TICK       = 2     -- seconds between barrel passes
local HOLD_FOR   = 90    -- seconds a dock stays untouched while its Pigger takes his supplies

local RING_CAP   = 100   -- furthest ring a Pigger will mine (matches pigger.lua)
local DEF_R2     = 24    -- default outer ring (49x49: about 3x3 chunks)
local Y_MIN, Y_MAX = 6, 120
local NAME_MAX   = 16

-- First-run presets (absolute Y). Ancient debris is commonest around Y 15; the lava sea is at Y 31.
local DEFAULT_PRESETS = {
  { name = "Debris",      minY = 12, maxY = 17, r1 = 1, r2 = DEF_R2 },
  { name = "Debris deep", minY =  8, maxY = 22, r1 = 1, r2 = DEF_R2 },
  { name = "Above lava",  minY = 33, maxY = 44, r1 = 1, r2 = DEF_R2 },
  { name = "High quartz", minY = 60, maxY = 74, r1 = 1, r2 = DEF_R2 },
}
-- What the Nether keeps by default (the rest goes home), and what Pigger throws away underground
local DEFAULT_KEEP = {
  ["minecraft:bucket"] = 4, ["minecraft:lava_bucket"] = 16, ["minecraft:coal"] = 64,
  ["minecraft:charcoal"] = 64, ["minecraft:coal_block"] = 16, ["minecraft:blaze_rod"] = 64,
}
local DEFAULT_JUNK = { "netherrack", "blackstone", "basalt", "smooth_basalt", "soul_sand", "soul_soil",
  "magma_block", "gravel", "crimson_nylium", "warped_nylium", "nether_wart_block", "warped_wart_block",
  "cobblestone", "cobbled_deepslate", "polished_blackstone_bricks" }
-- Fuel the dock hands out, best first (fuel units each)
local FUELS = {
  { "minecraft:lava_bucket", 1000 }, { "minecraft:coal_block", 800 }, { "minecraft:blaze_rod", 120 },
  { "minecraft:coal", 80 }, { "minecraft:charcoal", 80 },
}

---------------------------------------------------------------------------
-- Registry: every Pigger ever seen, keyed by computer ID (the code says "digger": it's Foreman's)
--   { num, label, retired, want, minY, maxY, r1, r2, seq, pMin, pMax, pR1, pR2 }
--   minY/maxY/r1/r2 = the order it's running; pMin/pMax/pR1/pR2 = picked on screen, sent on START.
-- Presets: list of { name, minY, maxY, r1, r2 }.
---------------------------------------------------------------------------
local cfg = { nextNum = 1, diggers = {}, retiredNums = {}, presets = nil }
local function copyPreset(p) return { name = p.name, minY = p.minY, maxY = p.maxY, r1 = p.r1, r2 = p.r2 } end
local function loadCfg()
  if fs.exists(CONFIG) then
    local f = fs.open(CONFIG, "r"); local t = textutils.unserialize(f.readAll()); f.close()
    if type(t) == "table" then
      cfg.nextNum = tonumber(t.nextNum) or 1
      cfg.diggers = type(t.diggers) == "table" and t.diggers or {}
      cfg.retiredNums = type(t.retiredNums) == "table" and t.retiredNums or {}
      cfg.presets = type(t.presets) == "table" and t.presets or nil
      for _, k in ipairs({ "docks", "outputs", "stocks", "inputs", "ignored", "names", "dockFor", "keep",
                          "junk", "hungryAt", "fullAt", "sent" }) do cfg[k] = t[k] end
    end
  end
  for _, k in ipairs({ "docks", "outputs", "stocks", "inputs", "ignored" }) do cfg[k] = type(cfg[k]) == "table" and cfg[k] or {} end
  cfg.names = type(cfg.names) == "table" and cfg.names or {}
  cfg.dockFor = type(cfg.dockFor) == "table" and cfg.dockFor or {}
  cfg.sent = type(cfg.sent) == "table" and cfg.sent or {}
  if type(cfg.keep) ~= "table" then cfg.keep = {}; for k, v in pairs(DEFAULT_KEEP) do cfg.keep[k] = v end end
  if type(cfg.junk) ~= "table" then cfg.junk = {}; for i, v in ipairs(DEFAULT_JUNK) do cfg.junk[i] = v end end
  cfg.hungryAt, cfg.fullAt = tonumber(cfg.hungryAt) or 25, tonumber(cfg.fullAt) or 75
  if not cfg.presets then
    cfg.presets = {}
    for _, p in ipairs(DEFAULT_PRESETS) do cfg.presets[#cfg.presets + 1] = copyPreset(p) end
  end
  for _, p in ipairs(cfg.presets) do p.r1, p.r2 = p.r1 or 1, p.r2 or DEF_R2 end
  for _, dd in pairs(cfg.diggers) do  -- entries from before rings were adjustable
    dd.r1, dd.r2 = dd.r1 or 1, dd.r2 or DEF_R2
    dd.pR1, dd.pR2 = dd.pR1 or dd.r1, dd.pR2 or dd.r2
  end
end
local function saveCfg()
  local f = fs.open(CONFIG, "w"); f.write(textutils.serialize(cfg)); f.close()
end

local function newEntry(num)
  return { num = num, want = "dock", minY = 12, maxY = 17, pMin = 12, pMax = 17,
           r1 = 1, r2 = DEF_R2, pR1 = 1, pR2 = DEF_R2, seq = os.epoch("utc") }
end
local function numTaken(num, exceptId)
  if cfg.retiredNums[num] then return true end
  for id, d in pairs(cfg.diggers) do
    if id ~= exceptId and d.num == num and not d.retired then return true end
  end
  return false
end
local function nameOf(num) return ("Pigger-%02d"):format(num) end
local REBOOT_WAIT = 600000 -- ms: stop asking a Pigger to reboot if it hasn't confirmed by then

local live = {}        -- id -> { s = last status, seen = os.clock() }
local radioOK = nil    -- false = no ender/wireless modem on this computer: Piggers can't hear it
local capped = {}      -- junk storage has plenty of (from the storage computer)
local storageSeen = nil
local sendNow = {}     -- id -> true: send its order on the next pass

-- A Pigger asks for a number. Same computer keeps its number; a hint (its old label) is honoured
-- if free; otherwise the next number. Retired numbers are never reused.
local function assign(id, hint)
  local d = cfg.diggers[id]
  if d and not d.retired then return d.num end
  local num = tonumber(hint)
  if not num or num < 1 or numTaken(num, id) then
    num = cfg.nextNum
    while numTaken(num, id) do num = num + 1 end
  end
  cfg.diggers[id] = newEntry(num)
  cfg.diggers[id].label = nameOf(num)
  cfg.nextNum = math.max(cfg.nextNum, num + 1)
  saveCfg()
  return num
end

local function retire(id)
  local d = cfg.diggers[id]
  if not d then return end
  d.retired, d.want, d.seq = true, "dock", os.epoch("utc")
  cfg.retiredNums[d.num] = d.label or nameOf(d.num)
  saveCfg()
  sendNow[id] = true
end

local function order(id, want)
  local d = cfg.diggers[id]
  if not d or d.retired then return end
  d.want = want
  if want == "run" then d.minY, d.maxY, d.r1, d.r2 = d.pMin, d.pMax, d.pR1, d.pR2 end
  d.seq = os.epoch("utc") -- unique id for this order
  saveCfg()
  sendNow[id] = true
end

-- Ask a Pigger to reboot (it does so between blocks, then carries on). One fresh token per press.
local function requestReboot(id)
  local d = cfg.diggers[id]
  if not d then return end
  d.reboot, d.rebootAt = os.epoch("utc"), os.epoch("utc")
  d.rebootSeen = nil
  saveCfg()
  sendNow[id] = true
end

---------------------------------------------------------------------------
-- Barrels on the Nether cable: jobs (/assign), routing (keep or send home), dock supplies
---------------------------------------------------------------------------
local function listRemove(list, n) for i = #list, 1, -1 do if list[i] == n then table.remove(list, i) end end end
local function listAdd(list, n) for _, x in ipairs(list) do if x == n then return end end; list[#list + 1] = n end

local TYPES = {
  { key = "dock",   label = "Dock",   short = "Dock",   tag = "DOCK",   col = colours.yellow,
    about = "Pigger's barrel: I empty it, and put in a bucket or fuel when he asks. One per Pigger." },
  { key = "output", label = "Output", short = "Output", tag = "OUTPUT", col = colours.cyan,
    about = "Goes home: barrel > hopper > ender chest. Everything the Nether doesn't keep." },
  { key = "stock",  label = "Stock",  short = "Stock",  tag = "STOCK",  col = colours.lime,
    about = "Stays in the Nether: what the Rules keep (spare buckets, fuel). Extra goes home." },
  { key = "input",  label = "Input",  short = "Input",  tag = "INPUT",  col = colours.lightBlue,
    about = "Drop things in by hand: kept or sent home like Pigger's haul." },
  { key = "ignore", label = "Ignore", short = "Ignore", tag = "IGNORE", col = colours.lightGrey,
    about = "Never touched: I pretend it isn't there." },
}
local LISTS = { dock = "docks", output = "outputs", stock = "stocks", input = "inputs", ignore = "ignored" }

local function typeOf(n)
  for key, field in pairs(LISTS) do
    for _, x in ipairs(cfg[field] or {}) do if x == n then return key end end
  end
end
local function unassign(n)
  for _, field in pairs(LISTS) do listRemove(cfg[field], n) end
  cfg.dockFor[n] = nil
end
local function assignJob(n, key)
  unassign(n)
  listAdd(cfg[LISTS[key]], n)
end

local function call(name, method, ...)
  local ok, a, b = pcall(peripheral.call, name, method, ...)
  if ok then return a, b end
  return nil, a
end
local function inventories()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "inventory") then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end
local function itemTotals()
  local t = {}
  for _, n in ipairs(inventories()) do
    local c = 0
    for _, it in pairs(call(n, "list") or {}) do c = c + it.count end
    t[n] = c
  end
  return t
end

local paused, workerBusy = false, false   -- paused: /assign is watching for a dropped item
local barrel = { stock = {}, outFree = 0, outSlots = 0, outFull = false, docks = {}, seen = {} }
local requests = {}    -- dock requests waiting for the worker: { id, seq, bucket, fuel }
local holds = {}       -- dock name -> { id, untilT }: left alone while its Pigger takes his supplies
local lastReply = {}   -- id -> the last dock_ready sent (repeated if he asks again with the same seq)
local servedSeq = {}   -- id -> seq of the last request taken on

-- What the Stock barrels hold, by item
local function scanStock()
  local have, seen = {}, barrel.seen
  for _, n in ipairs(cfg.stocks) do
    for _, it in pairs(call(n, "list") or {}) do
      have[it.name] = (have[it.name] or 0) + it.count
      seen[it.name] = true
    end
  end
  barrel.stock = have
  return have
end

-- Move up to `count` of (from, slot) into the given barrels: ones already holding the item first
local function pushInto(list, from, slot, item, count)
  local moved = 0
  local firstPass, second = {}, {}
  for _, n in ipairs(list) do
    local holds = false
    for _, it in pairs(call(n, "list") or {}) do if it.name == item then holds = true; break end end
    if holds then firstPass[#firstPass + 1] = n else second[#second + 1] = n end
  end
  for _, group in ipairs({ firstPass, second }) do
    for _, n in ipairs(group) do
      if moved >= count then return moved end
      moved = moved + (call(from, "pushItems", n, slot, count - moved) or 0)
    end
  end
  return moved
end

-- Everything in one barrel goes to Stock (up to the keep count) or home. Returns items left behind.
local function routeAll(from, stockToo)
  local left = 0
  for slot, it in pairs(call(from, "list") or {}) do
    barrel.seen[it.name] = true
    local n = it.count
    local want = (cfg.keep[it.name] or 0) - (barrel.stock[it.name] or 0)
    if stockToo and want > 0 then
      local m = pushInto(cfg.stocks, from, slot, it.name, math.min(n, want))
      barrel.stock[it.name] = (barrel.stock[it.name] or 0) + m
      n = n - m
    end
    if n > 0 then
      local m = pushInto(cfg.outputs, from, slot, it.name, n)
      if m > 0 then cfg.sent[it.name] = (cfg.sent[it.name] or 0) + m end
      n = n - m
      if n > 0 then barrel.outFull = true end
    end
    left = left + n
  end
  return left
end

-- Stock above its keep count (or with no rule at all) goes home
local function trimStock()
  local over = {}
  for name, c in pairs(barrel.stock) do
    local extra = c - (cfg.keep[name] or 0)
    if extra > 0 then over[name] = extra end
  end
  if not next(over) then return end
  for _, n in ipairs(cfg.stocks) do
    for slot, it in pairs(call(n, "list") or {}) do
      local extra = over[it.name]
      if extra and extra > 0 then
        local m = pushInto(cfg.outputs, n, slot, it.name, math.min(extra, it.count))
        if m > 0 then
          over[it.name] = extra - m
          barrel.stock[it.name] = barrel.stock[it.name] - m
          cfg.sent[it.name] = (cfg.sent[it.name] or 0) + m
        elseif #cfg.outputs > 0 then barrel.outFull = true end
      end
    end
  end
end

-- Take `count` of an item out of Stock into a dock. Returns how many moved.
local function fromStock(item, count, dock)
  local moved = 0
  for _, n in ipairs(cfg.stocks) do
    for slot, it in pairs(call(n, "list") or {}) do
      if moved >= count then return moved end
      if it.name == item then
        moved = moved + (call(n, "pushItems", dock, slot, math.min(count - moved, it.count)) or 0)
      end
    end
  end
  return moved
end

local function dockOf(id)
  local free
  for _, d in ipairs(cfg.docks) do
    if cfg.dockFor[d] == id then return d end
    if not cfg.dockFor[d] and not free then free = d end
  end
  return free
end

-- A Pigger at his dock asks for a bucket and/or fuel: empty the dock, then load what Stock has
local function serveRequest(r)
  local dock = dockOf(r.id)
  local reply = { type = "dock_ready", id = r.id, seq = r.seq, got = {}, missing = {} }
  if not dock then
    reply.note = "No dock barrel: /assign one on the Nether Foreman"
  else
    routeAll(dock, true)
    scanStock()
    if r.bucket then
      if fromStock("minecraft:bucket", 1, dock) > 0 then reply.got["minecraft:bucket"] = 1
      else reply.missing[#reply.missing + 1] = "bucket" end
    end
    local units = math.max(0, tonumber(r.fuel) or 0)
    for _, f in ipairs(FUELS) do
      local n = math.floor(units / f[2])
      if f[1] == "minecraft:lava_bucket" then n = math.ceil(units / f[2]) end
      n = math.min(n, (f[1] == "minecraft:lava_bucket") and 14 or 64)
      if n > 0 and (barrel.stock[f[1]] or 0) > 0 then
        local m = fromStock(f[1], math.min(n, barrel.stock[f[1]]), dock)
        if m > 0 then
          reply.got[f[1]] = m
          units = units - m * f[2]
          barrel.stock[f[1]] = barrel.stock[f[1]] - m
        end
      end
      if units <= 0 then break end
    end
    if units >= 80 then reply.missing[#reply.missing + 1] = "fuel" end
    holds[dock] = { id = r.id, untilT = os.clock() + HOLD_FOR }
    if #reply.missing > 0 then
      reply.note = "Stock has no " .. table.concat(reply.missing, " or ")
    end
  end
  if rednet.isOpen() then rednet.send(r.id, reply, PROTOCOL) end
  lastReply[r.id] = reply
  return reply
end

local lastNote = nil
local function barrelPass()
  barrel.outFull = false
  scanStock()
  while #requests > 0 do
    local r = table.remove(requests, 1)
    local rep = serveRequest(r)
    lastNote = rep.note
  end
  for d, h in pairs(holds) do if os.clock() > h.untilT then holds[d] = nil end end
  for _, n in ipairs(cfg.inputs) do routeAll(n, true) end
  for _, d in ipairs(cfg.docks) do
    if not holds[d] then routeAll(d, true) end
  end
  trimStock()
  -- Output room, for the screens
  local free, slots = 0, 0
  for _, n in ipairs(cfg.outputs) do
    local size = call(n, "size") or 0
    local used = 0
    for _ in pairs(call(n, "list") or {}) do used = used + 1 end
    free, slots = free + size - used, slots + size
  end
  barrel.outFree, barrel.outSlots = free, slots
  local docks = {}
  for _, d in ipairs(cfg.docks) do
    local c = 0
    for _, it in pairs(call(d, "list") or {}) do c = c + it.count end
    docks[d] = c
  end
  barrel.docks = docks
end

-- Item names typed on the computer: "bucket", "lava_bucket", "ancient debris", "mod:thing"
local function resolveItem(text)
  text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub(" ", "_")
  if text == "" then return nil end
  if text:find(":") then return text end
  local hits = {}
  local pool = {}
  for name in pairs(barrel.seen) do pool[name] = true end
  for name in pairs(cfg.keep) do pool[name] = true end
  for name in pairs(cfg.sent) do pool[name] = true end
  for name in pairs(pool) do if name:match(":(.+)$") == text then hits[#hits + 1] = name end end
  if #hits == 1 then return hits[1] end
  if #hits > 1 then
    for _, h in ipairs(hits) do if h == "minecraft:" .. text then return h end end
    return hits[1]
  end
  return "minecraft:" .. text
end

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------
local K = colours
local STATES = {
  mining = { "MINING", K.lime }, returning = { "RETURNING", K.yellow }, docked = { "DOCKED", K.lightBlue },
  waiting = { "WAITING", K.orange }, error = { "ERROR", K.red }, lost = { "LOST", K.red },
  retired = { "RETIRED", K.grey }, rebooting = { "REBOOTING", K.purple },
}
local DIMS = { overworld = "Overworld", the_nether = "Nether", the_end = "End" }

local function fmtNum(n)
  if type(n) ~= "number" then return tostring(n or "?") end
  local s = tostring(math.floor(n))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function fmtAgo(s)
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end
local function pretty(id)
  local s = tostring(id):gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end
local function presetName(a, b, r1, r2)
  for _, p in ipairs(cfg.presets) do
    if p.minY == a and p.maxY == b and (r1 == nil or (p.r1 == r1 and p.r2 == r2)) then return p.name end
  end
end
local function rangeText(a, b, r1, r2)
  if not a then return "-" end
  local n = presetName(a, b, r1, r2)
  return (n and (n .. " ") or "") .. a .. ".." .. b
end
local function sq(r) return 2 * r + 1 end
local function ringText(r1, r2)
  r1, r2 = r1 or 1, r2 or DEF_R2
  if r1 <= 1 then return ("rings 1-%d, %dx%d"):format(r2, sq(r2), sq(r2)) end
  return ("rings %d-%d, %dx%d"):format(r1, r2, sq(r2), sq(r2))
end
local function isSelected(dd, p)
  return dd.pMin == p.minY and dd.pMax == p.maxY and dd.pR1 == p.r1 and dd.pR2 == p.r2
end
local function posText(s)
  if not s or not s.pos then return "position unknown" end
  return ("%d, %d, %d"):format(s.pos.x, s.pos.y, s.pos.z)
end
local function stateOf(id)
  local d, l = cfg.diggers[id], live[id]
  if d and d.retired then return "RETIRED", K.grey end
  if not l then return "NO SIGNAL", K.grey end
  local m = STATES[l.s.state] or { tostring(l.s.state or "?"):upper(), K.white }
  if os.clock() - l.seen > STALE then return m[1], K.grey end
  return m[1], m[2]
end

-- Sorted list of Pigger IDs to show
local function digIds(showRetired)
  local out = {}
  for id, d in pairs(cfg.diggers) do
    if (d.retired == true) == (showRetired == true) then out[#out + 1] = id end
  end
  table.sort(out, function(a, b) return cfg.diggers[a].num < cfg.diggers[b].num end)
  if not showRetired then
    -- Heard on the air but never asked for a number: running an old program
    local odd = {}
    for id in pairs(live) do if not cfg.diggers[id] then odd[#odd + 1] = id end end
    table.sort(odd)
    for _, id in ipairs(odd) do out[#out + 1] = id end
  end
  return out
end

---------------------------------------------------------------------------
-- Screens: the monitor (if one touches the computer) and the computer's own screen.
-- Both show the same page; each keeps its own tap areas.
---------------------------------------------------------------------------
-- Each screen has its own page state (ui is pointed at the right one while drawing / handling a tap)
local function newUi()
  return { page = "overview", id = nil, scroll = 1, showRetired = false, confirmRetire = nil, notice = nil,
           pscroll = 1, lscroll = 1, edit = nil, cmd = nil }
end
local ui = nil

local function findMonitor()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then return peripheral.wrap(side), side end
  end
end
local mon, monSide = findMonitor()
local views = {
  { dev = function() return mon end, kind = "monitor", hits = {}, ui = newUi() },
  { dev = function() return term end, kind = "term", hits = {}, ui = newUi() },
}
local termUi = views[2].ui
ui = termUi

local d, hits -- current device and its hit list while drawing
local function at(x, y, text, fg, bg)
  d.setCursorPos(x, y)
  d.setBackgroundColour(bg or K.black)
  d.setTextColour(fg or K.white)
  d.write(text)
end
local function pad(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s > w then return s:sub(1, w) end
  return s .. (" "):rep(w - #s)
end
local function lr(x, y, w, left, right, fgL, fgR)
  at(x, y, pad(left, w), fgL or K.lightGrey)
  if right then
    right = tostring(right):sub(1, w)
    at(x + w - #right, y, right, fgR or K.white)
  end
end
local function bar(x, y, w, frac, colour)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  at(x, y, (" "):rep(w), K.white, K.grey)
  if n > 0 then at(x, y, (" "):rep(n), K.white, colour) end
end
local function hit(x1, y1, x2, y2, fn) hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn } end
local function button(x, y, w, rows, label, bg, fn, fg)
  for r = 0, rows - 1 do at(x, y + r, (" "):rep(w), K.black, bg) end
  label = label:sub(1, w)
  at(x + math.floor((w - #label) / 2), y + math.floor(rows / 2), label, fg or K.black, bg)
  hit(x, y, x + w - 1, y + rows - 1, fn)
end
local function smallButton(x, y, label, bg, fn, fg)
  at(x, y, " " .. label .. " ", fg or K.black, bg)
  hit(x, y, x + #label + 1, y, fn)
  return x + #label + 3
end

local function header(w, title, right)
  at(1, 1, (" "):rep(w), K.cyan, K.grey)
  at(2, 1, title, K.cyan, K.grey)
  if right and #right + #title + 4 < w then at(w - #right, 1, right, K.lightGrey, K.grey) end
  if ui.notice and os.clock() < ui.notice.untilT then
    at(2, 2, pad(ui.notice.text, w - 2), ui.notice.colour)
  end
end

-- Notices show on every screen
local function say(text, colour)
  for _, v in ipairs(views) do v.ui.notice = { text = text, colour = colour or K.lime, untilT = os.clock() + 5 } end
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local openAssign   -- defined with the commands (the /assign screen needs the computer's keyboard)

-- One line about the barrels, for the overview's second row
local function barrelLine()
  if #cfg.docks == 0 or #cfg.outputs == 0 then
    return "Barrels: tap Barrels (or /assign) to give them jobs", K.orange
  end
  if barrel.outFull then return "Output full: is the hopper into the ender chest flowing?", K.red end
  if #cfg.stocks == 0 then return "No Stock barrel: everything goes home, spare buckets too", K.orange end
  local parts = {}
  for _, f in ipairs({ { "minecraft:bucket", "buckets" }, { "minecraft:lava_bucket", "lava" } }) do
    parts[#parts + 1] = ("%d %s"):format(barrel.stock[f[1]] or 0, f[2])
  end
  local fuel = 0
  for _, f in ipairs(FUELS) do fuel = fuel + (barrel.stock[f[1]] or 0) * f[2] end
  local sent = 0
  for _, c in pairs(cfg.sent) do sent = sent + c end
  return ("Stock %s, fuel %s.  Sent home %s"):format(table.concat(parts, ", "), fmtNum(fuel), fmtNum(sent)), K.lightGrey
end
local function drawOverview(w, h)
  local ids = digIds(ui.showRetired)
  if radioOK == false and not (ui.notice and os.clock() < ui.notice.untilT) then
    ui.notice = { text = "No ender modem on me: Piggers can't hear me", colour = K.red, untilT = os.clock() + 1e9 }
  end
  local active, retiredN = 0, 0
  for _, dd in pairs(cfg.diggers) do if dd.retired then retiredN = retiredN + 1 else active = active + 1 end end
  local outTxt = #cfg.outputs == 0 and "no output" or barrel.outFull and "OUTPUT FULL"
    or ("out %d/%d free"):format(barrel.outFree, barrel.outSlots)
  header(w, ui.showRetired and "NETHER  retired" or "NETHER FOREMAN",
    ("%d pigger%s  %s"):format(active, active == 1 and "" or "s", outTxt))
  if not (ui.notice and os.clock() < ui.notice.untilT) then
    local line, col = barrelLine()
    at(2, 2, pad(line, w - 2), col)
  end

  local top, bottom = 3, h - 2
  local rowH = (h >= 16) and 3 or 1      -- a card is 2 lines + a gap, or 1 line on small screens
  local per = math.max(1, math.floor((bottom - top + 1) / rowH))
  local pages = math.max(1, math.ceil(#ids / per))
  ui.scroll = math.max(1, math.min(ui.scroll, pages))

  if #ids == 0 then
    local lines = ui.showRetired and { "No retired Piggers." } or {
      "No Piggers yet.",
      "Set up a turtle as a Pigger (startup.lua, pick Pigger):",
      "it asks me for a number and shows up here.",
    }
    for i, l in ipairs(lines) do at(2, top + i, pad(l, w - 2), i == 1 and K.white or K.lightGrey) end
  end

  for i = 1, per do
    local id = ids[(ui.scroll - 1) * per + i]
    if not id then break end
    local l = live[id]
    local s = l and l.s
    local dd = cfg.diggers[id] or { unknown = true, label = (s and s.label or "?") .. "?", num = 0 }
    local y = top + (i - 1) * rowH
    local name = dd.label or nameOf(dd.num)
    local st, colour = stateOf(id)
    local stale = not l or os.clock() - l.seen > STALE
    local bg = (rowH == 3) and K.black or (i % 2 == 0 and K.grey or K.black)
    at(1, y, (" "):rep(w), K.white, bg)
    at(2, y, pad(name, 10), stale and K.lightGrey or K.white, bg)
    at(13, y, pad(st, 9), colour, bg)
    -- the numbers: depth, fuel, cargo
    local bits = {}
    if s then
      bits[#bits + 1] = "Y " .. tostring(s.y or "?")
      if type(s.fuel) == "number" and type(s.fuelLimit) == "number" and s.fuelLimit > 0 then
        bits[#bits + 1] = ("fuel %d%%"):format(math.floor(s.fuel / s.fuelLimit * 100))
      end
      bits[#bits + 1] = ("cargo %s/16"):format(tostring(s.slots or "?"))
    end
    local arrow = w >= 56
    local room = w - 22 - (arrow and 3 or 0)
    if room > 4 then at(22, y, pad(table.concat(bits, "  "), room), stale and K.grey or K.lightGrey, bg) end
    if arrow then at(w - 1, y, ">", K.cyan, bg) end
    if rowH == 3 then
      -- Line 2: what it's doing (or when it was last heard) on the left, where it is on the right
      local where = ""
      if s and s.pos then
        where = posText(s)
        if s.dim and s.dim ~= "overworld" then where = where .. " " .. (DIMS[s.dim] or s.dim) end
      end
      local left
      if dd.unknown then
        left = "No number: old program? Reboot it to update"
      elseif stale then
        left = l and ("not heard for " .. fmtAgo(math.floor(os.clock() - l.seen))) or "never heard from"
      elseif s and s.state == "mining" and s.layer and s.layers then
        left = ("%s, layer %s/%s"):format(rangeText(s.minY, s.maxY), s.layer, s.layers)
      else
        left = (s and s.msg ~= "" and s.msg) or rangeText(dd.minY, dd.maxY)
      end
      local roomL = w - 5 - #where - 2
      at(4, y + 1, pad(left, roomL), stale and K.grey or K.lightGrey)
      if #where > 0 then at(w - #where, y + 1, where, K.grey) end
    end
    if dd.unknown then
      hit(1, y, w, y + rowH - 1, function()
        say((s and s.label or "It") .. ": old program. Hold Ctrl+R on it to update.", K.orange)
      end)
    else
      hit(1, y, w, y + rowH - 1, function() ui.page, ui.id, ui.confirmRetire = "digger", id, nil end)
    end
  end

  -- Footer: dock everyone, show retired, pages
  local fy = h
  at(1, fy, (" "):rep(w))
  local x = 2
  if not ui.showRetired then
    x = smallButton(x, fy, "Dock all", K.red, function()
      for _, id in ipairs(digIds(false)) do order(id, "dock") end
      say("Sent every Pigger home.", K.yellow)
    end)
  end
  if retiredN > 0 or ui.showRetired then
    x = smallButton(x, fy, ui.showRetired and "Back" or ("Retired " .. retiredN), K.grey,
      function() ui.showRetired = not ui.showRetired; ui.scroll = 1 end, K.white)
  end
  if not ui.showRetired then
    x = smallButton(x, fy, "Presets", K.lightBlue, function() ui.page, ui.lscroll = "presets", 1 end)
    x = smallButton(x, fy, "Rules", K.yellow, function() ui.page, ui.kscroll = "rules", 1 end)
    x = smallButton(x, fy, "Barrels", K.cyan, function() openAssign() end)
    if active > 0 and w >= 64 then
      x = smallButton(x, fy, "Reboot all", K.purple, function()
        for _, id in ipairs(digIds(false)) do if cfg.diggers[id] then requestReboot(id) end end
        say("Reboot sent to every Pigger: they finish the block they're on first.", K.purple)
      end, K.white)
    end
  end
  if pages > 1 then
    local label = ("%d/%d"):format(ui.scroll, pages)
    local px = w - #label - 9
    if px > x then
      smallButton(px, fy, "<", ui.scroll > 1 and K.cyan or K.grey, function() ui.scroll = ui.scroll - 1 end)
      at(px + 4, fy, label, K.lightGrey)
      smallButton(w - 3, fy, ">", ui.scroll < pages and K.cyan or K.grey, function() ui.scroll = ui.scroll + 1 end)
    end
  end
end

---------------------------------------------------------------------------
-- One Pigger
---------------------------------------------------------------------------
local function drawStatus(id, x, y, w, maxY)
  local dd, l = cfg.diggers[id], live[id]
  local s = l and l.s
  local st, colour = stateOf(id)
  local function line(fn) if y <= maxY then fn(); end y = y + 1 end
  line(function() at(x, y, pad(st, w), colour) end)
  line(function() at(x, y, pad(s and s.msg or (dd.retired and "Retired" or "Waiting to hear from it"), w), K.lightGrey) end)
  line(function() at(x, y, pad(l and ("Seen " .. fmtAgo(math.floor(os.clock() - l.seen)) .. " ago") or "Never heard", w), K.grey) end)
  y = y + 1
  local f, lim = s and s.fuel, s and s.fuelLimit
  local frac = (type(f) == "number" and type(lim) == "number" and lim > 0) and f / lim or 1
  line(function() lr(x, y, w, "Fuel", type(f) == "number" and fmtNum(f) or (f or "-")) end)
  line(function()
    bar(x, y, w, s and frac or 0, (s and s.hungry) and K.orange or K.lime)
    -- the drink-lava marks
    for _, p in ipairs({ cfg.hungryAt, cfg.fullAt }) do
      local mx = x + math.floor(p / 100 * w + 0.5)
      if mx >= x and mx < x + w then at(mx, y, "|", K.black, mx < x + math.floor(frac * w + 0.5) and ((s and s.hungry) and K.orange or K.lime) or K.grey) end
    end
  end)
  line(function()
    local txt = not s and "-" or s.hungry and ("drinking to " .. cfg.fullAt .. "%")
      or ("drinks under " .. cfg.hungryAt .. "%")
    lr(x, y, w, "Lava", txt, K.lightGrey, (s and s.hungry) and K.orange or K.lightGrey)
  end)
  line(function()
    local b = s and s.bucket
    local txt = b == "empty" and "empty, ready" or b == "lava" and "full of lava" or b == "none" and "NONE" or "-"
    lr(x, y, w, "Bucket", txt, K.lightGrey, b == "none" and K.red or K.lightGrey)
  end)
  line(function()
    lr(x, y, w, "Drunk", s and (fmtNum(s.lavaScoops or 0) .. " scoops") or "-", K.grey, K.grey)
  end)
  line(function() lr(x, y, w, "Cargo", s and ((s.slots or "?") .. "/16") or "-") end)
  line(function() bar(x, y, w, s and ((s.slots or 0) / 16) or 0, (s and (s.slots or 0) >= 14) and K.orange or K.lightBlue) end)
  line(function() lr(x, y, w, "Layer", s and s.layer and s.layers and (math.min(s.layer, s.layers) .. "/" .. s.layers) or "-") end)
  line(function()
    lr(x, y, w, "Ring", s and s.ring and ("%s of %d-%d"):format(s.ring, s.minRing or 1, s.maxRing or DEF_R2) or "-")
  end)
  line(function() lr(x, y, w, "Range", s and s.minY and (s.minY .. ".." .. s.maxY) or "-") end)
  y = y + 1
  line(function() lr(x, y, w, "At", posText(s), K.lightGrey, K.white) end)
  line(function()
    local dim = s and s.dim and (DIMS[s.dim] or s.dim) or "?"
    lr(x, y, w, dim, s and s.facing and ("facing " .. s.facing) or "", K.lightGrey, K.lightGrey)
  end)
  line(function()
    local hm = s and s.home
    lr(x, y, w, "Home", hm and ("%d, %d, %d"):format(hm.x, hm.y, hm.z) or "-", K.lightGrey, K.lightGrey)
  end)
  line(function()
    local dock = dockOf(id)
    lr(x, y, w, "Dock", dock and (dock:gsub("^minecraft:", "") .. ((barrel.docks[dock] or 0) > 0 and (", " .. barrel.docks[dock] .. " in it") or ""))
      or "no dock barrel: /assign", K.grey, dock and K.grey or K.orange)
  end)
  if s and s.dockNote then
    line(function() at(x, y, pad(s.dockNote, w), K.orange) end)
  end
  if s and s.offPath then
    line(function() at(x, y, pad("Moved by hand. Goes home", w), K.orange) end)
    line(function() at(x, y, pad("by a tunnel under the dock.", w), K.orange) end)
  end
  return y
end

local function drawHaul(id, x, y, w, maxY)
  local l = live[id]
  if y > maxY then return end
  at(x, y, pad("LAST HAUL", w), K.grey)
  y = y + 1
  local haul = l and l.s.haul or {}
  if #haul == 0 and y <= maxY then at(x, y, pad("Nothing yet", w), K.grey) end
  for _, e in ipairs(haul) do
    if y > maxY then break end
    lr(x, y, w, pretty(e[1]), fmtNum(e[2]), K.white, K.cyan)
    y = y + 1
  end
end

local function clampY(v) return math.max(Y_MIN, math.min(Y_MAX, v)) end
local function clampR(v) return math.max(1, math.min(RING_CAP, v)) end

-- Pigger page: nudge the picked (not yet started) settings
local function adjust(dd, key, delta)
  if key == "pR1" or key == "pR2" then
    dd[key] = clampR(dd[key] + delta)
    if dd.pR1 > dd.pR2 then if key == "pR1" then dd.pR2 = dd.pR1 else dd.pR1 = dd.pR2 end end
  else
    dd[key] = clampY(dd[key] + delta)
    if dd.pMin > dd.pMax then if key == "pMin" then dd.pMax = dd.pMin else dd.pMin = dd.pMax end end
  end
  saveCfg()
end

-- One "Label value  [-][+]" row; steps = { {label, delta}, ... }
local function numRow(x, y, w, label, value, steps, fn, fieldFn, focused, buf)
  local bw = 0
  for _, s in ipairs(steps) do bw = bw + #s[1] + 3 end
  local vx = x + math.min(11, w - bw - 7)
  at(x, y, pad(label, w), K.white)
  if fieldFn then
    local txt = focused and (buf .. "_") or tostring(value)
    at(vx, y, pad(" " .. txt, 7), focused and K.black or K.white, focused and K.white or K.grey)
    hit(vx, y, vx + 6, y, fieldFn)
  else
    at(vx, y, tostring(value), K.white)
  end
  local bx = x + w - bw
  for _, s in ipairs(steps) do
    bx = smallButton(bx, y, s[1], K.grey, function() fn(s[2]) end, K.white) - 1
  end
end

local function drawControls(id, x, y, w, maxY)
  local dd, l = cfg.diggers[id], live[id]
  local s = l and l.s
  local yStep = { { "-", -1 }, { "+", 1 } }
  local rStep = { { "-5", -5 }, { "+5", 5 } }
  if w < 24 then rStep = { { "-", -5 }, { "+", 5 } } end

  -- How tall can things be? Everything below the preset list needs `fixed` rows.
  local room = maxY - y + 1
  local function fixedRows(bh, gap) return 1 + 4 + 1 + bh + gap + bh + 1 + 1 end
  local bh, gap = 3, 1
  if room - fixedRows(3, 1) < math.min(#cfg.presets, 4) then bh, gap = 1, 0 end
  local listRows = math.max(1, room - fixedRows(bh, gap))

  at(x, y, pad("LAYERS", w), K.grey)
  if w >= 16 then
    smallButton(x + w - 6, y, "Edit", K.lightBlue, function() ui.page, ui.lscroll = "presets", 1 end)
  end
  y = y + 1
  -- Preset list (paged if it doesn't fit)
  local n = #cfg.presets
  local per = (n > listRows) and math.max(1, listRows - 1) or listRows
  local pages = math.max(1, math.ceil(n / per))
  ui.pscroll = math.max(1, math.min(ui.pscroll or 1, pages))
  for i = 1, per do
    local p = cfg.presets[(ui.pscroll - 1) * per + i]
    if not p then break end
    local sel = isSelected(dd, p)
    local bg, fg = sel and K.cyan or K.black, sel and K.black or K.white
    at(x, y, (" "):rep(w), fg, bg)
    at(x + 1, y, p.name:sub(1, w - 2), fg, bg)
    if w >= 20 then
      local r = p.minY .. ".." .. p.maxY
      if w >= 30 then r = r .. "  r" .. (p.r1 > 1 and (p.r1 .. "-") or "") .. p.r2 end
      if #p.name + #r + 3 <= w then at(x + w - #r - 1, y, r, sel and K.black or K.lightGrey, bg) end
    end
    hit(x, y, x + w - 1, y, function()
      dd.pMin, dd.pMax, dd.pR1, dd.pR2 = p.minY, p.maxY, p.r1, p.r2; saveCfg()
    end)
    y = y + 1
  end
  if n == 0 then at(x, y, pad("No presets: tap Edit", w), K.grey); y = y + 1 end
  if pages > 1 then
    at(x, y, (" "):rep(w))
    smallButton(x, y, "<", ui.pscroll > 1 and K.cyan or K.grey, function() ui.pscroll = ui.pscroll - 1 end)
    at(x + 4, y, ("%d/%d"):format(ui.pscroll, pages), K.lightGrey)
    smallButton(x + w - 3, y, ">", ui.pscroll < pages and K.cyan or K.grey, function() ui.pscroll = ui.pscroll + 1 end)
    y = y + 1
  end
  -- Fine tuning
  numRow(x, y, w, "Min Y", dd.pMin, yStep, function(dv) adjust(dd, "pMin", dv) end); y = y + 1
  numRow(x, y, w, "Max Y", dd.pMax, yStep, function(dv) adjust(dd, "pMax", dv) end); y = y + 1
  numRow(x, y, w, w >= 26 and "From ring" or "Ring>", dd.pR1, rStep, function(dv) adjust(dd, "pR1", dv) end); y = y + 1
  numRow(x, y, w, w >= 26 and "To ring" or "Ring<", dd.pR2, rStep, function(dv) adjust(dd, "pR2", dv) end); y = y + 1
  local hint, hc = ("Area %dx%d"):format(sq(dd.pR2), sq(dd.pR2)), K.grey
  if dd.pR1 > 1 then hint = hint .. (", skips middle %dx%d"):format(sq(dd.pR1 - 1), sq(dd.pR1 - 1)) end
  if s and s.seq ~= dd.seq then hint, hc = "Sending...", K.yellow
  elseif s and s.offPath then hint, hc = "START/DOCK: send it home", K.orange
  elseif dd.want == "run" and (dd.minY ~= dd.pMin or dd.maxY ~= dd.pMax or dd.r1 ~= dd.pR1 or dd.r2 ~= dd.pR2) then
    hint, hc = "START to switch", K.orange
  end
  at(x, y, pad(hint, w), hc)
  y = y + 1
  button(x, y, w, bh, "START", K.lime, function() order(id, "run"); say(dd.label .. ": START sent.") end)
  y = y + bh + gap
  button(x, y, w, bh, w >= 11 and "STOP + DOCK" or "STOP", K.red, function()
    order(id, "dock"); say(dd.label .. ": heading home.", K.yellow)
  end)
  y = y + bh + 1
  if y <= maxY then
    -- Reboot | Retire share the last row
    local rw = math.floor((w - 1) / 2)
    local pending = dd.reboot ~= nil
    button(x, y, rw, 1, pending and "Rebooting..." or "Reboot", pending and K.grey or K.purple, function()
      requestReboot(id); say(dd.label .. ": reboot sent. It finishes its block first.", K.purple)
    end, K.white)
    local rx, rw2 = x + rw + 1, w - rw - 1
    if ui.confirmRetire == id then
      button(rx, y, rw2, 1, "Tap to retire", K.orange, function()
        retire(id); ui.confirmRetire = nil; ui.page = "overview"
        say(dd.label .. " retired. Number " .. dd.num .. " won't be used again.", K.orange)
      end)
    else
      button(rx, y, rw2, 1, "Retire", K.grey, function() ui.confirmRetire = id end, K.white)
    end
  end
end

---------------------------------------------------------------------------
-- Presets: list + editor
---------------------------------------------------------------------------
local function findPreset(name)
  name = (name or ""):lower()
  if name == "" then return nil end
  for i, p in ipairs(cfg.presets) do if p.name:lower() == name then return i end end
  local hitI, count = nil, 0
  for i, p in ipairs(cfg.presets) do
    if p.name:lower():sub(1, #name) == name then hitI, count = i, count + 1 end
  end
  if count == 1 then return hitI end
end

local function openEditor(idx, name)
  local p = idx and cfg.presets[idx] or { name = name or "", minY = -59, maxY = -48, r1 = 1, r2 = DEF_R2 }
  ui.edit = { idx = idx, name = p.name, minY = p.minY, maxY = p.maxY, r1 = p.r1, r2 = p.r2,
              focus = (idx == nil and (name or "") == "") and "name" or nil, buf = "", err = nil, confirmDel = false }
  if ui.edit.focus == "name" then ui.edit.buf = "" end
  ui.page = "edit"
end

local FIELDS = { "name", "minY", "maxY", "r1", "r2" }

-- Typing into a field ends when you press Enter/Tab or tap anything else
local function commitFocus(e)
  if not e or not e.focus then return end
  local f, b = e.focus, e.buf
  if f == "name" then
    e.name = b:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, NAME_MAX)
  elseif b ~= "" and b ~= "-" then
    local v = math.floor(tonumber(b) or 0)
    if f == "minY" or f == "maxY" then e[f] = clampY(v) else e[f] = clampR(v) end
  end
  e.focus, e.buf = nil, ""
end

local function startFocus(e, f)
  commitFocus(e)
  e.focus = f
  e.buf = (f == "name") and e.name or ""
end

local function validate(e)
  if e.name == "" then return "Give it a name" end
  for i, p in ipairs(cfg.presets) do
    if i ~= e.idx and p.name:lower() == e.name:lower() then return "There's already a preset called " .. p.name end
  end
  if e.minY > e.maxY then return "Min Y is above Max Y" end
  if e.r1 > e.r2 then return "From ring is past To ring" end
end

local function savePreset()
  local e = ui.edit
  commitFocus(e)
  local err = validate(e)
  if err then e.err = err; return end
  local new = { name = e.name, minY = e.minY, maxY = e.maxY, r1 = e.r1, r2 = e.r2 }
  if e.idx and cfg.presets[e.idx] then
    local old = cfg.presets[e.idx]
    -- Piggers that had the old version picked (not started yet) get the new one picked instead
    for _, dd in pairs(cfg.diggers) do
      if isSelected(dd, old) then dd.pMin, dd.pMax, dd.pR1, dd.pR2 = new.minY, new.maxY, new.r1, new.r2 end
    end
    cfg.presets[e.idx] = new
  else
    cfg.presets[#cfg.presets + 1] = new
  end
  saveCfg()
  ui.edit, ui.page = nil, "presets"
  say(("Saved %s: pick it on a Pigger's page."):format(new.name))
end

local function deletePreset(idx)
  local p = cfg.presets[idx]
  if not p then return end
  table.remove(cfg.presets, idx)
  saveCfg()
  say(("Deleted %s. Piggers keep what they're running."):format(p.name), K.orange)
end

local function movePreset(idx, dir)
  local j = idx + dir
  if j < 1 or j > #cfg.presets then return end
  cfg.presets[idx], cfg.presets[j] = cfg.presets[j], cfg.presets[idx]
  saveCfg()
end

local function drawPresets(w, h)
  header(w, "< PRESETS", ("%d preset%s"):format(#cfg.presets, #cfg.presets == 1 and "" or "s"))
  hit(1, 1, 12, 1, function() ui.page = "overview" end)
  local top, bottom = 3, h - 2
  local per = math.max(1, bottom - top + 1)
  local pages = math.max(1, math.ceil(#cfg.presets / per))
  ui.lscroll = math.max(1, math.min(ui.lscroll or 1, pages))
  if #cfg.presets == 0 then at(2, top, "No presets yet: + New", K.grey) end
  local arrows = w >= 40
  for i = 1, per do
    local idx = (ui.lscroll - 1) * per + i
    local p = cfg.presets[idx]
    if not p then break end
    local y = top + i - 1
    local bg = (i % 2 == 0) and K.grey or K.black
    at(1, y, (" "):rep(w), K.white, bg)
    at(2, y, pad(p.name, NAME_MAX), K.white, bg)
    local infoX = NAME_MAX + 4
    local infoW = w - infoX - (arrows and 7 or 1)
    local info = ("Y %d..%d  %s"):format(p.minY, p.maxY, ringText(p.r1, p.r2))
    if #info > infoW then info = ("Y %d..%d  rings %d-%d"):format(p.minY, p.maxY, p.r1, p.r2) end
    if infoW > 6 then at(infoX, y, pad(info, infoW), K.lightGrey, bg) end
    hit(1, y, w - (arrows and 7 or 0), y, function() openEditor(idx) end)
    if arrows then
      smallButton(w - 6, y, "^", idx > 1 and K.lightBlue or bg, function() movePreset(idx, -1) end)
      smallButton(w - 3, y, "v", idx < #cfg.presets and K.lightBlue or bg, function() movePreset(idx, 1) end)
    end
  end
  at(1, h, (" "):rep(w))
  local x = smallButton(2, h, "+ New", K.lime, function() openEditor(nil) end)
  x = smallButton(x, h, "Back", K.grey, function() ui.page = "overview" end, K.white)
  if pages > 1 then
    local label = ("%d/%d"):format(ui.lscroll, pages)
    local px = w - #label - 9
    if px > x then
      smallButton(px, h, "<", ui.lscroll > 1 and K.cyan or K.grey, function() ui.lscroll = ui.lscroll - 1 end)
      at(px + 4, h, label, K.lightGrey)
      smallButton(w - 3, h, ">", ui.lscroll < pages and K.cyan or K.grey, function() ui.lscroll = ui.lscroll + 1 end)
    end
  end
end

local function drawEdit(w, h, kind)
  local e = ui.edit
  if not e then ui.page = "presets"; return drawPresets(w, h) end
  header(w, e.idx and ("< EDIT " .. (cfg.presets[e.idx] and cfg.presets[e.idx].name or "")) or "< NEW PRESET")
  hit(1, 1, 12, 1, function() ui.edit, ui.page = nil, "presets" end)
  local cw = math.min(w - 2, 46)
  local x, y = 2, 3
  -- Name
  local nf = e.focus == "name"
  at(x, y, "Name", K.white)
  local nx = x + 11
  local nw = math.min(NAME_MAX + 2, cw - 11)
  local ntxt = nf and (e.buf .. "_") or (e.name ~= "" and e.name or "tap to type")
  at(nx, y, pad(" " .. ntxt, nw), nf and K.black or (e.name ~= "" and K.white or K.lightGrey), nf and K.white or K.grey)
  hit(nx, y, nx + nw - 1, y, function()
    startFocus(e, "name")
    if kind == "monitor" then say("Type the name on the computer's keyboard", K.yellow) end
  end)
  y = y + 2
  local yS = cw >= 36 and { { "-5", -5 }, { "-1", -1 }, { "+1", 1 }, { "+5", 5 } } or { { "-", -1 }, { "+", 1 } }
  local rS = cw >= 36 and { { "-10", -10 }, { "-1", -1 }, { "+1", 1 }, { "+10", 10 } } or { { "-", -1 }, { "+", 1 } }
  local rows = {
    { "Min Y", "minY", yS }, { "Max Y", "maxY", yS }, { "From ring", "r1", rS }, { "To ring", "r2", rS },
  }
  for _, r in ipairs(rows) do
    local key = r[2]
    numRow(x, y, cw, r[1], e[key], r[3], function(dv)
      if key == "minY" or key == "maxY" then e[key] = clampY(e[key] + dv) else e[key] = clampR(e[key] + dv) end
      e.err = nil
    end, function()
      startFocus(e, key)
      if kind == "monitor" then say("Type the number on the computer's keyboard", K.yellow) end
    end, e.focus == key, e.buf)
    y = y + 1
  end
  y = y + 1
  -- What it means
  local passes = 0
  do local c = e.maxY - 1; while c + 1 >= e.minY and c >= Y_MIN do passes = passes + 1; c = c - 3 end end
  local info = {
    { ("Mines Y %d..%d: %d pass%s of 3 levels"):format(e.minY, e.maxY, passes, passes == 1 and "" or "es"), K.lightGrey },
    { e.r1 > 1 and ("Square %dx%d, skipping the middle %dx%d"):format(sq(e.r2), sq(e.r2), sq(e.r1 - 1), sq(e.r1 - 1))
        or ("Square %dx%d around the shaft"):format(sq(e.r2), sq(e.r2)), K.lightGrey },
  }
  if e.r2 > 24 then info[#info + 1] = { "Is all of that force-loaded? Unloaded = he stops.", K.orange } end
  if e.err then info[#info + 1] = { e.err, K.red } end
  for _, l in ipairs(info) do
    if y <= h - 2 then at(x, y, pad(l[1], w - 2), l[2]) end
    y = y + 1
  end
  -- Buttons
  local by = h - 1
  local tall = h - 1 - y >= 3
  local bh = tall and 3 or 1
  by = h - bh + 1
  if kind == "term" then by = h - bh end  -- term keeps its bottom row for the command bar
  local bw = math.max(8, math.floor((cw - 2) / 3))
  button(x, by, bw, bh, "Save", K.lime, savePreset)
  button(x + bw + 1, by, bw, bh, "Cancel", K.grey, function() ui.edit, ui.page = nil, "presets" end, K.white)
  if e.idx then
    button(x + 2 * (bw + 1), by, bw, bh, e.confirmDel and "Sure?" or "Delete", e.confirmDel and K.orange or K.red, function()
      if e.confirmDel then deletePreset(e.idx); ui.edit, ui.page = nil, "presets" else e.confirmDel = true end
    end)
  end
end

---------------------------------------------------------------------------
-- Rules: when Piggers drink lava, what the Nether keeps, what Pigger throws away
---------------------------------------------------------------------------
local function keepList()
  local out = {}
  for name, c in pairs(cfg.keep) do out[#out + 1] = { name, c } end
  table.sort(out, function(a, b) return pretty(a[1]) < pretty(b[1]) end)
  return out
end
local function setKeep(name, c)
  cfg.keep[name] = (c and c > 0) and math.min(c, 99999) or nil
  saveCfg()
end
local function setLava(key, v)
  v = math.max(5, math.min(95, v))
  if key == "hungryAt" then cfg.hungryAt = math.min(v, cfg.fullAt - 5) else cfg.fullAt = math.max(v, cfg.hungryAt + 5) end
  saveCfg()
  for id in pairs(cfg.diggers) do sendNow[id] = true end
end

local function drawRules(w, h, kind)
  header(w, "< RULES", ("%d kept, %d junk"):format(#keepList(), #cfg.junk))
  hit(1, 1, 10, 1, function() ui.page = "overview" end)
  local y = 3
  -- Lava
  at(2, y, "LAVA", K.grey)
  local x = 8
  local t1 = ("drink under %d%%"):format(cfg.hungryAt)
  at(x, y, t1, K.white); x = x + #t1 + 1
  x = smallButton(x, y, "-", K.grey, function() setLava("hungryAt", cfg.hungryAt - 5) end, K.white) - 1
  x = smallButton(x, y, "+", K.grey, function() setLava("hungryAt", cfg.hungryAt + 5) end, K.white) + 1
  local t2 = ("until %d%%"):format(cfg.fullAt)
  if x + #t2 + 8 <= w then
    at(x, y, t2, K.white); x = x + #t2 + 1
    x = smallButton(x, y, "-", K.grey, function() setLava("fullAt", cfg.fullAt - 5) end, K.white) - 1
    smallButton(x, y, "+", K.grey, function() setLava("fullAt", cfg.fullAt + 5) end, K.white)
  else
    y = y + 1
    at(8, y, t2, K.white)
    local x2 = 8 + #t2 + 1
    x2 = smallButton(x2, y, "-", K.grey, function() setLava("fullAt", cfg.fullAt - 5) end, K.white) - 1
    smallButton(x2, y, "+", K.grey, function() setLava("fullAt", cfg.fullAt + 5) end, K.white)
  end
  y = y + 2
  -- Keep
  at(2, y, pad("KEEP IN THE NETHER (the rest goes home)", w - 10), K.grey)
  at(w - 5, y, "have", K.grey)
  y = y + 1
  local list = keepList()
  -- The junk list, wrapped (worked out first: it gets the rows it needs, up to 6)
  local jline, jlines = "", {}
  for _, j in ipairs(cfg.junk) do
    local word = j:gsub("^minecraft:", "")
    local add = (jline == "" and "" or ", ") .. word
    if #jline + #add > w - 3 then jlines[#jlines + 1] = jline .. ","; jline = word else jline = jline .. add end
  end
  if jline ~= "" then jlines[#jlines + 1] = jline end
  if #jlines == 0 then jlines[1] = "nothing: he brings everything home" end
  local junkRows = math.min(6, #jlines)
  local rows = math.max(2, h - y - junkRows - 3)
  local pages = math.max(1, math.ceil(#list / rows))
  ui.kscroll = math.max(1, math.min(ui.kscroll or 1, pages))
  for i = 1, rows do
    local e = list[(ui.kscroll - 1) * rows + i]
    if not e then
      if i == 1 then at(2, y, "Nothing kept: everything goes home", K.grey); y = y + 1 end
      break
    end
    local name, c = e[1], e[2]
    local bg = (i % 2 == 0) and K.grey or K.black
    at(1, y, (" "):rep(w), K.white, bg)
    local bx = w - 25
    at(2, y, pad(pretty(name), math.max(4, bx - 3)), K.white, bg)
    at(bx, y, ("%5d"):format(c), K.cyan, bg)
    bx = bx + 6
    bx = smallButton(bx, y, "-", K.lightGrey, function() setKeep(name, c - (c > 16 and 16 or 1)) end) - 1
    bx = smallButton(bx, y, "+", K.lightGrey, function() setKeep(name, c + (c >= 16 and 16 or 1)) end) - 1
    smallButton(bx, y, "x", K.red, function() setKeep(name, 0); say("Not keeping " .. pretty(name) .. ": it goes home.", K.orange) end)
    local have = barrel.stock[name] or 0
    at(w - 6, y, ("%6d"):format(have), have < c and K.orange or K.lime, bg)
    y = y + 1
  end
  if pages > 1 then
    smallButton(2, y, "<", ui.kscroll > 1 and K.cyan or K.grey, function() ui.kscroll = ui.kscroll - 1 end)
    at(6, y, ("%d/%d"):format(ui.kscroll, pages), K.lightGrey)
    smallButton(12, y, ">", ui.kscroll < pages and K.cyan or K.grey, function() ui.kscroll = ui.kscroll + 1 end)
    y = y + 1
  end
  y = y + 1
  -- Junk
  y = math.min(y, h - 1 - junkRows)
  if y <= h - 2 then
    at(2, y, "PIGGER THROWS AWAY (underground)", K.grey); y = y + 1
    for i, l in ipairs(jlines) do
      if y > h - 1 then break end
      if y == h - 1 and i < #jlines then l = "... /unjunk <item> to take one off" end
      at(2, y, pad(l, w - 2), K.lightGrey); y = y + 1
    end
  end
  -- Footer
  at(1, h, (" "):rep(w))
  local fx = smallButton(2, h, "+ Keep", K.lime, function()
    termUi.cmd = "/keep "
    if kind == "monitor" then say("Type it on the computer: /keep <item> <count>", K.yellow) end
  end)
  fx = smallButton(fx, h, "+ Junk", K.orange, function()
    termUi.cmd = "/junk "
    if kind == "monitor" then say("Type it on the computer: /junk <item>  (/unjunk to undo)", K.yellow) end
  end)
  smallButton(fx, h, "Back", K.grey, function() ui.page = "overview" end, K.white)
end

---------------------------------------------------------------------------
-- Commands typed on the computer (bottom row): /presets, /new, /edit, /delete, /home, /help
---------------------------------------------------------------------------
local HELP = "/rules /keep <item> <n> /junk /unjunk <item> /assign /presets /new /edit /delete /reboot /home"

local function runCommand(line)
  local cmd, arg = line:match("^/?(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  ui = termUi
  if cmd == "" or cmd == "help" or cmd == "?" then say(HELP, K.lightBlue)
  elseif cmd == "presets" or cmd == "preset" or cmd == "settings" or cmd == "p" then ui.page, ui.edit = "presets", nil
  elseif cmd == "home" or cmd == "back" or cmd == "overview" then ui.page, ui.edit = "overview", nil
  elseif cmd == "rules" or cmd == "keeps" then ui.page = "rules"
  elseif cmd == "assign" or cmd == "barrels" or cmd == "dock" then openAssign()
  elseif cmd == "keep" then
    local item, n = arg:match("^(.-)%s+(%d+)$")
    item = resolveItem(item or arg)
    if not item then say("/keep <item> <count>, e.g. /keep bucket 4  (0 = stop keeping it)", K.red); return end
    n = tonumber(n) or 64
    setKeep(item, n)
    ui.page = "rules"
    say(n > 0 and ("Keeping %d %s in the Nether."):format(n, pretty(item)) or ("Not keeping %s: it goes home."):format(pretty(item)),
      n > 0 and K.lime or K.orange)
  elseif cmd == "junk" or cmd == "unjunk" then
    local item = resolveItem(arg)
    if not item then say("/" .. cmd .. " <item>, e.g. /" .. cmd .. " netherrack", K.red); return end
    local short = item:gsub("^minecraft:", "")
    for i = #cfg.junk, 1, -1 do
      local j = cfg.junk[i]
      if j == short or j == item or ("minecraft:" .. j) == item then table.remove(cfg.junk, i) end
    end
    if cmd == "junk" then cfg.junk[#cfg.junk + 1] = short end
    saveCfg()
    for id in pairs(cfg.diggers) do sendNow[id] = true end
    ui.page = "rules"
    say(cmd == "junk" and ("Pigger throws %s away now."):format(pretty(item)) or ("Pigger brings %s home now."):format(pretty(item)),
      cmd == "junk" and K.orange or K.lime)
  elseif cmd == "new" or cmd == "add" then openEditor(nil, arg)
  elseif cmd == "reboot" or cmd == "restart" then
    local a = arg:lower()
    if a == "" then say("/reboot <pigger number or name> or /reboot all", K.red); return end
    local hits = {}
    for id, dd in pairs(cfg.diggers) do
      if not dd.retired then
        local lbl = (dd.label or nameOf(dd.num)):lower()
        if a == "all" or lbl == a or tonumber(a) == dd.num or lbl:find(a, 1, true) then hits[#hits + 1] = id end
      end
    end
    if #hits == 0 then say("No Pigger matches " .. arg, K.red); return end
    if a ~= "all" and #hits > 1 then say(arg .. " matches " .. #hits .. " Piggers: be more exact", K.red); return end
    for _, id in ipairs(hits) do requestReboot(id) end
    say(#hits == 1 and ((cfg.diggers[hits[1]].label or "Pigger") .. ": reboot sent.") or
      ("Reboot sent to " .. #hits .. " Piggers."), K.purple)
  elseif cmd == "edit" or cmd == "delete" or cmd == "remove" or cmd == "del" then
    local idx = findPreset(arg)
    if not idx then say(arg == "" and ("/" .. cmd .. " <preset name>") or ("No preset called " .. arg), K.red); return end
    openEditor(idx)
    if cmd ~= "edit" then ui.edit.confirmDel = true; say("Tap Sure? (or Enter) to delete " .. cfg.presets[idx].name, K.orange) end
  else
    say("Unknown command. " .. HELP, K.red)
  end
end

-- Bottom row of the computer's own screen
local function drawCmdBar(w, h)
  local y = h - 1
  if ui.page == "presets" or ui.page == "edit" then y = h end
  if ui.page == "digger" and not ui.cmd then return end
  if ui.page == "presets" and not ui.cmd then return end
  if ui.page == "rules" and not ui.cmd then return end
  if ui.cmd then
    at(1, y, pad("> " .. ui.cmd .. "_", w), K.white, K.grey)
  elseif ui.page == "overview" then
    at(1, y, pad(" /rules /assign /presets  /help for the rest", w), K.grey)
  elseif ui.page == "edit" then
    at(1, y, pad(ui.edit and ui.edit.focus and " Enter/Tab: next field" or " Enter: save   /home   /presets", w), K.grey)
  end
end

local function drawPigger(w, h)
  local id = ui.id
  local dd = cfg.diggers[id]
  if not dd then ui.page = "overview"; return drawOverview(w, h) end
  header(w, "< " .. (dd.label or nameOf(dd.num)), "computer #" .. id)
  hit(1, 1, math.min(w, 14), 1, function() ui.page, ui.confirmRetire = "overview", nil end)
  if w >= 44 then
    local cw = math.floor((w - 3) / 2)
    local y = drawStatus(id, 2, 3, cw, h)
    drawHaul(id, 2, y + 1, cw, h)
    if not dd.retired then drawControls(id, cw + 3, 3, w - cw - 3, h) end
  else
    local y = drawStatus(id, 1, 3, w, h)
    if not dd.retired then
      drawControls(id, 1, y + 1, w, h)
    else
      drawHaul(id, 1, y + 1, w, h)
    end
  end
  smallButton(w - 7, h, "Back", K.grey, function() ui.page, ui.confirmRetire = "overview", nil end, K.white)
end

local uiBusy = false   -- /assign has the computer's screen
local function draw()
  for _, v in ipairs(views) do
    d = v.dev()
    if d and not (uiBusy and v.kind == "term") then
      hits = {}
      ui = v.ui
      local ok = pcall(function()
        if v.kind == "monitor" then d.setTextScale(TEXT_SCALE) end
        local w, h = d.getSize()
        if not w then return end
        d.setBackgroundColour(K.black); d.clear()
        if ui.page == "digger" then drawPigger(w, h)
        elseif ui.page == "presets" then drawPresets(w, h)
        elseif ui.page == "edit" then drawEdit(w, h, v.kind)
        elseif ui.page == "rules" then drawRules(w, h, v.kind)
        else drawOverview(w, h) end
        if v.kind == "term" then drawCmdBar(w, h) end
      end)
      v.hits = hits
      if not ok and v.kind == "monitor" then mon, monSide = findMonitor() end
    end
  end
end

-- /assign: the same screen as storage's (assignui.lua). It takes over the computer's own screen.
local AUI = dofile("assignui.lua")
local assignRunning = false
openAssign = function()
  if ui ~= termUi or assignRunning then
    say("Barrels: type /assign on the Nether Foreman computer", K.yellow)
    return
  end
  assignRunning, uiBusy = true, true
  local ok, err = pcall(AUI.run, {
    title = "NETHER BARRELS",
    hint = "Click one to change it.",
    emptyText = "Nothing assigned yet. + Add: a Dock, an Output, a Stock.",
    types = TYPES, names = cfg.names, call = call,
    typeOf = typeOf, assign = assignJob, unassign = unassign,
    inventories = inventories,
    assignedNames = function()
      local out = {}
      for _, field in pairs(LISTS) do for _, n in ipairs(cfg[field]) do out[#out + 1] = n end end
      return out
    end,
    candidate = function(n) return true end,
    single = function() return nil end,
    defaultKey = function()
      if #cfg.docks == 0 then return "dock" end
      if #cfg.outputs == 0 then return "output" end
      if #cfg.stocks == 0 then return "stock" end
      return "input"
    end,
    problem = function()
      if #cfg.docks == 0 then return "No DOCK yet: Pigger's barrel." end
      if #cfg.outputs == 0 then return "No OUTPUT yet: nothing can go home." end
      if #cfg.stocks == 0 then return "No STOCK yet: spare buckets and fuel go home too." end
    end,
    warn = function(e, d)
      if e.key ~= e.orig and (d.count or 0) > 0 and (e.key == "dock" or e.key == "input") then
        return ("Its %d items get kept or sent home."):format(d.count)
      end
    end,
    extra = {
      key = "dock", plain = false,
      init = function(n) return { id = cfg.dockFor[n] } end,
      show = function(st)
        local dd = st.id and cfg.diggers[st.id]
        return "For", dd and (dd.label or nameOf(dd.num)) or "any Pigger (tap to pick one)"
      end,
      click = function(n, st)   -- cycle: any -> each Pigger -> any
        local ids = {}
        for id, dd in pairs(cfg.diggers) do if not dd.retired then ids[#ids + 1] = id end end
        table.sort(ids, function(a, b) return cfg.diggers[a].num < cfg.diggers[b].num end)
        local nextId = ids[1]
        for i, id in ipairs(ids) do if id == st.id then nextId = ids[i + 1] end end
        st.id = nextId
      end,
      save = function(n, st) cfg.dockFor[n] = st.id end,
    },
    hold = function() paused = true; while workerBusy do os.sleep(0.2) end end,
    release = function() paused = false end,
    beforeSave = function() while workerBusy do os.sleep(0.1) end end,
    afterSave = function() saveCfg() end,
    itemTotals = itemTotals,
  })
  assignRunning, uiBusy = false, false
  paused = false
  termUi.page = "overview"
  if not ok then say("Assign screen error: " .. tostring(err), K.red) end
  draw()
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function sendOrder(id)
  local dd = cfg.diggers[id]
  if dd.reboot and os.epoch("utc") - (dd.rebootAt or 0) > REBOOT_WAIT then
    dd.reboot, dd.rebootAt = nil, nil
    saveCfg()
    say((dd.label or "A Pigger") .. " never confirmed its reboot: old program? Reboot it by hand once.", K.orange)
  end
  local list = {}
  for name in pairs(capped) do list[#list + 1] = name end
  rednet.send(id, {
    type = "cmd", to = id, want = dd.retired and "dock" or dd.want, minY = dd.minY, maxY = dd.maxY,
    r1 = dd.r1 or 1, r2 = dd.r2 or DEF_R2, seq = dd.seq, reboot = dd.reboot, retired = dd.retired == true, capped = list,
    junk = cfg.junk, hungryAt = cfg.hungryAt, fullAt = cfg.fullAt,
  }, PROTOCOL)
end

local function netLoop()
  local opened = 0
  radioOK = false
  peripheral.find("modem", function(name, m)
    rednet.open(name); opened = opened + 1
    if m.isWireless() then radioOK = true end
    return false
  end)
  if opened == 0 then
    say("No modem! I need an ender modem to reach the Piggers.", K.red)
    while true do draw(); os.sleep(5) end
  end
  local lastSend = -100
  while true do
    local from, msg, proto = rednet.receive(1)
    if type(msg) == "table" and proto == PROTOCOL then
      if msg.type == "register" and msg.id == from then
        local num = assign(from, msg.want)
        local label = nameOf(num)
        rednet.send(from, { type = "assigned", id = from, num = num, label = label }, PROTOCOL)
        say(("%s joined the crew."):format(label))
        sendNow[from] = true
      elseif msg.type == "dock_req" and msg.id == from then
        if msg.seq ~= servedSeq[from] then
          servedSeq[from] = msg.seq
          requests[#requests + 1] = { id = from, seq = msg.seq, bucket = msg.bucket == true, fuel = tonumber(msg.fuel) or 0 }
          os.queueEvent("nether_work")
        elseif lastReply[from] and lastReply[from].seq == msg.seq then
          rednet.send(from, lastReply[from], PROTOCOL)   -- he missed my answer: say it again
        end
      elseif msg.type == "dock_done" and msg.id == from then
        for dn, hd in pairs(holds) do if hd.id == from then holds[dn] = nil end end
        os.queueEvent("nether_work")
      elseif msg.type == "status" and msg.id == from then
        live[from] = { s = msg, seen = os.clock() }
        local dd = cfg.diggers[from]
        if dd and dd.reboot and msg.rebootDone == dd.reboot then
          if msg.state == "rebooting" then
            dd.rebootSeen = true
          else
            -- Back up after the reboot: stop asking
            dd.reboot, dd.rebootAt, dd.rebootSeen = nil, nil, nil
            saveCfg()
            say((dd.label or "Pigger") .. " is back up and carrying on.", K.lime)
          end
        end
        if not dd and tonumber(msg.num) and not numTaken(tonumber(msg.num), from) then
          -- A Pigger I don't know that already has a number (e.g. foreman.cfg was lost): adopt it
          dd = newEntry(tonumber(msg.num))
          dd.label = msg.label or nameOf(dd.num)
          if msg.minY then dd.minY, dd.maxY, dd.pMin, dd.pMax = msg.minY, msg.maxY, msg.minY, msg.maxY end
          if msg.maxRing then
            dd.r1, dd.r2 = msg.minRing or 1, msg.maxRing
            dd.pR1, dd.pR2 = dd.r1, dd.r2
          end
          if msg.want then dd.want = msg.want end
          if msg.seq then dd.seq = msg.seq end
          if msg.retired then dd.retired = true; cfg.retiredNums[dd.num] = dd.label end
          cfg.diggers[from] = dd
          cfg.nextNum = math.max(cfg.nextNum, dd.num + 1)
          saveCfg()
        elseif dd and msg.label and msg.label ~= dd.label and not dd.retired then
          dd.label = msg.label; saveCfg()
        end
      end
    elseif type(msg) == "table" and proto == BASE and msg.type == "storage" then
      storageSeen = os.clock()
      local set = {}
      for _, n in ipairs(type(msg.overcap) == "table" and msg.overcap or {}) do set[n] = true end
      capped = set
    end
    local all = os.clock() - lastSend >= SEND_EVERY
    for id in pairs(cfg.diggers) do
      if all or sendNow[id] then sendOrder(id) end
    end
    sendNow = {}
    if all then lastSend = os.clock() end
    draw()
  end
end

-- Keys: typing into a preset field (whichever screen last tapped one), else the command bar
local focusView = nil
local function handleKey(e, a)
  local v = focusView
  if not (v and v.ui.page == "edit" and v.ui.edit and v.ui.edit.focus) then
    v = (termUi.page == "edit" and termUi.edit and termUi.edit.focus) and views[2] or nil
  end
  if v and not termUi.cmd then
    ui = v.ui
    local ed = ui.edit
    if e == "char" then
      local ok = ed.focus == "name" and #ed.buf < NAME_MAX
        or ed.focus ~= "name" and (a:match("%d") or (a == "-" and ed.buf == "")) and #ed.buf < 4
      if ok then ed.buf = ed.buf .. a end
    elseif e == "paste" and ed.focus == "name" then
      ed.buf = (ed.buf .. a):sub(1, NAME_MAX)
    elseif a == keys.backspace then ed.buf = ed.buf:sub(1, -2)
    elseif a == keys.enter or a == keys.numPadEnter or a == keys.tab then
      local fi = 1
      for i, f in ipairs(FIELDS) do if f == ed.focus then fi = i end end
      commitFocus(ed)
      if fi < #FIELDS then startFocus(ed, FIELDS[fi + 1]) end
    end
    ui.edit.err = nil
    return
  end
  -- Command bar (computer screen)
  ui = termUi
  if e == "char" or e == "paste" then
    if ui.cmd == nil and not (e == "char" and a == "/") then return end   -- commands start with /
    ui.cmd = ((ui.cmd or "") .. a):sub(1, 60)
  elseif a == keys.backspace and ui.cmd then
    ui.cmd = ui.cmd:sub(1, -2)
    if ui.cmd == "" then ui.cmd = nil end
  elseif (a == keys.enter or a == keys.numPadEnter) then
    if ui.cmd then
      local line = ui.cmd; ui.cmd = nil
      runCommand(line)
    elseif ui.page == "edit" and ui.edit then
      if ui.edit.confirmDel then
        deletePreset(ui.edit.idx); ui.edit, ui.page = nil, "presets"
      else
        savePreset()
      end
    end
  end
end

local function inputLoop()
  while true do
    local e, a, b, c = os.pullEvent()
    local v, x, y
    if e == "monitor_touch" and a == monSide then v, x, y = views[1], b, c
    elseif e == "mouse_click" then v, x, y = views[2], b, c
    elseif e == "mouse_scroll" then
      local u = views[2].ui
      if u.page == "overview" then u.scroll = u.scroll + a
      elseif u.page == "presets" then u.lscroll = u.lscroll + a
      elseif u.page == "digger" then u.pscroll = u.pscroll + a
      elseif u.page == "rules" then u.kscroll = (u.kscroll or 1) + a end
      draw()
    elseif e == "char" or e == "key" or e == "paste" then
      handleKey(e, a); draw()
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      mon, monSide = findMonitor(); draw()
    end
    if v then
      ui = v.ui
      local wasEditing = ui.page == "edit" and ui.edit
      for _, r in ipairs(v.hits) do
        if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then
          if wasEditing then commitFocus(ui.edit) end
          r.fn()
          if ui.page == "edit" and ui.edit and ui.edit.focus then focusView = v end
          break
        end
      end
      draw()
    end
  end
end

-- Barrels: every TICK seconds (sooner when a Pigger asks for something)
local function workerLoop()
  while true do
    if not paused then
      workerBusy = true
      local ok, err = pcall(barrelPass)
      workerBusy = false
      if not ok then say("Barrels: " .. tostring(err), K.red) end
      if lastNote then say(lastNote, K.orange); lastNote = nil end
      draw()
    end
    local t = os.startTimer(TICK)
    while true do
      local e, id = os.pullEvent()
      if (e == "timer" and id == t) or e == "nether_work" then break end
    end
  end
end

loadCfg()
draw()
parallel.waitForAny(netLoop, inputLoop, workerLoop)
