# Farmhand: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/farmhand/`

Control for every farm turtle (Partridge, Woodpecker). Already on the UI kit; shown here so the set is complete (see docs/systems/farmhand.md).

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Overview 57x24

```text w=57
▓FARMHAND▓                       2 turtles  all fine  ok 
─────────────────────────────────────────────────────────
 ▒ Partridge-01   \ working  ▒ Woodpecker-02   = docked  
 ▒ Picking up wheat          ▒ Docked, waiting           
 ▒ Fuel ▒▒▒▒▒▒▒▒░░░     71%  ▒ Fuel ▒▒▒▒░░░░░░░     34%  
 ▒ round 12/40  next in 3m   ▒ next round in 18m         
 ▒                           ▒                           
 ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒,▒    ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒,▒    
 ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒,▒+▒+▒    ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒,▒+▒+▒    
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    
 ▒ ░░░░▒▒▒▒░░>▒,▒,▒+▒+▒+▒    ▒ ░░░░▒▒▒▒░░>▒,▒,▒+▒+▒+▒    
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒,▒,▒    ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒,▒,▒    
 ▒ ░░░░░░░░░░░░+▒+▒+▒+▒,▒    ▒ ░░░░░░░░░░░░+▒+▒+▒+▒,▒    
 ▒ ░░░░░░░░░░░░+▒+▒+▒+▒+▒    ▒ ░░░░░░░░░░░░+▒+▒+▒+▒+▒    
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    
 ▒ ░░░░▒▒▒▒░░░░+▒,▒+▒+▒+▒    ▒ ░░░░▒▒▒▒░░░░+▒,▒+▒+▒+▒    
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒    
 ▒                           ▒                           
 ▒ Last: harvested 118       ▒ Last: chopped 64          
                                                         
                                                         
▓Rounds▓all▓ ░Pause░all░ ▒Reboot▒all▒        <  1/2  ░>░ 
```

- Tiles grow with the screen: state, message, fuel, next round, the farm drawn small (arrow = the turtle, live), last round.
- Footer: Rounds all (primary), Pause all, Reboot all (tap-twice); pager and wheel for more turtles.
- Tap a tile: opens that turtle.


## Overview 51x19

```text w=51
▓FARMHAND▓                 2 turtles  all fine  ok 
───────────────────────────────────────────────────
 ▒ Partridge-01\ working  ▒ Woodpecker-02= docked  
 ▒ Picking up wheat       ▒ Docked, waiting        
 ▒ Fuel ▒▒▒▒▒▒░░     71%  ▒ Fuel ▒▒▒░░░░░     34%  
 ▒ round 12/40  next i..  ▒ next round in 18m      
 ▒                        ▒                        
 ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒   ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒   
 ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒,▒+▒   ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒,▒+▒   
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒   ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒   
 ▒ ░░░░▒▒▒▒░░>▒,▒,▒+▒+▒   ▒ ░░░░▒▒▒▒░░>▒,▒,▒+▒+▒   
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒   ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒+▒   
 ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒,▒   ▒ ░░░░▒▒▒▒░░░░+▒+▒+▒,▒   
 ▒ ░░░░░░░░░░░░+▒+▒+▒+▒   ▒ ░░░░░░░░░░░░+▒+▒+▒+▒   
 ▒                        ▒                        
 ▒ Last: harvested 118    ▒ Last: chopped 64       
                                                   
                                                   
▓Rounds▓all▓ ░Pause░all░ ▒Reboot▒all▒  <  1/2  ░>░ 
```

- Same, 24-wide tiles, a smaller map.


## Overview 39x13

```text w=39
▓FARMHAND▓                          ok 
───────────────────────────────────────
 ▒ Partridge-01             \ working  
 ▒ Picking up wheat                    
 ▒ Fuel ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░     71%  
 ▒ round 12/40  next in 3m             
 ▒                                     
 ▒ ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒,▒,▒▒▒▒▒▒▒▒▒    
 ▒                                     
 ▒ Last: harvested 118                 
                                       
                                       
▓Rounds▓                   <  1/2  ░>░ 
```

- One turtle per page; map thumbnail drops below 3 rows.


## Turtle: Map 57x24

```text w=57
▓PARTRIDGE-01▓             crops  north is up  \ working 
─────────────────────────────────────────────────────────
 ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒,▒,▒▒▒▒▒   Picking up wheat         
 ▒▒▒▒▒▒▒▒░░░░+▒+▒,▒+▒+▒+▒▒▒▒▒   round 12 of 40           
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░,▒,▒+▒+▒+▒+▒░░░░   Fuel ▒▒▒▒▒▒▒▒▒▒▒░░░░ 71% 
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░   Next         round 13/40 
 ░░░░▒▒▒▒░░░░>▒+▒+▒,▒,▒,▒░░░░   Seeds                138 
 ░░░░░░░░░░░░+▒+▒+▒+▒,▒+▒░░░░                            
 ░░░░░░░░░░░░+▒+▒+▒+▒+▒+▒░░░░   ▓Rounds▓now▓             
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░+▒,▒+▒+▒+▒+▒░░░░   ░Pause░                  
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░   ░Re-map░                 
 ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒,▒,▒▒▒▒▒                            
 ▒▒▒▒▒▒▒▒░░░░+▒+▒,▒+▒+▒+▒▒▒▒▒   ▒Reboot▒                 
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░,▒,▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
                                                         
 > here  , growing  + ready  = dock                      
 ░^░ ░v░ ░<░ ░>░                                         
                                                         
░<░ Back ▓Map▓ ░Info░ ░Haul░ ░Settings░                  
```

