# Operator

Runs the Extreme Reactors 2 power plant headless. `computer/operator/`: `operator.lua` (loop, status, text screen), `opplant.lua` (what is on the cable, units, ports), `opdrivers.lua` (reactor drivers), `oppolicy.lua` (who runs), `opneeds.lua` (needs / has / missing), `oprods.lua` (rod stepping and manual holds), `opctl.lua` (what a person can change), `opscreen.lua`, `opwall.lua` and `opdraw.lua` (the screens). `shared/envfile.lua` reads `operator.env`.

## Plant model (`opplant.lua`)

- Scans the cable for units: reactors (`BigReactors-Reactor`), turbines (type contains "turbine") and energy storage (`energy_storage`), plus the reactor's access ports (type name contains "reactor" and "access" or "port"). The cable is shared with Storage and the reactor, so everything else (chests, machines) is ignored; the first-boot log lists every peripheral name and type so the port pairing can be confirmed. Ports are not assumed to be inventories. A unit's id is its peripheral name; `operator.cfg` remembers it with a label (`Reactor-1`). Numbers are per kind, handed out once in cable-name order and never reused.
- `operator.cfg` (a Lua table, reloaded when it changes; the screen writes it too) holds per unit: `mode` (auto|on|off), `enabled`, `onBelow`/`offAbove` (percent, beat the `.env` defaults), `input`, `output` (peripheral names of the inlet and outlet port), `levelMin`, `levelMax`, `holdMin`, `manage` (false = "Run it: NO", leave the reactor alone). A `plant` table holds the same settings for every reactor (set from the Set tab with "All reactors"); a unit's own value beats it, and it beats `operator.env`.
- Ports: from the config. With exactly one reactor and one or two free ports, the Operator works them out by contents (fuel in one = input, cyanite in one = output, the other of a pair is the remaining one) and writes them to the config. With several reactors, or empty ports it can't tell apart, it says "unknown"; set `input=`/`output=`. Never guesses.

## Drivers, policy (`opdrivers.lua`, `oppolicy.lua`)

