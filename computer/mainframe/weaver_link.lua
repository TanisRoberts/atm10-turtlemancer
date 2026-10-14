-- weaver_link.lua  --  base-side radio link for Weaver the builder (runs from startup.lua)
--
-- Passes orders from chat (island weaver build/stop/test/clear) to Weaver and keeps his status
-- for the alerts. The Architect computer can order him too: whichever order is newest wins (seqs
-- are epochs), and this link takes over an Architect order it hears so it doesn't repeat an old one. The storage computer hears his material requests directly and fills his
-- supply barrel; if storage has gone quiet, this tells Weaver so he just checks the barrel.

local PROTOCOL   = "tanis-rigger"
local CONFIG     = "weaver_link.cfg"
local SEND_EVERY = 3

local cfg = { want = "idle", seq = 0 }
if fs.exists(CONFIG) then
  local f = fs.open(CONFIG, "r"); local t = textutils.unserialize(f.readAll()); f.close()
  if type(t) == "table" then cfg = t end
end
local function saveCfg()
  local f = fs.open(CONFIG, "w"); f.write(textutils.serialize(cfg)); f.close()
end

-- Talk on every modem: wireless/ender for turtles and far machines, wired for computers on the same cable
local modem
peripheral.find("modem", function(name, m) rednet.open(name); modem = modem or m; return false end)
if not modem then return os.pullEvent("never") end

local function sendCmd()
  rednet.broadcast({ type = "cmd", want = cfg.want, seq = cfg.seq }, PROTOCOL)
end

local lastSend, pendingReq = -100, nil
while true do
  local _, msg = rednet.receive(PROTOCOL, 1)
  if type(msg) == "table" then
    if msg.type == "status" then
      _G.WEAVER_STATUS, _G.WEAVER_SEEN = msg, os.clock()
    elseif msg.type == "cmd" and type(msg.seq) == "number" and msg.seq > (tonumber(cfg.seq) or 0) then
      cfg.want, cfg.seq = msg.want, msg.seq   -- someone else (the Architect) gave a newer order
      saveCfg()
    elseif msg.type == "need" then
      if not (pendingReq and pendingReq.seq == msg.seq) then pendingReq = msg; pendingReq.at = os.clock() end
    elseif msg.type == "supplied" and pendingReq and msg.seq == pendingReq.seq then
      pendingReq = nil              -- storage answered him
    end
  end

  -- New order from chat
  local c = _G.WEAVER_CMD
  if c and type(c.seq) == "number" and c.seq > (tonumber(cfg.seq) or 0) then
    cfg.want, cfg.seq = c.want, c.seq
    saveCfg()
    lastSend = -100
  end

  -- Storage computer silent: tell Weaver so he just checks the barrel (you can fill it by hand)
  local storageQuiet = not _G.STORAGE_SEEN or os.clock() - _G.STORAGE_SEEN > 20
  if pendingReq and storageQuiet and os.clock() - pendingReq.at > 2 then
    rednet.broadcast({ type = "supplied", seq = pendingReq.seq, got = {}, missing = pendingReq.items }, PROTOCOL)
    pendingReq = nil
  end

  if os.clock() - lastSend >= SEND_EVERY then
    sendCmd(); lastSend = os.clock()
  end
end
