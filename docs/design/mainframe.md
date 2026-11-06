# Mainframe: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/mainframe/`

The island strip, the status board for every machine and the visitor column on the monitor wall. Read-only.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Wall 82x40 (8x6 at text scale 1): the floor-readable wall

Issue #117, concept B round 2, signed off by Tanis. Review page: https://claude.ai/artifact/M8FxWLe1qTxNVyWQqeNZDQ (example data throughout).

The 8x6 wall runs at `SCALE=1` (`wall.env`), which gives 82x40. Tanis reads it from the foot of the wall, so the top rows are far away and steep. The wall is split in two: the **top half** is the board, to step back and read; the **bottom half** is the glance, read from the floor. **Nothing moves:** every part has fixed rows, empty slots stay blank, and nothing slides up to fill space (the bottom-anchored try that moved the board was reverted in 480764c).

Use this layout when the monitor is at least 80x40. Smaller monitors keep the layouts further down.

### Over output, board page 1

```text w=82
░MACHINES░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│░VISITORS░░░░░░░░░░░
▒ Storage          ok                                      2s│ Alex           here
▒   79% full, 1,204 types, 3 orders waiting                  │ Steve        2h ago
▒ Smelter          ok                                      3s│ Sam          1d ago
▒   6 cooking, next done in 40s, 12 coal left                │                    
▒ Operator         running                                 2s│                    
▒   1 reactor on, level 60%, buffer 41%                      │                    
▒ Plastic          running                                 2s│                    
▒   1,204 made today, 3 trays filling                        │                    
▒ Neural lab       running                                 3s│                    
▒   6 columns, power 68%, 312 matrices                       │                    
▒ Canary-04      \ working                                 2s│                    
▒   Y -40, chunk 3 of 9, carrying 212                        │                    
▒ Canary-07      o waiting                                 4s│                    
▒   Y -12, fuel low (140), waiting for coal                  │                    
▒ Firecrest-02   \ working                                 3s│                    
▒   Y 31, 4 chunks left, fuel 2,100                          │                    
▒ Weaver         + building                                2s│                    
▒   Tower roof, layer 31 of 60, 412 blocks left              │                    
                             o .                             │ You're home        
──────────────────────────────────────────────────────────────────────────────────
                                       │                                          
 ▓ISLAND▓                              │ ░POWER░USE░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
                                       │                                          
 ▒▒▒▒▒▒  ▒▒▒▒▒▒        ▒▒    ▒▒▒▒▒▒    │    ▒▒      ▒▒    ▒▒▒▒▒▒  ▒▒  ▒▒          
 ▒▒  ▒▒  ▒▒      ▒▒  ▒▒▒▒        ▒▒    │  ▒▒▒▒    ▒▒▒▒        ▒▒      ▒▒          
 ▒▒  ▒▒  ▒▒▒▒▒▒        ▒▒    ▒▒▒▒▒▒    │    ▒▒      ▒▒    ▒▒▒▒▒▒    ▒▒            
 ▒▒  ▒▒  ▒▒  ▒▒  ▒▒    ▒▒    ▒▒        │    ▒▒      ▒▒        ▒▒  ▒▒              
 ▒▒▒▒▒▒  ▒▒▒▒▒▒      ▒▒▒▒▒▒  ▒▒▒▒▒▒    │  ▒▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒  ▒▒          
                                       │                                          
 Night  day 12  Clear                  │  3,400 of 3,000 FE/t                     
 Moon full  Plains  Light 7/0          │  Over output, buffer 41% falling         
                                       │                                          
 NEEDS YOU ────────────────────────────────────────────────────────────────────── 
 ▒ Canary-12 lost: not heard since 05:58, last at Y -51                           
 ▒ Canary-07 waiting: fuel low, no coal in Storage                                
                                                                                  
                                                                                  
                                                                                  
 All clear on the island (2 other things nearby)                                  
```

### Board page 2 (3 s later)

