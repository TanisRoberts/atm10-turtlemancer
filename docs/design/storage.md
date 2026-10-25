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


## Depot rules (#74)

Signed off by Tanis (#76): option B (rule form) with C's "Something like this" as a shortcut, plus a priority field.

A depot holds a **rule** instead of one item. Storage keeps each depot filled with what its rule matches, and inputs are always emptied: a new item that a depot wins goes straight to that depot; if the depot is full it goes to normal storage and comes over later as the depot empties.

### Rules

- A rule has up to four conditions, all of which must match: **Item** (an item id, every variant of it), **Tag** (one item tag, e.g. `c:enchantables`), **Mod** (the id's namespace, `apotheosis` in `apotheosis:gem`), **Enchanted** (Any / Yes / No). At least one must be set.
- Tags and enchantments come from `getItemDetail` (`tags`, `enchantments`), read once per variant key and cached with the rest of `info`. Enchanted books count as enchanted (check that CC's `enchantments` includes stored enchantments; if not, treat a non-empty stored list the same).
- **Priority**: a number 0 to 9999, default 0. Higher wins a tie.
- Saved in `cfg.depots[container]` as `{ item=, tag=, mod=, enchanted=true|false|nil, priority=0, added=N }` (`added` counts up, for the last tie-break). An old string value (`"minecraft:enchanted_book"`) still loads as `{ item = that }`. `""` is still "not chosen yet".

### Which depot gets an item

Each item variant goes to at most one depot, the winner:

1. Most specific rule: score Item 8 + Tag 4 + Mod 2 + Enchanted set 1. So an exact item beats any tag rule, and tag + enchanted beats tag alone.
2. Then the higher priority.
3. Then the depot added first.

If the winner is full or missing, the item stays in storage. It never goes to the next depot down. Items already in a depot that no longer match are left alone, as today.

Example: `library_books` (Item enchanted book) and `disenchant` (Tag c:enchantables + Enchanted Yes). Books go to the library, enchanted swords to the disenchanter, plain swords to neither.

### Step 2: the rule form (replaces the item list)

```text w=57
░ADD░DEPOT░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░step░2░of░3░ 
 What goes in library_in? Set any of these.              
                                                         
 Item       ░any░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
 Tag        ░c:enchantables░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
 Mod        ░any░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
 Enchanted  ░Any░ ▒Yes▒ ░No░                             
                                                         
 Matches now: 58 kinds, 149 items                        
   Enchanted book                                    41  
 ░Enchanted░diamond░sword░░░░░░░░░░░░░░░░░░░░░░░░░░░░2░  
   Enchanted iron pickaxe                             4  
 ░Enchanted░bow░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░1░  
   Enchanted netherite boots                          1  
 ... 53 more                                             
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 ▒Next▒ ░Something░like░this░ ░Back░                     
                                                         
```

- Tap **Item**, **Tag** or **Mod** to open the pick list for it; tap a set row's value and pick **Any** to clear it. Enchanted is three toggle buttons (cyan = current).
- **Matches now** is live: kinds and items in storage that this depot would win, top 5 by count. A rule that would lose items to another depot still lists them here, but the summary says where they go (Overlaps).
- **Next** is disabled (grey) until at least one condition is set.
- **Something like this** opens the example page.

### Pick list (Item, Tag or Mod)

```text w=57
░DEPOT░TAG░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░pick░one░
 Tags on items in storage. Type to narrow it down.       
 c:enchantables                            63 kinds  212 
░c:tools░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░40░kinds░░░88░
 c:tools/melee_weapon                      18 kinds   31 
░c:armors░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░24░kinds░░░40░
 minecraft:enchantable/durability          71 kinds  230 
░minecraft:bookshelf_books░░░░░░░░░░░░░░░░░░4░kinds░░░96░
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 ░Any░ ░Back░                                  page 1/9  
░Search:░c:_░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
```

- Same list as today's item step: search at the bottom, pager, tap a row to pick it and go back to the form. Item lists item ids (variants merged), Tag lists every tag on items in storage with kinds and items, Mod lists namespaces.
- **Any** clears the condition.

### Something like this

```text w=57
░SOMETHING░LIKE░THIS░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
 Drop one example into library_in, then tick what counts.
 Example: Enchanted book (Mending)                       
                                                         
 ▒x▒ This item, any variant   Enchanted book          41 
 ░ ░ Enchanted                yes                    149 
 ░ ░ Tag                      c:enchantables         212 
 ░ ░ Tag                      minecraft:bookshelf_b   96 
 ░ ░ Mod                      minecraft             9.1k 
                                                         
 Ticked lines fill in the form. Only one tag can be      
 ticked (the form has one Tag row).                      
                                                         
 Matches now: 1 kind, 41 items                           
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 ▒Use▒these▒ ░Other░example░ ░Back░                      
                                                         
```

- Uses the existing "drop one item in" watch on the depot itself (storage stops moving items while it watches, 30 s). The dropped item stays in the depot.
- Lists everything true about the example: the item, Enchanted (yes or no), each of its tags, its mod, with how much storage has of each. Tap to tick. Only one Tag line can be ticked; ticking another moves the tick.
- **Use these** fills the form's rows from the ticks (replacing them) and goes back. **Other example** watches again.

### Step 3: summary

```text w=57
░ADD░DEPOT░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░step░3░of░3░ 
 Check it, then Save.                                    
 Name      minecraft:barrel_14                           
 Nickname  ░library_in░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 
 Holds     Tag c:enchantables, enchanted                 
 Priority  ░0░░░░    higher wins a tie, 0 to 9999        
                                                         
 Matches   58 kinds, 149 items in storage now            
 Overlaps  Enchanted book: goes to library_books (more   
           specific)                                     
                                                         
 New matches go here first; when it's full they wait     
 in storage and come over as it empties.                 
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
                                                         
 ▒Save▒ ░Back░                                           
                                                         
```

- **Holds** sums up the rule in words; tap it to go back to the form.
- **Priority** is a text field: digits only, up to 4, empty saves as 0.
- **Overlaps** lists other depots that win some of what this rule matches (up to 2 lines, "+N more").
- The edit page for an existing depot shows the same Holds and Priority rows; Holds opens the form.

### Smaller screens

- 51x19 computer: same pages; the form's preview shows 2 rows, the pick list 13 rows per page.
