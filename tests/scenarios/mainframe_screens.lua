-- The mainframe picks its wall with shared/screens.lua (#99): a touching monitor wins as before; with none touching,
-- the monitors on the cable are numbered, a tap picks, a reboot remembers, `$island monitors` asks again.
local cc = require("sim.cc")
local T  = require("sim.test")

local function envDetector() return { types = { "environment_detector" }, peripheralMethods = {} } end
local function chatBox() return { types = { "chat_box" }, peripheralMethods = { "sendMessage" }, sent = {},
  sendMessage = function(self, ...) end } end

-- opts: touching = {w, h} for a monitor on the computer's own side
local function build(opts)
  opts = opts or {}
  local w = cc.world()
  local net = w:net()
  local big = net:monitor("monitor_12", 57, 24)
  local small = net:monitor("monitor_13", 15, 10)
  local mf = w:computer{ id = 1, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  mf:attach("back", cc.wired(net))
  mf:attach("right", envDetector())
  local touching = opts.touching and mf:monitor("bottom", opts.touching[1], opts.touching[2])
  mf:installRole("mainframe")
  mf.files["butler.lua"] = nil
  mf:run("mainframe")
  return w, mf, big, small, touching
end

T.test("mainframe screens: a touching monitor is the wall, no prompt, the cable monitors left alone", function()
  local w, mf, big, small, touching = build{ touching = { 57, 24 } }
  w:run(20)
  T.eq(mf.error, nil)
  T.contains(touching, "MACHINES")
  T.absent(mf.screen, "Pick")
  T.absent(big, "Tap to pick")
  T.falsy(mf:readFile("monitors.cfg"), "nothing saved")
end)

T.test("mainframe screens: no touching monitor, both on the cable are numbered, a tap picks, a reboot goes straight back", function()
  local w, mf, big, small = build()
  w:run(3)
  T.contains(mf.screen, "1 monitor_12 (57x24)")
  T.contains(mf.screen, "2 monitor_13 (15x10)")
  T.contains(big, "Tap to pick the main wall")
  big:touch(10, 10)
  w:run(15)
  T.eq(mf.error, nil)
  T.contains(big, "MACHINES")
  T.eq(small:text(), "", "the other monitor is blank")
  T.eq(mf:readFile("monitors.cfg"), "wall=monitor_12\n")
  mf:reboot()
  mf:run("mainframe")
  w:run(15)
  T.absent(mf.screen, "Pick")
  T.contains(big, "MACHINES")
  T.eq(small:text(), "")
end)

T.test("mainframe screens: $island monitors forgets the pick and asks again after the reboot", function()
  local w, mf, big, small = build()
  local chat = chatBox()
  mf:attach("left", chat)
  w:run(3)
  big:touch(10, 10)
  w:run(15)
  T.contains(big, "MACHINES")
  mf:queue("chat", "00000000-0000-0000-0000-000000000000", "Tanis", "$island monitors", false)
  w:run(3)
  T.falsy((mf:readFile("monitors.cfg") or ""):find("monitor_12", 1, true), "the pick is forgotten")
  mf:run("mainframe")
  w:run(3)
  T.contains(mf.screen, "Pick the main wall")
end)
