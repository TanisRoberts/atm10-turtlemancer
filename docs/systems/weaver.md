# Weaver fleet: Weavers, Architects, build files

Decided in the #82 spike (project #81). Every Weaver sub-issue builds on this. Where this note and an issue disagree, this note wins.

## The setup

- **Any number of Weavers, each paired with one Architect.** One Weaver per build. After pairing they are `Weaver-NN` and `Architect-NN`, the same NN. Numbers are never reused.
- **The island is finished.** The island Weaver and its Architect are the first pair, **01**. v2 replaces the old programs in place: roles stay `weaver` and `architect`, and the old files, `mossy.plan`, `weaver_link`, storage's `supplyWeaver` and the `tanis-rigger` protocol go as the v2 pieces ship (#86, #88, #89, #90). There is no separate migration (#91 closed).
- **Architects stay at home** on the base network. **Weavers work far away** (the arena is "very far" from Cryptodira, in the Overworld). Both carry **ender modems**.
- **No force-loading.** The base uses all 25 force-loaded chunks. Weaver carries an Advanced Peripherals chunk controller and keeps his own chunk loaded (turtle core `chunk`, as the old Weaver does). Nothing else at the site needs loading: an Ender Storage chest's contents are global.
- **GPS fixes his position and heading** (`weaver_gps.lua`, #140). The base's GPS towers use ender modems, so a fix reaches him anywhere in the Overworld. Dead reckoning from the dock is the fallback when GPS doesn't answer (never required). See section 8.

## 1. Who holds the build file: the Architect

The Architect holds the build (the `.litematic` and its converted plan). The Weaver holds a **working window**: the layer he is building and the next one, each as an ordered cell list.

| Concern | How it's covered |
|---|---|
| Disk (1 MB each) | Only the Architect stores the whole build. The Weaver stores two layer lists (a few KB to ~30 KB each). |
| Architect offline or destroyed | The Weaver finishes the two layers he holds, then waits at the dock. Supply goes straight to storage, not through the Architect, so it keeps working. A new Architect re-links by number (section 5). |
| Restart safety | The Weaver saves `weaver.state` (number, build name, plan hash, site, layer, cell index, position, heading) and the two layer lists as files. He resumes at the same index. Position is saved before each move, as today. |
| Gap list | The Weaver reports each cell he skipped (storage had none) when he finishes a layer. The Architect keeps the build-wide gap list on disk, never puts a cell on top of a gap into a later layer, and sends a **gap list** as a working area once storage has the block (it watches storage's `tanis-base` stock broadcast). The column above a gap is open, so Weaver fills it with `placeDown` from above. |
| Bill | The Architect computes it from the plan and broadcasts what's left on `tanis-base` as `{type="bill", n, bill}` so storage keeps those items back (it sums every Architect's bill). |
| Message size | A layer goes in parts of at most 256 cells, each acknowledged. |

## 2. Handing over a build file: drag and drop onto the Architect

Tanis drags the `.litematic` onto the Architect's screen (CC:Tweaked file upload, the same way `startup.lua` goes onto a device). The Architect converts it on the spot (`shared/litematic.lua`, #85) and keeps the result as `builds/<name>.plan2`. The build's name is the file's Litematica name (`Metadata.Name`), else the file name. A finished `.plan2` dropped the same way is accepted too.

Builds are never put in the repo (other people's builds, public repo). If an Architect is replaced, Tanis drops the same file again; the Architect checks it against the plan hash the Weaver reports.

## 3. Plan format v2 (`.plan2`)

Line-based text, written by the converter, read only by the Architect.

```
#plan2 <serialized info>   name, author, size = {x,y,z}, blocks, types, hash, bill = {[name]=n},
                           palette = { {name="minecraft:sandstone_stairs", state={facing="north",half="top"}}, ... }
#L <y>                     then one line per row: "z|x0|<count>:<p>,<count>:<p>,..."
                           p = palette index, or "." for nothing; runs are comma-separated
#M <y>                     then "x,z,<how>" for cells not placed the default way (section 4)
```

- **No 52-type limit**: palette entries are numbers. A palette entry is a block name plus only the states that matter: stair `facing`/`half`, slab `type`, `axis`, `facing` of gates, chests and wall torches. Dropped: fence/wall connections, stair `shape`, `waterlogged`, leaf `distance`, anything else that fixes itself.
- **No `#ext` section.** Builds are on land; the bottom layer goes on the ground. Seabed walls are gone.
- Coordinates are plan coordinates (x, y, z from 0). The Architect turns them into world cells with the site's origin and rotation, and **rotates states** with them (facing turns with the build; `axis` x and z swap at 90 and 270).

## 4. Build order and direction-sensitive blocks

The Weaver places like a player whose yaw is his heading. So he turns first, and the half comes from the face he clicks (table in #81). Default method: hover one above the cell and `placeDown`. Exceptions, worked out by the converter and written as `#M` lines so the order is fixed in the file and survives any restart:

| `how` | Cell | What Weaver does |
|---|---|---|
| (none) | most blocks; bottom-half stair/slab with a block under; top-half with **air** under (comes out top by itself) | turn to facing, `placeDown` from above |
| `F<d>` | bottom-half stair/slab with **air** under; wall torch (`d` = towards its wall) | stand in the cell on the other side (`cell - d`), face `d`, `place`. The converter puts this cell before the cell he stands in, in the same layer. |
| `T<d>` | top-half stair/slab with a **block** under (stair `S` at y, block `B` under it at y-1) | `B` is left out of layer y-1. In layer y, `S` comes first and goes down with air under it (top half). Then `B` is filled from its side `d`: Weaver goes down the open column at `B+d` and places forward into `B`. `B+d` at y-1 must be air in the finished build and not blocked at y when he goes down; the converter checks this. |
| `2` | double slab | `placeDown` twice. |
| `U` | could not be done as asked (no free side for `T`/`F`, sideways hay or logs with nothing to click) | placed the default way; the converter lists these, and Tanis accepts them (sideways hay standing upright is fine). |

**Code** (`shared/`, all in the `architect` role): `plan2.lua` builds a plan from a trimmed Litematica region (`plan2.fromLitematic(bytes)`), writes it (`plan2.text`) and reads it back (`plan2.parse`, `hashOK` checks the body against `info.hash`). `plan2place.lua` decides the `#M` marks (`classify`, run by `build`) and gives a layer's ordered cells for a rotation: `plan2place.layer(plan, y, rot)`. `plan2order.lua` is the ordering. Each entry has `how` (nil, `F`, `T`, `2`, `U`, or `B` = the fill of the block under a `T`), `d`, `turn` (the heading to face before placing), `item`, `n`, the rotated `state`, and position turned about the plan origin (as `weaverplan.toWorld`). `info.stats` counts F/T/U/2; `plan.ulist` says why each U could not be done. Other rules the planner follows: sideways logs/hay use `F` (clicking the next block of the row, so the row is built from its far end; its last block has nothing to click on a floor and is `U`); a top-half stair/slab on the ground (layer 0) is `U`; a block under a `T` that is not plain, or that a torch or sideways log hangs on, makes it `U`. `tests/scenarios/weaver_plan2.lua` builds a hand-made file in the sim by these lists and compares every state.

Fence gates face the heading; chests face back towards Weaver. The planner turns the entry (`turn`); the Weaver just faces it (cell format in section 8, #87). #83 confirms it in game.

Inside a layer, cells go in nearest-neighbour order (as `weaverplan.lua` does today), with the `F`/`T` constraints above. The Architect computes each layer's list and sends it already ordered. The Weaver just works through it by index.

## 5. Pairing and numbers

**The mainframe keeps the number list** (`weavers.reg`: every number handed out and the turtle and computer IDs it went to). It is always on and hears everyone. Numbers only go up. The first number ever handed out is **01**, for the island pair.

First contact (all on `tanis-weaver`):

1. A Weaver with no number (label not `Weaver-NN`) broadcasts `{type="hello", id}` every 3 s and shows "Waiting to pair, ID <id>" on his own screen.
2. Tanis picks **Pair with a new Weaver** on a fresh Architect. It lists the unpaired Weavers it hears, by computer ID. Tanis picks one.
3. Architect → mainframe `{type="number_req", turtle=id}`. Mainframe → `{type="number", turtle=id, n=NN}` and saves it. (Asked again for the same turtle, it answers with the same number.)
4. Architect → Weaver `{type="pair", n=NN}`. Weaver labels himself `Weaver-NN`, saves the Architect's ID, answers `{type="paired", n=NN}`. The Architect labels itself `Architect-NN`.

**Re-link:** Tanis picks **Re-link to Weaver number** on a fresh Architect and types `02`. It broadcasts `{type="relink", n=2}`. Weaver-02 switches to the new Architect's ID and answers with his state (build name, plan hash, site, layer, index, gaps). The Architect asks Tanis to drop the build file again, checks the hash, and carries on. The mainframe updates the computer ID in `weavers.reg`.

## 6. Protocol and roles

- Protocol **`tanis-weaver`**. `tanis-rigger` is retired with the old programs. Storage's stock and the bill stay on `tanis-base`.
- Roles stay **`weaver`** (turtle) and **`architect`** (computer). No new names, no "-igger".
- Every message carries `n` (the Weaver number). A Weaver obeys orders (`{type="order", n, want, seq}`; newest `seq` wins, as today) from his Architect or the mainframe (chat orders by label). Weaver status (`{type="status", n, label, ...}`) is broadcast every few seconds; the Architect and the mainframe both listen. The mainframe shows one row per Weaver (#90).

## 7. Supply: one ender chest per Weaver, cleared and refilled

One dye-coded Ender Storage chest per Weaver. Site end: under the Weaver's dock (he sits on it). Home end: on storage's cable with a full-block wired modem, assigned in `/assign` as **Weaver supply NN** (#89). Storage pushes into it and pulls out of it directly; no barrel or hopper in between.

1. Weaver, at the dock, works out the batch for the cells he holds next. He keeps what he already has of it (and his fuel and chunk controller) and drops everything else into the ender chest, empty buckets included.
2. Weaver → storage `{type="supply", n, seq, items={[name]=count}, fuel=units}`, repeated every 5 s until answered. At most what fits in his free slots.
3. Storage pulls everything out of that Weaver's chest into storage (the clear), then pushes the items and fuel (lava first, coal if none), one stack per call.
4. Storage → `{type="supplied", n, seq, sent={[name]=count}, missing={[name]=count}}`. For a repeated `seq` it re-sends this reply instead of doing it again. Requests from different Weavers queue; none is lost.
5. Weaver sucks from the chest until he has gained everything in `sent` (Ender Storage is instant, but he keeps checking for up to 30 s). Anything in `missing` becomes gaps in the cells he builds.

## 8. The Weaver program (v2, #86)

`turtle/weaver/`: `weaver.lua` loads `weaver_base/move/inv/net/build/loop.lua` into one shared environment (as the miner). Fuel and chunk loading come from the turtle core. Tunables in `weaver.env`: `FUEL_TARGET` 20000, `FUEL_LOW` 3000, `SUPPLY_WAIT` 30.

- **Setup** (first start, or `weaver setup`): a chest, barrel or Ender Storage chest must be under him; asks which way he faces. With a GPS fix he learns his facing himself (steps a block and back, never digging) and doesn't ask; otherwise he counts moves from the dock. Dock coordinates: the dock cell is 0,0,0; x east, y up, z south. After carrying him back to the dock: `weaver found`.
- **Cells** are the planner's entries (`plan2place.layer`, section 4) in dock coordinates, ordered: an array `{x, y, z, "minecraft:block"}` that also carries named fields `how`, `d`, `turn`, `item`, `n`, `state` (all optional; the Architect (#88) translates the planner's entries, keeping those names). Headings are compass letters `N E S W` (N = -z, E = +x). The Weaver reads `how d turn item n`; `state` is for checks and the Architect. He hovers at y+1 unless `how` says otherwise.
  - Default (`how` nil, `T`, `U`, `2`): go above the cell, face `turn` (if set), hold `item` (default: the block), `placeDown` `n` times (`2` = double slab, two placements).
  - `F`: stand in the cell `cell - d` at the cell's own height, face `d`, `place` forward (bottom-half stair/slab over air; wall torch, whose `item` is the torch and whose block is the wall torch; sideways logs).
  - `B` (the fill of the block under a `T` stair): the cell has the y of the block. He goes down the open column at `B + d`, faces away from `d`, and places forward into B.
  - A block already standing in the cell (same name) is accepted (restart safe); a natural block is dug first; anything else is `blocked`. `skipped`/`blocked` reports use the cell's name.
- **Messages** (all on `tanis-weaver`, broadcast, every one carries `n`):
  - `hello {id}` every 3 s while unpaired. `pair {n}` answered by `paired {n}`; label `Weaver-NN`.
  - `relink {n}` answered by `state {…status fields…}`.
  - `build {n, name, hash, total, blocks, dock, dh}`: a new `hash` wipes his layers and gaps. Answered `build_ack`. `blocks` = every block name in the build (also in `site`): saved in `weaver.cfg` as `blocks`. `canDig` refuses all of them at the site, whatever layer he is on, so he never digs the build (sandstone and terracotta are natural blocks too). A `weaver.cfg` without `blocks` sends `dock_req` until a `site` brings them, and he builds meanwhile.
  - `layer {n, hash, layer, total, part, parts, cells}`: layers number from 1, at most 256 cells per part, each part answered `layer_ack {layer, part}`. He holds the layer he builds and the next.
  - `layer_done {layer, skipped = {{x,y,z,name}}, blocked = {{x,y,z,name,why}}}` when a layer is finished (the Architect then sends layer+2). The last one also rides in `status.done`.
  - `gaps {n, cells}`: a working area; he does it at the next layer boundary (or at once when the build is done) and answers `gaps_filled {cells, buried}`; `gaps_ack` on receipt. Per cell he goes to it first (even with none of the block on him) and looks: the right block already there (put in by hand) is **filled**, nothing is fetched or placed. If the way in is shut by a block he must not dig (the build on top of a gap, a side placement walled in) the cell is **buried**: not dug, listed in `buried`, and he moves on. Either way it leaves his gap list. `gaps_forget` (Architect to Weaver) clears his gap list.
  - `order {n, want = "build"|"stop"|"status"|"reboot"|"test"|"clear", seq, corners}`; `done {build, gaps}` when the last layer is in and the gap list is empty.
  - `site {n, dock = {x,y,z}, dh}` (Architect to Weaver; `dock_req` is the Weaver asking). `status {n, label, state, msg, want, build, hash, layer, total, idx, cells, work, x, y, z, h, fuel, gaps, need, done, lost}` every 3 s (`h` = heading 0..3 N/E/S/W; the Architect shows `at` and heading, and `lost`, in every wizard step); `need` is the layer number he is waiting for.
  - Supply: `supply {seq, items, fuel}` to storage every 5 s until `supplied {seq, sent, missing}`; then he sucks until he has gained everything in `sent` (up to `SUPPLY_WAIT` s after the last item). `missing` names become gaps (`S.short`).
- **GPS** (`weaver_gps.lua`, #140): the Architect sends his dock's **world** position (wizard step 3: the turtle's block on the chest) in `site {dock = {x,y,z}, dh}` after step 3 and in every `build`; he keeps it in `weaver.cfg` as `wx wy wz`. With none saved (an older Weaver) he sends `dock_req` every 10 s until it arrives, and carries on meanwhile. A fresh fix (a stale one counts as none) minus the dock's world position is his dock coordinate (the axes are the world's). He checks it:
  - **at boot and when the dock position arrives**: position is overridden by the fix, and the heading is learned by stepping one block (forward, else back, else up first) and back, comparing fixes. A fix clears `lost` (if the heading was learned). Corrections are noted in `S.gnote` and reach the Architect's Log.
  - **every 40 moves and before going home**: position only.
  - Over `FAR_FROM_DOCK` no longer means lost once a fix has confirmed his position. While lost, he retries every ~30 s.
  - No answer: nothing changes. Status carries `gps` (true/false), `fix` (last world fix) and `gnote`; the Architect's Status shows "GPS ok" or "no GPS".
- **Dock visit**: burn the fuel he carries, work out the batch (cells ahead, at most 12 slots), drop everything else into the chest (empty buckets too), ask, collect. Fuel is asked for under `FUEL_LOW` or when the tank is close to the trip home; fuel items are burnt as they arrive.
- **Test and clear** (`weaver_mark.lua`, #138): `test` carries `corners` = the 4 bottom-layer corner cells of the turned footprint in dock coordinates. He flies to each and places one marker block on top of the cell (the block he carries most of; with nothing on him he asks storage for 4 cobblestone), then goes home. Status `marking` with `marked = k` while he works; `marks` = markers standing (saved in `S.marks`, so a reboot keeps them). `clear` digs exactly those positions (only if the same block is still there), then home. A `build` order with markers out clears them first.
- **Files**: `weaver.state` (progress, position, open supply request), `weaver.L<n>` (held layers), `weaver.gaps`, `weaver.gaplist`. A reboot or chunk unload resumes at the same cell; an open supply request is picked up again (same `seq`). A turn is saved before it is made, with the block ahead; after a reboot in the middle of one, a different block ahead means the turn happened. If it looks the same, he is `lost` (heading unknown): with GPS he works it out himself; without, carry him to the dock and run `weaver found`.
- **Never home from a position he can't trust** (#139): idle/stopped/done off the dock, he goes home only if an Architect has paired or a build is loaded; with neither he stays put. More than `FAR_FROM_DOCK` (200) blocks out in x or z, at boot or when idle, he is `lost` and doesn't move. Waiting at an unloaded chunk, stuck retrying, idle and lost all keep his chunk loaded on `core.chunk`'s timer, and the net loop keeps sending status.

## Notes for engineers

- Old files to replace or delete per sub-issue: `turtle/weaver/weaver.lua` and `mossy.plan` (#86), `computer/architect/architect.lua` (#88, done: `docs/systems/architect.md`), storage's `weaver` single job, `supplyWeaver`, `weaverReq` and `need` handling (#89), `computer/mainframe/weaver_link.lua` and `_G.WEAVER_STATUS` (#90). `shared/weaverplan.lua` is gone (the planner has the ordering).
- The sim has ender chests, block states and stair rules (see `tests/README.md`).
