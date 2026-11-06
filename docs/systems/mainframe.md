# Mainframe: the monitor wall

Design and mockups: `docs/design/mainframe.md`. Kit: `docs/systems/ui.md`. Code: `computer/mainframe/`.

## How the wall is drawn

`mainframe.lua` is the one place that looks for the monitor (the biggest one touching the computer) and runs `require("wall").run(mon, name)`, with the monitor's peripheral name so `ui.view(mon, { side = name })` can find its touch events. Nothing draws except `wall.lua`; it is read-only (no buttons).

The programs that used to draw now hand data over in globals, and `wall.lua` redraws once a second (and on kit beats):

| Global | Set by | Holds |
|---|---|---|
| `_G.WALL_STRIP` | `island.lua` (every 2 s) | time, phase, day, weather, moon, biome, light, nearby entities, hostiles, the current alert `{ text, more }` |
| `_G.WALL_BOARD` | `board.lua` (every 2 s) | rows `{ name, state, detail, seen, group }`, `seen` an `os.clock()` time |
| `_G.WALL_VISITORS` | `butler.lua` (each presence check) | rows `{ name, when, tone, here }`, `detector`, `foot = { text, tone }` |

`wall.layout(W, H)` says where things go.

- **Text size:** `SCALE=1` in `wall.env` (with `PAGE_S`, both read by `mainframe.lua` at boot; 0.5 to 5 in steps of 0.5; reboot after an edit). An 8x6 wall is 82x40 at 1 (164x81 at 0.5).
- **Normal wall** (57x24, 57x38, 36x24): strip on rows 1-3 (island chip, time, phase with Night red, day, weather; moon, biome, light; danger red, alert orange, or "All clear" lime), a rule, then the `MACHINES` board. At 50 wide and up, the `VISITORS` column sits at the right (20 wide) with "You're home" (lime) or "Away 12m, locked" (orange) on its last row.
- **Floor wall** (80 wide and 40 high or more, under the big wall's size; an 8x6 at scale 1 is 82x40): `L.glance` in `wall.layout`. Top half: `MACHINES` header (row 1), nine two-row entries (rows 2-19) from the kit's `v:board(..., { tworow = true, slots = 9 })`, page dots on row 20, visitors at the right (rows 2-19, foot on row 20). The board is grouped Storage, Mining, Farming, Building, Labs and pages every `PAGE_S` seconds (`wall.env`, default 3; `ui.PAGE_S`). Row 21 is a rule. Bottom half: clock column (ISLAND chip row 23, `bigNumber` time rows 25-29, phase/day/weather row 31, moon/biome/light row 32) and power column (x 42-81: `POWER USE` header, use % in block digits, `draw of potential FE/t`, a note). `NEEDS YOU` is row 34 with four slots; row 40 is the island line. Nothing moves: fixed rows, empty slots stay blank.
  - **Power slot:** lime under 100%, orange at 100% and up (not an alert). Red digits, a red `THROTTLED` tag and a `Power throttled: ...` first entry in Needs you only while the Operator's `power.limit` (FE/t) is set (#121; `power.asked` and `power.askedFor` add the "Asked for ..." line). No fresh power record (30 s, `POWER_STALE`): dim `--` and `Operator not reporting`.
  - **Needs you** is built from the board rows in `wall.lua` (`needs()`): lost, error, offline, stuck and failed are red, `waiting` is orange; over four, the last slot folds the rest. With none: `Nothing needs you.` and a summary line.
- **Big wall** (120 wide and 60 high or more, e.g. 164x81): three columns: the Island Station (key/value rows, danger line, the nearby list), the board with machines grouped under Storage, Mining, Farming, Building and Labs, and visitors.
- **Board rows** are the kit's `v:board`: stripe, glyph, state word, detail, last heard. A row not heard from for 30 s goes grey with a still `?`; a machine never heard from says `never`. `returning` is cyan. When rows do not fit, the board pages every 8 s and the last row shows `o . .` dots.
- Motion follows `ANIM=` in `wall.env` (full, calm or off; made on first run).

## Adding a machine to the board

Add a row in `board.lua`'s `rows()`: `{ name, state, detail, seen, group }` with `group` one of the five above. A new state word that is not in the kit's `ui.state` can get its colour from `TONE` in `wall.lua`.

## Reactor fuel (Storage's `reactor_fuel` report)

Storage broadcasts `{ type = "reactor_fuel", chests = { { name, label, units, keep, low } }, supply, best }` every 10 s on `tanis-operator`. `operator_link.lua` keeps the last one in `_G.REACTOR_FUEL` and `_G.REACTOR_FUEL_SEEN`, apart from `_G.OPERATOR`, so its alerts work while the Operator is quiet.

- **Board:** the Operator row ends with `fuel chest 48/64, store 412` (units and keep summed over the chests; `store` is the supply left in Storage). Not heard for 60 s it reads `fuel chest ?`. With no report ever heard, the row keeps the old `uranium N` text. `island operator` says the same.
- **Alerts:** `Fuel chest low` (a chest under its `low`; names the chest label and `units/keep`, clears at or above `low`) and `Nothing left to stock` (`supply == 0`). Both are silent while the report is stale. They replace `Fuel supply low`; `URANIUM_LOW` is no longer used (old `island.env` files keep the line, harmlessly).
- **Power use:** the Operator row also says `use 64% (1,920 / 3,000 FE/t)` (draw / potential, from the Operator's `power` record, see `docs/systems/operator.md`), after the buffer. `island operator` adds `Power use ...` the same way. Left out with no detector on the cable, no draw yet, or a record older than 30 s (`POWER_STALE`).
- **Power deficit** alert (`island alerts`, island strip): draw above potential for `DEFICIT_AFTER` seconds (`island.env`, default 30), so a short surge raises nothing. It clears as soon as draw is at or below potential. While the power report is stale (30 s) or the Operator is silent nothing new is raised and an alert already up is left as it is. Not raised when potential is 0 (nothing to compare with). `island operator` adds `Power deficit: ...` while draw is above potential.
- **Power throttled** alert (island strip and chat): while the Operator's breaker is tripped (`power.limit` set). It stays until Reset is pressed on the Operator (the mainframe cannot reset it) and the text says so.
- Code: `operator_fmt.lua` (`fuelText`, `fuelProblems`, `powerText`, `deficit`, `deficitText`, `throttledText`), raised from `island.lua`'s `watch()`.

## Commands

The wall has nothing to type into and the mainframe has no kit screen on its own terminal (that is the shell, where `reset` is typed), so there is no `/command` bar here. Chat (`$island ...`, `$dump`, `$pocket`, `$lock`) is how the mainframe is driven, and it is unchanged: `island status | scan | miner | storage | seagull | operator | alerts | test | help | remove_ring | monitors`. `island seagull` (also `carto`, `cartographer`) says where Seagull is from the Cartographer's heartbeat (`seagull.pos`, `seagull.at`): live (`Seagull-01 mapping at X Y Z (12 s ago), fuel 54,000. Region rx,rz, chunk 40/256.`), or after 30 s `last heard 14 min ago at X Y Z: <state> <msg>`; with no Cartographer heard in 30 s it says so.

## Tests

`tests/scenarios/mainframe_wall.lua` runs the real `mainframe.lua` with stand-in machines at 57x24, 57x38, 36x24, 82x40 and 164x81 (82x40: pages, dots, block digits, Needs you, the power colours and THROTTLED): rows, colours, the visitor column, grey rows after 30 s, paging. `operator_mainframe.lua` checks the Operator rows on the wall, the fuel chest text (report, stale, none) and both fuel alerts.

## Which monitor is the wall

`mainframe.lua` asks `shared/screens.lua` (see `docs/systems/screens.md`) for one slot, `wall`: the biggest monitor touching the computer, as before. With none touching, the mainframe shows numbers on the unowned monitors on the cable and you tap the one you want (or type its number on the computer); the pick is saved in `monitors.cfg`. The mainframe runs the claim daemon so other computers don't offer its wall. A resized or unplugged wall reboots the mainframe. `$island monitors` forgets the pick and reboots, which asks again. More slots (the light strips) can be added to the list at the top of `mainframe.lua`.
