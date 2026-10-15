# GPS host: screens

Part of issue #26. Built from the UI kit (`docs/design/ui-kit.md`): header B, buttons B, tiles B, the palette and motion A.

**Code:** `computer/gps/gps_host.lua`

A GPS tower: a status page and a first-run form.

Mockup legend: every block is exactly the width in its `w=` tag. A space is a black cell; `░` grey, `▓` gold, `▒` any other colour; letters sit on top; `─` is the thin rule. Colours are in the review page.


## GPS host 51x19

```text w=51
▓GPS▓HOST▓                        tower 2 of 4  ok 
───────────────────────────────────────────────────
 GPS host at 812 214 -1203                         
                                                   
 Turtles ask me where they are. Leave me running.  
 Delete gps.cfg and reboot if I'm moved.           
                                                   
 Warning lilamp on my top side, flashing every 3 s 
 Answered                1,204 requests since boot 
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
```

- Terminal only. State, coordinates, lamp, request count. The aircraft warning lamp flashes on the real-world clock as today (no motion on screen).


## GPS first run

```text w=51
▓GPS▓HOST▓                 tower 2 of 4  o waiting 
───────────────────────────────────────────────────
 First run: where am I?                            
 Press F3 and read the computer block's coordinates
                                                   
 X   ░812_░░░░░░░                                  
 Y   ░214_░░░░░░░                                  
 Z   ░-1203_░░░░░                                  
                                                   
 Other towers answered: filled in from them (X 812,
                                                   
 ▓Save▓ ░Cancel░                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
                                                   
```

- First-run form: three fields, filled from other towers when they answer.
