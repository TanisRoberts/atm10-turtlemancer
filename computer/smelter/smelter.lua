-- smelter.lua  --  the auto-smelting computer (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Hardware:
--   * A computer with a WIRED modem on the storage cable network (so it can see the furnaces).
--     It talks to the storage computer over the same cable; storage passes its news on to the
--     mainframe. A wireless/ender modem as well is fine but not needed.
--   * Furnaces (vanilla + every Iron Furnaces tier) on the storage cable. Blast furnaces/smokers are ignored.
--   * Optional: an advanced monitor touching the computer (tuned for 3 wide x 2 tall = 57x24).
--     The computer's own screen shows the same thing (click with the mouse, type commands).
--
-- The smelter decides WHAT to smelt and WHERE; the storage computer does every item move (it's the
-- only computer that touches storage), so the two never fight over the same barrels.
--
-- Which furnace: the fastest one that would finish the batch soonest. Iron Furnaces tiers are
-- ranked by their cook time (netherite before diamond before iron before a plain furnace), and
-- each furnace's real speed is measured as it works (speed augments, changed configs), so the best
-- furnaces get the work first and the slow ones only join in when there's plenty to go round.
--
-- Rules (smelt.txt, or tap a rule / a recipe on the screen):
--   "stone 20"  keep 20 stacks of stone          "iron all"  smelt every bit of raw iron that comes in
-- One-off jobs: "smelt stone 400" typed here, the rule page's Smelt now buttons, or chat "island smelt stone 400".
--
-- TRAINING: assign one furnace (somewhere out of the way, on the storage cable) as the trainer. It's
-- never part of the smelting array. Put a raw item in its top slot, tap TRAIN: the smelter fuels it,
-- waits for the first one to cook, and learns "this goes in, that comes out". Then pick a rule for it
-- (keep N stacks / smelt all / just learn it). Leftovers and the cooked item go back to storage.
-- Learned recipes live in smelter.cfg; the Recipes page lists everything it knows.
--
-- FACTORIES (ore doubling, Oct 2026): a Mekanism enriching factory (or chamber) set up as
--   feed barrel (on the cable, with a hopper upgrade pushing into one of the factory's Input faces)
--   -> factory (wired modem on it, so I can read it) -> auto-eject into an out barrel (on the cable).
-- Add one on the Factories page (or: factory add <machine> <feed> <out>). Storage fills the feed
-- barrel, treats the out barrel like an input chest, and never stores anything in either.
-- Raw ore with a factory route goes to the factories (whole batches: what a drip trial used, per process) instead of the
-- furnaces, and its dust is smelted. A new ore is tried once with a drip trial (drip.lua): one item at a
-- time until a process starts, eject off so I can read what comes out, eject back on. The dust is then checked in
-- the training furnace (it has to smelt into the same thing), and from then on that ore is enriched.
-- If every factory is down (gone, no power, stuck) for 5 minutes, ore goes to the furnaces again.

--
-- CODE LAYOUT: this file is the thin main. The program is split into modules (computer/smelter/smelter_*.lua)
-- that share one state table S: each module is `return function(S) ... end`, takes what it needs from S
-- (a name defined by an earlier module becomes a local alias, anything reassigned lives in S) and puts what
-- the others need back into S.
--   core     constants, saved config (cfg), shared state, small helpers, the link to storage
--   recipes  the recipe book, smelt.txt rules, learn / forget
--   factory  factories: routing, the drip trial, probe, adding and removing setups
--   pass     the smelting pass (fair shares, give / serve through storage)
--   train    the training furnace, "Find it", the factory-dust check
--   screen   the kit's views, the page router, button rows, the command bar and the event loop
--   home, trainui, lists, facui   the pages, built from the UI kit (home; training and pick the trainer; recipes and rule; factories)
--   net      status for chat and the mainframe, the slash commands (shared/slash.lua), the background loops

local S = {}
for _, part in ipairs({ "core", "recipes", "factory", "pass", "train", "screen", "home", "trainui", "lists", "facui", "net" }) do
  require("smelter_" .. part)(S)
end
local K, FX = S.K, S.FX

-- Talk on every modem: the wired one reaches storage over the cable, a wireless one (if any) the mainframe too
local opened = 0
peripheral.find("modem", function(name) rednet.open(name); opened = opened + 1; return false end)
if opened == 0 then
  printError("I need a modem: a wired modem on the storage cable is enough.")
  return
end
S.loadCfg()
S.buildBook()
S.loadSmeltRules()
S.findFurnaces()
do
  local t = FX.ts.recover(S.cfg)
  if t then
    S.train = t
    FX.notify(("Restarted mid-training: %s goes back into storage, nothing learned from that run."):format(S.pretty(t.input or "?")), K.orange)
  end
  if FX.cfgNote then S.saveCfg(); FX.notify(FX.cfgNote, K.orange) end
end
parallel.waitForAny(S.workLoop, S.trainLoop, S.netLoop, S.uiLoop)
