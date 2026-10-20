-- turtlecore_chunk.lua  --  core.chunk: keeps the chunk he's in loaded with Advanced Peripherals' chunk controller
-- (the "Chunky Turtle" upgrade). With one in his bag he swaps it onto his modem's side for a moment whenever he
-- crosses into a new chunk, and every `every` seconds anyway. While it's on it force-loads the chunk he's in;
-- taken off, that chunk stays loaded until the mod's timeout (chunkLoadValidTime, 600 s by default, never under
-- 60 s), so he only ever holds ONE chunk. Equipping it in a new chunk releases the old one at once.
-- Worn all the time (no modem swap) it reloads his chunk by itself. No controller: nothing happens.
return function(core)
local C = { every = 45, note = nil, swaps = 0, at = -1e9, key = nil }
core.chunk = C
C.ITEM = "advancedperipherals:chunk_controller"
local SWAP_FILE = "chunkswap.txt"   -- written during a swap: the side his modem belongs on
local EQUIP = { left = turtle.equipLeft, right = turtle.equipRight }

function C.isModem(name)
  return name == "computercraft:wireless_modem_advanced" or name == "computercraft:wireless_modem_normal"
end

local function sideOfType(t)
  for _, sd in ipairs({ "left", "right" }) do
    local types = { peripheral.getType(sd) }
    for _, x in ipairs(types) do if x == t then return sd end end
  end
end
local function slotOf(test)
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and test(d.name) then return s end end
end
local function controllerSlot() return slotOf(function(n) return n == C.ITEM end) end

-- Has he got a chunk controller (in his bag or worn)?
function C.have() return controllerSlot() ~= nil or sideOfType("chunky") ~= nil end

-- Load the chunk `key` names (the caller's "cx,cz"): swaps only in a new chunk, or `every` seconds after the
-- last swap, or when `force`. True when it loaded it now. C.note says why it couldn't (for his screen).
function C.ensure(key, force)
  if not force and key == C.key and os.clock() - C.at < C.every then return false end
  if sideOfType("chunky") then
    os.sleep(0.1)   -- worn all the time: it reloads the chunk he's in every tick
  else
    local slot, side = controllerSlot(), sideOfType("modem")
    if not (slot and side) then
      C.note = slot and "No modem to swap with" or "Chunk controller missing"
      return false
    end
    local prev = turtle.getSelectedSlot()
    turtle.select(slot)
    local f = fs.open(SWAP_FILE, "w"); f.write(side); f.close()   -- unloaded mid-swap: restore() puts it back
    if EQUIP[side]() then
      os.sleep(0.15)                       -- at least one server tick with it on: loads + touches this chunk
      turtle.select(slot)
      EQUIP[side]()                        -- modem back on; the controller goes back into that slot
    end
    fs.delete(SWAP_FILE)
    turtle.select(prev)
    pcall(rednet.open, side)
    C.swaps = C.swaps + 1
  end
  C.note = nil
  C.at, C.key = os.clock(), key
  return true
end

-- Boot: a swap that was cut short leaves the modem in his bag and the controller on. Put it back.
-- hint: the side the modem was on, if the role remembered it (older saves). True if he had to.
function C.restore(hint)
  local side = nil
  if fs.exists(SWAP_FILE) then
    local f = fs.open(SWAP_FILE, "r"); side = f.readAll(); f.close()
    fs.delete(SWAP_FILE)
  end
  if sideOfType("modem") then return false end
  local ms = slotOf(C.isModem)
  side = sideOfType("chunky") or side or hint
  if ms and EQUIP[side] then
    turtle.select(ms); EQUIP[side](); turtle.select(1)
    return true
  end
  return false
end
end
