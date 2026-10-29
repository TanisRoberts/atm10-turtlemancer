# Smelter: factories and the drip trial

Code: `computer/smelter/smelter.lua` is the thin main; the program lives in modules that share one state table `S` (each is `return function(S) ... end`; names an earlier module defined are local aliases, anything reassigned lives in `S`, and what others need is exported to `S` at the end):

| Module | Holds |
|---|---|
| `smelter_core` | constants, `cfg` load/save, shared state, small helpers, the link to storage (`sendBatch`) |
| `smelter_recipes` | recipe book, `smelt.txt` rules, `learn` / `forget` |
| `smelter_factory` | everything under `FX.`: routing, drip trial, probe, add/remove setups |
| `smelter_pass` | the smelting pass (fair shares, give/serve) |
| `smelter_train` | training furnace, "Find it", factory-dust check |
| `smelter_screen` | views, drawing helpers, draw cycle, touch/key loop |
| `smelter_home`, `smelter_trainui` | the pages (all drawing code stays in the screen modules) |
| `smelter_net` | status for chat/mainframe, terminal commands, background loops |

A new module needs its `manifest.lua` entry and a slot in the load list in `smelter.lua`. Drip decisions are in `drip.lua`, direct/via-dust and the hand-added list in `direct.lua`, power-cut safe config in `trainsafe.lua`.

## Factory routing
- A setup is feed barrel → hopper → factory → out barrel (`factory add <machine> <feed> <out>`; Mekanism machines are read-only over the cable). The process count is read from the machine (`getInput(p)` until it stops answering), never hard-coded.
- What an ore does is learned once, in `cfg.enrich[ore]`: `{ out, used, made, drip = true }` or `{ no = true }`. `used` is ore for ONE process, so a routing batch is `used x processes` (`FX.unitOf`). Entries from before the drip trial (no `drip` flag) count 3 per process.
- A factory that has been unseen for 10 s reads "factory missing, re-add it" on the screen and in the terminal (with the candidate machine, if one is on the cable). After 5 minutes ore goes to the furnaces again.

## Adding items by hand, and direct products
- `enrich add <item>` (full id, short name or suffix, like `enrich forget`) puts an item in `cfg.enrichExtra`, so it gets a normal drip trial even though it isn't an ore (`FX.trialable`). The list survives restarts and `enrich forget` (forget clears the learned result only and the item is trialled again).
- After a trial, the product is compared with the smelter's recipe book (`direct.lua`): the furnace makes the same product from the item = **direct** (`direct = true` in the entry, passed to `D.result`). Ancient debris → netherite scrap is the case. A direct product skips the dust check, only the recipe making that product routes the item to the factory, and the output goes to storage through the out barrel. Entries are also treated as direct when the book learns the furnace recipe later.
- Otherwise the product is a dust the furnace smelts (**via dust**, as raw iron) or something the dust check decides about (its ore stays in the furnaces if the dust won't smelt, or if there is no trainer and the names don't fit).
- `FX.enrichList` states: `refused`, `dust won't smelt`, `direct`, `via dust`, `checking dust`.

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

## Training: saving and power cuts (`trainsafe.lua`)
- `learn` saves `smelter.cfg` the moment the output is seen. The file is written as `.new` then swapped in (`.bak` keeps the previous one). On boot it loads `smelter.cfg`, else `.new`, else `.bak`; a file that exists but can't be parsed is moved to `smelter.cfg.bad` and never overwritten by an empty config. The screen says when a fallback was used.
- `cfg.training = { input }` is set while the trainer holds something the program put there (a run, the hand-back to storage, an auto dust check) and cleared when it is empty again. If it is still set at boot, the run is discarded: the trainer is emptied into storage and the screen says so. Nothing is learned from a half run (a recipe is only saved whole, when the output appears).
- Factory enrichment results (`cfg.enrich`) go through the same save; the drip trial's own recovery is above.
- Tests: `tests/scenarios/smelter_train.lua`.
