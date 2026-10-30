# Cartographer (computer) and Seagull's map

Design: `docs/design/cartographer.md`. Code: `computer/cartographer/`. Seagull's program is `turtle/seagull/seagull.lua`.

## What it is

An advanced computer, an ender modem and a big advanced monitor laid flat as a **floor** (8x6 = 328 x 243 map pixels; any size works). It keeps the whole world map, asks Seagull for what it is missing, draws the floor and its own 51x19 screen, and sends Seagull orders. The art controller no longer has a World map screen.

| File | What |
|---|---|
| `cartographer.lua` | startup, settings, the view, radio (Seagull, turtles, pylons), orders, typed commands, the loop |
| `carto_store.lua` | every chunk in memory; saved one file per region on the computer's disk, then floppies |
| `carto_paint.lua` | the 16-colour palette, land bands, the painter and the pane (view, quarter turns, outlines) |
| `carto_floor.lua` | the floor: map, zoom bar, FILL, region outlines, labels |
| `carto_screen.lua` | the computer's screen on the UI kit: thumbnail, Seagull / Next / Storage panel, controls, colour key |

## Storage

- Format: `shared/mapchunk.lua` (run-length coded). One file per region: `regions/<rx>_<rz>.map`; region = 16 x 16 chunks, `rx = floor(chunkX / 16)`.
- A region goes to the computer's disk while it has room (`RESERVE`, 60,000 bytes, stays free), else to the floppy with the most free space (`/disk`, `/disk2`, ...). A write that fails (disk full) moves on to the next mount.
- On start every region file on every mount is read as one map (the newest copy of a chunk wins). A floppy coming or going (`disk` / `disk_eject`) re-reads the mounts; the regions of a pulled floppy stay in memory and are written elsewhere on the next save.
- A region file can be bigger than a floppy (125 KB) when the terrain is very varied (the worst case is 134 KB). Those stay on the computer's disk.
- The storage gauge (computer screen, `/storage`) shows used/capacity per mount and about how many more regions fit.

## Radio (`tanis-carto`)

Kept from the old art-controller protocol, plus what Seagull's region work (#68) uses:

