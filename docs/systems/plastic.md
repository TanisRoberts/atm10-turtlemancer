# Plastic factory

Code: `computer/plastic/plastic.lua` (machines, passes, network) and `plastic_screens.lua` (every screen, built only from the UI kit, `docs/systems/ui.md`). Design: `docs/design/plastic.md`. Setup and what the factory does: README, "Plastic factory".

plastic.lua hands the screens a snapshot (`S.snap()`: state, totals, taps, units, furnaces, dock, problems) and the actions (`setPaused`, `scan`, `findMonitor`). The monitor lookup is in plastic.lua (`findMonitor`: the monitor `shared/screens.lua` picked at boot, a touching one or one from the cable; `/monitors` forgets the pick and reboots); the kit's view is given the monitor's peripheral name. The computer's own screen and the monitor show the same dashboard.

## Dashboard

- Header: `PLASTIC FACTORY`, state (running lime and moving, paused orange and still, waiting gold), `~N plastic/h` on regular and wide screens.
- `Made N plastic`, then blocks: one per Latex Processing Unit (latex, water, power bars), TAPS (one cell each: `ok` lime, `full` orange, `DRY` red, 12 columns wide), FURNACES AND DOCK, and the problems as red alert lines.
- It picks the roomiest layout that fits: a blank row between blocks, then none, then the short page (one line per thing, problems first: `Unit 1 L72 W90 P55`, `Taps 7 ok, 1 DRY`, `Furnace: 3 cooking`, `Dock fuel 280`). 57x24 and 51x19 get the full page; 39x13 the short one; 26x20 fits the full page without blank rows.
- Footer: **Pause** / **Run**. Touch on the monitor, click on the computer.

## Typed commands (computer's own screen, slash optional, `shared/slash.lua`)

`/status` (the status lines and problems, a report page), `/list` (what it found on the cable; rescans), `/home` (back to the dashboard), `/pause` (`/stop`), `/resume` (`/go`, `/run`), `/help`. The Back button or `/home` leaves a report page.

## Tests

`tests/scenarios/plastic_screens.lua` with `tests/demo/plastic_demo.lua` (a made-up factory: the sim has no fluid machines): the dashboard at 57x24, 51x19, 39x13 and 26x20, Pause/Run by touch, the commands, an empty cable, no colour, and the real program booting on an empty cable.
