# Foreman (Overworld)

The remote for every miner in every dimension (`computer/foreman/`). `foreman.lua` is the profile (title, protocol, presets, `remote = "hub"`, `screens`); the work is the Foreman engine in `shared/fm*.lua` (`docs/systems/miner.md`: registry, orders, radio, the link to the MD and Nether Foremen). `foreman_screens.lua` is everything it shows and takes typed, built only from the UI kit (`docs/systems/ui.md`); nothing in it writes to a terminal.

`shared/fm.lua` calls `P.screens(F)` after loading the engine parts. The screens module replaces the engine's `draw`, `inputLoop` and `say` on `F` (the engine calls them late-bound), and reads and orders through the engine: `F.live`, `F.entry`, `F.order`, `F.pick`, `F.adjust`, `F.requestReboot`, `F.retire`, `F.presetList`, `F.savePreset` ... The MD Foreman is not moved yet and still uses the engine's own drawing (`fm_draw`, `fm_pages`, `fm_edit`, `fm_cmd`); those four parts go when it moves. The Nether Foreman (`docs/systems/nether.md`) reuses this module: it fills `F.ext` first (hooks `header`, `statusLine`, `buttons`, `statusRows`, `pages`; listed at the top of `foreman_screens.lua`) and gets `F.kit` back.

## Screens

Each view (the computer's own screen and a monitor, which may differ in size) keeps its own page. The monitor is found by the engine's `findMonitor`; the view gets its peripheral name (`ui.view(mon, { side = name })`).

- **Overview:** `v:tiles`: a tile per miner (state, what it is doing, fuel, cargo and Y, last heard and dimension). Header: `FOREMAN`, the count and `storage ok`, and `ok` or the first problem (a dimension Foreman not heard, its output full, or `waiting` while none has been heard). Buttons: Presets, Reboot all, Dock all (tap twice), Retired (n) on 56+ wide. A miner silent for 15 s shows `lost`, greyed, "not heard 3m". No miners yet: a waiting spinner and what to do.
- **A miner (tap its tile):** on 44+ wide, status on the left (message, alerts, fuel and cargo bars, layer, chunk, range, position, dimension, dock, gear, whose Foreman, computer) and **Layers** on the right: the presets as a column (tap one to pick it), steppers for Min Y, Max Y and the two chunk rings, a hint line (chunk count, "Past ring 1: needs a chunk controller", "Sending...", "START to switch"), START, STOP + DOCK, Reboot, Re-dock, Retire (Reboot and Retire tap twice; Retire is permanent). Footer tabs Status / Haul. Narrower: tabs Info / Layers / Haul. Edit opens the presets of that miner's own Foreman. A retired miner has no layers or orders.
- **Presets:** a list of the selected Foreman's presets (mine, or with `Of:` an MD's or Nether's, sent to it as a `presets` remote command), buttons + New, Edit, Duplicate, Up, Down. A tap selects a row, a second tap opens it.
- **Edit preset:** Name field (type on the computer; a monitor shows it only), steppers, a line saying how many passes and rings it makes, Save, Cancel, Delete (tap twice). A bad one (no name, name taken, Min Y above Max Y, From ring past To ring) stays open with the reason.
- **Commands page** (`/help`): every command with its usage.

## Typed commands (computer only)

Through `shared/slash.lua`, with or without the slash, shown in the kit's command bar when `/` is typed. On every page of the computer's own screen.

| Command | What |
|---|---|
| `/presets` (`/preset /settings /p`) | the presets page (mine) |
| `/new [name]` (`/add`) | a new preset |
| `/edit <name>` | edit a preset (a prefix is enough) |
| `/delete <name>` (`/remove /del`) | open it; tap Delete, then Sure? |
| `/reboot <miner\|all>` (`/restart`) | by label, number or part of the name |
| `/redock <miner\|all>` | each sets his dock up where he stands |
| `/retired` | the retired miners |
| `/home` (`/back /overview`) | the overview |
| `/help [command]` | the commands page, or one usage line |

## Tests

`tests/scenarios/foreman_screens.lua` runs the real Foreman with stand-in Starlings at 57x24 (monitor) and 51x19, 39x13 and 26x20: tiles, a miner's page and its tabs, steppers, START / STOP, tap-twice Reboot / Retire / Dock all, a miner going lost, presets (new, edit, duplicate, move, delete, bad input), a monitor that cannot type, every command, the empty state, no modem. `tests/scenarios/foreman_remote.lua` covers the link to the MD and Nether Foremen through the same screens.
