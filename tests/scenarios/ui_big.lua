-- UI kit 10.12-10.14 (shared/ui_parts.lua): two-row board entry with paging, block number, Needs you slots.
local cc  = require("sim.cc")
local T   = require("sim.test")
local ENV = require("sim.env")
local COL = ENV.colors

local function frame(w, h, body, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, w = w, h = h, colour = opts.colour }
  for _, f in ipairs({ "ui", "ui_widgets", "ui_parts", "ui_motion" }) do c:install("shared/" .. f .. ".lua") end
  c:writeFile("t.lua", 'local ui = require("ui"); local v = ui.view(term.current()); _G.v = v; v:frame(function(v)\n' ..
    body .. '\nend); sleep(1000)')
  c:run("t"); world:run(0.5)
  T.running(c)
  return world, c
end
local function rowOf(scr, H, s) for y = 1, H do if scr:line(y):find(s, 1, true) then return y end end end
local function bg(scr, x, y) local _, b = scr:colourAt(x, y); return b end
local function fg(scr, x, y) local f = scr:colourAt(x, y); return f end

local ROWS = [[ { { name = "Firecrest-02", state = "working", detail = "Y 31, 4 chunks left, fuel 2,100", age = 3 },
                  { name = "Canary-12", state = "lost", detail = "not heard since 05:58, last at Y -51", age = 180 },
                  { name = "Starling-01", state = "idle", detail = "docked", age = 4 } } ]]

T.test("ui big: two-row board entry", function()
  local world, c = frame(61, 12, "v:board(1, 2, 61, " .. ROWS .. ", { tworow = true })")
  local scr = c.screen
  T.truthy(scr:line(2):find("Firecrest-02", 3, true), "name on row 1")
  T.truthy(scr:line(2):find("working", 1, true), "state word on row 1")
  T.eq(scr:line(2):gsub("%s+$", ""):sub(-2), "3s", "last heard right-aligned")
  T.eq(scr:line(3):sub(1, 6), " " .. " " .. " " .. " " .. "Y " , "detail indented 4")
  T.truthy(scr:line(3):find("Y 31, 4 chunks left", 5, true))
  T.eq(bg(scr, 1, 2), COL.lime, "stripe in the state colour, row 1")
  T.eq(bg(scr, 1, 3), COL.lime, "stripe runs down row 2")
  T.eq(fg(scr, 5, 3), COL.lightGrey, "detail is dim")
  T.eq(bg(scr, 1, 4), COL.grey, "lost for 3 m is stale: grey")
  T.eq(bg(scr, 1, 6), COL.lightBlue, "idle is blue")
end)

T.test("ui big: stale entry greys out, last heard orange", function()
  local world, c = frame(61, 12, "v:board(1, 2, 61, { { name = 'Canary-12', state = 'lost', detail = 'x', age = 45 } }, { tworow = true })")
  local scr = c.screen
  T.eq(bg(scr, 1, 2), COL.grey, "stripe grey"); T.eq(bg(scr, 1, 3), COL.grey)
  T.eq(fg(scr, 3, 2), COL.lightGrey, "name grey")
  T.eq(fg(scr, 60, 2), COL.orange, "last heard orange")
end)

T.test("ui big: departures paging keeps slots and turns pages", function()
  local body = [[ local r = {}
    for i = 1, 5 do r[i] = { name = "Bird-" .. i, state = "idle", detail = "d" .. i, age = 1 } end
    local y = v:board(1, 2, 40, r, { tworow = true, slots = 2, page = _G.pg })
    _G.endY = y; _G.anim = v.animated ]]
  local world, c = frame(40, 10, "_G.pg = 1 " .. body)
  local scr = c.screen
  T.eq(c.G.endY, 7, "2 slots x 2 rows + dot row")
  T.truthy(scr:line(2):find("Bird-1", 1, true)); T.truthy(scr:line(4):find("Bird-2", 1, true))
  T.truthy(scr:line(6):find("o . .", 1, true), "dots: first page lit")
  T.eq(c.G.anim, true, "paging re-arms the redraw")
  local w3, c3 = frame(40, 10, "_G.pg = 3 " .. body)
  T.truthy(c3.screen:line(2):find("Bird-5", 1, true), "last page")
  T.falsy(c3.screen:line(4):find("Bird", 1, true), "short last page leaves slot 2 blank")
  T.truthy(c3.screen:line(6):find(". . o", 1, true))
  -- no page forced: the page follows the clock
  local w4, c4 = frame(40, 10, (body:gsub("page = _G.pg", "")))
  local first = c4.screen:line(2)
  w4:run(3.1); c4.G.v:frame(function(v) local r = {}
    for i = 1, 5 do r[i] = { name = "Bird-" .. i, state = "idle", age = 1 } end
    v:board(1, 2, 40, r, { tworow = true, slots = 2 }) end)
  T.truthy(c4.screen:line(2) ~= first, "page turned after PAGE_S")
  -- one page: no dots
  local w5, c5 = frame(40, 10, [[ _G.endY = v:board(1, 2, 40, { { name = "A", state = "ok", age = 1 } }, { tworow = true, slots = 2 }) ]])
  T.eq(c5.G.endY, 6, "no dot row on one page")
end)

