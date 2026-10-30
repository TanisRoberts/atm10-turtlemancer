# Neural lab

Code: `computer/neural/neural.lua` (columns, power, passes, network) and `neural_screens.lua` (every screen, built only from the UI kit, `docs/systems/ui.md`). Design: `docs/design/neural.md`. What the lab does: README, "Neural lab", and the header of neural.lua.

neural.lua hands the screens a snapshot (`S.snap()`: columns `L`, per-column state `P`, `cfg`, problems, power, note) and the actions (`setPaused`, `setForce`, `check`, `setRule`, `scan`, `findMonitor`). The monitor lookup is in neural.lua (`findMonitor`: a monitor touching the computer); the kit's view is given the monitor's peripheral name. The computer's own screen and the monitor each keep their own page.

## Overview

- Header: `NEURAL LAB`, state (running / paused / waiting), `power N%  matrices N` (`sim #2 12%` instead of the power figure while one chamber is starving).
- One tile per column: `#n Mob`, state word with glyph, item and stock/target, accuracy (`runs N` on a training column), **CHECK**. Tap a tile to open the column. 5-row tiles on tall screens; 2-row (name and state) on short ones, with CHECK on the column page. The pager is in the footer.
- State words: `running` (lime, moving), `training` (purple, moving), `learning` / `checking` (cyan), the waits `at target` / `off` / `paused` / `wait power` / `train wait` (orange, still `o`), and the ones that need a person (`no fab`, `no model`, `no matrices`, `no counts`, `dock full`, `pick a drop`, `no power`, `fab no power`, `trained?`, `stuck`, `no dock`; red `!`). The lamps on the wall are unchanged.
- Under the tiles, when there is room: the most useful problem as an alert line and the lab's note.
- Footer: **Pause** / **Run**, **Check all** (every column that can be checked); the buttons shorten to fit beside the pager.

## Column page

`#n MOB`, state, `column n`. Fab output and how to change it (in the fab's own screen), the stock bar with `stock / target`, a **Target** stepper (steps of 16, 64 from 256; it edits `neural.txt`; 0 = off), the **Mode** switch AUTO / ON / OFF and **CHECK**, run stats, the network names (chamber, fab, lamp), and this column's problems as red lines at the bottom. A column on Training explains what to do next (switch the chamber back to Inference when it is Self Aware, matrices kept spare) and needs no fab. Back returns to the overview.

## Typed commands (computer's own screen, slash optional, `shared/slash.lua`)

`/status`, `/list` (rescans), `/pairs` (which fab and lamp go with each chamber) show a report page; `/column <n>` opens a column page; `/home` goes back; `/check <n>`; `/on <n>`, `/off <n>`, `/auto <n>`; `/target <n> <count>` (0 = off); `/pause` (`/stop`); `/resume` (`/go`, `/run`); `/help`. `/target` and `/column` are new; the rest are the old terminal words.

## Tests

`tests/scenarios/neural_screens.lua` with `tests/demo/neural_demo.lua` (a made-up lab: the sim has no Hostile Neural Networks machines): overview and column page at 57x24, 51x19, 39x13 and 26x20, taps on tiles / CHECK / Check all / Pause / the mode switch / the target stepper, a training column, the commands, an empty lab, no colour, and the real program booting on an empty cable.