```text w=82
░MACHINES░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│░VISITORS░░░░░░░░░░░
▒ Seagull          mapping                                 5s│ Alex           here
▒   61%, 214 chunks, flying to region 7                      │ Steve        2h ago
▒ Farmhand         ok                                      4s│ Sam          1d ago
▒   all fine, 4 fields, wheat ready in 6m                    │                    
▒ Partridge-01   \ working                                 2s│                    
▒   round 12, wheat field 2, 340 picked                      │                    
▒ Woodpecker-01  = docked                                  8s│                    
▒   next round in 18m, 96 logs last round                    │                    
▒ Bowerbird-01   = docked                                  6s│                    
▒   idle, last made 32 chests                                │                    
░ Canary-12      ! lost                                    3m│                    
░   not heard since 05:58, last at Y -51                     │                    
                                                             │                    
                                                             │                    
                                                             │                    
                                                             │                    
                                                             │                    
                                                             │                    
                             . o                             │ You're home        
──────────────────────────────────────────────────────────────────────────────────
                                       │                                          
 ▓ISLAND▓                              │ ░POWER░USE░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
                                       │                                          
 ▒▒▒▒▒▒  ▒▒▒▒▒▒        ▒▒    ▒▒▒▒▒▒    │    ▒▒      ▒▒    ▒▒▒▒▒▒  ▒▒  ▒▒          
 ▒▒  ▒▒  ▒▒      ▒▒  ▒▒▒▒        ▒▒    │  ▒▒▒▒    ▒▒▒▒        ▒▒      ▒▒          
 ▒▒  ▒▒  ▒▒▒▒▒▒        ▒▒    ▒▒▒▒▒▒    │    ▒▒      ▒▒    ▒▒▒▒▒▒    ▒▒            
 ▒▒  ▒▒  ▒▒  ▒▒  ▒▒    ▒▒    ▒▒        │    ▒▒      ▒▒        ▒▒  ▒▒              
 ▒▒▒▒▒▒  ▒▒▒▒▒▒      ▒▒▒▒▒▒  ▒▒▒▒▒▒    │  ▒▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒  ▒▒          
                                       │                                          
 Night  day 12  Clear                  │  3,400 of 3,000 FE/t                     
 Moon full  Plains  Light 7/0          │  Over output, buffer 41% falling         
                                       │                                          
 NEEDS YOU ────────────────────────────────────────────────────────────────────── 
 ▒ Canary-12 lost: not heard since 05:58, last at Y -51                           
 ▒ Canary-07 waiting: fuel low, no coal in Storage                                
                                                                                  
                                                                                  
                                                                                  
 All clear on the island (2 other things nearby)                                  
```

### Throttled

