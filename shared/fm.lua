-- fm.lua  --  the Foreman engine: what the MD Foreman, the Nether Foreman and the Overworld Foreman share
-- (docs/systems/miner.md). A Foreman program is a profile plus:
--   dofile("fm.lua")(P)
-- The parts (fm_reg, fm_barrels, fm_draw, fm_pages, fm_edit, fm_cmd, fm_net, fm_remote) are loaded into ONE shared
-- environment, so a top-level name in one part (cfg, say, draw ...) is seen by all of them, as if they were one
-- file. Globals of the computer (term, rednet, colours ...) show through it. The profile is P.
--
-- P: title ("NETHER FOREMAN"), short ("NETHER"), name ("the Nether Foreman"), place ("the Nether"),
--    bird ("Firecrest"), birds ("Firecrests"), kind ("firecrest"), birdNames ({ Firecrest = true }),
--    protocol, config, regKey ("firecrests"), oldKey/oldPrefix (names from before the rename), dim,
--    defR2, yMin, yMax, newEntry ({ minY, maxY }), presets, keep, junk (nil: the miners keep their own),
--    lava (Firecrest's drink-lava rule), fuelTarget (Canary's top-up rule), barrels (a cable with jobs),
--    jobs (the barrel jobs offered, in order), help (the /help line), remote ("dimension" or "hub"),
--    screens (a function(F) that draws the Foreman on the UI kit instead of fm_draw/fm_pages/fm_edit/fm_cmd).
local PARTS = { "fm_reg.lua", "fm_barrels.lua", "fm_draw.lua", "fm_pages.lua", "fm_edit.lua", "fm_cmd.lua",
  "fm_net.lua", "fm_remote.lua" }

return function(P)
  local F = setmetatable({ P = P }, { __index = _ENV })
  for _, name in ipairs(PARTS) do
    local f = fs.open(name, "r")
    if not f then error("Missing " .. name .. ": reboot to update", 0) end
    local src = f.readAll(); f.close()
    assert(load(src, "@" .. name, "t", F))()
  end
  if P.screens then P.screens(F) end   -- a profile on the UI kit replaces the engine's drawing and input (foreman_screens.lua)
  F.start()
end
