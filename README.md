# atm10-turtlemancer

ComputerCraft (CC:Tweaked + Advanced Peripherals) scripts for Tanis's ATM10 island: the base computer
(island station, storage, miner panel) and the turtles Digger, Rigger, Tigger and Figger.

## Setting up a machine (once)

Label it first if it's a turtle (`label set Digger`), then run:

```
wget run https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/install.lua
```

It installs the self-updating `startup.lua` and reboots.

## Updating

Reboot the machine (hold Ctrl+R). On every boot `startup.lua` pulls that machine's latest files from
`main`, then starts its program. GitHub's raw links can cache for about 5 minutes after a push.

## Who gets what

| Label | Role | Files |
|---|---|---|
| any computer (not a turtle) | base | `base.lua`, `island.lua`, `storage.lua`, `miner_panel.lua`, `rigger_link.lua`, `farm_link.lua`, `smelt.txt`* |
| Digger | miner | `miner.lua`, `junk.txt`* |
| Rigger | rigger | `rigger.lua`, `mossy.plan`* |
| Tigger | lumberjack | `lumberjack.lua` |
| Figger | farmer | `farmer.lua` |

\* only downloaded if missing, so your edits are kept. Labels match on the first word, so `Digger-2`
works. A `role.txt` file containing a role name overrides the label.

If GitHub can't be reached, or a file is broken (empty, or a `.lua` that doesn't compile), the old
file is kept and the machine boots anyway. State files (`*.state`, `*.cfg`, `*.zone`) are never touched.

Test
