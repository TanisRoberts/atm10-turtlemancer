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

## Wall 164x81 (8x6 at text scale 0.5): chart on top, glance band below

Issue #117, concept O2, signed off by Tanis. Review page: https://claude.ai/artifact/M8FxWLe1qTxNVyWQqeNZDQ (example data throughout). Follows the big-wall direction in `ui-kit.md` section 1.1, and shares its power slot and Needs you list with the mainframe wall (`mainframe.md`, "Wall 82x40").

The Operator's 8x6 wall sits at ground height and stays at text scale 0.5. Everything on today's wall is kept, in a new order: the buffer chart across the top (big enough to read from across the room), the Power Grid column and the full reactor panels in the middle (walk up to read them), and a glance band in the bottom quarter. **Nothing moves:** every part has fixed rows, and empty slots stay blank.

In these blocks `▒` is cyan (the chart fill), and the chart's last column, white, is now. `░` is any grey cell, including rods and bar tracks.

### Over output (reactor 1 has a problem)

```text w=164
▓OPERATOR▓                                                                                                                     2 reactors  1 on  1 problem  waiting 
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 PLANT BUFFER, LAST 30 MINUTES ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── now 41% 
 100%                                                                                                                                                               
                                                                                                                                                                    
  90% · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · 
                                                                                                                                         ▒▒▒▒                       
                                                                                                                                      ▒▒▒▒▒▒▒▒▒                     
                                                                                                                                   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                  
                                                                                                                                ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                
                                                                                                                             ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒              
                                                                                                                          ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒           
                                                                                                                      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒         
                          ▒▒▒▒▒▒▒▒▒▒▒▒                                                                             ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒      
                   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                                                         ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒    
               ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                                        ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
          ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
  30% ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒·▒·▒·▒·▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
   0% ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      -30 min                                                                    -15 min                                                                        now 
                                                                                                                                                                    
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
░POWER░GRID░░░░░░░░░░░░░░░░░░░░░░░░░░░│░REACTORS░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                                      │                                                                                                                             
 Output                    1,840 FE/t │ ▧ Reactor-1                     \ running ▤ Reactor-2                        o idle                                         
 Buffer                           41% │ ▧ Waste outlet not emptying               ▤ Off: buffer above 90%                                                           
 Net                        +120 FE/t │ ▧                                         ▤                                                                                 
 Reactors on                   1 of 2 │ ▧ POWER LEVEL ─────────────────────────── ▤ POWER LEVEL ───────────────────────────                                         
 Average level                    60% │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Fuel                             55% │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Supply (Storage)           48 ingots │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Hottest casing                  612C │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Waste outlets                 1 full │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
                                      │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ Auto set it 3m ago: buffer falling      ▤ Auto: off until buffer under 30%                                                
                                      │ ▧ ░<<░  60%  ░>>░   ▓AUTO▓░ON░░OFF░       ▤ ░<<░  60%  ░>>░   ▓AUTO▓░ON░░OFF░                                               
                                      │ ▧                                         ▤                                                                                 
                                      │ ▧ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥░░░░░░░░░░  62% ▤ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥░░  91%                                         
                                      │ ▧ Output                       1,840 FE/t ▤ Output                           0 FE/t                                         
                                      │ ▧ Fuel                                71% ▤ Fuel                                40%                                         
                                      │ ▧ Casing temperature                 540C ▤ Casing temperature                 290C                                         
                                      │ ▧ Waste outlet                       full ▤ Waste outlet                      empty                                         
                                      │                                                                                                                             
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
░POWER░USE░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │ NEEDS YOU ──────────────────────────────────────────────────────────────────────────────── 
                                                                       │ ▨ Reactor-1: waste outlet not emptying                                                     
      ▧▧▧▧            ▧▧▧▧        ▧▧▧▧▧▧▧▧▧▧▧▧    ▧▧▧▧    ▧▧▧▧         │ ▧ Power output unknown: tap off cable                                                      
      ▧▧▧▧            ▧▧▧▧        ▧▧▧▧▧▧▧▧▧▧▧▧    ▧▧▧▧    ▧▧▧▧         │                                                                                            
  ▧▧▧▧▧▧▧▧        ▧▧▧▧▧▧▧▧                ▧▧▧▧            ▧▧▧▧         │                                                                                            
  ▧▧▧▧▧▧▧▧        ▧▧▧▧▧▧▧▧                ▧▧▧▧            ▧▧▧▧         │                                                                                            
      ▧▧▧▧            ▧▧▧▧        ▧▧▧▧▧▧▧▧▧▧▧▧        ▧▧▧▧             │ RECENT ─────────────────────────────────────────────────────────────────────────────────── 
      ▧▧▧▧            ▧▧▧▧        ▧▧▧▧▧▧▧▧▧▧▧▧        ▧▧▧▧             │ 06:12  Reactor-1  on, buffer 29%                                                           
      ▧▧▧▧            ▧▧▧▧                ▧▧▧▧    ▧▧▧▧                 │ 06:10  Reactor-1  level raised to 60% (buffer falling)                                     
      ▧▧▧▧            ▧▧▧▧                ▧▧▧▧    ▧▧▧▧                 │ 05:58  Reactor-2  off, buffer 91%                                                          
  ▧▧▧▧▧▧▧▧▧▧▧▧    ▧▧▧▧▧▧▧▧▧▧▧▧    ▧▧▧▧▧▧▧▧▧▧▧▧    ▧▧▧▧    ▧▧▧▧         │ 05:41  Reactor-1  waste outlet not emptying                                                
  ▧▧▧▧▧▧▧▧▧▧▧▧    ▧▧▧▧▧▧▧▧▧▧▧▧    ▧▧▧▧▧▧▧▧▧▧▧▧    ▧▧▧▧    ▧▧▧▧         │                                                                                            
                                                                       │                                                                                            
  3,400 of 3,000 FE/t                                                  │                                                                                            
  Over output, buffer 41% falling                                      │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                                                                                                                    
░<░ Back                                                                                                                                                            
```

