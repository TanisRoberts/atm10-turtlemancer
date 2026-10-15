# Smart glasses: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `glasses/hud/glasses.lua`

The glasses' own settings screen (26x20) and the in-world HUD overlay.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Glasses screen 26x20

```text w=26
▓GLASSES▓                 
──────────────────────────
 Night vision             
 ▓AUTO▓░ON░░OFF░          
 on in the dark, light 4  
                          
 Aggro alert              
 ▓ON▓░OFF░ ░every░2s░     
 on, 8 blocks             
                          
 HUD                      
 ▓ON▓░OFF░                
 Alex, inv 8/36 free      
                          
 light 4 plains           
                          
                          
                          
                          
1-3 NV A S H Q quit       
```

- The settings page on the glasses' own terminal: three segmented switches (Night vision, Aggro alert + scan speed, HUD) with a status line under each. Keys 1-3, A, S, H, Q still work. Status lines are orange when a module is missing (`No Night Vision Module fitted`).
- Glasses terminal is plain: `ANIM` is `calm`: no motion.


## HUD overlay in the world

```text w=40
       CREEPER 4m to the left           
                     NV AUTO: on        
             06:12  night in 10:39      
               543 64 -1737  S          
               Inv 28% ▒▒▒░░░░░░░░░     
                                        
                                        
                                        
                                        
                                        
                                        
                                        
```

- Not a terminal: text drawn by the Overlay Module in the top-right corner (night vision mode, time, coordinates, inventory bar) and a red aggro alert top-middle. Text colours follow the palette: lime for on, white for numbers, red for danger. Layout is set in `glasses.env` (corner and edge gaps), unchanged.
