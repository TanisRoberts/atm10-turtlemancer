# Smelter: factories and the drip trial

Code: `computer/smelter/smelter.lua` is the thin main; the program lives in modules that share one state table `S` (each is `return function(S) ... end`; names an earlier module defined are local aliases, anything reassigned lives in `S`, and what others need is exported to `S` at the end):

| Module | Holds |
|---|---|
| `smelter_core` | constants, `cfg` load/save, shared state, small helpers, the link to storage (`sendBatch`) |
| `smelter_recipes` | recipe book, `smelt.txt` rules, `learn` / `forget` |
| `smelter_factory` | everything under `FX.`: routing, drip trial, probe, add/remove setups |
| `smelter_pass` | the smelting pass (fair shares, give/serve) |
| `smelter_train` | training furnace, "Find it", factory-dust check |
| `smelter_screen` | the kit's views, page router (`S.go`), button rows (`S.plan`), command bar, event loop |
| `smelter_home`, `smelter_trainui`, `smelter_lists`, `smelter_facui` | the pages (home; training and pick the trainer; recipes and rule; factories and the add wizard) |
| `smelter_net` | status for chat/mainframe, the slash commands, background loops |

All drawing is in the four page modules and uses only the UI kit (`docs/systems/ui.md`); nothing writes to a terminal. A page is `S.pages.<name> = function(v, st)` (`v` the kit view, `st` that screen's own page state); `S.go(v, page, extra)` opens one. A new module needs its `manifest.lua` entry and a slot in the load list in `smelter.lua`. Drip decisions are in `drip.lua`, direct/via-dust and the hand-added list in `direct.lua`, power-cut safe config in `trainsafe.lua`.

## Factory routing
- A setup is feed barrel → hopper → factory → out barrel (`factory add <machine> <feed> <out>`; Mekanism machines are read-only over the cable). The process count is read from the machine (`getInput(p)` until it stops answering), never hard-coded.
- What an ore does is learned once, in `cfg.enrich[ore]`: `{ out, used, made, drip = true }` or `{ no = true }`. `used` is ore for ONE process, so a routing batch is `used x processes` (`FX.unitOf`). Entries from before the drip trial (no `drip` flag) count 3 per process.
- A factory that has been unseen for 10 s reads "factory missing, re-add it" on the screen and in the terminal (with the candidate machine, if one is on the cable). After 5 minutes ore goes to the furnaces again.

## Adding items by hand, and direct products
- `enrich add <item>` (full id, short name or suffix, like `enrich forget`) puts an item in `cfg.enrichExtra`, so it gets a normal drip trial even though it isn't an ore (`FX.trialable`). The list survives restarts and `enrich forget` (forget clears the learned result only and the item is trialled again). `enrich remove <item>` drops a hand-added item and its learned result for good (a running trial of it is called off). The terminal commands and the Factories page buttons call the same functions: `FX.enrichAdd / enrichForget / enrichRemove`. Only an item some recipe takes as an input gets trialled; any other hand-added item stays `queued`.
- After a trial, the product is compared with the smelter's recipe book (`direct.lua`): the furnace makes the same product from the item = **direct** (`direct = true` in the entry, passed to `D.result`). Ancient debris → netherite scrap is the case. A direct product skips the dust check, only the recipe making that product routes the item to the factory, and the output goes to storage through the out barrel. Entries are also treated as direct when the book learns the furnace recipe later.
- Otherwise the product is a dust the furnace smelts (**via dust**, as raw iron) or something the dust check decides about (its ore stays in the furnaces if the dust won't smelt, or if there is no trainer and the names don't fit).
- `FX.enrichList` states: `queued` (hand-added, no result yet, waiting for an idle factory), `trying n` (a trial has dripped n items), `refused`, `not worth it` (the dust won't smelt), `direct`, `via dust`, `checking dust`.

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


## Screens
The monitor and the computer's own screen are two kit views; each keeps its own page and state (`S.states.monitor`, `S.states.term`). The computer's screen also has the command bar (below). Every screen has Back (or the `<` pill on a narrow one) to its parent; the pager and the mouse wheel page long lists.

- **Home:** a tile per furnace, fastest first, with its tier band, item, count left and finished items waiting (`+12`). A cooking furnace gets one smelting glyph at the end of its band (`ui.beat(2)`; `ANIM=off` stills it). At 44 wide or more a right column shows the trainer, the factories (a line each), the rules (tap one) and one-off jobs; narrower screens reach those through the buttons. Footer buttons: TRAIN, Recipes, Pause / Run, Factories (short names on a narrow screen; they wrap onto the rows above the footer when they do not fit). Header: `ok`, `paused`, or `error` with a red "Storage not heard" line.
- **Training:** idle (put the raw item in the top slot), ready, cooking (steps, progress bar, CANCEL is tap-twice), learned (choose No rule / Keep N stacks (stepper) / Smelt all, then Save or Just learn it), failed (TRY AGAIN). Screens 50 wide and 17 tall or more draw the furnace with PUT IN / COMES OUT cards, flames, smoke and sparkles (on `ui.beat(4)`, `ANIM=full` only); smaller ones list the two items. "Restarted mid-training" (#12) shows as a notice on boot.
- **Pick the trainer:** a list of the furnaces (one tap picks), Find it (drop an item into the top slot, with a spinner and a countdown bar), No trainer (tap-twice).
- **Recipes:** every recipe with its rule; a gold stripe (a star on a narrow screen) marks the learned ones; one tap opens the rule page. **Rule:** what it makes and where from, a No rule / Keep N stacks / Smelt all switch, Smelt 64 / 256 / 1024 / all, Save, Forget (tap-twice, learned only). Save and Back return to where it was opened from.
- **Factories:** a card per factory (state in the stripe, power, machine and process count, feed and out barrel; "factory missing, re-add it" in red with "not on the cable"), then the ORES list: each learned ore with `made per used` and its state (`direct`, `via dust` lime; `checking dust` gold; `refused`, `dust won't smelt` orange). Tap a card to select it; `Remove F#` is tap-twice. `+ Add` opens the wizard: factory, feed barrel, out barrel, one tap each. The footer is one list of buttons (`S.plan`) and the ORES list is a kit list, so more buttons and a pick page (#64) are added next to them.

## Typed commands
Type on the computer's own screen with or without the slash; `/` lists them, Tab completes, `/help` (or `/help <command>`) explains (`shared/slash.lua`, `smelter_net.lua`). Enter with nothing typed starts training on the training page.

| Command | Does |
|---|---|
| `smelt <item> <n>` | queue a one-off job |
| `train`, `trainer` (`pick`), `recipes`, `factories`, `home` | open that page |
| `rule <item>` | open one recipe's rule |
| `pause`, `run` (`resume`, `go`), `reload` | pause or resume smelting, read `smelt.txt` again |
| `status` | one line: furnaces, trainer, queue, factories, rules |
| `factory add <machine> <feed> <out>`, `factory remove <n>` | set up or remove a factory |
| `probe [item] [factory]`, `probe stop` | log what a factory does |
| `enrich add <item>`, `enrich forget <ore>` | try an item in the factories, or forget what was learned |

Terminal log lines (the factory trial and probe print them) scroll the screen, so they go through `FX.print`, which repaints the kit afterwards.

Tests: `tests/scenarios/smelter_pages.lua` (every page at 57x24, 51x19, 39x13, 26x20), `smelter_screens.lua` (lists, taps, training, factories, commands), `smelter_motion.lua` (the dashboard glyph).
- **Factories:** a card per factory (tap to select, then Remove F*n*, tap-twice) and the ORES list: every learned ore and every hand-added item (leading `+`) with its state on the right. Footer: `+ Add`, `+ Item`; tapping an ORES row adds `Retry` (= `enrich forget`) and, for hand-added items only, a tap-twice `Remove` (= `enrich remove`). Selecting an ore row lets go of a selected card and the reverse. **+ Item** (`fitem` page) lists storage's items most first, `Smeltable` (the book cooks it, or an ore, or hand-added) or `All`; tap one then `Try it` (`already on` rows can't be picked). The state is queued by `FX.enrichAdd`; Back is Cancel. Code: `smelter_facui.lua`; test: `tests/scenarios/smelter_item.lua`.
