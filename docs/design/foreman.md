# Foreman: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/foreman/foreman.lua`

Mining control for every Canary (Overworld). Advanced computer + ender modem; monitor 3x2 (57x24) is typical, the computer's own screen (51x19) works the same.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Overview 57x24 (small board, 3x2)

```text w=57
▓FOREMAN▓                     6 canaries  storage ok  ok 
 Reboot sent to Canary-04: it finishes its block first.  
 ▒ Canary-04      \ working  ▒ Canary-07      o waiting  
 ▒ Digging to Y -40          ▒ Waiting for fuel          
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒░░░░░░ 64% ▒ Fuel ▒▒▒░░░░░░░░░░░░░ 18% 
 ▒ Cargo 12/16   Y -40       ▒ Cargo 16/16   Y -12       
 ▒ seen 2s ago               ▒ seen 4s ago               
                                                         
 ▒ Canary-09    < returning  ▒ Canary-11       = docked  
 ▒ Heading home              ▒ Docked, 3 layers done     
 ▒ Fuel ▒▒▒▒▒▒▒░░░░░░░░░ 41% ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░ 92% 
 ▒ Cargo 16/16   Y 62        ▒ Cargo 0/16   Y 64         
 ▒ seen 1s ago               ▒ seen 3s ago               
                                                         
 ░ Canary-12         ! lost  ▒ Canary-13      \ working  
 ░ not heard for 3m          ▒ Mining chunk 4 of 9       
 ░ Fuel ▒░░░░░░░░░░░░░░░  5% ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒░░░░ 77% 
 ░ Cargo 3/16   Y -30        ▒ Cargo 5/16   Y -58        
 ░ seen 3m ago               ▒ seen 2s ago               
                                                         
                                                         
                                                         
                                                         
▒Presets▒ ▒Reboot▒all▒ ░Retired░(2)░         <  1/2  ░>░ 
```

- Tap a tile: opens that Canary. Arrows move the highlight, Enter opens.
- `Reboot all` is tap-twice (turns red, says `Sure?`).
- `Retired (2)` swaps the overview for retired Canaries (grey, no tiles move).
- Notice sits in the rule row for 5 s.
- Header state word turns orange `no radio` when the ender modem is missing (red notice, stays until fixed).


## Overview 51x19 (computer)

```text w=51
▓FOREMAN▓               6 canaries  storage ok  ok 
───────────────────────────────────────────────────
 ▒ Canary-04   \ working  ▒ Canary-07   o waiting  
 ▒ Digging to Y -40       ▒ Waiting for fuel       
 ▒ Fuel ▒▒▒▒▒▒▒▒░░░░░ 64% ▒ Fuel ▒▒░░░░░░░░░░░ 18% 
 ▒ Cargo 12/16   Y -40    ▒ Cargo 16/16   Y -12    
 ▒ seen 2s ago            ▒ seen 4s ago            
                                                   
 ▒ Canary-09 < returning  ▒ Canary-11    = docked  
 ▒ Heading home           ▒ Docked, 3 layers done  
 ▒ Fuel ▒▒▒▒▒░░░░░░░░ 41% ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒░ 92% 
 ▒ Cargo 16/16   Y 62     ▒ Cargo 0/16   Y 64      
 ▒ seen 1s ago            ▒ seen 3s ago            
                                                   
                                                   
                                                   
                                                   
                                                   
▒Presets▒ ▒Reboot▒all▒                 <  1/2  ░>░ 
```

- Same as 57x24 with 24-wide tiles. `Retired` moves into the `/` commands.


## Overview 39x13 (short)

```text w=39
▓FOREMAN▓                           ok 
───────────────────────────────────────
 ▒ Canary-04                \ working  
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░ 64% 
                                       
 ▒ Canary-07                o waiting  
 ▒ Fuel ▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░ 18% 
                                       
 ▒ Canary-09              < returning  
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░ 41% 
                                       
                                       
▒Presets▒                  <  1/2  ░>░ 
```

- 2-row tiles (name+state, fuel). Message is dropped; tap a tile for it.


## Overview 26x20 / 2x2 display 36x24

```text w=36
▓FOREMAN▓                        ok 
────────────────────────────────────
 ▒ Canary-04             \ working  
 ▒ Digging to Y -40                 
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░ 64% 
 ▒ Cargo 12/16   Y -40              
 ▒ seen 2s ago                      
                                    
 ▒ Canary-07             o waiting  
 ▒ Waiting for fuel                 
 ▒ Fuel ▒▒▒▒░░░░░░░░░░░░░░░░░░░ 18% 
 ▒ Cargo 16/16   Y -12              
 ▒ seen 4s ago                      
                                    
 ▒ Canary-09           < returning  
 ▒ Heading home                     
 ▒ Fuel ▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░ 41% 
 ▒ Cargo 16/16   Y 62               
 ▒ seen 1s ago                      
                                    
                                    
                                    
                                    
▒Presets▒               <  1/2  ░>░ 
```

- One column, 34 wide. On 26x20 the column is 24 wide.


## No Canaries yet

