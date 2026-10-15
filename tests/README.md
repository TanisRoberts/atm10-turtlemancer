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
  `c:type("text")`, `c:key(257)` (Enter), `c:click(x, y)`, `c:writeFile / readFile / writeTable / readTable`,
  `c:output()` (everything `print`ed), `c.screen:text()`, `c.screen:dump()` to see a layout, `c.env._G.x` for a program's globals.
- **Turtles:** `w:turtle{id=, x=, y=, z=, facing=0..3 (N,E,S,W), fuel=, left=, right=, items={[slot]={name,count}}}`.
  World blocks: `w:setBlock(x,y,z,"minecraft:stone", inv?)`, `w:fill(x1,y1,z1,x2,y2,z2,block)`, `w:getBlock`, `w:count(name, box)`.
  `w.gpsOn = true` makes `gps.locate()` answer with the true position.
- **Inventories:** `cc.Inv.new{size=, types=, slotLimit=}`, `inv:give(name, n)`, `inv:count(name)`, `inv:totals()`, `w:furnace{speed=}`.
- **Time/events:** `w:at(t, fn)` and `w:after(dt, fn)` run a callback at a virtual time (to unplug a modem, drop in an item, ...);
  `net:add / net:remove` while running raises the `peripheral` / `peripheral_detach` events.
- **Other computers talking on rednet:** write a tiny stand-in with `c:writeFile("x.lua", [[ ... ]])` and `c:run("x")`
  (see the Foreman in `miner_basic.lua`) or run the real program.

## Extending the mocks

If a program needs an API the mock lacks, add it to the mock (with a line in `sim_basics.lua` if its behaviour is tricky)
rather than working around it in a scenario. Keep mock behaviour true to CC:Tweaked: `pushItems`/`pullItems` move at most one
stack and turtle actions take game time. (The mock does not enforce that wired modems can't see chests here:
scenarios put barrels on the cable, as the real base does.) Don't write a
throwaway harness in a scratchpad.

Not simulated yet: `http`, `window`, redstone, the neural/plastic machines, Functional Storage drawers (use `slotLimit`),
chunk loading, mobs, fluids other than lava pickup.
