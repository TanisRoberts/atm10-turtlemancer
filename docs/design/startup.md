# Startup and reset: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `startup.lua, reset.lua`

What every device shows when it boots and updates, and the reset confirmation.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## startup: updated 51x19

```text w=51
Turtlemancer: Foreman computer (Foreman-01)        
                                                   
| Updating from GitHub...                          
▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░░░ 24/30    
                                                   
Updated: foreman.lua, ui.lua, ui_widgets.lua       
                                                   
Starting foreman...                                
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
```

- What every device shows on boot. A spinner and a progress bar while it downloads, then a one-line summary. Kept 1 s, then the role starts.


## startup: up to date / offline / kept old / self update

```text w=51
Turtlemancer: Foreman computer (Foreman-01)        
                                                   
Updated: foreman.lua                               
Kept old: ui.lua (bad download)                    
A file that does not compile never replaces a worki
                                                   
Starting foreman...                                
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
```

- Variants: `Already up to date.` (lime); `Could not reach GitHub: starting with the files I have.` (orange); `Kept old: x (bad download)` (orange, only for files that did not compile); `startup.lua changed: rebooting...` (yellow).


## startup: 39x13

```text w=39
Turtlemancer: Foreman computer (Foreman
                                       
| Updating from GitHub...              
▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░░░░░ 24/30    
                                       
Updated: foreman.lua, ui.lua, ui_widget
                                       
Starting foreman...                    
                                       
                                       
                                       
                                       
                                       
```

- Same, one column; lines wrap.


## startup: duplicate ID

```text w=51
▒DUPLICATE▒ID▒#17?▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒
                                                   
This disk belongs to "Foreman-01" (computer).      
This is "Smelter-02" (computer).                   
Set up as: nothing yet.                            
Two machines with the same ID share their files.   
                                                   
[1] Same machine, carry on                         
[2] Stop: show the fix                             
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
```

- Red header, the two machines, and two choices (click or press 1 / 2). 2 shows the four-step fix.


## reset

```text w=51
RESET THIS DEVICE                                  
Wipes its role, scripts, saved state, maps and conf
then runs setup again so you can pick a new role.  
                                                   
Type RESET to confirm: RESET_                      
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
```

- Type RESET to confirm; Esc cancels. Warns that turtle items stay.
