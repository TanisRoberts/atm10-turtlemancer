-- direct.lua  --  what a factory's output is FOR, and the hand-added ("enrich add") item list.
--
-- A factory learns `item -> product`. Compared with the smelter's own recipe book:
--   direct   the furnace makes that same product from the item (ancient debris -> netherite scrap):
--            the product goes straight to storage, never waits on a dust check
--   via dust the product is something a recipe smelts (raw iron -> dust -> ingot): the dust route
--   nil      neither is known (yet): the dust check decides
-- Pure decisions, no peripherals: smelter.lua passes the book and cfg in.
local X = {}

local function has(list, x) for _, v in ipairs(list or {}) do if v == x then return true end end return false end
local function isInputOf(r, name)
  if has(r.inputs, name) then return true end
  return r.pattern ~= nil and name:find(r.pattern) ~= nil
end
local function outIs(r, name)
  if r.modded then return name:find(r.out, 1, true) ~= nil end
  return name == r.out
end

-- A recipe in `book` that makes `product` from `item`
function X.furnaceRecipe(book, item, product)
  for _, r in pairs(book) do
    if outIs(r, product) and isInputOf(r, item) then return r end
  end
end

-- "direct" / "via dust" / nil for a learned entry (e.direct is the marker set when it was learned)
function X.kind(book, item, e)
  if type(e) ~= "table" or not e.out or e.no or e.dustBad then return nil end
  if e.direct or X.furnaceRecipe(book, item, e.out) then return "direct" end
  for _, r in pairs(book) do
    if has(r.inputs, e.out) then return "via dust" end
  end
  return nil
end

-- Items matching a typed word: full id, short name, or a name ending in it (debris, scrap...), plus raw_<word>
-- The exact id or short name wins; otherwise every suffix match.
function X.match(word, names)
  local exact, suffix = {}, {}
  for _, n in ipairs(names) do
    local short = n:gsub("^[^:]*:", "")
    if n == word or short == word or short == "raw_" .. word then exact[#exact + 1] = n
    elseif short:sub(-#word - 1) == "_" .. word then suffix[#suffix + 1] = n end
  end
  return #exact > 0 and exact or suffix
end

-- cfg.enrichExtra is a list of item ids Tanis added by hand
function X.addExtra(extra, item)
  if has(extra, item) then return false end
  extra[#extra + 1] = item
  table.sort(extra)
  return true
end
function X.isExtra(extra, item) return has(extra, item) end

return X
