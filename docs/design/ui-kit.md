# UI kit

Status: **draft for Tanis's sign-off** (issue #2). Picks already made: header B (chip and rule), buttons B (one row, big tap area), tiles B (edge stripe). Palette approved. Block palette revised to match the advanced monitor frame (section 3).

Every controller draws its screens with `shared/ui.lua`, which implements this document. A screen says what it shows (header, buttons, tiles, list); the kit decides sizes, colours, hit boxes and keys, so screens on a 26x20 pair of glasses and a 164x81 wall come from the same code.

**How to read the mockups.** Every block is exactly the width in its `w=` tag. A space is a black cell. Shaded cells are coloured backgrounds: `░` grey, `▓` gold, `▒` any other colour (named under the block). Letters sit on top. `─` is a thin rule (teletext character 140, grey on black).

## 1. Screens and size classes

Monitors run at text scale 0.5, CC's smallest. Characters: `round((64n-20)/3)` wide by `round((64n-20)/4.5)` tall for n blocks.

| Screen | Blocks | Characters | Class |
|---|---|---|---|
| Smart glasses | | 26x20 | narrow, normal |
| Display | 2x2 | 36x24 | compact, normal |
| Turtle | | 39x13 | compact, short |
| Advanced computer | | 51x19 | regular, normal |
| Small board | 3x2 | 57x24 | regular, normal |
| Large board | 3x3 | 57x38 | regular, tall |
| Canvas | 3x6 | 57x81 | regular, tall |
| Wall | 8x6 | 164x81 | wide, tall |

The kit reads `term.getSize()` and picks from width and height separately, so an odd monitor (4x3) still works.

| | narrow (up to 30) | compact (31-45) | regular (46-70) | wide (71+) |
|---|---|---|---|---|
| Header | title only, state word | title + state | title + state + right text | same, right text can hold a summary |
| Buttons | short labels (`Reboot` → `Boot`) | full labels | full labels, `<<` `>>` steppers | same |
| Tiles | 1 column, 24 wide | 1 column, up to 34 wide | 2 columns, 24 to 27 wide | as many columns as fit |
| Tabs | 4-letter labels | full labels | full labels | full labels |

| | short (up to 14) | normal (15-30) | tall (31+) |
|---|---|---|---|
| Tile height | 2 rows (name+state, bar) | 5 rows | 5 rows, more of them |
| List | fewer rows per page | rows per page = height - 3 | same, more rows |
| Map | no pan buttons row (keys and drag only) | pan row | pan row, bigger viewport |

**Layout contract.** Margin of one column left and right for content. Rows from the top: 1 header, 2 rule or notice, then content. Rows from the bottom: footer (1 row), and above it an input row (search or command bar) when the screen has one. Content never draws in those rows.

**Tile grid.** Columns = `max(1, floor((W-2+1)/(24+1)))`, tile width = `floor((W-2-(cols-1))/cols)`. 51 wide gives 2 columns of 24, 57 gives 2 of 27, 164 gives 6 of 26, 26 gives 1 of 24. Rows of tiles = `floor((avail+1)/(h+1))`, with a one-row gap.

## 2. Palette

Approved. The kit remaps CC's 16 colour slots with `term.setPaletteColour` on every advanced computer and monitor, so code says `colours.lime` and gets the kit's lime. Slots keep their CC names; the kit also exports role names (`ui.c.good`). If a terminal ignores the remap (glasses may), the stock colours read the same way because the roles match.

| Slot | Hex | Role | Means |
|---|---|---|---|
| black | `#17181C` | `bg` | Screen background |
| grey | `#3A3C42` | `bar` | Chrome: idle buttons, bar track, panels |
| lightGrey | `#A6A8B0` | `dim` | Secondary text, units, hints |
| white | `#F2EFE4` | `fg` | Primary text and numbers |
| yellow | `#F2B71F` | `gold` | Identity and focus: header chip, active tab, selected row, main button, armed tap-twice. At most two per screen |
| orange | `#F58340` | `warn` | Needs attention soon: waiting, low fuel, almost full, stale |
| red | `#F2686E` | `bad` | Broken or stopped: error, lost, destructive button |
| lime | `#86D96B` | `good` | Working, healthy, fuel fill |
| green | `#4FB06C` | `good2` | Farm life, crops; quieter "ok" |
| cyan | `#4CC3CC` | `info` | Live data you can open, progress fill, map cursor |
| lightBlue | `#7AA7EE` | `idle` | Docked, done, standing by |
| blue | `#3E5CB0` | `water` | Water on maps only |
| purple | `#B28DEA` | `busy` | Rebooting, updating, order in flight |
| magenta | `#E077C2` | `mark` | Markers: Nether portal, flagged |
| pink | `#F4A6C6` | `soft` | Reserved for art |
| brown | `#8B5E3C` | `soil` | Soil and logs on maps only |

