# Miners and their Foremans

Miners are one program (`turtle/miner/`) named by the dimension they are set up in: **Canary** (Mining Dimension, `allthemodium:mining`, or anywhere that isn't the Nether or the End), **Firecrest** (Nether), **Starling** (End). Each dimension with a base has its own Foreman, which owns its miners and their docks. The Overworld Foreman is the remote for all of them.

```
                    Overworld Foreman (computer/foreman)        remote: every miner, one screen
                    owns Starlings itself (no End base)
                       |  tanis-remote (fleet snapshots up, remote_cmd down)
          +------------+-------------+
   MD Foreman (computer/mdforeman)   Nether Foreman (computer/nether)
   tanis-miner: Canaries             tanis-nether: Firecrests
   barrels: Dock Output Stock        barrels: Dock Output Stock Input Ignore
   Input Ignore Factory in/out Overflow
```

## Rules that always hold

- **Never deaf.** A question on a miner's own screen (lost, moved, re-dock) gives way to a new order, reboot or re-dock from his Foreman. With no ender modem he stops mining, goes home and waits (he keeps looking for a modem, and puts back one left in his bag by a chunk swap).
- **One brain per miner.** A miner takes `cmd` only from his own dimension's Foreman, on its protocol. `cmd.kind` names the bird it is meant for (`canary`, `firecrest`, `starling`); a miner ignores a `cmd` for another kind, and on `tanis-miner` one with no kind (an old Foreman). The Overworld Foreman never sends `cmd` to a Canary or a Firecrest: it sends `remote_cmd` to their Foreman.
- **Dig rules don't weaken:** never dig a turtle, a cable/pipe/modem/computer/barrel/hopper/ender chest/storage block (`isProtected`), and empty a chest before digging it (`isLootable`, `lootAt`).
- **Numbers:** each Foreman hands out its bird's numbers (`Canary-04`); a retired number is never reused.
- Everything on a dimension Foreman's cable is a barrel (chest → hopper → barrel where a chest is needed).

## Docks

- **One dock barrel, every miner.** He empties everything into it except his gear (chunk controller, modem, shulker box) and, for a Firecrest, his one bucket. Before heading out he asks for what he needs: `dock_req { id, seq, bucket, fuel }` on his protocol; his Foreman empties the dock, puts in fuel (and a bucket) and answers `dock_ready { id, seq, got, missing, note }`. He burns the fuel up to his target, hands back what's left (empty buckets, spare coal) and says `dock_done`. Nobody answering in 10 s: he takes whatever fuel is in the barrel himself (so a dock can be fed by hand).
- A **Starling** (the End, no Foreman serving docks there) doesn't ask: he takes fuel from his barrel and leaves his haul in it, both by hand. A save from the old two-barrel dock has no dock barrel, so he sets up again at boot (keeping his number).
- Fuel target: he tops up to `fullAt` % of his tank (75 % by default, set by his Foreman). A Firecrest also drinks lava underground below `hungryAt` %. A Canary heads out only with `fuelToStart()` (shaft down and back + a chunk + 500) and turns back when fuel < distance home + reserve (150), so a dock at Y 253 mining at Y -63 (about 630 fuel for the shaft each round trip) never runs dry.

## Junk

A Canary's junk list is `junk.txt` on the turtle (Firecrest's comes from the Nether Foreman). A plain line is junk: thrown away underground, but up to 4 slots still come home while storage is under its cap. A `keep` line is never thrown away. A `dump` line is junk that never comes home (netherrack and end stone, which the Mining Dimension is full of); it's also dropped down the shaft before he unloads. Lines added to the default list later are appended once to an older `junk.txt` (deleting them afterwards sticks).

## A moved miner

He keeps his dock's world position (`S.home`) and checks it against GPS at boot. GPS disagreeing means he was carried:

