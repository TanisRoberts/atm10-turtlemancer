-- tests/demo/ui_demo.lua  --  a small demo screen built only from the UI kit's core components
-- (header, buttons, tap-twice confirm, stepper, notices, footer). The scenarios in tests/scenarios/ui_core.lua
-- run it at every screen size; #15 and the Farmhand pilot can copy its shape. State is in _G.demo for tests.
local ui = require("ui")

local demo = { depth = 40, paused = false, pending = false, reboots = 0, forgotten = 0, backs = 0, stateTaps = 0 }
_G.demo = demo

local views = { ui.view(term.current()) }
demo.view = views[1]
local mon = peripheral.wrap("right")
if mon then views[#views + 1] = ui.view(mon, { side = "right" }) end

local function draw(v)
  v:header("Demo", { state = demo.paused and "waiting" or "working", right = "3 canaries, storage ok",
                     onState = function() demo.stateTaps = demo.stateTaps + 1 end })
  local _, y = v:buttons(2, 4, {
    { label = "Pause", style = "primary", key = "p", fn = function() demo.paused = not demo.paused end },
    { label = "Reboot", short = "Boot", fn = function()
        demo.reboots = demo.reboots + 1; ui.say("Reboot sent to Canary-04: it finishes its block", "busy") end },
    { label = "Forget", style = "danger", confirm = true, fn = function()
        demo.forgotten = demo.forgotten + 1; ui.say("Forgot Canary-04", "good") end },
  })
  v:buttons(2, y + 1, { { label = "Off", style = "disabled", fn = function() demo.off = true end } })
  v:stepper(2, y + 3, "Mine depth", demo.depth, { min = 0, max = 60, pending = demo.pending,
    on = function(n) demo.depth = n; demo.pending = true end })
  v:footer({ back = function() demo.backs = demo.backs + 1; ui.quit() end })
end

ui.run(views, draw)
for _, v in ipairs(views) do v:close() end
