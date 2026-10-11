-- rigger_link.lua  --  base-side radio link for Rigger the builder (runs from startup.lua)
--
-- Passes orders from chat (island rigger build/stop/test/clear) to Rigger and keeps his status
-- for the alerts. The storage computer hears his material requests directly and fills his
-- supply barrel; if storage has gone quiet, this tells Rigger so he just checks the barrel.

local PROTOCOL   = "tanis-rigger"
local CONFIG     = "rigger_link.cfg"
local SEND_EVERY = 3

local cfg = { want = "idle", seq = 0 }
if fs.exists(CONFIG) then
  local f = fs.open(CONFIG, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  if type(t) == "table" then cfg = t end
end
local function saveCfg()
  local f = fs.open(CONFIG, "w"); f.write(textutils.serialize(cfg)); f.close()
end

local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then return os.pullEvent("never") end
rednet.open(peripheral.getName(modem))

local function sendCmd()
  rednet.broadcast({ type = "cmd", want = cfg.want, seq = cfg.seq }, PROTOCOL)
end

local lastSend, pendingReq = -100, nil
while true do
  local _, msg = rednet.receive(PROTOCOL, 1)
  if type(msg) == "table" then
    if msg.type == "status" then
      _G.RIGGER_STATUS, _G.RIGGER_SEEN = msg, os.clock()
    elseif msg.type == "need" then
      if not (pendingReq and pendingReq.seq == msg.seq) then pendingReq = msg; pendingReq.at = os.clock() end
    elseif msg.type == "supplied" and pendingReq and msg.seq == pendingReq.seq then
      pendingReq = nil              -- storage answered him
    end
  end

  -- New order from chat
  local c = _G.RIGGER_CMD
  if c and c.seq ~= cfg.seq then
    cfg.want, cfg.seq = c.want, c.seq
    saveCfg()
    lastSend = -100
  end

  -- Storage computer silent: tell Rigger so he just checks the barrel (you can fill it by hand)
  local storageQuiet = not _G.STORAGE_SEEN or os.clock() - _G.STORAGE_SEEN > 20
  if pendingReq and storageQuiet and os.clock() - pendingReq.at > 2 then
    rednet.broadcast({ type = "supplied", seq = pendingReq.seq, got = {}, missing = pendingReq.items }, PROTOCOL)
    pendingReq = nil
  end

  if os.clock() - lastSend >= SEND_EVERY then
    sendCmd(); lastSend = os.clock()
  end
end
