-- nether.lua  --  the Nether Foreman: Firecrest control + the Nether dock barrels (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Lives in the Nether, next to Firecrest's dock. Needs: an advanced computer with an ender (or wireless)
-- modem for the Firecrests, a WIRED modem on the Nether cable, and an advanced monitor touching it
-- (optional: the computer's own screen works too, click with the mouse). Force-load its chunk.
--
-- Barrels on the Nether cable, each given a job with /assign (the same screen as storage's):
--   Dock    one per Firecrest: he empties into it; I take everything out and put in what he asks for
--   Output  goes home: barrel > hopper > ender chest (its twin at home feeds storage's input)
--   Stock   what stays in the Nether (spare buckets, lava buckets, coal...): see Rules
--   Input   drop things in by hand: sorted like Firecrest's haul
--   Ignore  never touched
-- Everything Firecrest brings (and anything in an Input) goes to Stock if the Rules keep some of it and
-- Stock is short, else home through the Output. Stock above its keep count goes home too.
--
-- Firecrest: one card each on the overview (state, depth, fuel, cargo); tap one for its layers
-- (presets or Min/Max/rings), START, STOP + DOCK, reboot, retire. Numbers Firecrest-01, -02... like
-- the Foreman's Canaries (a retired number is never handed out again). Saved in nether.cfg.
-- Rules page: when Firecrests drink lava (under 25% until 75% by default), what the Nether keeps and
-- what Firecrest throws away underground. Typed on the computer: /keep /junk /unjunk /assign /presets
-- (/help lists them all). What it shows is computer/nether/nether_screens.lua, on the UI kit.

-- The Foreman engine (shared/fm*.lua) does the work; this is what makes it the Nether's.
require("fm")({
  title = "NETHER FOREMAN", short = "NETHER", name = "the Nether Foreman", place = "the Nether",
  bird = "Firecrest", birds = "Firecrests", one = "firecrest", unit = "firecrest", kind = "firecrest", birdNames = { Firecrest = true },
  protocol = "tanis-nether", config = "nether.cfg", regKey = "firecrests", oldKey = "diggers", oldPrefix = "Pigger",
  dim = "the_nether", defR2 = 1, yMin = 6, yMax = 120, newEntry = { minY = 12, maxY = 17 },
  lava = true, barrels = true, jobs = { "dock", "output", "stock", "input", "ignore" },
  -- First-run presets (absolute Y). Ancient debris is commonest around Y 15; the lava sea is at Y 31.
  presets = {
    { name = "Debris",      minY = 12, maxY = 17, r1 = 0, r2 = 1 },
    { name = "Debris deep", minY =  8, maxY = 22, r1 = 0, r2 = 1 },
    { name = "Above lava",  minY = 33, maxY = 44, r1 = 0, r2 = 1 },
    { name = "High quartz", minY = 60, maxY = 74, r1 = 0, r2 = 1 },
  },
  -- What the Nether keeps by default (the rest goes home), and what Firecrest throws away underground
  keep = {
    ["minecraft:bucket"] = 4, ["minecraft:lava_bucket"] = 16, ["minecraft:coal"] = 64,
    ["minecraft:charcoal"] = 64, ["minecraft:coal_block"] = 16, ["minecraft:blaze_rod"] = 64,
  },
  junk = { "netherrack", "blackstone", "basalt", "smooth_basalt", "soul_sand", "soul_soil",
    "magma_block", "gravel", "crimson_nylium", "warped_nylium", "nether_wart_block", "warped_wart_block",
    "cobblestone", "cobbled_deepslate", "polished_blackstone_bricks" },
  remote = "dimension",
  emptyText = { "No Firecrests yet. A Firecrest asks me for a number the first time it starts at its dock." },
  screens = require("nether_screens"),   -- everything it shows: computer/nether/nether_screens.lua (docs/systems/nether.md)
})
