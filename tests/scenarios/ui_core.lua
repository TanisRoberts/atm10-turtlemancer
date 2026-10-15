-- UI kit part 1 (shared/ui.lua): look, header, buttons, steppers, notices, footer, event loop.
-- The demo screen is tests/demo/ui_demo.lua; the pure helpers load ui.lua straight into the host Lua.
local cc  = require("sim.cc")
local T   = require("sim.test")
local COL = require("sim.env").colors

local SIZES = { { 57, 24 }, { 51, 19 }, { 39, 13 }, { 26, 20 } }
local RULE = "\140"

local function pure()
  local env = setmetatable({ colours = COL, keys = require("sim.env").keys, os = os }, { __index = _G })
  env.require = function(n) return assert(loadfile(cc.ROOT .. "/shared/" .. n .. ".lua", "t", env))() end
  return assert(loadfile(cc.ROOT .. "/shared/ui.lua", "t", env))()
end

local function demo(w, h, opts)
  opts = opts or {}
  local world = cc.world()
  local c = world:computer{ id = 1, label = "Demo", w = w, h = h, colour = opts.colour }
  local mon = opts.monitor and c:monitor("right", opts.monitor[1], opts.monitor[2])
  c:install("shared/ui.lua"); c:install("shared/ui_widgets.lua")
  c:install("tests/demo/ui_demo.lua")
  c:run("ui_demo")
  world:run(0.5)
  return world, c, mon
end

-- x of `s` on screen row y (plain find), or nil
local function inRow(scr, y, s) return scr:line(y):find(s, 1, true) end
local function tap(world, c, x, y) c:click(x, y); world:run(0.2) end
local function fg(scr, x, y) local f = scr:colourAt(x, y); return f end
local function bg(scr, x, y) local _, b = scr:colourAt(x, y); return b end

---------------------------------------------------------------------------------------------------------
T.test("ui: size classes and the content area", function()
  local ui = pure()
  local function cls(w, h) local a, b = ui.layout.classes(w, h); return a .. "/" .. b end
  T.eq(cls(26, 20), "narrow/normal")        -- glasses
  T.eq(cls(36, 24), "compact/normal")       -- 2x2 display
  T.eq(cls(39, 13), "compact/short")        -- turtle
  T.eq(cls(51, 19), "regular/normal")       -- advanced computer
  T.eq(cls(57, 24), "regular/normal")       -- 3x2 board
  T.eq(cls(57, 38), "regular/tall")         -- 3x3 board
  T.eq(cls(164, 81), "wide/tall")           -- wall
  T.eq(cls(30, 14), "narrow/short")
  T.eq(cls(31, 15), "compact/normal")
  T.eq(cls(71, 31), "wide/tall")
  local r = ui.layout.content(51, 19)
  T.eq(r.x1 .. "," .. r.y1 .. "," .. r.x2 .. "," .. r.y2, "2,3,50,18")
  r = ui.layout.content(51, 19, true)
  T.eq(r.y2, 17, "an input row takes one more row")
end)

T.test("ui: manifest.lua ships shared/ui.lua to every role that will use it, and the file compiles flat", function()
  local f = assert(io.open(cc.ROOT .. "/manifest.lua")); local src = f:read("*a"); f:close()
  local m = assert(load(src, "@manifest.lua", "t", {}))()
  local want = { computer = { "mainframe", "storage", "smelter", "foreman", "nether", "farmhand", "architect", "plastic",
                              "neural" }, glasses = { "hud" } }
  local function has(r)
    local a, b
    for _, p in ipairs(r.files or {}) do a = a or p == "shared/ui.lua"; b = b or p == "shared/ui_widgets.lua" end
    return a and b
  end
  for kind, roles in pairs(want) do
    for _, name in ipairs(roles) do
      local r = m.types[kind].roles[name]
      T.truthy(r, kind .. "/" .. name .. " exists")
      T.truthy(has(r), name .. " should list shared/ui.lua and shared/ui_widgets.lua")
    end
  end
  -- devices keep shared files flat (shared/ui.lua -> ui.lua), so a program says require("ui")
  local world = cc.world()
  local c = world:computer{ id = 1 }
  c:installRole("foreman")
  T.truthy(c.files["ui.lua"], "installed as ui.lua")
end)

