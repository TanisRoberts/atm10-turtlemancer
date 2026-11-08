# Weaver fleet: Weavers, Architects, build files

Decided in the #82 spike (project #81). Every Weaver sub-issue builds on this. Where this note and an issue disagree, this note wins.

## The setup

- **Any number of Weavers, each paired with one Architect.** One Weaver per build. After pairing they are `Weaver-NN` and `Architect-NN`, the same NN. Numbers are never reused.
- **The island is finished.** The island Weaver and its Architect are the first pair, **01**. v2 replaces the old programs in place: roles stay `weaver` and `architect`, and the old files, `mossy.plan`, `weaver_link`, storage's `supplyWeaver` and the `tanis-rigger` protocol go as the v2 pieces ship (#86, #88, #89, #90). There is no separate migration (#91 closed).
- **Architects stay at home** on the base network. **Weavers work far away** (the arena is "very far" from Cryptodira, in the Overworld). Both carry **ender modems**.
- **No force-loading.** The base uses all 25 force-loaded chunks. Weaver carries an Advanced Peripherals chunk controller and keeps his own chunk loaded (turtle core `chunk`, as the old Weaver does). Nothing else at the site needs loading: an Ender Storage chest's contents are global.
- **No GPS at the site.** Weaver navigates by dead reckoning from his dock. GPS is used only if it answers (never required).

## 1. Who holds the build file: the Architect

The Architect holds the build (the `.litematic` and its converted plan). The Weaver holds a **working window**: the layer he is building and the next one, each as an ordered cell list.

| Concern | How it's covered |
|---|---|
| Disk (1 MB each) | Only the Architect stores the whole build. The Weaver stores two layer lists (a few KB to ~30 KB each). |
| Architect offline or destroyed | The Weaver finishes the two layers he holds, then waits at the dock. Supply goes straight to storage, not through the Architect, so it keeps working. A new Architect re-links by number (section 5). |
| Restart safety | The Weaver saves `weaver.state` (number, build name, plan hash, site, layer, cell index, position, heading) and the two layer lists as files. He resumes at the same index. Position is saved before each move, as today. |
| Gap list | The Weaver reports each cell he skipped (storage had none) when he finishes a layer. The Architect keeps the build-wide gap list on disk, never puts a cell on top of a gap into a later layer, and sends a **gap list** as a working area once storage has the block (it watches storage's `tanis-base` stock broadcast). The column above a gap is open, so Weaver fills it with `placeDown` from above. |
| Bill | The Architect computes it from the plan and broadcasts what's left (`tanis-base`, as today's Weaver does) so storage keeps those items back. |
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

Fence gates face the heading; chests face back towards Weaver (turn the other way first). #83 confirms all of this in game; #87 implements it.

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

## Notes for engineers

- Old files to replace or delete per sub-issue: `turtle/weaver/weaver.lua` and `mossy.plan` (#86), `computer/architect/architect.lua` (#88), storage's `weaver` single job, `supplyWeaver`, `weaverReq` and `need` handling (#89), `computer/mainframe/weaver_link.lua` and `_G.WEAVER_STATUS` (#90). `shared/weaverplan.lua` goes once nothing uses it; its nearest-neighbour order moves to the new code.
- The sim has ender chests, block states and stair rules (see `tests/README.md`).
