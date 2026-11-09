-- weaver.lua  --  Weaver v2: a build-agnostic builder turtle (CC:Tweaked, ATM10 / MC 1.21.1). docs/systems/weaver.md.
--
-- He knows nothing about any build. His Architect (a computer on the base network) pairs with him, holds the
-- build file and sends him the layer he is building and the next one as ordered cell lists, in dock
-- coordinates (the dock is 0,0,0; x east, y up, z south). He flies one block above each cell and places
-- downwards. Supply: one Ender Storage chest under his dock; he empties what he won't need into it, asks storage
-- for a batch over the radio and sucks it out once it has arrived. Cells storage has no block for become gaps.
-- GPS (the base's ender-modem towers) fixes his position and heading when it answers; else he counts his moves. Fuel and chunk loading: the turtle core.
-- Orders come from the Architect or the mainframe. Type `weaver found` after carrying him back to his dock.
--
-- The program is in parts (weaver_*.lua), loaded into ONE shared environment (as the miner is): a name defined in
-- one part is seen by all of them.
local PARTS = { "weaver_base.lua", "weaver_move.lua", "weaver_inv.lua", "weaver_gps.lua", "weaver_net.lua", "weaver_build.lua",
  "weaver_mark.lua", "weaver_loop.lua" }
local M = setmetatable({ core = dofile("turtlecore.lua"), args = { ... } }, { __index = _ENV })
for _, name in ipairs(PARTS) do
  local f = fs.open(name, "r")
  if not f then error("Missing " .. name .. ": reboot to update", 0) end
  local src = f.readAll(); f.close()
  assert(load(src, "@" .. name, "t", M))()
end
M.start()
