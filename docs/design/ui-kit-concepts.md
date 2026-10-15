# UI kit: concepts to pick from (issue #2)

Status: **waiting on Tanis**. Pick one of A/B/C in each of the three choices below (or mix, or say "none, try again"). Once you have, the full kit goes in `docs/design/ui-kit.md` and this file is deleted.

How to read the mockups: every block is exactly the width in its `w=` tag. A space is a black cell. Shaded cells are coloured backgrounds: `░` grey (bars, idle buttons), `▓` gold (active, primary), `▒` a state colour (named under the block). Letters are text on top of that.

## 1. What the screens do today (grep survey)

Every screen draws its own copy. Same job, different look:

| Screen | Buttons | Header | Bars | Footer / paging | Colours |
|---|---|---|---|---|---|
| smelter, foreman, nether, farmhand | `button(x,y,w,rows,label,bg,fn,fg)` 1-3 rows, black text on colour, plus `smallButton` ` label ` | grey bar, cyan title, grey right text | grey track, lime/red fill, `Fuel` label + `%` | `smallButton` row at bottom, `< 2/5 >` | `K = colours`; cyan accent, lime good, orange warn, red bad, purple reboot, lightBlue docked |
| storage | ` label ` pills, cyan when active, grey when not | none (item list starts at row 1) | no | search bar at the bottom, `/` commands | own `C` table (bg/bar/fg/dim/accent/warn/good) |
| architect | `[Label]` brackets, grey | grey bar with the tabs inside it, **yellow** title | gray track, coloured fill | text input row `> ` on the last row, notice row above it | `colors.gray` spelling, `STATE_COL` table |
| neural, plastic | `btn()` pill, black text on colour, no padding rule | grey bar, `<` back chip, PAUSE/RUN chip at right | grey track | list pager `n/m` | `colours.*` inline |
| mainframe board | none (read-only) | grey bar, cyan title | no | none | `STATE_COLOUR` table (lime working, yellow returning, lightBlue docked, orange waiting, red error, purple rebooting) |
| setup | picker card, cyan pick | none | no | none | own `K` table, falls back to mono |
| glasses | `button()` grey pill, `switch()` segmented `[AUTO][ ON ][OFF ]` | none | no | none | white/grey/orange/cyan |
| assignui (shared) | `btn()` active = accent | none | no | none | own `C` table, same keys as storage |

What this tells us:

- **Three copies of one table.** smelter, foreman, nether and farmhand have the same `at/pad/bar/hit/button/smallButton/header/say` pasted in. storage and assignui have the same `C` table pasted in. Those become `shared/ui.lua`.
- **Eight colour meanings are already shared by habit:** lime = good/working, orange = warning/waiting, red = error/lost, cyan = accent/selected, lightBlue = docked/idle, purple = rebooting, yellow = returning/pending, grey = chrome. The kit writes them down and gives them names.
- **Things that differ with no good reason:** brackets vs pills, cyan vs yellow titles, `gray` vs `grey`, pager as `< 2/5 >` vs `n/m`, tabs in the header (architect) vs in the footer (farmhand).
- **Nobody remaps the palette** except the art computer, so every screen is the stock CC colours.

## 2. Palette (recommended; one look, no vote needed)

The kit remaps CC's 16 colour slots with `term.setPaletteColour` on every advanced computer and monitor, so code keeps saying `colours.lime` and gets the kit's lime. Slots keep their CC names so no existing line breaks. If a terminal ignores the remap (glasses may), the stock colours still read the same way because the roles match.

Gold is the house colour: the advanced computer and advanced turtle frame. It means "this is yours / this is selected / press this". Deepslate is the background and chrome.

| Slot | Hex | Role name | Means |
|---|---|---|---|
| black | `#17181C` | `bg` | Screen background. A touch darker than deepslate bricks so a monitor looks inset in a deepslate wall |
| grey | `#3A3C42` | `bar` | Chrome: header and footer bars, idle buttons, empty bar track. Close to deepslate bricks |
| lightGrey | `#A6A8B0` | `dim` | Secondary text, units, hints |
| white | `#F2EFE4` | `fg` | Primary text and numbers (slightly warm) |
| yellow | `#F2B71F` | `gold` | Identity and focus: titles, active tab, selected row, primary button, tap-twice armed |
| orange | `#F58340` | `warn` | Needs attention soon: waiting, low fuel, full, stale |
| red | `#F2686E` | `bad` | Broken or stopped: error, lost, destructive buttons |
| lime | `#86D96B` | `good` | Working and healthy, fuel and progress fill |
| green | `#4FB06C` | `good2` | Farm life: crops, growing; also a quieter "ok" |
| cyan | `#4CC3CC` | `info` | Live data and links: values you can drill into, map cursor |
| lightBlue | `#7AA7EE` | `idle` | Docked, done, standing by |
| blue | `#3E5CB0` | `water` | Water on maps only; never text |
| purple | `#B28DEA` | `busy` | Rebooting, updating, remote order in flight |
| magenta | `#E077C2` | `mark` | Markers and unusual: Nether portal, flagged items |
| pink | `#F4A6C6` | `soft` | Spare; reserved for art |
| brown | `#8B5E3C` | `soil` | Soil and logs on maps only |