- Side column at 44+ wide; tabs Map / Info / Haul / Settings. Narrower: Map / Do / Info / Set with the order buttons on Do.
- Map: a farm that fits is centred with 2-character cells and no pan row; a bigger one follows the turtle (Follow, arrows, Home or `f`, wheel). A tap on a block says what it is.
- Orders repeat every 3 s until the turtle confirms; `Rounds now` shows busy until then.


## Turtle: Info

```text w=57
▓PARTRIDGE-01▓             crops  north is up  \ working 
─────────────────────────────────────────────────────────
 State                                           working 
 Message                                Picking up wheat 
 Seen                                             2s ago 
 Position                                   812 64 -1203 
 GPS                                                 yes 
 Last round                          harvested 118 in 4m 
 Farm                                    24 x 18, 6 rows 
                                                         
 Silent for 2 minutes? Then you can forget it:           
 ░Forget░this░turtle░                                    
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back ░Map░ ▓Info▓ ░Haul░ ░Settings░                  
```

- `Forget this turtle` appears after 2 minutes of silence, tap-twice.


## Turtle: Haul

```text w=57
▓PARTRIDGE-01▓             crops  north is up  \ working 
─────────────────────────────────────────────────────────
 LAST HAUL ───────────────────────────────────────────── 
 ▒ Wheat                                            118  
 ▒ Seeds                                             92  
 ▒ Carrot                                            44  
 ▒ Potato                                            31  
                                                         
 TOTALS ──────────────────────────────────────────────── 
 ▒ Wheat                                          4,812  
 ▒ Seeds                                          3,090  
 ▒ Carrot                                         1,630  
 ▒ Potato                                         1,203  
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back ░Map░ ░Info░ ▓Haul▓ ░Settings░                  
```

- Last haul and totals.


## Turtle: Settings

```text w=57
▓PARTRIDGE-01▓             crops  north is up  \ working 
─────────────────────────────────────────────────────────
 Rounds every      ░-░  3  ░+░  min                      
                                                         
 Keep seeds        ░-░  16 ░+░  sent, waiting for the tur
                                                         
 Re-map every      ░-░  1  ░+░  rounds                   
                                                         
 A setting shows gold until the turtle confirms it.      
 Written into its own .env file.                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back ░Map░ ░Info░ ░Haul░ ▓Settings▓                  
```

- One stepper per setting, sent live. Gold value = not confirmed yet.


## Turtle: lost (alert line)

```text w=57
▓PARTRIDGE-01▓             crops  north is up  \ working 
▒ Lost: no GPS fix. Walk it to the dock, tap Found.      
 ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒,▒,▒▒▒▒▒   Picking up wheat         
 ▒▒▒▒▒▒▒▒░░░░+▒+▒,▒+▒+▒+▒▒▒▒▒   round 12 of 40           
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░,▒,▒+▒+▒+▒+▒░░░░   Fuel ▒▒▒▒▒▒▒▒▒▒▒░░░░ 71% 
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░   Next         round 13/40 
 ░░░░▒▒▒▒░░░░>▒+▒+▒,▒,▒,▒░░░░   Seeds                138 
 ░░░░░░░░░░░░+▒+▒+▒+▒,▒+▒░░░░                            
 ░░░░░░░░░░░░+▒+▒+▒+▒+▒+▒░░░░   ▓Rounds▓now▓             
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░+▒,▒+▒+▒+▒+▒░░░░   ░Pause░                  
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░   ░Re-map░                 
 ▒▒▒▒▒▒▒▒░░░░+▒+▒+▒+▒,▒,▒▒▒▒▒                            
 ▒▒▒▒▒▒▒▒░░░░+▒+▒,▒+▒+▒+▒▒▒▒▒   ▒Reboot▒                 
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░,▒,▒+▒+▒+▒+▒░░░░                            
 ░░░░▒▒▒▒░░░░+▒+▒+▒+▒+▒+▒░░░░                            
                                                         
 > here  , growing  + ready  = dock                      
 ░^░ ░v░ ░<░ ░>░                                         
                                                         
░<░ Back ▓Map▓ ░Info░ ░Haul░ ░Settings░                  
```

- A turtle with no GPS fix gets a red alert line and a `Found` button (primary) replaces `Re-map`.
