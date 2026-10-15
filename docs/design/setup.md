# Setup: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `setup.lua`

First-time setup: pick type, role and name, one card at a time.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## Pick the device type 51x19

```text w=51
▓SETUP▓ step 1 of 3                                
                                                   
 What are you setting up?                   1 of 3 
                                                   
 ^ Glasses                                         
 ▓COMPUTER▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓suggested▓ 
 ▓ A computer that sits at the base                
 ▓                                                 
 ▓ The base's brains: storage, smelting, the ma..  
 ▓ the Foreman, the Nether Foreman, the Farmhan..  
 ▓                                                 
 ▓                                                 
 ▓                                                 
 ▓                                                 
 ▓                                                 
 ▓                                                 
 v Turtle                                          
                                                   
                  up/down browse           ▓Pick▓>▓
```

- One option at a time, like a character select: the card in the middle, the neighbours peeking above and below. Up/Down, Left/Right, scroll, number keys, or click the neighbours; Enter, `Pick >` or a click on the card picks. Backspace or `< Back` goes back.
- The selected card is gold, as everywhere in the kit (selected = gold). `suggested` marks what the machine looks like (turtle, computer, glasses); a warning line (orange) says if the pick does not match the hardware.


## Pick the role 51x19

```text w=51
▓SETUP▓ step 2 of 3                                
                                                   
 Which role?                                1 of 3 
                                                   
 ^ Foreman                                         
 ▓MAINFRAME▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓suggested▓ 
 ▓ Chat, alerts, island strip, status board        
 ▓                                                 
 ▓ The server. Chat commands and alerts, a moni..  
 ▓ showing every machine, and the butler: $dump..  
 ▓ top-ups, welcomes, visitors and the storage ..  
 ▓                                                 
 ▓ Needs an ender or wireless modem.               
 ▓                                                 
 ▓                                                 
 ▓                                                 
 v Storage                                         
                                                   
 ░<░Back░         up/down browse           ▓Pick▓>▓
```

- Same picker for the role. Long text ends in `...` when the screen is short.


## Pick the role 39x13 (turtle)

```text w=39
▓SETUP▓ step 2 of 3                    
                                       
 Which role?                    1 of 3 
 ^ Foreman                             
 ▓MAINFRAME▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓suggested▓ 
 ▓ Chat, alerts, island strip, stat..  
 ▓                                     
 ▓ The server. Chat commands and al..  
 ▓ showing every machine, and the b..  
 ▓ top-ups, welcomes, visitors and ..  
 ▓                                     
 v Storage                             
 ░<░Back░   up/down browse     ▓Pick▓>▓
```

- Turtle: spacing squeezes, the second detail paragraph drops.


## Pick the role 26x20 (glasses)

```text w=26
▓SETUP▓ step 2 of 3       
                          
 Which role?       1 of 3 
                          
 ^ Foreman                
 ▓MAINFRAME▓▓▓▓suggested▓ 
 ▓ Chat, alerts, islan..  
 ▓                        
 ▓ The server. Chat co..  
 ▓ showing every machi..  
 ▓ top-ups, welcomes, ..  
 ▓                        
 ▓ Needs an ender or w..  
 ▓                        
 ▓                        
 ▓                        
 ▓                        
 v Storage                
                          
 ░<░Baup/down brow▓Pick▓>▓
```

- Glasses: card text wraps at 21 characters.


## Name it

```text w=51
▓SETUP▓ step 3 of 3                                
                                                   
 Name this computer                                
                                                   
 Shown on the status board and in chat. Enter keeps
 the suggestion.                                   
                                                   
 ░Foreman-01_░░░░░░░░░░░░░░                        
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
 ░<░Back░                                 ▓Save▓>▓ 
```

- A text field with the suggested name; Enter keeps it. `auto` roles (Canaries) skip this step.


## Saved

```text w=51
                                                   
                                                   
 Saved: Computer, Foreman, labelled Foreman-01.    
                                                   
 | Rebooting to download its files...              
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
```

- Confirmation, a spinner, then reboots into startup.
