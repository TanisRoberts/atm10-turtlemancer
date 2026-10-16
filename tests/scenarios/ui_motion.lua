-- UI kit motion (shared/ui_motion.lua, docs/design/ui-kit.md section 9): the shared beat, status glyphs, budget,
-- ANIM setting, spinner and indeterminate bar, busy buttons, and the cost of a beat. Drives tests/demo/ui_demo2.lua.
local cc  = require("sim.cc")
local T   = require("sim.test")
local ENV = require("sim.env")
local COL = ENV.colors

local function install(c)
  c:install("shared/ui.lua"); c:install("shared/ui_widgets.lua"); c:install("shared/ui_parts.lua"); c:install("shared/ui_motion.lua")
end
local function demo2(w, h, cfg, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, label = "Demo2", w = w, h = h, colour = opts.colour }
  install(c); c:install("tests/demo/ui_demo2.lua")
  c:writeTable("demo2.cfg", cfg or {})
  c:run("ui_demo2")
  world:run(0.5)
  return world, c
end
local function frame(w, h, body, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, w = w, h = h, colour = opts.colour }
  install(c)
  c:writeFile("t.lua", 'local ui = require("ui"); local v = ui.view(term.current()); _G.v = v; _G.draw = function()\n' ..
    'v:frame(function(v)\n' .. body .. '\nend) end; _G.draw(); while true do sleep(0.25); _G.draw() end')
  c:run("t"); world:run(0.1)
  T.running(c)
  return world, c
end
local function grid(scr, W, H)
  local g = {}
  for y = 1, H do g[y] = {}; for x = 1, W do g[y][x] = scr.ch[y][x] end end
  return g
