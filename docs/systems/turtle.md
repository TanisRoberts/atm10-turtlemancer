# Turtle core: fuel, dock, GPS and chunk loading for every turtle

`shared/turtlecore.lua` is the one place a turtle gets its fuel table, refuelling, dock handling, GPS and chunk loading. A change here reaches every turtle on its next boot. The core never digs.

Files (flat on the device, loaded with `dofile`, each part is `return function(core) ... end`):
`turtlecore.lua` (entry), `turtlecore_gps.lua`, `turtlecore_fuel.lua`, `turtlecore_dock.lua`, `turtlecore_chunk.lua`.

```lua
local core = dofile("turtlecore.lua")
```

Farm turtles (Woodpecker, Partridge) get it through `shared/farmbot.lua` as `B.core`.

## Fuel: `core.fuel`

One table, best first. Only these are ever burned: never logs, planks or saplings.

| # | Item | Fuel |
|---|---|---|
| 1 | `minecraft:coal_block` | 800 (stacks to 64) |
| 2 | `minecraft:lava_bucket` | 1000 (stack of 1) |
| 3 | `minecraft:blaze_rod` | 120 |
| 4 | `mekanism:bio_fuel` | 5 |
| 5 | `minecraft:coal` | 80 |
| 6 | `minecraft:charcoal` | 80 |
| 7 | `minecraft:stick` | 5 |

- `fuel.order`, `fuel.value[name]`, `fuel.rank[name]`, `fuel.isFuel(name)`.
- `fuel.level()` / `fuel.limit()`: numbers (`math.huge` when unlimited).
- `fuel.needFuel(low)`: true when the level is under `low`.
- `fuel.burnSlot(slot, target)`: burns just enough of that slot to reach `target`. Returns items burned.
- `fuel.refuelFromInventory(target)`: burns what he carries, best fuel first. Returns fuel gained. An empty bucket stays in his slots until the next dock visit.
- `fuel.refuelFromDock(dir, target, want)`: takes fuel from the dock up to `target`, plus `want(name, have)` more of anything he restocks from it (saplings). Puts empty buckets back. Returns `{ [name] = taken }`.
- `fuel.returnEmpties(drop)`: every `minecraft:bucket` he carries goes into the dock.

`suck()` always hands over the barrel's first stack, so the order of the dock's slots decides which fuel he takes first. Priority applies fully to what he carries. Storage can put the best fuel in the lowest slot (#41).

Don't refuel to full out of habit: fuel is time. Each role keeps its own thresholds in its `.env` file (`FUEL_TARGET`: top up to, `FUEL_LOW`: won't start a round below).

## Dock: `core.dock`

One dock per turtle: the barrel he returns to for fuel and for unloading.

- `dock.ops(dir)`: `drop, suck` for the dock's side (`"up"`, `"down"`, anything else = in front; the role turns to face it first).
- `dock.list(dir)`: what is in the barrel, or nil if he can't tell. `dock.holding(name, except)`: how many he carries.
- `dock.set({x, y, z}, dir)` / `dock.known`: the dock's world position.
- `dock.setHooks({ go = fn, back = fn })`: the role says how to get to the dock and back.
- `dock.visit(fn)`: `go`, then `fn`, then `back` (`back` runs even if `fn` fails).
- `dock.report(o)`: tells Storage where the dock is (below). Returns the ack, or nil plus why. `o.timeout` (2 s per try), `o.tries` (2), `o.role`.
- `dock.maybeReport(o)`: `report` at most every `o.every` seconds (600); a try nobody answered is repeated after a third of that. Farmbot calls it from its main loop.

### Message: dock report

On protocol `tanis-base` (the one Storage listens on), by `rednet.broadcast`:

```lua
{ type = "dock_report", id = <computer id>, label = "Woodpecker-01", role = "lumberjack",
  x = 100, y = 64, z = 200,        -- the dock barrel's world position (GPS)
  dir = 0 | "up" | "down" }        -- the side of the turtle it is on (0..3 compass-number, as the role keeps it)
```

Storage answers the sender with:

```lua
{ type = "dock_ack", id = <that computer id>, assigned = "<barrel name>" | nil }
-- assigned: the barrel /assign has as that turtle's dock at this position; nil lists it as "unassigned dock"
```

The turtle works fine without an answer (Storage not updated yet, out of range). `/assign` is unchanged: Tanis can still assign docks by hand. Storage's side of this message is #41.

## GPS: `core.gps`

`gps.locate(timeout, retries)` returns `ok, x, y, z, stale`:

- A real fix: `true, x, y, z, false`. It is remembered in `gps.last`.
- No answer after `retries` more tries (half a second apart): the last fix with `stale = true`, or `false` if there never was one.

Callers that need to know where he is NOW (finding his heading, checking he wasn't carried off) must treat `stale` as no fix. Farmbot's `B.locate` does this: it returns x, y, z of a fresh fix only.

## Chunk loading: `core.chunk`

An Advanced Peripherals chunk controller in his bag keeps the chunk he's in loaded. He swaps it onto his modem's side for a moment (at least a tick), then swaps the modem back: the chunk stays loaded until AP's `chunkLoadValidTime` (600 s), and loading a new chunk releases the old one, so he holds one chunk at a time. Worn all the time (no swap), it reloads by itself.

- `chunk.have()`: a controller in his bag or worn.
- `chunk.ensure(key, force)`: load the chunk `key` names (the role's `"cx,cz"`). Swaps only in a new chunk, `chunk.every` seconds (45, well under 600) after the last swap, or when `force`. True when it loaded it now. `chunk.swaps` counts the swaps.
- `chunk.note`: why it couldn't, for his screen: `"Chunk controller missing"` or `"No modem to swap with"`. `nil` after a good swap.
- `chunk.restore(hint)`: at boot, puts the modem back on if a swap was cut short (the side is kept in `chunkswap.txt` during a swap; `hint` is a side the role remembered). True if it had to.
- `chunk.ITEM` (the controller's item id) and `chunk.isModem(name)`, for roles that keep them out of their cargo.

Farm turtles don't call it. The miner calls `ensure` after every move and while waiting.

## Moving another turtle onto the core

1. It already gets the files: `manifest.lua` appends `types.turtle.core` to every turtle role. A new core file goes in that one list.
2. `local core = dofile("turtlecore.lua")`.
3. Replace its own fuel table and `turtle.refuel` loops with `core.fuel.refuelFromInventory` / `refuelFromDock`, and `gps.locate` with `core.gps.locate`.
4. Set `core.dock.set(...)` once the dock's world position is known, call `core.dock.maybeReport` now and then, and `core.dock.setHooks` if it uses `visit`.
5. Keep the role's `FUEL_*` thresholds in its `.env` file.
6. Delete the old copies, and add a scenario (see `tests/scenarios/turtle_core.lua`).

Not fully on the core yet: the miner (chunk loading and the one-barrel dock's fallback use it; its own fuel and GPS go in #59's last stage), Weaver. Seagull keeps its own fuel-up before a scouting trip. Bowerbird never moves.
