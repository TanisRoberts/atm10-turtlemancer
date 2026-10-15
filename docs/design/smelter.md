# Smelter: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/smelter/smelter.lua`

Auto-smelting computer: furnace array, training furnace, recipes, rules, factories. Monitor 3x2 (57x24) is the target; the computer screen shows the same.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Home 57x24 (3x2 board)

```text w=57
▓SMELTER▓                      8 furnaces  6 cooking  ok 
─────────────────────────────────────────────────────────
 ▒ Netherite 1^  ▒ Netherite 2^  │ TRAINER ──────────────
 ▒ raw iron      ▒ raw gold      │ Furnace 9 ready       
 ▒ x64      +12  ▒ x32           │ raw tin in the slot   
                                 │                       
 ▒ Diamond 1  ^  ░ Diamond 2     │ FACTORIES ────────────
 ▒ raw copper    ░ idle          │ 2 set up  80% power   
 ▒ x48       +5  ░               │                       
                                 │ RULES ────────────────
 ▒ Iron 1     ^  ▒ Iron 2     ^  │ iron               all
 ▒ cobblestone   ▒ sand          │ stone            20 st
 ▒ x64           ▒ x16       +3  │ copper             all
                                 │ plastic            all
 ░ Iron 3        ░ Furnace 1  ^  │                       
 ░ idle          ░ raw tin       │ ONE-OFF JOBS ─────────
 ░               ░ x8            │ stone         400 left
                                 │                       
                                 │                       
                                 │                       
                                 │                       
                                 │                       
                                 │                       
▒TRAIN▒ ▒Recipes▒ ░Pause░ ░Factories░        <  1/2  ░>░ 
```

- Left: the furnace array fastest first, a tile each: tier colour stripe, item and count, the smelting glyph (orange `^`) while it cooks, finished items waiting (`+12`, lime). Right column: trainer, factories, rules (tap one to open it), one-off jobs.
- **Calm:** only the glyph moves, 2 beats a second. The random flames are gone from the dashboard.
- Footer: TRAIN (green, nudges between yellow and lime when an item is waiting in the trainer), Recipes, Pause/Run, Factories, pager.
- Tile tap: nothing (furnaces are read-only here).


## Home 51x19 (computer)

```text w=51
▓SMELTER▓                8 furnaces  6 cooking  ok 
───────────────────────────────────────────────────
 ▒ Netherite 1             ^ │ TRAINER ────────────
 ▒ raw iron                  │ Furnace 9 ready     
 ▒ x64                   +12 │ raw tin in the slot 
                             │                     
 ▒ Netherite 2             ^ │ FACTORIES ──────────
 ▒ raw gold                  │ 2 set up  80% power 
 ▒ x32                       │                     
                             │ RULES ──────────────
 ▒ Diamond 1               ^ │ iron             all
 ▒ raw copper                │ stone          20 st
 ▒ x48                    +5 │ copper           all
                             │ plastic          all
 ░ Diamond 2                 │                     
 ░ idle                      │ ONE-OFF JOBS ───────
 ░                           │ stone       400 left
                             │                     
▒TRAIN▒ ▒Recipes▒ ░Pause░ ░Factories░  <  1/2  ░>░ 
```

- Same; right column 20 wide; tiles one per row if the array is small.


## Home 36x24 (2x2 display)

```text w=36
▓SMELTER▓                        ok 
────────────────────────────────────
 ▒ Netherite 1 ^  ▒ Netherite 2 ^   
 ▒ raw iron       ▒ raw gold        
 ▒ x64       +12  ▒ x32             
                                    
 ▒ Diamond 1   ^  ░ Diamond 2       
 ▒ raw copper     ░ idle            
 ▒ x48        +5  ░                 
                                    
 ▒ Iron 1      ^  ▒ Iron 2      ^   
 ▒ cobblestone    ▒ sand            
 ▒ x64            ▒ x16        +3   
                                    
 ░ Iron 3         ░ Furnace 1   ^   
 ░ idle           ░ raw tin         
 ░                ░ x8              
                                    
                                    
                                    
                                    
                                    
                                    
▒Train▒ ▒Rec▒ ░Pause░               
```

- No right column: the Trainer / Factories / Rules sit behind the footer buttons.


## Home 39x13 (short)

```text w=39
▓SMELTER▓                           ok 
───────────────────────────────────────
 ▒ Netherite 1   ^  ▒ Netherite 2   ^  
 ▒ raw iron         ▒ raw gold         
 ▒ x64         +12  ▒ x32              
                                       
 ▒ Diamond 1     ^  ░ Diamond 2        
 ▒ raw copper       ░ idle             
 ▒ x48          +5  ░                  
                                       
                                       
                                       
▒Train▒ ▒Rec▒ ░Pause░                  
```

