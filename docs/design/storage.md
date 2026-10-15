# Storage: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/storage/storage.lua, shared/assignui.lua`

Item search and take screen (monitor touch or computer search bar), commands, the lock screen and /assign.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Item list: monitor 57x24 (touch)

```text w=57
▓STORAGE▓                     1,203/1,512 slots  79%  ok 
─────────────────────────────────────────────────────────
 Sort ▓Qty▓░A-Z░                                         
 Cobbled Deepslate                                 4,096 
 Iron Ingot                                          48k 
▓Redstone▓Dust▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓12k▓
 Diamond                                           1,204 
 Coal                                              9,310 
 Lapis Lazuli                                      2,880 
 Gold Ingot                                        1,642 
 Oak Log                                             960 
 Sand                                              2,112 
 Glass                                               640 
 Netherite Scrap                                       6 
 Copper Ingot                                      7,410 
 Quartz                                            1,024 
 Ender Pearl                                          72 
 Blaze Rod                                           128 
 Gunpowder                                           560 
 Bone                                                320 
 String                                              410 
                                                         
                                                         
░x1░ ▓x16▓ ░Stack░                          <  1/19  ░>░ 
```

- Tap an item to send it to the output chest (amount from the take buttons). Sort Qty / A-Z at the top. `x1 x16 Stack` live in the footer on a monitor.
- Header right: slots used and fill percent (orange from 90%). Notice row: `Sent 16 Diamond to the output chest`.
- Wheel and the pager page through the list; the monitor has no search (type on the computer).
- Row: name left, count right (cyan = you can act on it).


## Item list: computer 51x19 (search)

```text w=51
▓STORAGE▓               1,203/1,512 slots  79%  ok 
───────────────────────────────────────────────────
 Sort ▓Qty▓░A-Z░            ░x1░ ▓x16▓ ░Stack░     
 Cobbled Deepslate                           4,096 
 Iron Ingot                                    48k 
▓Redstone▓Dust▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓12k▓
 Diamond                                     1,204 
 Coal                                        9,310 
 Lapis Lazuli                                2,880 
 Gold Ingot                                  1,642 
 Oak Log                                       960 
 Sand                                        2,112 
 Glass                                         640 
 Netherite Scrap                                 6 
 Copper Ingot                                7,410 
 Quartz                                      1,024 
 Ender Pearl                                    72 
▒>▒░ing_░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                                      <  1/19  ░>░ 
```

- The computer has a search bar at the bottom (kit search): the list filters as you type; Enter sends the top item; `/` starts a command.
- Take buttons sit on the Sort row.
- Click a row to send it.


## Item list: 39x13 / 26x20

```text w=39
▓STORAGE▓                           ok 
───────────────────────────────────────
 Sort ▓Qty▓░A-Z░░x1░ ▓x16▓ ░Stack░     
 Cobbled Deepslate               4,096 
 Iron Ingot                        48k 
▓Redstone▓Dust▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓12k▓
 Diamond                         1,204 
 Coal                            9,310 
 Lapis Lazuli                    2,880 
 Gold Ingot                      1,642 
 Oak Log                           960 
▒>▒░type░to░search,░/░for░commands░░░░░
                          <  1/19  ░>░ 
```

- Short: Sort row stays, list gets the free rows; take buttons drop into the `/` commands (`/x16`).


## Command list (type /)

```text w=51
▓STORAGE▓               1,203/1,512 slots  79%  ok 
───────────────────────────────────────────────────
 Sort ▓Qty▓░A-Z░            ░x1░ ▓x16▓ ░Stack░     
▓/assign▓▓▓inputs,▓output,▓docks,▓fuel...▓▓▓▓▓▓▓▓▓▓
 /setup    assign chests with marker items         
 /rescan   re-read every chest now                 
 /drawers  what storage sees in the drawers        
 /tidy     biggest piles into biggest drawers      
 /fuelinfo Canary fuel barrels and fuel stock      
 /lock     lock the monitor                        
 /unlock   lift a /lock                            
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
▒>▒░/as_░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                                      <  1/19  ░>░ 
```

- The search bar becomes a command bar; the list is the command list. Tab completes, Enter runs, Esc backs out.