```text w=82
░MACHINES░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│░VISITORS░░░░░░░░░░░
▒ Storage          ok                                      2s│ Alex           here
▒   79% full, 1,204 types, 3 orders waiting                  │ Steve        2h ago
▒ Smelter          ok                                      3s│ Sam          1d ago
▒   6 cooking, next done in 40s, 12 coal left                │                    
▒ Operator         running                                 2s│                    
▒   1 reactor on, level 60%, buffer 41%                      │                    
▒ Plastic          running                                 2s│                    
▒   1,204 made today, 3 trays filling                        │                    
▒ Neural lab       running                                 3s│                    
▒   6 columns, power 68%, 312 matrices                       │                    
▒ Canary-04      \ working                                 2s│                    
▒   Y -40, chunk 3 of 9, carrying 212                        │                    
▒ Canary-07      o waiting                                 4s│                    
▒   Y -12, fuel low (140), waiting for coal                  │                    
▒ Firecrest-02   \ working                                 3s│                    
▒   Y 31, 4 chunks left, fuel 2,100                          │                    
▒ Weaver         + building                                2s│                    
▒   Tower roof, layer 31 of 60, 412 blocks left              │                    
                             o .                             │ You're home        
──────────────────────────────────────────────────────────────────────────────────
                                       │                                          
 ▓ISLAND▓                              │ ░POWER░USE░░░░░░░░░░░░░░░░░░░▒THROTTLED▒ 
                                       │                                          
 ▒▒▒▒▒▒  ▒▒▒▒▒▒        ▒▒    ▒▒▒▒▒▒    │  ▒▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒  ▒▒                  
 ▒▒  ▒▒  ▒▒      ▒▒  ▒▒▒▒        ▒▒    │  ▒▒  ▒▒  ▒▒  ▒▒      ▒▒                  
 ▒▒  ▒▒  ▒▒▒▒▒▒        ▒▒    ▒▒▒▒▒▒    │  ▒▒▒▒▒▒  ▒▒  ▒▒    ▒▒                    
 ▒▒  ▒▒  ▒▒  ▒▒  ▒▒    ▒▒    ▒▒        │      ▒▒  ▒▒  ▒▒  ▒▒                      
 ▒▒▒▒▒▒  ▒▒▒▒▒▒      ▒▒▒▒▒▒  ▒▒▒▒▒▒    │  ▒▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒  ▒▒                  
                                       │                                          
 Night  day 12  Clear                  │  Throttled at 2,700 FE/t                 
 Moon full  Plains  Light 7/0          │  Asked for 4,800 (160%) for 2m           
                                       │                                          
 NEEDS YOU ────────────────────────────────────────────────────────────────────── 
 ▒ Power throttled: the base wants more than 150% of the reactor. Add power.      
 ▒ Canary-12 lost: not heard since 05:58, last at Y -51                           
 ▒ Canary-07 waiting: fuel low, no coal in Storage                                
                                                                                  
                                                                                  
 All clear on the island (2 other things nearby)                                  
```

### All clear (nothing needs you)

```text w=82
░MACHINES░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│░VISITORS░░░░░░░░░░░
▒ Storage          ok                                      2s│ Alex           here
▒   79% full, 1,204 types, 3 orders waiting                  │ Steve        2h ago
▒ Smelter          ok                                      3s│ Sam          1d ago
▒   6 cooking, next done in 40s, 12 coal left                │                    
▒ Operator         running                                 2s│                    
▒   1 reactor on, level 60%, buffer 41%                      │                    
▒ Plastic          running                                 2s│                    
▒   1,204 made today, 3 trays filling                        │                    
▒ Neural lab       running                                 3s│                    
▒   6 columns, power 68%, 312 matrices                       │                    
▒ Canary-04      \ working                                 2s│                    
▒   Y -40, chunk 3 of 9, carrying 212                        │                    
▒ Canary-07      o waiting                                 4s│                    
▒   Y -12, fuel low (140), waiting for coal                  │                    
▒ Firecrest-02   \ working                                 3s│                    
▒   Y 31, 4 chunks left, fuel 2,100                          │                    
▒ Weaver         + building                                2s│                    
▒   Tower roof, layer 31 of 60, 412 blocks left              │                    
                             o .                             │ You're home        
──────────────────────────────────────────────────────────────────────────────────
                                       │                                          
 ▓ISLAND▓                              │ ░POWER░USE░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
                                       │                                          
 ▒▒▒▒▒▒  ▒▒▒▒▒▒        ▒▒    ▒▒▒▒▒▒    │  ▒▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒  ▒▒                  
 ▒▒  ▒▒  ▒▒      ▒▒  ▒▒▒▒        ▒▒    │  ▒▒          ▒▒      ▒▒                  
 ▒▒  ▒▒  ▒▒▒▒▒▒        ▒▒    ▒▒▒▒▒▒    │  ▒▒▒▒▒▒  ▒▒▒▒▒▒    ▒▒                    
 ▒▒  ▒▒  ▒▒  ▒▒  ▒▒    ▒▒    ▒▒        │  ▒▒  ▒▒  ▒▒      ▒▒                      
 ▒▒▒▒▒▒  ▒▒▒▒▒▒      ▒▒▒▒▒▒  ▒▒▒▒▒▒    │  ▒▒▒▒▒▒  ▒▒▒▒▒▒  ▒▒  ▒▒                  
                                       │                                          
 Night  day 12  Clear                  │  1,840 of 3,000 FE/t                     
 Moon full  Plains  Light 7/0          │  Buffer 76%                              
                                       │                                          
 NEEDS YOU ────────────────────────────────────────────────────────────────────── 
 Nothing needs you.                                                               
 15 machines: 12 working, 3 docked, none lost                                     
                                                                                  
                                                                                  
                                                                                  
 All clear on the island (2 other things nearby)                                  
```

