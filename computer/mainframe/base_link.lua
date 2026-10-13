-- base_link.lua  --  mainframe-side link to the storage and smelter computers (runs from mainframe.lua)
--
-- Listens on "tanis-base" and shares what it hears with the other mainframe programs:
--   _G.STORAGE_STATS / STORAGE_SEEN / STORAGE_OVERCAP   (alerts, chat, status board, miner panel)
--   _G.SMELTER / SMELTER_SEEN / SMELT_STATUS            (chat, status board)
--   _G.FACTORY / FACTORY_SEEN                           (plastic factory: chat, alerts, status board)
--   _G.NEURAL / NEURAL_SEEN                             (neural lab: chat, alerts, status board)
-- and passes smelting orders from chat (_G.SMELT_CMD) on to the smelter until it confirms.

local BASE = "tanis-base"
-- Talk on every modem: wireless/ender for turtles and far machines, wired for computers on the same cable
local modem
peripheral.find("modem", function(name, m) rednet.open(name); modem = modem or m; return false end)
if not modem then return os.pullEvent("never") end

local lastSend = -100
while true do
  local _, msg = rednet.receive(BASE, 1)
  if type(msg) == "table" then
    if msg.type == "storage" then
      _G.STORAGE_STATS, _G.STORAGE_SEEN = msg, os.clock()
      _G.STORAGE_OVERCAP = type(msg.overcap) == "table" and msg.overcap or {}
    elseif msg.type == "smelter" then
      _G.SMELTER, _G.SMELTER_SEEN = msg, os.clock()
      _G.SMELT_STATUS = msg.lines
    elseif msg.type == "factory" then
      _G.FACTORY, _G.FACTORY_SEEN = msg, os.clock()
    elseif msg.type == "neural" then
      _G.NEURAL, _G.NEURAL_SEEN = msg, os.clock()
    end
  end
  -- Keep repeating a smelting order from chat until the smelter says it has it
  local c = _G.SMELT_CMD
  if c and not (_G.SMELTER and _G.SMELTER.lastCmd == c.seq) and os.clock() - lastSend >= 3 then
    rednet.broadcast({ type = "smelt_cmd", item = c.item, amount = c.amount, seq = c.seq }, BASE)
    lastSend = os.clock()
  end
end
