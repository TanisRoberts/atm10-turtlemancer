-- storage_rules.lua  --  depot rules for storage. Loaded with dofile() and called with the program's state:
--   dofile("storage_rules.lua")({ cfg = function() return cfg end, info = info, items = function() return items end,
--                                  nameOf = function(key) ... end })
--
-- A depot holds a rule: { item=, tag=, mod=, enchanted=true|false|nil, priority=0, added=N }. All set
-- conditions must match. Each item variant goes to at most one depot, the winner:
--   1. most specific rule (Item 8 + Tag 4 + Mod 2 + Enchanted 1), 2. higher priority, 3. added first.
-- Tags and enchantments are read once per variant (R.fill, from getItemDetail) and kept in `info`.
-- docs/design/storage.md, "Depot rules".

return function(o)
  local R = {}

  local WEIGHT = { item = 8, tag = 4, mod = 2, enchanted = 1 }

  -- A saved value -> a rule table, or nil for "not chosen yet" (""). Old values were a bare item id.
  function R.normalize(v)
    if type(v) == "string" then
      if v == "" then return nil end
      return { item = v, priority = 0 }
    end
    if type(v) ~= "table" then return nil end
    local r = { item = v.item, tag = v.tag, mod = v.mod, enchanted = v.enchanted,
                priority = tonumber(v.priority) or 0, added = v.added }
    if r.item == "" then r.item = nil end
    if r.tag == "" then r.tag = nil end
    if r.mod == "" then r.mod = nil end
    if not (r.item or r.tag or r.mod or r.enchanted ~= nil) then return nil end
    return r
  end

  -- Make cfg.depots tables with an `added` number each (old string values are upgraded in place).
  -- "" stays "" (container assigned, rule not chosen yet).
  function R.upgrade()
    local depots = o.cfg().depots
    if not depots then return end
    local top = 0
    for _, v in pairs(depots) do
      if type(v) == "table" and v.added and v.added > top then top = v.added end
    end
    local names = {}
    for n in pairs(depots) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
      local v = depots[n]
      if type(v) == "string" and v ~= "" then
        top = top + 1
        depots[n] = { item = v, priority = 0, added = top }
      elseif type(v) == "table" and not v.added then
        top = top + 1
        v.added = top
      end
    end
  end

  -- The next `added` number, for a depot saved now
  function R.nextAdded()
    local top = 0
    for _, v in pairs(o.cfg().depots or {}) do
      if type(v) == "table" and v.added and v.added > top then top = v.added end
    end
    return top + 1
  end

  function R.modOf(name) return (name:match("^([^:]+):")) or "minecraft" end

  -- Copy the parts of a getItemDetail answer rules need into an info entry.
  function R.fill(i, d)
    local tags = {}
    for t, on in pairs(d.tags or {}) do if on then tags[t] = true end end
    i.tags = tags
    local ench = d.enchantments
    local stored = d.storedEnchantments
    i.enchanted = (type(ench) == "table" and next(ench) ~= nil) or (type(stored) == "table" and next(stored) ~= nil) or false
    return i
  end

  function R.score(r)
    return (r.item and WEIGHT.item or 0) + (r.tag and WEIGHT.tag or 0)
      + (r.mod and WEIGHT.mod or 0) + (r.enchanted ~= nil and WEIGHT.enchanted or 0)
  end

  -- Does the rule match this variant? A variant whose tags are not known yet matches no tag/enchanted rule.
  function R.matches(r, key, name)
    if r.item and r.item ~= name then return false end
    if r.mod and r.mod ~= R.modOf(name) then return false end
    if r.tag or r.enchanted ~= nil then
      local i = o.info[key]
      if not (i and i.tags) then return false end
      if r.tag and not i.tags[r.tag] then return false end
      if r.enchanted ~= nil and i.enchanted ~= r.enchanted then return false end
    end
    return true
  end

  local function beats(a, b)   -- rule a (with depot name) beats b
    local sa, sb = R.score(a.rule), R.score(b.rule)
    if sa ~= sb then return sa > sb end
    if a.rule.priority ~= b.rule.priority then return a.rule.priority > b.rule.priority end
    local aa, ab = a.rule.added or math.huge, b.rule.added or math.huge
    if aa ~= ab then return aa < ab end
    return a.name < b.name
  end

  -- Every depot with a rule: { { name=, rule= }, ... }; `extra` is a hypothetical { name=, rule= } to add
  -- (replacing the depot of that name).
  local function candidates(extra)
    local out = {}
    for n, v in pairs(o.cfg().depots or {}) do
      local r = R.normalize(v)
      if r and not (extra and extra.name == n) then out[#out + 1] = { name = n, rule = r } end
    end
    if extra then out[#out + 1] = extra end
    return out
  end

  local function winnerIn(cands, key, name)
    local best
    for _, c in ipairs(cands) do
      if R.matches(c.rule, key, name) and (not best or beats(c, best)) then best = c end
    end
    return best and best.name
  end

  -- The depot (network name) that wins this variant, or nil
  function R.winner(key, name) return winnerIn(candidates(), key, name) end

  -- Winners for everything in storage: { [depot] = { entry, ... } } (entries of the items list)
  function R.winners()
    local cands, out = candidates(), {}
    for _, e in ipairs(o.items()) do
      local w = winnerIn(cands, e.key, e.name)
      if w then out[w] = out[w] or {}; table.insert(out[w], e) end
    end
    return out
  end

  -- What a rule would win in storage if it were depot `depot` (nil: a new one, added last):
  -- { kinds=, items=, list = { entries sorted by count, biggest first }, lost = { [other depot] = kinds } }
  function R.preview(rule, depot)
    rule = R.normalize(rule)
    local res = { kinds = 0, items = 0, list = {}, lost = {} }
    if not rule then return res end
    rule.added = rule.added or (depot and (R.normalize(o.cfg().depots[depot]) or {}).added) or R.nextAdded()
    local me = { name = depot or "\0new", rule = rule }
    local others = candidates(me)
    for _, e in ipairs(o.items()) do
      if R.matches(rule, e.key, e.name) then
        local w = winnerIn(others, e.key, e.name)
        if w == me.name then
          res.kinds, res.items = res.kinds + 1, res.items + e.count
          res.list[#res.list + 1] = e
        elseif w then
          res.lost[w] = (res.lost[w] or 0) + 1
        end
      end
    end
    table.sort(res.list, function(a, b)
      if a.count ~= b.count then return a.count > b.count end
      return (a.label or a.name) < (b.label or b.name)
    end)
    return res
  end

  -- Tags on items in storage: { { tag=, kinds=, items= }, ... } sorted by items, biggest first
  function R.tags()
    local t, out = {}, {}
    for _, e in ipairs(o.items()) do
      for tag in pairs((o.info[e.key] or {}).tags or {}) do
        local x = t[tag]
        if not x then x = { tag = tag, kinds = 0, items = 0 }; t[tag] = x; out[#out + 1] = x end
        x.kinds, x.items = x.kinds + 1, x.items + e.count
      end
    end
    table.sort(out, function(a, b)
      if a.items ~= b.items then return a.items > b.items end
      return a.tag < b.tag
    end)
    return out
  end

  -- Mods (id namespaces) in storage: { { mod=, kinds=, items= }, ... } sorted by items, biggest first
  function R.mods()
    local t, out = {}, {}
    for _, e in ipairs(o.items()) do
      local m = R.modOf(e.name)
      local x = t[m]
      if not x then x = { mod = m, kinds = 0, items = 0 }; t[m] = x; out[#out + 1] = x end
      x.kinds, x.items = x.kinds + 1, x.items + e.count
    end
    table.sort(out, function(a, b)
      if a.items ~= b.items then return a.items > b.items end
      return a.mod < b.mod
    end)
    return out
  end

  -- One line for a rule: "Tag c:enchantables, enchanted"
  function R.describe(rule)
    rule = R.normalize(rule)
    if not rule then return "nothing yet" end
    local p = {}
    if rule.item then p[#p + 1] = "Item " .. rule.item end
    if rule.tag then p[#p + 1] = "Tag " .. rule.tag end
    if rule.mod then p[#p + 1] = "Mod " .. rule.mod end
    if rule.enchanted ~= nil then p[#p + 1] = rule.enchanted and "enchanted" or "not enchanted" end
    return table.concat(p, ", ")
  end

  return R
end