### Rows

| Rows | What |
|---|---|
| 1 | Board header `MACHINES` (columns 1-61), divider at 62, `VISITORS` header (63-82) |
| 2-19 | 9 machine entries, two rows each (board), visitors one per row |
| 20 | Page dots, centred under the board (`o` current, `.` others); visitor foot (`You're home` lime, or `Away 12m, locked` orange) |
| 21 | Thin rule, full width |
| 22-33 | Clock column (2-39) and power column (42-81), divider at 40 |
| 34 | `NEEDS YOU` section label (gold caps, rule to the right edge) |
| 35-38 | Four Needs you slots |
| 40 | Island line: `All clear on the island (2 other things nearby)` lime, or the danger line red |

### Board (top half)

- **Two-row entry** (kit 10.12). Row 1: state stripe, name (14 wide), glyph and state word in the state colour, last heard right-aligned. Row 2: the details, indented 4, dim, cut to fit with `..`. The stripe runs down both rows.
- Details come from the row's existing `detail`. Senders may make it longer now (up to 56 characters fits), e.g. `Y 31, 4 chunks left, fuel 2,100`.
- **Fixed order:** grouped by system (Storage, Mining, Farming, Building, Labs), then by name. A machine keeps its slot and page. Problems don't move up on the board; they show in Needs you.
- **Pages:** 9 entries a page. When there are more, all of them turn every 3 s (`PAGE_S=3` in `wall.env`), like a departures board. A short last page leaves its slots blank. One page: no dots.
- Not heard for 30 s: the whole entry goes grey, stripe grey, last heard orange.
- Visitors: as today, one row each, name left, when right; at most 18 rows.

### Glance (bottom half)