T.test("ui: text.fit cuts with ..", function()
  local ui = pure()
  T.eq(ui.text.fit("Canary-04", 9), "Canary-04")
  T.eq(ui.text.fit("Canary-04", 8), "Canary..")
  T.eq(ui.text.fit("Canary-04", 2), "..")
  T.eq(ui.text.fit("Canary-04", 0), "")
end)

T.test("ui: hit.find picks the target that contains the tap, nearest drawn cells first", function()
  local ui = pure()
  local a = { x1 = 2, y1 = 4, x2 = 8, y2 = 4, tx1 = 1, ty1 = 3, tx2 = 9, ty2 = 5, name = "a" }
  local b = { x1 = 10, y1 = 4, x2 = 16, y2 = 4, tx1 = 9, ty1 = 3, tx2 = 17, ty2 = 5, name = "b" }
  local boxes = { a, b }
  T.eq(ui.hit.find(boxes, 5, 4).name, "a")                   -- on the pill
  T.eq(ui.hit.find(boxes, 5, 3).name, "a")                   -- the extra row above
  T.eq(ui.hit.find(boxes, 5, 5).name, "a")                   -- and below
  T.eq(ui.hit.find(boxes, 5, 2), nil, "two rows up is outside")
  T.eq(ui.hit.find(boxes, 9, 4).name, "a", "the gap cell: a tie goes to the first")
  T.eq(ui.hit.find(boxes, 10, 4).name, "b")
  T.eq(ui.hit.find(boxes, 17, 4).name, "b", "half the gap beside the last pill")
  T.eq(ui.hit.find(boxes, 20, 4), nil)
  -- a control sitting in the row above wins over another's extra row
  local c = { x1 = 2, y1 = 3, x2 = 8, y2 = 3, name = "c" }
  T.eq(ui.hit.find({ a, c }, 5, 3).name, "c", "its own cells beat a neighbour's extra row")
end)

T.test("ui: palette installed on a colour screen, stock one restored on close", function()
  local world, c = demo(51, 19)
  T.eq(c.screen:paletteHex(COL.yellow), 0xF2B71F, "gold")
  T.eq(c.screen:paletteHex(COL.black), 0x17181C, "bg")
  T.eq(c.screen:paletteHex(COL.cyan), 0x4CC3CC, "info")
  c:key(259)                      -- Backspace = back; the demo's back stops the loop
  world:run(0.5)
  T.truthy(c.finished, "the demo ended")
  T.eq(c.screen:paletteHex(COL.yellow), 0xDEDE6C, "palette back to stock")
end)