### Throttled

```text w=164
▓OPERATOR▓                                                                                                                     2 reactors  1 on  1 problem  waiting 
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 PLANT BUFFER, LAST 30 MINUTES ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── now 41% 
 100%                                                                                                                                                               
                                                                                                                                                                    
  90% · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · 
                                                                                                                                         ▒▒▒▒                       
                                                                                                                                      ▒▒▒▒▒▒▒▒▒                     
                                                                                                                                   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                  
                                                                                                                                ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                
                                                                                                                             ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒              
                                                                                                                          ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒           
                                                                                                                      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒         
                          ▒▒▒▒▒▒▒▒▒▒▒▒                                                                             ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒      
                   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                                                         ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒    
               ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                                        ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
          ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
  30% ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒·▒·▒·▒·▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
   0% ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      -30 min                                                                    -15 min                                                                        now 
                                                                                                                                                                    
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
░POWER░GRID░░░░░░░░░░░░░░░░░░░░░░░░░░░│░REACTORS░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                                      │                                                                                                                             
 Output                    1,840 FE/t │ ▧ Reactor-1                     \ running ▤ Reactor-2                        o idle                                         
 Buffer                           41% │ ▧ Waste outlet not emptying               ▤ Off: buffer above 90%                                                           
 Net                        +120 FE/t │ ▧                                         ▤                                                                                 
 Reactors on                   1 of 2 │ ▧ POWER LEVEL ─────────────────────────── ▤ POWER LEVEL ───────────────────────────                                         
 Average level                    60% │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Fuel                             55% │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Supply (Storage)           48 ingots │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Hottest casing                  612C │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Waste outlets                 1 full │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
                                      │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ Auto set it 3m ago: buffer falling      ▤ Auto: off until buffer under 30%                                                
                                      │ ▧ ░<<░  60%  ░>>░   ▓AUTO▓░ON░░OFF░       ▤ ░<<░  60%  ░>>░   ▓AUTO▓░ON░░OFF░                                               
                                      │ ▧                                         ▤                                                                                 
                                      │ ▧ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥░░░░░░░░░░  62% ▤ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥░░  91%                                         
                                      │ ▧ Output                       1,840 FE/t ▤ Output                           0 FE/t                                         
                                      │ ▧ Fuel                                71% ▤ Fuel                                40%                                         
                                      │ ▧ Casing temperature                 540C ▤ Casing temperature                 290C                                         
                                      │ ▧ Waste outlet                       full ▤ Waste outlet                      empty                                         
                                      │                                                                                                                             
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
░POWER░USE░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░▨THROTTLED▨ │ NEEDS YOU ──────────────────────────────────────────────────────────────────────────────── 
                                                                       │ ▨ Power throttled: over 150%. Add power.                                                   
  ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨    ▨▨▨▨                         │ ▨ Reactor-1: waste outlet not emptying                                                     
  ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨    ▨▨▨▨                         │ ▧ Power output unknown: tap off cable                                                      
  ▨▨▨▨    ▨▨▨▨    ▨▨▨▨    ▨▨▨▨            ▨▨▨▨                         │                                                                                            
  ▨▨▨▨    ▨▨▨▨    ▨▨▨▨    ▨▨▨▨            ▨▨▨▨                         │                                                                                            
  ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨    ▨▨▨▨        ▨▨▨▨                             │ RECENT ─────────────────────────────────────────────────────────────────────────────────── 
  ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨    ▨▨▨▨        ▨▨▨▨                             │ 06:12  Reactor-1  on, buffer 29%                                                           
          ▨▨▨▨    ▨▨▨▨    ▨▨▨▨    ▨▨▨▨                                 │ 06:10  Reactor-1  level raised to 60% (buffer falling)                                     
          ▨▨▨▨    ▨▨▨▨    ▨▨▨▨    ▨▨▨▨                                 │ 05:58  Reactor-2  off, buffer 91%                                                          
  ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨    ▨▨▨▨                         │ 05:41  Reactor-1  waste outlet not emptying                                                
  ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨▨▨▨▨▨▨▨▨    ▨▨▨▨    ▨▨▨▨                         │                                                                                            
                                                                       │                                                                                            
  Throttled at 2,700 FE/t                                              │                                                                                            
  Asked for 4,800 (160%) for 2m                                        │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                                                                                                                    
░<░ Back                                                                                                                                                            
```

