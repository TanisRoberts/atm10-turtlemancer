-- island remove_ring (computer/mainframe/ring.lua): takes a cursed ring out of the owner's Curios slots.
local cc = require("sim.cc")
local T  = require("sim.test")

local function load() return assert(loadfile(cc.ROOT .. "/computer/mainframe/ring.lua", "t", _G))() end

-- A fake Inventory Manager: curios[type][slot] = item, inv = the player's inventory
local function manager(owner, curios, full)
  local m = { inv = {} }
  function m.getOwner() return "uuid", owner end
  function m.listCurios() return curios end
  function m.exportCuriosItem(from, to, f)
    assert(to == "@", "should go to the player's inventory")
    local it = curios[from] and curios[from][f.fromSlot]
    if not it or it.name ~= f.name or full then return 0 end
    curios[from][f.fromSlot] = nil
    m.inv[#m.inv + 1] = it
    return it.count
  end
  return m
end

local SEVEN = { name = "enigmaticlegacy:cursed_ring", displayName = "Ring of the Seven Curses", count = 1 }
local GOLD  = { name = "artifacts:golden_hook", displayName = "Golden Hook", count = 1 }

T.test("mainframe: remove_ring takes the cursed ring off and leaves the rest", function()
  local R = load()
  local m = manager("Tanis", { ring = { [1] = SEVEN, [2] = GOLD } })
  local reply = R.remove(m, "tanis")
  T.eq(m.inv[1], SEVEN)
  T.eq(#m.inv, 1)
  assert(reply:find("Took off Ring of the Seven Curses", 1, true), reply)
end)

T.test("mainframe: remove_ring only works for the card's owner", function()
  local R = load()
  local m = manager("Tanis", { ring = { [1] = SEVEN } })
  local reply = R.remove(m, "Visitor")
  T.eq(#m.inv, 0)
  assert(reply:find("Only Tanis", 1, true), reply)
end)

T.test("mainframe: remove_ring says what's there when nothing matches, and takes a name", function()
  local R = load()
  local m = manager("Tanis", { ring = { [1] = GOLD } })
  local reply = R.remove(m, "Tanis")
  assert(reply:find("Golden Hook", 1, true), reply)
  T.eq(#m.inv, 0)
  reply = R.remove(m, "Tanis", "hook")
  T.eq(m.inv[1], GOLD)
end)

T.test("mainframe: remove_ring with a full inventory", function()
  local R = load()
  local m = manager("Tanis", { ring = { [1] = SEVEN } }, true)
  local reply = R.remove(m, "Tanis")
  assert(reply:find("inventory is full", 1, true), reply)
end)
