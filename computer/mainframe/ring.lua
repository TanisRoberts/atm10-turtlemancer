-- ring.lua  --  "island remove_ring": takes a cursed ring out of your Curios slots and puts it in your inventory.
-- Uses the Inventory Manager's Curios calls (AP 0.8: listCurios, exportCuriosItem). They move the stack straight
-- out of the slot, so a ring that says it can't be taken off still comes off. Only the memory card's owner can use it.
local R = {}

-- What counts as "the ring" when no word is given: Enigmatic Legacy's Ring of the Seven Curses and its ports
local DEFAULT = { "cursed_ring", "seven", "sins" }

local function matches(it, words)
  local id, shown = tostring(it.name):lower(), tostring(it.displayName or ""):lower()
  for _, w in ipairs(words) do
    if id:find(w, 1, true) or shown:find(w, 1, true) then return true end
  end
  return false
end

-- m: the inventory manager (or nil). user: who asked. word: optional part of the item's name.
-- Returns the reply to say to the user.
function R.remove(m, user, word)
  if not m then return "No Inventory Manager next to the mainframe." end
  if not m.listCurios or not m.exportCuriosItem then return "This Inventory Manager can't see Curios slots." end
  local ok, _, owner = pcall(m.getOwner)
  if not ok or not owner then return "The Inventory Manager's memory card owner isn't online." end
  if tostring(owner):lower() ~= tostring(user):lower() then
    return "Only " .. tostring(owner) .. " can do that: the Inventory Manager only reaches their slots."
  end

  local okList, curios = pcall(m.listCurios)
  if not okList or type(curios) ~= "table" then return "Couldn't read your Curios slots: " .. tostring(curios) end
  local words = (word and word ~= "") and { word:lower() } or DEFAULT
  local found, rings = {}, {}
  for slotType, items in pairs(curios) do
    for slot, it in pairs(items) do
      if matches(it, words) then found[#found + 1] = { type = slotType, slot = slot, it = it } end
      if slotType == "ring" then rings[#rings + 1] = it.displayName or it.name end
    end
  end
  if #found == 0 then
    local seen = #rings > 0 and (" Your ring slots hold: " .. table.concat(rings, ", ") .. ".") or ""
    return "No matching ring in your Curios slots." .. seen .. " Try: island remove_ring <part of its name>"
  end

  local removed, last = {}, nil
  for _, f in ipairs(found) do
    local okMove, moved = pcall(m.exportCuriosItem, f.type, "@", { name = f.it.name, fromSlot = f.slot, count = f.it.count or 1 })
    if okMove and type(moved) == "number" and moved > 0 then
      removed[#removed + 1] = f.it.displayName or f.it.name
    else
      last = okMove and "your inventory is full" or tostring(moved)
    end
  end
  if #removed == 0 then return "Couldn't take it off: " .. tostring(last) .. "." end
  return "Took off " .. table.concat(removed, ", ") .. ". It's in your inventory now."
    .. (last and (" (Something else failed: " .. last .. ".)") or "")
end

return R