### All clear (nothing needs you)

```text w=164
▓OPERATOR▓                                                                                                                     2 reactors  1 on  1 problem  waiting 
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
 PLANT BUFFER, LAST 30 MINUTES ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── now 41% 
 100%                                                                                                                                                               
                                                                                                                                                                    
  90% · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · 
                                                                                                                                         ▒▒▒▒                       
                                                                                                                                      ▒▒▒▒▒▒▒▒▒                     
                                                                                                                                   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                  
                                                                                                                                ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                
                                                                                                                             ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒              
                                                                                                                          ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒           
                                                                                                                      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒         
                          ▒▒▒▒▒▒▒▒▒▒▒▒                                                                             ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒      
                   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                                                         ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒    
               ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                                        ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
          ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                                      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒                  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
  30% ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒·▒·▒·▒·▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
   0% ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ 
      -30 min                                                                    -15 min                                                                        now 
                                                                                                                                                                    
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
░POWER░GRID░░░░░░░░░░░░░░░░░░░░░░░░░░░│░REACTORS░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                                      │                                                                                                                             
 Output                    1,840 FE/t │ ▧ Reactor-1                     \ running ▤ Reactor-2                        o idle                                         
 Buffer                           41% │ ▧ Waste outlet not emptying               ▤ Off: buffer above 90%                                                           
 Net                        +120 FE/t │ ▧                                         ▤                                                                                 
 Reactors on                   1 of 2 │ ▧ POWER LEVEL ─────────────────────────── ▤ POWER LEVEL ───────────────────────────                                         
 Average level                    60% │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Fuel                             55% │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Supply (Storage)           48 ingots │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Hottest casing                  612C │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
 Waste outlets                 1 full │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
                                      │ ▧ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░      ▤ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░ ░░░░░░                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥ ▥▥▥▥▥▥      ▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤ ▤▤▤▤▤▤                                              
                                      │ ▧ Auto set it 3m ago: buffer falling      ▤ Auto: off until buffer under 30%                                                
                                      │ ▧ ░<<░  60%  ░>>░   ▓AUTO▓░ON░░OFF░       ▤ ░<<░  60%  ░>>░   ▓AUTO▓░ON░░OFF░                                               
                                      │ ▧                                         ▤                                                                                 
                                      │ ▧ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥░░░░░░░░░░  62% ▤ Buffer ▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥▥░░  91%                                         
                                      │ ▧ Output                       1,840 FE/t ▤ Output                           0 FE/t                                         
                                      │ ▧ Fuel                                71% ▤ Fuel                                40%                                         
                                      │ ▧ Casing temperature                 540C ▤ Casing temperature                 290C                                         
                                      │ ▧ Waste outlet                       full ▤ Waste outlet                      empty                                         
                                      │                                                                                                                             
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
░POWER░USE░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │ NEEDS YOU ──────────────────────────────────────────────────────────────────────────────── 
                                                                       │ Nothing needs you.                                                                         
  ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥    ▥▥▥▥                         │ 2 reactors: 1 on, 1 off by Auto, all parts found                                           
  ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥    ▥▥▥▥                         │                                                                                            
  ▥▥▥▥                    ▥▥▥▥            ▥▥▥▥                         │                                                                                            
  ▥▥▥▥                    ▥▥▥▥            ▥▥▥▥                         │                                                                                            
  ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥▥▥▥▥▥▥▥▥        ▥▥▥▥                             │ RECENT ─────────────────────────────────────────────────────────────────────────────────── 
  ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥▥▥▥▥▥▥▥▥        ▥▥▥▥                             │ 06:12  Reactor-1  on, buffer 29%                                                           
  ▥▥▥▥    ▥▥▥▥    ▥▥▥▥            ▥▥▥▥                                 │ 06:10  Reactor-1  level raised to 60% (buffer falling)                                     
  ▥▥▥▥    ▥▥▥▥    ▥▥▥▥            ▥▥▥▥                                 │ 05:58  Reactor-2  off, buffer 91%                                                          
  ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥    ▥▥▥▥                         │ 05:41  Reactor-1  waste outlet not emptying                                                
  ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥▥▥▥▥▥▥▥▥    ▥▥▥▥    ▥▥▥▥                         │                                                                                            
                                                                       │                                                                                            
  1,840 of 3,000 FE/t                                                  │                                                                                            
  Buffer 76%                                                           │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                       │                                                                                            
                                                                                                                                                                    
░<░ Back                                                                                                                                                            
```

