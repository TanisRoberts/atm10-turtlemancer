# Tests: a CraftOS simulator and scenarios

Runs the repo's real programs (storage, smelter, miner, ...) against a simulated CC:Tweaked world on a
virtual clock, so most things can be checked before Tanis has to test them in game.

```
pip install --break-system-packages -q lupa     # Lua 5.2, same as CraftOS
python3 tests/run.py                  # compile-check every .lua, then run every scenario
python3 tests/run.py storage          # compile check + scenarios/storage*.lua only
python3 tests/run.py --check          # compile check only
python3 tests/run.py --no-check miner # skip the compile check
```

Exit code is 0 only if everything passed. Run it before every push to main.

## What the simulator has (`tests/sim/`)

| File | What |
|---|---|
| `cc.lua` | The world: virtual clock + scheduler, computers/turtles, wired networks ("the cable"), rednet between computers, voxel blocks, GPS |
| `env.lua` | What a program sees: `os fs term peripheral rednet parallel textutils keys colors shell read print ...` |
| `term.lua` | Screens (computer, turtle, monitor) with text and colour per cell, `:text()`, `:find()`, `:dump()` |
| `inv.lua` | Inventories (chests, barrels, drawers) with one-stack-per-call `pushItems`/`pullItems`, and a furnace that cooks in virtual time |
| `turtle.lua` | A turtle in the voxel world: moves, digs (with drops), inspect, suck/drop, refuel, place, equip; every action takes game time |
| `me.lua` | An Advanced Peripherals ME Bridge on an AE2 grid: `w:meBridge{}` then `net:add("me_bridge_0", me)`. Drives/racks/cells with AE2's byte maths, storage buses (priority, capacity, `void`), insert order (highest priority, cells already holding the item first), extract order (lowest priority first), `exportItem`/`importItem` over many stacks, AP's `getDrives` zero-bytes quirk, offline (`me:setOnline(false)`). Helpers: `addRack`, `addRackAt` (a 2x5 rack by wall position, for the server board), `addDrive`, `addCell`, `addBus`, `fill`, `where`, `total`. Header of `me.lua` lists the source facts |
| `placement.lua` | Block state for what a turtle places (stairs, slabs, logs/hay, gates, chests, torches), read from CC:Tweaked's `TurtlePlaceCommand`; see "Block states" below |
| `ender.lua` | Ender Storage chests: one shared inventory per dye code, at a world block and on a wired net; `w:ender()` |
| `architect.lua` | An Architect that is already set up (`A.prepare(c)` writes its label, state and a build), for screen and monitor scenarios |
| `weaver.lua` | Weaver scenario helper: flat ground, dock turtle on an ender chest, and a world-vs-expected-blocks diff |
| `test.lua` | `T.test`, `T.eq`, `T.contains`, `T.waitFor`, `T.running` |

Nothing runs unless the scenario advances time: `w:run(30)` runs 30 virtual seconds,
`w:runUntil(pred, max)` runs until `pred()` is true. A program that crashes is recorded
(`c.error`, with traceback) and fails the test.

## Writing a scenario

Put `tests/scenarios/<system>_<what>.lua` in the repo (`python3 tests/run.py <system>` picks it up by prefix):

```lua
local cc = require("sim.cc")
local T  = require("sim.test")

T.test("storage: sorts the input barrel", function()
  local w   = cc.world()
  local net = w:net()                                   -- a networking cable
  local inp = net:add("minecraft:barrel_0", cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  local out = net:add("minecraft:barrel_1", cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })

  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))                       -- a wired modem on the cable
  c:attach("top", cc.wireless{ ender = true })          -- a wireless modem
  local mon = c:monitor("right", 57, 24)                -- an advanced monitor (mon:touch(x, y) taps it)
  c:installRole("storage")                              -- copies the files manifest.lua gives that role
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })

  inp:give("minecraft:iron_ingot", 64)
  c:run("storage")                                      -- the program, as if typed in the shell
  T.waitFor(w, function() return inp:isEmpty() end, 60, "input never emptied")
  T.contains(mon, "Iron Ingot")
end)
```

Handy calls:

- **Computers:** `w:computer{id=, label=, w=, h=}`, `c:run("prog")`, `c:reboot()` (runs `startup.lua` if there is one; files survive),
  `c:type("text")`, `c:key(257)` (Enter), `c:click(x, y)`, `c:drop(name, bytes)` (a file dragged onto the screen: the `file_transfer` event), `c:writeFile / readFile / writeTable / readTable`,
  `c:output()` (everything `print`ed), `c.screen:text()`, `c.screen:dump()` to see a layout, `c.G.x` for the running program's globals (its own, else `_G`) (`c.env` is the computer's `_G`: like CraftOS, `require` and `shell` live only in each program's env, so a `dofile()`d file can't use them).
- **Turtles:** `w:turtle{id=, x=, y=, z=, facing=0..3 (N,E,S,W), fuel=, left=, right=, items={[slot]={name,count}}}`.
  World blocks: `w:setBlock(x,y,z,"minecraft:stone", inv?)`, `w:fill(x1,y1,z1,x2,y2,z2,block)`, `w:getBlock`, `w:count(name, box)`.
  `w.gpsOn = true` makes `gps.locate()` answer with the true position.
- **Disks:** `c.mounts = { disk = 125000 }` (and `c.dirs.disk = true`) gives a computer a floppy folder with a size limit; `c.hddCapacity` caps the computer's own disk (writes past it raise "Out of space").
- **Inventories:** `cc.Inv.new{size=, types=, slotLimit=}`, `inv:give(name, n)`, `inv:count(name)`, `inv:totals()`, `w:furnace{speed=}`.
- **Ticks:** `w.ticks = true` makes every inventory call (`list`, `pushItems` ...) wait for the next game tick
  (0.05 s), as in CC, with calls from parallel coroutines sharing a tick. Use it wherever throughput matters.