T.test("ui big: block number", function()
  local world, c = frame(40, 8, [[ _G.e = v:bigNumber(2, 2, "113%", "warn", { px = 2, py = 1 }) ]])
  local scr = c.screen
  T.eq(c.G.e, 31, "30 wide from x=2 ends at 31")
  T.eq(bg(scr, 2, 2), COL.black, "1: top-left of '1' is clear"); T.eq(bg(scr, 4, 2), COL.orange, "1: top middle lit")
  T.eq(bg(scr, 2, 3), COL.orange, "1: second row left lit")
  T.eq(bg(scr, 4, 6), COL.orange, "bottom row of 1"); T.eq(bg(scr, 2, 7), COL.black, "5 rows tall")
  T.eq(bg(scr, 26, 2), COL.orange, "percent top-left"); T.eq(bg(scr, 28, 2), COL.black)
  local w2, c2 = frame(40, 12, [[ _G.e = v:bigNumber(1, 1, "8:-", "good", { px = 4, py = 2 }) ]])
  T.eq(c2.G.e, 44, "4x2: (4*3-1)*4 = 44 columns")
  T.eq(bg(c2.screen, 1, 1), COL.lime); T.eq(bg(c2.screen, 1, 2), COL.lime, "py = 2 repeats rows")
  T.eq(bg(c2.screen, 1, 3), COL.lime, "8 row 2 left"); T.eq(bg(c2.screen, 5, 3), COL.black, "8 middle clear")
  local w3, c3 = frame(40, 8, [[ v:bigNumber(1, 1, "7", "warn", { px = 2, py = 1 }) ]], { colour = false })
  T.eq(c3.screen.ch[1][1], "#", "no colour: # cells")
end)

T.test("ui big: screens picker uses the kit font", function()
  local world, c = frame(40, 8, [[ _G.f = ui.bigFont ]])
  for _, k in ipairs({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "%", ":", "-" }) do
    T.truthy(c.G.f[k] and #c.G.f[k] == 5, "glyph " .. k)
  end
end)

local ALERTS = [[ { { text = "Smelter low on coal", tone = "warn", name = "Smelter" },
                    { text = "Tap #4 is dry", tone = "bad", name = "Farm" },
                    { text = "Seagull stuck", tone = "warn", name = "Seagull" },
                    { text = "Storage 98% full", tone = "warn", name = "Storage" },
                    { text = "Canary-12 lost", tone = "bad", name = "Canary" } } ]]

T.test("ui big: Needs you lists worst first and folds the rest", function()
  local world, c = frame(50, 10, "_G.e = v:needsYou(1, 2, 50, 4, " .. ALERTS .. ")")
  local scr = c.screen
  T.eq(c.G.e, 7, "label + 4 slots")
  T.truthy(scr:line(2):find("NEEDS YOU", 1, true)); T.eq(fg(scr, 1, 2), COL.yellow, "gold label")
  T.truthy(scr:line(3):find("Tap #4 is dry", 1, true), "red first"); T.eq(bg(scr, 1, 3), COL.red)
  T.truthy(scr:line(4):find("Canary-12 lost", 1, true)); T.eq(bg(scr, 1, 4), COL.red)
  T.truthy(scr:line(5):find("Smelter low on coal", 1, true), "then orange in order"); T.eq(bg(scr, 1, 5), COL.orange)
  T.truthy(scr:line(6):find("+2 more: Seagull, Storage", 1, true), "last slot folds the rest")
  T.eq(fg(scr, 3, 6), COL.orange)
end)

T.test("ui big: Needs you with few alerts and with none", function()
  local world, c = frame(50, 10, [[ _G.e = v:needsYou(1, 2, 50, 4, { { text = "Tap #4 is dry", tone = "bad" } }) ]])
  T.truthy(c.screen:line(3):find("Tap #4 is dry", 1, true)); T.eq(c.screen:line(4):gsub("%s", ""), "", "empty slots blank")
  T.eq(c.G.e, 7, "still 4 slots")
  local w2, c2 = frame(50, 10, [[ _G.e = v:needsYou(1, 2, 50, 4, {}, { summary = "12 systems fine" }) ]])
  T.truthy(c2.screen:line(3):find("Nothing needs you.", 1, true)); T.eq(fg(c2.screen, 3, 3), COL.lime, "lime")
  T.truthy(c2.screen:line(4):find("12 systems fine", 1, true)); T.eq(fg(c2.screen, 3, 4), COL.lightGrey, "dim summary")
  T.eq(c2.G.e, 7)
  -- exactly n alerts: all shown, no fold
  local w3, c3 = frame(50, 10, [[ _G.e = v:needsYou(1, 2, 50, 2, { { text = "a", tone = "warn" }, { text = "b", tone = "warn" } }) ]])
  T.truthy(c3.screen:line(4):find("b", 3, true)); T.falsy(c3.screen:line(4):find("more", 1, true))
end)