### Rows

| Rows | What |
|---|---|
| 1 | Gold `OPERATOR` chip; at the right `2 reactors  1 on  1 problem` dim, then the state word (`running` lime, `waiting` orange, `idle` lightBlue) |
| 2 | Thin rule |
| 3 | Section label `PLANT BUFFER, LAST 30 MINUTES`, rule, `now 41%` at the right (orange while falling, else white) |
| 4-25 | The chart, 22 rows, columns 7-163; `100%`, `90%`, `30%`, `0%` labels in columns 2-5 |
| 26 | Time axis: `-30 min` at the left, `-15 min` centred, `now` at the right |
| 28 | Thin rule |
| 29 | `POWER GRID` header (1-38), divider at 39 (rows 29-57), `REACTORS` header (40-164) |
| 31-39 | Power Grid totals (key-value rows, as before) |
| 31-56 | Up to three reactor panels, 41 wide, at columns 41, 83, 125 |
| 58 | Thin rule |
| 59-73 | Power use (1-70): header bar, block digits, two lines |
| 59-79 | Divider at 72; Needs you (74-163, rows 59-63); Recent (rows 65-79) |
| 81 | Footer: `<` Back |

### Chart

- The summed plant buffer (stored over capacity, every reactor), one column per sample, resampled from the Operator's ring buffer (a sample every 15 s, 120 samples) to the 156 columns. Filled cyan to the value; the newest column white.
- The 30% and 90% thresholds (each reactor's `onBelow` and `offAbove`; the plant's when they differ) as dotted rows, `·` in every other empty cell: 90% lightBlue, 30% orange.
- No history yet (just started): the chart fills from the right as samples arrive; the rest is blank.