- Driver: `status()` (also the rod count, each rod's level and the average `level`), `setActive()`, `setOutput(insertion)`, `rods()`. Every call is guarded (missing method or error gives nil). `passive` is FE straight from the power tap. A reactor answering `isActivelyCooled() == true` gets `active`: it reads the same plus coolant/hot fluid; its turbine/steam control is a later driver in the same file.
- Policy: `follow` (day one) switches each reactor on below `ON_BELOW`% and off above `OFF_ABOVE`% of its own buffer, nothing in between. `disabled` and manual `on`/`off` win. Fuel is never a reason to switch off. A new policy (e.g. stagger) is a new function in `oppolicy.lua`, chosen by `POLICY=` in `operator.env`; it sees the plant totals and every unit.

## Control rods (`oprods.lua`)

- **Level** = power setting in percent = `100 - rod insertion`. All rods move together. The policy returns a target `level` per running reactor (full power at the ON threshold and below, `LEVEL_MIN` at the OFF threshold, a straight line between); `oprods.step` moves toward it and the driver applies it.
- Auto steps at most `ROD_STEP` percent every `ROD_EVERY` seconds and leaves the rods alone within `LEVEL_BAND` of the target (unless the target is a limit). At steady load the level drifts a few percent at most.
- Off: the rods keep their level, and switching on does not reset them.
- Manual: `level` in a unit's `operator.cfg` entry (or `MANUAL_LEVEL` in `operator.env`) holds a level until removed. A hold set by command lasts `HOLD_MIN` minutes (default 10), forces the reactor ON, and then returns to Auto (logged). Limits per unit: `levelMin`, `levelMax`.
- `RODS=off` leaves the rods alone. A reactor without rod methods is controlled on/off only.
- Command (protocol `tanis-operator`): `{ type="operator_cmd", unit=<label or id; none = every reactor>, mode="auto"|"on"|"off", level=1..100 }`. A mode is saved in `operator.cfg`; a level is a hold.
- Status per unit adds `level`, `rodCount`, `rodLevels`, `levelWhy` ("buffer falling" / "buffer filling" / "manual"), `levelAt` and `holdLeft` (seconds).

## Setup wizard (`opwizard.lua`)

A reactor with no saved setup (`setup` not `true` in its `operator.cfg` entry) is **awaiting setup**: the Operator reads it but does not switch it or move its rods, the overview shows a "New Reactor Awaiting Setup" card, and the mainframe board says `awaiting setup` without an alert. What the Operator thinks the ports are (from what they hold) is only a suggestion in the wizard and is never saved. A reactor that already has both ports saved is set up automatically (`setup = true`). `SETUP_WIZARD=no` in `operator.env` skips all of this: ports are worked out and saved as before.

Four pages (style A, design in `docs/design/operator.md`): found, inlet, outlet, check and name. The port pages list every device on the cable with what it holds; the likely one is marked `suggested`. `Find it` watches every device that can list items while you drop one item into the right port by hand (the Operator only reads), and offers the one whose count went up. Finish saves `input`, `output`, `label` (if renamed) and `setup = true`. `Run setup again` on the Set tab (tap twice) sets `setup = false` and keeps the ports.

## Screens (`opscreen.lua`, `opwall.lua`, UI kit)

Design: `docs/design/operator.md`. The computer's screen and every monitor touching a side are separate views, each with its own page. Taps and keys work on all of them.

- **Overview**: 50 wide or more has the Power Grid column (totals over every reactor, net FE/t from the last minute) and a 5-row tile per reactor (stripe: orange when something is missing, lime running, light blue idle, grey not heard for 30 s). 36 to 49 wide has a totals strip and 2-row tiles; narrower, the 26-wide layout. A tap opens the reactor on its Power tab. One reactor on a screen under 50 wide opens straight on Power.
- **Power**: rods (grey inserted, lime withdrawn, light blue when off), the level stepper (5% a tap, stops at Lowest and Highest with a notice), the Run switch AUTO / ON / OFF, buffer bar with the ON and OFF marks, fuel and temperatures. Stepping the level in Auto forces ON and holds it for `HOLD_MIN` minutes (`Manual Hold:` with the countdown at the right edge); AUTO returns at once. In Auto the page shows `Auto set:` with how long ago, at the right, and why below.
- **Needs**: the checklist (`+` ok, `!` missing, `?` unknown, `-` not needed or ignored). A row that is not ok says `1 problem` / `1 warning` at the right (a 26-wide screen puts the reason on a second line). A tap opens that need's page: the reason in full, for the port needs a **Manually assign** button and **Clear**, and **Ignore this** / **Stop ignoring** for any of them. Pages when it does not fit.
- **Assign**: a list of every device on the cable (ER2 access ports first, taken ones marked with the reactor that holds them) with a search field on the computer's own screen; tap a device twice to make it the reactor's inlet or outlet. It is saved as `input` / `output` in `operator.cfg` and takes the port from another reactor that held it. **Clear** goes back to auto-detect. An ignored need is `ignore = { power = true }` in the unit's `operator.cfg` entry and stops counting as a warning.
- **Set**: ON below, OFF above (at least 10 points apart), Lowest, Highest, Back to Auto after, Run it, Reset to defaults (tap twice). "Applies to" picks this reactor (an override, shown `local`) or all reactors (the plant-wide value). Every change is saved to `operator.cfg`.
- **Wall** (120 wide and 50 tall or more): Power Grid, up to three whole reactor panels, the plant buffer chart (last 30 minutes) and the recent events. More than three reactors become tiles. Chart and events come from `plant.hist` (one sample every 15 s, 120 of them) and `plant.events` (the last 8) in the status record.
- A command from the mainframe or the screen acts at once, not at the next pass.

## Items: the Operator never moves any

Storage fills the inlet port and drains the outlet port (issue #37). The Operator reads: uranium in the inlet (ingots, blocks count 9) and the outlet. "Waste not clearing" = every outlet slot taken, or cyanite in the outlet that hasn't dropped for `STUCK_AFTER` seconds (default 120). Fuel left = reactor `getFuelAmount/Max`. Uranium in supply comes from Storage: a `{type="uranium", total=<ingots>}` broadcast on protocol `tanis-operator`; the plant totals and the mainframe alert use it. It is not a Needs check (the Needs tab used to have "Fuel supply" and "Power output"; both were removed because nothing on them could be fixed).

## Needs / has / missing (`opneeds.lua`)

A list of small checks, each giving `ok | missing | unknown | na` and a one-line reason: computer port, inlet port, fuel in reactor (inlet or reactor), outlet port, waste draining, control rods, fuel and casing temperature, coolant and turbine. "Unknown" is used when the Operator can't tell. Recomputed on boot, every `SLOW` seconds, when the cable changes, and when waste starts or stops clearing. The list is in the unit's status record.

## Status to the mainframe

Protocol `tanis-operator`, a `{type="operator", units={...}, plant={...}}` broadcast every `STATUS_EVERY` seconds, which is also the heartbeat. `computer/mainframe/operator_link.lua` keeps the last one in `_G.OPERATOR` / `_G.OPERATOR_SEEN`. `operator_fmt.lua` (mainframe) turns it into board rows, chat lines and alert text.

- **Board**: one `Operator` row: running / idle / waiting, `ON|OFF`, FE/t, buffer %, uranium (Storage's report, else what sits in the inlets). With more than one reactor the row says `N of M on` and a row per reactor follows.
- **Alerts** (same mechanism as the rest, `island alerts` to subscribe): `Reactor silent` (no heartbeat for `OPERATOR_SILENT_AFTER`, 60 s), `Fuel supply low` (Storage reports fewer than `URANIUM_LOW`, 16 ingots), `waste not clearing` and `not answering` / `not on the cable`, each naming the reactor. Both numbers are in `island.env` on the mainframe.
- **Chat**: `island operator [reactor] on|off|auto|status` (reactor as `reactor-1`, `1` or `reactor 1`; none = every reactor; `status` is the default). `status` replies with one line. An order goes out as `{type="operator_cmd", unit, mode}` three times, one a second apart, and the Operator saves the mode in `operator.cfg`. The existing chat commands have no player list, and neither does this one.

## Log

`operator.log` records what was found at boot (every peripheral name and type on the cable, then the reactor and its ports), every on/off with the buffer, "waste not clearing", and what a full-buffer reactor does (burn and FE/t), so the real passive behaviour can be confirmed.

## Tests

`tests/scenarios/operator_mainframe.lua`: island.lua, board.lua and operator_link.lua on a simulated mainframe: the board row (one and two reactors), alerts (fuel low, waste, silent and back), chat orders and status.
`tests/scenarios/operator_screen.lua`: the overview at 51x19, 39x13, 26x20 and 164x81, taps for tile / level / hold / ON / OFF / AUTO, limits, Needs, Set (one reactor, all, reset), the narrow single-reactor start, and the wall.
`tests/scenarios/operator_rods.lua`: steps out and in, steady load, off keeps the level, manual level and limits, a hold that expires, no rod methods.
`tests/scenarios/operator_core.lua` with the `BigReactors-Reactor` mock in `tests/sim/reactor.lua`: hysteresis, ports worked out with Storage draining the outlet, an outlet that doesn't empty, a full outlet, two reactors with their own thresholds and a manual override, needs lists for different reactors, a silent reactor.