## Locked screen (monitor)

```text w=57
                                                         
                                                         
                                                         
                         .-----.                         
                        / .---. \                        
                        | |   | |                        
                        | |   | |                        
                      .-'-'---'-'-.                      
                      |           |                      
                      |    .-.    |                      
                      |    '-'    |                      
                      |     |     |                      
                      |     |     |                      
                      '-----------'                      
                                                         
                         LOCKED                          
              You are away from the island               
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
```

- Shown on the monitor while the butler says you are away, or after `/lock`. Ignores taps. The padlock is drawn at the biggest text scale that fits (gold, no motion). The computer's own screen always works.


## Assign list 57x24

```text w=57
▓ASSIGNED▓STORAGE▓                         9 inventories 
─────────────────────────────────────────────────────────
 ▒ No OUTPUT yet: items cannot be taken out.             
                                                         
 Network name          Job          Nickname / in it     
 ▒ barrel_10           Input        ore in        0      
 ▒ barrel_11           Input        mob farm      12     
 ▓▓barrel_74▓▓▓▓▓▓▓▓▓▓▓Dock▓▓▓▓▓▓▓▓▓Canary▓fuel▓▓▓64▓▓▓▓ 
 ▒ barrel_20           Fuel         Canary-04     1 st   
 ▒ barrel_30           Weaver       supply        240    
 ▒ barrel_31           Pocket dump  dump          0      
 ▒ drawer_5            Drawers      (by name)     ...    
 ░ barrel_90           Ignore       spare                
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 ▒+▒Add▒                                                 
                                                         
                                                         
░<░ Back                                     <  1/1   >  
```

- Shared by storage and the Nether Foreman. List of inventories with a job: tap a row to edit, `+ Add`. `(by name)` rows (drawers found by name) cannot be deleted.
- Orange alert line for problems (`No OUTPUT yet`).


## Assign: add

```text w=57
▓ADD▓AN▓INVENTORY▓                watching...  o waiting 
─────────────────────────────────────────────────────────
 Type part of its name to narrow it down, or drop one ite
                                                         
 ░barrel__░░░░░░░░░░░░░░░░░░░░░                          
                                                         
 ▓▓barrel_74▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓barrel▓ 
   barrel_75                                     barrel  
   barrel_76                                     barrel  
                                                         
                                                         
 | Find it: drop ONE item into the barrel you mean.      
   Nothing gets moved while I watch. 24 s left.          
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 ▒Find▒it▒                                               
                                                         
                                                         
░<░ Back                                                 
```

- Type to narrow, or `Find it`: drop one item in the barrel you mean (spinner, 30 s, storage stops moving items while it watches).


## Assign: edit

```text w=57
▓EDIT:▓BARREL_74▓                                        
─────────────────────────────────────────────────────────
 Pick its job, then Save.                                
                                                         
 ░Input░░░░░░░░░░  ▓Output▓▓▓▓▓▓▓▓▓  ░Dock░░░░░░░░░░░    
                                                         
 ░Canary░fuel░░░░  ░Weaver░supply░░  ░Pocket░dump░░░░    
                                                         
 ░Pocket░restock░  ░Drawers░░░░░░░░  ░Ignore░░░░░░░░░    
                                                         
                                                         
 ▒ Replaces barrel_20; that one has no job then.         
                                                         
 Nickname  ░output░chest_░░░░░░░░░░                      
                                                         
                                                         
 ▓Save▓ ▒Delete▒                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- Job buttons 3 per row (gold = current). Warning line when the job is single-only (`Replaces ...`). Nickname is a text field. `Delete` is tap-twice.


## Report page (/fuelinfo, /drawers)

```text w=57
▓FUEL▓INFO▓                                   3 Canaries 
─────────────────────────────────────────────────────────
 Canary-04 barrel                                1 stack 
 Canary-07 barrel                              0.4 stack 
 Canary-09 barrel                                1 stack 
                                                         
 Fuel in storage                              9,310 coal 
 Enough for                             about 38 refills 
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- Commands that print information open a report page: key/value rows, Back to return. Same layout for `/drawers`.