Contrast (WCAG ratio) on `bg`: white 15.4, gold 9.8, lime 10.3, cyan 8.4, lightBlue 7.3, lightGrey 7.5, purple 6.7, orange 6.9, red 5.9, green 6.6. On a grey bar: white 9.6, gold 6.1, lime 6.4, cyan 5.2, orange 4.3, red 3.7, lightGrey 4.6. Black text on a gold or any state-colour button is above 5.9 everywhere except blue and brown (never used for buttons).

Rules: one state colour per thing; never colour alone (the word is always there too: "error", not just red); gold appears at most twice per screen (title and the selected or primary thing), so it stays meaningful.

## 3. Block palette (in game, to match)

Computers and monitors sit in a **deepslate** wall, so the screen's black and grey read as part of the build and the gold frames of advanced computers pop.

| Role | Blocks | Matches |
|---|---|---|
| Walls, floors | Deepslate Bricks, Polished Deepslate, Deepslate Tiles | `bar` grey |
| Inset behind monitors | Blackstone, Polished Blackstone | `bg` |
| Gold trim, frames, pillars | Gold Block, Raw Gold Block, Yellow Terracotta (cheap bulk gold) | `gold` |
| Light | Shroomlight, Glowstone, Lanterns (warm light, no cold white) | warm `fg` |
| Status lamps (redstone lamp behind coloured glass) | Lime, Orange, Red, Light Blue stained glass | `good` `warn` `bad` `idle` |
| Accent wall stripe | Dark Prismarine, Cyan Terracotta | `info` |
| Floor of farm rooms | Moss Block, Dark Oak | `green` `soil` |

Rule of thumb: 80% deepslate, 15% gold, 5% accent. Pair every gold block with deepslate on two sides so it frames rather than floods.

## 4. Pick: header bar

Shown at 51 wide, and squeezed to 26. Title left, state right. The state colour follows section 2 (here `lime` = working).

### A. Slab (one row, today's look, gold title)
```text w=51
░FOREMAN░░░░░░░░░░░░░░░░░░░3░canaries░·░storage░ok░
```
Whole row grey. Title gold, right text dim, state word in its state colour. Back is a `<` chip at the left when a page has a parent.

```text w=26
░FOREMAN░░░░░░░3░canaries░
```

### B. Chip and rule (two rows, calmer)
```text w=51
▓FOREMAN▓                  3 canaries · storage ok 
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
```
Row 1: title on a gold chip, the rest black; state text right. Row 2: a thin grey rule (a half-block character, shown here as `▔`). Costs one extra row.

```text w=26
▓FOREMAN▓      3 canaries 
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
```

### C. Crumb (one row, shows where you are)
```text w=51
▒<▒░Foreman░/░Canary-04░░░░░░░░░░░░░░░░░░●░working░
```
`< ` is a lighter grey chip and the back button (key: Backspace). The path squeezes from the left: `…/Canary-04`. The dot is the state colour.

```text w=26
▒<▒░…/Canary-04░●░working░
```

Notices ("Sent. Reboot Canary-04") take the row under the header for 5 seconds in every option, coloured by meaning.

## 5. Pick: button style and size

Same three buttons (`Pause`, `Reboot`, `Forget`) at 51 wide. Tap area is always at least what is drawn.

### A. Adaptive 3/2/1 rows (what the ticket planned)
Tall when there is room, one row when not. The kit picks the height from the free rows; the screen only says "a row of buttons".
```text w=35
▓▓▓▓▓▓▓▓▓▓▓ ░░░░░░░░░░░ ░░░░░░░░░░░
▓▓▓Pause▓▓▓ ░░░Reboot░░ ░░░Forget░░
▓▓▓▓▓▓▓▓▓▓▓ ░░░░░░░░░░░ ░░░░░░░░░░░
```
39x13 and 26x20 get the one-row form:
```text w=31
▓▓Pause▓▓ ░░Reboot░░ ░░Forget░░
```