State to colour (used by header state, tile stripe, board): `working mining building mapping surveying clearing marking` lime; `returning` cyan (in transit; was yellow on the board, which now belongs to gold); `docked done idle` lightBlue; `waiting low stale` orange; `error lost stopped` red; `rebooting updating` purple. Unknown state: lightGrey.

Rules: one state, one colour, and the state is always also a word. Gold at most twice per screen. Blue and brown are never text or buttons. Contrast on `bg`: white 15.4, lime 10.3, gold 9.8, cyan 8.4, lightBlue 7.3, orange 6.9, purple 6.7, green 6.6, red 5.9. On a grey bar the lowest is red at 3.7, which is why a state also gets a word.

## 3. Blocks and rooms

Computers and monitors sit in a **deepslate** wall so the screen's black and grey look part of the build.

**The advanced monitor frame is not gold.** Read from CC:Tweaked's own textures (`computer_advanced_*`, `monitor_advanced_*`): the frame is a pale olive-yellow, `#DDD771` lit, `#ECEC9C` on its inner highlight, with `#303030` detail, hue 56 degrees. In game it dims to about `#938D4A` in shade. The UI's gold chip (`#F2B71F`, hue 43) is warmer and more orange, so gold blocks (Gold Block, Raw Gold, Yellow Terracotta) look wrong beside the frames. The UI palette stays as approved; the block palette now follows the frame instead.

**Frame yellow blocks.** Matched on hue, saturation and lightness against the frame body (`#DDD771`, hue 56, saturation 0.51, lightness 0.87) across vanilla and the pack's mods (Aether, Create, Chipped, Mekanism, Industrial Foregoing, Ars Nouveau, Regions Unexplored and others; textures read from the 1.21.1 jars and mod sources).

| Block | Mod | Average | Hue | Use |
|---|---|---|---|---|
| **Block of Ambrosium** | Aether | `#E0D661` | 55 | an exact match: trim, pillars, frames around monitors. Craft from 9 Ambrosium Shards (Ambrosium Ore, Aether islands) |
| **Quicksoil** | Aether | `#D8CE82` | 53 | the same hue, a little paler and softer: walls and panels around monitors. Mined in the Aether, plentiful |
| **Stripped Bamboo Block** | vanilla | `#C1AD50` | 49 | the closest vanilla block; slightly warmer and darker. The fallback anywhere without Aether blocks |
| End Stone Bricks | vanilla | `#DAE0A2` | 65 | cooler and paler than the frame; fine for pillars beside Stripped Bamboo |

Checked in your screenshot: in that lighting the frame reads about `#A8A053` lit and `#817C48` in shade, and the Ambrosium Block's average scaled by the same lighting (0.76) lands within about 10 units of the lit frame, where Sponge, Bamboo Planks and End Stone each miss on hue or saturation. Sponge is out (too hard to get); the Gold Block family is out (wrong hue).

Not worth it: Create's Brass and Mekanism's Refined Glowstone are gold, not olive-yellow; Chipped's variants reuse vanilla colours and add nothing new here.

**Room recipe (coloured wall theory).** Walls, floor and ceiling differ in lightness and in temperature. Lightness steps up from floor to ceiling; temperature sandwiches: warm floor, cool walls, warm ceiling, tied together by a frame-yellow line. Deepslate Tiles were too close to the Deepslate Brick walls in both, so they are out of the floor.

| Surface | Block | Lightness L* | Temperature |
|---|---|---|---|
| Ceiling | **Mud Bricks** (brighter: Cut Sandstone, L* 83) | 47 | warm, pale brown |
| Walls | **Deepslate Bricks**, Polished Deepslate pillars | 30 | cool grey |
| Floor | **Dark Oak Planks**, Polished Blackstone Bricks inlay border | 20 / 18 | warm, deep brown |
| Skirting and cornice | **Block of Ambrosium** (or **Stripped Bamboo Block**), one block high where wall meets floor and ceiling | | frame yellow, the bridge |
| Pillars and panels between monitors | **Quicksoil** (or **End Stone Bricks**) | | frame yellow, pale |
| Behind monitors | Blackstone, Polished Blackstone | | matches screen `bg` |
| Light | Shroomlight, Glowstone, Lanterns (warm light) | | warm |
| Status lamps | Lime, Orange, Red, Light Blue stained glass over lit redstone lamps | | match state colours |
| Accent stripe | Dark Prismarine, Cyan Terracotta | | matches `info` |
| Farm rooms | Moss Block, Dark Oak | | green and soil |

Floor alternatives if dark oak does not suit a room: Polished Blackstone Bricks (darker and warmer than the walls), Spruce Planks (lighter). Keep the rule: the floor is the darkest and warmest large surface, the ceiling the lightest.

About 80% deepslate, 15% frame yellow, 5% accent by what you see at monitor height. Put frame yellow against deepslate on two sides so it frames and does not flood.

