# Architect (v2, #88)

One computer per Weaver. Screens: `docs/design/architect-fleet.md` (wizard) and `architect.md` (tabs). Protocol and data: `docs/systems/weaver.md`.

## Files (`computer/architect/`, one shared environment like the Weaver; each part under 12 KB)

| File | What |
|---|---|
| `architect.lua` | loads the parts, `start()`. The sim reads the state from the global `ARCHITECT`. |
| `architect_base.lua` | constants, `S` (saved in `architect.state`), `R` (live), the log (`architect.log`), helpers |
| `architect_plan.lua` | dropped file -> `builds/<name>.plan2`; the site; `layerCells(k)`; `layerToSend`; gaps; bill; progress |
| `architect_gaps.lua` | the gap list: buried and filled gaps, Forget gaps, the build's block names |
| `architect_net.lua` | radio: pairing, re-link, status, build and layers out, gaps, orders, the bill on `tanis-base` |
| `architect_wizard.lua`, `architect_site.lua` | wizard frame and steps 1-4 |
| `architect_tabs.lua`, `architect_maps.lua` | Status, Bill, Log, the monitor; Map and Side |
| `architect_run.lua` | commands, drawing, the three loops (UI, radio, file reading), `start()` |

## How it works

- **State** `S` (survives reboots): `n` (number), `wid` (Weaver's computer ID), `name hash file` (the build), `site`, `started`, `gaps`, `held`, the last `order`. The label `Architect-NN` also restores `n`. Boot: started build -> Status; else the wizard at the first step that is not done.
- **Site** `{dx,dy,dz,dh, cx,cy,cz, rot}`: dock (the turtle's own block, F3 Block) and heading; the south-west bottom corner (the first block of the bottom layer); the turn in degrees clockwise. Turning keeps the corner. Cells go to the Weaver in dock coordinates: `x = e.x - minX + cx - dx`, `z = e.z - maxZ + cz - dz`, `y = e.y + cy - dy` (`e` = planner entry, `minX`/`maxZ` = the turned footprint's west and south edge). The planner's `how d turn item n state` ride along as named fields.
- **Dock position for GPS** (#140): `sendSite()` broadcasts `site {dock = {x,y,z}, dh}` after step 3's Next and answers the Weaver's `dock_req`; `build` carries `dock` too. The Weaver turns GPS fixes into dock coordinates with it (docs/systems/weaver.md). Status shows "GPS ok" or "no GPS" from `status.gps`, and the Log gets the Weaver's `gnote` corrections.
- **Layers** are the plan layers that have blocks, numbered from 1, sent in parts of 256. The Architect keeps his layer and the next one on the Weaver (driven by `status.layer`, so it survives either side rebooting). `build` is sent until `status.hash` matches.
- **Gaps**: `layer_done.skipped` -> `S.gaps` (full entries). Cells above a gap in layers sent later wait in `S.held`. When storage's stock (the `storage` broadcast on `tanis-base`) covers gap cells they go to the Weaver as a `gaps` working area (stable order: by height, then the planner's). `gaps_filled` removes them; held cells whose column is open become gaps. Cells above a gap that were already in the layer sent ahead are built as sent, so that gap is **buried** (#141): `sweepBuried()` (before a gap list goes out) compares each gap with the highest cell already sent in its column, and `gaps_filled.buried` (the Weaver found no way in) does the same. Buried gaps leave `S.gaps` (and the bill) for `S.buried`, one Log line each with world coordinates ("buried, fix by hand"), and show on Status as "N gaps, M buried". They are never sent. After Tanis fixed them by hand, the Status button **Forget gaps** (tap twice) or `gaps forget` clears both lists (held cells whose column is open become gaps) and tells the Weaver. `gaps` alone lists the counts. `gaps_filled.cells` also covers gaps that were already filled by hand.
- **Block names** (#141): `site` and `build` carry `blocks`, every block name in the palette, which the Weaver saves so he never digs the build.
- **Bill**: items still to place (whole build minus layers done and the cells of his layer before `idx`, plus gaps and held cells), broadcast every 30 s as `{type="bill", n, bill}`.
- **Orders** `build stop home reboot refresh`: `home` is `stop` (he waits at the dock). Repeated every 2 s until `status.want` matches; `seq` is the epoch. Weaver v2 has no `test`/`clear`, so the Architect has no Test button or `ext`. The kit's map has no zoom, so no `zoom`.
- **File drop**: the CC:Tweaked `file_transfer` event, accepted on wizard step 2 and on the re-link page. `.litematic` (converted with `plan2.fromLitematic`, in its own coroutine) or `.plan2`. A replacement Architect refuses a file whose hash differs from the one the Weaver holds.
- **Numbers**: the mainframe (`computer/mainframe/weaver_numbers.lua`, `weavers.reg`) answers `number_req` and `relink`, and keeps the site of each build (`site_set`) so a replacement Architect finds it again; the Weaver does not know his own site. A pair message goes to the chosen turtle only (`rednet.send`), so other fresh Weavers stay unpaired.
- `status.state == "done"` is the finished build (`status.done` is the last `layer_done` record).

## Test and Clear (#138)
Wizard step 3 and the Status tab have **Test** and **Clear** buttons. Test sends the site to the mainframe, then the `test` order with the 4 bottom corners of the turned footprint (`testCorners()` in `architect_net.lua`). Status shows "marking k/4", then "markers out, type clear" while the Weaver reports `marks > 0`. Clear sends `clear`. Start build with markers out is fine: the Weaver clears them first.

## Tests

`tests/scenarios/architect_wizard.lua` runs the real Architect, Weaver and mainframe module with a stub storage: pairing, a dropped `placement.litematic`, the site typed in, the whole build compared with the file (also turned 90), gaps filled when storage gets the blocks, a reboot, and a second fresh Architect re-linking. `architect_monitor.lua` and `wired_monitors_5.lua` use `tests/sim/architect.lua` (an Architect already set up) and `tests/demo/weaver_stub.lua`.