- **Far** (outside his chunk area, or above his dock: another dock or another dimension, since MD pads keep X/Z) **with a barrel next to him:** his screen offers to set up here. Yes: dimension, position, facing and dock barrel are learned again; number, label and totals are kept. No (or no barrel): status "Carry me back to my dock", and he never tunnels there.
- **Near** (inside his area): as before, he waits for START/DOCK, then digs down, tunnels to his shaft and comes up it.
- **Lost on his dock** (unloaded mid-turn, so his heading is unknown): he turns until his dock barrel is in front of him; that gives his heading with no GPS and no free side to step into (the MD's docks have none).
- **Re-dock:** the Re-dock button on a miner's page (or `/redock <name|all>`, on his own Foreman or the Overworld Foreman) sends `cmd.redock` (a fresh token per press). When he isn't mining he sets his dock up again right where he stands: GPS position, heading (a step, his old barrel, or asked on his screen), the one barrel next to him. Number, label and totals are kept; status `redockDone` echoes the token. On the turtle itself: Ctrl+T, then `miner redock`.

## Modules

Miner (`turtle/miner/`, all in `manifest.lua`): `miner.lua` is the header and a loader; the parts share one environment (like the Foreman engine), each under 12 KB:

| Part | What |
|---|---|
| `miner_base.lua` | MODES (bird by dimension), junk lists, saved state, position (dock-relative, GPS), the dig rules (`isTurtle`, `isProtected`, `isLootable`), facing by a step |
| `miner_move.lua` | `move` (never digs a turtle or cable; empties a chest first), turns, going round cables, `goToXZ`, `goY`, `goHome` |
| `miner_inv.lua` | gear, junk, valuables, making room, chests, chunk loading (`core.chunk`), the shulker box |
| `miner_lava.lua` | Firecrest's bucket, hunger, drinking pools |
| `miner_plan.lua` | orders (`applyCtrl`, reboot, `checkpoint` before every block), the chunk-by-chunk plan |
| `miner_dock.lua` | unloading, the one-barrel dock (`dock_req`), the two-barrel dock, the dock report |
| `miner_setup.lua` | labels, setup, restarts, being carried (near or far) |
| `miner_loop.lua` | main loop, radio (status out, `cmd` in), `start()` |

Fuel, GPS, the dock report and chunk loading come from the turtle core (`docs/systems/turtle.md`): `core.fuel`, `core.gps`, `core.dock`, `core.chunk`. The miner has no fuel table, refuel loop or `gps.locate` of its own.

Foremans share one engine in `shared/fm*.lua` (each a `return function(F) ... end` part on one table `F`, loaded like the turtle core): the registry (numbers, orders, presets), the barrel jobs (dock passes, stock and keep rules, output home, overflow, the factory, `dock_req`), the screens (overview, a miner's page, presets, rules, `/assign`), the miner radio and the remote link. A Foreman program is a profile (dimension, bird, protocol, config file, barrel jobs, presets) plus `dofile("fm.lua")(profile)`.

## MD Foreman barrel jobs

`/assign` on the MD Foreman (the same screen as the Nether's and storage's):

| Job | What happens to it |
|---|---|
| Dock | One per Canary. Emptied every pass (except while he takes his supplies); filled with fuel when he asks. |
| Output | Goes home: barrel → hopper → ender chest (same frequency as the Nether's Output; its twin feeds storage). |
| Overflow | Haul goes here when every Output is full. When an Output has room, Overflow drains into it first. |
| Stock | Stays in the MD: every lava bucket from the factory, empty buckets and fuel up to their keep counts (Rules page). |
| Factory in | The lava factory's input: gets every empty bucket (from docks, and Stock above its keep). |
| Factory out | The factory's output. The factory can't be stopped (a full Factory out drops buckets on the floor), so Factory out has its own lane every half second: every lava bucket to Stock while Stock has room, every empty bucket back to Factory in. Only a full Stock leaves lava waiting here ("Factory out full" on the overview); a dock that asked can still take it straight from here. |
| Input | Dropped in by hand: routed like a haul. |
| Ignore | Never touched. |

Empty and lava buckets never go home.

Every inventory call waits for a game tick, so a pass makes its calls side by side (`each` in `fm_barrels.lua`): every dock, its slots, the Inputs and Factory out at once, and each barrel is read once per pass. With 11 full docks and a full Factory out a pass takes about 6 s (one call at a time took over a minute). The sim charges the tick when a scenario sets `w.ticks = true`. The overview shows "OUTPUT FULL" and how full Overflow is.

## Remote protocol: `tanis-remote`

- **`fleet`** (dimension Foreman → broadcast, every 3 s and at once after a change): `{ type, kind, bird, birds, short, title, name, dim, foreman = <its id>, miners = { [id] = registry entry }, presets, line, full, fullAt, hungryAt, lava, fuelTarget, imported }`. Registry entry: `num label retired want minY maxY r1 r2 pMin pMax pR1 pR2 seq reboot`. The remote reads miners' own `status` broadcasts directly (ender modems hear every dimension), on `tanis-miner` and `tanis-nether`.
- **`remote_cmd`** (remote → that Foreman, `rednet.send`): `{ type, kind, rseq, op, id, ... }`, ops `pick` (pMin pMax pR1 pR2), `order` (want, and the picks to run with), `reboot`, `retire`, `presets` (the whole list). Answered with `remote_ack { rseq, ok, msg }`; resent every 3 s until acked (30 s at most). The Foreman applies it exactly like a tap on its own screen, so its screen and the remote always agree.
- **`caps`** (Overworld Foreman → broadcast): storage's junk caps, passed on to every dimension Foreman.
- **`registry_req` / `registry` / `registry_ack`:** once only. The MD Foreman asks for the Canary registry every 10 s until it has it; the Overworld Foreman sends `foreman.cfg`'s Canaries (every entry not labelled Starling), retired numbers and `nextNum`, and on the ack drops them from its own list (a copy stays in `cfg.handed`). Afterwards it never sends `cmd` to anything but a Starling, and drops a Canary the hand-over missed (an old "Digger-" label, say) as soon as the MD Foreman shows him or he reports in as a Canary. Until then the Overworld Foreman still orders the Canaries and the MD Foreman neither numbers nor adopts any, so there is one brain at every moment. `/fresh` on the MD Foreman starts without the list.

On the Overworld Foreman a miner's page offers his own Foreman's presets; the Presets page edits its own (Starlings') list, and "Of:" switches it to a dimension Foreman's (sent whole as a `presets` op).

## Tests

`tests/scenarios/miner_*.lua`, `nether_*.lua`, `mdforeman_*.lua`, `foreman_*.lua`, `turtle_core.lua`.
