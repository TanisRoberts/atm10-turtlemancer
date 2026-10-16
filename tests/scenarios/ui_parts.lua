-- UI kit part 3 (shared/ui_parts.lua): section, key-value, alert, switch, board, picker card, report page, spinner
-- line. The demo screen is tests/demo/ui_demo3.lua (screens: parts, board, picker, report, wait).
local cc  = require("sim.cc")
local T   = require("sim.test")
local ENV = require("sim.env")
local COL = ENV.colors

local SIZES = { { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }
local ESC, ENTER, TAB, PGDN = 256, 257, 258, 267
local LEFT, RIGHT, DOWN, UP, HOME, END = 263, 262, 264, 265, 268, 269

local function install(c)
  c:install("shared/ui.lua"); c:install("shared/ui_widgets.lua"); c:install("shared/ui_parts.lua"); c:install("shared/ui_motion.lua")
end
local function demo3(w, h, cfg, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, label = "Demo3", w = w, h = h, colour = opts.colour }
  local mon = opts.monitor and c:monitor("right", opts.monitor[1], opts.monitor[2])
  install(c); c:install("tests/demo/ui_demo3.lua")
  c:writeTable("demo3.cfg", cfg or {})
  c:run("ui_demo3")
  world:run(0.5)
  return world, c, mon
end
local function frame(w, h, body, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, w = w, h = h, colour = opts.colour }
  install(c)
  c:writeFile("t.lua", 'local ui = require("ui"); local v = ui.view(term.current()); _G.v = v; v:frame(function(v)\n' ..
    body .. '\nend); sleep(1000)')
  c:run("t"); world:run(0.5)
  T.running(c)
  return world, c
end

local function rowOf(scr, H, s) for y = 1, H do if scr:line(y):find(s, 1, true) then return y end end end
local function inRow(scr, y, s) return scr:line(y):find(s, 1, true) end
local function fg(scr, x, y) local f = scr:colourAt(x, y); return f end
local function bg(scr, x, y) local _, b = scr:colourAt(x, y); return b end
local function tap(world, c, x, y) c:click(x, y); world:run(0.2) end
local function key(world, c, code) c:key(code); world:run(0.2) end
local function d3(c) return c.env._G.d3 end

for _, s in ipairs(SIZES) do
  local W, H = s[1], s[2]

  T.test(("ui3: section, kv and alert at %dx%d"):format(W, H), function()
    local world, c = demo3(W, H, { screen = "parts" })
    local scr = c.screen
    T.eq(inRow(scr, 4, "LAYERS"), 2, "caps label at x")
    T.eq(fg(scr, 2, 4), COL.lightGrey, "label is dim")
    T.eq(scr.ch[4][W - 1], "\140", "rule runs to the right edge")
    T.eq(fg(scr, W - 1, 4), COL.grey, "rule is grey")
    T.eq(scr.ch[4][W], " ", "and stops one column short of the edge")
    -- kv: key at the left (dim), value ends at W-1; the value is cut last
    if W >= 39 then T.eq(inRow(scr, 5, "Plan"), 2); T.eq(fg(scr, 2, 5), COL.lightGrey) end
    T.eq(scr:line(5):gsub("%s+$", ""):len(), W - 1, "value ends at the right edge")
    T.eq(fg(scr, W - 1, 5), COL.white, "plain value is white")
    T.eq(fg(scr, W - 1, 6), COL.lime, "toned value takes the tone")
    if W >= 39 then
      T.truthy(inRow(scr, 6, ".."), "a key too long for the row is cut with ..")
      T.truthy(inRow(scr, 6, "none (storage has it all)"), "the value is whole")
    else
      T.truthy(inRow(scr, 6, "none (storage"), "narrow: the value stays, the key goes")
    end
    -- alerts: stripe, text in the tone
    T.eq(bg(scr, 2, 7), COL.orange, "orange stripe"); T.eq(fg(scr, 4, 7), COL.orange, "orange text")
    T.eq(bg(scr, 2, 8), COL.red, "red stripe"); T.eq(fg(scr, 4, 8), COL.red)
    T.eq(bg(scr, 3, 7), COL.black, "the stripe is one cell")
  end)

  T.test(("ui3: switch at %dx%d: taps, cursor keys, wrap, squeeze"):format(W, H), function()
    local world, c = demo3(W, H, { screen = "parts" })
    local scr = c.screen
    local y = rowOf(scr, H, "AUTO")
    local ax = inRow(scr, y, "AUTO")
    T.eq(bg(scr, ax, y), COL.yellow, "current is gold"); T.eq(fg(scr, ax, y), COL.black)
    local ox = inRow(scr, y, "ON")
    T.eq(bg(scr, ox, y), COL.grey, "others are grey")
    T.eq(ox, ax + #"AUTO" + 2, "segments touch")
    tap(world, c, ox, y)
    T.eq(d3(c).mode, "ON"); T.eq(bg(scr, ox, y), COL.yellow, "the tapped segment is now gold")
    T.eq(bg(scr, ax, y), COL.grey)
    tap(world, c, inRow(scr, y, "OFF") + 1, y); T.eq(d3(c).mode, "OFF")
    -- keys: Tab to the first switch, Right moves a cursor without picking, Enter picks, Left wraps
    key(world, c, TAB)
    key(world, c, RIGHT)
    T.eq(d3(c).mode, "OFF", "moving the cursor does not pick")
    T.eq(bg(scr, ax, y), COL.lightGrey, "the cursor segment shows")
    key(world, c, ENTER); T.eq(d3(c).mode, "AUTO", "Enter picks the cursor (wrapped from OFF to AUTO)")
    key(world, c, LEFT); key(world, c, ENTER); T.eq(d3(c).mode, "OFF", "Left wraps to the end")
    key(world, c, ESC)
    -- the second switch: long labels when they fit, short ones when not
    local y2 = rowOf(scr, H, "None") or rowOf(scr, H, "No rule")
    if W <= 30 then
      T.truthy(inRow(scr, y2, "None") and inRow(scr, y2, "Keep") and inRow(scr, y2, "All"), "short labels at 26")
      T.absent(scr:line(y2), "Keep N", "not the long ones")
    else
      T.truthy(inRow(scr, y2, "No rule") and inRow(scr, y2, "Keep N stacks") and inRow(scr, y2, "Smelt all"))
    end
    local kx = inRow(scr, y2, "Keep")
    tap(world, c, kx + 1, y2); T.eq(d3(c).rule, "keep")
    T.eq(bg(scr, kx, y2), COL.yellow)
    T.eq(bg(scr, inRow(scr, y2, "No") or inRow(scr, y2, "None"), y2), COL.grey)
  end)

  T.test(("ui3: board at %dx%d: stripe, glyph, state, detail, age, grey after 30 s"):format(W, H), function()
    local world, c = demo3(W, H, { screen = "board" })
    local scr = c.screen
    T.eq(bg(scr, 2, 4), COL.grey, "header bar"); T.eq(bg(scr, W - 1, 4), COL.grey, "to the right edge")
    T.eq(inRow(scr, 4, "MACHINES"), 3); T.eq(fg(scr, 3, 4), COL.yellow, "gold caps label")
    T.eq(bg(scr, 2, 5), COL.lime, "ok stripe is lime"); T.eq(bg(scr, 2, 6), COL.lime)
    T.eq(inRow(scr, 5, "Storage"), 4); T.eq(fg(scr, 4, 5), COL.white)
    T.truthy(inRow(scr, 5, "ok"))
    local g = inRow(scr, 5, "ok") - 2
    T.eq(scr.ch[5][g], "+", "a glyph slot before the state word"); T.eq(fg(scr, g, 5), COL.lime)
    T.truthy(inRow(scr, 7, "running"))
    if W >= 39 then T.truthy(inRow(scr, 5, "79% full"), "detail"); T.truthy(inRow(scr, 7, "1,204 made"))
    else T.absent(scr:line(5), "79%", "narrow: no detail") end
    T.eq(scr:line(5):gsub("%s+$", ""):len(), W - 1, "age ends at the right edge")
    T.eq(scr:line(5):sub(W - 2, W - 1), "2s")
    -- the Neural row is 45 s old: grey stripe, dim text, still "?" glyph
    T.eq(bg(scr, 2, 8), COL.grey, "stale stripe is grey"); T.eq(fg(scr, 4, 8), COL.lightGrey, "name is dim")
    T.eq(scr:line(8):sub(W - 3, W - 1), "45s")
    T.eq(scr.ch[8][inRow(scr, 8, "ok") - 2], "?", "still grey glyph")
    -- a row ages past 30 s while the board is up
    d3(c).ages[1] = 31; world:run(1.2)
    T.eq(bg(scr, 2, 5), COL.grey, "now grey"); T.eq(fg(scr, 4, 5), COL.lightGrey)
    -- read only: a tap does nothing
    tap(world, c, 6, 6); T.eq(d3(c).picked, nil)
  end)

  T.test(("ui3: picker at %dx%d: card, neighbours, counter, keys, wrap, click"):format(W, H), function()
    local world, c = demo3(W, H, { screen = "picker" })
    local scr = c.screen
    local y2 = H - 1
    T.eq(inRow(scr, 3, "Which role?"), 2)
    T.eq(scr:line(3):sub(W - 6, W - 1), "2 of 3", "counter at the right")
    T.truthy(inRow(scr, 4, "^ Foreman"), "previous peeks above"); T.truthy(inRow(scr, y2, "v Storage"), "next peeks below")
    T.eq(fg(scr, 2, 4), COL.lightGrey, "neighbours are dim")
    T.eq(bg(scr, 2, 5), COL.yellow, "card title bar is gold"); T.eq(bg(scr, W - 1, 5), COL.yellow)
    T.truthy(inRow(scr, 5, "MAINFRAME")); T.truthy(inRow(scr, 5, "suggested"), "tag at the right")
    T.eq(bg(scr, 2, 6), COL.yellow, "body stripe"); T.truthy(inRow(scr, 6, "The server"), "body text")
    T.truthy(inRow(scr, H, "Pick >"), "Pick button in the footer row")
    if W >= 39 then T.truthy(inRow(scr, H, "up/down browse"), "hint") end
    -- keys
    key(world, c, DOWN)
    T.eq(d3(c).moved, "storage"); T.truthy(inRow(scr, 5, "STORAGE")); T.truthy(inRow(scr, 3, "3 of 3") or inRow(scr, 3, "3 of"))
    key(world, c, DOWN); T.eq(d3(c).moved, "foreman", "wraps from the last to the first")
    key(world, c, UP); T.eq(d3(c).moved, "storage", "and back")
    key(world, c, HOME); T.truthy(inRow(scr, 5, "FOREMAN"))
    key(world, c, END); T.truthy(inRow(scr, 5, "STORAGE"))
    c:type("2"); world:run(0.2); T.truthy(inRow(scr, 5, "MAINFRAME"), "number key jumps")
    c:scroll(1); world:run(0.2); T.truthy(inRow(scr, 5, "STORAGE"), "wheel down")
    c:scroll(-1); world:run(0.2); T.truthy(inRow(scr, 5, "MAINFRAME"), "wheel up")
    -- click a neighbour
    tap(world, c, 6, y2); T.truthy(inRow(scr, 5, "STORAGE"), "click on the next one moves to it")
    tap(world, c, 6, 4); T.truthy(inRow(scr, 5, "MAINFRAME"), "click on the previous one")
    T.eq(d3(c).picked, nil, "none of that picked")
    -- Enter picks (nothing focused); the Pick button picks too
    key(world, c, ENTER); T.eq(d3(c).picked, "mainframe")
    d3(c).picked = nil; key(world, c, DOWN)
    tap(world, c, inRow(scr, H, "Pick >") + 1, H); T.eq(d3(c).picked, "storage")
    -- Back is focusable and Enter on it goes back instead of picking
    d3(c).picked = nil
    key(world, c, TAB); key(world, c, ENTER)
    T.eq(d3(c).backs, 1); T.eq(d3(c).picked, nil, "Enter on a focused Back does not pick")
  end)

  T.test(("ui3: report page at %dx%d: sections, rows, alert, pager"):format(W, H), function()
    local world, c = demo3(W, H, { screen = "report" })
    local scr = c.screen
    T.eq(inRow(scr, 3, "PLAN"), 2); T.truthy(inRow(scr, 4, "Plan")); T.truthy(inRow(scr, 5, "Missing"))
    T.eq(scr:line(6):gsub("%s+", ""), "", "a blank row above the second section")
    T.eq(inRow(scr, 7, "LINKS"), 2)
    T.eq(fg(scr, W - 1, 8), COL.orange, "toned value"); T.eq(bg(scr, 2, 9), COL.orange, "alert stripe")
    T.truthy(inRow(scr, H, "<"), "Back")
    tap(world, c, 2, H); T.eq(d3(c).backs, 1)
    T.absent(scr:line(H), "1/", "no pager when it fits")
    local w2, c2 = demo3(W, H, { screen = "report", extra = 30 })
    T.truthy(inRow(c2.screen, H, "1/"), "pager when it does not fit")
    key(w2, c2, PGDN)
    T.truthy(inRow(c2.screen, H, "2/"), "PgDn turns the page")
    T.eq(c2.screen:line(3):find("PLAN", 1, true), nil, "page 2 starts further on")
  end)

  T.test(("ui3: spinner line at %dx%d: the waiting glyph steps on the beat"):format(W, H), function()
    local world, c = demo3(W, H, { screen = "wait" })
    local scr = c.screen
    T.truthy(inRow(scr, 5, "Waiting for storage"))
    local seen = {}
    for _ = 1, 8 do
      seen[scr.ch[5][4]] = true; T.eq(fg(scr, 4, 5), COL.orange, "waiting is orange")
      world:run(0.25)
    end
    local n = 0; for _ in pairs(seen) do n = n + 1 end
    T.truthy(n >= 3, "the glyph changes between beats")
    for g in pairs(seen) do T.truthy(g == "." or g == "o" or g == "O", "frames are . o O") end
  end)
end

T.test("ui3: switch wraps to a second row when even the short labels do not fit; returns its end", function()
  local world = cc.world()
  local c = world:computer{ id = 1, w = 26, h = 8 }
  install(c)
  c:writeFile("t.lua", [[
    local ui = require("ui")
    ui.run(ui.view(term.current()), function(v)
      _G.r = { v:switch(2, 3, { { id = "a", label = "Smelt everything" }, { id = "b", label = "Keep N stacks" },
                               { id = "c", label = "No rule" } }, "b", function(id) _G.picked = id end) }
    end)]])
  c:run("t"); world:run(0.5)
  local scr = c.screen
  T.truthy(inRow(scr, 3, "Smelt everything")); T.truthy(inRow(scr, 4, "Keep N stacks"), "the next one starts a new row")
  T.truthy(inRow(scr, 4, "No rule"), "and the next one fits beside it")
  T.absent(scr:line(5), "No rule")
  T.eq(c.env._G.r[2], 4, "returns the last row")
  T.eq(bg(scr, 3, 4), COL.yellow, "current is gold on the second row")
  tap(world, c, 4, 3); T.eq(c.env._G.picked, "a", "a tap on the first row")
  tap(world, c, 20, 4); T.eq(c.env._G.picked, "c", "and beside it")
end)

T.test("ui3: kv cuts the key first and the value last; alert and section clip to their width", function()
  local world, c = frame(30, 8, [[
    v:kv(2, 3, 20, "A long key here", "value", nil)
    v:kv(2, 4, 10, "Key", "a very long value indeed", nil)
    v:section(2, 5, 12, "Something much longer")
    v:alert(2, 6, 12, "A very long alert message", "bad")
  ]])
  local scr = c.screen
  T.truthy(inRow(scr, 3, "A long key"), "room for most of the key"); T.eq(scr:line(3):sub(17, 21), "value")
  T.eq(scr:line(4):sub(2, 11), "a very l..", "value cut, key dropped")
  T.eq(scr:line(5):sub(2, 11), "SOMETHIN..", "label cut with ..")
  T.eq(scr:line(6):sub(4, 13), "A very l..", "alert text cut")
  T.eq(scr.ch[6][14], " ", "and nothing past the width")
end)

T.test("ui3: without colour: ! stripe, [current] switch, - rule, | board stripe, [TITLE] card", function()
  local world, c = demo3(51, 19, { screen = "parts" }, { colour = false })
  local scr = c.screen
  T.eq(scr.ch[7][2], "!", "alert marker"); T.truthy(inRow(scr, 4, "LAYERS -"), "ascii rule")
  T.truthy(inRow(scr, rowOf(scr, 19, "AUTO"), "[AUTO]"), "current segment in brackets")
  T.truthy(rowOf(scr, 19, "ON") and not rowOf(scr, 19, "[ON]"))
  local w2, c2 = demo3(51, 19, { screen = "board" }, { colour = false })
  T.eq(c2.screen.ch[5][2], "|", "board stripe is a bar"); T.eq(c2.screen.ch[8][2], "?", "stale is a ?")
  T.truthy(inRow(c2.screen, 4, "MACHINES")); T.eq(c2.screen.ch[5][2], "|")
  local w3, c3 = demo3(51, 19, { screen = "picker" }, { colour = false })
  T.truthy(inRow(c3.screen, 5, "[MAINFRAME]"), "title in brackets"); T.eq(c3.screen.ch[6][2], "|")
  key(w3, c3, DOWN); T.truthy(inRow(c3.screen, 5, "[STORAGE]"))
  local w4, c4 = demo3(51, 19, { screen = "wait" }, { colour = false })
  T.eq(c4.screen.ch[5][4], ".", "still glyph without colour")
  local w5, c5 = frame(40, 6, [[ ui.anim = "off"; v:spinner_line(2, 3, "x"); _G.an = v.animated ]])
  T.eq(c5.env._G.an, nil, "ANIM=off: still, not animated")
  local w6, c6 = frame(40, 6, [[ v:spinner_line(2, 3, "x"); _G.an = v.animated ]])
  T.eq(c6.env._G.an, true, "a spinner marks the view as animated")
end)

T.test("ui3: a monitor view picks with a touch and has no keys", function()
  local world, c, mon = demo3(51, 19, { screen = "picker" }, { monitor = { 39, 13 } })
  T.truthy(inRow(mon, 5, "MAINFRAME"))
  mon:touch(39 - 8 + 1, 13); world:run(0.2)
  T.eq(d3(c).picked, "mainframe", "touch on Pick > on the monitor")
  mon:touch(6, 12); world:run(0.2)
  T.truthy(inRow(mon, 5, "STORAGE"), "touch a neighbour"); T.truthy(inRow(c.screen, 5, "STORAGE") ~= nil, "both views share the picker")
end)
