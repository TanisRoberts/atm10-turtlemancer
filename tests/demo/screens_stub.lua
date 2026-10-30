-- tests/demo/screens_stub.lua  --  a minimal controller on shared/screens.lua for the screens scenarios.
-- Reads stub.cfg = { slots = { {id=, label=, required=} ... } }. Asks for each slot, prints "got <id> <name>"
-- (or "got <id> none"), then runs the daemon and prints "changed <id>" for every screens_changed.
local f = fs.open("stub.cfg", "r"); local cfg = textutils.unserialise(f.readAll()); f.close()
local screens = require("screens")
local s = screens.new({ slots = cfg.slots })
_G.s = s
for _, sl in ipairs(cfg.slots) do
  local mon, name = s:get(sl.id)
  print("got " .. sl.id .. " " .. tostring(name or "none"))
end
parallel.waitForAny(
  function() s:daemon() end,
  function()
    while true do
      local _, id = os.pullEvent("screens_changed")
      print("changed " .. id)
    end
  end)
