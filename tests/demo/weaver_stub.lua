-- A stand-in Weaver for the Architect scenarios: answers "ask" with a small plan (2 layers, a 10x6 slab)
-- and sends a status every 3 s. Set the global STATUS (a table) to change what it says.
local PROTOCOL = "tanis-rigger"
rednet.open(peripheral.getNames()[1] and (function()
  for _, n in ipairs(peripheral.getNames()) do if peripheral.hasType(n, "modem") then return n end end
end)())
STATUS = STATUS or { state = "building", msg = "", phase = "layer", layer = 1, layers = 2, cell = 31, placed = 30, total = 120,
  at = { x = 105, y = 70, z = 202, h = 1 }, v = 2, gaps = 0 }
local site = { cx = 100, cz = 200, sea = 62, seabed = 55, rot = 0, cruise = 80, dx = 98, dy = 64, dz = 198, dh = 0 }
local rows = {}
for z = 0, 5 do rows[#rows + 1] = { z, 0, "10#" } end
local info = { type = "info", id = os.getComputerID(), plan = "test slab", layers = 2, blocks = 120, ybase = 1, topY = 2,
  site = site, bounds = { x1 = 100, x2 = 109, z1 = 200, z2 = 205, y1 = 63, y2 = 64 }, ext = {}, profile = {} }
local timer = os.startTimer(0)
while true do
  local e, a, b, c = os.pullEvent()
  if e == "timer" and a == timer then
    local s = {}
    for k, v in pairs(STATUS) do s[k] = v end
    s.type, s.label, s.seq = "status", "Weaver-01", 0
    rednet.broadcast(s, PROTOCOL)
    timer = os.startTimer(3)
  elseif e == "rednet_message" and c == PROTOCOL and type(b) == "table" and b.type == "ask" then
    if b.what == "info" then rednet.send(a, info, PROTOCOL)
    elseif b.what == "layer" then rednet.send(a, { type = "layer", id = os.getComputerID(), n = b.n, rows = rows }, PROTOCOL) end
  end
end
