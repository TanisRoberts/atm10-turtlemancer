# atm10-turtlemancer

ComputerCraft (CC:Tweaked + Advanced Peripherals) scripts for Tanis's ATM10 island.

## Setting up any device

1. Drag `startup.lua` onto the computer, turtle or Smart Glasses (or `wget https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/startup.lua startup.lua`).
2. Reboot (hold Ctrl+R). Setup asks: computer, turtle or glasses, which role (one role at a time as a full card: up/down or scroll to browse, Enter or click the card to pick), and a label. Canaries skip the label: the Foreman numbers them.
3. It reboots, downloads that role's files and starts.

**Updating:** reboot. Every boot pulls the device's latest files from `main` (raw GitHub links can cache ~5 min after a push). If `startup.lua` itself changed, the device reboots once more by itself so the new one runs.
**Changing a role:** type `reset`. It wipes the device (role, scripts, saved state, maps, configs) and runs setup again. The label stays.

## Roles

| Type | Role | Runs | What it does |
|---|---|---|---|
| Computer | Mainframe | `mainframe` | Chat commands, alerts, island strip, status board for every machine, the butler (`$dump`, torch top-ups, warnings, welcomes, visitors, storage lock) |
| Computer | Storage | `storage` | Sorts input chests, touch screen, fuels the turtles, fills Weaver's barrel, does the smelter's item moves |
| Computer | Smelter | `smelter` | Auto-smelting rules (`smelt.txt`), fastest furnace tiers first, training furnace for new recipes; asks storage to move the items |
| Computer | Foreman | `foreman` | Mining control: overview of every Canary, tap one for its layers / START / DOCK / position / retire; hands out Canary numbers; layer presets (Y range + chunk rings) edited on the Presets page or with `/presets` on its screen; Reboot / Reboot all / `/reboot` (a Canary finishes its block, reboots, updates and carries on) |
| Computer | Nether Foreman | `nether` | In the Nether by Firecrest's dock: Firecrest cards (layers / START / DOCK / reboot / retire), the Nether barrels (`/assign`: dock, output home, stock, input), Rules for what stays in the Nether, what Firecrest throws away and when he drinks lava |
| Computer | Farmhand | `farmhand` | Control screen for the farm turtles: overview of Partridge, Woodpecker and friends, tap one for ROUNDS NOW / PAUSE / RE-MAP / FOUND / REBOOT, live settings, position, last haul and running totals |
| Computer | Architect | `architect` | Weaver's control screen (no monitor, the computer's own screen): what he's doing, a map of the layer he's on (done / to do / gaps / him / his next block), the island from the side, materials left vs storage, where the test markers went, a log, and build / stop / test / clear / reboot orders (typed or clicked) |
| Computer | GPS host | `gps_host` | One of 4 GPS towers so turtles know their exact X/Y/Z |
| Computer | Plastic factory | `plastic` | Industrial Foregoing plastic line: tree taps -> Latex Processing Unit -> furnace -> dock barrel (`plastic.env`) |
| Computer | Neural lab | `neural` | Hostile Neural Networks wall: runs each chamber + fab column until storage has enough of what it makes (`neural.txt`, `neural.env`) |
| Computer | Art controller | `art` | Monitor wall: live turtle map coloured by height, GPS pylons, generative art you can poke (`art.env`) |
| Computer | Cartographer | `cartographer` | Holds the whole world map Seagull finds and draws it on a floor-size monitor, with its own panel and floppy spill-over (`cartographer.env`, `docs/systems/cartographer.md`) |
| Turtle | Miner | `miner` | One miner, named by the dimension he's set up in. **Canary** (anywhere but the Nether/End): shaft + expanding squares, `junk.txt`, dump + fuel barrels, numbered Canary-01... by the Foreman. **Firecrest** (Nether): one dock barrel, drinks lava with his bucket (under 25% until 75%), numbered by the Nether Foreman. **Starling** (End): a Canary in the End. All of them empty chests before digging them and never dig turtles, cables, barrels or hoppers |
| Turtle | Weaver | `weaver` | Builds from a plan file (`mossy.plan`, put on him by hand: it's big); run from the Architect or `island weaver ...` in chat. If storage runs out of a block he leaves a gap, builds everything else he can (never on top of a gap) and fills the gaps when the block turns up. A chunk controller in his bag keeps his own chunk loaded (same swap as the miners) |
| Turtle | Woodpecker | `lumberjack` | Tree farm: maps a slab-ringed zone, plants a tree grid, chops and replants on a timer (`woodpecker.env`) |
| Turtle | Partridge | `farmer` | Crop farm: harvests and replants any crop, hoes new soil, picks up what falls (`partridge.env`) |
| Turtle | Seagull | `seagull` | Flies over the island with a Geo Scanner and sends the map to the Cartographer (`seagull.env`) |
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
- **Storage:** a wired modem on the storage cable (barrels, drawers, input/output chests), its own monitor for the touch screen, then `/assign` on its computer to say which inventory does what.
  - **`/assign`** lists every inventory with a job: Input (any number), Output, Dock, Canary fuel, Weaver supply, Pocket dump, Pocket restock, Drawers, Ignore. Click one to change its job, give it a nickname ("Nether chest") or delete it. **+ Add** shows every unassigned inventory on the cable with what's in it: type part of its network name (`barrel_74`, `drawer`, `ender`) and the list narrows, Enter picks the last one left. Or **Find it**: drop one item into the chest you mean. Everything not on the list is storage. `/setup` with marker items still works and adds to the list.
  - **Drawers first:** new items go to a drawer already holding them (if it has room), then an empty drawer (the smallest one big enough for that item's whole pile, so big drawers stay free for big piles), and only then to barrels. **`/tidy`** redistributes everything: items ranked by *stacks* (100 lava buckets = 100 stacks beats 101 cobble) get the drawers biggest-first, each taking just enough drawers for its whole pile, and the smallest piles go to barrels when drawers run out. Items already in the right size of drawer stay put, so a second run moves nothing. The first run can take a few minutes; sorting pauses meanwhile. Unlock drawers first: a locked drawer can't be given to another item.
  - **Wired modems won't go on chests here:** feed a chest into a barrel with a hopper (chest > hopper > barrel) and put the modem on the barrel. The barrel is the Input.
- **Smelter:** just a wired modem on the **same** storage cable, with the furnaces on that cable too. No wireless modem needed: it talks to storage over the cable, and storage passes its news to the mainframe. Storage is the only computer that moves items, so they never fight.
- **Smelter screen:** an advanced monitor touching the computer (3 wide x 2 tall is ideal) shows the array (fastest tier first), the rules and the trainer. **Training furnace:** put one furnace somewhere out of the way on the storage cable, tap TRAIN > PICK THE TRAINER (or Find it, then drop an item in). Put a raw item in its top slot, tap TRAIN, then pick a rule for what came out.
- **Mainframe:** Environment Detector, optional Chat Box, monitor wall (island strip + status board, plus a visitor column when the wall is at least 50 characters wide; a wall 120x60 or bigger shows three columns, see `docs/systems/mainframe.md`). For the butler: an **Inventory Manager** with your bound Memory Card and a **Player Detector**, both touching the mainframe.
- **Where the butler's items go:** the Inventory Manager can only move items into a chest it can reach, so the modem the mainframe's blocks sit on must be **joined to the storage cable**. Then `$dump` goes straight into storage's main input chest and torch top-ups come out of storage's output chest (or a dedicated restock chest: `/assign` it as Pocket restock on storage). That's the default (`POCKET_DUMP=storage`, `POCKET_RESTOCK=storage`). A chest touching the manager also works: `$pocket dump <side>`.

## The butler (mainframe)

- `$get [n] <item>`: straight from storage into your inventory (`$get 32 iron ingot`, `$get torches`; no number = one stack; a vague name lists the options).
- `$dump`: everything except your hotbar goes to storage (armour and offhand stay). `$pocket`: what the manager sees, to check the hotbar slots (`HOTBAR_FIRST`).
- Torches: under 10 on you, storage tops you back up to 64 (any item, any numbers: `TORCH_ITEM`, `TORCH_MIN`, `TORCH_FILL`).
- Private warnings: inventory nearly full / full; armour or a tool at 15% and again at 5%.
- Player Detector: "welcome home" (with who dropped by), guests greeted, a visitor column on the wall, and the **storage monitor locks** (big padlock, taps ignored) while you're away. The storage computer's own screen always works. `/lock` and `/unlock` on storage do it by hand. If the mainframe goes quiet for a minute, the auto-lock lets go.
- Settings: `butler.env` on the mainframe, made on first run. Edit it live; deleted keys come back with their defaults, your lines are never overwritten. The Inventory Manager only works while you're online.
- **Foreman:** advanced computer, **ender modem** (reaches Canaries anywhere), advanced monitor touching it (any size; the computer's own screen works too).
- **Farmhand:** advanced computer, wireless or **ender modem**, advanced monitor touching it (any size; the computer's own screen works too).
- **GPS hosts (optional, recommended):** 4 computers with ender modems, high up and not all at one height. Canaries then check their position against GPS, notice if they've been carried somewhere, and find their own way back. Farm turtles pin their farm map to GPS and can't get lost.
- **Each Canary:** pickaxe + ender modem, a dump barrel (storage input) and a fuel barrel next to its dock. Storage `/assign` each fuel barrel as Canary fuel (or `/setup` with a lava bucket in each; Canaries also link their own barrels); storage keeps one refill in every one, but never takes its last stack of coal/charcoal (the smelter needs it).

## Plastic factory

Everything for plastic in one building, run by one computer (role **Plastic factory**).

- **Its own wired cable.** Don't join it to the storage cable: storage would treat the latex machines as storage barrels and the smelter would grab the factory's furnace.
- On that cable, each with a wired modem (right-click it, red ring):
  - **Tree Fluid Extractors** ("taps"), each facing away from a log (it drains the block behind it). Power makes them 3x faster. Acacia and mangrove give the most latex (4 mB a pull), oak/birch/spruce/jungle 2.
  - **Latex Processing Unit(s)** with power. 750 mB latex + 500 mB water = 1 dry rubber.
  - **Water:** any tank or block holding water (an infinite water source is ideal). Or skip it and fill the unit's 16 B water tank with buckets now and then.
  - **Buffer tanks (optional):** any other tank soaks up latex while the units are full.
  - **A furnace** (vanilla or Iron Furnace) for dry rubber -> plastic.
  - **The dock barrel:** plastic goes out here, furnace fuel comes from here. Give it a **second** wired modem on the **storage** cable and `/assign` it as a Dock on storage: storage then takes the plastic away and keeps ~32 coal in it. Now nothing needs feeding by hand.
- A monitor touching the computer shows the units' latex / water / power bars, every tap, the furnace and the dock. Tap **PAUSE / RUN** in its corner.
- **Taps wear out the log:** each pull has a 1% chance to wear it; about 8 wears turn it into a stripped log (still gives 1 mB a pull), then air. A tap that stops giving latex shows **DRY** and raises an alert: put a new log behind it.
- With a wireless/ender modem it's on the mainframe's board, raises alerts, and answers `island plastic` (`island plastic pause | go`).
- No furnace (or `FURNACE=no` in `plastic.env`)? Dry rubber goes to the dock instead; add `plastic all` to `smelt.txt` and the smelter makes it.
- Terminal commands (slash optional, `/help` lists them): `/status`, `/list` (what it found on the cable), `/pause`, `/resume`, `/home`. Settings in `plastic.env` (same rules as `butler.env`): `DOCK` (if there's more than one chest on the cable), `FURNACE`, `STALL_AFTER`, `WATER_LOW`, `TICK`.
- If a machine's tanks or slots don't show up, open it and check its side settings (the coloured face buttons): the face with the modem must not be switched off.

## Neural lab (Hostile Neural Networks)

A wall of **columns**, one per mob: a **Simulation Chamber** on top, **its Loot Fabricator** underneath, and optionally a lamp. One computer (role **Neural lab**) runs them all.

- **Cable: either way works.**
  - **On the storage cable** (simplest): no dock needed. Drops go straight into storage's main input chest, and the lab asks storage for matrices and Furnator fuel, which storage puts directly into the chambers and Furnators. Storage never treats the lab's machines as storage.
  - **Its own cable:** then it needs the dock barrel below.
- **Each column:** chamber, fab, and the modems that join them to the lab cable. Full-block wired modems behind the wall work well. Right-click each modem (red ring).
- **Lamp (optional):** a **Redstone Relay** (CC:Tweaked) or AP **Redstone Integrator** touching a modem, with any lamp touching the relay. The relay switches on every side, so a flush wall works: lamp in the middle row, relay behind it between the two modems. **Steady** = running, **off** = stopped (target reached or switched off), **blinking** = needs you.
- **Power** goes to the chambers and fabs separately (power cables or Flux Points): wired modems don't carry FE. Each chamber stores 2M FE and each fab 1M, so a new column drains your cell once while it fills.
- **Dock barrel** (own cable only) on the lab cable with a second modem on the storage cable. On storage: `/assign` it as a Dock, then Keeps: `prediction_matrix 64`. Drops and generalized predictions leave through it; matrices and Furnator fuel come in.
- Optional on the lab cable: **energy cell(s)** (the lab reads stored power from them) and **Powah Furnator(s)**.
- A **wireless/ender modem** on the computer: it gets item counts from storage and reports to the mainframe.

**How it runs**
- The **data model lives in its chamber for good** (the mod won't let a computer take it out). Put it in by hand.
- **Pick the drop in each fab's own screen.** The lab learns what a fab makes from its output.
- `neural.txt`: how many of each item to keep, e.g. `blaze_rod 512`, `ender_pearl 256`, `end_crystal off`. Items with no line: `DEFAULT_KEEP` (256). A column runs until storage has that many, then stops, and starts again under 90% (`RESTART_AT`).
- **On** = it drips matrices into the chamber one at a time and feeds predictions to its fab two at a time. **Off** = it stops adding them; the chamber finishes its run and idles (idle machines use no power).
- **Switched a fab's drop?** A running column notices on its next batch. For a stopped one, tap **CHECK** on its card: it sends one banked prediction through. It also checks by itself after 15 min, then less and less often while nothing changes (up to every 4 h); each check is one batch.
- **New columns are picked up by themselves.** Chambers, fabs and lamps are paired in the order they were connected, and a pair sticks (a replaced fab joins the chamber that lost one). Wrong pair? `PAIRS=` in `neural.env`, e.g. `PAIRS=3:5:2` (chamber 3, fab 5, lamp 2; `/pairs` on the terminal shows the numbers).
- **Power:** solar first. The Furnator gets charcoal/coal while your cells, or **any one chamber**, are under 30% (`FUEL_BELOW`): power doesn't spread evenly, so the chamber furthest from the generators can starve while the rest are full. The header then names it (`sim #2 0%`). Under 10% (`LOW_POWER`) only the column furthest below its target runs.
- Leave the chamber on **Inference** and both redstone settings on **Ignored**. A chamber on Training uses matrices and makes nothing: the lab flags it.
- **Screens** (monitor and terminal, `docs/systems/neural.md`): a tile per column (state, item stock/target, accuracy, CHECK). Tap a column for its page: target stepper (edits `neural.txt`), **AUTO / ON / OFF**, CHECK, stats. **Pause / Run** and **Check all** on the bottom row.
- **Terminal commands** (slash optional, `/help` lists them): `/status`, `/list`, `/pairs`, `/column <n>`, `/check <n>`, `/on <n>`, `/off <n>`, `/auto <n>`, `/target <n> <count>`, `/pause`, `/resume`, `/home`.
- **Alerts** (mainframe): out of matrices, no power, chamber stuck or on Training, fab with no drop picked, dock full, no counts from storage. Chat: `island neural`, `island neural pause | go`.
- **Tip:** level a model with the Deep Learner (kills) rather than Training mode (one matrix per run). With the mod's default numbers that's about 100 kills from blank to Self Aware.

## The art wall (art controller) and the map room (Cartographer + Seagull)

**Art controller:** an advanced computer, an ender modem, and the biggest **advanced** monitor you can build touching it
(an 8x6 wall = 328 x 243 pixels: every character cell is split into 2 x 3 little pixels). Tap the **three bars in the
bottom-right corner** to switch screens:

- **Turtle map:** every turtle that knows its GPS position, as a dot coloured by height (14 bands from Y -64 to 320,
  key on the right), with a trail of where it's been. Canaries, Partridge, Woodpecker, Weaver and Seagull all report one now.
  The **GPS pylons are red crosses**: the wall asks the GPS towers where they are, so new pylons appear by themselves.
  Tap a turtle for its details, tap anywhere else to move the map there, **-** / **+** to zoom, **FIT** to follow everyone again.
  Turtles in the Nether or End aren't shown.
- **Art: Plasma, Rings, Aurora:** generative art. Tap to send a ripple out from your finger. A fresh pattern every
  time it's picked, and again after 10 minutes without a tap.
- Goes back to the Turtle map after 5 minutes without a tap (`DEFAULT_VIEW`, `IDLE_RETURN`), or set `CYCLE=60` to
  rotate through every screen when nobody's touching it. Other settings in `art.env`: height bands, trail length, FPS.
- Its terminal: `1`-`4` switch screens, `Q` stops it (the monitor's colours go back to normal).

**Cartographer:** an advanced computer, an ender modem and a big advanced monitor laid flat as a floor. It keeps the
whole world map (the World map used to live on the art wall) and draws it with pan and zoom; its own screen has Seagull's
panel, the next region, storage and the MAP / DOCK buttons. Read `docs/systems/cartographer.md`.

**Seagull (map-making turtle):** a turtle with a **Geo Scanner** on one side, an **ender modem** on the other and an Advanced
Peripherals **chunk controller** in his bag. No pickaxe: he never digs, he flies over things. Needs the GPS towers.

- **Dock:** a barrel touching him that storage keeps fuelled. On storage: `/assign` the barrel as a Dock, Keeps e.g. `coal 128`
  in it (fewer trips home than the default ~32). **Open sky above his dock spot**: he leaves and lands straight up and down.
- First start: put him on his dock spot and start him. He finds the barrel, steps once to learn which way he faces, and waits.
- Press **MAP** on the Cartographer (or **M** on his screen). He maps **one region** (16 x 16 chunks) chunk by chunk, `CLEARANCE`
  (3) blocks above the ground: one radius-8 scan from each chunk's middle covers the whole chunk, plus a second scan only where a
  cliff or pit left columns unseen. In every chunk he swaps the chunk controller onto his modem's side for a moment, so the chunk
  stays loaded and nothing is skipped. The region shows up on the Cartographer in one go when it is whole; he then forgets his copy
  and docks. **MAP again = the next region**: the one tapped on the Cartographer, else the next one in a spiral out from home.
  He goes home for fuel when he needs to and carries on with the same region. **D** on his screen = dock.
- Restarted mid-region? He asks GPS where he is and carries on from his last checkpoint (at most 8 chunks are scanned again).
- The old fixed area (`CENTRE_X`, `CENTRE_Z`, `WIDTH`, `DEPTH`, `STEP`, `STRIP`) is gone; leftover lines in `seagull.env` do nothing.
- The Cartographer keeps the map (`regions/` on its disk and floppies) and catches up from Seagull's (`seagull.map`)
  whenever it starts. On the mainframe's board the Cartographer has one row (Seagull's state, regions held, fuel).

## Farm turtles and the Farmhand

Partridge (crops) and Woodpecker (trees) run on one shared engine (`shared/farmbot.lua`).

- **Farm:** ring the area with slabs: on the ground for Woodpecker, at crop height for Partridge (he flies one block above the
  crops). Start the turtle inside it next to its dock barrel (Partridge can also start ON a dock built into the ring, facing
  in). Make the barrel a storage dock (`/assign` it as a Dock, or the coal marker in `/setup`): storage takes the produce and keeps fuel in it.
- **It maps the farm by itself** and re-maps every few rounds (`RESURVEY_EVERY`), so new rows or a bigger field get picked
  up. Woodpecker keeps his tree grid on re-maps. A map that fails (gap in the slabs, no fuel) is retried every few minutes.
- **Never lost with GPS:** the map is pinned to world coordinates. After a restart, even one mid-turn, it asks GPS where it
  is and steps once to learn which way it faces; at home after every round it checks GPS agrees with its count. Carried off
  the farm? It says where it is and where home is; put it back and press **Found** (or `island partridge found`). Without GPS
  it works its way out from the map, like before.
- **Settings:** `partridge.env` / `woodpecker.env` on the turtle, edited live. Round timer, seeds/saplings kept and how often it
  re-maps can also be changed from the Farmhand (yellow until the turtle confirms).
- **Farmhand screen:** a card per turtle (state, fuel, next round or progress, position). Tap one for ROUNDS NOW, PAUSE/GO,
  RE-MAP, FOUND (when lost), REBOOT (it finishes its job, restarts, updates), settings, last haul and everything it has
  brought in. Footer: Rounds all, Pause all, Reboot all. A turtle silent for 2 minutes can be forgotten.
- **Still on the mainframe:** every farm turtle keeps its row on the board (round progress, last round, fuel) plus a
  Farmhand row; alerts and chat (`island partridge rounds|survey|stop|go|found`) work as before.
- **ATM10 note:** with a hoe, CC:Tweaked right-clicks a crop before digging it, and ATM10 harvests ripe crops on right-click,
  dropping them on the ground. Partridge hoovers up under him at every plot.

## One miner, three birds (Oct 2026)

Canary, Firecrest and Starling are the same program (`turtle/miner/miner.lua`, `miner` on the turtle). Setup picks
**Miner** and asks the dimension first; that decides who he is:

| Dimension | Name | Boss | Dock |
|---|---|---|---|
| Overworld, mining dimension, anything else | Canary-NN | Foreman (`tanis-miner`) | dump barrel + fuel barrel, `junk.txt` |
| The Nether | Firecrest-NN | Nether Foreman (`tanis-nether`) | one barrel + one empty bucket; drinks lava |
| The End | Starling-NN | Foreman (`tanis-miner`) | dump barrel + fuel barrel, like a Canary |

A numbered miner whose label names a different bird than his dimension relabels himself on boot (Firecrest-01,
Starling-04). The Foreman numbers Canaries and Starlings from one list. In the End storage can't reach his
barrels, so a Starling doesn't try to link them: fill his fuel barrel by hand, and send his dump barrel home the
Nether way (barrel > hopper > ender chest). Lowest level he'll mine: Y -63 (Canary), Y 6 (Firecrest, bedrock under
Y 5), Y 1 (Starling, void under Y 0).

## Chunk by chunk (CBC), chunk controllers and shulker boxes (Oct 2026)

Every miner works **one chunk at a time**: all the levels of a chunk (down through them in one chunk, up
through them in the next), a snake over its 16x16 on each level, then the next chunk. His area is **chunk
rings** round his dock's chunk, set on his Foreman page (and in presets): ring 0 = the dock's chunk, ring 1
= the 3x3 round it, ring 5 = 11x11 chunks. Saved block rings were converted once (50 blocks -> ring 3).

- **No chunk controller:** force-load his dock's chunk (FTB Chunks). A force-loaded chunk keeps the 8 chunks
  round it running too, so rings 0-1 (3x3 chunks) work off that one chunk. Further out he'd stop as soon as
  he left them, so the Foreman warns "Past ring 1: needs a chunk controller".
- **With a chunk controller** (Advanced Peripherals, `advancedperipherals:chunk_controller`: iron, redstone,
  an eye of ender) in his bag: whenever he steps into a new chunk, and every 45 s, he swaps it onto his
  modem's side for a moment. That force-loads the chunk he's in and drops the last one, so he only ever
  holds **one** chunk, and it stays loaded after he swaps back (the mod keeps it ~10 min). It survives server
  restarts. Any area size, no FTB chunks needed (still force-load his dock and the Foreman so you can reach them).
  Needs `enableChunkyTurtle` on in the server's Advanced Peripherals config (it is by default).
- **With a shulker box** in his bag (vanilla, or a Sophisticated Storage one: those upgrade to huge, with
  stack upgrades): when he's down to 2 free slots he puts it down above, below or behind him, puts his ore in
  and digs it back up. He only comes home when the box is full too. At the dock he unpacks it into the barrel
  (it goes in the top of his shaft for that). Backpacks can't do this: turtles can't sneak to place them.
- His gear (controller, modem, box, Firecrest's bucket) never gets unloaded, stashed or thrown away.
- **Weaver** does the same swap with a chunk controller in his bag (he flies all over the build site), and
  never throws it out as junk or hands it back to storage; his material batches are one slot smaller for it.
- The Foreman page shows `Chunk 3 of 49, ring 1` and `Gear  loader + box` (or `box FULL`).

## Chests underground

Every miner empties a chest (dungeon, mineshaft corridor, fortress, bastion, stronghold, end city...) **before**
digging it, since a dug chest drops its loot on the floor and he'd walk on. A chest just above or below his tunnel
gets emptied and left standing. Loot always comes home and is never thrown away to make room, except things on
his junk list (netherrack in a fortress chest is still netherrack). Too full to take it all: he goes home,
unloads and comes back to that chest for the rest. The Foreman status carries `chests` (how many he's emptied).

He never touches **barrels, hoppers, ender chests** (vanilla and Ender Storage) or Functional Storage /
Sophisticated Storage / Storage Drawers blocks: he goes round them like a cable. That's how your own storage is
wired, and natural loot underground is in chests. A chest of yours inside a mining area **will** be emptied (the
contents come home) and dug, so keep chests out of the rings or swap them for barrels.

## Canaries and the Foreman

- **Numbers:** a new Canary asks the Foreman for one when it first starts (Canary-01, -02...). It keeps it when moved or reset. **Retire** (tap twice on its page) docks it for good; its number is never handed out again.
- **Position:** set up at its dock, it learns X/Y/Z (from GPS, or typed in), which way it faces and the dimension, and reports where it is all the time.
- **Carried off?** With GPS it notices on restart, works out which way it faces by stepping once, and waits. Press START or DOCK on its Foreman page: it digs down to Y 0, tunnels under everything to its shaft and comes up. Put it down outside, not on a floor you care about. Without GPS it counts its moves, so carry it back to its dock instead.
- **Older Canaries** fill in their dock's X/Z and facing by themselves on the first boot with GPS, or ask once on their screen without it.

## Firecrest and the Nether Foreman

Firecrest mines the Nether and his haul comes home through a linked ender chest.

- **Firecrest:** an **advanced** mining turtle (diamond pickaxe) with an **ender modem**, and **one empty bucket** in his inventory. Set him up (startup.lua, pick Miner, answer "Nether") on top of where his shaft should go, with **one barrel** next to him (a side or above): his dock. He asks for his X/Y/Z and facing (F3) unless there's GPS in the Nether.
- **The Nether cable:** a wired modem on the Nether Foreman computer, joined by cable to wired modems on: Firecrest's **dock** barrel, an **output** barrel, and one or more **stock** barrels (optional: **input** barrels to drop things in by hand). On the computer: `/assign` (or the Barrels button) and give each its job, the same screen as storage's.
- **Getting it home:** output barrel > hopper > Ender Storage ender chest (orange/orange/orange). Its twin at home feeds storage the same way: ender chest > hopper > a barrel that's a storage Input. A hopper moves ~150 items a minute; a Pipez item pipe is quicker if it ever backs up.
- **What goes where:** everything Firecrest brings (and anything in an input) goes to stock if the Rules keep some of it and stock is short of that; the rest goes home. Stock above its keep count goes home too. Defaults keep 4 buckets, 16 lava buckets and some coal / charcoal / coal blocks / blaze rods for emergencies. `/keep <item> <count>` (0 = stop), or the - / + / x buttons on the Rules page.
- **Fuel:** under **25%** he scoops every lava source he sees with his bucket and drinks it (1,000 each); finding one, he drinks the whole pool around him (only the lava cells, on his own level, inside his rings) until he's over **75%**, then leaves lava alone. Both numbers are on the Rules page. Running low with no lava about, he comes home and the dock gives him lava buckets / coal from stock. No bucket? The dock gives him one from stock.
- **Junk:** the Rules page lists what he throws away underground (netherrack, basalt, blackstone...); everything else comes home. `/junk <item>`, `/unjunk <item>`.
- **Chunk loading:** force-load Firecrest's dock and the Nether Foreman's chunk (FTB Chunks). That's enough for chunk rings 0-1 (3x3 chunks, the default). For more, give him a chunk controller (see Chunk by chunk). An unloaded Firecrest just stops and carries on when it loads again. Force-load the island base too if you want storage sorting while you're away.
- **The mainframe** hears Firecrests through its ender modem: they show on the status board, in `island miner` and in the alerts like Canaries.

## Renamed turtles (Oct 2026)

The turtles are birds now: Canary (miner; Firecrest in the Nether, Starling in the End), Weaver (builder), Woodpecker (lumberjack),
Partridge (farmer), Seagull (map-maker). Nothing to do by hand: on its next boot each turtle switches its role, its
label (Digger-04 becomes Canary-04), and its saved state and `.env` settings over to the new name, and drops its old
program files. The Foreman, Nether Foreman and storage carry their saved settings over too. Chat commands use the new
names (`island weaver build`, `island partridge rounds`).

## Miners never dig turtles

ComputerCraft lets a turtle mine another turtle (it turns into an item in the digger's bag). Canaries, Firecrests and Starlings
never do: a turtle in the way makes them wait up to 2 minutes for it to move on (status "Another turtle in my way"),
and a turtle item they pick up always comes home rather than being thrown away underground.

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

No false alarms from `reset`, re-running setup, `label set`, Canaries naming themselves, or crafting a computer
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
