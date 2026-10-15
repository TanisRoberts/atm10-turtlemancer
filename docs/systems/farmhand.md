# Farmhand

Control screen for every farm turtle (Partridge, Woodpecker). `computer/farmhand/`: `farmhand.lua` (registry, orders, radio), `farmhand_screens.lua` (what is drawn), `farmhand_map.lua` (farm maps). The screens are built only from the UI kit (`docs/systems/ui.md`); nothing here writes to a terminal.

## Data and radio (`farmhand.lua`)

- Protocol `tanis-farm`. Turtles broadcast a `status` message every ~3 s (farmbot.lua `B.statusMsg`); the Farmhand keeps the latest in `live[id]` with the time it was heard, and remembers every turtle it has seen in `farmhand.cfg` (`cfg.turtles[id]` = label, role, pending order, pending settings, pending reboot). A turtle silent for 20 s greys out (`STALE`).
- Orders (`rounds`, `stop`, `go`, `survey`, `found`), setting changes and reboots carry a time-stamp `seq`/`setSeq`/`reboot`. The Farmhand repeats them every 3 s until the turtle's status echoes the same number. A setting shows gold on the screen until then. An unconfirmed reboot is dropped after 10 minutes.
- Maps: for the turtles on show (overview tiles, or the open page) it sends `mapreq` when it has no map or the status carries a different `mapStamp`, at most every 5 s per turtle. The map message is farmbot.lua `B.mapMsg`.
- It broadcasts a `farmhand` summary (turtle count, working, problems, a note) every 5 s for the mainframe board.
- `ui.run` is the event loop (`tick = 1`); the net loop only stores what arrives, so a status, a tap or the clock all redraw. A monitor that is attached, removed or resized is picked up from the `peripheral`/`monitor_resize` events.

## Screens (`farmhand_screens.lua`)

Each view (the computer's own screen and a monitor, which may differ in size) keeps its own page and tab.

- **Overview:** `v:tiles` with `grow = true`: a tile per turtle (state word and stripe, what it is doing, fuel bar, next round, last heard, then its farm drawn small with an arrow where it is, and its last round). Buttons below: Rounds all (primary), Pause all, Reboot all. The pager and the mouse wheel page through more turtles.
- **One turtle** (tap its tile; Back returns): on screens 44+ wide the side column shows state, message, fuel, next round, seeds or saplings and the order buttons (Rounds now, Pause or Go, Re-map, Found when lost, Reboot), and the footer tabs are Map / Info / Haul / Settings. Narrower screens get Map / Do / Info / Set, with the order buttons on Do.
  - Map: `v:map` in an area above the key, with `bounds` and `wide` so a farm that fits is centred with 2-character cells and no pan buttons; a bigger farm follows the turtle, with pan buttons, Follow, arrows, Home or `f`, and the wheel. A tap on a block says what it is (with world coordinates when the map is pinned to north).
  - Info: position, GPS state, last round, and Forget this turtle (tap twice) once it has been silent for 2 minutes.
  - Haul: last haul and the totals. Settings: one stepper per setting (`SETTINGS` in `farmhand.lua`), sent live and written into the turtle's own `.env`.

## Maps (`farmhand_map.lua`)

`M.look` turns a map character and its state (`h` harvested last round, `g` growing, `e` empty) into a glyph and two kit roles; `M.getter` is the `get` the kit's map wants; `M.key` and `M.drawKey` lay out the key; `M.thumb` draws the small copy on a tile (1 or 2 characters per cell when it fits, otherwise shrunk, keeping the most important cell of each block).

## Tests

`tests/scenarios/farmhand_screens.lua` runs the real Farmhand with stand-in turtles (`tests/demo/farm_stub.lua`) at 57x24 (monitor) and 51x19, 39x13 and 26x20: tiles and colours, orders to one and to all, settings and the gold pending value, Info/Haul, Forget, Found, a big farm with pan and Follow, separate pages per view, no modem, a reboot, no colour.