## 4. Components
### 4.1 Header

Two rows. Row 1: a gold chip with the title (`TITLE` in caps) at the left, state at the right as a coloured word, optional dim summary before it (regular and wide only). Row 2: the rule, or a notice (4.7) while one is showing. The chip is the only gold in the header.

```text w=51
▓FOREMAN▓         3 canaries · storage ok  working 
───────────────────────────────────────────────────
```
Chip gold with black text; summary dim; state word in its state colour (lime here); rule grey on black.
```text w=26
▓FOREMAN▓         working 
──────────────────────────
```
States: the state word and its colour follow section 2; `ok` lime, `?` dim when nothing is known, `offline` orange when the device has not been heard from.
Taps: none on the chip. A tap on the state word opens that machine's log or details when the screen offers one (screens say so with `onState`).
Keys: none.
Squeeze: narrow drops the summary and shortens the title if it does not fit (`..`). Short screens keep both rows.

### 4.2 Buttons

One row tall at every size, drawn as a pill with one cell of padding either side: ` Label `. Layouts never jump between sizes.

```text w=32
▓Pause▓ ░Reboot░ ▒Forget▒       
```
Primary gold, normal grey with white text, danger red with black text.
```text w=32
▓Pause▓ ░Reboot░  Forget        
```
Last one disabled: no fill, grey text, ignores taps.
**Big tap area.** The drawn pill is the visible target. The tap target is bigger: the pill's cells, plus half the gap to its neighbours left and right, plus one row above and one below when no other control sits there. A tap picks the control whose target contains it; if two do, the one whose drawn cells are nearest wins. Dots mark the extra area here (invisible in game):

```text w=32
········· ·········· ·········· 
▓Pause▓ ░Reboot░ ▒Forget▒       
········· ·········· ·········· 
```
States: idle, primary (the one main action, gold, at most one per screen), danger (red), disabled, busy (purple, label becomes `...` while an order is in flight), on (gold, for toggles and the active tab), armed (below).

**Tap-twice confirm.** For anything destructive or slow to undo, set `confirm = true`. First tap: the button turns gold (red for danger) and its label becomes `Sure?`. A second tap on it within 4 seconds runs it. Any other tap, key press or 4 seconds later puts it back. Keys: Enter on the focused button taps it, so Enter twice confirms.

```text w=9
▒Forget▒ 
```
```text w=9
▒Sure?▒  
```
Left: idle. Right (next block): armed.
Keys: Tab and Shift+Tab move focus (a focused button is drawn with a white `>` on its left when there is a free cell, else brighter fill); Enter taps. A button may take a `key` (like `p`) that taps it from the keyboard; the kit shows it nowhere, so list shortcuts in the screen's help.
Squeeze: labels carry a short form (`label = "Reboot", short = "Boot"`). Narrow screens use the short form. If buttons still do not fit a row, the row wraps to the next row down.

### 4.3 Steppers (- / +)

A value you nudge: `-`, the number, `+`. Tap `-` or `+` for one step. On regular and wide screens an optional pair `<<` `>>` steps ten. Hold is not available on monitors, so the step buttons repeat only when the key is held on a computer.

```text w=26
Mine depth ░-░  40 ░+░    
```
```text w=36
Mine depth ░<<░ ░-░  40 ░+░ ░>>░    
```
States: at its minimum the `-` is disabled; at its maximum the `+`. A value that has been sent but not confirmed by the device is gold (it is the pending change); once the device reports it, white.
Keys: Left/Right or `-`/`+` change the focused stepper, PgUp/PgDn step ten.
Squeeze: narrow stacks the label above the stepper.

### 4.4 Footer, tabs and paging

The last row. Left to right: Back (when the page has a parent), the tabs (when the screen has several views), and at the right the pager (when the content has several pages).