---------------------------------------------------------------------------------------------------------
for _, s in ipairs(SIZES) do
  local W, H = s[1], s[2]
  local wide = W >= 46

  T.test(("ui: header, buttons, stepper and footer at %dx%d"):format(W, H), function()
    local world, c = demo(W, H)
    local scr = c.screen
    -- header: gold chip with black title, state word lime at the right, rule below
    T.eq(inRow(scr, 1, " DEMO "), 1)
    T.eq(bg(scr, 1, 1), COL.yellow, "chip is gold")
    T.eq(fg(scr, 2, 1), COL.black)
    T.eq(inRow(scr, 1, "working"), W - 7, "state word sits at the right edge")
    T.eq(fg(scr, W - 3, 1), COL.lime, "working is lime")
    T.eq(scr.ch[2][1], RULE); T.eq(scr.ch[2][W], RULE)
    T.eq(fg(scr, 1, 2), COL.grey)
    if wide then T.contains(scr:line(1), "3 canaries, storage ok") else T.absent(scr:line(1), "canaries") end
    -- buttons on row 4: primary gold, normal grey, danger red, disabled bare
    local px = inRow(scr, 4, " Pause ")
    T.eq(px, 2, "buttons start at the margin")
    T.eq(bg(scr, px, 4), COL.yellow, "primary is gold")
    local rx = inRow(scr, 4, W <= 30 and "Boot" or "Reboot")
    if W <= 30 then T.absent(scr:line(4), "Reboot", "narrow uses the short label") end
    T.eq(bg(scr, rx, 4), COL.grey, "normal is grey"); T.eq(fg(scr, rx, 4), COL.white)
    local fx = inRow(scr, 4, "Forget")
    T.eq(bg(scr, fx, 4), COL.red, "danger is red"); T.eq(fg(scr, fx, 4), COL.black)
    local ox = inRow(scr, 5, "Off")
    T.eq(bg(scr, ox, 5), COL.black, "disabled has no fill"); T.eq(fg(scr, ox, 5), COL.grey)
    -- stepper: label, - value +, and << >> when there is room
    local sx, sy = scr:find("40")
    T.truthy(sx, "stepper value")
    if W > 30 then T.truthy(inRow(scr, sy, "Mine depth"), "label on the same row") else
      T.truthy(inRow(scr, sy - 1, "Mine depth"), "narrow stacks the label above") end
    T.eq(inRow(scr, sy, "<<") ~= nil, wide, "<< >> on regular and wide only")
    T.eq(inRow(scr, sy, ">>") ~= nil, wide)
    T.truthy(inRow(scr, sy, " - ")); T.truthy(inRow(scr, sy, " + "))
    T.eq(fg(scr, sx, sy), COL.white, "value is white until a change is pending")
    -- footer: last row, Back on regular and wide, a bare < otherwise
    T.eq(inRow(scr, H, " < "), 1)
    T.eq(inRow(scr, H, "Back") ~= nil, wide)
    T.eq(bg(scr, 2, H), COL.grey)
    -- nothing draws below the content area into the footer or on the rule row
    for y = 3, H - 1 do T.absent(scr:line(y), RULE) end
  end)
end

---------------------------------------------------------------------------------------------------------
T.test("ui: tapping buttons, and the bigger tap area", function()
  local world, c = demo(51, 19)
  local scr = c.screen
  tap(world, c, 4, 4)                                   -- on Pause
  T.eq(c.env._G.demo.paused, true)
  T.contains(scr:line(1), "waiting"); T.eq(fg(scr, 51 - 3, 1), COL.orange, "waiting is orange")
  tap(world, c, 4, 3)                                   -- the row above Pause: its extra area
  T.eq(c.env._G.demo.paused, false, "extra row above")
  tap(world, c, 8, 5)                                   -- the row below (Off is nearer its own cells)
  T.eq(c.env._G.demo.paused, true, "extra row below")
  tap(world, c, 4, 7)                                   -- three rows down: nothing there
  T.eq(c.env._G.demo.paused, true)
  local rx = inRow(scr, 4, "Reboot")
  tap(world, c, rx + 2, 4)
  T.eq(c.env._G.demo.reboots, 1)
  tap(world, c, rx - 2, 4)                              -- the gap before Reboot is Pause's or Reboot's, never lost
  T.truthy(c.env._G.demo.reboots + (c.env._G.demo.paused and 0 or 1) >= 2, "gap tap landed on a neighbour")
  local ox = inRow(scr, 5, "Off")
  tap(world, c, ox, 5)
  T.eq(c.env._G.demo.off, nil, "a disabled button ignores taps")
  tap(world, c, 49, 1)                                  -- the state word
  T.eq(c.env._G.demo.stateTaps, 1)
end)

