-- `$island seagull`: the mainframe says where Seagull is. Real Cartographer + mainframe chat + a stand-in Seagull.
local cc = require("sim.cc")
local T  = require("sim.test")

local UUID = "00000000-0000-0000-0000-000000000001"
local function chatBox()
  return { types = { "chat_box" }, peripheralMethods = { "sendMessage" }, sent = {},
    sendMessage = function(self, msg, opts) self.sent[#self.sent + 1] = { msg = msg, player = opts and opts.player }; return true end }
end

local function build(o)
  o = o or {}
  local w = cc.world()
  local mf = w:computer{ id = 1, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  local chat = chatBox()
  mf:attach("left", chat); mf:attach("right", { types = { "environment_detector" }, peripheralMethods = {} })
  mf:installRole("mainframe")
  mf:writeFile("launch.lua", [[
    local function sb() local e = { require = require }; return e end
    parallel.waitForAll(
      function() os.run(sb(), "island.lua") end,
      function() os.run({ require = require }, "base_link.lua") end)
  ]])
  mf:run("launch")
  local c
  if o.cartographer ~= false then
    c = w:computer{ id = 10, label = "Cartographer", w = 51, h = 19 }
    c:attach("top", cc.wireless{ ender = true })
    c:monitor("right", 164, 81)
    c:installRole("cartographer")
    c:writeFile("startup.lua", 'shell.run("cartographer")')
    c:run("cartographer")
  end
  local s
  if o.seagull ~= false then
    s = w:computer{ id = 20, label = "Seagull-01" }
    s:attach("top", cc.wireless{ ender = true })
    s:install("tests/demo/seagull_stub.lua"); s:install("shared/mapchunk.lua")
    s:writeTable("stub.cfg", { regions = {}, status = { type = "status", role = "cartographer", label = "Seagull-01",
      state = "mapping", msg = "Region", fuel = 54000, fuelLimit = 80000, mapping = true, wp = 40, wps = 256,
      home = { x = 100, y = 64, z = 100 }, pos = { x = 702, y = 64, z = -1736 } } })
    s:run("seagull_stub")
  end
  return w, mf, c, s, chat
end
local function ask(w, mf, text) mf:queue("chat", UUID, "Tanis", text, false); w:run(6) end
local function last(chat) local m = chat.sent[#chat.sent]; return m and m.msg or "" end

T.test("island seagull: live position, region, chunk and fuel", function()
  local w, mf, c, s, chat = build()
  w:run(15)
  ask(w, mf, "$island seagull")
  local m = last(chat)
  T.contains(m, "Seagull-01 mapping at 702 64 -1736")
  T.contains(m, "fuel 54,000")
  T.contains(m, "Region 2,-7")
  T.contains(m, "chunk 40/256")
  ask(w, mf, "$island carto"); T.contains(last(chat), "702 64 -1736")
end)

T.test("island seagull: gone quiet, it gives the last-heard position and how long ago", function()
  local w, mf, c, s, chat = build()
  w:run(15)
  s:_stop()
  w:run(14 * 60)
  ask(w, mf, "$island seagull")
  local m = last(chat)
  T.contains(m, "last heard 14 min ago at 702 64 -1736")
  T.contains(m, "mapping Region")
end)

T.test("island seagull: a rebooted Cartographer still reports the last-heard position", function()
  local w, mf, c, s, chat = build()
  w:run(15)
  s:_stop(); c:_stop()
  w:run(120)
  c:run("cartographer")
  w:run(20)
  ask(w, mf, "$island seagull")
  T.contains(last(chat), "last heard")
  T.contains(last(chat), "702 64 -1736")
end)

T.test("island seagull: no Cartographer on the air says so", function()
  local w, mf, c, s, chat = build{ cartographer = false, seagull = false }
  w:run(10)
  ask(w, mf, "$island seagull")
  T.contains(last(chat), "No Cartographer on the air")
end)
