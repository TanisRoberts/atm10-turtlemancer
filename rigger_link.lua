-- rigger_link.lua  --  base-side radio link for Rigger the builder (runs from startup.lua)
--
-- Passes orders from chat (island rigger build/stop/test/clear) to Rigger, keeps his status
-- for the alerts, and hands his material requests to storage, which fills his supply barrel.

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
      pendingReq = msg
      _G.RIGGER_REQUEST = msg       -- storage fills the supply barrel and answers in RIGGER_SUPPLIED
    end
  end

  -- New order from chat
  local c = _G.RIGGER_CMD
  if c and c.seq ~= cfg.seq then
    cfg.want, cfg.seq = c.want, c.seq
    saveCfg()
    lastSend = -100
  end

  -- Storage finished a request
  local s = _G.RIGGER_SUPPLIED
  if pendingReq and s and s.seq == pendingReq.seq then
    rednet.broadcast({ type = "supplied", seq = s.seq, got = s.got, missing = s.missing }, PROTOCOL)
    pendingReq = nil
  elseif pendingReq and not _G.STORAGE_STATS then
    -- Storage isn't running: tell Rigger so he just checks the barrel
    rednet.broadcast({ type = "supplied", seq = pendingReq.seq, got = {}, missing = pendingReq.items }, PROTOCOL)
    pendingReq = nil
  end

  if os.clock() - lastSend >= SEND_EVERY then
    sendCmd(); lastSend = os.clock()
  end
end
