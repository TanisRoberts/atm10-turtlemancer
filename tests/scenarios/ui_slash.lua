-- Typed "/" commands (shared/slash.lua): parsing, arguments, errors, help; and the Farmhand as the demo user.
local cc = require("sim.cc")
local T  = require("sim.test")
local KEYS = require("sim.env").keys

local function mod()
  local env = setmetatable({ print = print }, { __index = _G })
  return assert(loadfile(cc.ROOT .. "/shared/slash.lua", "t", env))()
end

-- A set shaped like the Cartographer's (#67): /goto x z, /next x,z | clear, /status, /map.
local function cart(slash)
  local shown, got = {}, {}
  local cmds = slash.new({ say = function(text, tone) shown[#shown + 1] = { text, tone } end })
  cmds:add({ name = "status", help = "one line", max = 0, run = function() return true, "all fine" end })
  cmds:add({ name = "map", help = "show the map", run = function() got.map = true; return true end })
  cmds:add({ name = "goto", args = "x z", min = 2, max = 2, help = "go to x z",
             run = function(a)
               local x, z = a:xz(1)
               if not x then return false, z end
               got.go = { x, z }; return true, ("going to %d %d"):format(x, z)
             end })
  cmds:add({ name = "next", args = "x,z | clear", min = 1, max = 2, help = "next dock",
             run = function(a)
               if a:is(1, "clear") then got.next = "clear"; return true, "cleared" end
               local x, z = a:xz(1)
               if not x then return false, z end
               got.next = { x, z }; return true, "next set"
             end })
  return cmds, shown, got
end

T.test("slash: with and without the slash, any case, extra spaces", function()
  local cmds, shown, got = cart(mod())
  T.truthy(cmds:exec("/map")); T.truthy(got.map); got.map = nil
  T.truthy(cmds:exec("map")); T.truthy(got.map); got.map = nil
  T.truthy(cmds:exec("  /MAP  ")); T.truthy(got.map)
  T.eq(#shown, 0, "a handler with no text shows nothing")
  T.truthy(cmds:exec("/status")); T.eq(shown[1][1], "all fine"); T.eq(shown[1][2], "good")
end)

T.test("slash: arguments as x z, x,z, negatives and quotes", function()
  local slash = mod()
  local cmds, shown, got = cart(slash)
  cmds:exec("/goto 10 -5"); T.eq(got.go[1], 10); T.eq(got.go[2], -5)
  cmds:exec("/next -120,35"); T.eq(got.next[1], -120); T.eq(got.next[2], 35)
  cmds:exec("/next clear"); T.eq(got.next, "clear")
  cmds:exec("/next CLEAR"); T.eq(got.next, "clear")
  local _, words = slash.parse('say "two words" x')
  T.eq(#words, 2); T.eq(words[1], "two words")
end)

T.test("slash: bad arguments show the usage line, the handler's message first", function()
  local cmds, shown, got = cart(mod())
  T.falsy(cmds:exec("/goto 10"))
  T.contains(shown[1][1], "Usage: /goto x z"); T.eq(shown[1][2], "warn")
  T.falsy(cmds:exec("/goto 1 2 3")); T.contains(shown[2][1], "Usage: /goto x z")
  T.falsy(cmds:exec("/goto ten 5")); T.contains(shown[3][1], "'ten' is not a whole number"); T.contains(shown[3][1], "/goto x z")
  T.falsy(cmds:exec("/next 5,x")); T.contains(shown[4][1], "not x,z")
  T.falsy(cmds:exec("/next")); T.contains(shown[5][1], "/next x,z | clear")
  T.eq(got.go, nil, "the handler never ran")
  T.falsy(cmds:exec("/status now")); T.contains(shown[6][1], "Usage: /status")
end)

T.test("slash: unknown command and /help list the commands", function()
  local cmds, shown = cart(mod())
  T.falsy(cmds:exec("/frobnicate"))
  T.contains(shown[1][1], "Unknown command /frobnicate"); T.contains(shown[1][1], "/goto x z"); T.contains(shown[1][1], "/help")
  T.falsy(cmds:exec("")); T.contains(shown[2][1], "Type a command")
  T.truthy(cmds:exec("/help")); T.contains(shown[3][1], "/status"); T.contains(shown[3][1], "/next x,z | clear")
  T.truthy(cmds:exec("help goto")); T.contains(shown[4][1], "go to x z")
  T.falsy(cmds:exec("help nope")); T.contains(shown[5][1], "No command nope")
end)

T.test("slash: a crashing handler is reported, a screen can replace /help, the kit gets a command list", function()
  local slash = mod()
  local cmds, shown = cart(slash)
  cmds:add({ name = "boom", help = "x", run = function() error("kaput") end })
  T.falsy(cmds:exec("/boom")); T.contains(shown[1][1], "/boom failed"); T.eq(shown[1][2], "bad")
  cmds:add({ name = "help", help = "mine", run = function() return true, "my help" end })
  cmds:exec("/help"); T.eq(shown[2][1], "my help")
  local n = 0
  for _, c in ipairs(cmds:commands()) do if c.name == "help" then n = n + 1 end end
  T.eq(n, 1, "one /help")
  local list = cmds:commands()
  T.eq(list[1].name, "status"); T.truthy(list[1].fn)
  local go = list[3]; T.eq(go.name, "goto"); T.contains(go.help, "x z")
  go.fn("4 5"); T.eq(shown[#shown][1], "going to 4 5")
end)

-- The Farmhand: type on the computer terminal, not on a monitor
local function farmhand(mon)
  local w = cc.world()
  local fh = w:computer{ id = 1, label = "Farmhand", w = 51, h = 19 }
  fh:attach("top", cc.wireless{ ender = true })
  local m = mon and fh:monitor("right", 57, 24)
  fh:installRole("farmhand")
  fh:run("farmhand")
  w:run(5)
  return w, fh, m
end

T.test("slash: Farmhand terminal takes /status and /help; a monitor shows no command bar", function()
  local w, fh, mon = farmhand(true)
  local scr = fh.screen
  T.running(fh)
  T.contains(scr:line(18), "/ = commands")
  T.absent(mon:text(), "/ = commands", "the wall monitor has no keyboard")
  fh:type("/"); w:run(0.3)
  T.contains(scr:text(), "/status"); T.contains(scr:text(), "/help")
  fh:type("status"); w:run(0.3)
  fh:key(KEYS.enter); w:run(0.3)
  T.contains(scr:line(2), "no farm turtles yet")
  fh:type("/help"); w:run(0.3); fh:key(KEYS.enter); w:run(0.3)
  T.contains(scr:line(2), "/status")
  T.contains(scr:line(2), "/help")
end)
