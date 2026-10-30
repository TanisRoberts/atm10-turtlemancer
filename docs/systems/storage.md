# Storage (`computer/storage/`)

The only computer that moves items in or out of storage. This note covers the screens (UI kit, issue #21); design: `docs/design/storage.md`, kit: `docs/systems/ui.md`.

## Files

- `storage.lua`: scanning, sorting, drawers, docks, depots, fuel, network. Holds the "/" command handlers and hands the screens what they show.
- `storage_screens.lua`: the item list, report and progress pages, the take amounts, `/x1 /x16 /stack /sort`, and the two kit loops.
- `storage_lock.lua`: the padlock screen.
- `storage_rules.lua`, `storage_docks.lua`: depot rules and dock links (see the design doc).
- `shared/assignui.lua` + `shared/assignrules.lua`: the `/assign` pages, shared with the Nether and MD Foremen.

## Screens

Two kit views run side by side: the computer's own screen and the one monitor, picked by `shared/screens.lua` (`Scr.findMonitor`, the only place that asks; slot `screen`): the biggest one touching the computer, else the one you picked from the cable (see `docs/systems/screens.md`). The view is given the monitor's peripheral name, so taps on a wired monitor find it. `/monitors` forgets the pick and reboots, which asks again; a resized or unplugged monitor reboots too. Each has its own kit loop, so a long command on the computer never freezes the monitor.

**Item list.** Header `STORAGE`, state `ok` (or `NN% full` in orange from 90%), slots used/total on regular and wide screens (`Fuel NN%` first when there are fuel barrels, `MONITOR LOCKED` on the computer while locked). Row 3: `Sort Qty A-Z`. Take amount `x1 x16 Stack` (default Stack) sits on that row on the computer when it is 39 wide or more, in the footer on a monitor 30 wide or more, on a row of its own on a narrower monitor; a narrow computer uses `/x1 /x16 /stack`. Tapping an item (or Enter on the search bar for the top match) sends that amount to the output chest. The notice row says what was sent. The wheel and pager page the list.

**Computer only.** The search bar filters as you type. Typing `/` turns it into the command bar: the list becomes the command list, Tab completes, Up/Down choose, Enter runs, Esc backs out. The monitor has no keyboard, so no search.

**Commands** (typed with or without the slash; `shared/slash.lua`): `/assign`, `/setup`, `/rescan`, `/drawers`, `/tidy`, `/fuelinfo`, `/lock`, `/unlock`, `/x1`, `/x16`, `/stack`, `/sort qty|az`, `/help`. The old names `/addinput /fuel /dock /pocket /inputs` still run `/assign` and sit at the end of the list.

- `/drawers`, `/fuelinfo` and `/tidy` open a **report page** (`v:report`, Back returns). `/tidy` and `/rescan` show a spinner page while they work.
- `/setup` (marker chests) and a dock's keep list (inside `/assign`) still use a cleared plain terminal with prompts; the kit redraws afterwards.
- `/assign` ends the computer's kit loop, runs the assign screen on the same view and restarts the loop. The monitor keeps updating meanwhile.

**Lock screen.** The monitor shows a gold padlock at the biggest text scale that fits while the butler says Tanis is away (and auto-lock is on) or after `/lock`. It ignores taps. The computer's own screen always works. `/unlock` lifts a manual lock.

## `/assign`

Pages: list (tap a row to edit; search by name or contents; `+ Add`), kind (Depot / Fluid depot / Other job, only when the program has depots), pick (a container by name, or `Find it`: drop one item into the barrel, 30 s, the program stops moving items while it watches), edit (job switch, nickname, warnings, Save, tap-twice Delete), item (pick the item for a plain depot), and the depot rule pages (rule form, Item/Tag/Mod pick list with ticks, `Something like this`, Holds / Priority / Matches / Overlaps rows on the edit page). Rows show the job in its colour as a stripe. `(by name)` rows (drawers found by name) cannot be deleted.

`AUI.run(o)` keeps its options (see the header of `assignui.lua`); `o.view` lets the caller pass the kit view of its screen. Without it a view is made and the palette restored at the end.

## Tests

`tests/scenarios/storage_screens.lua` (list, search, command bar, `/assign`, Find it at 57x24, 51x19, 39x13 and 26x20; lock; reports; old command names; first run), `storage_depot_ui.lua`, `storage_depot.lua`, `storage_sort.lua`, and `mdforeman_basic.lua` for the Foreman's `/assign`.
