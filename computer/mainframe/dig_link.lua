-- dig_link.lua  --  mainframe-side ear for every Canary (runs from mainframe.lua)
--
-- The Foreman computer gives the Canaries their orders (and the Nether Foreman the Firecrests'); the
-- mainframe only listens, so the status board, alerts and chat can show every Canary and Firecrest:
--   _G.CANARIES = { [computer id] = { s = last status, seen = os.clock() } }
-- (Firecrests are in the Nether: the mainframe's ender modem hears them across dimensions.)

local PROTOCOLS = { ["tanis-miner"] = true, ["tanis-nether"] = true }
-- Talk on every modem: wireless/ender for turtles and far machines, wired for computers on the same cable
local modem
peripheral.find("modem", function(name, m) rednet.open(name); modem = modem or m; return false end)
if not modem then return os.pullEvent("never") end

_G.CANARIES = _G.CANARIES or {}
while true do
  local from, msg, proto = rednet.receive()
  if PROTOCOLS[proto] and type(msg) == "table" and msg.type == "status" and msg.id == from then
    _G.CANARIES[from] = { s = msg, seen = os.clock() }
  end
end