- Tiles two columns; footer shortens to `Train` `Rec` `Pause`.


## Home: paused

```text w=57
▓SMELTER▓                8 furnaces  6 cooking  - paused 
─────────────────────────────────────────────────────────
 ▒ Netherite 1^  ▒ Netherite 2^  │ TRAINER ──────────────
 ▒ raw iron      ▒ raw gold      │ Furnace 9 ready       
 ▒ x64      +12  ▒ x32           │ raw tin in the slot   
                                 │                       
 ▒ Diamond 1  ^  ░ Diamond 2     │ FACTORIES ────────────
 ▒ raw copper    ░ idle          │ 2 set up  80% power   
 ▒ x48       +5  ░               │                       
                                 │ RULES ────────────────
 ▒ Iron 1     ^  ▒ Iron 2     ^  │ iron               all
 ▒ cobblestone   ▒ sand          │ stone            20 st
 ▒ x64           ▒ x16       +3  │ copper             all
                                 │ plastic            all
 ░ Iron 3        ░ Furnace 1  ^  │                       
 ░ idle          ░ raw tin       │ ONE-OFF JOBS ─────────
 ░               ░ x8            │ stone         400 left
                                 │                       
                                 │                       
                                 │                       
                                 │                       
                                 │                       
                                 │                       
▒TRAIN▒ ▒Recipes▒ ▒Run▒ ░Factories░          <  1/2  ░>░ 
```

- Header state `PAUSED` (orange, still glyph). Finished items still come out. `Run` replaces `Pause`.


## Home: storage not heard

```text w=57
▓SMELTER▓                 8 furnaces  6 cooking  ! error 
▒─Storage not heard: nothing new goes in.────────────────
 ▒ Netherite 1^  ▒ Netherite 2^  │ TRAINER ──────────────
 ▒ raw iron      ▒ raw gold      │ Furnace 9 ready       
 ▒ x64      +12  ▒ x32           │ raw tin in the slot   
                                 │                       
 ▒ Diamond 1  ^  ░ Diamond 2     │ FACTORIES ────────────
 ▒ raw copper    ░ idle          │ 2 set up  80% power   
 ▒ x48       +5  ░               │                       
                                 │ RULES ────────────────
 ▒ Iron 1     ^  ▒ Iron 2     ^  │ iron               all
 ▒ cobblestone   ▒ sand          │ stone            20 st
 ▒ x64           ▒ x16       +3  │ copper             all
                                 │ plastic            all
 ░ Iron 3        ░ Furnace 1  ^  │                       
 ░ idle          ░ raw tin       │ ONE-OFF JOBS ─────────
 ░               ░ x8            │ stone         400 left
                                 │                       
                                 │                       
                                 │                       
                                 │                       
                                 │                       
                                 │                       
▒TRAIN▒ ▒Recipes▒ ░Pause░ ░Factories░        <  1/2  ░>░ 
```

- Red alert line in the rule row until storage answers. Nothing new is sent in.


## Training: idle

```text w=57
▓TRAINING▓                             Furnace 9  - idle 
─────────────────────────────────────────────────────────
                                                         
 Tap TRAIN and I will fuel it and watch what comes out.  
                                                         
 Put the raw item in the trainer's TOP slot first.       
 One is enough. Leftovers go back into storage.          
                                                         
     PUT IN                                              
   ░░░░░░░░░░░░░░                                        
   ░            ░                                        
   ░  raw tin   ░                                        
   ░  x1        ░                                        
   ░░░░░░░░░░░░░░                                        
                                                         
 ▒TRAIN▒                                                 
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back ░Change░trainer░ ▒Recipes▒                      
```

- Explains the steps; `TRAIN` starts it. `Change trainer` opens Pick.


## Training: cooking

```text w=57
▓TRAINING▓                          Furnace 9  \ working 
─────────────────────────────────────────────────────────
                                                         
     PUT IN                             COMES OUT        
   ░░░░░░░░░░░░░░                     ░░░░░░░░░░░░░░     
   ░            ░  \ >>> >>>          ░            ░     
   ░  raw tin   ░    ^  ^  ^          ░   empty    ░     
   ░  x1        ░                     ░            ░     
   ░░░░░░░░░░░░░░                     ░░░░░░░░░░░░░░     
                                                         
                                                         
 Cooking one raw tin... (I give up after 40s)            
                                                         
 Fuel in  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ done 
 Cooking  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░ 16s left 
                                                         
 ▒CANCEL▒                                                
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back ░Change░trainer░ ▒Recipes▒                      
```

- The furnace art stays: PUT IN / COMES OUT cards, an animated arrow and flames (training is one-thing-at-a-time, so it may use the big motion), fuel and cook progress bars, `CANCEL` (tap-twice).
- Gives up after 40 s with `That did not work` and TRY AGAIN.


