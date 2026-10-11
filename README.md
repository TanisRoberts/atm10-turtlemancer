# atm10-turtlemancer

ComputerCraft (CC:Tweaked + Advanced Peripherals) scripts for Tanis's ATM10 island.

## Setting up any device

1. Drag `startup.lua` onto the computer or turtle (or `wget https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/startup.lua startup.lua`).
2. Reboot (hold Ctrl+R). Setup asks: turtle or computer, which role, and a label.
3. It reboots, downloads that role's files and starts.

**Updating:** reboot. Every boot pulls the device's latest files from `main` (raw GitHub links can cache ~5 min after a push).
**Changing a role:** type `reset`. It wipes the device (role, scripts, saved state, maps, configs) and runs setup again. The label stays.

## Roles

| Type | Role | Runs | What it does |
|---|---|---|---|
| Computer | Mainframe | `mainframe` | Chat commands, alerts, island strip, status board for every machine, miner panel |
| Computer | Storage | `storage` | Sorts input chests, touch screen, fuels the turtles, fills Rigger's barrel, does the smelter's item moves |
| Computer | Smelter | `smelter` | Auto-smelting rules (`smelt.txt`); asks storage to move the items |
| Turtle | Digger | `miner` | Shaft + expanding-square mining (`junk.txt`) |
| Turtle | Rigger | `rigger` | Builds from a plan file (`mossy.plan`) |
| Turtle | Tigger | `lumberjack` | Tree farm |
| Turtle | Figger | `farmer` | Crop farm |

Every role is defined in `manifest.lua`: its files live under `computer/<role>/` or `turtle/<role>/` and land
on the device under their own names. Adding a role = adding its folder and one manifest entry.

## Hardware for the base computers

- **Every base computer** needs a wireless or ender modem: they talk on the `tanis-base` network.
- **Storage:** a wired modem on the storage cable (barrels, drawers, input/output chests), its own monitor for the touch screen, then `/setup` with the marker items.
- **Smelter:** a wired modem on the **same** storage cable, with the furnaces on that cable too. Storage is the only computer that moves items, so they never fight.
- **Mainframe:** Environment Detector, optional Chat Box, monitor wall (island strip + status board), miner panel monitor.

## Safety

If GitHub can't be reached or a download is broken (empty, or a `.lua` that doesn't compile), the old file is
kept and the device boots anyway. Files marked `once` in the manifest (`junk.txt`, `smelt.txt`, `mossy.plan`)
are only downloaded if missing, so your edits stay. `reset` won't wipe anything if it can't download setup first.

Test