```text w=51
░<░ Back  ▓Map▓ ░Do░ ░Info░ ░Set░       ░<░ 2/5 ░>░
```
Active tab gold. Pager arrows grey, disabled ones have no fill.
```text w=39
░<░ ░Map░ ▓Do▓ ░Info░ ░Set░  <  1/3 ░>░
```
```text w=26
░<░ ▓Map▓ ░Do░ ░Set░      
```
Narrow: Back is just `<`, no pager when there is one page.
Taps: a tab switches view (the page's scroll resets); `<` at the far left goes back; pager arrows move one page.
Keys: Tab / Shift+Tab next and previous tab, `1`-`9` jump to a tab, Backspace goes back, PgUp/PgDn change page, mouse wheel scrolls a page.
States: active tab gold; a tab with something waiting shows a lime `*` after the label (`Do*`).
Squeeze: tabs that do not fit shrink to 4-letter labels, then to just the active tab plus `..` which cycles.

### 4.5 Tiles (edge stripe)

One machine or turtle on an overview. A stripe in the state colour runs down the left edge; the stripe is the state at a glance, from across the room. Rows: name and state word, what it is doing, fuel bar, a numbers line, last seen.

```text w=51
 ▒ Canary-04     working  ▒ Canary-07     waiting  
 ▒ Digging to Y -40       ▒ Waiting for fuel       
 ▒ Fuel ▒▒▒▒▒▒▒▒░░░░░ 64% ▒ Fuel ▒▒░░░░░░░░░░░ 18% 
 ▒ Cargo 12/16   Y -40    ▒ Cargo 16/16   Y -12    
 ▒ seen 2s ago            ▒ seen 4s ago            
                                                   
 ▒ Canary-09   returning  ░ Canary-12        lost  
 ▒ Heading home           ░ No reply               
 ▒ Fuel ▒▒▒▒▒░░░░░░░░ 41% ░ Fuel ▒░░░░░░░░░░░░ 5%  
 ▒ Cargo 16/16   Y 62     ░ Cargo 3/16   Y -30     
 ▒ seen 1s ago            ░ seen 3m ago            
```
Stripe and state word in the state colour: lime working, orange waiting, cyan returning, red lost. The last tile is stale (not heard recently): grey stripe, dim text.
```text w=26
 ▒ Canary-04     working  
 ▒ Digging to Y -40       
 ▒ Fuel ▒▒▒▒▒▒▒▒░░░░░ 64% 
 ▒ Cargo 12/16   Y -40    
 ▒ seen 2s ago            
```
```text w=39
 ▒ Canary-04                  working  
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░ 64% 
 ▒ Canary-07                  waiting  
 ▒ Fuel ▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░ 18% 
```
Short screens: two rows, name and fuel.
Whole tile is the tap target: opens that machine's page. A stale tile (no message for more than the screen's stale time) greys the stripe and text and says `not heard 3m` in place of the activity.
States: working, waiting, returning, error, lost, rebooting (purple), docked, stale.
Keys: arrows move a highlight (gold stripe), Enter opens, Esc clears.
Squeeze: see the grid rule in section 1: heights 5 / 3 / 2 rows by screen height, columns by width. On the wall a tile can show a map thumbnail in its spare rows.

### 4.6 Fuel and progress bars

A bar is `Label`, a track, and a number. Fill is a coloured background, track is grey. On screens with the half-block character (`\149`) the fill has half-cell precision.

```text w=40
 Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░ 64%
```
```text w=40
 Fuel ▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░ 18%
```
```text w=40
 Fuel ▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 5% 
```
```text w=40
 Layer ▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░ 37/100
```
Progress fill is cyan.
Colours: fuel lime above 20%, orange 10-20%, red below 10%. Capacity (storage slots): lime below 70%, orange 70-90%, red above 90%. Progress (layer, blocks built): cyan. Unknown value: all-grey track and `-`.
Squeeze: label drops first, then the number, then the bar shrinks to 6 cells minimum.

### 4.7 Notices

A short message in the rule row (row 2) for 5 seconds, then the rule comes back. Coloured by meaning, never gold.

```text w=51
 Reboot sent to Canary-04: it finishes its block.. 
```
Purple: order in flight.
```text w=26
 Reboot sent to Canary-.. 
```
Narrow: cut with `..`.
Colours: lime done, orange careful, red failed, purple sent and waiting, white plain information. Errors stay until tapped or until the next notice; everything else expires.
Taps: a tap on the notice dismisses it. A screen can attach one action (`Undo`).
Rule: the same notice goes to every view of the computer (a computer with a terminal and two monitors shows it on all three).

### 4.8 Text field, search bar and command bar

**Text field.** A grey box with the typed text, a gold cursor and a dim hint when empty. On computers it takes typing; a monitor can show it but cannot type, so the screen says `type on the computer`.

```text w=40
 Name ░Canary-0_░░░░░░░░░░              
```
```text w=40
 Name ░name░of░the░turtle░░░░░░░░       
```
Empty: grey hint text on the box.
States: idle, focused (gold cursor), invalid (box turns red, one line of red text under it says why), disabled. Keys: characters, Backspace, Enter commits, Esc cancels, Tab leaves it.

**Search bar.** The input row at the bottom of list screens (storage style). `>` prompt on a grey bar, the text, a dim hint when empty. The list above filters as you type. Enter opens the top match.

```text w=51
▒>▒░dia_░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```
```text w=26
▒>▒░search,░/░=░commands░░
```
Hint truncated on narrow screens.
**Command bar.** Typing `/` first turns the search bar into a command bar. The list above becomes the command list: name, then what it does. Tab completes, Up/Down choose, Enter runs, Esc backs out.

```text w=38
▓/reboot▓▓reboot▓a▓turtle▓▓▓▓▓▓▓▓▓▓▓▓▓
 /refuel  send fuel to a turtle       
 /retire  retire a number for good    
▒>▒░/re_░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```
Top match gold.
### 4.9 Paged list rows

