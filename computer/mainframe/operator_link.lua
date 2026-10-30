-- operator_link.lua  --  base-side radio link for the Operator (the reactor plant). Runs from the mainframe.
-- Keeps the Operator's latest status for the board, alerts and chat: units, plant totals, and when it was last heard
-- (the heartbeat), so "reactor silent" can be told apart from "reactor off". Passes on orders from chat.
--   _G.OPERATOR       the last status message { label, units = {...}, plant = {...} }
--   _G.OPERATOR_SEEN  os.clock() when it arrived
--   _G.REACTOR_FUEL       Storage's last { type = "reactor_fuel", chests = {...}, supply, best } (kept apart from _G.OPERATOR,
--   _G.REACTOR_FUEL_SEEN  so its alerts work while the Operator is quiet), and os.clock() when it arrived
--   _G.OPERATOR_CMD   an order from chat { unit = <label or nil = every reactor>, mode = "auto"|"on"|"off", left = sends }
--                     repeated a few times (once a second), since a radio message can be missed

local PROTOCOL = "tanis-operator"
local modem
peripheral.find("modem", function(name, m) rednet.open(name); modem = modem or m; return false end)
if not modem then return os.pullEvent("never") end

_G.OPERATOR, _G.OPERATOR_SEEN = _G.OPERATOR, _G.OPERATOR_SEEN
_G.REACTOR_FUEL, _G.REACTOR_FUEL_SEEN = _G.REACTOR_FUEL, _G.REACTOR_FUEL_SEEN

while true do
  local _, msg = rednet.receive(PROTOCOL, 1)
  if type(msg) == "table" and msg.type == "operator" then
    _G.OPERATOR, _G.OPERATOR_SEEN = msg, os.clock()
  elseif type(msg) == "table" and msg.type == "reactor_fuel" then
    _G.REACTOR_FUEL, _G.REACTOR_FUEL_SEEN = msg, os.clock()
  end
  local c = _G.OPERATOR_CMD
  if c and (c.left or 0) > 0 and os.clock() - (c.at or -10) >= 1 then
    rednet.broadcast({ type = "operator_cmd", unit = c.unit, mode = c.mode, level = c.level }, PROTOCOL)
    c.left, c.at = c.left - 1, os.clock()
  end
end
