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

- **Normal wall** (57x24, 57x38, 36x24): strip on rows 1-3 (island chip, time, phase with Night red, day, weather; moon, biome, light; danger red, alert orange, or "All clear" lime), a rule, then the `MACHINES` board. At 50 wide and up, the `VISITORS` column sits at the right (20 wide) with "You're home" (lime) or "Away 12m, locked" (orange) on its last row.
- **Big wall** (120 wide and 60 high or more, e.g. 164x81): three columns: the Island Station (key/value rows, danger line, the nearby list), the board with machines grouped under Storage, Mining, Farming, Building and Labs, and visitors.
- **Board rows** are the kit's `v:board`: stripe, glyph, state word, detail, last heard. A row not heard from for 30 s goes grey with a still `?`; a machine never heard from says `never`. `returning` is cyan. When rows do not fit, the board pages every 8 s and the last row shows `o . .` dots.
- Motion follows `ANIM=` in `wall.env` (full, calm or off; made on first run).

## Adding a machine to the board

Add a row in `board.lua`'s `rows()`: `{ name, state, detail, seen, group }` with `group` one of the five above. A new state word that is not in the kit's `ui.state` can get its colour from `TONE` in `wall.lua`.

## Commands

The wall has nothing to type into and the mainframe has no kit screen on its own terminal (that is the shell, where `reset` is typed), so there is no `/command` bar here. Chat (`$island ...`, `$dump`, `$pocket`, `$lock`) is how the mainframe is driven, and it is unchanged: `island status | scan | miner | storage | operator | alerts | test | help | remove_ring | monitors`.

## Tests

`tests/scenarios/mainframe_wall.lua` runs the real `mainframe.lua` with stand-in machines at 57x24, 57x38, 36x24 and 164x81: rows, colours, the visitor column, grey rows after 30 s, paging. `operator_mainframe.lua` checks the Operator rows on the wall.

## Which monitor is the wall

`mainframe.lua` asks `shared/screens.lua` (see `docs/systems/screens.md`) for one slot, `wall`: the biggest monitor touching the computer, as before. With none touching, the mainframe shows numbers on the unowned monitors on the cable and you tap the one you want (or type its number on the computer); the pick is saved in `monitors.cfg`. The mainframe runs the claim daemon so other computers don't offer its wall. A resized or unplugged wall reboots the mainframe. `$island monitors` forgets the pick and reboots, which asks again. More slots (the light strips) can be added to the list at the top of `mainframe.lua`.
