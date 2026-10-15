# Mainframe: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/mainframe/`

The island strip, the status board for every machine and the visitor column on the monitor wall. Read-only.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


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


## Wall 164x81 (8x6)

- Three columns: the Island Station (large, with the nearby list), the board, and visitors, each with its own header chip; machines group by system under section labels (Storage, Mining, Farming, Building, Labs). Same components, more room; built when the board is migrated.
