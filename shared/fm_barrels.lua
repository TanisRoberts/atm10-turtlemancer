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

function call(name, method, ...)
  local ok, a, b = pcall(peripheral.call, name, method, ...)
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
barrel = { stock = {}, outFree = 0, outSlots = 0, outFull = false, docks = {}, seen = {}, factoryLava = 0,
           factoryIn = { used = 0, size = 0 }, overflow = { used = 0, size = 0, items = 0 } }
requests = {}    -- dock requests waiting for the worker: { id, seq, bucket, fuel }
holds = {}       -- dock name -> { id, untilT }: left alone while its miner takes his supplies
lastReply = {}   -- id -> the last dock_ready sent (repeated if he asks again with the same seq)
servedSeq = {}   -- id -> seq of the last request taken on
local NEVER_HOME = P.neverHome or {}   -- items that never go home (the MD's buckets)

-- What the Stock barrels hold, by item (and the lava waiting in Factory out)
function scanStock()
  local have, seen = {}, barrel.seen
  for _, n in ipairs(cfg.stocks) do
    for _, it in pairs(call(n, "list") or {}) do
      have[it.name] = (have[it.name] or 0) + it.count
      seen[it.name] = true
    end
  end
  barrel.stock = have
  local lava = 0
  for _, n in ipairs(cfg.factoryOuts) do
    for _, it in pairs(call(n, "list") or {}) do if it.name == LAVA then lava = lava + it.count end end
  end
  barrel.factoryLava = lava
  return have
end

-- Move up to `count` of (from, slot) into the given barrels: ones already holding the item first
function pushInto(list, from, slot, item, count)
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
function routeAll(from, stockToo)
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
  end
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

-- The lava factory: every lava bucket in Factory out goes to Stock while Stock has room, so the factory never
-- stalls on a full output (lava never goes home). Only a full Stock leaves it waiting there.
local function factoryPass()
  for _, n in ipairs(cfg.factoryOuts) do
    for slot, it in pairs(call(n, "list") or {}) do
      if it.name == LAVA then
        local m = pushInto(cfg.stocks, n, slot, LAVA, it.count)
        barrel.stock[LAVA] = (barrel.stock[LAVA] or 0) + m
        barrel.factoryLava = barrel.factoryLava - m
      end
    end
  end
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
  local free
  for _, d in ipairs(cfg.docks) do
    if cfg.dockFor[d] == id then return d end
    if not cfg.dockFor[d] and not free then free = d end
  end
  return free
end

-- A miner at his dock asks for a bucket and/or fuel: empty the dock, then load what Stock (and Factory out) has
function serveRequest(r)
  local dock = dockOf(r.id)
  local reply = { type = "dock_ready", id = r.id, seq = r.seq, got = {}, missing = {} }
  if not dock then
    reply.note = ("No dock barrel: /assign one on %s"):format(P.name)
  else
    routeAll(dock, true)
    scanStock()
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
    holds[dock] = { id = r.id, untilT = os.clock() + HOLD_FOR }
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
  local used, size, items = 0, 0, 0
  for _, n in ipairs(list) do
    size = size + (call(n, "size") or 0)
    for _, it in pairs(call(n, "list") or {}) do used = used + 1; items = items + it.count end
  end
  return used, size, items
end

lastNote = nil
function barrelPass()
  barrel.outFull = false
  scanStock()
  while #requests > 0 do
    local r = table.remove(requests, 1)
    local rep = serveRequest(r)
    lastNote = rep.note
  end
  for d, h in pairs(holds) do if os.clock() > h.untilT then holds[d] = nil end end
  drainOverflow()
  factoryPass()
  for _, n in ipairs(cfg.inputs) do routeAll(n, true) end
  for _, d in ipairs(cfg.docks) do
    if not holds[d] then routeAll(d, true) end
  end
  trimStock()
  -- Room, for the screens
  local used, slots = room(cfg.outputs)
  barrel.outFree, barrel.outSlots = slots - used, slots
  local u, s = room(cfg.factoryIns)
  barrel.factoryIn = { used = u, size = s }
  local fu, fs_ = room(cfg.factoryOuts)
  barrel.factoryFull = fs_ > 0 and fu >= fs_
  local ou, os_, oi = room(cfg.overflows)
  barrel.overflow = { used = ou, size = os_, items = oi }
  if oi > 0 and #cfg.outputs > 0 then barrel.outFull = true end
  local docks = {}
  for _, d in ipairs(cfg.docks) do
    local c = 0
    for _, it in pairs(call(d, "list") or {}) do c = c + it.count end
    docks[d] = c
  end
  barrel.docks = docks
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
