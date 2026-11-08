-- architect.lua  --  the Architect (v2): one computer, one Weaver. docs/systems/weaver.md, screens: docs/design/architect-fleet.md.
--
-- Needs: an advanced computer with a wireless or ENDER modem (the Weaver works far away). Everything is on the computer's own
-- screen (tap it, or type). An advanced monitor touching it (any size) shows the map alone, following the Weaver.
-- A fresh Architect opens a setup wizard: 1 Weaver (pair with a new one, or re-link to a numbered one by typing it),
-- 2 Build (drag a .litematic onto the screen), 3 Site (where the dock and the build go), 4 Go. After that: Status, Map,
-- Side, Bill and Log tabs. Type `help` for commands.
--
-- The Architect holds the build (builds/<name>.plan2) and sends the Weaver ordered layer lists (the layer he builds and
-- the next), keeps the gap list, and broadcasts what is still needed to storage on tanis-base.
--
-- The program is in parts (architect_*.lua), loaded into ONE shared environment (as the Weaver is): a name defined in one
-- part is seen by all of them.
local PARTS = { "architect_base.lua", "architect_plan.lua", "architect_net.lua", "architect_tabs.lua", "architect_maps.lua", "architect_wizard.lua",
  "architect_site.lua", "architect_run.lua" }
local M = setmetatable({ args = { ... } }, { __index = _ENV })
ARCHITECT = M      -- (the sim reads the state from here)
for _, name in ipairs(PARTS) do
  local f = fs.open(name, "r")
  if not f then error("Missing " .. name .. ": reboot to update", 0) end
  local src = f.readAll(); f.close()
  assert(load(src, "@" .. name, "t", M))()
end
M.start()
