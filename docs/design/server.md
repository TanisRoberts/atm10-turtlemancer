# Server room board

Status: **signed off by Tanis** (#125, option A2). Mockups: https://claude.ai/artifact/An4Px8uYV6vm555RGzT7mo

Runs on the **server** computer (`computer/server/`, #127): an advanced computer on the storage cable that reads the same ME Bridge and drives a 4 wide × 5 tall advanced monitor (**79x67** at scale 0.5, picked with `shared/screens.lua`). Display only: it never moves items.

## The room

- Drive = 10 cells, 2 columns × 5 rows (the drive's slot order: slot 1 top-left, 2 top-right, ..., 10 bottom-right).
- Rack = 10 drives, 2 columns × 5 rows. One priority per rack.
- Wall = 3 racks. Bank = 2 walls facing each other. 2 banks. Full room: 12 racks, 120 drives, 1,200 cells.

## Layout comes from the bridge (no typed positions)

`getDrives()` gives each drive's `position {x,y,z}`, `priority` and `cells`.
1. **Walls:** group drives sharing a plane: the same `x` (wall runs along z) or the same `z` (runs along x). Pick the grouping that leaves the fewest groups.
2. **Banks:** two parallel walls facing each other with an aisle between them are one bank. Banks are ordered by coordinate, walls in a bank by coordinate. The first wall of a bank is "West" or "North" (by axis), the second "East" or "South".
3. **Columns and rows:** within a wall, the horizontal axis is the other horizontal coordinate, drawn as seen from the aisle (the viewer stands between the two walls, so the two walls run in opposite directions). Vertical = `y`, top at the top.
4. **Racks:** split the wall's columns into 2-wide groups, left to right from the wall's first drive column. Rows are the 5 drive heights from the wall's lowest drive.
5. **Not built yet:** `server.env` gives the room's size: `BANKS=2`, `WALLS_PER_BANK=2`, `RACKS_PER_WALL=3`, `RACK_COLS=2`, `RACK_ROWS=5`. Racks with no drives are drawn as "no drive" positions after the built ones. `FLIP_<n>=1` mirrors wall n (1-4, in board order) if it comes out backwards. Rack names `R1`..`R12` go in board order.
6. A drive that doesn't fit the grid (an odd one elsewhere) is listed under the tiers as `1 drive outside the room`, never dropped silently. ME chests are left out.

## Screen (79x67)

Mockup legend (kit notation): `▒` a coloured cell, `░` an empty cell slot (grey), `·` no drive at that position (grey dot on black), `▓` gold.

```text w=79
▓SERVER▓ROOM▓                                        30 drives · 281 cells  ok 
───────────────────────────────────────────────────────────────────────────────
                                                                               
 Bytes  ▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   3% 199.5M of 6G         
 Slots  ▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  23% 281 of 1200 cells    
                                                                               
 BANK 1 · West      BANK 1 · East        BANK 2 · West      BANK 2 · East      
 R1 0  R2 0  R3 5   R4 10 R5    R6       R7    R8    R9     R10   R11   R12    
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
                                                                               
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ·· ··  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
                                                                               
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ·· ·· ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
                                                                               
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ▒▒ ▒▒ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ▒▒ ▒▒ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ▒▒ ▒▒ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ░░ ░░ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ░░ ░░ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
                                                                               
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ▒▒ ▒▒ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ▒▒ ▒▒ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ▒▒ ▒▒ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ░░ ░░ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 ▒▒ ▒▒ ▒▒ ▒▒ ▒▒ ▒▒  ░░ ░░ ·· ·· ·· ··    ·· ·· ·· ·· ·· ··  ·· ·· ·· ·· ·· ··  
 1k    4k    64k    256M                                                       
                                                                               
 TIERS  items fill the top tier first ──────────────────────────────────────── 
 p10  R4      256M    ▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   3% 5.8G free     0 full 
 p5   R3      64k     ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░  52% 1.7M free     0 full 
 p0   R1+R2   1k/4k   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░  86% 69.6k free  111 full 
 ▒ 3 cells with no size: 2 Infinity, 1 MEGA Bulk. Not in the byte totals.      
                                                                               
 DEFRAG ────────────────────────────────────────────────────────────────────── 
 running  Cobbled Deepslate -> p10 / void drawer              item 14 of 41    
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  p0 freed 41k bytes
                                                                               
 Energy ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░ 82%  1,240 AE/t      2,735 kinds  41.2M items     
                                                                               
 BIGGEST PILES  defrag moves these first ───────────────────────────────────── 
 Cobbled Deepslate              1.84M    Granite                         288k  
 Cobblestone                     912k    Tuff                            190k  
 Netherrack                      640k    Andesite                        171k  
 Raw Copper                      301k    Diorite                         152k  
                                                                               
                                                                               
                                                                               
                                                                               
                                                                               
                                                                               
                                                                               
                                                                               
                                                                               
                                                                               
 Fill ▒ <70%  ▒ 70-90%  ▒ >90%  ▒ no size (infinity, bulk) ░ empty  · no drive 
```

### Rows
- **1–2 header:** gold chip `SERVER ROOM`, dim `N drives · N cells`, state word: `ok` lime, `ME offline` red (bridge not connected/online; the last data stays on screen, dimmed), `?` dim before the first read.
- **4 Bytes:** bar over all sized cells, `NN%`, `used of total` (k/M/G). Colour: lime under 70%, orange 70–90%, red over 90%.
- **5 Slots:** cells fitted out of the room's total (cyan bar).
- **7–39 the room:** four walls side by side (x = 1, 22, 42, 63; 3 racks 6 apart). Row 1 the wall name, row 2 the rack name and priority (`R1 0`), then 5 drive rows of 5 cell rows with a blank row between, then the rack's cell size(s) in dim (`1k`, `1k/4k` when mixed). Drive = 2 cells, a space, the next drive.
  - Cell colour = its `usedBytes / maxBytes` (lime, orange, red as above).
  - **No size** (ExtendedAE Infinity, MEGA Bulk: the bridge gives no `maxBytes`): light blue (`idle`), no glyph. Left out of every byte total and tier bar.
  - Empty slot in a drive: `·` dim on grey. No drive: `·` grey on black.
- **Tiers** (`TIERS  items fill the top tier first`): one row per priority, highest first: `p10`, racks, sizes, fill bar, `NN%`, `X free`, `N full` (red when over 0; full = over 90%). Under it, only when there are any: light-blue swatch + `N cells with no size: N Infinity, N MEGA Bulk. Not in the byte totals.` and `N drives outside the room`.
- **Defrag:** from storage's `{ type = "defrag", running, item, done, left, freedBytes }` on `tanis-base`. Running: `running` cyan, item name, `item N of M`, cyan progress bar, `p0 freed X bytes`. Not running: `idle` light blue + the last run's result, or `never run` dim. No news for 30 s: `storage not heard` orange.
- **Energy:** `getStoredEnergy / getEnergyCapacity` bar, `NN%`, `getEnergyUsage` AE/t; dim `N kinds  N items` (from `getItems`).
- **Biggest piles** (`BIGGEST PILES  defrag moves these first`): top 8 items by count from `getItems`, two columns, count in cyan.
- **67 legend:** fill swatches, light blue `no size`, empty slot, no drive.

### Refresh
Read `getDrives` and the totals every 5 s, `getItems` every 30 s (2,700+ kinds), off the draw path; redraw only what changed. A slow read never freezes the screen.

### Smaller monitors
Under 79 wide: the banks stack (Bank 1's two walls, then Bank 2's). Under 50 rows tall: the piles go, then energy. Under 39 wide: the room becomes one row of rack tiles (fill bar per rack).

### Taps and keys
None (display only). The computer's own screen shows the same board scaled down plus `/monitors` (re-pick) and `/help`.
