# Architect: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/architect/architect.lua`

Weaver's controller. Terminal only (no monitor): tabs, orders, a map, a bill and a log.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Status 51x19

```text w=51
▓ARCHITECT▓     Weaver-01  seen 2s ago  + building 
───────────────────────────────────────────────────
 Plan          island_v3  54,200 blocks, 60 layers 
 Now          Layer 31 of 60 (Y 41), block 412/940 
 Layer   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░ 44% 
 Build                      23,420 / 54,200 placed 
 Overall ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░ 43% 
 Fuel    ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░ 12,400 
                                                   
 At                     812 41 -1203, facing north 
 Missing                 none (storage has it all) 
                                                   
 ▓Build▓ ░Stop░ ░Test░ ░Clear░ ▒Reboot▒            
                                                   
                                                   
                                                   
                                                   
▒>▒░type░a░command░(help)░░░░░░░░░░░░░░░░░░░░░░░░░░
▓Status▓ ░Map░ ░Side░ ░Bill░ ░Corners░ ░Log░       
```

- Terminal only (no monitor). Header: state of Weaver and when he was last heard. Footer tabs, input row above it: type a command.
- Orders are buttons (`Build` primary, `Reboot` tap-twice); each shows busy (purple) until Weaver confirms, repeated every 2 s.
- Tab / Shift+Tab switch tabs, `1`-`6` jump.


## Map 51x19

```text w=51
▓ARCHITECT▓                   layer 31  + building 
───────────────────────────────────────────────────
 Layer 31/60  Y 41  412 done, 528 to do, 3 gaps    
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░                
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░    W Weaver    
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░    ▓ next block
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░    ▒ done      
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░    ░ to do     
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒W▒▓▓▒▒▒▒░░░░░░    ▒ gap       
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░                
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░                
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░                
 ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░                
 ▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░                
                                                   
 ░-░ ░+░ ░^░ ░v░ ░<░ ░>░ ▓Follow▓                  
                                                   
▒>▒░type░a░command░(help)░░░░░░░░░░░░░░░░░░░░░░░░░░
░Status░ ▓Map▓ ░Side░ ░Bill░ ░Corners░ ░Log░       
```

- Layer seen from above: done (green), to do (grey), gaps (magenta), Weaver (cyan `W`), next block (gold). Zoom `-` `+` or wheel, arrows pan, PgUp/PgDn change layer, `Follow` returns to him.
- `zoom`, `layer <n>`, `follow` also work as commands.


## Bill 51x19

```text w=51
▓ARCHITECT▓                  Weaver-01  + building 
───────────────────────────────────────────────────
 30,780 blocks left, storage covers 96%            
 Material       left      storage                  
 Stone Bricks       8,200     2,100        NEEDED  
 Deepslate Bricks   6,420    12,000        ok      
 Oak Planks         3,100     2,800        short   
 Glass              2,048     9,310        ok      
 Sea Lantern        1,200     1,200        ok      
 Dark Prismarine      900     4,000        ok      
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
▒>▒░type░a░command░(help)░░░░░░░░░░░░░░░░░░░░░░░░░░
░Status░ ░Map░ ░Side░ ▓Bill▓ ░Corners░ < o1/2  ░>░ 
```

- Materials still needed vs storage; sorted shortage first. NEEDED (red) = Weaver waiting on it; short (orange); ok.


## Log 51x19

```text w=51
▓ARCHITECT▓                             + building 
───────────────────────────────────────────────────
 12:01 order: build  (confirmed)                   
 12:03 Weaver: layer 30 done                       
 12:08 Weaver: waiting, storage had no Stone Br..  
 12:09 Weaver: back at work                        
 12:14 order: reboot (queued until he docks)       
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
▒>▒░type░a░command░(help)░░░░░░░░░░░░░░░░░░░░░░░░░░
░Status░ ░Map░ ░Side░ ░Bill░ ░Corners░ < o1/4  ░>░ 
```

- Everything he reported and every order sent. Pager and wheel scroll.


## Not heard yet 51x19

```text w=51
▓ARCHITECT▓                   listening  o waiting 
───────────────────────────────────────────────────
 | Weaver hasn't been heard yet.                   
                                                   
 My radio          wireless/ender modem, listening 
 Mainframe      its Weaver link heard 4s ago (#17) 
 Plan ask                            no answer yet 
                                                   
 The mainframe gets through but Weaver does not, so
 - look at Weaver's own screen: is there an error? 
 - or he is out of range: wireless reaches ~64 bloc
   an ENDER modem on me hears him anywhere.        
                                                   
                                                   
                                                   
                                                   
                                                   
▒>▒░type░a░command░(help)░░░░░░░░░░░░░░░░░░░░░░░░░░
▓Status▓ ░Map░ ░Side░ ░Bill░ ░Corners░ ░Log░       
```

- Waiting screen with a spinner and a checklist of what the architect can see (radio, mainframe link, plan ask), then advice per failure.


## Side, Corners

- **Side:** the island from the side: layers done (green), the one in progress (cyan), him, sea level line. **Corners:** the 8 test markers as a list with result words (on the corner lime, on the ground yellow, FAILED red). Same list rows as the Bill.
