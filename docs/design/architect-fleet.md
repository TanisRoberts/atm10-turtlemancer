# Architect fleet: setup wizard, pairing, build and site

Issue #84 (project #81). Tanis picked option A (review page: https://claude.ai/artifact/BwPeXA98HAHgM4Jaf4mCKy). Built from the UI kit (`docs/design/ui-kit.md`). The tabs after setup follow `docs/design/architect.md`, with the changes in "After setup" below. Protocol and data: `docs/systems/weaver.md`.

**Code:** `computer/architect/` (#88), replacing `architect.lua` in place.

Mockup legend as in `architect.md`: `▓` gold, `░` grey, `▒` any other colour, letters on top. The header chip is gold (black letters). Exact colours are on the review page. Example data throughout (Desert Arena, Weaver-02, turtle #214, coordinates).

## Flow

A fresh Architect (no `Architect-NN` label) opens the wizard at step 1. A paired one with no build opens it at step 2; one with a build but no site at step 3. Once a build has started, boot goes straight to Status. Typing `setup` reopens the wizard at step 2 (load the next build) or any step (the step bar is tappable). Esc or Back on step 1 leaves the wizard if the Architect is already paired.

The header right shows `setup step N of 4`. Row 3 is the step bar: done steps dim, the current step gold, later steps dim. Back is at the bottom left, Next (primary, gold) at the bottom right; Next is disabled until the step is complete.

## Step 1: Weaver

```text w=51
ARCHITECT                         setup step 1 of 4
───────────────────────────────────────────────────
 Weaver  > Build > Site > Go                       
                                                   
 Which Weaver does this computer run?              
                                                   
 ▓A▓new▓Weaver▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓>▓     
    Pairs with a turtle that has no number yet.    
                                                   
 ░An░existing░Weaver,░by░number░░░░░░░░░░░░>░      
    This computer replaces a lost Architect.       
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
 up/down choose, Enter picks                       
```

- Two picker rows (selected row gold). Up/Down or tap chooses, Enter or tap again picks.

**New Weaver** (pairing, `weaver.md` section 5):

```text w=51
ARCHITECT                         setup step 1 of 4
───────────────────────────────────────────────────
 Weaver  > Build > Site > Go                       
                                                   
 | Listening for Weavers with no number            
                                                   
 ▓Turtle▓#214▓▓▓▓heard▓1s▓ago▓▓▓no▓number▓▓▓▓▓     
 ░Turtle░#388░░░░heard░4s░ago░░░no░number░░░░░     
                                                   
 The ID is on the turtle's own screen. Pick it,    
 and the mainframe hands out the next number.      
                                                   
 Number    02 from the mainframe                   
 Turtle    #214 is now Weaver-02                   
 Me        Architect-02                            
                                                   
                                                   
<Back                                    ▓Next▓>▓  
                                                   
```

- Lists turtles heard saying `hello` (no number) with their computer ID and when last heard; refreshes live. The turtle shows its ID on its own screen.
- Picking one runs the handshake; the three lines below fill in one by one (spinner while waiting, lime when done): number from the mainframe, turtle relabelled, this computer relabelled.
- Mainframe silent for 10 s: the Number line turns orange, "the mainframe hasn't answered, is it on?", and keeps asking.
- No turtles heard: a waiting line (`ui-kit` 9.3) "Listening for Weavers with no number. Put the turtle down and boot it."

**Existing Weaver, by number** (re-link):

```text w=51
ARCHITECT                         setup step 1 of 4
───────────────────────────────────────────────────
 Weaver  > Build > Site > Go                       
                                                   
 Re-link to Weaver number                          
                                                   
 Number  02_░░░░░░░░░░░░░░░░                       
                                                   
 Weaver-02 answered (turtle #214)                  
 Building    Desert Arena, layer 9                 
 Site        dock 812 64 -1170, facing E           
                                                   
 I don't have the build file. Drag                 
 Desert Arena.litematic onto this screen to        
 carry on where he is.                             
                                                   
                                                   
<Back                                     Next >   
                                                   
```

- Text field takes 1-3 digits. Enter sends `relink`. The Weaver's answer fills the lines below: build name, layer, site.
- If he holds a build, the screen asks for the same file to be dropped (gold file name). A dropped file whose hash doesn't match says so in red and is not used. Next is enabled once the file matches, and goes straight to Status (his site is already set).
- No answer in 10 s: "No Weaver-02 answered. Is he on, with an ender modem?" in orange; keeps asking.

## Step 2: Build

```text w=51
ARCHITECT-02                      setup step 2 of 4
───────────────────────────────────────────────────
 Weaver > Build  > Site > Go                       
                                                   
                                                   
        Drag a .litematic file onto this           
        screen to load a build.                    
                                                   
     Reading Desert Arena.litematic (12 KB)        
     ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░      
     layer 16 of 41, 6,120 blocks so far           
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
<Back                                              
                                                   
```

- Waiting for a file: two lines of instruction. Dropping a `.litematic` (or a `.plan2`) starts reading: a progress bar by layer and a running block count (it yields, so the screen stays live).
- Errors (not a litematic, several regions, file too big for the disk) show in red in place of the bar, with what to do.

```text w=51
ARCHITECT-02                      setup step 2 of 4
───────────────────────────────────────────────────
 Weaver > Build  > Site > Go                       
                                                   
 Build     Desert Arena  by WoezelenPep            
 Size      76 x 64, 28 high                        
 Blocks    10,012 of 17 kinds                      
 Placing   9,996 as the file says                  
           16 a simpler way (see list)             
                                                   
 Most used                                         
  Cut Sandstone        3,349   storage 4,200       
  Red Terracotta       2,697   storage   310       
  Sandstone            2,154   storage 9,800       
  Sandstone Stairs     1,357   storage   900       
                                                   
 ░All░17░ ░Simpler░16░ ░Other░file░                
<Back                                    ▓Next▓>▓  
                                                   
```

- Summary: name and author (from the file), trimmed size, blocks and kinds, how many are placed as the file says (lime) and how many a simpler way (`U`, orange).
- Most used: top 4 by count with storage's stock (lime enough, orange less than needed, red less than a tenth).
- `All 17` opens the full bill (the Bill tab's list as a report page). `Simpler 16` lists the `U` cells: block, where, why. `Other file` clears it and goes back to waiting for a drop.

## Step 3: Site

```text w=51
ARCHITECT-02                      setup step 3 of 4
───────────────────────────────────────────────────
 Weaver > Build > Site  > Go                       
 Read F3 standing there. Block, not XYZ.           
 Weaver's dock 812░░64░░-1170 NESW                 
 Corner (SW)   820░░64░░-1176                      
 Turn          090180270                           
  ░░░░░░░░░░░░░░░░░░░░░░░░░░  North up             
  ░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░  76 wide E-W          
  ░▒▒░░░░░░░░░░░░░░░░░░░░▒▒░  64 deep N-S          
  ░▒▒░░░░░░░░░░░░░░░░░░░░▒▒░                       
  ░▒▒░░░░░░░░░░░░░░░░░░░░▒▒░  ▒▒ build             
  ░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░  D dock               
D>░░░░░░░░░░░░░░░░░░░░░░░░░░                       
 Corner is 8 E, 6 N of the dock. Needs a           
 76 x 64 flat area; yours is 96 x 80.              
 ░Test░ Weaver marks the 4 bottom corners          
<Back                                    ▓Next▓>▓  
                                                   
```

- Tanis stands on the spot and reads F3's **Block** line (whole numbers). Two triples of text fields; Tab moves X, Y, Z, next field.
- **Weaver's dock:** where the turtle sits (on his ender chest), plus his facing: N E S W segmented switch (kit 10.4). Tanis reads which way the turtle's front faces.
- **Corner (SW):** the south-west bottom corner, the first block of the bottom layer, as it will be after turning. Turning keeps this corner where it is; the build grows north and east from it.
- **Turn:** 0 / 90 / 180 / 270 segmented switch, clockwise seen from above. The size lines swap (76 E-W x 64 N-S at 0 and 180, 64 x 76 at 90 and 270).
- **Preview:** the footprint (cyan outline, 2 cells thick) and the dock (`D` gold, with an arrow for his facing), scaled to fit, north up. Below it, one line with the corner's offset from the dock ("8 E, 6 N of the dock") so a typo shows as a strange number.
- `Test` sends Weaver to mark the 4 bottom corners of the footprint (as today's test marker, cleared with `clear`). Status shows his progress.
- Next is enabled when both positions are filled in. A dock inside the footprint is shown red with "the dock is inside the build".

## Step 4: Go

```text w=51
ARCHITECT-02                      setup step 4 of 4
───────────────────────────────────────────────────
 Weaver > Build > Site > Go                        
                                                   
 Weaver   Weaver-02 at the dock, fuel 4,800        
 Build    Desert Arena, 28 layers                  
 Site     SW corner 820 64 -1176, turn 0           
 Supply   storage has ender chest 02               
 Bill     short of 2 kinds (gaps are fine)         
 Time     about 5 h 30, fuel about 23,000          
                                                   
 He sends the bill to storage, asks for the        
 first batch, then starts the bottom layer.        
                                                   
                                                   
                                                   
                                                   
<Back                             ▓Start▓build▓    
                                                   
```

- One summary line per part, each with its state. Supply comes from storage's answer (is there a Weaver supply job for this number). Bill short counts kinds storage doesn't have enough of; gaps are fine. Time and fuel are the converter's estimate.
- `Start build` (primary) sends the build, the first two layers and the `build` order, and switches to Status.

## After setup: tabs

Tabs: Status, Map, Side, Bill, Log (Corners is gone). The header chip reads `ARCHITECT-NN`; the summary is `Weaver-NN seen Ns ago`. No "island" or "seabed" anywhere; Side shows the build from the side with the ground line instead of sea level.

```text w=51
ARCHITECT-02        Weaver-02 seen 2s ago  building
───────────────────────────────────────────────────
 Build       Desert Arena  10,012 blocks, 28 high  
 Now         Layer 6 of 28, block 412 of 1,180     
 Layer   ▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░ 35% 
 Build                       2,431 / 10,012        
 Overall ▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 24% 
 Fuel    ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░░░░░░░ 12,400 
                                                   
 At              31 6 -12 from dock, facing E      
 Supply  storage is out of Red Terracotta          
         leaving 214 gaps, fills them later        
                                                   
 ▓Build▓ ░Stop░ ░Test░ ░Home░ ▒Reboot▒             
                                                   
                                                   
                                                   
>type░a░command░(help)░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
Status Map Side Bill Log                           
```

- The `At` line is relative to the dock (dead reckoning). The `Supply` line shows the newest supply problem, else "ok". `Home` sends him to the dock.

**Supply problems** turn the header row 2 into a notice (kit 4.7) and the Status body into a checklist:

```text w=51
ARCHITECT-02        Weaver-02 seen 1s ago   waiting
 ! Weaver-02 has waited 12 min for supplies        
 Build       Desert Arena  10,012 blocks, 28 high  
 Now         Layer 9 of 28, at the dock            
                                                   
 Supply  no answer from storage                    
         asked 144 times since 14:02               
                                                   
 Things to check                                   
  - Is storage on? Its screen shows the queue.     
  - /assign: is an ender chest set as              
    Weaver supply 02?                              
  - Same dye code on both ender chests?            
                                                   
 ░Ask░again░ ░Stop░                                
                                                   
                                                   
>type░a░command░(help)░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
Status Map Side Bill Log                           
```

- Storage hasn't answered his `supply` request for 5 min: red line "no answer from storage" with the count and the checklist above.
- Storage answered but sent nothing he needs for 10 min (everything `missing`): orange "storage is out of X" and "leaving gaps, fills them later". No notice unless every cell left needs a missing block.

## Monitor

Unchanged from today: an advanced monitor touching the computer (any size, made for 2x2) shows the Map alone, following Weaver (his layer, him, progress, gaps). Display only. The computer's own screen is the one you drive. During setup the monitor shows the site preview from step 3 once a site is set, else the header with "setting up".

## Keys and commands

- Wizard: Up/Down, Enter, Tab between fields, Esc/Backspace back. Commands still work on the command bar of the tabs.
- New commands: `setup` (reopen the wizard), `home`. Kept: `build`, `stop`, `test`, `clear`, `reboot`, `layer <n>`, `follow`, `zoom <n>`, `refresh`, `help`. Gone: `ext`.