One row per entry: a name at the left, the value at the right, an optional state colour as a one-cell stripe. The selected row is gold. Rows per page is the free rows between the rule and the footer (less one for an input row).

```text w=51
▒ Diamond                                    1,204 
▒ Iron Ingot                                   48k 
▓▓Redstone▓Dust▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓312▓
▒ Cobbled Deepslate                          4,096 
▒ Netherite Scrap                                6 
```
Stripe is the stock state (lime fine, orange low, red out). Values cyan: you can open them. Selected row gold.
```text w=26
▒ Diamond           1,204 
▒ Iron Ingot          48k 
▓▓Redstone▓Dust▓▓▓▓▓▓▓312▓
```
Taps: tap a row to select it, tap it again (or the value) to open it. A tap on the pager moves a page.
Keys: Up/Down move, PgUp/PgDn page, Home/End first and last, Enter opens, type to search when a search bar is present.
Squeeze: the value is never cut; the name is, with `..`. Narrow drops the stripe.

### 4.10 Map viewport with pan

A framed area of block-coloured cells (soil brown, crops green, water blue, trees dark green, land the stock grey) with the machine drawn as a cyan arrow. It follows the machine until you pan, then a `Follow` button appears.

```text w=21
 ░░▒▒▒▒▒▒░░▒▒▒▒░░░░░ 
 ░▒▒▒▒▒▒▒░░▒▒▒▒░░░░░ 
 ░░▒▒▒▒▒▒▒▒▒▒▒░░░░░▒ 
 ░░░░▒▒▒▒^▒▒▒▒▒░░░░░ 
 ░░░░▒▒▒▒▒▒▒▒▒░░░▒▒░ 
 ░░░░░▒▒▒▒░░░░░▒▒░░░ 
```
Brown soil, green crops, lime saplings, blue water, grey land, cyan `^` the turtle (the arrow points the way it faces: `^ > v <`).
```text w=38
░^░ ░v░ ░<░ ░>░ ▓Follow▓              
```
Pan row, above the footer, when the screen is not short.
Taps: pan buttons move the view by half a viewport; a tap on a cell puts what is there in the notice row (`Wheat, 7/7 grown`); `Follow` snaps back to the machine.
Keys: arrows pan, Home or `f` follows, mouse wheel pans vertically.
Squeeze: the viewport takes every row between the rule and the pan row. Short screens drop the pan row and rely on keys. On wide screens a tile's spare rows show a thumbnail without controls.

## 5. Whole screens

A foreman overview, built only from the components above.

**51x19 advanced computer** (2 columns of 24, 5-row tiles).

```text w=51
▓FOREMAN▓                           4 canaries  ok 
───────────────────────────────────────────────────
 ▒ Canary-04     working  ▒ Canary-07     waiting  
 ▒ Digging to Y -40       ▒ Waiting for fuel       
 ▒ Fuel ▒▒▒▒▒▒▒▒░░░░░ 64% ▒ Fuel ▒▒░░░░░░░░░░░ 18% 
 ▒ Cargo 12/16   Y -40    ▒ Cargo 16/16   Y -12    
 ▒ seen 2s ago            ▒ seen 4s ago            
                                                   
 ▒ Canary-09   returning  ░ Canary-12        lost  
 ▒ Heading home           ░ No reply               
 ▒ Fuel ▒▒▒▒▒░░░░░░░░ 41% ░ Fuel ▒░░░░░░░░░░░░ 5%  
 ▒ Cargo 16/16   Y 62     ░ Cargo 3/16   Y -30     
 ▒ seen 1s ago            ░ seen 3m ago            
                                                   
                                                   
                                                   
                                                   
                                                   
░<░ Back                                 <  1/2 ░>░
```
**39x13 turtle** (1 column of 37, 2-row tiles).

```text w=39
▓FOREMAN▓                           ok 
───────────────────────────────────────
 ▒ Canary-04                  working  
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░ 64% 
                                       
 ▒ Canary-07                  waiting  
 ▒ Fuel ▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░ 18% 
                                       
 ▒ Canary-09                returning  
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░ 41% 
                                       
                                       
░<░                          <  1/2 ░>░
```
**26x20 glasses** (1 column of 24, 5-row tiles).

```text w=26
▓FOREMAN▓              ok 
──────────────────────────
 ▒ Canary-04     working  
 ▒ Digging to Y -40       
 ▒ Fuel ▒▒▒▒▒▒▒▒░░░░░ 64% 
 ▒ Cargo 12/16   Y -40    
 ▒ seen 2s ago            
                          
 ▒ Canary-07     waiting  
 ▒ Waiting for fuel       
 ▒ Fuel ▒▒░░░░░░░░░░░ 18% 
 ▒ Cargo 16/16   Y -12    
 ▒ seen 4s ago            
                          
 ▒ Canary-09   returning  
 ▒ Heading home           
 ▒ Fuel ▒▒▒▒▒░░░░░░░░ 41% 
 ▒ Cargo 16/16   Y 62     
 ▒ seen 1s ago            
░<░             <  1/2 ░>░
```
**57x24 small board**: 2 columns of 27, 5-row tiles, same as the 51 layout with 3 more columns each. **57x38**: 5 rows of tiles per page where the board has them. **164x81 wall**: 6 columns of 26, and the pager disappears when everything fits.

