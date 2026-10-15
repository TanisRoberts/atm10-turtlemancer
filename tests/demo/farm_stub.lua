-- tests/demo/farm_stub.lua  --  a stand-in farm turtle (Partridge or Woodpecker) for Farmhand scenarios.
-- Reads stub.cfg = { status = <the status message>, map = <the map message> }, broadcasts the status every 3 s
-- like farmbot.lua, answers map requests, keeps every order it gets in _G.cmds and confirms them the way
-- farmbot does (seq, setSeq and the settings it reports, rebootDone).
local f = fs.open("stub.cfg", "r"); local cfg = textutils.unserialise(f.readAll()); f.close()
peripheral.find("modem", function(n) rednet.open(n); return false end)
local P = "tanis-farm"
local status = cfg.status
status.id = os.getComputerID()
status.settings = status.settings or {}
_G.cmds, _G.mapreqs = {}, 0
local last = -100
while true do
  local from, msg = rednet.receive(P, 1)
  if type(msg) == "table" and msg.type == "mapreq" and tonumber(msg.to) == os.getComputerID() then
    _G.mapreqs = _G.mapreqs + 1
    rednet.send(from, cfg.map, P)
  end
  if type(msg) == "table" and msg.type == "cmd" and tonumber(msg.to) == os.getComputerID() then
    _G.cmds[#_G.cmds + 1] = msg
    if msg.want and msg.seq then
      status.seq = msg.seq
      if msg.want == "stop" then status.paused, status.state = true, "docked"
      elseif msg.want == "go" then status.paused, status.state = false, "working" end
    end
    if type(msg.set) == "table" and msg.setSeq then
      for k, v in pairs(msg.set) do status.settings[k] = v end
      status.setSeq = msg.setSeq
    end
    if msg.reboot then status.rebootDone = msg.reboot end
  end
  if os.clock() - last >= 3 then rednet.broadcast(status, P); last = os.clock() end
end
