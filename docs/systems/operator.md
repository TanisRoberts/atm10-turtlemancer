# Operator

Runs the Extreme Reactors 2 power plant headless. `computer/operator/`: `operator.lua` (loop, status, text screen), `opplant.lua` (what is on the cable, units, ports), `opdrivers.lua` (reactor drivers), `oppolicy.lua` (who runs), `opneeds.lua` (needs / has / missing). `shared/envfile.lua` reads `operator.env`.

## Plant model (`opplant.lua`)

- Scans the cable for units: reactors (`BigReactors-Reactor`), turbines (type contains "turbine") and energy storage (`energy_storage`), plus access ports (inventory whose type contains "access"/"port") and barrels. A unit's id is its peripheral name; `operator.cfg` remembers it with a label (`Reactor-1`). Numbers are per kind, handed out once in cable-name order and never reused.
- `operator.cfg` (a Lua table, edit by hand, reloaded when it changes) holds per unit: `mode` (auto|on|off), `enabled`, `onBelow`/`offAbove` (percent, beat the `.env` defaults), `input`, `output`, `waste` (peripheral names). Plant-wide `waste` too.
- Ports: from the config. With exactly one reactor and one or two free ports, the Operator works them out by contents (fuel in one = input, cyanite in one = output, the other of a pair is the remaining one) and writes them to the config. With several reactors, or empty ports it can't tell apart, it says "unknown"; set `input=`/`output=`. Never guesses. Waste barrel: the only barrel on the cable, else `waste=`.

## Drivers, policy (`opdrivers.lua`, `oppolicy.lua`)

- Driver: `status()`, `setActive()`, `setOutput()` (rod insertion, for the later rod issue), `rods()`. Every call is guarded (missing method or error gives nil). `passive` is FE straight from the power tap. A reactor answering `isActivelyCooled() == true` gets `active`: it reads the same plus coolant/hot fluid; its turbine/steam control is a later driver in the same file.
- Policy: `follow` (day one) switches each reactor on below `ON_BELOW`% and off above `OFF_ABOVE`% of its own buffer, nothing in between. `disabled` and manual `on`/`off` win. Fuel is never a reason to switch off. A new policy (e.g. stagger) is a new function in `oppolicy.lua`, chosen by `POLICY=` in `operator.env`; it sees the plant totals and every unit.

## Waste and fuel

Cyanite in the output port is moved to the barrel each pass, a stack per call; if the barrel can't take it the unit says "waste not clearing" (nothing is voided). Fuel left = reactor `getFuelAmount/Max`; uranium in supply = ingots (blocks count 9) in the input port.

## Needs / has / missing (`opneeds.lua`)

A list of small checks, each giving `ok | missing | unknown` and a one-line reason: computer port, control rods, temperatures, fuel input, fuel supply, waste output, waste destination, power output, coolant, turbine. "Unknown" is used when the Operator can't tell (a passive reactor's power tap is not on the cable, so that one is always unknown). Recomputed on boot, every `SLOW` seconds, when the cable changes, and when waste starts or stops clearing. The list is in the unit's status record.

## Status to the mainframe

Protocol `tanis-operator`, a `{type="operator", units={...}, plant={...}}` broadcast every `STATUS_EVERY` seconds, which is also the heartbeat. `computer/mainframe/operator_link.lua` keeps the last one in `_G.OPERATOR` / `_G.OPERATOR_SEEN`; the board row, alerts and chat are issue #36. The text screen shows the same on the computer and any monitor.

## Log

`operator.log` records what was found at boot (reactor, ports, barrel names), every on/off with the buffer, "waste not clearing", and what a full-buffer reactor does (burn and FE/t), so the real passive behaviour can be confirmed.

## Tests

`tests/scenarios/operator_core.lua` with the `BigReactors-Reactor` mock in `tests/sim/reactor.lua`: hysteresis, ports worked out, waste to the barrel, a full barrel, two reactors with their own thresholds and a manual override, needs lists for different reactors, a silent reactor.
