-- tests/demo/ui_demo2.lua  --  demo of the UI kit's part 2 components: tabs and paging, tiles, bars, a paged
-- list with a search and command bar, a text field, and a map. tests/scenarios/ui_more.lua drives it.
-- State is in _G.d2. demo2.cfg (optional) picks the first tab and how many tiles / list rows there are.
local ui = require("ui")
local cfg = { tab = "tiles", tiles = 7, rows = 30 }
if fs.exists("demo2.cfg") then
  local f = fs.open("demo2.cfg", "r"); for k, v in pairs(textutils.unserialise(f.readAll())) do cfg[k] = v end; f.close()
end
local d2 = { tab = cfg.tab, opened = nil, picked = nil, cmd = nil, backs = 0 }
_G.d2 = d2

local STATES = { "working", "waiting", "returning", "lost", "rebooting", "docked", "working" }
local items = {}
for i = 1, cfg.tiles do
  items[i] = { name = ("Canary-%02d"):format(i), state = STATES[(i - 1) % #STATES + 1], fuel = (i * 17 % 100) / 100,
               cargo = i % 17, y = -40 + i }
end
local rows = {}
for i = 1, cfg.rows do
  rows[i] = { name = ("Item number %02d"):format(i), value = i * 100 + 4, state = ({ "good", "warn", "bad" })[i % 3 + 1], id = i }
end
rows[2].name = "A very long item name that cannot possibly fit on a narrow screen"

local filter = ui.field{ hint = "search" }
local name = ui.field{ hint = "name of the turtle", max = 16,
  validate = function(t) if t:find(" ", 1, true) then return "no spaces" end end,
  on_commit = function(t) d2.named = t end }
local TABS = { { id = "tiles", label = "Tiles" }, { id = "list", label = "List", star = true }, { id = "map", label = "Map" },
               { id = "form", label = "Form" } }

local function terrain(x, z)
  if x < 0 or z < 0 then return nil end
  if x == 12 and z == 9 then return { "soil", " ", "Wheat, 7/7 grown" } end
  if x > 14 then return "water" end
  if z > 12 then return "good2" end
  return "bar"
end

local mon = peripheral.wrap("right")
local views = { ui.view(term.current()) }
if mon then views[2] = ui.view(mon, { side = "right" }) end

ui.run(views, function(v)
  v:header("Demo2", { state = "working" })
  if d2.tab == "tiles" then
    v:tiles(items, { on = function(it) d2.opened = it.name end, render = function(it)
      return { name = it.name, state = it.state, activity = "Digging to Y " .. it.y, fuel = it.fuel,
               numbers = ("Cargo %d/16   Y %d"):format(it.cargo, it.y), seen = "seen 2s ago",
               stale = it.state == "lost" and "3m" or nil }
    end })
  elseif d2.tab == "list" then
    local shown = {}
    for _, r in ipairs(rows) do
      if filter.text:sub(1, 1) == "/" or r.name:lower():find(filter.text:lower(), 1, true) then shown[#shown + 1] = r end
    end
    v:list(shown, { input = true, on = function(r) d2.opened = r.name end })
    v:search(filter, { commands = {
      { name = "reboot", help = "reboot a turtle", fn = function(a) d2.cmd = "reboot " .. a end },
      { name = "refuel", help = "send fuel to a turtle", fn = function(a) d2.cmd = "refuel " .. a end },
      { name = "retire", help = "retire a number for good", fn = function(a) d2.cmd = "retire " .. a end } } })
  elseif d2.tab == "map" then
    v:map({ get = terrain, at = { x = 10, z = 10, facing = 1 } })
  else
    v:field(2, 4, "Name", 20, name)
    v:bar(2, 8, math.min(40, v.W - 3), "Layer", 0.37, { kind = "progress", text = "37/100" })
    v:bar(2, 9, math.min(40, v.W - 3), "Slots", 0.95, { kind = "cap" })
  end
  v:footer({ back = function() d2.backs = d2.backs + 1; ui.quit() end, tabs = TABS, tab = d2.tab,
           on_tab = function(id) d2.tab = id end })
end)
