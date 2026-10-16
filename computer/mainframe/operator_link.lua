-- operator_link.lua  --  base-side radio link for the Operator (the reactor plant). Runs from the mainframe.
-- Keeps the Operator's latest status for the board, alerts and chat (issue #36): units, plant totals, and when it was
-- last heard (the heartbeat), so "reactor silent" can be told apart from "reactor off".
--   _G.OPERATOR       the last status message { label, units = {...}, plant = {...} }
--   _G.OPERATOR_SEEN  os.clock() when it arrived

local PROTOCOL = "tanis-operator"
local modem
peripheral.find("modem", function(name, m) rednet.open(name); modem = modem or m; return false end)
if not modem then return os.pullEvent("never") end

_G.OPERATOR, _G.OPERATOR_SEEN = _G.OPERATOR, _G.OPERATOR_SEEN

while true do
  local _, msg = rednet.receive(PROTOCOL)
  if type(msg) == "table" and msg.type == "operator" then
    _G.OPERATOR, _G.OPERATOR_SEEN = msg, os.clock()
  end
end