## 6. Keys, in one place

| Key | Does |
|---|---|
| Tab / Shift+Tab | next / previous focus (button, tab, field) |
| Enter | taps the focused control; opens the selected row; commits a field |
| Esc | cancels a field, clears a selection, dismisses an armed button |
| Backspace | back (when not typing) |
| Arrows | move selection or pan the map |
| PgUp / PgDn | previous / next page |
| Home / End | first / last row; Home on a map follows |
| `/` | start a command (in a screen with a search bar) |
| `1`-`9` | jump to tab |
| Mouse wheel | scroll a page / pan |

A tap on a monitor is `monitor_touch`; a click on a computer is `mouse_click`. The kit treats both as a tap at (x, y).

## 7. Code: `shared/ui.lua`

One module, loaded by every controller. It owns the palette, drawing, hit boxes and keys; a screen calls it and never writes to the terminal.

```lua
local ui = require("ui")                     -- repo file shared/ui.lua; devices keep shared files flat, as ui.lua

local view = ui.view(term.current())         -- or a wrapped monitor / glasses; installs the palette,
                                             -- sets text scale 0.5 on monitors, reads W x H and classes
view.on("tap", ...)                          -- optional raw access; screens normally don't need it

function draw(v)
  v:header("FOREMAN", { state = "ok", color = "good", right = "4 canaries" })
  v:notice()                                 -- draws the current notice in the rule row, if any
  v:tiles(items, { height = "auto", render = tileFields, on = openMachine })
  v:footer({ back = goBack, tabs = tabs, page = page, pages = pages })
end
ui.run(views, draw)                          -- event loop: redraw, taps, keys, resize, notices
```

Rules for the code:

- Colours are role names (`ui.c.good`), never `colours.lime`.
- Every drawing call returns where it ended, and registers its hit boxes in the same call, so layout and taps cannot drift apart.
- `ui.say(text, tone)` posts a notice to every view of the computer.
- `ui.confirm` state lives in the kit (one armed button per view, 4-second timer).
- Component functions are small and testable on their own: `ui.layout.tiles(W, H, n)` returns columns, width, height; `ui.hit.find(boxes, x, y)` returns the target. The simulator scenarios test them without a screen.
- Fallback: if a terminal is not colour (`term.isColour()` false), buttons become `[ Label ]`, the stripe becomes `|`, fills become `#` and `-`.
- Migration order: foreman, nether, farmhand and smelter (they already share pasted code), then storage and assignui, then neural and plastic, then the mainframe board, setup, glasses, architect.

## 8. Not decided here

- Per-screen designs (storage, smelter and so on) get their own `docs/design/<screen>.md` using these components.
- Mouse drag on monitors does not exist in CC, so nothing relies on it.
- Glasses: it is not known whether the palette remap applies there; the kit works either way.

## 9. Motion

Signed off by Tanis: concept A, glyphs. One character per icon, four frames, nothing else moves. Written for issue #24.

### 9.1 Rules

1. **Only active things move.** working, building, farming, smelting, waiting, returning and rebooting animate. docked, done, idle, stale, lost and error show a still glyph. A stale or offline machine never animates.
2. **One beat.** Dashboard icons step together on a shared clock at 2 beats a second (`ui.beat(2)`); loading screens run at 4 (`ui.beat(4)`). Icons never carry their own timers or phase offsets, so a beat changes a few cells in the same rows and costs one `blit` per changed row.
3. **Fixed size.** The icon slot is always one character, drawn for every state (still glyph when not animating), so words never shift. Nothing animates bars, numbers, backgrounds, positions or the stripe.
4. **Slow.** Nothing flashes faster than once a second. An error pulses three times when it first appears (`!` red, then white, one second each) and then stays still.
5. **Budget.** At most 24 animated glyphs per view. Past that, the rest show their still glyph. A view with nothing animated redraws only on events, as before.
6. **Calm dashboard.** One glyph per tile header (state word, not the whole tile) and one in the header state. Big motion (flames, sparkles, a long spinner line) belongs on training, picking and loading screens, one thing at a time.
7. **Setting.** `ANIM=full|calm|off` in each device's `.env`, default `full` (glasses: `calm`). `calm` keeps dashboard glyphs and drops loading-screen extras to a spinner only; `off` shows still glyphs everywhere. A terminal that is not colour draws still glyphs.

### 9.2 Glyphs

