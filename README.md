# atm10-turtlemancer

ComputerCraft (CC:Tweaked + Advanced Peripherals) scripts for Tanis's ATM10 island.

## Setting up any device

1. Drag `startup.lua` onto the computer, turtle or Smart Glasses (or `wget https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/startup.lua startup.lua`).
2. Reboot (hold Ctrl+R). Setup asks: computer, turtle or glasses, which role (click, or arrows + Enter; each role is described underneath), and a label. Diggers skip the label: the Foreman numbers them.
3. It reboots, downloads that role's files and starts.

**Updating:** reboot. Every boot pulls the device's latest files from `main` (raw GitHub links can cache ~5 min after a push). If `startup.lua` itself changed, the device reboots once more by itself so the new one runs.
**Changing a role:** type `reset`. It wipes the device (role, scripts, saved state, maps, configs) and runs setup again. The label stays.

## Roles

| Type | Role | Runs | What it does |
|---|---|---|---|
| Computer | Mainframe | `mainframe` | Chat commands, alerts, island strip, status board for every machine, the butler (`$dump`, torch top-ups, warnings, welcomes, visitors, storage lock) |
| Computer | Storage | `storage` | Sorts input chests, touch screen, fuels the turtles, fills Rigger's barrel, does the smelter's item moves |
| Computer | Smelter | `smelter` | Auto-smelting rules (`smelt.txt`); asks storage to move the items |
| Computer | Foreman | `foreman` | Mining control: overview of every Digger, tap one for its layers / START / DOCK / position / retire; hands out Digger numbers; layer presets (Y range + rings) edited on the Presets page or with `/presets` on its screen; Reboot / Reboot all / `/reboot` (a Digger finishes its block, reboots, updates and carries on) |
| Computer | Farmhand | `farmhand` | Control screen for the farm turtles: overview of Figger, Tigger and friends, tap one for ROUNDS NOW / PAUSE / RE-MAP / FOUND / REBOOT, live settings, position, last haul and running totals |
| Computer | GPS host | `gps_host` | One of 4 GPS towers so turtles know their exact X/Y/Z |
| Computer | Plastic factory | `plastic` | Industrial Foregoing plastic line: tree taps -> Latex Processing Unit -> furnace -> dock barrel (`plastic.env`) |
| Computer | Neural lab | `neural` | Hostile Neural Networks wall: runs each chamber + fab column until storage has enough of what it makes (`neural.txt`, `neural.env`) |
| Computer | Art controller | `art` | Monitor wall: live turtle map coloured by height, GPS pylons, Zigger's world map, generative art you can poke (`art.env`) |
| Turtle | Digger | `miner` | Shaft + expanding-square mining (`junk.txt`); numbered Digger-01, -02... by the Foreman; reports its exact position |
| Turtle | Rigger | `rigger` | Builds from a plan file (`mossy.plan`) |
| Turtle | Tigger | `lumberjack` | Tree farm: maps a slab-ringed zone, plants a tree grid, chops and replants on a timer (`tigger.env`) |
| Turtle | Figger | `farmer` | Crop farm: harvests and replants any crop, hoes new soil, picks up what falls (`figger.env`) |
| Turtle | Zigger | `cartographer` | Flies over the island with a Geo Scanner and maps it for the art wall's World map (`zigger.env`) |
| Glasses | HUD | `glasses` | Smart Glasses: night vision AUTO / ON / OFF, HUD stats (clock, coords + facing, inventory bar), aggro alerts (`glasses.env`) |

Every role is defined in `manifest.lua`: its files live under `computer/<role>/`, `turtle/<role>/` or `glasses/<role>/`
(files more than one role needs live in `shared/`) and land on the device under their own names. Adding a role = adding its folder and one manifest entry.

## Smart Glasses