- **Clock column:** gold `ISLAND` chip (row 23); time in block digits (rows 25-29, kit 10.13, pixel 2 wide x 1 tall, white); row 31 phase (Night red, otherwise gold), `day N` dim, weather (Clear lightBlue, else orange); row 32 moon, biome, light, dim.
- **Power column** (data from #119/#121, via the Operator's broadcast): grey `POWER USE` header bar (row 23); use as a percentage of the reactor's potential in block digits (rows 25-29); row 31 `3,400 of 3,000 FE/t` (white); row 32 a dim or toned note.
  - Under 100%: lime digits, note `Buffer 76%` dim.
  - 100% and up, not throttled: orange digits, note `Over output, buffer 41% falling` orange. Not an alert: Tanis is fine with surges.
  - Throttled (`power.limit` set, #121): red digits showing the capped use, a red `THROTTLED` tag at the right end of the header, row 31 `Throttled at 2,700 FE/t`, row 32 `Asked for 4,800 (160%) for 2m` red.
  - No power data (Operator not heard for 30 s, or no detector): dim `--`, row 31 `Operator not reporting` dim.
- **Needs you** (kit 10.14): four slots, worst first: `Power throttled: ...` (red, only while throttled), then lost and error machines (red), then waiting ones (orange), each with what is wrong. More than four: slot 4 says `+3 more: Smelter, Seagull, ...` in orange. Empty: slot 1 `Nothing needs you.` lime, slot 2 a dim summary `15 machines: 12 working, 3 docked, none lost`, slots 3-4 blank.
- Read-only: nothing to tap, no keys.

## Wall 57x24 (3x2 board)

```text w=57
▒ISLAND▒ 06:12  Night  day 12  Clear                     
 Moon full  Biome plains  Light 7/0                      
 All clear (2 other things nearby)                       
─────────────────────────────────────────────────────────
░MACHINES░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│░VISITORS░░░░░░░ 
▒ Storage      ok       79% full     2s│ Alex       here 
▒ Smelter      ok       6 cooking    3s│ Steve    2h ago 
▒ Plastic      running  1,204 made   2s│ Sam      1d ago 
▒ Neural lab   running  6 columns,.. 3s│                 
▒ Canary-04   \ working Y -40, car.. 2s│                 
▒ Canary-07   o waiting Y -12, fue.. 4s│                 
▒ Weaver      + buildinglayer 31/60  2s│                 
▒ Seagull      mapping  61%, 214 c.. 5s│                 
▒ Farmhand     ok       all fine     4s│                 
▒ Partridge-01\ working round 12, .. 2s│                 
▒ Woodpecker-0= docked  next in 18m  8s│                 
░ Canary-12   ! lost    not heard .. 3m│                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │ You're home     
```

- Island strip (3 lines), divider, the status board with the visitor column at right (the visitor column appears at 50+ wide). Read-only: nothing to tap.
- Board rows: state stripe and glyph in the state colour, name, state word, detail, last heard; rows older than 30 s go grey and stop moving.
- Strip: time, phase (Night red), day, weather; moon, biome, light; danger (red) or all clear (lime).
- Visitor column footer: `You're home` (lime) or `Away 12m, locked` (orange).


## Wall 57x38 (3x3 board)

```text w=57
▒ISLAND▒ 06:12  Night  day 12  Clear                     
 Moon full  Biome plains  Light 7/0                      
 All clear (2 other things nearby)                       
─────────────────────────────────────────────────────────
░MACHINES░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│░VISITORS░░░░░░░ 
▒ Storage      ok       79% full     2s│ Alex       here 
▒ Smelter      ok       6 cooking    3s│ Steve    2h ago 
▒ Plastic      running  1,204 made   2s│ Sam      1d ago 
▒ Neural lab   running  6 columns,.. 3s│                 
▒ Canary-04   \ working Y -40, car.. 2s│                 
▒ Canary-07   o waiting Y -12, fue.. 4s│                 
▒ Weaver      + buildinglayer 31/60  2s│                 
▒ Seagull      mapping  61%, 214 c.. 5s│                 
▒ Farmhand     ok       all fine     4s│                 
▒ Partridge-01\ working round 12, .. 2s│                 
▒ Woodpecker-0= docked  next in 18m  8s│                 
░ Canary-12   ! lost    not heard .. 3m│                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │                 
                                       │ You're home     
```

- More rows of machines; the strip stays 3 lines. If rows run out of room the board pages every 8 s (pager dots in the footer).


## Board only 36x24 (2x2 display)

```text w=36
▒ISLAND▒ 06:12  Night  day 12  Clear
 Moon full  Biome plains  Light 7/0 
 All clear (2 other things nearby)  
────────────────────────────────────
░MACHINES░░░░░░░░░░░░░░░░░░░░░░░░░░░
▒ Storage      ok       79% full  2s
▒ Smelter      ok       6 cooking 3s
▒ Plastic      running  1,204 m.. 2s
▒ Neural lab   running  6 colum.. 3s
▒ Canary-04   \ working Y -40, .. 2s
▒ Canary-07   o waiting Y -12, .. 4s
▒ Weaver      + buildinglayer 3.. 2s
▒ Seagull      mapping  61%, 21.. 5s
▒ Farmhand     ok       all fine  4s
▒ Partridge-01\ working round 1.. 2s
▒ Woodpecker-0= docked  next in.. 8s
░ Canary-12   ! lost    not hea.. 3m
                                    
                                    
                                    
                                    
                                    
                                    
                                    
```

- No visitor column below 50 wide; the strip is 3 lines, the board uses the rest.


## Wall 164x81 (8x6 at text scale 0.5)

- Replaced by the 82x40 wall above: an 8x6 runs at text scale 1. At 0.5 the code may keep today's three-column layout, but it is no longer the target.
