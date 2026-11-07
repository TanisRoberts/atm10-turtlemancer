-- server.lua  --  the server room board (docs/design/server.md, docs/systems/server.md, #127).
-- An advanced computer on the storage cable. It reads the same ME Bridge and draws the drive room on a big monitor
-- (picked with shared/screens.lua). Display only: it never moves an item.
--   * server_layout.lua  works the walls / banks / racks out from getDrives() positions
--   * server_board.lua   draws a model on a UI-kit view
--   * this file          reads the bridge in the background (cache, never on the draw path), listens for storage's
--                        defrag broadcast, and runs the screens
local ui = require("ui")
local slash = require("slash")
local layout = require("server_layout")
local board = require("server_board")

local BASE = "tanis-base"
local DRIVES_EVERY, ITEMS_EVERY = 5, 30       -- seconds

---------------------------------------------------------------------------
-- server.env: the room's size, and FLIP_n to mirror a wall that comes out backwards
---------------------------------------------------------------------------
local env = require("envfile").new("server.env", "Server room board settings.", {
  { "BANKS", 2, "Banks in the room (two walls facing each other)." },
  { "WALLS_PER_BANK", 2, "Walls in a bank." },
  { "RACKS_PER_WALL", 3, "Racks along a wall." },
  { "RACK_COLS", 2, "Drive columns in a rack." },
  { "RACK_ROWS", 5, "Drive rows in a rack." },
  { "RACK_GAP", "", "Blocks between racks on a wall. Blank = worked out from the drives; a number overrides (for a room with one built rack)." },
  { "FLIP_1", 0, "1 = draw wall 1 (board order) the other way round. Same for FLIP_2 to FLIP_4." },
  { "FLIP_2", 0, "" }, { "FLIP_3", 0, "" }, { "FLIP_4", 0, "" },
})
env.load()
ui.loadAnim("server.env")

local function config()
  local v = env.v
  local flip = {}
  for n = 1, 4 do if v["FLIP_" .. n] == 1 then flip[n] = true end end
  return { banks = v.BANKS, wallsPerBank = v.WALLS_PER_BANK, racksPerWall = v.RACKS_PER_WALL,
           rackCols = v.RACK_COLS, rackRows = v.RACK_ROWS, rackGap = tonumber(v.RACK_GAP), flip = flip }
end

---------------------------------------------------------------------------
-- The model the board draws. Only the background loops below write to it.
---------------------------------------------------------------------------
local M = { room = layout.build({}, config()), online = false, seen = false, now = os.clock() }

local function prettyName(it)
  local n = it.displayName
  if type(n) == "string" and n ~= "" then return (n:gsub("^%[(.*)%]$", "%1")) end
  n = tostring(it.name or "?"):gsub("^[^:]*:", ""):gsub("_", " ")
  return (n:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

local function readItems(bridge)
  local items = bridge.getItems()
  if type(items) ~= "table" then return false end
  -- infinity cells report 2^31-1 of an item: not a real pile, left out of the totals and the biggest list
  local real = {}
  for _, it in ipairs(items) do if (it.count or 0) < 2147483647 then real[#real + 1] = it end end
  items = real
  local total = 0
  for _, it in ipairs(items) do total = total + (it.count or 0) end
  table.sort(items, function(a, b) return (a.count or 0) > (b.count or 0) end)
  local piles = {}
  for i = 1, math.min(8, #items) do piles[i] = { name = prettyName(items[i]), count = items[i].count or 0 } end
  M.kinds, M.items, M.piles = #items, total, piles
  return true
end

local lastItems = -1e9
local function readOnce()
  env.refresh()
  local bridge = peripheral.find("me_bridge")
  local ok, drives = false, nil
  if bridge then
    local c, o = pcall(function() return bridge.isConnected() and bridge.isOnline() end)
    if c and o then
      local g, list = pcall(bridge.getDrives)
      if g and type(list) == "table" then ok, drives = true, list end
    end
  end
  if ok then
    M.room = layout.build(drives, config())
    M.online, M.seen = true, true
    local c1, stored = pcall(bridge.getStoredEnergy)
    local c2, cap = pcall(bridge.getEnergyCapacity)
    local c3, usage = pcall(bridge.getEnergyUsage)
    if c1 and c2 and c3 and tonumber(stored) and tonumber(cap) then
      M.energy = { stored = stored, cap = cap, usage = tonumber(usage) or 0 }
    end
    if os.clock() - lastItems >= ITEMS_EVERY then
      lastItems = os.clock()
      pcall(readItems, bridge)
    end
  else
    M.online = false              -- the last data stays on screen, dimmed
  end
  os.queueEvent("server_data")
end

local function readLoop()
  while true do
    pcall(readOnce)
    os.sleep(DRIVES_EVERY)
  end
end

-- storage's defrag progress on the base protocol
local netOn = false
local function netLoop()
  if not netOn then return os.pullEvent("never") end
  while true do
    local _, msg = rednet.receive(BASE)
    if type(msg) == "table" and msg.type == "defrag" then
      M.defrag = { msg = msg, at = os.clock() }
      os.queueEvent("server_data")
    end
  end
end

---------------------------------------------------------------------------
-- Screens: the computer's own and the monitor (shared/screens.lua)
---------------------------------------------------------------------------
local scr = require("screens").new({ slots = { { id = "wall", label = "the server room board", required = false, scale = 0.5 } } })
scr:open()
local function repickMonitor() scr:repick("wall"); os.reboot() end

local views = { ui.view(term.current()) }
local function syncMonitor()
  local mon, name = scr:current("wall")
  if views[2] and views[2].side == name then views[2].t = mon or views[2].t; views[2]:measure(); return end
  views[2] = mon and ui.view(mon, { side = name }) or nil
end

local cmds = slash.new()
cmds:add({ name = "monitors", help = "pick the monitor again (reboots)", max = 0,
  run = function() repickMonitor() end })
local field
field = ui.field{ hint = "type a command, / lists them", max = 60,
  on_commit = function(t) field.text = ""; if not t:match("^%s*$") then cmds:exec(t) end end }

local lastErr
local function draw(v)
  M.now = os.clock()
  local ok, err = pcall(board.draw, v, M, { reserve = v.side and 0 or 2 })
  if not ok and err ~= lastErr then lastErr = err; ui.say("Screen error: " .. tostring(err), "bad") end
  if not v.side then v:search(field, { commands = cmds:commands() }) end
end

local function screenLoop()
  syncMonitor()
  ui.run(views, draw, { tick = 1, on_event = function(e, ...)
    scr:handle(e, ...)
    if e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then syncMonitor() end
  end })
end

peripheral.find("modem", function(name, m)
  if m.isWireless and m.isWireless() then rednet.open(name); netOn = true end
  return false
end)
scr:get("wall")
parallel.waitForAny(readLoop, netLoop, screenLoop)