### Power Grid and reactor panels

- As in the earlier wall spec: the Power Grid totals, then up to three whole panels: state and what it waits for, rods 14 rows tall, what Auto did, level stepper and Auto/On/Off switch, buffer bar, readings (output, fuel, casing temperature, waste outlet). Every control works by touch as today.
- Each reactor's own Needs list moves off the wall (it is in the computer's Needs tab). Its problems show in the Needs you list below.
- More than three reactors: kit tiles in rows 31-56, as many columns as fit, as today; a tap opens the reactor on its Power tab.

### Glance band

- **Power use** (data from #119/#121, the energy detector): grey `POWER USE` header (columns 1-70); use as a percentage of what the reactor can make in block digits, pixel 4 wide x 2 tall (kit 10.13, rows 61-70); row 72 `3,400 of 3,000 FE/t`; row 73 a note. Colours as on the mainframe:
  - Under 100%: lime digits, note `Buffer 76%` dim.
  - 100% and up, not throttled: orange, note `Over output, buffer 41% falling` orange. Not an alert.
  - Throttled (`power.limit`, #121): red digits showing the capped use, red `THROTTLED` tag at the right end of the header, row 72 `Throttled at 2,700 FE/t`, row 73 `Asked for 4,800 (160%) for 2m` red.
  - No detector: dim `--`, row 72 `No energy detector on the cable` dim.
- **Needs you** (kit 10.14), four slots, worst first: `Power throttled: over 150%. Add power.` (red, only while throttled), then each reactor's missing parts and stuck outlets (red, `Reactor-1: waste outlet not emptying`), then unknowns (orange, `Power output unknown: tap off cable`). More than four: slot 4 `+2 more: ...`. Empty: `Nothing needs you.` lime and a dim summary `2 reactors: 1 on, 1 off by Auto, all parts found`.
- **Recent:** the event log, newest first, time dim and the event in white, up to 14 rows.
- Footer: Back, as today.

## Data the screen needs from the core

Per unit: state, waiting-for text, buffer %, FE/t, level (and rod count and each rod's level), mode (auto/on/off) with manual-hold time left, last auto change and reason, fuel %, inlet count, temperatures, waste outlet fill, and the needs list `{ id, label, state = ok|missing|unknown|na, value, reason }`. Plant: totals as shown, plus net FE/t.

## Setup wizard (#40)

Chosen by Tanis: style A (one question at a time) with a `Find it` button on the port pages. Mockups: https://claude.ai/artifact/XxGDy5Q8hkHvZLRsfY65EH

- A reactor with no saved setup shows the **New Reactor Awaiting Setup** card (cyan `info` stripe, `setup` in place of the state, a `Set up >` button on the 5-row tile) in place of its tile. It is read but not switched. Tapping the card starts the wizard.
- Pages: 1 found on the cable (`Not now` / `Start >`), 2 which port feeds fuel IN, 3 which port takes waste OUT, 4 check it (name field, the two ports, the switching defaults; `Back` / `Finish`). The header's right text is `step N of 4` (`N/4` under 40 wide).
- Port pages: the kit list of devices, each with what it holds (`12 uranium`, `3 cyanite`, `empty`), the likely one marked `suggested`; search field on the computer's own screen; `Find it` and `Pick >` on the footer row. A device taken as the inlet is not offered as the outlet.
- `Find it`: "Drop ONE uranium ingot into the fuel inlet port" (outlet: "Drop ONE item into the waste outlet port"), a spinner line `Watching N ports...`, then `Found: <port>` with `Not it` / `That's it >`. `Pick from list` goes back. If no device can list items it says so and offers the list.
- Wall: the panel of a reactor awaiting setup says to finish on the computer's screen.
- The Set tab gets `Run setup again` (tap twice).