- Advanced Peripherals Smart Glasses (incl. Netherite Reinforced) are a pocket computer you wear. Right-click them in your hand to open the terminal.
- Setup only offers the Glasses type on actual glasses (it checks for the `smartglasses` API), and pre-picks the HUD role.
- Wear them (head or Curios slot) when they boot: the `smart_glasses` peripheral only shows up while they're equipped.
- Reboot from the glasses' terminal (hold Ctrl+R) to pull new versions.
- **Night vision** needs the Night Vision Module (it's on by default when fitted). Modes, switched on the glasses' screen (click, or 1 / 2 / 3; H toggles the HUD, Q stops):
  - **AUTO**: on when the light where you stand is `NV_DARK` (7) or less, or you're in the Deep Dark; off again at `NV_BRIGHT` (10) or more. In between it keeps doing what it was doing, so torch-lit edges don't flicker. Needs an **Environment Detector** in the glasses; without one AUTO just stays on.
  - **ON** / **OFF**: always / never. While the module is switched off, night vision potions don't work either (that's the module).
- **HUD** (needs an **Overlay Module**), stacked in the top-right under the potion effect icons, each line switchable in `glasses.env`:
  - `NV AUTO: on`: night vision mode and state (`HUD_NV`).
  - `14:20  night in 3:05`: Minecraft time and real time until night (or day). Time only outside the Overworld. Needs the **Environment Detector** (`HUD_CLOCK`).
  - `281 50 -14  NE`: your coordinates and facing; in the Nether the matching Overworld X/Z is added. Needs the **Player Detector**; your name is worked out once and saved as `OWNER` (`HUD_COORDS`).
  - `Inv 28%` + bar: free main-inventory slots (36, hotbar included; armour and offhand don't count), green / amber under 50% / red under 20%. Appears when an **Inventory Manager** is in the glasses (`HUD_INV`, `INV_BAR_W`).
  - Position: `HUD_CORNER` (top-right / top-left / bottom-right / bottom-left), `HUD_EDGE_X`, `HUD_EDGE_Y`; it right-aligns itself to your screen size and GUI scale.
- **Aggro alert**, top-middle: `! CREEPER 4m BEHIND +1`. Any mob within `AGGRO_RANGE` that's attacking (AP's `aggressive` flag; creepers count as soon as they lock on). Creepers take priority and flash red; the **Warden** alerts whenever it's in range. Says which side it's on and how many others there are; stays up `AGGRO_HOLD` seconds after the last sighting. `AGGRO_IGNORE` lists mobs that never count (wolves and golems by default: they attack other things). AP scans up to 8 blocks for free, once every 2 s.
- AP wipes all HUD objects when the glasses come off (including opening the terminal with them in your hand); the HUD rebuilds itself as soon as they're back on.
- To change modes while wearing them, use a **Smart Glasses Interface** (right-click opens the worn glasses' screen), or take them off and right-click them.
- Settings: `glasses.env`, made on first run, same rules as `butler.env` (edit live; your lines are never overwritten; the mode buttons rewrite the `NV_MODE` line).

## Hardware for the base computers

- **Mainframe and storage** need a wireless or ender modem: they talk on the `tanis-base` network (the smelter can use the storage cable instead, see below).
- **Storage:** a wired modem on the storage cable (barrels, drawers, input/output chests), its own monitor for the touch screen, then `/setup` with the marker items.
- **Smelter:** just a wired modem on the **same** storage cable, with the furnaces on that cable too. No wireless modem needed: it talks to storage over the cable, and storage passes its news to the mainframe. Storage is the only computer that moves items, so they never fight.
- **Mainframe:** Environment Detector, optional Chat Box, monitor wall (island strip + status board, plus a visitor column when the wall is at least 50 characters wide). For the butler: an **Inventory Manager** with your bound Memory Card and a **Player Detector**, both touching the mainframe.
- **Where the butler's items go:** the Inventory Manager can only move items into a chest it can reach, so the modem the mainframe's blocks sit on must be **joined to the storage cable**. Then `$dump` goes straight into storage's main input chest and torch top-ups come out of storage's output chest (or a dedicated restock chest picked with `/pocket` on storage). That's the default (`POCKET_DUMP=storage`, `POCKET_RESTOCK=storage`). A chest touching the manager also works: `$pocket dump <side>`.

## The butler (mainframe)

- `$get [n] <item>`: straight from storage into your inventory (`$get 32 iron ingot`, `$get torches`; no number = one stack; a vague name lists the options).
- `$dump`: everything except your hotbar goes to storage (armour and offhand stay). `$pocket`: what the manager sees, to check the hotbar slots (`HOTBAR_FIRST`).
- Torches: under 10 on you, storage tops you back up to 64 (any item, any numbers: `TORCH_ITEM`, `TORCH_MIN`, `TORCH_FILL`).
- Private warnings: inventory nearly full / full; armour or a tool at 15% and again at 5%.
- Player Detector: "welcome home" (with who dropped by), guests greeted, a visitor column on the wall, and the **storage monitor locks** (big padlock, taps ignored) while you're away. The storage computer's own screen always works. `/lock` and `/unlock` on storage do it by hand. If the mainframe goes quiet for a minute, the auto-lock lets go.
- Settings: `butler.env` on the mainframe, made on first run. Edit it live; deleted keys come back with their defaults, your lines are never overwritten. The Inventory Manager only works while you're online.
- **Foreman:** advanced computer, **ender modem** (reaches Diggers anywhere), advanced monitor touching it (any size; the computer's own screen works too).
- **Farmhand:** advanced computer, wireless or **ender modem**, advanced monitor touching it (any size; the computer's own screen works too).
- **GPS hosts (optional, recommended):** 4 computers with ender modems, high up and not all at one height. Diggers then check their position against GPS, notice if they've been carried somewhere, and find their own way back. Farm turtles pin their farm map to GPS and can't get lost.
- **Each Digger:** pickaxe + ender modem, a dump barrel (storage input) and a fuel barrel next to its dock. Storage `/fuel` adds each fuel barrel (or `/setup` with a lava bucket in each); storage keeps one refill in every one, but never takes its last stack of coal/charcoal (the smelter needs it).

## Plastic factory

Everything for plastic in one building, run by one computer (role **Plastic factory**).

- **Its own wired cable.** Don't join it to the storage cable: storage would treat the latex machines as storage barrels and the smelter would grab the factory's furnace.
- On that cable, each with a wired modem (right-click it, red ring):
  - **Tree Fluid Extractors** ("taps"), each facing away from a log (it drains the block behind it). Power makes them 3x faster. Acacia and mangrove give the most latex (4 mB a pull), oak/birch/spruce/jungle 2.
  - **Latex Processing Unit(s)** with power. 750 mB latex + 500 mB water = 1 dry rubber.
  - **Water:** any tank or block holding water (an infinite water source is ideal). Or skip it and fill the unit's 16 B water tank with buckets now and then.
  - **Buffer tanks (optional):** any other tank soaks up latex while the units are full.
  - **A furnace** (vanilla or Iron Furnace) for dry rubber -> plastic.
  - **The dock barrel:** plastic goes out here, furnace fuel comes from here. Give it a **second** wired modem on the **storage** cable and run `/dock` on storage: storage then takes the plastic away and keeps ~32 coal in it. Now nothing needs feeding by hand.
- A monitor touching the computer shows the units' latex / water / power bars, every tap, the furnace and the dock. Tap **PAUSE / RUN** in its corner.
- **Taps wear out the log:** each pull has a 1% chance to wear it; about 8 wears turn it into a stripped log (still gives 1 mB a pull), then air. A tap that stops giving latex shows **DRY** and raises an alert: put a new log behind it.
- With a wireless/ender modem it's on the mainframe's board, raises alerts, and answers `island plastic` (`island plastic pause | go`).
- No furnace (or `FURNACE=no` in `plastic.env`)? Dry rubber goes to the dock instead; add `plastic all` to `smelt.txt` and the smelter makes it.
- Terminal: `status`, `list` (what it found on the cable), `pause`, `resume`. Settings in `plastic.env` (same rules as `butler.env`): `DOCK` (if there's more than one chest on the cable), `FURNACE`, `STALL_AFTER`, `WATER_LOW`, `TICK`.
- If a machine's tanks or slots don't show up, open it and check its side settings (the coloured face buttons): the face with the modem must not be switched off.

## Neural lab (Hostile Neural Networks)

A wall of **columns**, one per mob: a **Simulation Chamber** on top, **its Loot Fabricator** underneath, and optionally a lamp. One computer (role **Neural lab**) runs them all.

- **Cable: either way works.**
  - **On the storage cable** (simplest): no dock needed. Drops go straight into storage's main input chest, and the lab asks storage for matrices and Furnator fuel, which storage puts directly into the chambers and Furnators. Storage never treats the lab's machines as storage.
  - **Its own cable:** then it needs the dock barrel below.
- **Each column:** chamber, fab, and the modems that join them to the lab cable. Full-block wired modems behind the wall work well. Right-click each modem (red ring).
- **Lamp (optional):** a **Redstone Relay** (CC:Tweaked) or AP **Redstone Integrator** touching a modem, with any lamp touching the relay. The relay switches on every side, so a flush wall works: lamp in the middle row, relay behind it between the two modems. **Steady** = running, **off** = stopped (target reached or switched off), **blinking** = needs you.
- **Power** goes to the chambers and fabs separately (power cables or Flux Points): wired modems don't carry FE. Each chamber stores 2M FE and each fab 1M, so a new column drains your cell once while it fills.
- **Dock barrel** (own cable only) on the lab cable with a second modem on the storage cable. On storage: `/dock`, pick it, and keep `prediction_matrix 64` in it. Drops and generalized predictions leave through it; matrices and Furnator fuel come in.
- Optional on the lab cable: **energy cell(s)** (the lab reads stored power from them) and **Powah Furnator(s)**.
- A **wireless/ender modem** on the computer: it gets item counts from storage and reports to the mainframe.

**How it runs**
- The **data model lives in its chamber for good** (the mod won't let a computer take it out). Put it in by hand.
- **Pick the drop in each fab's own screen.** The lab learns what a fab makes from its output.
- `neural.txt`: how many of each item to keep, e.g. `blaze_rod 512`, `ender_pearl 256`, `end_crystal off`. Items with no line: `DEFAULT_KEEP` (256). A column runs until storage has that many, then stops, and starts again under 90% (`RESTART_AT`).
- **On** = it drips matrices into the chamber one at a time and feeds predictions to its fab two at a time. **Off** = it stops adding them; the chamber finishes its run and idles (idle machines use no power).
- **Switched a fab's drop?** A running column notices on its next batch. For a stopped one, tap **CHECK** on its card: it sends one banked prediction through. It also checks by itself after 15 min, then less and less often while nothing changes (up to every 4 h); each check is one batch.
- **New columns are picked up by themselves.** Chambers, fabs and lamps are paired in the order they were connected, and a pair sticks (a replaced fab joins the chamber that lost one). Wrong pair? `PAIRS=` in `neural.env`, e.g. `PAIRS=3:5:2` (chamber 3, fab 5, lamp 2; `pairs` on the terminal shows the numbers).
- **Power:** solar first. The Furnator gets charcoal/coal while your cells, or **any one chamber**, are under 30% (`FUEL_BELOW`): power doesn't spread evenly, so the chamber furthest from the generators can starve while the rest are full. The monitor then names it (`Sim #2 0%`). Under 10% (`LOW_POWER`) only the column furthest below its target runs.
- Leave the chamber on **Inference** and both redstone settings on **Ignored**. A chamber on Training uses matrices and makes nothing: the lab flags it.
- **Monitor:** overview cards (state, item stock/target, accuracy, CHECK). Tap a column for its page: target **-** / **+** (edits `neural.txt`), **AUTO / ON / OFF**, CHECK, stats. **PAUSE / RUN** in the corner.
- **Terminal:** `status`, `list`, `pairs`, `check <n>`, `on <n>`, `off <n>`, `auto <n>`, `pause`, `resume`.
- **Alerts** (mainframe): out of matrices, no power, chamber stuck or on Training, fab with no drop picked, dock full, no counts from storage. Chat: `island neural`, `island neural pause | go`.
- **Tip:** level a model with the Deep Learner (kills) rather than Training mode (one matrix per run). With the mod's default numbers that's about 100 kills from blank to Self Aware.

## The art wall (art controller + Zigger)

**Art controller:** an advanced computer, an ender modem, and the biggest **advanced** monitor you can build touching it
(an 8x6 wall = 328 x 243 pixels: every character cell is split into 2 x 3 little pixels). Tap the **three bars in the
bottom-right corner** to switch screens:

- **Turtle map:** every turtle that knows its GPS position, as a dot coloured by height (14 bands from Y -64 to 320,
  key on the right), with a trail of where it's been. Diggers, Figger, Tigger, Rigger and Zigger all report one now.
  The **GPS pylons are red crosses**: the wall asks the GPS towers where they are, so new pylons appear by themselves.
  Tap a turtle for its details, tap anywhere else to move the map there, **-** / **+** to zoom, **FIT** to follow everyone again.
  Turtles in the Nether or End aren't shown.
- **World map:** Zigger's height map: land coloured by height (sand to green to rock to snow, scaled to your island),
  trees, shallow and deep water, turtles in magenta, pylons red, and Zigger's scan square in white while he works.
  **MAP** sends Zigger off on a new pass, **DOCK** calls him home.
- **Art: Plasma, Rings, Aurora:** generative art. Tap to send a ripple out from your finger. A fresh pattern every
  time it's picked, and again after 10 minutes without a tap.
- Goes back to the Turtle map after 5 minutes without a tap (`DEFAULT_VIEW`, `IDLE_RETURN`), or set `CYCLE=60` to
  rotate through every screen when nobody's touching it. Other settings in `art.env`: height bands, trail length, FPS.
- Its terminal: `1`-`5` switch screens, `Q` stops it (the monitor's colours go back to normal).

**Zigger (cartographer turtle):** a turtle with a **Geo Scanner** on one side and an **ender modem** on the other. No pickaxe:
he never digs, he flies over things. Needs the GPS towers.

- **Dock:** a barrel touching him that storage keeps fuelled. On storage: `/dock`, pick the barrel, keep e.g. `coal 128`
  in it (fewer trips home than the default ~32). **Open sky above his dock spot**: he leaves and lands straight up and down.
- First start: put him on his dock spot and start him. He finds the barrel, steps once to learn which way he faces, and waits.
- Press **MAP** on the World map (or **M** on his screen). He covers the area in strips 16 blocks apart, `CLEARANCE` (3) blocks
  above the ground, scanning every 8 blocks, and the wall paints each scan as it arrives. A full 328 x 243 pass is about an
  hour and ~6,500 fuel (80-ish coal). He goes home for fuel when he needs to, and docks when done. **D** on his screen = dock.
- Area: centred on his dock, 328 x 243 (fills an 8x6 wall at 1 block per pixel). Change `CENTRE_X`, `CENTRE_Z`, `WIDTH`,
  `DEPTH` in `zigger.env`; he starts the pass again if you change the area mid-way.
- **Chunks:** he only works where chunks are loaded (near a player, or force-loaded). Spots outside are skipped, not fatal:
  run another pass later with someone over there. Restarted or reloaded mid-pass? He asks GPS where he is and carries on.
- The wall keeps its own copy of the map (`art.map`) and catches up from Zigger's (`zigger.map`) whenever it starts.
  On the mainframe's board he has his own row (state, % done, chunks, fuel).

## Farm turtles and the Farmhand

Figger (crops) and Tigger (trees) run on one shared engine (`shared/farmbot.lua`).

- **Farm:** ring the area with slabs: on the ground for Tigger, at crop height for Figger (he flies one block above the
  crops). Start the turtle inside it next to its dock barrel (Figger can also start ON a dock built into the ring, facing
  in). Make the barrel a storage dock (`/dock`, or the coal marker in `/setup`): storage takes the produce and keeps fuel in it.
- **It maps the farm by itself** and re-maps every few rounds (`RESURVEY_EVERY`), so new rows or a bigger field get picked
  up. Tigger keeps his tree grid on re-maps. A map that fails (gap in the slabs, no fuel) is retried every few minutes.
- **Never lost with GPS:** the map is pinned to world coordinates. After a restart, even one mid-turn, it asks GPS where it
  is and steps once to learn which way it faces; at home after every round it checks GPS agrees with its count. Carried off
  the farm? It says where it is and where home is; put it back and press **Found** (or `island figger found`). Without GPS
  it works its way out from the map, like before.
- **Settings:** `figger.env` / `tigger.env` on the turtle, edited live. Round timer, seeds/saplings kept and how often it
  re-maps can also be changed from the Farmhand (yellow until the turtle confirms).
- **Farmhand screen:** a card per turtle (state, fuel, next round or progress, position). Tap one for ROUNDS NOW, PAUSE/GO,
  RE-MAP, FOUND (when lost), REBOOT (it finishes its job, restarts, updates), settings, last haul and everything it has
  brought in. Footer: Rounds all, Pause all, Reboot all. A turtle silent for 2 minutes can be forgotten.
- **Still on the mainframe:** every farm turtle keeps its row on the board (round progress, last round, fuel) plus a
  Farmhand row; alerts and chat (`island figger rounds|survey|stop|go|found`) work as before.
- **ATM10 note:** with a hoe, CC:Tweaked right-clicks a crop before digging it, and ATM10 harvests ripe crops on right-click,
  dropping them on the ground. Figger hoovers up under him at every plot.

## Diggers and the Foreman

- **Numbers:** a new Digger asks the Foreman for one when it first starts (Digger-01, -02...). It keeps it when moved or reset. **Retire** (tap twice on its page) docks it for good; its number is never handed out again.
- **Position:** set up at its dock, it learns X/Y/Z (from GPS, or typed in), which way it faces and the dimension, and reports where it is all the time.
- **Carried off?** With GPS it notices on restart, works out which way it faces by stepping once, and waits. Press START or DOCK on its Foreman page: it digs down to Y 0, tunnels under everything to its shaft and comes up. Put it down outside, not on a floor you care about. Without GPS it counts its moves, so carry it back to its dock instead.
- **Older Diggers** fill in their dock's X/Z and facing by themselves on the first boot with GPS, or ask once on their screen without it.

## Safety

If GitHub can't be reached or a download is broken (empty, or a `.lua` that doesn't compile), the old file is
kept and the device boots anyway. Files marked `once` in the manifest (`junk.txt`, `smelt.txt`, `mossy.plan`)
are only downloaded if missing, so your edits stay. `reset` won't wipe anything if it can't download setup first.

## Duplicate IDs

Every computer, turtle and pair of Smart Glasses keeps its files in a folder named after its ID (type `id` to see
it). If two machines end up with the **same ID**, they share one set of files, so whichever was set up last
takes the other over (e.g. your glasses suddenly running the plastic factory).

**How it happens:** ComputerCraft's ID counter (`world/computercraft/ids.json` on the server) restarts from 0 if
that file is lost or corrupted, which a server crash can do. Every machine made after that reuses an old
number. It also happens if a computer is copied (creative Ctrl+middle-click) or an old computer item is reused.

**The check:** `startup.lua` remembers which machine each disk belongs to (`owner.cfg`: label + hardware). If a
different machine boots from it, it stops with a red **DUPLICATE ID** screen instead of running the other
machine's program:
- **[1] Same machine, carry on**: you renamed it outside the scripts (e.g. an anvil). It remembers the new name.
- **[2] Stop: show the fix**: leaves you at the shell with the steps below.

No false alarms from `reset`, re-running setup, `label set`, Diggers naming themselves, or crafting a computer
into a turtle. It can't tell apart two machines that are both unlabelled *and* the same hardware, so keep
everything labelled (setup always does). The check arrives with the new `startup.lua`, so it starts working
from a device's *second* reboot.

**Fixing a clash:**
1. Keep one machine and replace the other: whichever is cheaper to rebuild (glasses: replace the computer).
2. Craft a **new** computer/turtle at a crafting table (never a copy or a spare), swap it in for the old one,
   drag `startup.lua` on and pick its role. Check `id` shows a new number. Want its settings? Copy the
   `.cfg`/`.env` files across with a disk drive and floppy before swapping.
3. **Destroy the old item** (lava or a trash can). It still carries the shared ID.
4. Reboot the machine you kept. If it shows the warning, pick **[1]**. If it's running the wrong program, type
   `reset` and set it up again.
5. If a crash caused it, other recent machines may clash too: run `id` on them. Whoever runs the server can stop
   it and set the `"computer"` number in `world/computercraft/ids.json` higher than the biggest folder number in
   `world/computercraft/computer/`, so new machines get safe IDs.
