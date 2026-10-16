# UI kit (`shared/ui.lua`)

Design: `docs/design/ui-kit.md`. Devices keep shared files flat, so a program says `local ui = require("ui")` and lists `shared/ui.lua` in its manifest role. The Farmhand is the first user (see `docs/systems/farmhand.md`); the other controllers move over in the kit's migration order.

## Part 1 (#2): `shared/ui.lua`

- `ui.view(term, { side = "right" })`: reads W x H, picks the width class (narrow, compact, regular, wide) and height class (short, normal, tall), sets text scale 0.5 on monitors, installs the palette on colour terminals. `view:close()` puts the stock palette back. `side` is the monitor's peripheral name so `monitor_touch` finds it; leave it nil for the computer's own screen.
- **Drawing is buffered.** Components write into a buffer (`v:put`, `v:cells`); `v:frame(draw)` clears the buffer, draws, then `v:flush()` sends only the rows that changed since last time, one `blit` each. The screen itself is never cleared, so a frame that changed nothing writes nothing. This matters: the computer runs alongside the game, and a clear followed by a repaint can be seen as a blank screen (flicker). Never call `term.clear()` or write to the terminal behind the kit's back; if you must, call `v:invalidate()` so the next frame shows every row again. `ui.run` redraws input events at once and everything else (a radio message, a timer) at most every `min_interval` seconds (default 0.25).
- Colours are role names (`ui.c.good`, `"gold"` in options). A terminal without colour gets the fallback: `[ Label ]` buttons, `-` rule, `[TITLE]` chip, nearest grey.
- `view:header(title, { state, color, right, onState })`, `view:buttons(x, y, list)`, `view:stepper(x, y, label, value, opts)`, `view:footer({ back = fn })`, `view:notice()` (the header draws it), `view:rect()` for the content area. Each call draws, registers its hit boxes and returns where it ended.
- `view:frame(draw)` starts a frame (clears boxes, focus list, screen) and calls `draw(view)`. `ui.run(views, draw, { on_event, tick })` is the event loop: taps (`mouse_click`, `monitor_touch`), keys, resize, notice and confirm timers; `ui.quit()` ends it.
- Hit boxes: a button's target is its pill plus half the gap each side and one row above and below. `ui.hit.find` picks the box whose target holds the tap, then the one with the nearest drawn cells, then the first registered. Disabled boxes still win the tap and ignore it.
- Tap-twice: `confirm = true` on a button. State lives on the view (`armed`, 4 seconds); any other tap or key disarms. Confirm buttons keep one width (`max(label, "Sure?")`) so rows do not jump.
- Notices: `ui.say(text, tone, { action = { label, fn } })` is global to the computer, so every view shows it. Errors (`"bad"`) stay until tapped; other tones expire after 5 seconds.
- Keys: Tab / Shift+Tab focus, Enter taps the focused control, Esc clears focus, Backspace goes back, a button's `key` letter taps it, Left/Right/`-`/`+` and PgUp/PgDn on a focused stepper.

## Part 2 (#15): `shared/ui_widgets.lua`

Loaded by `ui.lua` itself, so a program only requires `ui`; both files must be in the role's manifest entry. Each file stays under about 30 KB (26 KB and 26 KB now); new components go in another `shared/ui_*.lua`.

Paging state lives on the view: `v.page` is the page being shown, lists and tiles set `v.pages` while drawing, and the footer (drawn last) shows the pager from it. `v:turn(d)` changes page; PgUp/PgDn and the mouse wheel call it. Tabs reset the page to 1. Pass `page`, `pages` or `on_page` to the footer to manage paging yourself. `v.sel` is the highlighted tile or selected list row.

- `v:footer({ back, tabs = { { id, label, short, star } }, tab, on_tab })`: Back, tabs, pager. Tabs are full labels, then 4-letter ones, then the active tab plus a `..` pill that cycles. Tabs are in the Tab-key focus ring, `1`-`9` jump to one.
- `v:tiles(items, { render = fn(item) -> fields, on })` and `ui.layout.tiles(W, H, n)` (columns, width, height, rows per page, pages). Fields: name, state, activity, fuel (0..1), numbers, seen, stale (`"3m"`), color. 5-row tiles, or 2-row (name and fuel) on short screens. Arrows move the highlight, Enter opens, Esc clears.
- `v:bar(x, y, w, label, frac, { kind = "fuel"|"cap"|"progress", text })`; `ui.barColour(kind, frac)`.
- `ui.field{ hint, max, validate, on_commit, on_cancel }` and `v:field(x, y, label, w, f)`. `v:search(f, { hint, commands = { { name, help, fn(arg) } } })` draws the input row and returns true in command mode; call it after the list, because the command list replaces what was drawn above it (and its hit boxes). A search bar takes all typing unless another field is focused, so button hotkeys and `1`-`9` are off on screens that have one. Enter on a search bar with no `on_commit` opens the selected list row, else the top one.
- `v:list(rows, { on, input })`: rows `{ name, value, state (colour role), id }`. Up/Down, PgUp/PgDn, Home/End, Enter.
- `v:map({ get = fn(x, z) -> role | { role, char, text, textRole }, at = { x, z, facing, fg, bg }, on_cell, input, area, bounds, wide })`: pan buttons, `Follow`, arrows, Home or `f`, wheel. `area` draws in a box instead of the content area (the pan row is its last row). `bounds` says where the map exists: a map that fits is centred with no pan row, a bigger one stays inside it; `wide` makes cells 2 characters when they fit. `v:cells(x, y, { { char, fg, bg }, ... })` draws one row of coloured cells with a single `blit` (the map uses it; so can a thumbnail).

