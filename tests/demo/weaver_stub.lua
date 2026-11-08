-- A stand-in Weaver for the Architect scenarios (tanis-weaver): sends a status every 3 s as Weaver-01. Change the global STATUS
-- (a table) to change what it says; the Architect scenario writes its hash into it.
local PROTOCOL = "tanis-weaver"
for _, n in ipairs(peripheral.getNames()) do if peripheral.hasType(n, "modem") then rednet.open(n) end end
STATUS = STATUS or { state = "building", msg = "", n = 1, label = "Weaver-01", layer = 1, total = 3, idx = 31, cells = 120, work = "layer",
  x = 5, y = 1, z = 2, fuel = 12000, gaps = 0 }
local timer = os.startTimer(0)
while true do
  local e, a = os.pullEvent()
  if e == "timer" and a == timer then
    local s = {}
    for k, v in pairs(STATUS) do s[k] = v end
    s.type = "status"
    rednet.broadcast(s, PROTOCOL)
    timer = os.startTimer(3)
  end
end
