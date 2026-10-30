# Screens (`shared/screens.lua`)

Picks the monitor a controller draws on. Issue #97 is the project; this is the module only.

```lua
local screens = require("screens")
local s = screens.new({ slots = { { id = "wall", label = "the main wall", required = false, scale = 0.5 } } })
local mon, name = s:get("wall")     -- the wrapped monitor and its peripheral name, or nil
s:daemon()                          -- in parallel: answers other computers (or call s:handle(ev...) from your own loop)
s:repick("wall")                    -- forget the saved pick; the next get asks again
```

Slots are asked in the order declared. `get` can block (a 1 s claims query, then the picker), so call it before the main loop.

## Which monitor

1. Slot 1 uses the biggest monitor touching the computer. No prompt, nothing saved.
2. `monitors.cfg` (`slot=peripheral_name`, one per line, written by the module) if that monitor is still on the cable and no other computer owns it.
3. The picker over the monitors on the cable that nobody owns. No candidates: an optional slot returns nil without a prompt; a required slot waits for a monitor.

Picker: each candidate shows its number in 3x5 block digits (scaled to fit, down to 1x1) and `Tap to pick <label>`. The computer lists `1 monitor_12 (57x24)` and takes a typed number plus Enter (Enter alone skips an optional slot; the skip is saved as `slot=-`). After the pick the chosen monitor is cleared and every other candidate is blanked. Re-pick: `s:repick(id)`, or delete `monitors.cfg` and reboot.

## Claims between computers

Peer to peer on the wired modems, channel **4747** (`screens.CHANNEL`), no rednet and no mainframe. Peripheral names are the same on one cable, so claims are by name.

| Message | Meaning |
|---|---|
| `{op="claims?"}` | who owns what? (sent before numbering, answers collected for 1 s) |
| `{op="claims", owned={...}, numbering={...}}` | answer; also sent when a pick is made or a monitor is lost |
| `{op="numbering", names={...}}` | I am showing numbers on these (repeated every second while picking) |

Every message carries `from` (the computer id). A monitor a peer owns or is numbering is not a candidate. If two computers number the same monitor at once, the lower id keeps it and the other drops it. Known gap: a computer that is switched off does not answer, so its monitor can show up as a candidate. A controller has to run `s:daemon()` or `s:handle()`, or it stops answering after boot.

## Events

`screens_changed <slotId>` is queued after a `monitor_resize` (the module has already re-measured: `s.size[id] = {w=, h=}`) or a `peripheral_detach` of an owned monitor (the slot is empty; the next `get` falls back to rules 1-3). Both need `s:handle` / `s:daemon` to see the raw events.

## Mid-run lookup

`s:current(id)` never asks: it returns the slot's monitor (or, for slot 1, a touching monitor that appeared since). Controllers that re-sync on `peripheral` events use it after one `get` at boot.

## Who uses it

Mainframe (`$island monitors`), neural, plastic, cartographer, architect (`/monitors`, `monitors`) and art (key `M`), plus the Foreman engine (`shared/fm_draw.lua` `findMonitor`: Overworld, MD and Nether Foremen, `/monitors`) and the Farmhand (`/monitors`). All use one optional slot `wall` (art: required) and reboot on a re-pick. Tests: `wired_monitors_5.lua`, `wired_monitors_4.lua`.

## Tests

`tests/scenarios/screens_basic.lua`, `screens_peers.lua`, stand-in controller `tests/demo/screens_stub.lua`. The sim has monitors on a cable (`net:monitor(name, w, h)`, touch goes to every computer on that cable) and `modem.open/transmit` between computers on one cable.
