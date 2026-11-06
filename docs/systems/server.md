# Server room board (`computer/server/`)

Spec: `docs/design/server.md`. An advanced computer on the storage cable that reads the same ME Bridge and draws the drive room on a 4x5 monitor (79x67 at scale 0.5). **Display only: it never moves items.**

## Files

| File | What |
|---|---|
| `server.lua` | Boots, reads the bridge in the background, listens for storage's defrag broadcast, runs the screens (computer + monitor, `/monitors`, `/help`). |
| `server_layout.lua` | Pure: `getDrives()` list -> walls, banks, racks, byte totals, tiers. |
| `server_board.lua` | Pure drawing: a model -> a UI-kit view. Never calls a peripheral. |

Manifest role `server` (computers list, last). Needs the bridge on the cable, and a wireless or ender modem for the defrag news. The monitor is cabled, so it is picked with `shared/screens.lua` (slot `wall`, `/monitors` to pick again).

## Reading the bridge

`readLoop` runs beside the screen: `getDrives` and the energy totals every 5 s, `getItems` (2,700+ kinds) every 30 s. Draw only reads the cache, so a slow read never freezes the screen. Offline (not connected / not online / a failed call): the last data stays, drawn grey, header says `ME offline`.

## Layout (from drive positions, no typed coordinates)

Walls = drives sharing a plane (same x, or same z; whichever axis gives fewer groups). Banks = the walls in coordinate order, `WALLS_PER_BANK` at a time; first wall of a bank is West/North, second East/South. Columns run as seen from the aisle (West wall: high z to low z, East: low to high; North: low x to high x, South: high to low), rows by y from the wall's lowest drive. A rack is `RACK_COLS` x `RACK_ROWS` drives. Racks `R1`.. in board order; racks with no drive are drawn as "no drive". A wall comes out backwards: `FLIP_<n>=1` in `server.env`.

Not drawn but counted as `N drives outside the room`: drives more than 64 blocks from the middle of the room, extra planes beyond `BANKS * WALLS_PER_BANK`, and drives off the wall's grid. ME chests (`type` without "drive") are ignored.

Because the first drive column / lowest row of a built wall sets the origin, a wall whose first rack or bottom row is not built yet can come out shifted: build from the start of the wall and bottom row up, or use `FLIP_n`.

`server.env`: `BANKS=2 WALLS_PER_BANK=2 RACKS_PER_WALL=3 RACK_COLS=2 RACK_ROWS=5 FLIP_1..4=0` (edits are picked up within 5 s).

## Cells

A cell is coloured by `usedBytes / maxBytes` (lime under 70%, orange to 90%, red over). AP gives a drive's own bytes as 0, so the cells are summed. Cells with no `maxBytes` (ExtendedAE Infinity, MEGA Bulk) are light blue, listed under the tiers by kind, and left out of every byte total. Infinity / Bulk are matched on `"infinity"` / `"bulk"` in the cell item's name: **not checked against the real item ids**; any other sizeless cell is counted as "other".

## Defrag

Storage broadcasts `{ type = "defrag", running, item, done, left, freedBytes }` on `tanis-base` (`storage_defrag.lua`). Running shows the item, `item done+1 of done+left`, a progress bar and `freed`. Not running: `last run: N items, freed X bytes`, or `never run` when both are 0. No message for 30 s (or ever): `storage not heard`.

## Sizes

79 wide: four walls in a row. Narrower (39+) and tall enough: banks stacked. Otherwise one line per built rack. Under 50 rows tall the piles and legend go. The computer's own screen draws the same board (rack lines on a 51x19) with the search bar at the bottom.

## Tests

`tests/scenarios/server_board.lua`, using `ME:addRackAt` (a rack laid out by position) and the mock's `infinity` / `bulk` cells in `tests/sim/me.lua`.
