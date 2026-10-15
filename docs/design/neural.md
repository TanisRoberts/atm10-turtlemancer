# Neural lab: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/neural/neural.lua`

A wall of Hostile Neural Networks columns: overview of columns, a page per column.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Overview 57x24

```text w=57
▓NEURAL▓LAB▓                 power 68%  matrices 312  ok 
─────────────────────────────────────────────────────────
 ▒ Column #4 has no fab: build one or set it to Traini.. 
 Furnator fuelled from the dock.                         
                                                         
 ▒ #1 Zombie      \ running  ▒ #2 Skeleton    o stopped  
 ▒ stock 412/512             ▒ stock 256/256             
 ▒ acc 98%                   ▒ acc 97%                   
 ▒                 ▒CHECK▒   ▒                 ▒CHECK▒   
 ▒                           ▒                           
                                                         
 ▒ #3 Creeper     \ running  ▒ #4 Enderman  ! needs you  
 ▒ stock 88/128              ▒ no fab yet                
 ▒ acc 91%                   ▒ training                  
 ▒                 ▒CHECK▒   ▒                           
 ▒                           ▒                           
                                                         
 ▒ #5 Blaze       \ running  ▒ #6 Witch       o stopped  
 ▒ stock 310/512             ▒ stock 64/64               
 ▒ acc 99%                   ▒ acc 94%                   
 ▒                 ▒CHECK▒   ▒                 ▒CHECK▒   
 ▒                           ▒                           
                                                         
░Pause░ ▒Check▒all▒                          <  1/2  ░>░ 
```

- A tile per column (mob): stripe and glyph show running (lime, moving), stopped (orange, still), needs you (red, slow pulse). Rows: stock vs target, accuracy. `CHECK` sends one prediction through to see what the fab makes now.
- Top: power and matrices in the header; the most useful problem in words as an orange or red alert line; a one-line note under it.
- Footer: Pause / Run all, Check all; pager. Lamps on the wall stay as they are (steady / off / blinking).
- Tap a tile: opens that column.


## Overview 39x13

```text w=39
▓NEURAL▓LAB▓                        ok 
───────────────────────────────────────
 ▒ Column #4 has no fab: build one o.. 
                                       
 ▒ #1 Zombie                \ running  
 ▒ stock 412/512                       
                                       
 ▒ #2 Skeleton              o stopped  
 ▒ stock 256/256                       
                                       
 ▒ #3 Creeper               \ running  
 ▒ stock 88/128                        
░Pause░ ▒Check▒all▒        <  1/2  ░>░ 
```

- 2-row tiles (name+state, stock). CHECK moves to the column page.


## Column page 57x24

```text w=57
▓#1▓ZOMBIE▓                          column 1  \ working 
─────────────────────────────────────────────────────────
 Fab makes: rotten flesh                                 
 Pick it in the fab's own screen.                        
                                                         
 Stock  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░ 412 / 512 
 Target  ░-░ 512 ░+░                                     
                                                         
 Mode    ▓AUTO▓░ON░░OFF░   ▒CHECK▒                       
                                                         
 Runs 214, preds 1,980, acc 98%                          
 Made 5,120, banked 1, in fab 4                          
 Matrices 312, C 71% F 64%                               
                                                         
 chamber_5                                               
 fab_5                                                   
 lamp: redstone_relay_3                                  
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- Fab output, stock bar and target stepper (steps of 16, 64 above 256), mode switch AUTO / ON / OFF, CHECK, run stats, and the network names it is paired with.
- Problems for this column show as red alert lines at the bottom.


## Training column

```text w=57
▓#4▓ENDERMAN▓                          training  ! error 
─────────────────────────────────────────────────────────
 Training: levels the model                              
 Then switch the chamber to Inference                    
 (its screen) when it is Self Aware.                     
 Keeps 64 matrices spare.                                
                                                         
 No fab yet: set it to Training and I will feed it.      
                                                         
 Mode    ░AUTO░▓ON▓░OFF░                                 
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- A chamber in Training mode needs no fab; the page explains what to do next. Purple state.
