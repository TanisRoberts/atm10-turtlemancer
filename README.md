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
| Turtle | Digger | `miner` | Shaft + expanding-square mining (`junk.txt`); numbered Digger-01, -02... by the Foreman; reports its exact position |
| Turtle | Rigger | `rigger` | Builds from a plan file (`mossy.plan`) |
| Turtle | Tigger | `lumberjack` | Tree farm |
| Turtle | Figger | `farmer` | Crop farm |
| Glasses | HUD | `glasses` | Smart Glasses: night vision + heads-up display (for now: a module report saved to `glasses_report.txt`) |

Every role is defined in `manifest.lua`: its files live under `computer/<role>/`, `turtle/<role>/` or `glasses/<role>/`
and land on the device under their own names. Adding a role = adding its folder and one manifest entry.

## Smart Glasses

- Advanced Peripherals Smart Glasses (incl. Netherite Reinforced) are a pocket computer you wear. Right-click them in your hand to open the terminal.
- Setup only offers the Glasses type on actual glasses (it checks for the `smartglasses` API), and pre-picks the HUD role.
- Wear them (head or Curios slot) when they boot: the `smart_glasses` peripheral only shows up while they're equipped.
- Reboot from the glasses' terminal (hold Ctrl+R) to pull new versions.

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

## Diggers and the Foreman

- **Numbers:** a new Digger asks the Foreman for one when it first starts (Digger-01, -02...). It keeps it when moved or reset. **Retire** (tap twice on its page) docks it for good; its number is never handed out again.
- **Position:** set up at its dock, it learns X/Y/Z (from GPS, or typed in), which way it faces and the dimension, and reports where it is all the time.
- **Carried off?** With GPS it notices on restart, works out which way it faces by stepping once, and waits. Press START or DOCK on its Foreman page: it digs down to Y 0, tunnels under everything to its shaft and comes up. Put it down outside, not on a floor you care about. Without GPS it counts its moves, so carry it back to its dock instead.
- **Older Diggers** fill in their dock's X/Z and facing by themselves on the first boot with GPS, or ask once on their screen without it.

## Safety

If GitHub can't be reached or a download is broken (empty, or a `.lua` that doesn't compile), the old file is
kept and the device boots anyway. Files marked `once` in the manifest (`junk.txt`, `smelt.txt`, `mossy.plan`)
are only downloaded if missing, so your edits stay. `reset` won't wipe anything if it can't download setup first.
