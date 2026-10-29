-- fm_barrels.lua  --  Foreman engine: the barrels on the Foreman's cable. Jobs (/assign), routing (keep or send
-- home, Overflow when home is full), the lava factory's two barrels, and what a miner asks his dock for.
-- A part of fm.lua (one shared environment: see there). Everything on the cable is a barrel.
local function listRemove(list, n) for i = #list, 1, -1 do if list[i] == n then table.remove(list, i) end end end
local function listAdd(list, n) for _, x in ipairs(list) do if x == n then return end end; list[#list + 1] = n end

BUCKET, LAVA = "minecraft:bucket", "minecraft:lava_bucket"
-- Fuel the dock hands out, best first (fuel units each)
FUELS = {
  { "minecraft:lava_bucket", 1000 }, { "minecraft:coal_block", 800 }, { "minecraft:blaze_rod", 120 },
  { "minecraft:coal", 80 }, { "minecraft:charcoal", 80 },
}

local JOBS = {
  dock     = { key = "dock",   label = "Dock",   short = "Dock",   tag = "DOCK",   col = colours.yellow,
    about = ("%s's barrel: I empty it, and put in %s when he asks. One per %s."):format(P.bird,
      P.lava and "a bucket or fuel" or "fuel", P.bird) },
  output   = { key = "output", label = "Output", short = "Output", tag = "OUTPUT", col = colours.cyan,
    about = ("Goes home: barrel > hopper > ender chest. Everything %s doesn't keep."):format(P.place) },
  stock    = { key = "stock",  label = "Stock",  short = "Stock",  tag = "STOCK",  col = colours.lime,
    about = ("Stays in %s: what the Rules keep (%s). Extra goes home."):format(P.place,
      P.neverHome and "lava and empty buckets, fuel" or "spare buckets, fuel") },
  input    = { key = "input",  label = "Input",  short = "Input",  tag = "INPUT",  col = colours.lightBlue,
    about = ("Drop things in by hand: kept or sent home like %s's haul."):format(P.bird) },
  ignore   = { key = "ignore", label = "Ignore", short = "Ignore", tag = "IGNORE", col = colours.lightGrey,
    about = "Never touched: I pretend it isn't there." },
  factory_in  = { key = "factory_in", label = "Factory in", short = "Fact in", tag = "FACT IN", col = colours.orange,
    about = "The lava factory's input: I keep it supplied with empty buckets." },
  factory_out = { key = "factory_out", label = "Factory out", short = "Fact out", tag = "FACT OUT", col = colours.red,
    about = "The lava factory's output: I move its lava buckets to Stock, so it never fills up." },
  overflow = { key = "overflow", label = "Overflow", short = "Overflow", tag = "OVERFLOW", col = colours.purple,
    about = "Haul waits here when every Output is full, and drains back first when there's room." },
}
local FIELD = { dock = "docks", output = "outputs", stock = "stocks", input = "inputs", ignore = "ignored",
  factory_in = "factoryIns", factory_out = "factoryOuts", overflow = "overflows" }
TYPES, LISTS = {}, {}
for _, k in ipairs(P.jobs or {}) do TYPES[#TYPES + 1] = JOBS[k]; LISTS[k] = FIELD[k] end

function typeOf(n)
  for key, field in pairs(LISTS) do
    for _, x in ipairs(cfg[field] or {}) do if x == n then return key end end
  end
end
function unassign(n)
  for _, field in pairs(LISTS) do listRemove(cfg[field], n) end
  cfg.dockFor[n] = nil
end
function assignJob(n, key)
  unassign(n)
  listAdd(cfg[LISTS[key]], n)
end

-- CC keeps only 256 queued events and drops the rest. Every call that waits for its tick gets its answer as
-- an event, so hundreds of calls at once (11 full docks, a move per slot) lose answers and their tasks wait
-- forever: the pass hangs and the screen goes stale. So no more than MAX_CALLS wait at the same time.
MAX_CALLS = 100
local inFlight, gated, callGen = 0, 0, 0
-- A pass that is abandoned (PAUSED, an error in a sibling task, the watchdog) leaves tasks stuck inside call()
-- that never get to count themselves out. resetCalls() starts a new generation: the old ones are forgotten,
-- and a call that began in an older generation doesn't touch the counters when it ends.
function resetCalls()
  callGen, inFlight, gated = callGen + 1, 0, 0
  os.queueEvent("fm_gate")
end
function call(name, method, ...)
  local gen = callGen
  while inFlight >= MAX_CALLS and gen == callGen do
    gated = gated + 1
    os.pullEvent("fm_gate")
    if gen == callGen then gated = math.max(0, gated - 1) end
  end
  gen = callGen
  inFlight = inFlight + 1
  local ok, a, b = pcall(peripheral.call, name, method, ...)
  if gen == callGen then
    inFlight = math.max(0, inFlight - 1)
    if gated > 0 then os.queueEvent("fm_gate") end
  end
  if ok then return a, b end
  return nil, a
end
function inventories()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "inventory") then out[#out + 1] = n end
  end
  table.sort(out)
  return out
end
function itemTotals()
  local t = {}
  for _, n in ipairs(inventories()) do
    local c = 0
    for _, it in pairs(call(n, "list") or {}) do c = c + it.count end
    t[n] = c
  end
  return t
end

paused, workerBusy = false, false   -- paused: /assign is watching for a dropped item
-- What the last pass saw: Stock by item, Output room, docks' item counts, every item name seen,
-- lava waiting in Factory out, Factory in's and Overflow's slots
barrel = { stock = {}, outFree = 0, outSlots = 0, outFull = false, docks = {}, seen = {}, factoryLava = 0, errs = {}, bad = {},
           factoryIn = { used = 0, size = 0 }, overflow = { used = 0, size = 0, items = 0 } }
requests = {}    -- dock requests waiting for the worker: { id, seq, bucket, fuel }
holds = {}       -- dock name -> { id, untilT }: left alone while its miner takes his supplies
lastReply = {}   -- id -> the last dock_ready sent (repeated if he asks again with the same seq)
servedSeq = {}   -- id -> seq of the last request taken on
local NEVER_HOME = P.neverHome or {}   -- items that never go home (the MD's buckets)

-- Every inventory call waits for the next game tick, so a pass makes its calls side by side: fn(x) for each x
-- of the list, all at once (with 11 docks, one at a time took over a minute and the docks filled up).
function each(list, fn)
  local tasks = {}
  for _, x in ipairs(list) do tasks[#tasks + 1] = function() fn(x) end end
  if #tasks == 1 then tasks[1]() elseif #tasks > 1 then parallel.waitForAll(table.unpack(tasks)) end
end
-- A barrel's contents, read once per pass (only used to pick a barrel that already holds an item)
function listOf(n)
  local l = barrel.lists[n]
  if l == nil then l = call(n, "list") or {}; barrel.lists[n] = l end
  return l
end

-- What the Stock barrels hold, by item (and the lava waiting in Factory out)
function scanStock(fresh)
  local have, seen = {}, barrel.seen
  local reads = {}
  if fresh then   -- read again, not this pass's copy (a dock request comes after moves into Stock)
    for _, n in ipairs(cfg.stocks) do barrel.lists[n] = nil end
    for _, n in ipairs(cfg.factoryOuts) do barrel.lists[n] = nil end
  end
  for _, n in ipairs(cfg.stocks) do reads[#reads + 1] = n end
  for _, n in ipairs(cfg.factoryOuts) do reads[#reads + 1] = n end
  each(reads, listOf)
  for _, n in ipairs(cfg.stocks) do
    for _, it in pairs(listOf(n)) do
      have[it.name] = (have[it.name] or 0) + it.count
      seen[it.name] = true
    end
  end
  barrel.stock = have
  local lava = 0
  for _, n in ipairs(cfg.factoryOuts) do
    for _, it in pairs(listOf(n)) do if it.name == LAVA then lava = lava + it.count end end
  end
  barrel.factoryLava = lava
  return have
end

-- Move up to `count` of (from, slot) into the given barrels: ones already holding the item first
PAUSED = "paused"   -- error thrown to stop a barrel pass at once (/assign has opened)
function pushInto(list, from, slot, item, count)
  if paused then error(PAUSED, 0) end
  local moved = 0
  local firstPass, second = {}, {}
  if #list > 1 then   -- read the barrels not read yet this pass, all at once (30 Stock barrels one by one took 1.5 s)
    local unread = {}
    for _, n in ipairs(list) do if barrel.lists[n] == nil and not barrel.bad[n] then unread[#unread + 1] = n end end
    each(unread, listOf)
  end
  for _, n in ipairs(list) do
    if not barrel.bad[n] then
      local holds = false
      if #list > 1 then   -- (with one barrel there's nothing to choose)
        for _, it in pairs(listOf(n)) do if it.name == item then holds = true; break end end
      end
      if holds then firstPass[#firstPass + 1] = n else second[#second + 1] = n end
    end
  end
  for _, group in ipairs({ firstPass, second }) do
    for _, n in ipairs(group) do
      if moved >= count then return moved end
      local m, err = call(from, "pushItems", n, slot, count - moved)
      if not m then
        -- Most likely the two aren't on ONE wired network (a second cable or modem, or a barrel touching
        -- the computer instead of on the cable). The screen says so, the whole error goes in fm_errors.txt,
        -- and that barrel is left alone for the rest of this pass (each try costs a tick).
        local line = ("%s can't reach %s: are both on my cable? (%s)"):format((from:gsub("^.-:", "")),
          (n:gsub("^.-:", "")), tostring(err))
        barrel.moveErr = barrel.moveErr or line
        barrel.errs[#barrel.errs + 1] = ("%s -> %s: %s"):format(from, n, tostring(err))
        barrel.bad[n] = true
      end
      moved = moved + (m or 0)
    end
  end
  return moved
end

-- Home: the Outputs, then Overflow when they're full. Returns how many moved.
local function sendHome(from, slot, item, n)
  local m = pushInto(cfg.outputs, from, slot, item, n)
  if m > 0 then cfg.sent[item] = (cfg.sent[item] or 0) + m end
  if m < n then
    barrel.outFull = true
    m = m + pushInto(cfg.overflows, from, slot, item, n - m)
  end
  return m
end

-- Everything in one barrel goes to Stock (up to the keep count) or home. Empty buckets go to the lava factory,
-- and what never goes home (P.neverHome) stays in Stock. Returns items left behind.
-- (Its slots are moved side by side; Stock's count is reserved before a move, so they don't overfill it.)
function routeAll(from, stockToo)
  local left = 0
  local slots = {}
  for slot, it in pairs(call(from, "list") or {}) do slots[#slots + 1] = { slot, it } end
  each(slots, function(e)
    local slot, it = e[1], e[2]
    barrel.seen[it.name] = true
    local n = it.count
    local want = (cfg.keep[it.name] or 0) - (barrel.stock[it.name] or 0)
    if stockToo and want > 0 then
      local take = math.min(n, want)
      barrel.stock[it.name] = (barrel.stock[it.name] or 0) + take
      local m = pushInto(cfg.stocks, from, slot, it.name, take)
      barrel.stock[it.name] = barrel.stock[it.name] - (take - m)
      n = n - m
    end
    if n > 0 and it.name == BUCKET and #cfg.factoryIns > 0 then
      n = n - pushInto(cfg.factoryIns, from, slot, it.name, n)
    end
    if n > 0 and NEVER_HOME[it.name] then
      if stockToo then
        local m = pushInto(cfg.stocks, from, slot, it.name, n)
        barrel.stock[it.name] = (barrel.stock[it.name] or 0) + m
        n = n - m
      end
    elseif n > 0 then
      n = n - sendHome(from, slot, it.name, n)
    end
    left = left + n
  end)
  return left
end

-- Stock above its keep count (or with no rule at all) goes home; empty buckets above it go to the factory
function trimStock()
  local over = {}
  for name, c in pairs(barrel.stock) do
    local extra = c - (cfg.keep[name] or 0)
    if extra > 0 and (not NEVER_HOME[name] or (name == BUCKET and #cfg.factoryIns > 0)) then over[name] = extra end
  end
  if not next(over) then return end
  for _, n in ipairs(cfg.stocks) do
    for slot, it in pairs(call(n, "list") or {}) do
      local extra = over[it.name]
      if extra and extra > 0 then
        local m
        if NEVER_HOME[it.name] then m = pushInto(cfg.factoryIns, n, slot, it.name, math.min(extra, it.count))
        else
          m = pushInto(cfg.outputs, n, slot, it.name, math.min(extra, it.count))
          if m > 0 then cfg.sent[it.name] = (cfg.sent[it.name] or 0) + m
          elseif #cfg.outputs > 0 then barrel.outFull = true end
        end
        if m > 0 then
          over[it.name] = extra - m
          barrel.stock[it.name] = barrel.stock[it.name] - m
        end
      end
    end
  end
end

-- Overflow drains into the Outputs first, as soon as they have room
local function drainOverflow()
  for _, n in ipairs(cfg.overflows) do
    for slot, it in pairs(call(n, "list") or {}) do
      local m = pushInto(cfg.outputs, n, slot, it.name, it.count)
      if m > 0 then cfg.sent[it.name] = (cfg.sent[it.name] or 0) + m end
      if m < it.count then barrel.outFull = true; return end
    end
  end
end

-- The lava factory can't be stopped: a full Factory out drops its buckets on the floor, where they despawn.
-- So every lava bucket in Factory out goes to Stock while Stock has room (lava never goes home); only a full
-- Stock leaves it waiting there. An empty bucket that comes out goes back into Factory in. Factory out has its
-- own lane, every half second (fm_net.lua factoryLoop).
function factoryPass()
  local slots = {}
  for _, n in ipairs(cfg.factoryOuts) do
    for slot, it in pairs(call(n, "list") or {}) do slots[#slots + 1] = { n, slot, it } end
  end
  each(slots, function(e)
    local n, slot, it = e[1], e[2], e[3]
    do
      if it.name == LAVA then
        local m = pushInto(cfg.stocks, n, slot, LAVA, it.count)
        barrel.stock[LAVA] = (barrel.stock[LAVA] or 0) + m
        barrel.factoryLava = barrel.factoryLava - m
      elseif it.name == BUCKET then
        -- an empty bucket the factory let through: back into Factory in (or Stock if that's full)
        local m = pushInto(cfg.factoryIns, n, slot, BUCKET, it.count)
        if m < it.count then pushInto(cfg.stocks, n, slot, BUCKET, it.count - m) end
      end
    end
  end)
end

-- Take `count` of an item out of Stock (lava: then Factory out) into a dock. Returns how many moved.
function fromStock(item, count, dock)
  local moved = 0
  local sources = cfg.stocks
  if item == LAVA and #cfg.factoryOuts > 0 then
    sources = {}
    for _, n in ipairs(cfg.stocks) do sources[#sources + 1] = n end
    for _, n in ipairs(cfg.factoryOuts) do sources[#sources + 1] = n end
  end
  for _, n in ipairs(sources) do
    for slot, it in pairs(call(n, "list") or {}) do
      if moved >= count then return moved end
      if it.name == item then
        moved = moved + (call(n, "pushItems", dock, slot, math.min(count - moved, it.count)) or 0)
      end
    end
  end
  return moved
end

function dockOf(id)
  for _, d in ipairs(cfg.docks) do if cfg.dockFor[d] == id then return d end end
end

-- A miner whose dock isn't known yet: I put his fuel in one dock nobody owns and ask "is it yours?". He looks in
-- the barrel next to him and answers dock_mine (I remember it, like "For" in /assign) or dock_wrong (I take the
-- fuel back and try the next one). One try at a time, so only one unowned dock ever has fuel in it.
probe = nil      -- { id, dock, r, untilT, answer = "mine" | "wrong" }
probeN = 0
PROBE_FOR = 20   -- seconds he has to answer

function learnDock(d, id)
  for k, v in pairs(cfg.dockFor) do if v == id then cfg.dockFor[k] = nil end end
  cfg.dockFor[d] = id
  saveCfg()
end

-- Done with the try (or it timed out): wrong ones go back to Stock and his request goes round again
function settleProbe()
  local p = probe
  if not p or p.answer == nil and os.clock() < p.untilT then return end
  probe = nil
  if p.answer == "mine" then return end   -- learned in the radio loop; the hold stays until his dock_done
  holds[p.dock] = nil
  routeAll(p.dock, true)
  p.r.tried[p.dock] = true
  if servedSeq[p.r.id] == p.r.seq then table.insert(requests, 1, p.r) end
end

-- Load what he asked for into `dock` from Stock (and Factory out)
local function fill(dock, r, reply)
  if r.bucket then
    if fromStock(BUCKET, 1, dock) > 0 then reply.got[BUCKET] = 1
    else reply.missing[#reply.missing + 1] = "bucket" end
  end
  local units = math.max(0, tonumber(r.fuel) or 0)
  for _, f in ipairs(FUELS) do
    local n = math.floor(units / f[2])
    if f[1] == LAVA then n = math.ceil(units / f[2]) end
    n = math.min(n, (f[1] == LAVA) and 14 or 64)
    local have = (barrel.stock[f[1]] or 0) + (f[1] == LAVA and barrel.factoryLava or 0)
    if n > 0 and have > 0 then
      local m = fromStock(f[1], math.min(n, have), dock)
      if m > 0 then
        reply.got[f[1]] = m
        units = units - m * f[2]
        local fromStockN = math.min(m, barrel.stock[f[1]] or 0)
        barrel.stock[f[1]] = (barrel.stock[f[1]] or 0) - fromStockN
        if f[1] == LAVA then barrel.factoryLava = barrel.factoryLava - (m - fromStockN) end
      end
    end
    if units <= 0 then break end
  end
  if units >= 80 then reply.missing[#reply.missing + 1] = "fuel" end
end

-- A miner at his dock asks for a bucket and/or fuel: empty the dock, then load what Stock (and Factory out) has
function serveRequest(r)
  local dock = dockOf(r.id)
  local reply = { type = "dock_ready", id = r.id, seq = r.seq, got = {}, missing = {} }
  local probing = false
  if not dock and #cfg.docks > 0 then
    r.tried = r.tried or {}
    local free = {}
    for _, d in ipairs(cfg.docks) do
      if not cfg.dockFor[d] and not holds[d] and not r.tried[d] then free[#free + 1] = d end
    end
    -- First try: his haul out of his barrel, so the dock I try is the only unowned one with anything in it
    if not next(r.tried) then each(free, function(d) routeAll(d, true) end) end
    dock, probing = free[1], free[1] ~= nil
    if not dock then
      reply.note = next(r.tried) and ("Couldn't find %s's dock: set its For in /assign"):format(reg[r.id] and reg[r.id].label or ("#" .. r.id))
        or "No free dock barrel: /assign one"
    end
  elseif not dock then
    reply.note = ("No dock barrel: /assign one on %s"):format(P.name)
  end
  if dock then
    routeAll(dock, true)
    scanStock(true)
    fill(dock, r, reply)
    if probing and next(reply.got) then
      probeN = probeN + 1
      reply.probe, reply.dock = probeN, dock
      probe = { id = r.id, dock = dock, r = r, untilT = os.clock() + PROBE_FOR }
    end
    if not probing or reply.probe then holds[dock] = { id = r.id, untilT = os.clock() + HOLD_FOR } end
    if #reply.missing > 0 then
      reply.note = "Stock has no " .. table.concat(reply.missing, " or ")
    end
  end
  if rednet.isOpen() then rednet.send(r.id, reply, PROTOCOL) end
  lastReply[r.id] = reply
  return reply
end

-- Slots used and size of a list of barrels
local function room(list)
  -- Each barrel's numbers go in its own slot: the calls wait a tick, so a shared running total would lose counts
  local got = {}
  each(list, function(n)
    local g = {}
    got[n] = g
    each({ "size", "list" }, function(m) if m == "size" then g.size = call(n, "size") or 0 else g.list = call(n, "list") or {} end end)
  end)
  local used, size, items = 0, 0, 0
  for _, g in pairs(got) do
    size = size + g.size
    for _, it in pairs(g.list) do used = used + 1; items = items + it.count end
  end
  return used, size, items
end

lastNote = nil
-- A barrel pass that failed outright: kept in fm_errors.txt as well as on the screen
function writePassError(what, err)
  local f = fs.open("fm_errors.txt", "w")
  f.write(what .. " stopped with an error:\n" .. tostring(err) .. "\n")
  f.close()
end
-- The full text of this pass's failed moves, for Tanis to read (edit fm_errors.txt)
local function writeErrors()
  if #barrel.errs == 0 then
    if fs.exists("fm_errors.txt") then fs.delete("fm_errors.txt") end
    return
  end
  local f = fs.open("fm_errors.txt", "w")
  f.write("Moves that failed in the last barrel pass (from -> to: error):\n" .. table.concat(barrel.errs, "\n") .. "\n")
  f.close()
end

function barrelPass()
  barrel.passStart = os.clock()
  barrel.outFull, barrel.moveErr, barrel.errs, barrel.bad, barrel.lists = false, nil, {}, {}, {}
  scanStock()
  settleProbe()
  local later = {}
  while #requests > 0 do
    local r = table.remove(requests, 1)
    if servedSeq[r.id] ~= r.seq then                         -- he has asked again since: that one counts
    elseif probe and not dockOf(r.id) then                   -- finding another miner's dock: his turn next
      later[#later + 1] = r
      if rednet.isOpen() then rednet.send(r.id, { type = "dock_wait", id = r.id, seq = r.seq }, PROTOCOL) end
    else
      local rep = serveRequest(r)
      if not rep.probe then lastNote = rep.note end
    end
  end
  for _, r in ipairs(later) do requests[#requests + 1] = r end
  for d, h in pairs(holds) do if os.clock() > h.untilT then holds[d] = nil end end
  drainOverflow()
  -- The factory, the Inputs and every dock (not held for its Canary) at the same time
  local jobs = {}   -- (Factory out has its own lane: factoryLoop)
  for _, n in ipairs(cfg.inputs) do jobs[#jobs + 1] = function() routeAll(n, true) end end
  for _, d in ipairs(cfg.docks) do
    if not holds[d] then jobs[#jobs + 1] = function() routeAll(d, true) end end
  end
  each(jobs, function(job) job() end)
  trimStock()
  writeErrors()
  -- Room, for the screens (all read at once)
  local r, docks = {}, {}
  each({ "outputs", "factoryIns", "factoryOuts", "overflows", "docks" }, function(k)
    if k ~= "docks" then r[k] = { room(cfg[k]) }; return end
    each(cfg.docks, function(d)
      local c = 0
      for _, it in pairs(call(d, "list") or {}) do c = c + it.count end
      docks[d] = c
    end)
  end)
  barrel.outFree, barrel.outSlots = r.outputs[2] - r.outputs[1], r.outputs[2]
  barrel.factoryIn = { used = r.factoryIns[1], size = r.factoryIns[2] }
  barrel.factoryFull = r.factoryOuts[2] > 0 and r.factoryOuts[1] >= r.factoryOuts[2]
  local oi = r.overflows[3]
  barrel.overflow = { used = r.overflows[1], size = r.overflows[2], items = oi }
  if oi > 0 and #cfg.outputs > 0 then barrel.outFull = true end
  barrel.docks = docks
  barrel.passEnd = os.clock()
end

-- Item names typed on the computer: "bucket", "lava_bucket", "ancient debris", "mod:thing"
function resolveItem(text)
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
