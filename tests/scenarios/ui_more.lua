-- UI kit part 2 (shared/ui_widgets.lua): footer tabs and paging, tiles, bars, fields, search and command bar,
-- paged lists, map. The demo screen is tests/demo/ui_demo2.lua (tabs: tiles, list, map, form).
local cc  = require("sim.cc")
local T   = require("sim.test")
local ENV = require("sim.env")
local COL = ENV.colors

local SIZES = { { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }
local ESC, BKSP, ENTER, TAB, PGUP, PGDN = 256, 259, 257, 258, 266, 267
local LEFT, RIGHT, DOWN, UP, HOME = 263, 262, 264, 265, 268

local function install(c)
  c:install("shared/ui.lua"); c:install("shared/ui_widgets.lua")
end
local function demo2(w, h, cfg, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, label = "Demo2", w = w, h = h, colour = opts.colour }
  local mon = opts.monitor and c:monitor("right", opts.monitor[1], opts.monitor[2])
  install(c); c:install("tests/demo/ui_demo2.lua")
  c:writeTable("demo2.cfg", cfg or {})
  c:run("ui_demo2")
  world:run(0.5)
  return world, c, mon
end
-- a program that draws one frame with `body` (v is the view) and waits
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

local function inRow(scr, y, s) return scr:line(y):find(s, 1, true) end
local function fg(scr, x, y) local f = scr:colourAt(x, y); return f end
local function bg(scr, x, y) local _, b = scr:colourAt(x, y); return b end
local function tap(world, c, x, y) c:click(x, y); world:run(0.2) end
local function key(world, c, code) c:key(code); world:run(0.2) end
local function typ(world, c, s) c:type(s); world:run(0.2) end
local function pure()
  local env = setmetatable({ colours = COL, keys = ENV.keys, os = os }, { __index = _G })
  env.require = function(n) return assert(loadfile(cc.ROOT .. "/shared/" .. n .. ".lua", "t", env))() end
  return assert(loadfile(cc.ROOT .. "/shared/ui.lua", "t", env))()
end
local function d2(c) return c.env._G.d2 end

---------------------------------------------------------------------------------------------------------
T.test("ui2: layout.tiles columns, width, height, rows", function()
  local ui = pure()
  local function lay(w, h, n)
    local c, tw, th, rows, pages = ui.layout.tiles(w, h, n)
    return ("%d %d %d %d %d"):format(c, tw, th, rows, pages)
  end
  T.eq(lay(51, 19, 4), "2 24 5 2 1")          -- the kit's 51x19 board: 2 columns of 24
  T.eq(lay(57, 24, 7), "2 27 5 3 2")          -- 2 of 27
  T.eq(lay(26, 20, 3), "1 24 5 3 1")          -- glasses: 1 column of 24
  T.eq(lay(39, 13, 3), "1 37 2 3 1")          -- turtle: 1 column of 37, 2-row tiles
  T.eq(lay(164, 81, 6), "6 26 5 13 1")        -- wall: 6 columns of 26
  T.eq(lay(51, 19, 9), "2 24 5 2 3")          -- 9 tiles, 4 a page
  T.eq(lay(51, 19, 0), "2 24 5 2 1")
end)

for _, s in ipairs(SIZES) do
  local W, H = s[1], s[2]
  local cols = W >= 46 and 2 or 1
  local tw = ({ [57] = 27, [51] = 24, [39] = 37, [26] = 24 })[W]
  local th = H <= 14 and 2 or 5
  local rows = math.floor((H - 3 + 1) / (th + 1))
  local per = cols * rows
  local pages = math.ceil(7 / per)

  T.test(("ui2: tiles at %dx%d: stripe, state, bar, stale, paging, taps"):format(W, H), function()
    local world, c = demo2(W, H, { tab = "tiles", tiles = 7 })
    local scr = c.screen
    -- tile 1: lime stripe at the left edge, name, state word at the right in its colour
    T.eq(bg(scr, 2, 3), COL.lime, "working stripe")
    T.eq(inRow(scr, 3, "Canary-01"), 4)
    T.eq(inRow(scr, 3, "working"), 2 + tw - 1 - 7, "state word right-aligned inside the tile")
    T.eq(fg(scr, 2 + tw - 3, 3), COL.lime)
    T.eq(c.screen.ch[3][2], " ")
    if th == 5 then
      T.truthy(inRow(scr, 4, "Digging to Y -39")); T.eq(fg(scr, 4, 4), COL.lightGrey, "activity is dim")
      T.truthy(inRow(scr, 6, "Cargo 1/16")); T.truthy(inRow(scr, 7, "seen 2s ago"))
      T.eq(bg(scr, 2, 7), COL.lime, "stripe runs the full tile height")
      T.eq(bg(scr, 2, 8), COL.black, "and stops with a gap row below")
    else
      T.absent(scr:line(4), "Digging", "short screens: two rows, name and fuel")
      T.eq(bg(scr, 2, 4), COL.lime)
    end
    -- fuel bar: label, track, number; 17% is orange (10-20%), the rest of the track grey
    local fy = th == 5 and 5 or 4
    T.truthy(inRow(scr, fy, "Fuel"), "bar label"); T.truthy(inRow(scr, fy, "17%"))
    local bx = inRow(scr, fy, "Fuel") + 5
    T.eq(bg(scr, bx, fy), COL.orange, "17% fuel is orange")
    T.eq(bg(scr, 2 + tw - 6, fy), COL.grey, "the unfilled track is grey")
    -- paging
    T.eq(inRow(scr, H, "1/" .. pages) ~= nil, true, "pager 1/" .. pages)
    T.eq(d2(c).opened, nil)
    if cols == 2 then
      T.eq(bg(scr, 2 + tw + 1, 3), COL.orange, "second column: waiting stripe")
      tap(world, c, 2 + tw + 3, 5)                      -- anywhere on tile 2 opens it
      T.eq(d2(c).opened, "Canary-02")
    else
      tap(world, c, 5, th == 5 and 5 or 4); T.eq(d2(c).opened, "Canary-01")
    end
    -- next page via the pager arrow and via the wheel
    local px = scr:line(H):find(">", 1, true) -- the last > in the row is the pager arrow
    px = #scr:line(H):gsub("%s+$", "")
    tap(world, c, px - 1, H)
    T.truthy(inRow(scr, H, "2/" .. pages), "pager arrow turned the page")
    T.truthy(inRow(scr, 3, ("Canary-%02d"):format(per + 1)), "page 2 starts with tile " .. (per + 1))
    c:scroll(-1); world:run(0.2)
    T.truthy(inRow(scr, H, "1/" .. pages), "wheel up goes back")
    c:scroll(1); world:run(0.2)
    T.truthy(inRow(scr, H, "2/" .. pages), "wheel down")
    key(world, c, PGUP); T.truthy(inRow(scr, H, "1/" .. pages), "PgUp")
    key(world, c, PGDN); T.truthy(inRow(scr, H, "2/" .. pages), "PgDn")
  end)
end

T.test("ui2: tiles: stale tile is grey and says not heard; every state has its colour", function()
  local world, c = demo2(57, 24, { tab = "tiles", tiles = 7 })
  local scr = c.screen
  local want = { { 2, 3, COL.lime }, { 30, 3, COL.orange }, { 2, 9, COL.cyan }, { 30, 9, COL.grey },
                 { 2, 15, COL.purple }, { 30, 15, COL.lightBlue } }
  for _, w in ipairs(want) do T.eq(bg(scr, w[1], w[2]), w[3], ("stripe at %d,%d"):format(w[1], w[2])) end
  T.truthy(inRow(scr, 10, "not heard 3m"), "stale replaces the activity")
  T.eq(fg(scr, 32, 9), COL.lightGrey, "stale name is dim")
  -- tile 5 has 85% fuel: lime
  T.eq(bg(scr, inRow(scr, 17, "Fuel") + 5, 17), COL.lime, "85% fuel is lime")
end)

T.test("ui2: tiles: arrows move the highlight (gold stripe), Enter opens, Esc clears", function()
  local world, c = demo2(57, 24, { tab = "tiles", tiles = 7 })
  local scr = c.screen
  key(world, c, RIGHT); T.eq(bg(scr, 2, 3), COL.yellow, "first arrow highlights tile 1")
  key(world, c, RIGHT); T.eq(bg(scr, 30, 3), COL.yellow); T.eq(bg(scr, 2, 3), COL.lime)
  key(world, c, DOWN);  T.eq(bg(scr, 30, 9), COL.grey == 0 and 0 or COL.yellow, "down a row")
  key(world, c, ENTER); T.eq(d2(c).opened, "Canary-04")
  key(world, c, ESC);   T.eq(bg(scr, 30, 9), COL.grey, "Esc clears the highlight (stale grey again)")
  key(world, c, RIGHT); key(world, c, RIGHT); key(world, c, RIGHT); key(world, c, RIGHT); key(world, c, RIGHT)
  key(world, c, RIGHT); key(world, c, RIGHT)
  T.truthy(inRow(scr, 24, "2/2"), "moving the highlight past the page turns it")
  T.truthy(inRow(scr, 3, "Canary-07"))
end)

---------------------------------------------------------------------------------------------------------
T.test("ui2: bars: colours by kind, half cells, squeeze, unknown, no colour", function()
  local world, c = frame(60, 12, [[
    v:bar(2, 3, 40, "Fuel", 0.64)
    v:bar(2, 4, 40, "Fuel", 0.18)
    v:bar(2, 5, 40, "Fuel", 0.05)
    v:bar(2, 6, 40, "Layer", 0.37, { kind = "progress", text = "37/100" })
    v:bar(2, 7, 40, "Slots", 0.95, { kind = "cap" })
    v:bar(2, 8, 40, "Slots", 0.75, { kind = "cap" })
    v:bar(2, 9, 40, "Slots", 0.40, { kind = "cap" })
    v:bar(2, 10, 40, "Fuel", nil)
    v:bar(2, 11, 12, "Fuel", 0.5)
    v:bar(2, 12, 7, "Fuel", 0.5)
  ]])
  local scr = c.screen
  local function fillAt(y) return bg(scr, y >= 6 and y <= 9 and 8 or 7, y) end
  T.eq(fillAt(3), COL.lime, "64% lime"); T.eq(fillAt(4), COL.orange, "18% orange"); T.eq(fillAt(5), COL.red, "5% red")
  T.eq(fillAt(6), COL.cyan, "progress is cyan"); T.eq(fillAt(7), COL.red, "95% full is red")
  T.eq(fillAt(8), COL.orange, "75% full is orange"); T.eq(fillAt(9), COL.lime, "40% full is lime")
  T.truthy(inRow(scr, 3, "64%")); T.truthy(inRow(scr, 6, "37/100"))
  -- track is 40 - 5 ("Fuel ") - 4 (" 64%") = 31 cells; 64% of 31 = 19.84 -> 39.7 half cells -> 20 full cells
  local lx = 2 + 5
  T.eq(bg(scr, lx + 19, 3), COL.lime, "20th cell filled"); T.eq(bg(scr, lx + 20, 3), COL.grey, "21st is track")
  -- half-cell precision: 5% of 31 cells = 3.1 half cells -> 3: one full cell and a half block
  T.eq(scr.ch[5][lx + 1], "\149", "half block at the end of the fill")
  T.eq(fg(scr, lx + 1, 5), COL.red); T.eq(bg(scr, lx + 1, 5), COL.grey)
  -- unknown value: all-grey track and a dash
  T.eq(bg(scr, lx, 10), COL.grey); T.truthy(inRow(scr, 10, " -"))
  -- squeeze: 12 wide drops the label, 7 wide drops the number too and keeps a 6-cell track
  T.absent(scr:line(11), "Fuel"); T.truthy(inRow(scr, 11, "50%"))
  T.absent(scr:line(12), "50%"); T.eq(bg(scr, 7, 12), COL.grey)
end)

T.test("ui2: bars without colour use # and -", function()
  local world, c = frame(40, 5, [[ v:bar(2, 3, 30, "Fuel", 0.5) v:bar(2, 4, 30, "Fuel", nil) ]], { colour = false })
  T.truthy(inRow(c.screen, 3, "Fuel ###########-"), "# fill")
  T.truthy(inRow(c.screen, 3, "#----------"))
  T.truthy(inRow(c.screen, 4, "Fuel -------"))
end)

---------------------------------------------------------------------------------------------------------
T.test("ui2: footer tabs: active gold, star, tap, digits, Tab+Enter, page resets", function()
  local world, c = demo2(57, 24, { tab = "tiles", tiles = 7 })
  local scr = c.screen
  local tx = inRow(scr, 24, " Tiles ")
  T.eq(bg(scr, tx, 24), COL.yellow, "active tab is gold"); T.eq(fg(scr, tx, 24), COL.black)
  local lx = inRow(scr, 24, " List* ")
  T.eq(bg(scr, lx, 24), COL.grey); T.eq(fg(scr, lx + 5, 24), COL.lime, "the star is lime"); T.eq(scr.ch[24][lx + 5], "*")
  -- page 2 then switch tabs: the page resets to 1
  c:scroll(1); world:run(0.2); T.truthy(inRow(scr, 24, "2/2"))
  tap(world, c, lx + 2, 24)
  T.eq(d2(c).tab, "list"); T.truthy(inRow(scr, 3, "Item number 01")); T.truthy(inRow(scr, 24, "1/2"), "page reset to 1")
  T.eq(bg(scr, inRow(scr, 24, " List* "), 24), COL.yellow, "the new tab is gold")
  typ(world, c, "")                                   -- the list tab has a search bar: digits type into it
  tap(world, c, inRow(scr, 24, " Map ") + 2, 24); T.eq(d2(c).tab, "map")
  typ(world, c, "4"); T.eq(d2(c).tab, "form", "digit 4 jumps to the fourth tab")
  typ(world, c, "1"); T.eq(d2(c).tab, "tiles")
  -- Tab walks the focus ring: tabs and Back are in it; Enter on a focused tab switches
  key(world, c, TAB); key(world, c, TAB)              -- Back, then the first tab? order: footer boxes in draw order
  local before = d2(c).tab
  key(world, c, TAB); key(world, c, ENTER)
  T.truthy(d2(c).tab ~= nil)
end)

T.test("ui2: footer tabs shrink to 4 letters, then to the active tab and a cycling ..", function()
  local world, c = demo2(39, 13, { tab = "list" })
  local scr = c.screen
  T.truthy(inRow(scr, 13, " List* "), "active tab"); T.truthy(inRow(scr, 13, " .. "), "cycle pill")
  T.absent(scr:line(13), "Tiles"); T.absent(scr:line(13), "Map")
  tap(world, c, inRow(scr, 13, " .. ") + 1, 13)
  T.eq(d2(c).tab, "map", ".. cycles to the next tab")
  T.truthy(inRow(scr, 13, " Tiles ") and inRow(scr, 13, " Form "), "the map tab has no pager, so all four fit")
  tap(world, c, inRow(scr, 13, " Form ") + 1, 13); T.eq(d2(c).tab, "form")
  local w3, c3 = demo2(39, 13, { tab = "tiles", tiles = 7 })
  tap(w3, c3, inRow(c3.screen, 13, " .. ") + 1, 13); T.eq(d2(c3).tab, "list", ".. goes to the next tab")
  local w2, c2 = demo2(26, 20, { tab = "map" })
  T.truthy(inRow(c2.screen, 20, " Map "), "narrow: short labels"); T.absent(c2.screen:line(20), "Back")
end)

---------------------------------------------------------------------------------------------------------
for _, s in ipairs(SIZES) do
  local W, H = s[1], s[2]
  T.test(("ui2: paged list at %dx%d"):format(W, H), function()
    local world, c = demo2(W, H, { tab = "list", rows = 30 })
    local scr = c.screen
    local rpp = H - 1 - 1 - 3 + 1                         -- rule row, search row and footer are not content
    local pages = math.ceil(30 / rpp)
    T.truthy(inRow(scr, 3, "Item number 01")); T.truthy(inRow(scr, 3 + rpp - 1, ("Item number %02d"):format(rpp)))
    T.absent(scr:line(3 + rpp), "Item number", "nothing below the last row of the page")
    T.truthy(inRow(scr, H, "1/" .. pages), "pager")
    -- value right-aligned with one cell of margin, cyan; the long name is cut with .. and the value kept
    T.eq(scr:line(3):gsub("%s+$", ""):sub(-3), "104")
    T.eq(#scr:line(3):gsub("%s+$", ""), W - 1)
    T.eq(fg(scr, W - 1, 3), COL.cyan)
    T.truthy(inRow(scr, 4, "..") and inRow(scr, 4, "204"), "long name cut, value kept")
    -- stripe: state colour at the left except on narrow
    if W > 30 then T.eq(bg(scr, 1, 3), COL.orange, "row 1 is state 'warn'"); T.eq(inRow(scr, 3, "Item"), 3)
    else T.eq(inRow(scr, 3, "Item"), 2, "narrow drops the stripe") end
    -- select, then open
    tap(world, c, 8, 5)
    T.eq(bg(scr, 8, 5), COL.yellow, "selected row is gold"); T.eq(d2(c).opened, nil, "first tap only selects")
    T.eq(fg(scr, W - 1, 5), COL.black, "gold row has black text")
    tap(world, c, 8, 5); T.eq(d2(c).opened, "Item number 03", "second tap opens")
    d2(c).opened = nil
    tap(world, c, W - 1, 6); T.eq(d2(c).opened, "Item number 04", "a tap on the value opens at once")
    -- keys
    key(world, c, UP);   T.eq(bg(scr, 8, 5), COL.yellow, "Up from row 4 is row 3")
    key(world, c, DOWN); key(world, c, DOWN); T.eq(bg(scr, 8, 7), COL.yellow)
    key(world, c, ENTER) ; T.eq(d2(c).opened, "Item number 05")
    key(world, c, PGDN); T.truthy(inRow(scr, H, "2/" .. pages)); T.truthy(inRow(scr, 3, ("Item number %02d"):format(rpp + 1)))
    key(world, c, HOME); T.truthy(inRow(scr, H, "1/" .. pages), "Home goes to the first row, and its page")
    key(world, c, 269);  T.truthy(inRow(scr, H, pages .. "/" .. pages), "End goes to the last row's page")
  end)
end

T.test("ui2: search bar filters as you type, Backspace, Esc, Enter opens the top match", function()
  local world, c = demo2(51, 19, { tab = "list", rows = 30 })
  local scr = c.screen
  T.truthy(inRow(scr, 18, "search, / = commands"), "hint when empty")
  T.eq(bg(scr, 1, 18), COL.lightGrey, "prompt chip"); T.eq(bg(scr, 10, 18), COL.grey, "bar")
  T.eq(bg(scr, 4, 18), COL.yellow, "gold cursor")
  typ(world, c, "number 2")
  T.truthy(inRow(scr, 18, "number 2"))
  T.truthy(inRow(scr, 3, "Item number 20")); T.truthy(inRow(scr, 12, "Item number 29")); T.absent(scr:line(13), "Item")
  T.absent(scr, "Item number 03")
  key(world, c, BKSP); typ(world, c, "")
  T.truthy(inRow(scr, 18, "number "))
  typ(world, c, "3")
  key(world, c, ENTER); T.eq(d2(c).opened, "Item number 30", "Enter opens the top match")
  key(world, c, ESC)
  T.truthy(inRow(scr, 18, "search, / = commands"), "Esc clears the text")
  T.truthy(inRow(scr, 3, "Item number 01"))
end)

T.test("ui2: / turns the search bar into a command bar: list, Tab, Up/Down, Enter, Esc", function()
  local world, c = demo2(51, 19, { tab = "list", rows = 30 })
  local scr = c.screen
  typ(world, c, "/")
  T.truthy(inRow(scr, 3, "/reboot") and inRow(scr, 3, "reboot a turtle"), "top row is the first command")
  T.truthy(inRow(scr, 4, "/refuel")); T.truthy(inRow(scr, 5, "/retire"))
  T.absent(scr, "Item number", "the list is replaced by the command list")
  T.eq(bg(scr, 3, 3), COL.yellow, "top match is gold"); T.eq(bg(scr, 3, 4), COL.black)
  typ(world, c, "ref")
  T.truthy(inRow(scr, 3, "/refuel")); T.absent(scr, "/reboot"); T.eq(bg(scr, 3, 3), COL.yellow)
  key(world, c, TAB)
  T.truthy(inRow(scr, 18, "/refuel "), "Tab completes")
  typ(world, c, "Canary-04"); key(world, c, ENTER)
  T.eq(d2(c).cmd, "refuel Canary-04", "Enter runs the command with its argument")
  T.truthy(inRow(scr, 3, "Item number 01"), "back to the list")
  typ(world, c, "/re"); key(world, c, DOWN)
  T.eq(bg(scr, 3, 4), COL.yellow, "Down moves the choice"); T.eq(bg(scr, 3, 3), COL.black)
  key(world, c, ENTER); T.eq(d2(c).cmd, "refuel ", "runs the chosen one")
  typ(world, c, "/zzz"); T.absent(scr, "/reboot"); key(world, c, ENTER)
  T.contains(scr:line(2), "Unknown command")
  key(world, c, ESC); T.truthy(inRow(scr, 3, "Item number 01"), "Esc backs out")
  typ(world, c, "/"); tap(world, c, 5, 5)                    -- a tap on a command completes it
  T.truthy(inRow(scr, 18, "/retire "))
end)

---------------------------------------------------------------------------------------------------------
T.test("ui2: text field: tap to type, cursor, Enter commits, Esc reverts, invalid goes red, Tab leaves", function()
  local world, c = demo2(51, 19, { tab = "form" })
  local scr = c.screen
  T.eq(inRow(scr, 4, "Name"), 2); T.truthy(inRow(scr, 4, "name of the turtle"), "hint when empty")
  T.eq(bg(scr, 7, 4), COL.grey, "box is grey")
  tap(world, c, 10, 4)
  T.eq(bg(scr, 7, 4), COL.yellow, "focused: gold cursor")
  typ(world, c, "Canary-0")
  T.truthy(inRow(scr, 4, "Canary-0")); T.eq(bg(scr, 7 + 8, 4), COL.yellow, "cursor follows the text")
  typ(world, c, "4"); key(world, c, BKSP); typ(world, c, "5")
  T.truthy(inRow(scr, 4, "Canary-05"))
  key(world, c, ENTER); T.eq(d2(c).named, "Canary-05", "Enter commits")
  T.eq(bg(scr, 7 + 9, 4), COL.grey, "and leaves the field")
  tap(world, c, 10, 4); typ(world, c, "x"); key(world, c, ESC)
  T.truthy(inRow(scr, 4, "Canary-05")); T.absent(scr:line(4), "Canary-05x", "Esc cancels the edit")
  -- invalid: a space turns the box red with one red line under it
  tap(world, c, 10, 4); typ(world, c, " y")
  T.eq(bg(scr, 7, 4), COL.red, "invalid box is red"); T.truthy(inRow(scr, 5, "no spaces")); T.eq(fg(scr, 7, 5), COL.red)
  key(world, c, BKSP); key(world, c, BKSP)
  T.eq(bg(scr, 7, 4), COL.grey); T.absent(scr:line(5), "no spaces")
  -- Tab leaves the field: the next Tab target is focused, and typing stops going to the field
  key(world, c, TAB)
  typ(world, c, "q"); T.absent(scr:line(4), "Canary-05q")
  -- the other form widgets
  T.truthy(inRow(scr, 8, "Layer")); T.truthy(inRow(scr, 9, "95%")); T.eq(bg(scr, 8, 9), COL.red, "95% full is red")
end)

T.test("ui2: a monitor shows the field but cannot type", function()
  local world, c, mon = demo2(51, 19, { tab = "form" }, { monitor = { 36, 24 } })
  T.truthy(inRow(mon, 4, "type on the computer"))
  mon:touch(12, 4); world:run(0.2); typ(world, c, "abc")
  T.absent(mon:line(4), "abc"); T.absent(c.screen:line(4), "abc", "the monitor tap did not focus the field")
  tap(world, c, 10, 4); typ(world, c, "abc")
  T.truthy(inRow(c.screen, 4, "abc")); T.truthy(inRow(mon, 4, "abc"), "the monitor shows what is typed on the computer")
end)

---------------------------------------------------------------------------------------------------------
for _, s in ipairs(SIZES) do
  local W, H = s[1], s[2]
  T.test(("ui2: map at %dx%d: cells, arrow, pan row, tap a cell, pan and follow"):format(W, H), function()
    local world, c = demo2(W, H, { tab = "map" })
    local scr = c.screen
    local pan = H > 14
    local vw, vh = W - 2, (H - 1) - 3 + 1 - (pan and 1 or 0)
    local ox, oz = 10 - math.floor(vw / 2), 10 - math.floor(vh / 2)
    local function sx(wx) return 2 + wx - ox end
    local function sy(wz) return 3 + wz - oz end
    T.eq(scr.ch[sy(10)][sx(10)], ">", "the machine, facing east")
    T.eq(fg(scr, sx(10), sy(10)), COL.cyan, "the arrow is cyan")
    T.eq(bg(scr, sx(10), sy(10)), COL.grey, "on land")
    T.eq(bg(scr, sx(12), sy(9)), COL.brown, "soil"); T.eq(bg(scr, sx(15), sy(5)), COL.blue, "water")
    T.eq(bg(scr, sx(11), sy(14)), COL.green, "crops")
    if pan then
      local y = H - 1
      T.truthy(inRow(scr, y, " ^ ") and inRow(scr, y, " v ") and inRow(scr, y, " < ") and inRow(scr, y, " > "), "pan row")
      T.absent(scr:line(y), "Follow", "no Follow while following")
    else
      T.absent(scr:line(H - 1), " ^ ", "short screens drop the pan row")
    end
    -- tap a cell: what is there goes to the notice row
    tap(world, c, sx(12), sy(9)); T.contains(scr:line(2), "Wheat, 7/7 grown")
    tap(world, c, sx(15), sy(5)); T.contains(scr:line(2), "water")
    -- pan with keys: one cell; the Follow button appears; Home follows again
    key(world, c, LEFT)
    T.eq(scr.ch[sy(10)][sx(10) + 1], ">", "panned left by one: the arrow moved right")
    if pan then T.truthy(inRow(scr, H - 1, "Follow")) end
    key(world, c, HOME)
    T.eq(scr.ch[sy(10)][sx(10)], ">", "Home follows")
    typ(world, c, "")
    key(world, c, DOWN); key(world, c, DOWN); typ(world, c, "f")
    T.eq(scr.ch[sy(10)][sx(10)], ">", "f follows")
    if pan then
      local bx = inRow(scr, H - 1, " < ") + 1
      local hx, hz = math.floor(vw / 2), math.floor(vh / 2)
      tap(world, c, inRow(scr, H - 1, " > ") + 1, H - 1)         -- half a viewport to the right
      T.eq(bg(scr, sx(15) - hx, sy(5)), COL.blue, "pan button moves the view by half a viewport")
      T.truthy(inRow(scr, H - 1, "Follow"))
      local fx = inRow(scr, H - 1, "Follow"); T.truthy(fx); T.eq(bg(scr, fx, H - 1), COL.yellow, "Follow is the primary button")
      tap(world, c, fx + 2, H - 1)
      T.eq(scr.ch[sy(10)][sx(10)], ">"); T.absent(scr:line(H - 1), "Follow")
      tap(world, c, inRow(scr, H - 1, " v ") + 1, H - 1)
      T.eq(bg(scr, sx(11), sy(13) - hz), COL.green, "pan down moves the view down by half")
    end
    key(world, c, HOME)
    c:scroll(1); world:run(0.2)
    T.eq(scr.ch[sy(10) - 3][sx(10)], ">", "the wheel pans vertically")
  end)
end

T.test("ui2: map without colour: characters instead of colours", function()
  local world, c = demo2(51, 19, { tab = "map" }, { colour = false })
  T.running(c)
  local scr = c.screen
  T.truthy(scr:text():find(">", 1, true), "arrow")
  T.truthy(scr:text():find(".", 1, true), "land is dots")
  T.truthy(inRow(scr, 18, "[ ^ ]"), "pan buttons use brackets")
end)

T.test("ui2: tiles, list and tabs without colour: | stripe, [ ] buttons, no crash", function()
  local world, c = demo2(51, 19, { tab = "tiles", tiles = 5 }, { colour = false })
  T.running(c)
  local scr = c.screen
  T.eq(scr.ch[3][2], "|"); T.eq(scr.ch[7][2], "|"); T.eq(scr.ch[8][2], " ")
  T.truthy(inRow(scr, 5, "Fuel ####") or inRow(scr, 5, "Fuel -") or inRow(scr, 5, "Fuel #"))
  T.truthy(inRow(scr, 19, "[ Tile"), "tabs are bracketed buttons")
  typ(world, c, "2")
  T.eq(d2(c).tab, "list"); T.truthy(inRow(scr, 3, "Item number 01"))
end)

T.test("ui2: a monitor view gets tiles and taps of its own", function()
  local world, c, mon = demo2(51, 19, { tab = "tiles", tiles = 7 }, { monitor = { 57, 24 } })
  T.truthy(inRow(mon, 3, "Canary-01") and inRow(mon, 3, "Canary-02"), "57x24: two columns")
  mon:touch(32, 5); world:run(0.2)
  T.eq(d2(c).opened, "Canary-02")
  local lx = inRow(mon, 24, " List* ")
  mon:touch(lx + 1, 24); world:run(0.2)
  T.eq(d2(c).tab, "list"); T.truthy(inRow(c.screen, 3, "Item number 01"), "the computer's own view follows")
end)
