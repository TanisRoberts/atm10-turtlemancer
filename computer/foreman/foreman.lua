-- foreman.lua  --  the Overworld Foreman: the remote for every miner in every dimension (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Needs: an advanced computer with an ENDER modem (reaches every dimension) and an advanced monitor touching it
-- (bigger is nicer; the computer's own screen works too, click with the mouse).
--
-- Two levels of Foreman (docs/systems/miner.md): each dimension with a base has its own Foreman, which owns its
-- miners and their docks (the MD Foreman: Canaries; the Nether Foreman: Firecrests). This one is the remote for
-- all of them: one card per miner with his dimension, and a tap opens his page (layers, START, STOP + DOCK,
-- reboot, retire), exactly as on his own Foreman's screen. What I'm asked to do for a Canary or a Firecrest I
-- ask his Foreman to do (protocol tanis-remote); I never give them orders myself. An order given on a
-- dimension Foreman's own screen shows here too.
-- Starlings (the End has no base, so no End Foreman) are mine: I number them and give their orders.
-- The Canary list (numbers, retired numbers) was mine before the MD Foreman: it takes it over once, when it
-- first starts. Junk caps from storage are passed on to every dimension Foreman.
--
-- Presets: named layer settings (Min/Max Y + which CHUNK rings to mine). Miners work chunk by chunk:
--   ring 0 = the dock's chunk, ring 1 = 3x3 chunks, ring 5 = 11x11 chunks; "from ring 2" skips a
--   middle that's already mined out. Past ring 1 a miner needs a chunk controller (or loaded chunks).
--   A miner's page offers his own Foreman's presets. The Presets page edits mine (Starlings') or, with
--   "Of:", a dimension Foreman's. Type /presets on the computer (/help lists the commands).

-- The Foreman engine (shared/fm*.lua) does the work; this is what makes it the Overworld's remote.
dofile("fm.lua")({
  title = "FOREMAN", short = "FOREMAN", name = "the Foreman", place = "the Overworld",
  bird = "Starling", birds = "miners", one = "miner", unit = "miner", birdNames = { Canary = true, Starling = true },
  protocol = "tanis-miner", config = "foreman.cfg", regKey = "canaries", oldKey = "diggers", oldPrefix = "Digger",
  dim = "overworld", defR2 = 3, yMin = -63, yMax = 319, newEntry = { minY = -59, maxY = -58 },
  help = "/presets /new /edit /delete <name>  /reboot /redock <miner|all>  /home",
  emptyText = {
    "No miners yet.",
    "Canaries come from the MD Foreman, Firecrests from the Nether",
    "Foreman. A Starling (the End) asks me for a number.",
  },
  -- First-run presets (absolute Y). Each pass covers 3 levels, so small ranges are cheap.
  presets = {
    { name = "Diamonds",  minY = -59, maxY = -58, r1 = 0, r2 = 3 },
    { name = "Deep ores", minY = -59, maxY = -48, r1 = 0, r2 = 3 },
    { name = "Gold",      minY = -19, maxY = -13, r1 = 0, r2 = 3 },
    { name = "Lapis",     minY =  -3, maxY =   3, r1 = 0, r2 = 3 },
    { name = "Iron",      minY =  13, maxY =  19, r1 = 0, r2 = 3 },
    { name = "Copper",    minY =  45, maxY =  51, r1 = 0, r2 = 3 },
  },
  remote = "hub",
})
