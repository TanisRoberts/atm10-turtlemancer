# atm10-turtlemancer: project instructions

CC:Tweaked scripts for Tanis's island base in All the Mods 10. Computers, turtles and smart glasses all run from this repo.

## Delivery: main is production

- Every device pulls its files from `main` on each boot, as listed in `manifest.lua`. **Pushing to main is shipping.** Nothing else delivers a change.
- `startup.lua` is the only file placed on a device by hand. A new or moved file needs its `manifest.lua` entry, or no device will download it.
- A `.lua` file that doesn't compile is refused on the device, which keeps the old copy. Compile-check every changed file before pushing.
- GitHub's raw CDN caches `main` for up to 5 minutes. Tell Tanis to wait about 5 minutes, then reboot (hold Ctrl+R) the named devices.
- Several sessions can run at once, so engineers work on their own branch (`eng/<issue-number>-<short-name>`), never directly on `main`. When the work is done and compile-checked: `git fetch origin main && git rebase origin/main`, re-run the checks, then `git push origin HEAD:main` to merge it (that ships it). Delete the branch afterwards. Never force-push `main`.

## How work flows

Work is tracked in GitHub Issues. Read `docs/workflow.md` once per session. Roles (PM, design, engineering) start from the prompts in `docs/team/prompts/`. One issue per session; hand over in issue comments, not in chat.

## Reading the code cheaply

Most files are big (smelter 109 KB, storage 88 KB, miner 74 KB, nether 72 KB, neural 63 KB, weaver 58 KB, README 37 KB). **Never read a big file whole.** Grep for the function or message you need and read around it with an offset and limit. Read `docs/systems/<system>.md` when it exists before touching that system. New code goes in modules under `shared/` (or a role's own folder), not into the monoliths.

## Layout

- `startup.lua setup.lua reset.lua manifest.lua`: boot, first-time setup, wipe, and which files each role gets.
- `computer/<role>/`: mainframe (island strip, status board, butler, links to every other system), storage (the only computer that moves items in or out of storage), smelter, foreman (Overworld miners), nether (Nether Foreman), farmhand, architect (Weaver's controller), gps, plastic, neural, art.
- `turtle/<role>/`: miner (one program, named by dimension), weaver (builder), woodpecker (lumberjack), partridge (farmer), seagull (cartographer), bowerbird (crafter).
- `glasses/hud/`: smart glasses HUD.
- `shared/`: modules used by several roles (farmbot, assignui, mapchunk, weaverplan).
- `docs/`: workflow, team prompts, design specs, per-system notes.

## Names

- Turtles are birds. Miners are named by dimension: Canary (Overworld), Firecrest (Nether), Starling (End). Weaver builds, Woodpecker chops, Partridge farms, Seagull maps, Bowerbird crafts. Old "-igger" names (Digger, Pigger, Rigger, Tigger, Figger, Zigger) are aliases in `manifest.lua` only. Don't reintroduce them.
- Labels are role plus number, like `Canary-04`. The controller hands out numbers, and a retired number is never reused.

## Facts about the server (don't relearn these)

- ATM10 8.2 on NeoForge 21.1.251, Minecraft 1.21.1. CC:Tweaked 1.120.2 (CraftOS 1.9) and Advanced Peripherals 0.8.1a. **Every mod and version is in `docs/mods.md`**: check it before relying on a mod's API.
- Advanced Peripherals 0.8 peripheral types are snake_case (`chat_box`, `player_detector`, `environment_detector`). Use the 0.8 docs (IntelligenceModding/Advanced-Peripherals-Documentation, branch `0.8`), not 0.7. Mod source settles anything vague: AdvancedPeripherals branch `release/0.8-1.21.1`, CC-Tweaked branch `mc-1.21.x`.
- Tanis uses advanced computers only. Every computer's monitors touch one of its sides; scripts use those, never monitors on the cable.
- **Wired modems don't connect to chests here.** Wire a chest as chest → hopper → barrel, with the modem on the barrel. Suggest barrels for anything on a cable.
- **No datapacks** can be added to the server. No datapack-based fixes, like custom turtle tool upgrades.
- FTB Chunks allows 25 force-loaded chunks. Miners mine chunk by chunk and swap an Advanced Peripherals chunky upgrade onto their modem slot.
- A Functional Storage controller gets one modem. Modems on its drawers too would count every item twice.
- `pushItems` and `pullItems` move at most one stack per call.
- Tunables live in auto-generated `.env`-style files on each device: missing keys are appended, existing lines are never overwritten.
- **Leaves break instantly** (a mod on the server) as soon as no log is left around them, and drop their items at once. Don't cut or wait for leaves to rot: remove the logs and the leaves clear themselves.
- Fuel = ticks = time: a move saved is both fuel and time saved.
- Turtles must never dig another turtle, a network cable or pipe, or a loot chest. Chests are emptied before they're dug.

## Testing

- `pip install --break-system-packages -q lupa` gives Lua 5.2 (same as CraftOS). Then `python3 tests/run.py` compile-checks every `.lua` and runs every scenario in the CraftOS simulator (`tests/sim/`); `python3 tests/run.py storage` runs one system's scenarios. Run it before every push to main.
- The simulator runs the real programs on a virtual clock: computers, turtles in a voxel world, wired networks, rednet, monitors with touch, inventories, furnaces. `tests/README.md` says how to add a scenario. Extend the mocks and scenarios; don't write a throwaway harness in a scratchpad.
- Check anything you can in the sim before Tanis has to test it in game.

## Finishing a change

Push, then comment on the issue: what changed, which devices to reboot, and anything Tanis has to do in game (an `/assign`, a block to place), as numbered steps. Only hand the issue to Tanis (`for: tanis`, `status: test in game`) if there are such steps; otherwise close it. Keep it short.
