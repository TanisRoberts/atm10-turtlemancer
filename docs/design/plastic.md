# Plastic factory: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/plastic/plastic.lua`

One dashboard for the latex and plastic line.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Dashboard 57x24

```text w=57
▓PLASTIC▓FACTORY▓               ~14.2 plastic/h  running 
─────────────────────────────────────────────────────────
 Made 1,204 plastic                                      
                                                         
 LATEX UNIT 1 ────────────────────────────────────────── 
 latex ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░ 72% 
 water ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░ 90% 
 power ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░ 55% 
                                                         
 TAPS ────────────────────────────────────────────────── 
 #1 ok       #2 ok       #3 full     #4 DRY              
 #5 ok       #6 ok       #7 ok       #8 full             
                                                         
 FURNACES AND DOCK ───────────────────────────────────── 
 Furnace 1: 3 cooking, fuel 40                           
 Dock: fuel for 280, 64 plastic out                      
                                                         
 ▒ Tap #4 is dry: its log is used up. Replace the log.   
                                                         
                                                         
                                                         
                                                         
                                                         
░Pause░                                                  
```

- One screen. Header: state (running lime and moving, paused orange still, waiting yellow), plastic per hour. Bars: latex (grey-white), water (blue), power (red when charged).
- Taps: one cell each, coloured ok (lime), full (orange), DRY (red). Problems at the bottom as red alert lines (and on the board).
- Footer: Pause / Run (tap). Terminal commands unchanged.


## Dashboard: paused

```text w=57
▓PLASTIC▓FACTORY▓              ~14.2 plastic/h  - paused 
─────────────────────────────────────────────────────────
 Made 1,204 plastic                                      
                                                         
 LATEX UNIT 1 ────────────────────────────────────────── 
 latex ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░ 72% 
 water ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░ 90% 
 power ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░ 55% 
                                                         
 TAPS ────────────────────────────────────────────────── 
 #1 ok       #2 ok       #3 full     #4 DRY              
 #5 ok       #6 ok       #7 ok       #8 full             
                                                         
 FURNACES AND DOCK ───────────────────────────────────── 
 Furnace 1: 3 cooking, fuel 40                           
 Dock: fuel for 280, 64 plastic out                      
                                                         
 ▒ Tap #4 is dry: its log is used up. Replace the log.   
                                                         
                                                         
                                                         
                                                         
                                                         
▒Run▒                                                    
```

- Paused: header orange, Run in the footer.


## Dashboard 39x13

```text w=39
▓PLASTIC▓                      running 
───────────────────────────────────────
 Made 1,204  ~14.2/h                   
 ▒ Tap #4 is dry                       
 Unit 1 L72 W90 P55                    
 Taps 7 ok, 1 DRY                      
 Furnace: 3 cooking                    
 Dock fuel 280                         
                                       
                                       
                                       
                                       
░Pause░                                
```

- Short: one line per thing, problems first (as today).
