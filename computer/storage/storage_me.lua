-- storage_me.lua  --  storage in ME mode: an Advanced Peripherals ME Bridge (`me_bridge`) on the cable makes AE2 the
-- storage (#124, project #122). Part of computer/storage/storage.lua, which keeps every job (inputs, docks, depots,
-- fuel, smelter, neural, Weaver, pocket, reactor) and only swaps the two seams:
--   deposit  (storage.lua moveInto)  -> ME.import(from, slot, count, key)    = bridge.importItem
--   retrieve (storage.lua retrieve)  -> ME.export(key, amount, target, slot) = bridge.exportItem
-- and builds the item list from bridge.getItems() instead of scanning inventories.
--
--   local ME = dofile("storage_me.lua")({ call = fn, info = table, fill = RULES.fill, keyOf = fn })
--
-- In ME mode no inventory on the cable is storage: only assigned job inventories are touched, so ME drives,
-- interfaces and IO ports that carry a modem are safe. Items are keyed like the rest of storage: "name" or
-- "name#<nbt hash>" (the hash the bridge reports; an item the bridge shows with no hash has a plain key).
return function(o)
  local ME = {}
  local name, lastOk = nil, true       -- the bridge in use (the first me_bridge found), and whether the last call worked
  local have = {}                      -- key -> count, from the last getItems()

  -- Find the bridge. The first one by name wins; call it again to re-check (storage does, on every rescan).
  function ME.find()
    name = nil
    local names = peripheral.getNames()
    table.sort(names)
    for _, n in ipairs(names) do
      if peripheral.hasType(n, "me_bridge") then name = n; break end
    end
    return name
  end
  function ME.on() return name ~= nil end
  function ME.name() return name end
  function ME.isBridge(n) return name ~= nil and n == name end

  -- Is the grid usable right now? (an unplugged or unpowered bridge is "ME offline")
  function ME.online()
    if not name then return false end
    if not peripheral.isPresent(name) then lastOk = false; return false end
    local _, conn = pcall(peripheral.call, name, "isConnected")
    local _, onl = pcall(peripheral.call, name, "isOnline")
    lastOk = conn == true and onl == true
    return lastOk
  end
  function ME.offline() return name ~= nil and not lastOk end

  local function bridge(method, ...)
    if not name then return nil, "NO_BRIDGE" end
    local ok, a, b = pcall(peripheral.call, name, method, ...)
    if not ok then lastOk = false; return nil, a end
    return a, b
  end

  local function splitKey(key)
    local n, h = key:match("^(.-)#(.*)$")
    if n then return n, h end
    return key, nil
  end

  -- AP gives tags as a list of strings; the rules want a set
  local function tagSet(t)
    local s = {}
    for k, v in pairs(t or {}) do
      if type(k) == "number" and type(v) == "string" then s[v] = true
      elseif v == true then s[k] = true end
    end
    return s
  end

  -- The grid's items: a list of { key, name, count } or nil when the bridge can't answer (offline).
  -- New variants get an info entry (label, tags); the stack size is learnt later from a real stack (`stackKnown`).
  function ME.items()
    local list = bridge("getItems")
    if type(list) ~= "table" then lastOk = false; return nil end
    lastOk = true
    local out = {}
    have = {}
    for _, it in ipairs(list) do
      if it.count and it.count > 0 then
        local k = o.keyOf(it)
        out[#out + 1] = { key = k, name = it.name, count = it.count }
        have[k] = it.count
        if not (o.info[k] and o.info[k].tags) then
          o.info[k] = o.fill({ label = it.displayName, max = (o.info[k] and o.info[k].max) or 64, guessedMax = true },
            { tags = tagSet(it.tags) })
        end
      end
    end
    return out
  end

  -- How many of `key` the grid holds right now (nil when the bridge can't answer). One cheap call, no full list.
  function ME.count(key)
    local n, hash = splitKey(key)
    local f = { name = n }
    if hash then f.nbtHash = hash end
    local it = bridge("getItem", f)
    if type(it) ~= "table" then return nil end
    return it.count or 0
  end

  -- Item bytes in use / in all (nil when offline)
  function ME.bytes()
    local used = bridge("getUsedItemStorage")
    local total = bridge("getMaxItemStorage")
    if type(used) ~= "number" or type(total) ~= "number" then return nil end
    return used, total
  end

  -- Take up to `amount` of `key` out of AE2 into `target` (a peripheral name on the cable). One call moves any amount.
  -- Returns moved, full (full: the target refused some of what AE2 has).
  function ME.export(key, amount, target, toSlot)
    local n, hash = splitKey(key)
    local f = { name = n, count = amount }
    if hash then f.nbtHash = hash end
    if toSlot then f.toSlot = toSlot end
    local moved = bridge("exportItem", target, f)
    moved = type(moved) == "number" and moved or 0
    local avail = have[key]
    if avail == nil then avail = moved end     -- not on the last list: don't call a short answer "full"
    local full = moved < math.min(amount, avail)
    if moved > 0 and have[key] then have[key] = math.max(0, have[key] - moved) end
    return moved, full
  end

  -- Put up to `count` of the stack in (from, slot) into AE2. The slot pins the exact stack, so no hash is needed.
  function ME.import(from, slot, count, key)
    local n = splitKey(key)
    local moved = bridge("importItem", from, { name = n, fromSlot = slot, count = count })
    moved = type(moved) == "number" and moved or 0
    if moved > 0 then have[key] = (have[key] or 0) + moved end
    return moved
  end

  return ME
end
