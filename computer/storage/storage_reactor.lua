-- storage_reactor.lua  --  the "Reactor fuel" job (#104, project #103). Docs: docs/systems/storage.md.
-- Keeps every Reactor fuel chest (an Ender Storage chest on a full-block modem) at REACTOR_FUEL_KEEP fuel units,
-- stocking the best fuel storage has first, and tells the Operator about it on "tanis-operator".
-- Nothing is ever pulled out of a fuel chest and nothing is crafted.
--   local R = dofile("storage_reactor.lua")({ cfg = fn, items = fn, info = tbl, call = fn, retrieve = fn, env = envfile })
--   R.tick() -> true when storage's own stock changed (call buildItems);  R.units(chest) -> units, keep
return function(X)
  local R = {}
  local PROTOCOL, REPORT_EVERY = "tanis-operator", 10

  local tune = X.env.new("storage.env", "Storage settings.", {
    { "REACTOR_FUEL", "#c:storage_blocks/uranium=9,#c:ingots/uranium=1",
      "Reactor fuel, best first: <item id or #tag>=<fuel units>, comma separated. A uranium ingot is 1 unit, a block 9." },
    { "REACTOR_FUEL_KEEP", 64, "Fuel units kept in each Reactor fuel chest." },
    { "REACTOR_FUEL_LOW", 16, "Fuel units in a chest below which the mainframe calls it low." },
  })
  tune.load()

  -- "#c:ingots/uranium=1, minecraft:coal=2" -> { { id=, tag=, units= }, ... }, parsed again only when the text changes
  local parsedFrom, parsed = nil, {}
  local function fuels()
    tune.refresh()
    local raw = tostring(tune.v.REACTOR_FUEL or "")
    if raw ~= parsedFrom then
      parsedFrom, parsed = raw, {}
      for part in raw:gmatch("[^,]+") do
        local what, units = part:match("^%s*(%S+)%s*=%s*(%d+)%s*$")
        units = tonumber(units)
        if what and units and units > 0 then
          if what:sub(1, 1) == "#" then parsed[#parsed + 1] = { tag = what:sub(2), units = units }
          else parsed[#parsed + 1] = { id = what, units = units } end
        end
      end
    end
    return parsed
  end
  local function number(key, default)
    tune.refresh()
    return math.max(0, math.floor(tonumber(tune.v[key]) or default))
  end
  function R.keep() return number("REACTOR_FUEL_KEEP", 64) end
  function R.low() return number("REACTOR_FUEL_LOW", 16) end

  -- Which entry of the list (best first) an item is, and what one of it is worth: rank, units (nil = not a fuel)
  local function rankOf(name, tags)
    for i, f in ipairs(fuels()) do
      if (f.id and f.id == name) or (f.tag and tags and tags[f.tag]) then return i, f.units end
    end
  end

  -- Tags of an item that sits in a fuel chest (not in storage, so not in info): read once per variant
  local chestTags = {}
  local function tagsInChest(chest, slot, key)
    local i = X.info[key]
    if i and i.tags then return i.tags end
    if not chestTags[key] then
      local d = X.call(chest, "getItemDetail", slot)
      if not d then return nil end
      chestTags[key] = d.tags or {}
    end
    return chestTags[key]
  end

  -- Fuel units in a chest (only what is on the list counts)
  function R.units(chest)
    local list = X.call(chest, "list")
    if not list then return nil end
    local have = 0
    for slot, it in pairs(list) do
      local key = it.name .. (it.nbt and ("#" .. it.nbt) or "")
      local _, units = rankOf(it.name, tagsInChest(chest, slot, key))
      if units then have = have + units * it.count end
    end
    return have
  end

  -- What storage holds of each listed fuel, best first: { { key, name, units, count } ... }
  local function stock()
    local out = {}
    for _, e in ipairs(X.items()) do
      local i = X.info[e.key]
      local rank, units = rankOf(e.name, i and i.tags)
      if rank and e.count > 0 then out[#out + 1] = { key = e.key, name = e.name, rank = rank, units = units, count = e.count } end
    end
    table.sort(out, function(a, b)
      if a.rank ~= b.rank then return a.rank < b.rank end
      return a.key < b.key
    end)
    return out
  end

  local function supplyOf(have)
    local supply, best = 0, nil
    for _, s in ipairs(have) do
      supply = supply + s.units * s.count
      if not best and s.count > 0 then best = s.name end
    end
    return supply, best
  end

  local lastReport = -100
  local function report(have)
    if not rednet.isOpen() then return end
    local chests, keep, low = {}, R.keep(), R.low()
    for _, n in ipairs(X.cfg().reactorFuels or {}) do
      if peripheral.isPresent(n) then
        chests[#chests + 1] = { name = n, label = (X.cfg().names or {})[n] or n, units = R.units(n) or 0, keep = keep, low = low }
      end
    end
    if #chests == 0 then return end
    local supply, best = supplyOf(have or stock())
    rednet.broadcast({ type = "reactor_fuel", chests = chests, supply = supply, best = best }, PROTOCOL)
    lastReport = os.clock()
  end

  -- Top every chest up to the keep level, then report (right after a top-up, otherwise every 10 s)
  function R.tick()
    local chestNames = X.cfg().reactorFuels or {}
    if #chestNames == 0 then return false end
    local keep, changed = R.keep(), false
    local have = stock()
    for _, n in ipairs(chestNames) do
      if peripheral.isPresent(n) then
        local deficit = keep - (R.units(n) or keep)
        for _, s in ipairs(have) do
          if deficit <= 0 then break end
          -- Round up to a whole item (never over by a full item's value), but not past what storage has
          local want = math.min(math.ceil(deficit / s.units), s.count)
          if want > 0 then
            local moved = X.retrieve(s.key, want, n)
            if moved > 0 then
              s.count = s.count - moved
              deficit = deficit - moved * s.units
              changed = true
            end
          end
        end
      end
    end
    if changed or os.clock() - lastReport >= REPORT_EVERY then report(have) end
    return changed
  end

  return R
end
