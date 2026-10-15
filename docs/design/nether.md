# Nether Foreman: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/nether/nether.lua`

Firecrest control plus the Nether dock barrels. Same shape as the Foreman, with a barrels status line, a Rules page and the shared /assign screen.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Overview 57x24

```text w=57
▓NETHER▓FOREMAN▓            3 firecrests  storage ok  ok 
 Reboot sent to Firecrest-02: it finishes its block fi.. 
 Stock 64 buckets, 12 lava  Sent home 12k                
 ▒ Firecrest-01   \ working  ▒ Firecrest-02 < returning  
 ▒ Mining Y 34..40           ▒ Drinking lava first       
 ▒ Fuel ▒▒▒▒▒▒▒▒▒░░░░░░░ 58% ▒ Fuel ▒▒▒▒░░░░░░░░░░░░ 22% 
 ▒ Cargo 9/16   Y 36         ▒ Cargo 14/16  Y 40         
 ▒ seen 2s ago               ▒ seen 3s ago               
                                                         
 ▒ Firecrest-03    = docked                              
 ▒ Docked, supplies loaded                               
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 97%                             
 ▒ Cargo 0/16   Y 64                                     
 ▒ seen 1s ago                                           
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
▒Presets▒ ▒Rules▒ ▒Barrels▒ ▒Reboot▒all▒     <  1/1   >  
```

- Same as the Foreman overview, with a status line under the header about the barrels (orange `Tap Barrels to give them jobs`, red `Output full`, lime-grey stock line).
- Header right text: firecrest count and `out 24/27 free`.
- `Rules` and `Barrels` open their own pages. `Reboot all` is tap-twice.


## Overview 39x13

```text w=39
▓NETHER▓FOREMAN▓                    ok 
───────────────────────────────────────
 Stock 64 buckets, 12 lava  Sent hom.. 
 ▒ Firecrest-01             \ working  
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░ 58% 
                                       
 ▒ Firecrest-02           < returning  
 ▒ Fuel ▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░ 22% 
                                       
 ▒ Firecrest-03              = docked  
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░ 97% 
                                       
▒Presets▒ ▒Rules▒          <  1/1   >  
```

- Short: 2-row tiles. Barrels moves into the footer menu (`/assign` still works on the computer).


## Firecrest page 57x24

```text w=57
▓FIRECREST-01▓                    seen 2s ago  \ working 
─────────────────────────────────────────────────────────
 Digging to Y -40             LAYERS ─────────────▒Edit▒ 
                                Diamonds       -59..-58  
 Fuel  ▒▒▒▒▒▒▒▒▒▒░░░░░ 4,812  ▓▓Deep▓ores▓▓▓▓▓▓-59..-48▓ 
 Cargo ▒▒▒▒▒▒▒▒▒▒▒░░░░ 12/16    Gold           -19..-13  
                                Lapis             -3..3  
 Layer                   2/3                             
 Chunk        4 of 9, ring 1  Min Y   ░-░ -59  ░+░       
 Range              -59..-48  Max Y   ░-░ -48  ░+░       
 At            812 -40 -1203  Rings   ░-░ 0  ░+░         
 Overworld       facing east                             
 Dock           800 64 -1200  ▓START▓ ░STOP░+░DOCK░      
 GPS                     yes                             
 Gear           loader + box  ░Reboot░ ▒Retire▒          
 Barrels   linked to storage                             
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back ▓Status▓ ░Haul░                                 
```

- Identical to the Foreman Canary page: Status | Layers, Haul tab. Y range is 6..120 (Nether).
- Extra info rows: `Lava` (fuel top-up state) and `Dock` barrel.


## Presets 57x24