T.test("ui: tap-twice confirm: Sure?, runs on the second tap, times out after 4 seconds", function()
  local world, c = demo(51, 19)
  local scr, d = c.screen, nil
  local fx = inRow(scr, 4, "Forget")
  tap(world, c, fx, 4)
  d = c.env._G.demo
  T.eq(d.forgotten, 0, "first tap only arms")
  T.truthy(inRow(scr, 4, "Sure?"), "label becomes Sure?")
  T.eq(bg(scr, inRow(scr, 4, "Sure?"), 4), COL.red, "danger stays red when armed")
  tap(world, c, fx, 4)
  T.eq(d.forgotten, 1, "second tap runs it")
  T.truthy(inRow(scr, 4, "Forget"), "back to idle")
  -- timeout
  tap(world, c, fx, 4)
  T.truthy(inRow(scr, 4, "Sure?"))
  world:run(3)
  T.truthy(inRow(scr, 4, "Sure?"), "still armed at ~3s")
  world:run(1.5)
  T.truthy(inRow(scr, 4, "Forget"), "disarmed after 4 seconds, with no event to prompt the redraw")
  tap(world, c, fx, 4)
  T.eq(d.forgotten, 1, "a tap after the timeout arms again, it does not run")
  -- any other tap disarms
  tap(world, c, 4, 4)
  T.truthy(inRow(scr, 4, "Forget"), "another tap puts it back")
  tap(world, c, fx, 4)
  T.eq(d.forgotten, 1)
  -- any key press disarms too
  c:type("x"); world:run(0.2)
  c:key(263); world:run(0.2)
  T.truthy(inRow(scr, 4, "Forget"), "a key press puts it back")
end)

T.test("ui: keys: Tab focus, Enter twice confirms, hotkey, Esc, Backspace goes back", function()
  local world, c = demo(51, 19)
  local scr, d = c.screen, c.env._G.demo
  c:key(258); world:run(0.2)                            -- Tab: Pause
  T.eq(scr.ch[4][1], ">", "focused button gets a > in the free cell before it")
  T.eq(fg(scr, 1, 4), COL.white)
  c:key(258); c:key(258); world:run(0.2)                -- Reboot, then Forget
  T.eq(scr.ch[4][inRow(scr, 4, "Forget") - 2], ">")
  c:key(257); world:run(0.2)                            -- Enter arms
  T.truthy(inRow(scr, 4, "Sure?")); T.eq(d.forgotten, 0)
  c:key(257); world:run(0.2)                            -- Enter again confirms
  T.eq(d.forgotten, 1)
  c:queue("key", 258, false); c:queue("key", 258, false); world:run(0.2)   -- on to the stepper, then Back
  c:key(258); world:run(0.2)                            -- wraps to Pause
  T.eq(scr.ch[4][1], ">")
  c:key(256); world:run(0.2)                            -- Esc clears the focus
  T.eq(scr.ch[4][1], " ")
  c:type("p"); world:run(0.2)                           -- hotkey
  T.eq(d.paused, true)
  c:key(259); world:run(0.5)                            -- Backspace = back
  T.eq(d.backs, 1)
  T.truthy(c.finished, "ui.quit ends ui.run")
end)

T.test("ui: Shift+Tab goes backwards", function()
  local world, c = demo(51, 19)
  local scr = c.screen
  c:queue("key", 340, false); c:queue("key", 258, false); c:queue("key_up", 340); world:run(0.2)
  -- the last focusable is Back, whose pill starts at x=1 and draws a brighter fill instead of a >
  T.eq(bg(scr, 2, 19), COL.lightGrey, "Back focused: brighter fill")
end)

