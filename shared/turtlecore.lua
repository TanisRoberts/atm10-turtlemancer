-- turtlecore.lua  --  what every turtle shares: fuel (one table, lava and coal), its dock, and GPS.
-- docs/systems/turtle.md has the API. Loaded with dofile() like farmbot.lua; the parts are separate
-- files (turtlecore_fuel / _dock / _gps), each one `return function(core) ... end`, as ui.lua loads its parts.
--   local core = dofile("turtlecore.lua")
--   core.fuel.refuelFromInventory(target)   core.dock.report()   core.gps.locate(2)
-- The core never digs anything.
local core = {}
dofile("turtlecore_gps.lua")(core)
dofile("turtlecore_fuel.lua")(core)
dofile("turtlecore_dock.lua")(core)
return core
