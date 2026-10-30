-- mdforeman.lua  --  the MD Foreman: Canary control + the Mining Dimension's dock barrels (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Lives in the Mining Dimension (allthemodium:mining), by the Canaries' docks. Needs: an advanced computer with an
-- ender modem for the Canaries, a WIRED modem on the MD cable, and an advanced monitor touching it (optional:
-- the computer's own screen works too, click with the mouse). Force-load its chunk.
--
-- Barrels on the MD cable (everything on it is a barrel), each given a job with /assign:
--   Dock         one per Canary: he empties into it; I take everything out and put in the fuel he asks for
--   Output       goes home: barrel > hopper > ender chest (the same frequency as the Nether's Output)
--   Overflow     haul waits here while every Output is full, and drains back into it first
--   Stock        what stays in the MD: every lava bucket the factory makes, fuel up to its keep count (Rules)
--   Factory in   the lava factory's input: I keep it supplied with empty buckets
--   Factory out  the lava factory's output: emptied into Stock, so the factory never stalls
--   Input        drop things in by hand: sorted like a Canary's haul
--   Ignore       never touched
-- Empty and lava buckets never go home. Canaries' junk lists are junk.txt on each Canary.
--
-- Canary cards on the overview (state, depth, fuel, cargo); tap one for its layers, START, STOP + DOCK,
-- reboot, retire. Numbers Canary-01, -02... (a retired number is never handed out again). Saved in mdforeman.cfg.
-- The Overworld Foreman is the remote for every miner: it shows mine and sends Tanis's orders here.
-- Typed on the computer: /keep /assign /presets /rules (/help lists them all). docs/systems/miner.md.

-- The Foreman engine (shared/fm*.lua) does the work; this is what makes it the Mining Dimension's.
dofile("fm.lua")({
  title = "MD FOREMAN", short = "MD", name = "the MD Foreman", place = "the Mining Dimension",
  bird = "Canary", birds = "Canaries", kind = "canary", birdNames = { Canary = true },
  ownKinds = { canary = true }, registers = { Canary = true },
  protocol = "tanis-miner", config = "mdforeman.cfg", regKey = "canaries",
  dim = "allthemodium:mining", defR2 = 2, yMin = -63, yMax = 250, newEntry = { minY = -59, maxY = -54 },
  fuelTarget = true, barrels = true, neverHome = { ["minecraft:bucket"] = true, ["minecraft:lava_bucket"] = true },
  jobs = { "dock", "output", "overflow", "stock", "factory_in", "factory_out", "input", "ignore" },
  help = "/rules /keep <item> <n> /assign /presets /new /edit /delete /reboot /redock /monitors /home",
  -- First-run presets (absolute Y): the MD's ores sit where the Overworld's do. The docks are at Y 253, so a
  -- shaft to the bottom is ~316 blocks: wider areas make each trip down worth more.
  presets = {
    { name = "Diamonds",  minY = -59, maxY = -54, r1 = 0, r2 = 2 },
    { name = "Deep ores", minY = -59, maxY = -48, r1 = 0, r2 = 2 },
    { name = "Gold",      minY = -19, maxY = -13, r1 = 0, r2 = 2 },
    { name = "Lapis",     minY =  -3, maxY =   3, r1 = 0, r2 = 2 },
    { name = "Iron",      minY =  13, maxY =  19, r1 = 0, r2 = 2 },
    { name = "Copper",    minY =  45, maxY =  51, r1 = 0, r2 = 2 },
  },
  -- What the MD keeps by default (lava for the docks; empty buckets all go to the factory)
  keep = { ["minecraft:lava_bucket"] = 16, ["minecraft:coal_block"] = 16, ["minecraft:coal"] = 64 },
  remote = "dimension",
})