T.test("ui: stepper taps, limits, pending value and keys", function()
  local world, c = demo(51, 19)
  local scr, d = c.screen, c.env._G.demo
  local sx, sy = scr:find("40")
  local function press(txt) tap(world, c, inRow(scr, sy, txt) + 1, sy) end
  press(" - ");  T.eq(d.depth, 39); T.eq(fg(scr, scr:find("39"), sy), COL.yellow, "pending value is gold")
  press(" + ");  T.eq(d.depth, 40)
  press(">>");   T.eq(d.depth, 50)
  press("<<");   T.eq(d.depth, 40)
  press(">>"); press(">>"); T.eq(d.depth, 60, "clamped at max")
  T.eq(fg(scr, inRow(scr, sy, " + ") + 1, sy), COL.grey, "+ is disabled at the maximum")
  press(" + ");  T.eq(d.depth, 60)
  -- keys on a focused stepper
  c:key(258); c:key(258); c:key(258); c:key(258); world:run(0.2)     -- Pause, Reboot, Forget, stepper
  T.eq(scr.ch[sy][1], ">", "stepper focus marker")
  c:key(263); world:run(0.2); T.eq(d.depth, 59)
  c:key(262); world:run(0.2); T.eq(d.depth, 60)
  c:key(267); world:run(0.2); T.eq(d.depth, 50)                      -- PgDn
  c:key(266); world:run(0.2); T.eq(d.depth, 60)                      -- PgUp
  c:type("-"); world:run(0.2); T.eq(d.depth, 59)
  c:type("+"); world:run(0.2); T.eq(d.depth, 60)
end)

