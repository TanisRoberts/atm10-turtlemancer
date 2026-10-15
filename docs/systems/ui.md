# UI kit (`shared/ui.lua`)

Design: `docs/design/ui-kit.md`. Devices keep shared files flat, so a program says `local ui = require("ui")` and lists `shared/ui.lua` in its manifest role. Nothing uses it yet; the Farmhand pilot (#3) is first.

## Part 1 (#2): `shared/ui.lua`

- `ui.view(term, { side = "right" })`: reads W x H, picks the width class (narrow, compact, regular, wide) and height class (short, normal, tall), sets text scale 0.5 on monitors, installs the palette on colour terminals. `view:close()` puts the stock palette back. `side` is the monitor's peripheral name so `monitor_touch` finds it; leave it nil for the computer's own screen.
- Colours are role names (`ui.c.good`, `"gold"` in options). A terminal without colour gets the fallback: `[ Label ]` buttons, `-` rule, `[TITLE]` chip, nearest grey.
- `view:header(title, { state, color, right, onState })`, `view:buttons(x, y, list)`, `view:stepper(x, y, label, value, opts)`, `view:footer({ back = fn })`, `view:notice()` (the header draws it), `view:rect()` for the content area. Each call draws, registers its hit boxes and returns where it ended.
- `view:frame(draw)` starts a frame (clears boxes, focus list, screen) and calls `draw(view)`. `ui.run(views, draw, { on_event, tick })` is the event loop: taps (`mouse_click`, `monitor_touch`), keys, resize, notice and confirm timers; `ui.quit()` ends it.
- Hit boxes: a button's target is its pill plus half the gap each side and one row above and below. `ui.hit.find` picks the box whose target holds the tap, then the one with the nearest drawn cells, then the first registered. Disabled boxes still win the tap and ignore it.
- Tap-twice: `confirm = true` on a button. State lives on the view (`armed`, 4 seconds); any other tap or key disarms. Confirm buttons keep one width (`max(label, "Sure?")`) so rows do not jump.
- Notices: `ui.say(text, tone, { action = { label, fn } })` is global to the computer, so every view shows it. Errors (`"bad"`) stay until tapped; other tones expire after 5 seconds.
- Keys: Tab / Shift+Tab focus, Enter taps the focused control, Esc clears focus, Backspace goes back, a button's `key` letter taps it, Left/Right/`-`/`+` and PgUp/PgDn on a focused stepper.

## Part 2 (#15): `shared/ui_widgets.lua`

Loaded by `ui.lua` itself, so a program only requires `ui`; both files must be in the role's manifest entry. Each file stays under about 30 KB (23 KB and 25 KB now); put part 3 in another `shared/ui_*.lua`.

Paging state lives on the view: `v.page` is the page being shown, lists and tiles set `v.pages` while drawing, and the footer (drawn last) shows the pager from it. `v:turn(d)` changes page; PgUp/PgDn and the mouse wheel call it. Tabs reset the page to 1. Pass `page`, `pages` or `on_page` to the footer to manage paging yourself. `v.sel` is the highlighted tile or selected list row.

- `v:footer({ back, tabs = { { id, label, short, star } }, tab, on_tab })`: Back, tabs, pager. Tabs are full labels, then 4-letter ones, then the active tab plus a `..` pill that cycles. Tabs are in the Tab-key focus ring, `1`-`9` jump to one.
- `v:tiles(items, { render = fn(item) -> fields, on })` and `ui.layout.tiles(W, H, n)` (columns, width, height, rows per page, pages). Fields: name, state, activity, fuel (0..1), numbers, seen, stale (`"3m"`), color. 5-row tiles, or 2-row (name and fuel) on short screens. Arrows move the highlight, Enter opens, Esc clears.
- `v:bar(x, y, w, label, frac, { kind = "fuel"|"cap"|"progress", text })`; `ui.barColour(kind, frac)`.
- `ui.field{ hint, max, validate, on_commit, on_cancel }` and `v:field(x, y, label, w, f)`. `v:search(f, { hint, commands = { { name, help, fn(arg) } } })` draws the input row and returns true in command mode; call it after the list, because the command list replaces what was drawn above it (and its hit boxes). A search bar takes all typing unless another field is focused, so button hotkeys and `1`-`9` are off on screens that have one. Enter on a search bar with no `on_commit` opens the selected list row, else the top one.
- `v:list(rows, { on, input })`: rows `{ name, value, state (colour role), id }`. Up/Down, PgUp/PgDn, Home/End, Enter.
- `v:map({ get = fn(x, z) -> role | { role, char, text }, at = { x, z, facing }, on_cell, input })`: pan buttons, `Follow`, arrows, Home or `f`, wheel. Draws rows with `blit`.

Not built: the map thumbnail inside a wall tile (kit 4.5, optional).

## Tests

`tests/scenarios/ui_core.lua` with the demo screen `tests/demo/ui_demo.lua`, and `tests/scenarios/ui_more.lua` with `tests/demo/ui_demo2.lua` (tabs: tiles, list, map, form): layout and tap targets at 57x24, 51x19, 39x13 and 26x20, confirm timer, notices, colourless fallback, monitors, resize.