```text w=57
▓PRESETS▓                                      6 presets 
─────────────────────────────────────────────────────────
 Name                           Y range       Chunks     
   Diamonds                     -59..-58      r0-3       
 ▓▓Deep▓ores▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓-59..-48▓▓▓▓▓▓r0-3▓▓▓▓▓▓ 
   Gold                         -19..-13      r0-3       
   Lapis                        -3..3         r0-3       
   Iron                         13..19        r0-3       
   Coal + copper                40..55        r2-5       
                                                         
 ▒+▒New▒ ▒Edit▒ ░Duplicate░                              
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 Presets are what the Layers list on a Canary page offers
                                                         
░<░ Back                                                 
```

- Same as the Foreman; defaults are Nether ranges (ring 1 default).


## Edit preset 57x24

```text w=57
▓EDIT▓PRESET▓                                            
─────────────────────────────────────────────────────────
 Name      ░Deep░ores_░░░░░░░░░░░                        
                                                         
 Min Y     ░-░  34  ░+░      -63..319                    
 Max Y     ░-░  40  ░+░                                  
                                                         
 From ring ░-░ 0  ░+░    the dock chunk                  
 To ring   ░-░ 3  ░+░    7x7 chunks                      
                                                         
 4 passes of 3 levels. Past ring 1 needs a chunk loader. 
                                                         
 ▓Save▓ ░Cancel░ ▒Delete▒                                
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- Same as the Foreman.


## Rules 57x24

```text w=57
▓RULES▓                                   6 kept, 9 junk 
─────────────────────────────────────────────────────────
 LAVA ────────────────────────────────────────────────── 
 Drink under  ░-░ 25% ░+░      until ░-░ 75% ░+░         
                                                         
 KEEP IN THE NETHER ──────────────────────────────────── 
 Item                         keep                have   
 Bucket                   ░-░  64 ░+░               64   
 Lava Bucket              ░-░  16 ░+░               12   
 Coal                     ░-░ 128 ░+░              310   
 Cobblestone              ░-░  0  ░+░               45   
 Torch                    ░-░  64 ░+░               22   
                                                         
 JUNK ────────────────────────────────────────────────── 
 netherrack  basalt  blackstone  cobbled deepslate  tuff 
 gravel  soul sand  magma block  nether bricks           
                                                         
 ▒+▒Keep▒ ░+░Junk░                                       
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- Lava: when Firecrests drink (`-`/`+` 5% steps). Keep: what stays in the Nether; the `keep` stepper is per item, `have` goes orange when below. Junk: what Firecrest throws away underground.
- `+ Keep` and `+ Junk` open a search list of items (same list as storage).
- Commands: `/keep`, `/junk`, `/unjunk`.


## Rules 39x13

```text w=39
▓RULES▓                                
───────────────────────────────────────
 LAVA ──────────────────────────────── 
 Drink under  ░-░ 25% ░+░              
 Until        ░-░ 75% ░+░              
                                       
 KEEP IN THE NETHER ────────────────── 
 Item              keep         have   
 Bucket        ░-░  64 ░+░        64   
 Lava Bucket   ░-░  16 ░+░        12   
 Coal          ░-░ 128 ░+░       310   
 Cobblestone   ░-░  0  ░+░        45   
░<░                                    
```

- Compact: steppers stack under their labels; lists scroll with the pager.


## Barrels (assign) 57x24

```text w=57
▓BARRELS▓                                     6 assigned 
─────────────────────────────────────────────────────────
 Which barrel does what, on the Nether cable.            
                                                         
 ▒ barrel_12   Dock      Firecrest-01             120    
 ▒ barrel_13   Dock      Firecrest-02             0      
 ▒ barrel_14   Dock      Firecrest-03             64     
 ▓▓barrel_20▓▓▓Output▓▓▓▓to▓home▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓31▓▓▓▓ 
 ▒ barrel_21   Stock     buckets, coal            412    
 ▒ barrel_22   Input     hand drop                0      
                                                         
 ▒+▒Add▒ ▒Edit▒                                          
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 Same screen as storage /assign.                         
                                                         
░<░ Back                                                 
```

- The shared `/assign` screen, specified once under Storage. Jobs here: Dock, Output, Stock, Input, Ignore.