The map thumbnail on a tile is done by the screen through `fields.extra` and `v:cells`.

## Part 3 (#27): `shared/ui_parts.lua`

Loaded by `ui.lua` after `ui_widgets.lua`; every role that uses the kit lists all three files in its manifest entry. Design: `docs/design/ui-kit.md` section 10. Single-row components return the next free row (`y + 1`); `switch` returns the next free x and its last row, like `v:buttons`.

- `v:section(x, y, w, text)`: dim caps label and a grey rule to `x + w - 1`. Leave a blank row above it.
- `v:kv(x, y, w, key, value, tone)`: key left (dim), value right (white or a role). Too long: the key is cut first, the value last.
- `v:alert(x, y, w, text, tone)`: one-cell stripe and text in the tone (default `"warn"`). Without colour the stripe is `!`.
- `v:switch(x, y, options, current, on_pick, { id, maxx })`: touching pills, the current one gold. Options are ids or `{ id, label, short }`; `on_pick(id, option)`. If the long labels do not fit, `short` ones are used, then it wraps to a second row. Tap a segment to pick it. Tab focuses the switch: Left/Right move a cursor (wraps), Enter picks the cursor. Without colour the current one is `[AUTO]`.
- `v:board(x, y, w, rows)` and `v:boardHeader(x, y, w, title)`: rows `{ name, state, detail, age, color, glyph }` (`rows.title` draws the grey header bar with the gold caps label first). Stripe in the state colour, glyph and state word, detail, and `age` (seconds, or text) at the right. `age >= 30` greys the row, with a still `?`. No hit boxes. Detail is dropped when it does not fit (26 wide has none). The glyph is `v:glyph` once motion (#24) is in, otherwise a still one.
- `ui.picker{ question, items = { { id, name, tag, lines | text } }, index, hint, on_pick(item, i), on_move(item, i) }` and `v:picker(p)`: the question and `n of m` counter, the previous and next items peeking above and below (`^`/`v`, click to move to one), the current one as a gold title bar (name, tag) with its body (`lines`, or `text` word-wrapped; cut with `...`). It draws the hint and `Pick >` on the footer row, so call it **after** `v:footer{ back }`. Up/Down/Left/Right, wheel, Home/End, `1`-`9`; Enter with nothing focused (or `Pick >`) picks. Wraps around. `p:move(d)`, `p:jump(i)`, `p:pick()`.
- `v:report{ title, state, color, right, back, rows }`: a whole info page. Rows are `{ section }`, `{ key, value, tone }`, `{ alert, tone }`, `{ text, tone }` or `{ blank = true }`; a blank row goes above every section but the first, a pager appears when it does not fit, and the footer has Back. Use it for what a command used to print on the terminal.
- `v:spinner_line(x, y, text)`: the orange waiting glyph (`. o O o`, 4 beats a second) then the text; sets `v.animated`. `ui.anim == "off"` or no colour shows a still glyph. It uses `ui.beat` when motion lands, else the clock at the same rate.
- The furnace tile and the padlock live in the smelter's and storage's own screens modules.

## Motion (#24): `shared/ui_motion.lua`

Loaded by `ui.lua` last; every role that uses the kit lists it. Design: `docs/design/ui-kit.md` section 9.

- `ui.anim` is `"full"` (default), `"calm"` (dashboard glyphs only, no bar) or `"off"` (everything still). `ui.setAnim(mode)`; `ui.loadAnim("x.env", default)` reads `ANIM=` from a device's .env-style file and appends the line if it is missing (an existing line is never overwritten). Read at start, so a change needs a reboot. Glasses should pass `"calm"`.
- `ui.beat(rate)`: an integer that goes up `rate` times a second. Dashboards use 2, waiting screens 4. `ui.nextBeat(rate)` is the `os.clock()` time of the next one.
- `v:glyph(x, y, state, { rate, stale, since })`: one character in the state's colour (working `\ | / |`, building, farming, smelting, waiting, returning, rebooting; still `=` docked, `+` done, `-` idle, `?` stale, `!` lost/error). Still when `ui.anim == "off"`, on a terminal without colour, for `stale`, and past 24 moving glyphs a view. `since` (an `os.clock()` time) makes an error pulse red/white for 3 seconds. `v:glyphChar(state, o)` gives the character and colour role without drawing.
- `v:spinner(x, y, state)`: the waiting glyph at 4 a second. `v:indeterminate(x, y, w)`: a track with a 6-cell block bouncing one cell a beat; still on `calm` and `off`. `v:spinner_line` (part 3) uses the spinner.
- Tiles and the header put a glyph two cells before the state word (a tile whose name would be cut to make room leaves the glyph out). A `busy` button keeps its label and puts the rebooting glyph before it.
- A view that drew something moving sets `v.animated` and `v.animRate`; `ui.run` then wakes for the next beat, and sleeps again when nothing moves. A beat writes one `blit` per changed row.

## Tests

`tests/scenarios/ui_core.lua` with the demo screen `tests/demo/ui_demo.lua`, and `tests/scenarios/ui_more.lua` with `tests/demo/ui_demo2.lua` (tabs: tiles, list, map, form): layout and tap targets at 57x24, 51x19, 39x13 and 26x20, confirm timer, notices, colourless fallback, monitors, resize.

`tests/scenarios/ui_parts.lua` with `tests/demo/ui_demo3.lua` (screens: parts, board, picker, report, wait): every part-3 component at the four sizes, taps and keys, the squeeze, a monitor, and the colourless fallback.

`tests/scenarios/ui_motion.lua` (beat, frames and colours, budget, `ANIM`, stale, cost of a beat, spinner and bar, busy button, no colour) and `tests/scenarios/smelter_motion.lua` (the smelter dashboard).