## Training: learned

```text w=57
▓TRAINING▓                             Furnace 9  + done 
─────────────────────────────────────────────────────────
                                                         
     PUT IN                             COMES OUT        
   ░░░░░░░░░░░░░░                     ░░░░░░░░░░░░░░     
   ░            ░  -----> learned     ░            ░     
   ░  raw tin   ░                     ░  tin ingot ░     
   ░  x1        ░                     ░  x1        ░     
   ░░░░░░░░░░░░░░                     ░░░░░░░░░░░░░░     
                                                         
                                                         
 Learned: raw tin -> 1 tin ingot per 1                   
                                                         
 What should I do with raw tin?                          
 ░No░rule░░Keep░N░stacks░▓Smelt▓all▓                     
                                                         
 ▓Save▓ ░Just░learn░it░                                  
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back ░Change░trainer░ ▒Recipes▒                      
```

- When it learned: choose a rule with the segmented switch, then Save. `Just learn it` saves the recipe with no rule.


## Pick the trainer

```text w=57
▓PICK▓THE▓TRAINER▓                watching...  o waiting 
─────────────────────────────────────────────────────────
                                                         
 | Drop any item into the TOP slot of the furnace you wan
 The smelting array is paused while I watch.             
 38 s left                                               
                                                         
 OR TAP ONE TO MAKE IT THE TRAINER ───────────────────── 
 ▓▓Furnace▓9▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓trainer▓now▓ 
   Iron 3                                  in the array  
   Furnace 10                              in the array  
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 ▒Find▒it▒ ▒No▒trainer▒                                  
                                                         
                                                         
░<░ Back                                                 
```

- Spinner while it watches. Tap a furnace, or drop one item in the TOP slot of the one you mean. `No trainer` clears it (tap-twice).


## Recipes 57x24

```text w=57
▓RECIPES▓                            42 known, 7 learned 
─────────────────────────────────────────────────────────
  iron              gold              copper             
 ▓tin▓▓▓▓▓▓▓▓▓▓▓▓▓  lead              silver             
  osmium            stone             sand               
  cobblestone       log               clay               
  kelp              cactus            potato             
  beef                                                   
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 yellow = learned                                        
 Tap one to set its rule.                                
                                                         
░<░ Back                                     <  1/3  ░>░ 
```

- Three columns of recipe names; yellow = learned. Tap opens the rule. Pager for more.


## Rule 57x24

```text w=57
▓RULE:▓RAW▓TIN▓                                  learned 
─────────────────────────────────────────────────────────
 Smelts into                   1 tin ingot per 1 raw tin 
 In storage                        1,240 raw, 320 ingots 
 Made so far                                         480 
                                                         
 RULE ────────────────────────────────────────────────── 
 ░No░rule░▓Keep▓N▓stacks▓░Smelt░all░                     
                                                         
 Keep  ░-░  20 ░+░     stacks of tin ingot               
 Now: keep 20 stacks. 760 left to smelt.                 
                                                         
 DO IT NOW ───────────────────────────────────────────── 
 ▓Smelt▓64▓ ░Smelt░400░ ░Smelt░all░                      
                                                         
                                                         
 ▓Save▓ ▒Forget▒                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- Segmented switch for the rule, a stepper for stacks, one-off smelt buttons (queue a job), `Forget` (learned only, tap-twice).


## Factories 57x24

```text w=57
▓FACTORIES▓                                     2 set up 
─────────────────────────────────────────────────────────
 ▒ factory_3                                  \ working  
 ▒ feed barrel_40 -> out barrel_41                       
 ▒ 80%, 12 procs                                         
                                                         
 ▒ chamber_1                                  o waiting  
 ▒ feed barrel_42 -> out barrel_43                       
 ▒ power low, 0 procs                                    
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 Storage fills the feed barrel and never stores in either
                                                         
 ▒+▒Add▒ ▒Remove▒F1▒                                     
                                                         
                                                         
                                                         
░<░ Back                                                 
```

- A card per factory: state stripe, feed and out barrels, power and process count. `Remove` is tap-twice.


## Add a factory (wizard step 2/3)

```text w=57
▓ADD▓A▓FACTORY▓                                 step 2/3 
─────────────────────────────────────────────────────────
 Pick its FEED barrel (hopper upgrade into the factory): 
                                                         
 ▓▓barrel_40▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓empty▓ 
   barrel_42                                      empty  
   barrel_50                                 in storage  
                                                         
                                                         
 Needs: factory with a wired modem (red ring), a feed bar
 cable, and auto-eject into an out barrel on the cable.  
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
░Cancel░                                                 
```

- Three steps (machine, feed, out), each a list of what is left on the cable. `Cancel` leaves.