- Cartographer -> Seagull `have {revs}` (rev of every chunk it holds); Seagull answers `chunks {chunks, more}` in batches of 24; while `more` the next `have` follows at once. Seagull also pushes fresh chunks unasked.
- Cartographer -> Seagull `cmd {want = "map" | "dock", next = {rx, rz} | false, seq}`, repeated every 2 s until Seagull's status `seq` echoes it (30 s at most). `next` names the region to map next; `false` clears it.
- Seagull `status` may carry `done_region = {rx, rz}`. Once the Cartographer holds all 256 chunks of it **and has saved the region to a disk**, it sends `{type = "region_ok", to = <seagull>, region = {rx, rz}}` (again on each status that still names it). If the region cannot be saved (storage full) it does not answer and shows an error.
- `scan_region = {rx, rz}`, `scan_started` (epoch seconds or ms) and `scan_secs` give the scan percentage; without them the outline says "scanning" with no %. Without `scan_region` the region under Seagull's position is used.
- Mainframe: every 5 s `{type = "cartographer", regions, chunks, seagull = {...}}` on `tanis-base`. The board shows one Cartographer row (Seagull's state, regions, chunks, fuel) and hides Seagull's own `carto` row while a Cartographer is on the air.

## Seagull's side (`turtle/seagull/seagull.lua`, `shared/regionplan.lua`)

- **One region per MAP.** The region is `cmd.next` if the Cartographer sent one (tap), else the first region not on his `done` list in rings round the region holding his home (the same order the Cartographer shows as "spiral"). `cmd.next = false` clears the tap. `REGION_CHUNKS` in `seagull.env` (16) is the region side; leave it.
- **Chunk by chunk.** He flies a snake over the region's 256 chunks to each chunk's middle (`plan.centre`), keeps it loaded with `core.chunk.ensure` (a chunk controller in his bag swapped onto his modem's side for a moment, see `turtle.md`), and scans with radius 8: that covers the whole chunk. Quarters of a chunk with unseen columns (a pit or cliff beyond the scan's height) get a second scan from their middle (`plan.extras`). A chunk that cannot be entered ("chunk not loaded") is retried 3 times, then skipped and counted in `skipped`; the Cartographer then never gets all 256 chunks and keeps waiting.
- **Held back until whole.** While he scans a region its chunks are not sent (not pushed, not in `have` answers), so the region appears at once. Ground seen outside the region (on the way) is kept in memory only, for flying.
- **Hand-over.** The last chunk done, he sets `done_region`, queues the region's chunks, flies home and waits for `region_ok` (queuing them again every minute). Then he deletes the region's chunks from `seagull.map`, adds it to his `done` list and idles. MAP while he waits does nothing.
- **Status** (`tanis-carto`): `scan_region`, `scan_started` (epoch ms, set when the first chunk is reached), `scan_secs` (the whole region's expected time: elapsed over chunks done, so the Cartographer's % is the real progress; the last region's time before chunk 5), `done_region`, `next_region`, plus `wp`/`wps` = chunk number / 256 for the mainframe board.
- **Reboot.** The state file keeps region, chunk number and a checkpoint every 8 chunks (the map is saved then); on boot he returns to the checkpoint and carries on. Fuel: he goes home when the trip to the next chunk and back is not covered, refuels and returns to the same chunk.
- He stays on the radio while scanning (the modem is off for 0.15 s per swap), so DOCK and tap orders arrive mid-region.

## Floor

- Left: the map. Right 8 columns: `+`, a track with a tick per zoom level (1, 2, 4, 8, 16 blocks per pixel; tap a tick), `-`, `FILL`. A tap on the map centres the view (on the computer too). It never sends Seagull anywhere.
- **Never seen** is black with a faint dot and the dotted region grid. **Ocean** is solid blue (`blue` deep, `lightBlue` shallow). Land has six bands (beach, grass, low, mid, hills, stone). Cyan outline = region being scanned (`~NN%`), white outline = next region (`NEXT`), white dots = turtles (with labels), red `+` = GPS pylons.
- **FILL** (`FLOOR_FILL` in `cartographer.env`): the map takes the whole floor, fits everything explored, keeps fitting as it grows, ignores taps and the computer's view; only a lit FILL button stays.
- **`FLOOR_ROTATE`** (0-3 quarter turns): computers cannot read which way a flat monitor faces, so set which way the top of the floor points (0 north, 1 east, 2 south, 3 west). The computer's own screen is always north-up.

## Computer screen

Header (state, regions), a small copy of the floor's view on the left (tap mapped ground to centre; tap an unmapped region twice within 4 s to queue it as the next region), Seagull / Next / Storage on the right, buttons `MAP DOCK < > ^ v - + FIT`, the command bar, `Key` for the colour key. Next shows the queued pick (`you`) or the next unmapped region in rings round Seagull's home (`spiral`).

Keys (command bar empty): arrows pan, `-` / `+` zoom, `f` fits.

### Commands (shared slash module, with or without the `/`)

`/map`, `/dock`, `/next X,Z` (region numbers), `/next clear`, `/goto x z` (blocks), `/fit`, `/fill on|off`, `/storage`, `/status`, `/help`.

## Settings (`cartographer.env`)

`FLOOR_FILL`, `FLOOR_ROTATE`, `SAVE_EVERY` (30 s), `STALE` (30 s), `HIDE_AFTER` (900 s), `RESERVE` (60000 bytes).

## Setting one up

1. Advanced computer with an ender modem; an advanced monitor touching it or on the wired cable (the biggest touching one wins; otherwise tap-to-pick, `/monitors` asks again; laid flat is the idea, any works); optional disk drives next to it with floppies.
2. `startup` -> pick Cartographer. It lists itself on the mainframe board within seconds.
3. It finds Seagull on the radio and catches up with his map. The old `art.map` on the art controller is not read; Seagull's `seagull.map` is the master.

## Known limits

- The `have` message lists every chunk the Cartographer holds, so it grows with the map (a big map makes a big message every few minutes).
- Seagull forgets a region only after `region_ok`; until then (the Cartographer off, its storage full) he waits at his dock with the whole region.

## Tests

`tests/scenarios/cartographer_basic.lua` with `tests/demo/seagull_stub.lua`: a whole region arriving, region_ok, floor and screen, taps and zoom, FILL, orders, scan estimate, floppy spill-over and reboot, a full disk, the art controller without a World map, the mainframe row. The sim's `c.mounts` / `c.hddCapacity` give a computer floppies and a small disk.