The glyph sits directly before the state word, with one space between: `\ working`. Colour is the state colour. Frames play in order at the beat.

| State (words that share it) | Frame 1 | 2 | 3 | 4 | Colour |
|---|---|---|---|---|---|
| working (mining, mapping, surveying, clearing, marking) | `\` | `|` | `/` | `|` | lime |
| building | `+` | `x` | `+` | `x` | lime |
| farming (planting, harvesting) | `.` | `,` | `i` | `Y` | green |
| smelting (cooking) | `\30` | `^` | `\30` | `'` | red, orange, yellow, orange |
| waiting | `.` | `o` | `O` | `o` | orange |
| returning | `<` | `\171` (`«`) | `<` | `\171` | cyan |
| rebooting, updating | `|` | `/` | `-` | `\` | purple |

Still glyphs (no animation): docked `=` lightBlue, done `+` lightBlue, idle `-` lightGrey, stale `?` grey, lost and error `!` red (three slow pulses on arrival, see rule 4).

The working glyph reads as a swinging pickaxe: the stroke goes up-left, vertical, up-right, vertical. Four frames of the foreman tile header at 24 wide:

```text w=24
▒ Canary-04   \ working 
▒ Canary-04   | working 
▒ Canary-04   / working 
▒ Canary-04   | working 
```
Frames 1 to 4 top to bottom. Stripe, glyph and state word lime.
```text w=24
▒ Canary-07   . waiting 
▒ Canary-07   o waiting 
▒ Canary-07   O waiting 
▒ Canary-07   o waiting 
```
Waiting, orange.
**Header state.** The header's right-hand state word gets the same glyph (`\ working`). It is the only place on the page that moves besides tiles.

**Buttons.** A `busy` button (an order in flight) keeps its label and puts the rebooting glyph before it, purple, and ignores taps until the order is confirmed.

```text w=12
▒|▒Reboot▒  
▒/▒Reboot▒  
▒-▒Reboot▒  
▒\▒Reboot▒  
```
Purple fill, black text.
### 9.3 Waiting and loading screens

Every screen that waits for something (no reply from storage, a map being fetched, a turtle booting, training) shows four things: the title with a spinner, an indeterminate bar, one line saying what is being tried, and Back. The spinner is the waiting or rebooting glyph at 4 beats a second. The bar is a 6-cell block bouncing in the track at 4 beats a second (one cell per beat). With `ANIM=calm` the bar is still and only the spinner moves.

```text w=36
▓STORAGE▓                   waiting 
────────────────────────────────────
                                    
       | Waiting for storage        
                                    
    ▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░    
                                    
 Asked 3 times. Still no answer.    
                                    
                                    
░<░░Back░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```
Beat 0. Spinner `|`, block at the left of the track.
```text w=36
▓STORAGE▓                   waiting 
────────────────────────────────────
                                    
       - Waiting for storage        
                                    
    ░░░░░░▒▒▒▒▒▒░░░░░░░░░░░░░░░░    
                                    
 Asked 3 times. Still no answer.    
                                    
                                    
░<░░Back░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```
Beat 6. Spinner `-`, block six cells along.
Wording: say what is being waited for and what has been tried, never just `Loading...`. When the wait ends the screen is replaced by the real one; nothing fades or wipes.

### 9.4 Cost and the buffered redraw

The kit writes only changed rows, one `blit` each, and never clears. A beat on the foreman dashboard therefore costs one write for each tile row that holds a moving glyph: at most the number of visible tile rows plus the header. On a 51x19 computer that is 3 rows every half second; on the 164x81 wall, up to 24 glyphs in at most 13 rows, at 2 beats a second.

`ui.run` already redraws non-input events at most every `min_interval` (0.25 s). Motion adds:

- `ui.beat(rate)` returns an integer that increments `rate` times a second from a shared origin; every glyph in a frame reads it, so all glyphs are in step.
- `v:glyph(x, y, state, opts)` draws the glyph for a state at the current beat (still if the machine is stale or `ANIM=off`), counts it against the view's budget and sets `v.animated = true`.
- `ui.run` re-arms its timer for the next beat only while some view drew an animated glyph in the last frame; otherwise it idles as it does now. A screen with no motion costs nothing.
- Loading screens call `v:spinner(x, y)` and `v:indeterminate(x, y, w)`, which use the 4-a-second beat.

### 9.5 The smelter

The smelter keeps its flames, with a smaller job:

- **Home (dashboard):** each cooking furnace tile gets the smelting glyph in its band (replacing the flame on the end of line 1). The random flame row on line 3 and the per-tile offsets go; line 3 shows `x42` and the finished count, still. Nothing else moves.
- **Train and Pick pages:** keep the flames, sparkles and `learning...` dots as they are (one thing happens at a time); move their timer onto `ui.beat(4)` and the shared `ANIM` setting.
- `animating()` becomes the kit's `v.animated`: the smelter stops waking four times a second when nothing on screen moves.

### 9.6 Tests

In the simulator: (1) at 51x19 with four tiles in different states, only working, waiting and returning tiles change between beats, and only in the glyph cell; (2) `ANIM=off` and a stale tile never change; (3) a beat flushes at most one `blit` per changed row and never calls `clear`; (4) 25 animated tiles draw 24 moving glyphs; (5) the timer is not armed when nothing animated.

## 10. Components the screens need beyond sections 4 and 9

Added for issue #26. Every controller's screens (`docs/design/<controller>.md`) use these as well as the components above.

### 10.1 Section label

A dim caps label and a rule to the right edge. Groups a page without boxes.


```text w=51
 LAYERS ────────────────────────────────────────── 
 KEEP IN THE NETHER ────────────────────────────── 
                                                   
