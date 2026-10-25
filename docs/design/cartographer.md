# Cartographer: map floor and computer

Issue #66 (project #73). Artifact: https://claude.ai/artifact/Xti1trijwJuXFVDZJfRU4F (round 2; Tanis picked B, split into a floor and a computer screen).

The Cartographer is an advanced computer with an ender modem and an **8x6 advanced monitor laid flat as a floor** (164x81 characters at text scale 0.5, 328x243 map pixels at 2x3 per cell). The floor shows only the map. The computer's own screen (51x19) holds Seagull's panel, the next-region pick, storage and the map controls. The floor and the computer show the same view: panning or zooming on either moves both, except while the floor is in **Fill** (below).

Any floor size must work: the zoom bar stays 8 columns wide on the right; on a shorter floor the track gets shorter.

## Map (both screens)

- **Never seen**: black background (`black`) with a faint grey dot (`grey`) every few cells. Unexplored ground also shows the region grid as dotted lines, so the squares Seagull can be sent to are visible.
- **Ocean** is always solid blue (`blue` deep, `lightBlue` shallow), so it can never be mistaken for never seen.
- **Regions** are 16x16 chunks (256x256 blocks; sizes confirmed in #65). Finished regions are drawn as map with no border. The region Seagull is scanning has a **cyan** outline with `~NN%` in it (an estimate from his start time and the usual time per region, since he's off the radio while scanning). The queued next region has a **white** outline with `NEXT`.
- Turtles (`●` + label, white on black), pylons (red `+`) and Seagull (`●` in his region) are drawn on top.
- Zoom levels: 1, 2, 4, 8, 16 blocks per pixel.

### Colours (16 slots, shared by map and kit)

Land drops to 6 height bands so the kit keeps its colours. The map room doesn't need pink, magenta or purple, so those slots are repainted as land with `setPaletteColour` on both screens.

| slot | hex | use |
|---|---|---|
| black | #17181C | background, never seen |
| grey | #3A3C42 | buttons, bars, never-seen dots |
| lightGrey | #A6A8B0 | dim text; highest land (stone) |
| white | #F2EFE4 | text, turtles, next-region outline |
| yellow | #F2B71F | gold: title chip, MAP |
| orange | #F58340 | warn: low fuel, disk filling |
| red | #F2686E | bad; pylons |
| lime | #86D96B | good; grass land |
| cyan | #4CC3CC | scanning region, progress |
| blue | #1E3C8C | deep water |
| lightBlue | #3F78C8 | shallow water (also "docked") |
| green | #2E6B30 | trees |
| pink | #E0D49A | beach land (y 62) |
| magenta | #5AA646 | low land |
| purple | #7D9A4A | mid land |
| brown | #8B5E3C | hills |

## Floor (8x6 monitors, 164x81)

No header, no buttons except the zoom bar and FILL on the right 8 columns. Example data. `░` marks a grey button background.

```
·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·           
                                                                                                                                                             ░░░░░░ 
                                                                                                                                                             ░░+░░░ 
·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    ░░░░░░ 
                                                                                                                                                                    
                                                                                                                                                                    
·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    ┼ 1    
                                                                                                                                                             │      
 · · · · · · · · · ·                                 ▌▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▐ · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · │      
·   ·   ·   ·   ·   ·                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                     ▌                               ▐                                                                       │      
                                                     ▌                               ▐                                                                       │      
·   ·   ·   ·   ·   ·                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                     ▌                               ▐                                                                       │      
                                                     ▌                               ▐                                                                       │      
·   ·   ·   ·   ·   ·                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                     ▌                               ▐                                                                       │      
                                                     ▌      ● Seagull-01G            ▐                                                                       │      
·   ·   ·   ·   ·   ·                                ▌  ·   ·   ·  ~40% ·   ·   ·   ·▐  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                     ▌                               ▐                                                                       │      
                                                     ▌                               ▐                                                                       │      
·   ·   ·   ·   ·   ·                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    ┼ 2    
                                                     ▌                               ▐                                                                       │      
                                                     ▌                               ▐                                                                       │      
·   ·   ·   ·   ·   ·                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                     ▌                               ▐                                                                       │      
                                                     ▌                               ▐                                                                       │      
·   ·   ·   ·   ·   ·                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                     ▌                               ▐                                                                       │      
 · · · · · · · · · ·                                 ▌▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▐                               ▌▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▐ · · · │      
·   ·   ·   ·   ·   ·                                                                                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·    │      
                                                          +                                                          ▌                               ▐       │      
                                                                                                                     ▌                               ▐       │      
·   ·   ·   ·   ·   ·                                                                                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·    │      
                                                ● Woodpecker-01                                                      ▌                               ▐       │      
                                                                                                                     ▌                               ▐       │      
·   ·   ·   ·   ·   ·                                               ● Canary-04                                      ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·   ▐█ 4    
                                                                                                                     ▌                               ▐       │      
                                                                                                                     ▌                               ▐       │      
·   ·   ·   ·   ·   ·                                                                                                ▌  ·   ·   ·  NEXT ·   ·   ·   ·▐  ·    │      
                                                                                                                     ▌         you picked it         ▐       │      
                                                                                                                     ▌                               ▐       │      
·   ·   ·   ·   ·   ·                                                                     +                          ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·    │      
               +                                                                                                     ▌                               ▐       │      
                                                                                                                     ▌                               ▐       │      
·   ·   ·   ·   ·   ·                                                                                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·    │      
                                                                                                                     ▌                               ▐       │      
                                                                                                                     ▌                               ▐       │      
·   ·   ·   ·   ·   ·                                                                                                ▌  ·   ·   ·   ·   ·   ·   ·   ·▐  ·    │      
                                                                                                                     ▌                               ▐       │      
                                                                                                                     ▌                               ▐       │      
·· ··· ··· ··· ··· ··                                                                                                ▌▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▐ ··· · ┼ 8    
                                                                                                                                                             │      
                                                                                                                                                             │      
·   ·   ·   ·   ·   ·                                                                                                   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                                                                                                                             │      
                                                                                                                                                             │      
·   ·   ·   ·   ·   ·                                                                                                   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                                                                                                                             │      
                                                                                                                                                             │      
·   ·   ·   ·   ·   ·                                                                                                   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                                                                                                                             │      
                                                                                                                                                             │      
·   ·   ·   ·   ·   ·                                                                                                   ·   ·   ·   ·   ·   ·   ·   ·   ·    │      
                                                                                                                                                             │      
                                                                                                                                                             │      
·   ·   ·   ·   ·   ·                                                                                                   ·   ·   ·   ·   ·   ·   ·   ·   ·    ┼ 16   
                                                                                                                                                                    
                                                                                                                                                                    
·   ·   ·   ·   ·   ·                                                                                                   ·   ·   ·   ·   ·   ·   ·   ·   ·    ░░░░░░ 
                                                                                                                                                             ░░-░░░ 
                                                                                                                                                             ░░░░░░ 
·· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ··· ·        
                                                                                                                                                                    
                                                                                                                                                             ░░░░░░ 
·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·    ░FILL░ 
                                                                                                                                                             ░░░░░░ 
                                                                                                                                                                    
·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·   ·           
                                                                                                                                                                    
                                                                                                                                                                    
```

### Zoom bar (right 8 columns)

- `+` button at the top, `-` button under the track, `FILL` button under that.
- The track has one tick per zoom level (1, 2, 4, 8, 16). The current level is the white `█` marker. Tapping a tick jumps to that level. `+`/`-` step one level.
- On a shorter floor the ticks move closer together; `+`, `-` and FILL keep their 3-row size.

### Taps on the floor

- **Fill off (default):** tapping the map centres the view on that spot (on both screens). Nothing else: a tap on the floor can never send Seagull anywhere or queue a region.
- **FILL** toggles Fill. Saved in `cartographer.env` (`FLOOR_FILL=false`), so it survives a reboot.

### Fill on: a static map table

- The map fills the whole floor, including the 8 columns the zoom bar used. The zoom bar is hidden.
- The view fits everything explored (like FIT) and keeps fitting as the map grows.
- Taps on the map do nothing. The floor ignores pan and zoom from the computer; the computer keeps its own view meanwhile.
- Only the FILL button stays, floating over the bottom-right corner of the map, lit (`▓`, white background, black text) so it reads as "on". Tap it to turn Fill off: the zoom bar comes back and the floor takes the computer's current view again.

Bottom-right corner with Fill on (last 24 columns, last 6 rows; `~` is map):

```
~~~~~~~~~~~~~~~~ ▓▓▓▓▓▓ 
~~~~~~~~~~~~~~~~ ▓FILL▓ 
~~~~~~~~~~~~~~~~ ▓▓▓▓▓▓ 
~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~
~~~~~~~~~~~~~~~~~~~~~~~~
```

### Orientation

Monitors laid flat take their "up" from the way the player faced when placing them. The Cartographer reads that, so world north is drawn the way the floor faces, and a turtle walking north crosses the floor the same way.

## Computer (advanced computer, 51x19)

Example data.

```
 CARTOGRAPHER                   7 regions  mapping 
───────────────────────────────────────────────────
       ▌·●  ·  ▐·   ·   ·│ SEAGULL ─────────────── 
       ▌       ▐         │   Seagull-01    mapping 
       ▌       ▐         │   Region 0,-1  ring 1   
       ▌·   ·  ▐·   ·   ·│   Scan             ~40% 
       ▌+▄▄▄▄▄▄▐       ▌▀│   Fuel              72% 
      ●    ●           ▌ │   off radio 6m  60,-150 
                       ▌·│ NEXT ────────────────── 
                +      ▌ │  Region 2,0         you 
                       ▌ │  then -1,-2 (spiral)    
                       ▌▄│ STORAGE ─────────────── 
                         │  Disk               38% 
                         │  room for ~18 regions   
                        ·│                         
                         │                         
 MAP   DOCK   <   >   ^   v   -   +   FIT          
> /next 2,0                                        
 tap map: pick next   Key  type /help for commands 
```

- **Map (left, 23 columns):** a small copy of the view. Tap an unexplored region once to give it a white outline; the notice row says `Region 2,0: tap again to map it next`. A second tap on the same region within 4 s queues it (the kit's tap-twice rule). A tap on explored ground centres the view there.
- **SEAGULL:** label and state, the region he's on and its ring in the spiral, scan % (`~` while he's off the radio), fuel, how long since he was heard, last position.
- **NEXT:** the queued pick (`you`) or the next region in the spiral from home, then the one after.
- **STORAGE:** computer disk, then each floppy, and roughly how many more regions fit. Turns orange above 80%, red above 95%.
- **Buttons:** MAP sends Seagull to the next region; DOCK calls him home. `<` `>` `^` `v` pan by half a view, `-` `+` zoom, FIT shows everything explored and keeps following as it grows. These move the floor too, unless the floor is in Fill.
- **Keys:** arrows pan, `-` / `+` zoom, `f` fits.
- **Command row** (shared slash module, #70): `/map`, `/dock`, `/next X,Z`, `/next clear`, `/goto x z`, `/fit`, `/fill on|off`, `/storage`, `/status`, `/help`.
- **Key** (bottom row) opens the colour key full-screen, with Back.
- Header: gold `CARTOGRAPHER` chip, region count, Seagull's state.

## Not on the floor or computer

- The art wall loses its World map screen (#67).
- The mainframe board keeps one Cartographer row (Seagull's state and region count), as the art controller's world map row does today.
