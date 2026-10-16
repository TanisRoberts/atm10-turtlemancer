# Operator: screens

Issue #33 (the screen), on the data from #32 and the rod control in #34. Built from the UI kit (`ui-kit.md`): board and tile stripes, section label, key-value row, alert line, segmented switch, stepper, the palette and motion A. The Operator is a computer with a wired modem (reactors, ports) and a monitor; the screen reads the unit records it sends to the mainframe.

**Code:** `computer/operator/` (screens in their own module, not the core loop).

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey; `▓` gold; letters sit on top; `─` and `│` are the thin rule and divider. These blocks also use `▥` lime, `▧` orange, `▨` red, `▤` light blue (state colours: running, waiting, missing, idle) and `▦` grey where the cell is a drawing rather than a button (rods, bars). The leading `+` is lime, `!` red, `?` orange, `-` grey. The same screens in colour are in the review artifact linked from #33.

Decided with Tanis: tiles with a Needs tab (option B); a Power Grid column that shows totals only; a 5% step for the level; manual control returns to Auto after 10 minutes.

## Words

- **Level** is the reactor's power setting, 0 to 100%, 100 being full power. In the device it is the control rod insertion: `rod = 100 - level`. All rods move together (#34).
- **Run** is AUTO, ON or OFF. AUTO follows demand (on below the ON threshold, off above the OFF threshold, level by #34). ON and OFF force it.
- A reactor with something missing keeps running safely and says what it waits for.

## Overview 51x19

```text w=51
▓OPERATOR▓          2 reactors  1 problem  waiting 
───────────────────────────────────────────────────
░POWER GRID░░░░░░│░REACTORS░░░░░░░░░░░░░░░░░░░░░░░░
 Output          │ ▧ Reactor-1           \ running 
 1,840 FE/t      │ ▧ Outlet not emptying           
                 │ ▧ Buffer ▥▥▥▥▥▥▦▦▦▦ 62%         
 Buffer      76% │ ▧ 1,840 FE/t   power 60%        
 ▥▥▥▥▥▥▥▥▥▥▦▦▦   │ ▧ fuel 71%  seen 2s ago         
 Net      +120/t │                                 
                 │ ▤ Reactor-2              o idle 
 Reactors on 1/2 │ ▤ Buffer full, waiting          
 Power level 60% │ ▤ Buffer ▥▥▥▥▥▥▥▥▥▦ 91%         
 Fuel        55% │ ▤ 0 FE/t       power  0%        
 Supply       48 │ ▤ fuel 40%  seen 3s ago         
 Hottest    612C │                                 
                 │                                 
                 │                                 
                 │                                 
░<░ Back                                           
```

- Power Grid column (17 wide, appears at 50 wide or more, like the mainframe Visitors column): grey header bar with the gold caps label, one divider, rows, status line at the foot. Totals only, over every reactor: output FE/t, buffer (stored over capacity, summed) with bar, net FE/t (the buffer change over the last minute), reactors on, average level of the running ones, average fuel, uranium supply (from Storage's report, `unknown` if Storage is not reporting), hottest casing. Foot: `All good` (lime) or `N needs fixing` (orange).
- Tiles (33 wide, one column, 5 rows): stripe in the state colour; name and state with glyph; what it waits for (or `All good`); buffer bar; FE/t and level; fuel and last heard. Tap opens the reactor on its Power tab. Not heard for 30 s: grey, `not heard`.
- Header summary at the right: `N reactors  N problems  state`.
- One reactor: the grid column and one tile fit on one screen. On a screen under 50 wide, the Operator opens straight on that reactor's Power tab; Back (`<`) shows the overview.
- More reactors than rows: the pager at the footer right.

## Power tab 51x19

```text w=51
▓REACTOR-1▓                 5x5x5 passive  waiting 
───────────────────────────────────────────────────
 POWER LEVEL ───────────────────────────────────── 
  ▦▦▦ ▦▦▦ ▦▦▦ ▦▦▦ ▦▦▦     Output   1,840 FE/t      
  ▦▦▦ ▦▦▦ ▦▦▦ ▦▦▦ ▦▦▦                              
  ▦▦▦ ▦▦▦ ▦▦▦ ▦▦▦ ▦▦▦     Level  ░<<░  60%  ░>>░   
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥     Auto set it 3m ago:      
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥     buffer falling           
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥                              
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥     Run  ▓AUTO▓░ON░░OFF░     
 All 5 rods at 40% in                              
 BUFFER ────────────────────────────────────────── 
 Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▦▦▦▦▦▦▦▦▦▦▦▦▦ 62%      
                  ^on 30%             ^off 90%     
                                                   
 REACTOR ───────────────────────────────────────── 
 Fuel                             71%  12 in inlet 
 Temperature                fuel 612C  casing 540C 
░<░ Back ▓Power▓ ░Needs*░ ░Set░                    
```

```text w=51
▓REACTOR-1▓                 5x5x5 passive  waiting 
───────────────────────────────────────────────────
 POWER LEVEL ───────────────────────────────────── 
  ▦▦▦ ▦▦▦ ▦▦▦ ▦▦▦ ▦▦▦     Output   2,450 FE/t      
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥                              
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥     Level  ░<<░  80%  ░>>░   
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥     Manual hold, auto in 9:40
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥     tap AUTO to return now   
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥                              
  ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥ ▥▥▥     Run  ░AUTO░▓ON▓░OFF░     
 All 5 rods at 20% in                              
 BUFFER ────────────────────────────────────────── 
 Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▦▦▦▦▦▦▦▦▦▦▦ 66%      
                  ^on 30%             ^off 90%     
                                                   
 REACTOR ───────────────────────────────────────── 
 Fuel                             71%  12 in inlet 
 Temperature                fuel 612C  casing 540C 
░<░ Back ▓Power▓ ░Needs*░ ░Set░                    
```

- Rods: one column per rod, grey where inserted, lime where withdrawn, so the lime grows as the level rises. Up to 8 rods draw one column each; more draw 8 columns, each the average of a group, and the caption says `24 rods, 20% to 40% in` when they differ. A reactor that is off draws the withdrawn part in light blue.
- Level stepper `<<` `>>`: 5% a tap; Shift or PgUp/PgDn 25%; Left/Right when focused. Stops at the Lowest and Highest limits (Set tab) with a notice.
- Run switch: tap a segment. Stepping the level while in AUTO takes over: the switch goes to ON, the level is held, and `Manual hold, auto in 9:40` counts down. After 10 minutes (setting `Back to Auto after`) or a tap on AUTO, control returns and the Operator says so in a notice. In AUTO the page says when Auto last changed the level and why (`buffer falling`, `buffer filling`).
- OFF: the stepper is disabled (no fill) and the rods keep the last level.
- Buffer bar marks the ON and OFF thresholds under it.
- Keys: Tab / Shift+Tab focus, Enter taps, `1`-`3` jump to Power, Needs and Set, Backspace goes back.

## Needs tab 51x19

```text w=51
▓REACTOR-1▓                 5x5x5 passive  waiting 
───────────────────────────────────────────────────
 NEEDS  7 ok  1 missing  1 unknown ─────────────── 
 + Computer port                         Reactor_0 
 + Fuel inlet port              port_2, 12 uranium 
 + Fuel supply                  Storage: 48 ingots 
 + Waste outlet port                        port_3 
 ! Waste clearing        outlet full, not emptying 
 ? Power output               tap not on the cable 
 + Control rods                            5 found 
 + Fuel temperature                           612C 
 + Casing temperature                         540C 
 - Coolant and turbine         not needed, passive 
                                                   
                                                   
                                                   
                                                   
                                                   
░<░ Back ░Power░ ▓Needs*▓ ░Set░                    
```

- One row per check, in a fixed order: icon, name, value or reason. `+` ok, `!` missing (loudest: the tab marker and the overview tile show it), `?` unknown (the Operator cannot tell), `-` not needed for this reactor (passive: no coolant or turbine).
- Tab label gets a lime `*` while anything is missing or unknown. A reactor with nothing missing shows `all good` in lime in the section label.
- The Operator only reads the inlet and outlet ports; it never moves items. Fuel supply is Storage's report. Waste clearing is the outlet's fill level over time.
- Taps: a `!` or `?` row opens its detail line. Nothing here moves items.

## Set tab 51x19

```text w=51
▓REACTOR-1▓                 5x5x5 passive  waiting 
───────────────────────────────────────────────────
 Applies to  ▓This reactor▓░All reactors░          
                                                   
 SWITCHING ─────────────────────────────────────── 
 ON below                 ░<<░  30%  ░>>░  default 
 OFF above                ░<<░  90%  ░>>░  default 
                                                   
 LEVEL ─────────────────────────────────────────── 
 Lowest                  ░<<░  10%  ░>>░  set here 
 Highest                 ░<<░  100%  ░>>░  default 
 Back to Auto after    ░<<░  10 min  ░>>░  default 
                                                   
 REACTOR ───────────────────────────────────────── 
 Run it  ▓YES▓░NO░    NO = leave it alone          
 ░Reset to defaults░                               
                                                   
                                                   
░<░ Back ░Power░ ░Needs*░ ▓Set▓                    
```

- Switch at the top: `This reactor` or `All reactors`. A value reads `default` (the plant-wide value) or `set here` (an override saved under the reactor's id in the Operator config).
- Steppers: 5% for percentages, 5 minutes for the hold time. ON below stays at least 10 points under OFF above; the stepper stops and a notice says why.
- `Run it`: NO makes the Operator leave the reactor alone (no on/off or level changes) while still reporting it.
- `Reset to defaults` is tap-twice and clears this reactor's overrides.

## 39x13

```text w=39
▓OPERATOR▓                     waiting 
───────────────────────────────────────
 Grid  1,840 FE/t  buf 76%  1/2 on     
 ▧ Reactor-1            \ running      
 ▧ Buffer ▥▥▥▥▥▥▦▦▦▦▦▦▦▦▦▦ 62%         
                                       
 ▤ Reactor-2               o idle      
 ▤ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▦ 91%         
                                       
 1 needs fixing                        
                                       
                                       
░<░ Back                               
```

```text w=39
▓REACTOR-1▓                    waiting 
───────────────────────────────────────
 POWER LEVEL ───────────────────────── 
  ▦▦ ▦▦ ▦▦ ▦▦ ▦▦   Out 1,840 FE/t      
  ▦▦ ▦▦ ▦▦ ▦▦ ▦▦   Level ░<<░ 60% ░>>░ 
  ▥▥ ▥▥ ▥▥ ▥▥ ▥▥   Auto: buffer falling
  ▥▥ ▥▥ ▥▥ ▥▥ ▥▥   Run ▓AUTO▓░ON░░OFF░ 
 Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▦▦▦▦▦▦▦▦▦ 62%   
               ^on 30%        ^off 90% 
 Fuel                 71%  12 in inlet 
 Temp           fuel 612C  casing 540C 
                                       
░<░ Back ▓Power▓ ░Needs*░ ░Set░        
```

```text w=39
▓REACTOR-1▓                    waiting 
───────────────────────────────────────
 NEEDS  7 ok  1 missing  1 unknown ─── 
 + Computer port             Reactor_0 
 + Fuel inlet port  port_2, 12 uranium 
 + Fuel supply      Storage: 48 ingots 
 + Waste outlet port            port_3 
 ! Waste clearing  outlet not emptying 
 ? Power output       tap not on cable 
 + Control rods                5 found 
 + Fuel temperature               612C 
 + Casing temperature             540C 
░<░ ░Power░ ▓Needs*▓ ░Set░  ░<░ 1/2 ░>░
```

- Under 50 wide there is no grid column: a strip with the totals sits above the short (2 row) tiles, and the foot says what needs fixing.
- Power: rods are 2 wide by 4 tall. Needs: the pager appears when the list does not fit.

## 26x20 (glasses)

```text w=26
▓OPERATOR▓        waiting 
──────────────────────────
 1,840 FE/t  buffer 76%   
 1 of 2 on  1 needs fixing
                          
 ▧ Reactor-1   \ running  
 ▧ Outlet not emptying    
 ▧ Buffer ▥▥▥▥▦▦▦ 62%     
 ▧ 1,840 FE/t  pwr 60%    
 ▧ fuel 71%  seen 2s      
                          
 ▤ Reactor-2      o idle  
 ▤ Buffer full, waiting   
 ▤ Buffer ▥▥▥▥▥▥▦ 91%     
 ▤ 0 FE/t  pwr 0%         
 ▤ fuel 40%  seen 3s      
                          
                          
                          
░<░                       
```

```text w=26
▓REACTOR-1▓       waiting 
──────────────────────────
 POWER LEVEL ──────────── 
  ▦▦ ▦▦ ▦▦ ▦▦ ▦▦  Level   
  ▦▦ ▦▦ ▦▦ ▦▦ ▦▦  60%     
  ▥▥ ▥▥ ▥▥ ▥▥ ▥▥          
  ▥▥ ▥▥ ▥▥ ▥▥ ▥▥  Auto    
  ▥▥ ▥▥ ▥▥ ▥▥ ▥▥  falling 
 ░<<░  60%  ░>>░          
 Run ▓AUTO▓░ON░░OFF░      
 Out 1,840 FE/t           
 Buffer ▥▥▥▥▥▥▦▦▦▦ 62%    
           ^30   ^90      
                          
 Fuel                 71% 
 Temp         612C / 540C 
                          
                          
                          
░<░ ▓Pwr▓ ░Need*░ ░Set░   
```

```text w=26
▓REACTOR-1▓       waiting 
──────────────────────────
 NEEDS 7 ok 1 ! 1 ? ───── 
 + Computer port          
 + Fuel inlet port        
 + Fuel supply            
 + Waste outlet port      
 ! Waste clearing         
     outlet not emptying  
 ? Power output           
     tap not on cable     
 + Control rods           
 + Fuel temperature       
 + Casing temperature     
 - Coolant, turbine       
                          
                          
                          
                          
░<░ ░Pwr░ ▓Need*▓ ░Set░   
```

- Tabs shrink to 4 letters, Back is `<`. In Needs the ok rows drop their values and a `!` or `?` row keeps its reason on a second line.

## Wall 164x81 (8x6)

```text w=164
▓OPERATOR▓                                                                                                                           2 reactors  1 problem  waiting 
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
░POWER GRID░░░░░░░░░░░░░░░░░░░░░░░░░░░│░REACTORS░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
 OUTPUT                               │ ▧ Reactor-1                    \ running ▤ Reactor-2                       o idle                                           
 1,840 FE/t   2 reactors              │ ▧ Outlet not emptying                    ▤ Off: buffer above 90%                                                            
                                      │ ▧                                        ▤                                                                                  
 BUFFER                           76% │ ▧  POWER LEVEL ────────────────────────  ▤  POWER LEVEL ────────────────────────                                            
 ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▦▦▦▦▦▦▦▦   │ ▧ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦     ▤ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦                                               
         ^on 30%         ^off 90%     │ ▧ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦     ▤ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦                                               
                                      │ ▧ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦     ▤ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦                                               
 PLANT ────────────────────────────── │ ▧ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦     ▤ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦                                               
 Net                        +120 FE/t │ ▧ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦     ▤ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦                                               
 Reactors on                   1 of 2 │ ▧ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦     ▤ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦ ▦▦▦▦▦▦                                               
 Average level                    60% │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥     ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                               
 Fuel                             55% │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥     ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                               
 Supply (Storage)           48 ingots │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥     ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                               
 Hottest casing                  612C │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥     ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                               
 Waste outlets                 1 full │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥     ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                               
 Output last hour           1,610 avg │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥     ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                               
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥     ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                               
 NEEDS ATTENTION ──────────────────── │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥     ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                               
 ▨ Reactor-1: waste outlet is not     │ ▧  Auto set it 3m ago: buffer falling    ▤  Auto: off until buffer under 30%                                                
 ▨ emptying (100% full).              │ ▧  ░<<░  60%  ░>>░   ▓AUTO▓░ON░░OFF░     ▤  ░<<░  60%  ░>>░   ▓AUTO▓░ON░░OFF░                                               
 ▧ Reactor-1, Reactor-2: power        │ ▧                                        ▤                                                                                  
 ▧ output unknown (tap not on         │ ▧  BUFFER ─────────────────────────────  ▤  BUFFER ─────────────────────────────                                            
 ▧ the cable).                        │ ▧ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▦▦▦▦▦▦▦▦▦▦ 62% ▤ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▦▦ 91%                                           
                                      │ ▧                ^on 30          ^off 90 ▤                ^on 30          ^off 90                                           
                                      │ ▧                                        ▤                                                                                  
                                      │ ▧  READINGS ───────────────────────────  ▤  READINGS ───────────────────────────                                            
                                      │ ▧  Output                    1,840 FE/t  ▤  Output                        0 FE/t                                            
                                      │ ▧  Fuel                71%  12 in inlet  ▤  Fuel                 40%  8 in inlet                                            
                                      │ ▧  Fuel temperature                612C  ▤  Fuel temperature                310C                                            
                                      │ ▧  Casing temperature              540C  ▤  Casing temperature              290C                                            
                                      │ ▧  Waste outlet                    full  ▤  Waste outlet                   empty                                            
                                      │ ▧                                        ▤                                                                                  
                                      │ ▧  NEEDS  7 ok  1 !  1 ? ──────────────  ▤  NEEDS  8 ok  0 !  1 ? ──────────────                                            
                                      │ ▧  + Computer port            Reactor_0  ▤  + Computer port            Reactor_1                                            
                                      │ ▧  + Fuel inlet port             port_2  ▤  + Fuel inlet port             port_5                                            
                                      │ ▧  + Fuel supply             Storage 48  ▤  + Fuel supply             Storage 48                                            
                                      │ ▧  + Waste outlet port           port_3  ▤  + Waste outlet port           port_6                                            
                                      │ ▧  ! Waste clearing        not emptying  ▤  + Waste clearing            draining                                            
                                      │ ▧  ? Power output         tap off cable  ▤  ? Power output         tap off cable                                            
                                      │ ▧  + Control rods               5 found  ▤  + Control rods               5 found                                            
                                      │ ▧  + Fuel temperature              612C  ▤  + Fuel temperature              310C                                            
                                      │ ▧  + Casing temperature            540C  ▤  + Casing temperature            290C                                            
                                      │ ▧  - Coolant, turbine           passive  ▤  - Coolant, turbine           passive                                            
                                      │ ▧                                        ▤                                                                                  
                                      │                                                                                                                             
                                      │  PLANT BUFFER, LAST 30 MINUTES ──────────────────────────────────────────────────────────────────────────────────────────── 
                                      │ 100%                                                                                                                        
                                      │                                                                                                                             
                                      │  90% ······················································································································ 
                                      │                                                                                                                             
                                      │                                                                                                                         ▥▥▥ 
                                      │                                                                                                              ▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │                                                                                                    ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │                                                                                        ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │      ▥▥▥▥▥▥▥                                                               ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │      ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥                                            ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │      ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥                         ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │  30% ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥······▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │      ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │      ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │      ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │   0% ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥ 
                                      │      -30 min                                                -15 min                                                    now  
                                      │                                                                                                                             
                                      │  RECENT ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────── 
                                      │ 06:12  Reactor-1  on, buffer 29%                                                                                            
                                      │ 06:10  Reactor-1  level raised to 60% (buffer falling)                                                                      
                                      │ 05:58  Reactor-2  off, buffer 91%                                                                                           
                                      │ 05:41  Reactor-1  waste outlet not emptying (100% full)                                                                     
                                      │ 05:30  Reactor-2  level lowered to 60% (buffer filling)                                                                     
                                      │ 05:12  Reactor-1  off, buffer 90%                                                                                           
                                      │ 04:55  Operator   started, 2 reactors found                                                                                 
                                      │                                                                                                                             
                                      │                                                                                                                             
                                      │                                                                                                                             
 1 needs fixing                       │                                                                                                                             
                                      │                                                                                                                             
░<░ Back                                                                                                                                                            
```

- Everything at once: Power Grid at the left, up to three reactor panels across, then the plant buffer chart and recent events.
- A panel holds the whole reactor: state and what it waits for, rods (14 rows tall), level with the stepper and the Run switch, buffer with the thresholds, readings, Needs. Every control works by touch.
- Plant buffer chart: the summed buffer, last 30 minutes, with the 30% and 90% thresholds dotted. Recent: the last events (on and off, level changes made by Auto and why, alerts).
- More than three reactors: panels become kit tiles (as many columns as fit) and the chart moves under them.
- **New data (optional):** a ring buffer of plant buffer percent (a sample every 15 s, 120 samples) and a short event log (about 8 entries) in the Operator status. Without them the wall leaves out the chart and events and gives the room to larger panels.

## Data the screen needs from the core

Per unit: state, waiting-for text, buffer %, FE/t, level (and rod count and each rod's level), mode (auto/on/off) with manual-hold time left, last auto change and reason, fuel %, inlet count, temperatures, waste outlet fill, and the needs list `{ id, label, state = ok|missing|unknown|na, value, reason }`. Plant: totals as shown, plus net FE/t.