- **Time/events:** `w:at(t, fn)` and `w:after(dt, fn)` run a callback at a virtual time (to unplug a modem, drop in an item, ...);
  `net:add / net:remove` while running raises the `peripheral` / `peripheral_detach` events.
- **Other computers talking on rednet:** write a tiny stand-in with `c:writeFile("x.lua", [[ ... ]])` and `c:run("x")`
  (see the Foreman in `miner_basic.lua`) or run the real program.

## Block states (`placement.lua`)

World blocks can carry `state` (a table, like `turtle.inspect` returns): `w:setBlock(x, y, z, { name = "...", state = { facing = "north" } })`.
A turtle's `place` / `placeUp` / `placeDown` sets the state the way CC:Tweaked 1.21 does. It acts like a player whose yaw is its
heading and tries clicks in this order (first that places wins): the block in the target cell (only for merging a slab), the block
one beyond the target (face toward the turtle), for forward only the top of the block under the target, then the turtle's own cell.
A sideways click is at height 0.45. So:

- **stairs** `facing` = heading; `half` from the clicked face. `placeDown` with a block two below: bottom; with air there: top.
  `placeUp` is the mirror. Forward `place`: always bottom. Corner `shape` and `waterlogged` are not simulated.
- **slabs** `type` bottom/top by the same rule. Placing the same slab into a single slab makes `type=double` (each placement
  uses one item, so a double costs two). A different slab, or a third, fails. Digging a double gives two.
- **hay_block, `_log`, `_wood`** `axis`: down/up gives `y`. Forward gives the heading's axis (`z` north/south, `x` east/west) only if
  a block is beyond the target or nothing is under it; with a block under the target and nothing beyond the turtle clicks that
  block's top and the pillar stands upright (`y`).
- **fence gates** `facing` = heading, `open=false`. **chests** `facing` = opposite of the heading, `type=single` (keeps its inventory).
- **torches**: forward with a solid block beyond: `wall_torch` (`soul_wall_torch` ...), `facing` = opposite of the heading, digs back
  to the torch item. Otherwise a floor `torch` if the block under the target is solid; `placeUp` fails. (The real game may also hang a
  torch on a side wall when it cannot hang ahead; not simulated.)

To add a block, add a row `{ "suffix$", function(ctx) return { ... } end }` to `Placement.rules` (ctx has `face`, `hitY`,
`heading`, `vertical`, `canHang`, `floorOk`). `tests/scenarios/sim_placement.lua` covers every row.

## Ender Storage (`ender.lua`)

```lua
local es = w:ender()                                    -- registry, one per world
es:place(0, 64, 0, {"red","blue","white"})              -- chest block: a turtle can suck/drop at it
es:onNet(net, 0, {"red","blue","white"})                -- same chest on a cable as "enderstorage:ender_chest_0"
es:inv(code)                                            -- the shared inventory (give/count/totals)
es.delay = 2                                            -- optional realism: items arrive at the other end 2 s later (default 0)
```

Every end with the same three-dye code is the same inventory. With a delay, space is checked when items go in and they land
after the delay (lost if the chest filled meanwhile). Peripheral type is `enderstorage:ender_chest`, 27 slots.

## Weaver scenarios (`weaver.lua`)

```lua
local W = require("sim.weaver")
local site = W.site{ y = 64, radius = 12, code = {"red","blue","white"} }   -- also ground=, heading=, fuel=, delay=, id=, label=
site.w, site.turtle (computer), site.body, site.chest (shared ender inv), site.groundY
site:home(0)                                            -- home end on a wired net (site.net) as enderstorage:ender_chest_0
W.diff(w, expected, { ox=, oy=, oz=, box={x1,y1,z1,x2,y2,z2}, fill=, max=10 })  -- ok, firstMismatches, total
W.expect(w, expected, opts)                             -- same, but raises with the report
```

The turtle sits at `(0, y+1, 0)` on an ender chest dock at `(0, y, 0)` in flat ground (no GPS), with a pickaxe, an ender modem and
an `advancedperipherals:chunk_controller` in slot 16; no role files are installed. `expected` maps `"x,y,z"` to a block name or
`{ name =, state = { ... } }` (only the listed state keys are compared). With `box`, every cell in it that is not listed must be
air (or `fill`).

## Extending the mocks

If a program needs an API the mock lacks, add it to the mock (with a line in `sim_basics.lua` if its behaviour is tricky)
rather than working around it in a scenario. Keep mock behaviour true to CC:Tweaked: `pushItems`/`pullItems` move at most one
stack and turtle actions take game time. (The mock does not enforce that wired modems can't see chests here:
scenarios put barrels on the cable, as the real base does.) Don't write a
throwaway harness in a scratchpad.

Screens behave like CC's: `term.current()` hands back plain functions (call `t.write(...)`, no colon), `setPaletteColour`
is remembered (`screen:paletteHex(colours.yellow)`), a `colour = false` computer refuses non-grey colours, and
`c:resize(w, h)` / `monitor:setSize(w, h)` raise `term_resize` / `monitor_resize`. `tests/demo/ui_demo.lua` is a small
screen built on the UI kit that `ui_core.lua` drives at every size.

Not simulated yet: `http`, `window`, redstone, the neural/plastic machines, Functional Storage drawers (use `slotLimit`),
chunk loading, mobs, fluids other than lava pickup.
