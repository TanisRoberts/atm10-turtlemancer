# Controller screens: index (issue #26)

Every controller's screens as exact-width mockups built from the UI kit (`ui-kit.md`). One file per controller; each lists its screens, taps, keys and how it squeezes on smaller screens. The art controller is not covered (issue #25).

| Controller | File | Screens |
|---|---|---|
| Mainframe | [`mainframe.md`](mainframe.md) | 4 |
| Storage | [`storage.md`](storage.md) | 9 |
| Smelter | [`smelter.md`](smelter.md) | 14 |
| Foreman | [`foreman.md`](foreman.md) | 13 |
| Nether Foreman | [`nether.md`](nether.md) | 8 |
| Farmhand | [`farmhand.md`](farmhand.md) | 8 |
| Neural lab | [`neural.md`](neural.md) | 4 |
| Plastic factory | [`plastic.md`](plastic.md) | 3 |
| Architect | [`architect.md`](architect.md) | 6 |
| GPS host | [`gps.md`](gps.md) | 2 |
| Startup and reset | [`startup.md`](startup.md) | 5 |
| Setup | [`setup.md`](setup.md) | 6 |
| Smart glasses | [`glasses.md`](glasses.md) | 2 |
| Operator | [`operator.md`](operator.md) | 4 tabs, 4 sizes |

## Common to every screen

- **Sizes.** Computers and the glasses: 51x19, 39x13 (turtle), 26x20 (glasses). Monitors at text scale 0.5: 36x24 (2x2), 57x24 (3x2), 57x38 (3x3), 57x81 (3x6), 164x81 (8x6). The mockup tags say which size each was drawn at; the kit picks its layout from width and height, so the other sizes follow the same rules.
- **Layout.** Row 1-2 header and rule or notice; content; the input row (search or command bar) above the footer; the footer last. Footer left is Back, then tabs, then the pager at the right.
- **Motion.** Status glyphs (section 9) beside every state word; they step together twice a second. Nothing else moves except on waiting and loading screens and the smelter's training page.
- **Taps and keys.** One tap target per control, as big as the kit makes it. Tab / Shift+Tab focus, Enter taps, Esc cancels, Backspace goes back, PgUp/PgDn page, `/` opens the command bar on screens that have one.
- **New components.** Section label, key-value row, alert line, segmented switch, board row, picker card, report page, furnace tile and padlock are specified in `ui-kit.md` section 10.
- **Migration.** Each controller's screens are built by engineering one at a time, in the kit's migration order: foreman, nether, smelter, storage and assign, neural, plastic, board, setup and startup, glasses, architect.