### B. Always one row, big tap area
Drawn as flat one-row pills with one cell of padding. The tap area grows one row up and one down (and to the gap) when nothing else is there, so a fat finger on a monitor still hits. Never gets taller on screen, so layouts never jump.
```text w=31
▓▓Pause▓▓ ░░Reboot░░ ░░Forget░░
```
Hit zone, shown with `.` (invisible in game):
```text w=31
......... .......... ..........
▓▓Pause▓▓ ░░Reboot░░ ░░Forget░░
......... .......... ..........
```
Same at every size; only the gap and labels shrink (`Reboot` → `Boot`).

### C. Two sizes: one big primary, the rest small
One 3-row gold primary per screen (the thing you most likely want), everything else one row.
```text w=29
▓▓▓▓▓▓▓▓▓▓▓                  
▓▓▓Pause▓▓▓ ░Reboot░ ░Forget░
▓▓▓▓▓▓▓▓▓▓▓                  
```
On 26x20 it stays 3 rows (rows are plentiful there); on 39x13 it drops to one row. Fewer coloured blocks, clearer "do this".

Tap-twice confirm (all options): the button turns gold and says `Sure?`, goes back to normal after 4 seconds or on any other tap. Destructive ones arm in red.

## 6. Pick: tile (one machine / turtle on an overview)

Two tiles side by side on 51 wide (25 + gap + 25). The state in these is `working` (lime). Bar: `▒` fill, `░` track.

### A. Banner card (today's farmhand look, tidied)
```text w=51
░Canary-04░░░░░░░working░ ░Canary-04░░░░░░░working░
 Digging to Y -40          Digging to Y -40        
 Fuel ▒▒▒▒▒▒▒▒▒▒░░░░░ 64%  Fuel ▒▒▒▒▒▒▒▒▒▒░░░░░ 64%
 Cargo 12/16   Y -40       Cargo 12/16   Y -40     
 seen 2s ago               seen 2s ago             
```
Grey name bar with state at right. Whole tile is the tap target. Squeezed to 1 row (39x13 overview): `Canary-04 working 64%`.

### B. Edge stripe
Coloured stripe down the left edge in the state colour; no bars of grey, so it is the lightest on screen and the state reads from across the room.
```text w=51
▒ Canary-04      working  ▒ Canary-04      working 
▒ Digging to Y -40        ▒ Digging to Y -40       
▒ Fuel ▒▒▒▒▒▒▒▒▒░░░░░ 64% ▒ Fuel ▒▒▒▒▒▒▒▒▒░░░░░ 64%
▒ Cargo 12/16   Y -40     ▒ Cargo 12/16   Y -40    
▒ seen 2s ago             ▒ seen 2s ago            
```
Name white, state in state colour. Stale tiles dim the stripe to grey.

### C. Framed slab
The whole tile sits on a grey panel with gold name, so each machine reads as one object; empty gaps of black between them.
```text w=51
░Canary-04░░░░░░░working░ ░Canary-04░░░░░░░working░
░Digging░to░Y░-40░░░░░░░░ ░Digging░to░Y░-40░░░░░░░░
░Fuel░▒▒▒▒▒▒▒▒▒     ░64%░ ░Fuel░▒▒▒▒▒▒▒▒▒     ░64%░
░Cargo░12/16░░░Y░-40░░░░░ ░Cargo░12/16░░░Y░-40░░░░░
░seen░2s░ago░░░░░░░░░░░░░ ░seen░2s░ago░░░░░░░░░░░░░
```
Name gold, state in state colour, rest dim. Costs a bit of contrast on the bar track (grey on grey), so the empty part of the track is drawn black (shown here as blank).

## 7. Components the full kit will cover

Not up for a vote; they follow whichever header, button and tile you pick:

header bar with state · buttons · tap-twice confirm · `-`/`+` steppers · tabs · footer with paging · tiles · fuel and progress bars · notices · text field · search bar · `/` command bar · paged list rows · map viewport with pan · palette.

## 8. Code shape (so the pick is the only open question)

`shared/ui.lua`, one file every controller loads. A screen builds a frame, the kit draws and registers taps in one call, so layout code and hit boxes can't drift apart.

```lua
local ui = require("shared.ui")
local f = ui.frame(term.current())          -- installs the palette, reads W x H, picks a size class: "L" 51x19, "M" 39x13, "S" 26x20
f:header("FOREMAN", { state = "ok", right = "3 canaries" })
f:row(function(r)                           -- a horizontal group: sizes buttons to the room
  r:button("Pause",  { primary = true, on = pause })
  r:button("Forget", { confirm = true, tone = "bad", on = forget })
end)
f:footer({ page = 2, pages = 5, tabs = tabs })
f:draw()                                    -- paints everything; f:touch(x, y) and f:key(k) dispatch
```

Colours are always role names (`ui.c.good`), never `colours.lime`, so the palette can change in one place.

Questions for Tanis are in the issue comment.