```text w=51
▓FOREMAN▓               0 canaries  storage ok  ok 
───────────────────────────────────────────────────
                                                   
                                                   
                                                   
 | Waiting for the first Canary                    
                                                   
 Set up a turtle as a Canary: drag startup.lua on i
 reboot, pick Miner. It asks me for a number       
 and shows up here.                                
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
▒Presets▒                                          
```

- Waiting screen: spinner and what to do. Replaced by the overview when the first Canary answers.


## Canary page 57x24

```text w=57
▓CANARY-04▓                       seen 2s ago  \ working 
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

- Two columns on regular and wide screens: Status left, Layers right. Footer tabs: Status, Haul.
- Preset rows are a list: tap selects and fills Min Y, Max Y and the rings. `Edit` opens Presets.
- `START` is primary and sends the layers to the Canary. `STOP + DOCK` sends it home. `Reboot` and `Retire` are tap-twice (Retire is permanent: the number is never reused).
- Stale for 15 s: state `lost`/stale grey, buttons stay (orders repeat until it answers).
- `Moved by hand` shows as an orange alert line under the header.


## Canary page 39x13: Info / Layers tabs

```text w=39
▓CANARY-04▓                  \ working 
───────────────────────────────────────
 Digging to Y -40                      
 seen 2s ago                           
                                       
 Fuel  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░ 4,812 
 Cargo ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░ 12/16 
 Layer                             2/3 
 Chunk                  4 of 9, ring 1 
 Range                        -59..-48 
 At                      812 -40 -1203 
                                       
░<░ ▓Info▓ ░Layers░ ░Haul░             
```

- Compact screens split into three tabs: Info, Layers, Haul.


## Canary page 39x13: Layers

```text w=39
▓CANARY-04▓                  \ working 
───────────────────────────────────────
 LAYERS ────────────────────────────── 
   Diamonds                  -59..-58  
 ▓▓Deep▓ores▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓-59..-48▓ 
   Gold                      -19..-13  
 Min Y   ░-░ -59  ░+░                  
 Max Y   ░-░ -48  ░+░                  
 ▓START▓ ░STOP░ ▒Retire▒               
                                       
                                       
                                       
░<░ ░Info░ ▓Layers▓ ░Haul░             
```

- Presets, Min/Max and the order buttons. `Retire` stays here, tap-twice.


## Canary page 26x20: Info

```text w=26
▓CANARY-04▓     \ working 
──────────────────────────
 Digging to Y -40         
 seen 2s ago              
                          
 Fuel  ▒▒▒▒▒▒▒▒░░░░ 4,812 
 Cargo ▒▒▒▒▒▒▒▒▒░░░ 12/16 
                          
 Layer                2/3 
 Chunk     4 of 9, ring 1 
 Range           -59..-48 
 At         812 -40 -1203 
                          
                          
                          
                          
                          
                          
                          
░<░ ▓Info▓ ░Lay░ ░Haul░   
```

- Narrow: labels shorten (`Lay` for Layers).


## Last haul 57x24

```text w=57
▓CANARY-04▓                                    \ working 
─────────────────────────────────────────────────────────
 LAST HAUL ───────────────────────────────────────────── 
 ▒ Diamond                                           12  
 ▒ Iron Ingot                                     1,240  
 ▒ Redstone Dust                                    311  
 ▒ Lapis Lazuli                                      96  
 ▒ Coal                                             402  
 ▒ Gold Ore                                          58  
 ▒ Emerald                                            4  
 ▒ Ancient Debris                                     2  
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back ░Status░ ▓Haul▓                                 
```

- Everything the Canary brought home last trip; values cyan.
- Wide screens show this under Status; compact ones as the Haul tab.


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

- Tap a row to select. `Edit` opens it, `+ New` adds a blank, `Duplicate` copies the selected one.
- Keys: Up/Down, Enter edits, Delete asks (tap-twice).


## Edit preset 57x24

```text w=57
▓EDIT▓PRESET▓                                            
─────────────────────────────────────────────────────────
 Name      ░Deep░ores_░░░░░░░░░░░                        
                                                         
 Min Y     ░-░ -59  ░+░      -63..319                    
 Max Y     ░-░ -48  ░+░                                  
                                                         
 From ring ░-░ 0  ░+░    the dock chunk                  
 To ring   ░-░ 3  ░+░    7x7 chunks                      
                                                         
 4 passes of 3 levels. Past ring 1 needs a chunk loader. 
                                                         
 ▓Save▓ ░Cancel░ ▒Delete▒                                
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- Name is a text field (type on the computer; a monitor shows it only). Steppers: tap `-`/`+`, or Left/Right on the focused one, PgUp/PgDn step 10.
- `Save` is primary, `Delete` is tap-twice, Esc cancels.
- The line under the steppers says how many passes it makes and warns about chunk loading.


## Command bar (computer)

```text w=51
▓FOREMAN▓               6 canaries  storage ok  ok 
───────────────────────────────────────────────────
▓/presets▓▓edit▓the▓layer▓presets▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
 /retire   retire a Canary for good                
 /reboot   reboot one or every Canary              
 /forget   forget a retired Canary                 
 /help     every command                           
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
▒>▒░/pr_░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                                       <  1/2  ░>░ 
```

- Type `/` and the list becomes the command list. Tab completes, Enter runs, Esc backs out. Monitors never show this bar.
