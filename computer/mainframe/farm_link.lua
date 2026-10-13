-- farm_link.lua  --  base-side radio link for the farm turtles (Tigger, Figger...). Runs from startup.lua.
-- Keeps their status for alerts/chat and passes on orders from chat (island <name> rounds|survey|stop|go|found).
-- Also hears the Farmhand's summary (its row on the board).

local PROTOCOL = "tanis-farm"
-- Talk on every modem: wireless/ender for turtles and far machines, wired for computers on the same cable
local modem
peripheral.find("modem", function(name, m) rednet.open(name); modem = modem or m; return false end)
if not modem then return os.pullEvent("never") end

_G.FARM_STATUS = _G.FARM_STATUS or {}
_G.FARM_SEEN = _G.FARM_SEEN or {}
_G.FARM_CMD = _G.FARM_CMD or {}
_G.FARMHAND, _G.FARMHAND_SEEN = _G.FARMHAND, _G.FARMHAND_SEEN

local sent = {}       -- name -> seq we last relayed
local lastSend = -100
while true do
  local _, msg = rednet.receive(PROTOCOL, 1)
  if type(msg) == "table" and msg.type == "status" and msg.label then
    local k = tostring(msg.label):lower()
    _G.FARM_STATUS[k] = msg
    _G.FARM_SEEN[k] = os.clock()
  elseif type(msg) == "table" and msg.type == "farmhand" then
    _G.FARMHAND, _G.FARMHAND_SEEN = msg, os.clock()
  end
  -- Keep repeating each turtle's latest order until it reports it has seen it (or a newer one,
  -- e.g. from the Farmhand: orders carry time-stamps and turtles only act on newer ones)
  if os.clock() - lastSend >= 3 then
    for name, c in pairs(_G.FARM_CMD) do
      local st = _G.FARM_STATUS[name]
      if not (st and (tonumber(st.seq) or 0) >= c.seq) then
        rednet.broadcast({ type = "cmd", target = name, want = c.want, seq = c.seq }, PROTOCOL)
      end
    end
    lastSend = os.clock()
  end
end
