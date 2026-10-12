-- dig_link.lua  --  mainframe-side ear for every Digger (runs from mainframe.lua)
--
-- The Foreman computer gives the Diggers their orders; the mainframe only listens, so the status
-- board, alerts and chat can show every Digger:
--   _G.DIGGERS = { [computer id] = { s = last status, seen = os.clock() } }

local PROTOCOL = "tanis-miner"
-- Talk on every modem: wireless/ender for turtles and far machines, wired for computers on the same cable
local modem
peripheral.find("modem", function(name, m) rednet.open(name); modem = modem or m; return false end)
if not modem then return os.pullEvent("never") end

_G.DIGGERS = _G.DIGGERS or {}
while true do
  local from, msg = rednet.receive(PROTOCOL)
  if type(msg) == "table" and msg.type == "status" and msg.id == from then
    _G.DIGGERS[from] = { s = msg, seen = os.clock() }
  end
end
