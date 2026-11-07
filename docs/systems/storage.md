# Storage (`computer/storage/`)

The only computer that moves items in or out of storage. This note covers the screens (UI kit, issue #21); design: `docs/design/storage.md`, kit: `docs/systems/ui.md`.

## Files

- `storage.lua`: scanning, sorting, drawers, docks, depots, fuel, network. Holds the "/" command handlers and hands the screens what they show.
- `storage_screens.lua`: the item list, report and progress pages, the take amounts, `/x1 /x16 /stack /sort`, and the two kit loops.
- `storage_lock.lua`: the padlock screen.
- `storage_rules.lua`, `storage_docks.lua`: depot rules and dock links (see the design doc).
- `storage_reactor.lua`: the Reactor fuel job (below).
- `storage_me.lua`: ME mode, AE2 through an ME Bridge as the storage (below).
- `storage_defrag.lua`: `/defrag` in ME mode (below).
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

Pages: list (tap a row to edit; search by name or contents; `+ Add`), kind (Depot / Fluid depot / Other job as pills with what each does in grey beside them, only when the program has depots), pick (a container by name, or `Find it`: drop one item into the barrel, 30 s, the program stops moving items while it watches), edit (job switch, nickname, warnings, Save, tap-twice Delete), item (pick the item for a plain depot), and the depot rule pages (rule form, Item/Tag/Mod pick list with ticks, `Something like this`, Holds / Priority / Matches / Overlaps rows on the edit page). Rows show the job in its colour as a stripe; the nickname or contents are grey. A page that redraws on every key never calls the cable from its draw (each inventory call waits a game tick and drops keys typed meanwhile): what a depot could hold is read once per page visit (`depotItems`); `w.ticks = true` in a scenario reproduces the dropped keys. `(by name)` rows (drawers found by name) cannot be deleted.

`AUI.run(o)` keeps its options (see the header of `assignui.lua`); `o.view` lets the caller pass the kit view of its screen. Without it a view is made and the palette restored at the end.

## Tests

`tests/scenarios/storage_screens.lua` (list, search, command bar, `/assign`, Find it at 57x24, 51x19, 39x13 and 26x20; lock; reports; old command names; first run), `storage_depot_ui.lua`, `storage_depot.lua`, `storage_sort.lua`, and `mdforeman_basic.lua` for the Foreman's `/assign`.

## Reactor fuel (`storage_reactor.lua`, #104)

An assigned inventory of type **Reactor fuel** (`cfg.reactorFuels`, `/assign`, one per reactor) is an Ender Storage chest on a full-block modem. Storage keeps it at a number of **fuel units** and tells the Operator.

- **Not storage.** It is special like a Canary fuel barrel: not counted, not sorted into, not a source for any move, `/tidy` and rescans never see it. **Nothing is ever pulled out of it**, and storage never crafts or compresses.
- **Settings** (`storage.env`, live, missing keys appended):
  - `REACTOR_FUEL=#c:storage_blocks/uranium=9,#c:ingots/uranium=1`: best first, `<item id or #tag>=<units>`. Tags are read from `getItemDetail().tags` (the same `info` the depot rules use). The first entry an item matches wins.
  - `REACTOR_FUEL_KEEP=64` fuel units per chest, `REACTOR_FUEL_LOW=16` (reported, the mainframe alerts on it).
- **Top-up** (every worker pass): units in the chest = what is on the list, counted with the values above (other items are ignored). Short of `KEEP`, it takes the best listed fuel storage has, rounding up to a whole item (so it overshoots by less than one item's value), then the next one down. A chest already over `KEEP` is left alone.
- **Waste** is an ordinary **Input**: assign the waste chest as Input and storage empties it. Both ender chests must be assigned, or storage treats them as storage.
- **Report** on protocol `tanis-operator` (`rednet.broadcast`), every 10 s and right after a top-up, only while a chest is assigned:
  `{ type = "reactor_fuel", chests = { { name, label, units, keep, low } }, supply = <units of every listed fuel in storage, chests not counted>, best = <item id being stocked with, nil when supply == 0> }`.
- `/assign` shows each chest as `48/64 units`.

Test: `tests/scenarios/storage_reactor.lua`.

## ME mode (`storage_me.lua`, #124)

When an **ME Bridge** (`me_bridge`, the first one by name) is on the cable, AE2 is the storage. Without one, storage works as described above (drawers, barrels, `/tidy`). The mode is read on every rescan; the command list is fixed at boot, so reboot after plugging in or removing a bridge.

- **Storage is the bridge.** No inventory on the cable is storage: only assigned job inventories are touched. Unassigned ones, ME drives, interfaces and IO ports with modems are never sorted into, taken from or counted.
- **Two seams.** `retrieve()` is `exportItem(target, {name, nbtHash, count, toSlot})`: one call moves any amount. Deposit (`moveInto` with the single target `mode = "me"`) is `importItem(source, {name, fromSlot, count})`: the slot pins the exact stack, so no hash is needed. Every job goes through them unchanged: inputs, output, docks and keep lists, depots and rules, Canary fuel and dump, smelter and neural ops, Weaver supply, pocket dump and restock, reactor fuel. Junk caps read `byName`.
- **Variants.** The item list is `getItems()`; a variant's key is `name` or `name#<hash>` (the bridge's `nbt`). A depot gets its winner's exact key, so it never receives another variant of the same item. A plain-name request (docks, fuel) leaves the variant to AE2, because the filter cannot ask for "no NBT". Stack sizes of items the bridge lists are guessed at 64 until a real stack of that item passes through a job inventory (`getItemDetail`).
- **Refresh.** The list is rebuilt from `getItems()` on the FULL_SCAN rhythm and after any move.
- **Off in ME mode:** drawer planning, `/drawers`, `/tidy` and `/setup` (not in `/help` or the command list). Fluids are unchanged (tanks, fluid depots).
- **Status** (`type = "storage"`): `used` and `total` are item **bytes** (`getUsedItemStorage` / `getMaxItemStorage`), `unit = "bytes"`, `meOffline = true` while the bridge is down. There is no `types`: the bridge reports no used types per cell. The mainframe words it as bytes and "time for more cells" (`island.lua`, `butler.lua`).
- **Item list.** The header shows `used/total bytes NN%`; `NN% full` in orange from 90%. Offline (`isConnected`/`isOnline` false, or no answer) it shows `ME offline` in red, keeps the last list, and the jobs run on what is on the cable: inputs wait (no "input stuck" alert) and refills do nothing until AE2 is back.

Test: `tests/scenarios/storage_me.lua` (uses the bridge mock `tests/sim/me.lua`).

## Defrag (`storage_defrag.lua`, #126)

`/defrag` (ME mode only) moves piles out of low-priority drives (small cells) into the highest-priority drives with room. AE2 inserts at the highest priority first and extracts from the lowest, so a **round trip** (export a chunk to the buffer, import all of it back) moves it from the lowest tier holding it into the top tier. Cell bytes from `getDrives` are only as fresh as AE2's last drive save (up to ~5 min, AP builds the cell info from the saved stack), so a run never measures bytes per trip. A **tier** is a drive priority (a rack shares one). Tiers with no sized cells (empty drives, Infinity/Bulk only) are left out of the tier list; the start page lists them dim (`p20: 2 drives, no sized cells: ignored`).  An ignored empty tier above the top sized tier also gets a warning (`p4000 has drives but no cells: fit cells there to defrag into it`). The finish reason puts its numbers on a second line. Priority 9999 storage buses (void drawers) are not drives and never show as tiers, but a round trip fills them first.

- **Defrag buffer.** An `/assign` job (one, any inventory, bigger = fewer trips; `cfg.defragBuffer`). Not storage, never counted. Whatever is in it goes back into AE2 at boot, after every run and every 30 s.
- **Start page.** Tiers (`P10: 1 rack, 8 drives  used/total bytes`), warnings (fewer than two priorities with sized cells: `Nothing to defrag towards`, Start is off; no buffer), `N items from infinity cells: skipped`, items to move with `about N min` (items ÷ buffer size × ~1.5 s per trip), items it would move (piles of at least `DEFRAG_MIN`, biggest first) and the **voided** list. A bus cannot be seen from the bridge, so a void drawer is declared in `storage.env`.
- **Infinity cells** (ExtendedAE) report their item at 2,147,483,647 and never lose or gain any: any item at that count is never queued.
- **Run.** Per item a fixed amount goes through the buffer: its count, less the `DEFRAG_VOID` keep when listed (the drawer holds that much). AE2 extracts lowest priority first and inserts highest first, so after the whole amount has made the trip every unit has had its chance to move up. Each trip is one `exportItem` and one `importItem` with no `fromSlot` (AP walks every slot). The destination is every sized tier except the lowest; it stops when their combined free bytes are under 5% (`upper tiers nearly full (p10: 2% free, p5: 4% free)`; bytes lag one autosave, fine for this rough guard), on Stop, or when the list is done. The grid's item count is read live after each trip: an item whose total drops without being in `DEFRAG_VOID` was voided by a bus nobody declared: shown in red and left alone from then on.
- **Yields.** The step is the worker's last job each pass, so docks, depots, fuel, smelter and Weaver run on time. It does not run while `paused` (Find it, barrel probe, setup) or while `/assign` holds the worker.
- **Progress page.** Item now, items done/left, `Moved N of M` items, bytes freed in the low tiers (`since last save`, may lag up to ~5 min), Stop. Back leaves it running; `/defrag` again reopens it.
- **Settings** (`storage.env`): `DEFRAG_SKIP=` item ids or `#tags` never moved; `DEFRAG_MIN=0` skip piles smaller than this (0 = one stack); `DEFRAG_VOID=minecraft:deepslate=256000` items behind a void drawer and how many it keeps.
- **Broadcast** on `tanis-base` every 3 s while running and once at the end: `{ type = "defrag", running, item, done, left, moved, toMove, freedBytes }`.

Test: `tests/scenarios/storage_defrag.lua`.
