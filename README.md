# atm10-turtlemancer

ComputerCraft (CC:Tweaked + Advanced Peripherals) scripts for Tanis's ATM10 island.

## Setting up any device

1. Drag `startup.lua` onto the computer, turtle or Smart Glasses (or `wget https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/startup.lua startup.lua`).
2. Reboot (hold Ctrl+R). Setup asks: computer, turtle or glasses, which role (click, or arrows + Enter; each role is described underneath), and a label. Diggers skip the label: the Foreman numbers them.
3. It reboots, downloads that role's files and starts.

**Updating:** reboot. Every boot pulls the device's latest files from `main` (raw GitHub links can cache ~5 min after a push).
**Changing a role:** type `reset`. It wipes the device (role, scripts, saved state, maps, configs) and runs setup again. The label stays.

## Roles

| Type | Role | Runs | What it does |
|---|---|---|---|
| Computer | Mainframe | `mainframe` | Chat commands, alerts, island strip, status board for every machine, the butler (`$dump`, torch top-ups, warnings, welcomes, visitors, storage lock) |
| Computer | Storage | `storage` | Sorts input chests, touch screen, fuels the turtles, fills Rigger's barrel, does the smelter's item moves |
| Computer | Smelter | `smelter` | Auto-smelting rules (`smelt.txt`); asks storage to move the items |
| Computer | Foreman | `foreman` | Mining control: overview of every Digger, tap one for its layers / START / DOCK / position / retire; hands out Digger numbers |
| Computer | GPS host | `gps_host` | One of 4 GPS towers so turtles know their exact X/Y/Z |
| Computer | Plastic factory | `plastic` | Industrial Foregoing plastic line: tree taps -> Latex Processing Unit -> furnace -> dock barrel (`plastic.env`) |
| Turtle | Digger | `miner` | Shaft + expanding-square mining (`junk.txt`); numbered Digger-01, -02... by the Foreman; reports its exact position |
| Turtle | Rigger | `rigger` | Builds from a plan file (`mossy.plan`) |
| Turtle | Tigger | `lumberjack` | Tree farm |
| Turtle | Figger | `farmer` | Crop farm |
| Glasses | HUD | `glasses` | Smart Glasses: night vision AUTO / ON / OFF and a HUD line (`glasses.env`) |

Every role is defined in `manifest.lua`: its files live under `computer/<role>/`, `turtle/<role>/` or `glasses/<role>/`
and land on the device under their own names. Adding a role = adding its folder and one manifest entry.

## Smart Glasses

- Advanced Peripherals Smart Glasses (incl. Netherite Reinforced) are a pocket computer you wear. Right-click them in your hand to open the terminal.
- Setup only offers the Glasses type on actual glasses (it checks for the `smartglasses` API), and pre-picks the HUD role.
- Wear them (head or Curios slot) when they boot: the `smart_glasses` peripheral only shows up while they're equipped.
- Reboot from the glasses' terminal (hold Ctrl+R) to pull new versions.
- **Night vision** needs the Night Vision Module (it's on by default when fitted). Modes, switched on the glasses' screen (click, or 1 / 2 / 3; H toggles the HUD, Q stops):
  - **AUTO**: on when the light where you stand is `NV_DARK` (7) or less, or you're in the Deep Dark; off again at `NV_BRIGHT` (10) or more. In between it keeps doing what it was doing, so torch-lit edges don't flicker. Needs an **Environment Detector** in the glasses; without one AUTO just stays on.
  - **ON** / **OFF**: always / never. While the module is switched off, night vision potions don't work either (that's the module).
- **HUD**: with an **Overlay Module**, a line in the top-right corner, under the potion effect icons, shows `NV AUTO: on` (green when on). Position: `HUD_CORNER` (top-right / top-left / bottom-right / bottom-left), `HUD_EDGE_X`, `HUD_EDGE_Y` (GUI pixels from the edges; it right-aligns itself to your screen size and GUI scale).
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
- **GPS hosts (optional, recommended):** 4 computers with ender modems, high up and not all at one height. Diggers then check their position against GPS, notice if they've been carried somewhere, and find their own way back.
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

## Diggers and the Foreman

- **Numbers:** a new Digger asks the Foreman for one when it first starts (Digger-01, -02...). It keeps it when moved or reset. **Retire** (tap twice on its page) docks it for good; its number is never handed out again.
- **Position:** set up at its dock, it learns X/Y/Z (from GPS, or typed in), which way it faces and the dimension, and reports where it is all the time.
- **Carried off?** With GPS it notices on restart, works out which way it faces by stepping once, and waits. Press START or DOCK on its Foreman page: it digs down to Y 0, tunnels under everything to its shaft and comes up. Put it down outside, not on a floor you care about. Without GPS it counts its moves, so carry it back to its dock instead.
- **Older Diggers** fill in their dock's X/Z and facing by themselves on the first boot with GPS, or ask once on their screen without it.

## Safety

If GitHub can't be reached or a download is broken (empty, or a `.lua` that doesn't compile), the old file is
kept and the device boots anyway. Files marked `once` in the manifest (`junk.txt`, `smelt.txt`, `mossy.plan`)
are only downloaded if missing, so your edits stay. `reset` won't wipe anything if it can't download setup first.