end
local function diff(a, b, W, H)
  local out = {}
  for y = 1, H do for x = 1, W do if a[y][x] ~= b[y][x] then out[#out + 1] = { x, y } end end end
  return out
end
local function fg(scr, x, y) local f = scr:colourAt(x, y); return f end

T.test("motion: ui.beat steps with the clock and ui.loadAnim keeps what is there", function()
  local world, c = frame(30, 4, [[ v:put(1, 1, "x", "fg", "bg") ]])
  local ui = c.env.require("ui")
  local b0 = ui.beat(2); world:run(0.5); T.eq(ui.beat(2), b0 + 1, "2 beats a second")
  local b1 = ui.beat(4); world:run(0.25); T.eq(ui.beat(4), b1 + 1, "4 beats a second")
  T.eq(ui.setAnim("calm"), "calm"); T.eq(ui.setAnim("bogus"), "full"); T.eq(ui.setAnim("OFF"), "off")
  c:writeFile("x.env", "# mine\nFOO=1\n")
  T.eq(ui.loadAnim("x.env", "calm"), "calm", "missing key: the default is used")
  c:writeFile("y.env", "ANIM=off\n")
  T.eq(ui.loadAnim("y.env", "full"), "off", "an existing line is never overwritten")
  T.eq(ui.loadAnim("y.env", "full"), "off")
end)

for _, W in ipairs({ 51 }) do
  local H = 19
  T.test("motion: only working, waiting and returning tiles move, and only in the glyph cell", function()
    local world, c = demo2(W, H, { tab = "tiles", tiles = 7 })
    local scr = c.screen
    local seen, prev = {}, grid(scr, W, H)
    for _ = 1, 8 do
      world:run(0.5)
      local cur = grid(scr, W, H)
      for _, p in ipairs(diff(prev, cur, W, H)) do
        local x, y = p[1], p[2]
        T.truthy(y == 1 or y == 3 or (y == 9 and x < 26), ("only a glyph cell moved, at %d,%d"):format(x, y))
        seen[y .. ":" .. (x < 26 and "L" or "R")] = true
      end
      prev = cur
    end
    T.truthy(seen["3:L"] and seen["3:R"] and seen["9:L"], "working, waiting and returning all moved")
    T.eq(seen["9:R"], nil, "the lost tile never moves")
    local wx = scr:line(3):find("working", 1, true)
    T.eq(fg(scr, wx - 2, 3), COL.lime, "the glyph takes the state colour")
  end)

  T.test("motion: the working glyph plays \\ | / | in order", function()
    local world, c = demo2(W, H, { tab = "tiles", tiles = 1 })
    local scr = c.screen
    local wx = scr:line(3):find("working", 1, true)
    local frames = {}
    for _ = 1, 8 do frames[#frames + 1] = scr.ch[3][wx - 2]; world:run(0.5) end
    local s = table.concat(frames)
    T.truthy(("\\|/|\\|/|"):find(s, 1, true) or ("|/|\\|/|\\"):find(s, 1, true) or ("/|\\|/|\\|"):find(s, 1, true)
      or ("|\\|/|\\|/"):find(s, 1, true), "frames in order: " .. s)
  end)

  T.test("motion: ANIM=off and a stale tile never change", function()
    local world, c = demo2(W, H, { tab = "tiles", tiles = 7, anim = "off" })
    local scr = c.screen
    local a = grid(scr, W, H)
    world:run(3)
    T.eq(#diff(a, grid(scr, W, H), W, H), 0, "nothing moves with ANIM=off")
    T.eq(scr.ch[3][scr:line(3):find("working", 1, true) - 2], "\\", "the still working glyph")
    local w2, c2 = demo2(W, H, { tab = "tiles", tiles = 7 })
    local lx = c2.screen:line(9):find("lost", 1, true)
    T.eq(c2.screen.ch[9][lx - 2], "?", "a stale tile shows a still grey ?")
    T.eq(fg(c2.screen, lx - 2, 9), COL.grey)
  end)

  T.test("motion: a beat writes one blit per changed row and never clears; the timer sleeps when nothing moves", function()
    local world, c = demo2(W, H, { tab = "tiles", tiles = 7 })
    local scr = c.screen
    scr.writes0 = scr.writes
    world:run(5)                                          -- 10 beats
    T.truthy(scr.writes - scr.writes0 <= 10 * 3, "at most the header and two tile rows a beat (" .. (scr.writes - scr.writes0) .. ")")
    T.truthy(scr.writes - scr.writes0 >= 10, "and it does move")
    T.eq(scr.clears or 0, 0, "never clears")
    -- nothing animated: no frames at all while idle
    local w3, c3 = demo2(W, H, { tab = "tiles", tiles = 7, anim = "off" })
    local f0 = c3.screen.writes
    w3:run(10); T.eq(c3.screen.writes, f0, "ANIM=off: an idle screen writes nothing")
  end)
end

T.test("motion: a view draws at most 24 moving glyphs; the rest show their still frame", function()
  local world, c = frame(60, 30, [[ for i = 1, 25 do v:glyph(2 + (i - 1) * 2, 3, "working") end ]])
  local scr, e = c.screen, c.env._G
  T.eq(e.v.glyphN, 24, "24 counted")
  T.eq(scr.ch[3][2 + 24 * 2], "\\", "the 25th is the still first frame")
  local seen = {}
  for _ = 1, 4 do seen[scr.ch[3][2]] = true; T.eq(scr.ch[3][2 + 24 * 2], "\\"); world:run(0.5) end
  T.truthy(seen["|"] and seen["/"], "while the first one plays")
end)

T.test("motion: glyph colours and frames per state (section 9.2)", function()
  local world, c = frame(60, 6, [[
    local states = { "building", "farming", "smelting", "waiting", "returning", "rebooting", "docked", "done", "idle", "stale", "lost", "error" }
    for i, s in ipairs(states) do v:glyph(2 + i * 2, 3, s) end
  ]])
  local scr = c.screen
  local function at(i) return scr.ch[3][2 + i * 2], fg(scr, 2 + i * 2, 3) end
  local ch, f = at(7); T.eq(ch, "="); T.eq(f, COL.lightBlue, "docked")
  ch, f = at(8); T.eq(ch, "+"); T.eq(f, COL.lightBlue, "done")
  ch, f = at(9); T.eq(ch, "-"); T.eq(f, COL.lightGrey, "idle")
  ch, f = at(10); T.eq(ch, "?"); T.eq(f, COL.grey, "stale")
  ch, f = at(11); T.eq(ch, "!"); T.eq(f, COL.red, "lost")
  ch, f = at(12); T.eq(ch, "!"); T.eq(f, COL.red, "error")
  ch, f = at(6); T.eq(f, COL.purple, "rebooting")
  ch, f = at(5); T.eq(f, COL.cyan, "returning")
  ch, f = at(2); T.eq(f, COL.green, "farming")
  -- smelting cycles red, orange, yellow, orange
  local cols = {}
  for _ = 1, 4 do cols[#cols + 1] = select(2, at(3)); world:run(0.5) end
  T.eq(#cols, 4)
  local set = {}; for _, x in ipairs(cols) do set[x] = true end
  T.truthy(set[COL.red] and set[COL.orange] and set[COL.yellow], "smelting flame colours")
end)

T.test("motion: a new error pulses three times, then stays still", function()
  local world, c = frame(20, 4, [[ v:glyph(2, 2, "error", { since = _G.since }) ]])
  local scr = c.screen
  -- no `since`: still red
  T.eq(fg(scr, 2, 2), COL.red)
  local w2, c2 = frame(20, 4, [[ _G.since = _G.since or os.clock(); v:glyph(2, 2, "error", { since = _G.since }) ]])
  local cols = {}
  for _ = 1, 5 do cols[#cols + 1] = fg(c2.screen, 2, 2); w2:run(1) end
  T.eq(cols[1], COL.red); T.eq(cols[2], COL.white, "white on the second second"); T.eq(cols[3], COL.red)
  T.eq(cols[5], COL.red, "and red and still after three seconds")
  T.eq(c2.screen.ch[2][2], "!")
end)

T.test("motion: spinner and indeterminate bar; calm keeps the spinner and stills the bar", function()
  local body = [[ v:spinner(2, 2); v:indeterminate(4, 4, 30) ]]
  local world, c = frame(40, 6, body)
  local scr = c.screen
  local function blockAt()
    for x = 4, 33 do local _, b = scr:colourAt(x, 4); if b ~= COL.grey then return x end end
  end
  local starts, glyphs = {}, {}
  for _ = 1, 40 do starts[#starts + 1] = blockAt(); glyphs[scr.ch[2][2]] = true; world:run(0.25) end
  local lo, hi = 99, 0
  for _, x in ipairs(starts) do lo = math.min(lo, x); hi = math.max(hi, x) end
  T.eq(lo, 4, "the block reaches the left end"); T.eq(hi, 4 + 30 - 6, "and the right end (a 6-cell block)")
  T.eq(math.abs(starts[2] - starts[1]), 1, "one cell a beat")
  T.truthy(glyphs["."] and glyphs["o"] and glyphs["O"], "the spinner plays . o O o")
  local w2, c2 = frame(40, 6, [[ require("ui").setAnim("calm") ]] .. body)
  local s2 = {}
  for _ = 1, 8 do
    for x = 4, 33 do local _, b = c2.screen:colourAt(x, 4); if b ~= COL.grey then s2[x] = true; break end end
    w2:run(0.25)
  end
  local n = 0; for _ in pairs(s2) do n = n + 1 end
  T.eq(n, 1, "calm: the bar is still"); T.truthy(c2.screen.ch[2][2] ~= nil)
end)

T.test("motion: a busy button keeps its label and spins the rebooting glyph in front of it", function()
  local world, c = frame(40, 6, [[ v:buttons(2, 3, { { label = "Reboot", busy = true }, { label = "Other" } }) ]])
  local scr = c.screen
  local rx = scr:line(3):find("Reboot", 1, true)
  T.truthy(rx, "the label stays")
  local seen = {}
  for _ = 1, 8 do
    seen[scr.ch[3][rx - 2]] = true
    T.eq(select(2, scr:colourAt(rx, 3)), COL.purple, "purple fill")
    world:run(0.5)
  end
  T.truthy(seen["|"] and seen["/"] and seen["-"] and seen["\\"], "| / - \\ in front")
  T.eq(scr:line(3):find("Other", 1, true), rx + 6 + 2 + 1, "the next button keeps its place")
end)

T.test("motion: no colour means still glyphs and no timer", function()
  local world, c = demo2(51, 19, { tab = "tiles", tiles = 7 }, { colour = false })
  local scr = c.screen
  local a = grid(scr, 51, 19)
  world:run(3)
  T.eq(#diff(a, grid(scr, 51, 19), 51, 19), 0, "nothing moves without colour")
end)
