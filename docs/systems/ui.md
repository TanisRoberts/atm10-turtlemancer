# UI kit (`shared/ui.lua`)

Design: `docs/design/ui-kit.md`. Devices keep shared files flat, so a program says `local ui = require("ui")` and lists `shared/ui.lua` in its manifest role. Nothing uses it yet; the Farmhand pilot (#3) is first.

## What is built (part 1, #2)

- `ui.view(term, { side = "right" })`: reads W x H, picks the width class (narrow, compact, regular, wide) and height class (short, normal, tall), sets text scale 0.5 on monitors, installs the palette on colour terminals. `view:close()` puts the stock palette back. `side` is the monitor's peripheral name so `monitor_touch` finds it; leave it nil for the computer's own screen.
- Colours are role names (`ui.c.good`, `"gold"` in options). A terminal without colour gets the fallback: `[ Label ]` buttons, `-` rule, `[TITLE]` chip, nearest grey.
- `view:header(title, { state, color, right, onState })`, `view:buttons(x, y, list)`, `view:stepper(x, y, label, value, opts)`, `view:footer({ back = fn })`, `view:notice()` (the header draws it), `view:rect()` for the content area. Each call draws, registers its hit boxes and returns where it ended.
- `view:frame(draw)` starts a frame (clears boxes, focus list, screen) and calls `draw(view)`. `ui.run(views, draw, { on_event, tick })` is the event loop: taps (`mouse_click`, `monitor_touch`), keys, resize, notice and confirm timers; `ui.quit()` ends it.
- Hit boxes: a button's target is its pill plus half the gap each side and one row above and below. `ui.hit.find` picks the box whose target holds the tap, then the one with the nearest drawn cells, then the first registered. Disabled boxes still win the tap and ignore it.
- Tap-twice: `confirm = true` on a button. State lives on the view (`armed`, 4 seconds); any other tap or key disarms. Confirm buttons keep one width (`max(label, "Sure?")`) so rows do not jump.
- Notices: `ui.say(text, tone, { action = { label, fn } })` is global to the computer, so every view shows it. Errors (`"bad"`) stay until tapped; other tones expire after 5 seconds.
- Keys: Tab / Shift+Tab focus, Enter taps the focused control, Esc clears focus, Backspace goes back, a button's `key` letter taps it, Left/Right/`-`/`+` and PgUp/PgDn on a focused stepper.

## Part 2 (#15) adds

Tabs and paging, tiles, bars, text fields and the command bar, paged lists, the map viewport. Extend this module; do not change part 1's API. Keep each file under about 30 KB (split into `shared/ui_*.lua` past that; `ui.lua` is about 24 KB now).

## Tests

`tests/scenarios/ui_core.lua` with the demo screen `tests/demo/ui_demo.lua`: layout and tap targets at 57x24, 51x19, 39x13 and 26x20, confirm timer, notices, colourless fallback, monitors, resize.