T.test("ui: stepper at the minimum disables -", function()
  local ui = pure()
  local t = cc.Term.new(51, 5)
  local seen = {}
  local v = ui.view({ getSize = function() return 51, 5 end, isColour = function() return true end,
    setCursorPos = function(x, y) t:setCursorPos(x, y) end, setBackgroundColour = function(x) t:setBackgroundColour(x) end,
    setTextColour = function(x) t:setTextColour(x) end, write = function(s) t:write(s) end, clear = function() t:clear() end })
  v:begin()
  v:stepper(2, 2, "Depth", 0, { min = 0, max = 10, on = function(n) seen[#seen + 1] = n end })
  local minus
  for _, b in ipairs(v.boxes) do if b.id == "step:Depth-" then minus = b end end
  T.eq(minus.enabled, false)
  v:tap(minus.x1, minus.y1)
  T.eq(#seen, 0)
end)

---------------------------------------------------------------------------------------------------------
T.test("ui: notices: purple in flight, cut with .. on narrow, expire after 5 seconds, tap dismisses", function()
  local world, c = demo(51, 19)
  local scr = c.screen
  tap(world, c, inRow(scr, 4, "Reboot") + 1, 4)
  T.eq((scr:line(2):gsub("%s+$", "")), " Reboot sent to Canary-04: it finishes its block")
  T.eq(fg(scr, 3, 2), COL.purple, "order in flight is purple")
  T.eq(scr.ch[2][51], " ", "the notice replaces the rule on the whole row")
  world:run(4)
  T.contains(scr:line(2), "Reboot sent")
  world:run(1.5)
  T.eq(scr.ch[2][1], RULE, "the rule comes back after 5 seconds")
  tap(world, c, inRow(scr, 4, "Reboot") + 1, 4)
  T.contains(scr:line(2), "Reboot sent")
  tap(world, c, 30, 2)
  T.eq(scr.ch[2][1], RULE, "a tap on the notice dismisses it")

  local world2, c2 = demo(26, 20)
  tap(world2, c2, inRow(c2.screen, 4, "Boot") + 1, 4)
  T.eq(c2.screen:line(2), " Reboot sent to Canary-.. ", "narrow cuts with ..")
end)

T.test("ui: an error notice stays until tapped; the next notice replaces it; action button", function()
  local world = cc.world()
  local c = world:computer{ id = 1, w = 51, h = 19 }
  c:install("shared/ui.lua"); c:install("shared/ui_widgets.lua")
  c:writeFile("t.lua", [[
    local ui = require("ui")
    local v = ui.view(term.current())
    _G.undone = 0
    ui.say("Order failed: no fuel", "bad")
    ui.run({ v }, function(v)
      v:header("T", { state = "error" })
      v:buttons(2, 4, { { label = "Plain", fn = function() ui.say("Done", "good") end },
                        { label = "Act", fn = function() ui.say("Sent", "busy", { action = { label = "Undo", fn = function() _G.undone = _G.undone + 1 end } }) end } })
    end)
  ]])
  c:run("t"); world:run(0.5)
  local scr = c.screen
  T.contains(scr:line(2), "Order failed"); T.eq(fg(scr, 3, 2), COL.red)
  world:run(30)
  T.contains(scr:line(2), "Order failed", "errors do not expire")
  tap(world, c, 4, 4)                                    -- the next notice replaces it
  T.contains(scr:line(2), "Done"); T.eq(fg(scr, 3, 2), COL.lime)
  tap(world, c, inRow(scr, 4, "Act") + 1, 4)
  T.contains(scr:line(2), "Sent")
  local ux = inRow(scr, 2, " Undo ")
  T.truthy(ux, "the action is drawn at the right")
  tap(world, c, ux + 2, 2)
  T.eq(c.env._G.undone, 1)
  T.eq(scr.ch[2][1], RULE, "running the action dismisses the notice")
end)

---------------------------------------------------------------------------------------------------------
T.test("ui: no colour: [ Label ] buttons, - rule, bracketed chip, no crash", function()
  local world, c = demo(51, 19, { colour = false })
  local scr = c.screen
  T.running(c)
  T.eq(inRow(scr, 1, "[DEMO]"), 1)
  T.eq(scr.ch[2][1], "-"); T.eq(scr.ch[2][51], "-")
  T.truthy(inRow(scr, 4, "[ Pause ]"), "primary")
  T.truthy(inRow(scr, 4, "[ Reboot ]"))
  T.truthy(inRow(scr, 4, "[ Forget ]"))
  T.absent(scr:line(5), "[ Off ]", "disabled has no brackets")
  T.truthy(inRow(scr, 5, "Off"))
  T.truthy(inRow(scr, 19, "[ < ] Back"))
  tap(world, c, 6, 4)
  T.eq(c.env._G.demo.paused, true, "taps work without colour")
  local fx = inRow(scr, 4, "Forget")
  tap(world, c, fx + 1, 4)
  T.truthy(inRow(scr, 4, "[ Sure?"), "armed")
end)

T.test("ui: a monitor gets text scale 0.5 and its own taps; notices go to every view", function()
  local world, c, mon = demo(51, 19, { monitor = { 36, 24 } })
  T.eq(mon.scale, 0.5, "monitor text scale")
  T.eq(c.screen.scale, 1, "the computer's own screen is left alone")
  T.eq(mon:paletteHex(COL.yellow), 0xF2B71F, "monitor palette")
  T.truthy(inRow(mon, 4, " Pause "), "monitor drawn")
  mon:touch(4, 4); world:run(0.2)
  T.eq(c.env._G.demo.paused, true, "monitor_touch on the monitor view")
  T.contains(mon:line(1), "waiting"); T.contains(c.screen:line(1), "waiting", "both views redraw")
  local mx = inRow(mon, 4, "Reboot")
  mon:touch(mx + 1, 4); world:run(0.2)
  T.contains(mon:line(2), "Reboot sent"); T.contains(c.screen:line(2), "Reboot sent", "the same notice on every view")
  tap(world, c, 4, 4)                                    -- a click on the computer does not tap the monitor view
  T.eq(c.env._G.demo.paused, false)
end)

T.test("ui: resize redraws at the new size class", function()
  local world, c = demo(51, 19)
  T.truthy(inRow(c.screen, 19, "Back"))
  c:resize(26, 20); world:run(0.3)
  T.running(c)
  T.absent(c.screen:line(20), "Back")
  T.truthy(inRow(c.screen, 4, "Boot"), "narrow labels after the resize")
  T.eq(c.screen.ch[2][26], RULE)
  c:resize(39, 13); world:run(0.3)
  T.eq(c.screen.ch[2][39], RULE)
  T.truthy(inRow(c.screen, 13, " < "), "footer moved to the new last row")
end)
