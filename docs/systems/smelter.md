# Smelter: factories and the drip trial

Code: `computer/smelter/smelter.lua` (everything under `FX.`), decisions in `computer/smelter/drip.lua`.

## Factory routing
- A setup is feed barrel → hopper → factory → out barrel (`factory add <machine> <feed> <out>`; Mekanism machines are read-only over the cable). The process count is read from the machine (`getInput(p)` until it stops answering), never hard-coded.
- What an ore does is learned once, in `cfg.enrich[ore]`: `{ out, used, made, drip = true }` or `{ no = true }`. `used` is ore for ONE process, so a routing batch is `used x processes` (`FX.unitOf`). Entries from before the drip trial (no `drip` flag) count 3 per process.
- A factory that has been unseen for 10 s reads "factory missing, re-add it" on the screen and in the terminal (with the candidate machine, if one is on the cable). After 5 minutes ore goes to the furnaces again.

## The drip trial (fewest items)
1. Starts only on an idle factory: inputs, outputs and feed barrel empty for 3 s, nothing routed to it lately. If none is idle, the emptiest one is reserved (nothing new routed to it) until it is.
2. Saves eject and auto-sort in `smelter.cfg` (`trialSaved`), turns both off, puts ONE item in the feed barrel. Nothing else goes into that feed or factory until the trial ends; other factories carry on.
3. After each drip it waits, then asks `drip.started`: did a process start? If not, one more item. `n` = items added when one started.
   - Default detector: wait one operation (`getTicksRequired`, +1.5 s) and watch the input count drop or an output appear.
   - `dripProgress = true` in `smelter.cfg` switches to `getRecipeProgress(p) > 0` (2 s after each drip). The choice is one function, `D.started`, plus `D.waitFor`.
4. The started operation finishes; the output count is read once stable: learned `{ used = n, made = count }`. `D.result` builds that table (one place to add fields).
5. Ends: never reached the input within 20 s = refused, `{ no = true }` and an alert (one item is stuck in the hopper, pull it by hand). 16 items with nothing started = called off, nothing learned, an alert says what is inside. Storage failing to deliver three times = called off.
6. No learning or refusing while the factory has 0 energy: the trial's clock stands still.

Settings come back when the trial ends, is cancelled (`factory remove`, `probe stop`), or the smelter reboots mid-trial (`readFactory` restores whatever `trialSaved` holds as soon as it sees the machine and no trial runs).

## probe
`probe [item] [factory number]` on the smelter's command line (default `minecraft:ancient_debris`, first factory). It waits for a free factory (pausing the smelter's use of it; the factory line says "probe"), runs a drip trial that learns nothing, and logs every 0.5 s `feed`, `getTicksRequired` and `getInput / getOutput / getRecipeProgress` for each process into `probe.log`, then uploads it with `pastebin put`. `probe stop` ends it.

## Tests
`tests/scenarios/smelter_drip.lua` runs the real smelter and storage against `tests/sim/factory.lua` (a mock Mekanism factory with a hopper).
