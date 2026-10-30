# Nether Foreman

Firecrest control plus the Nether dock barrels (`computer/nether/`). `nether.lua` is the profile (title, protocol `tanis-nether`, Nether Y range 6..120, first-run presets, keep and junk lists, `remote = "dimension"`, `screens`). The work is the Foreman engine in `shared/fm*.lua` (`docs/systems/miner.md`: registry, orders, radio, the barrels, the link up to the Overworld Foreman). Design: `docs/design/nether.md`.

`nether_screens.lua` is everything it shows and takes typed, built only from the UI kit (`docs/systems/ui.md`). It is the Overworld Foreman's screens (`computer/foreman/foreman_screens.lua`, `docs/systems/foreman.md`) plus what is the Nether's own: `nether_screens` fills `F.ext` (hooks the Foreman screens read: header, status line, buttons, extra status rows, extra pages), calls `foreman_screens`, then adds the Rules page and its commands. The monitor lookup is the engine's `findMonitor`; each view gets the monitor's peripheral name. The MD Foreman still uses the engine's own drawing.

## Screens

Each view (the computer's own screen and a monitor, which may differ in size) keeps its own page.

- **Overview:** header `NETHER FOREMAN`, the Firecrest count, `out 24/27 free` (the output barrel's free slots) and `ok` or `output full`. Under it one line about the barrels, from the engine: orange `tap Barrels (or /assign) to give them jobs`, red when a pass is stuck or the output cannot be emptied, orange `Output full: haul waits in Overflow`, otherwise grey `Stock 64 buckets, 12 lava, fuel 2,400.  Sent home 12k`. A tile per Firecrest (state, what it is doing, fuel, cargo and Y, last heard). Buttons: Presets, Rules, Barrels (not on a short screen), Reboot all (tap twice), Retired (n) on 56+ wide. There is no Dock all.
- **A Firecrest (tap its tile):** the Foreman's page: status on the left (message, alerts, fuel and cargo bars, layer, chunk, range, position, home, gear) and Layers on the right (presets, Min Y, Max Y, rings, START, STOP + DOCK, Reboot, Re-dock, Retire). On the left, three rows of its own: **Lava** (`drinks under 25%`, or `drinking to 75%` in orange), **Bucket** (`empty, ready`, `full of lava`, or a red `NONE`) and **Barrel** (the dock barrel it was given, and what is in it). Min Y and Max Y stop at 6 and 120.
- **Presets** and **Edit preset:** as on the Foreman; a new preset starts at Y 12..17.
- **Rules:** `Lava` (`Drink under` and `until` steppers, 5% steps; the two never cross), `Keep in the Nether` (a stepper per item: the keep count, and what Stock holds now, orange while it is below), and what Firecrest throws away (the junk list, three lines on a tall screen, one on a medium one, none on a short one). `+ Keep` and `+ Junk` put `/keep ` or `/junk ` in the command bar (a monitor says to type them on the computer). A keep count of 0 sends the item home and takes it off the list. The list pages with the footer pager.
- **Barrels:** the button (and `/assign`) opens `shared/assignui.lua` on the computer's own screen, the same screen as Storage's. It blocks the kit while it is open; the kit gets its palette back when it closes. On a monitor the button only says to type `/assign` on the computer. Not moved yet (#21).

## Typed commands (computer only)

Through `shared/slash.lua`, with or without the slash, listed in the kit's command bar when `/` is typed. All of the Foreman's (`/presets /new /edit /delete /reboot /redock /retired /home /help`, see `foreman.md`) and:

| Command | What |
|---|---|
| `/rules` (`/keeps`) | the Rules page |
| `/assign` (`/barrels /dock`) | the barrel jobs screen |
| `/keep <item> [count]` | keep this many in the Nether (default 64; 0 sends it home) |
| `/junk <item>` | Firecrest throws it away underground |
| `/unjunk <item>` | Firecrest brings it home again |

## Barrels

Unchanged by the screens: `shared/fm_barrels.lua` empties each Firecrest's dock barrel, keeps what the Rules say in Stock and sends the rest home through the Output (barrel > hopper > ender chest), and serves a Firecrest's `dock_req` with lava and a bucket from Stock. See `docs/systems/miner.md`.

## Tests

`tests/scenarios/nether_screens.lua` runs the real Nether Foreman with a stand-in Firecrest at 57x24 (monitor), 51x19, 39x13 and 26x20: the overview and its buttons, a Firecrest's page, the Min Y floor, START with the lava rule, Rules (steppers, keep, have, junk, `+ Keep` on the computer and on a monitor), Barrels and coming back from it, every command, a new preset's range, and no Firecrest yet. `tests/scenarios/nether_basic.lua` covers the barrels, the orders, retiring and the preset editor through the same screens.