```
Label lightGrey caps, rule grey. One blank row above it, none below. Never gold.

### 10.2 Key-value row

Key at the left (dim), value at the right (white, or a state colour). The kit truncates the value last. Used for info pages, reports and status blocks.


```text w=51
 Plan                     island_v3  54,200 blocks 
 Missing                 none (storage has it all) 
 Barrels                            not linked yet 
 GPS                            no, counting moves 
```

### 10.3 Alert line

One row with a stripe in the tone colour and the message in that colour. For problems the user can fix. At most two at a time; red ones stay until the problem goes, orange ones likewise. Neutral status text (a summary line) has no stripe.


```text w=51
 ▒ No OUTPUT yet: items cannot be taken out.       
 ▒ Tap #4 is dry: its log is used up.              
 Stock 64 buckets, 12 lava  Sent home 12k          
```
Orange, red, and a neutral line.

### 10.4 Segmented switch

One choice of a few, drawn as touching pills; the current one is gold. For modes (AUTO / ON / OFF), rules (No rule / Keep N stacks / Smelt all) and sort order. Tap a segment; Left/Right move, Enter picks. Squeeze: labels shorten, then the switch wraps to a second row.


```text w=51
 ▓AUTO▓░ON░░OFF░                                   
 ░No░rule░░Keep░N░stacks░▓Smelt▓all▓               
 Sort ▓Qty▓░A-Z░                                   
```

### 10.5 Board row

A read-only status row: state stripe (and glyph) in the state colour, name, state word, detail, how long since last heard. A row not heard for 30 s goes grey and stops moving. The board header is a grey bar with a gold caps label (it is not a title chip: boards have no page title of their own).


```text w=57
░MACHINES░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
▒ Storage      ok       79% full                       2s
▒ Smelter      ok       6 cooking                      3s
▒ Plastic      running  1,204 made                     2s
```

### 10.6 Picker card

One option at a time as a full gold card, the previous and next options peeking in above and below, a counter at the right, a hint in the footer. For setup. Up/Down, Left/Right, scroll, number keys, click a neighbour; Enter or `Pick >` picks. Wraps around.


```text w=39
▓SETUP▓ step 2 of 3                    
                                       
 Which role?                    1 of 3 
 ^ Foreman                             
 ▓MAINFRAME▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓suggested▓ 
 ▓ Chat, alerts, island strip, stat..  
 ▓                                     
 ▓ The server. Chat commands and al..  
 ▓ showing every machine, and the b..  
 ▓ top-ups, welcomes, visitors and ..  
 ▓                                     
 v Storage                             
 ░<░Back░   up/down browse     ▓Pick▓>▓
```

### 10.7 Report page

A page of key-value rows (and a section label or two) with Back. Opened by commands that print information (`/fuelinfo`, `/drawers`, `status`). Replaces text dumped on the terminal.

### 10.8 Spinner line and wizard steps

A waiting line is a spinner glyph (waiting, orange) then the sentence. A multi-step flow puts `step 2/3` in the header's right text. Both use section 9's glyphs and beats.

### 10.9 Furnace tile (smelter variant of the tile)

Same as the edge-stripe tile, three rows: tier name, item (or `idle`), count and finished-waiting. The stripe is the tier colour (netherite purple, diamond cyan, gold yellow, iron grey-white, plain grey) while cooking and grey when idle; the smelting glyph sits at the right of the top row. Not tappable.


```text w=31
 ▒ Netherite 1^ ░ Diamond 2    
 ▒ raw iron     ░ idle         
 ▒ x64      +12 ░              
```

### 10.10 Padlock

The storage lock screen: a 13x11 line-art padlock in gold, centred, with `LOCKED` and one line of why. No motion, taps ignored.

### 10.11 Whole-screen rules

- A page's actions are buttons in the content or the footer; the footer's left is always Back (when there is a parent), then tabs, then the pager at the right.
- Text the user types lives in a text field or in the input row; a monitor shows it but cannot type, and says `type on the computer`.
- The header chip carries the page title; the state word at the right is the only state in the header.
