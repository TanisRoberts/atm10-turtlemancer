-- tests/demo/ui_demo3.lua  --  demo of the UI kit's part 3 components (shared/ui_parts.lua): section, key-value,
-- alert, segmented switch, board, picker card, report page, spinner line. tests/scenarios/ui_parts.lua drives it.
-- demo3.cfg picks the screen (parts, board, picker, report, wait). State is in _G.d3.
local ui = require("ui")
local cfg = { screen = "parts" }
if fs.exists("demo3.cfg") then
  local f = fs.open("demo3.cfg", "r"); for k, v in pairs(textutils.unserialise(f.readAll())) do cfg[k] = v end; f.close()
end
local d3 = { mode = "AUTO", rule = "none", sort = "qty", picked = nil, moved = nil, backs = 0, ages = { 2, 3, 2, 45 } }
_G.d3 = d3

local picker = ui.picker{ question = "Which role?", hint = "up/down browse",
  items = {
    { id = "foreman", name = "Foreman", tag = nil, lines = { "Runs the Overworld miners." } },
    { id = "mainframe", name = "Mainframe", tag = "suggested",
      text = "The server. Chat commands and alerts, an island strip showing every machine, and the board that lists them all with top-ups, welcomes, visitors and more." },
    { id = "storage", name = "Storage", lines = { "The only computer that moves items." } },
  }, index = 2,
  on_pick = function(it) d3.picked = it.id end, on_move = function(it) d3.moved = it.id end }

local mon = peripheral.wrap("right")
local views = { ui.view(term.current()) }
if mon then views[2] = ui.view(mon, { side = "right" }) end

local function back() d3.backs = d3.backs + 1 end

ui.run(views, function(v)
  local W = v.W
  if cfg.screen == "parts" then
    v:header("Parts", { state = "working" })
    local y = v:section(2, 4, W - 2, "Layers")
    y = v:kv(2, y, W - 2, "Plan", "island_v3  54,200 blocks")
    y = v:kv(2, y, W - 2, "Missing a very long key that has to be cut", "none (storage has it all)", "good")
    y = v:alert(2, y, W - 2, "No OUTPUT yet: items cannot be taken out.", "warn")
    y = v:alert(2, y, W - 2, "Tap #4 is dry: its log is used up.", "bad")
    y = y + 1
    local _, ly = v:switch(2, y, { "AUTO", "ON", "OFF" }, d3.mode, function(id) d3.mode = id end)
    y = ly + 2
    local _, ly2 = v:switch(2, y, { { id = "none", label = "No rule", short = "None" },
      { id = "keep", label = "Keep N stacks", short = "Keep" }, { id = "all", label = "Smelt all", short = "All" } },
      d3.rule, function(id) d3.rule = id end)
    d3.switchRows = { y, ly2 }
    v:footer({ back = back })
  elseif cfg.screen == "board" then
    v:header("Board", { state = "ok" })
    v:board(2, 4, W - 2, { title = "Machines",
      { name = "Storage", state = "ok", detail = "79% full", age = d3.ages[1] },
      { name = "Smelter", state = "ok", detail = "6 cooking", age = d3.ages[2] },
      { name = "Plastic", state = "running", detail = "1,204 made", age = d3.ages[3] },
      { name = "Neural", state = "ok", detail = "idle", age = d3.ages[4] } })
  elseif cfg.screen == "picker" then
    v:header("Setup", { state = "step 2 of 3", color = "dim" })
    v:footer({ back = back })
    v:picker(picker)
  elseif cfg.screen == "report" then
    local rows = { { section = "Plan" }, { key = "Plan", value = "island_v3" }, { key = "Missing", value = "none" },
                   { section = "Links" }, { key = "Barrels", value = "not linked yet", tone = "warn" },
                   { alert = "GPS is counting moves", tone = "warn" } }
    for i = 1, tonumber(cfg.extra) or 0 do rows[#rows + 1] = { key = "Row " .. i, value = i } end
    v:report({ title = "Fuel info", state = "ok", rows = rows, back = back })
  else
    v:header("Storage", { state = "waiting" })
    v:spinner_line(4, 5, "Waiting for storage")
    v:footer({ back = back })
  end
end, { tick = cfg.screen == "wait" and 0.25 or 1 })
