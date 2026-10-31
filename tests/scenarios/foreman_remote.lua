-- The Overworld Foreman as the remote for every miner: the MD Foreman takes over the Canary list once, every
-- miner shows with its dimension, and orders go through each miner's own Foreman (one brain per miner).
-- Stand-in miners (tests/sim/miners.lua) talk like real ones.
local cc = require("sim.cc")
local T = require("sim.test")
local MS = require("sim.miners")

-- Overworld Foreman (1) with an old foreman.cfg (Canary-01, a retired Canary-02, Starling-03), the Nether
-- Foreman (2) and the MD Foreman (3), and stand-ins: Canary-01 (7), Firecrest-01 (9), Starling-03 (12).
local function world(o)
  o = o or {}
  local w = cc.world()
  local hub = w:computer{ id = 1, label = "Foreman" }
  hub:attach("top", cc.wireless{ ender = true })
  local hubMon = hub:monitor("right", 57, 24)
  hub:installRole("foreman")
  hub:writeTable("foreman.cfg", { nextNum = 4, chunkRings = true, retiredNums = { [2] = "Canary-02" }, canaries = {
    [7] = { num = 1, label = "Canary-01", want = "dock", minY = -59, maxY = -58, pMin = -59, pMax = -58, r1 = 0, r2 = 3, pR1 = 0, pR2 = 3, seq = 1 },
    [8] = { num = 2, label = "Canary-02", retired = true, want = "dock", minY = -59, maxY = -58, pMin = -59, pMax = -58, r1 = 0, r2 = 3, pR1 = 0, pR2 = 3, seq = 1 },
    [12] = { num = 3, label = "Starling-03", want = "dock", minY = 10, maxY = 20, pMin = 10, pMax = 20, r1 = 0, r2 = 1, pR1 = 0, pR2 = 1, seq = 1 },
  } })
  hub:run("foreman")

  local function dimForeman(id, role, label)
    local net = w:net()
    net:add("minecraft:barrel_" .. id, MS.barrel())
    local c = w:computer{ id = id, label = label }
    c:attach("back", cc.wired(net))
    c:attach("top", cc.wireless{ ender = true })
    local mon = c:monitor("right", 57, 24)
    c:installRole(role)
    return c, mon
  end
  local nether, netherMon = dimForeman(2, "nether", "Nether Foreman")
  nether:writeTable("nether.cfg", { docks = { "minecraft:barrel_2" } })
  nether:run("nether")
  local md, mdMon
  if not o.noMD then
    md, mdMon = dimForeman(3, "mdforeman", "MD Foreman")
    md:writeTable("mdforeman.cfg", { docks = { "minecraft:barrel_3" } })
    md:run("mdforeman")
  end

  local canary = MS.standIn(w, { id = 7, num = 1, label = "Canary-01", protocol = "tanis-miner", bird = "Canary",
    kind = "canary", dim = "allthemodium:mining" })
  local firecrest = MS.standIn(w, { id = 9, protocol = "tanis-nether" })
  local starling = MS.standIn(w, { id = 12, num = 3, label = "Starling-03", protocol = "tanis-miner", bird = "Starling",
    kind = "starling", dim = "the_end" })
  w:run(o.settle or 15)
  return { w = w, hub = hub, hubMon = hubMon, nether = nether, netherMon = netherMon, md = md, mdMon = mdMon,
           canary = canary, firecrest = firecrest, starling = starling }
end

local function tapOn(w, mon, text, last)
  local a, z, step = 3, mon.h, 1
  if last then a, z, step = mon.h, 3, -1 end
  for row = a, z, step do
    local x = mon:line(row):find(text, 1, true)
    if x then mon:touch(x, row); w:run(1); return end
  end
  error("no " .. text .. " on the monitor:\n" .. mon:text(), 2)
end

T.test("remote: the MD Foreman takes over the Canary list once, numbers and retired numbers kept", function()
  local e = world()
  T.running(e.hub); T.running(e.md)
  local md = e.md:readTable("mdforeman.cfg")
  T.eq(md.imported, true)
  T.eq(md.canaries[7].num, 1); T.eq(md.canaries[7].label, "Canary-01")
  T.eq(md.canaries[8].retired, true)
  T.eq(md.canaries[12], nil, "the Starling stays with the Overworld Foreman")
  T.eq(md.retiredNums[2], "Canary-02")
  T.eq(md.nextNum, 4)
  local hub = e.hub:readTable("foreman.cfg")
  T.eq(hub.handedOver, true)
  T.eq(hub.canaries[7], nil, "not mine any more")
  T.eq(hub.canaries[12].label, "Starling-03")
  -- a new Canary gets the next number from the MD Foreman, never a retired one
  local c2 = MS.standIn(e.w, { id = 20, protocol = "tanis-miner", bird = "Canary", kind = "canary", dim = "allthemodium:mining" })
  e.w:run(5)
  T.eq(c2.label, "Canary-04")
  T.eq(e.md:readTable("mdforeman.cfg").canaries[20].num, 4)
end)

T.test("remote: every miner shows on the Overworld Foreman with its dimension", function()
  local e = world()
  local mon = e.hubMon
  T.contains(mon, "FOREMAN")
  T.contains(mon, "3 miners")
  T.contains(mon, "Canary-01")
  T.contains(mon, "Firecrest-01")
  T.contains(mon, "Starling-03")
  T.contains(mon, "Mining")
  T.contains(mon, "Nether")
  T.contains(mon, "End")
  T.contains(mon:line(1), "ok")                      -- every dimension Foreman heard
  T.absent(mon, "Canary-02")
end)

T.test("remote: START a Canary through the MD Foreman and a Firecrest through the Nether Foreman", function()
  local e = world()
  e.canary.G.senders = {}
  e.firecrest.G.senders = {}
  tapOn(e.w, e.hubMon, "Canary-01")
  T.contains(e.hubMon, "CANARY-01")
  T.contains(e.hubMon, "MD Foreman")                 -- whose he is
  tapOn(e.w, e.hubMon, "START", true)
  e.w:run(2)
  T.contains(e.mdMon, "Canary-01: START from the Overworld Foreman.")
  e.w:run(3)
  T.eq(e.canary.G.want, "run")
  T.eq(e.canary.G.lastCmd.kind, "canary")
  T.eq(e.canary.G.lastCmd.minY, -59)
  T.eq(e.md:readTable("mdforeman.cfg").canaries[7].want, "run")
  tapOn(e.w, e.hubMon, "Back", true)
  tapOn(e.w, e.hubMon, "Firecrest-01")
  tapOn(e.w, e.hubMon, "STOP + DOCK", true)
  tapOn(e.w, e.hubMon, "START", true)
  e.w:run(5)
  T.eq(e.firecrest.G.want, "run")
  T.eq(e.nether:readTable("nether.cfg").firecrests[9].want, "run")
  e.w:run(10)
  for from in pairs(e.canary.G.senders) do T.eq(from, 3, "a Canary only hears his MD Foreman") end
  for from in pairs(e.firecrest.G.senders) do T.eq(from, 2, "a Firecrest only hears his Nether Foreman") end
end)

T.test("remote: an order given on the MD Foreman's own screen shows on the Overworld Foreman", function()
  local e = world()
  tapOn(e.w, e.mdMon, "Canary-01")
  tapOn(e.w, e.mdMon, "Gold")
  tapOn(e.w, e.mdMon, "START", true)
  e.w:run(5)
  tapOn(e.w, e.hubMon, "Canary-01")
  local _, y = e.hubMon:find("Min Y")
  T.truthy(y, e.hubMon:text())
  T.contains(e.hubMon:line(y), "-19")
  T.absent(e.hubMon, "START to switch")
  T.contains(e.hubMon, "Gold")
end)

T.test("remote: the Overworld Foreman gives a Starling his orders itself", function()
  local e = world()
  tapOn(e.w, e.hubMon, "Starling-03")
  tapOn(e.w, e.hubMon, "START", true)
  e.w:run(5)
  T.eq(e.starling.G.want, "run")
  T.eq(e.starling.G.cmdFrom, 1)
  T.eq(e.starling.G.lastCmd.kind, "starling")
end)

T.test("remote: reboot and retire from the remote go through the miner's Foreman", function()
  local e = world()
  tapOn(e.w, e.hubMon, "Firecrest-01")
  tapOn(e.w, e.hubMon, "Reboot", true)
  tapOn(e.w, e.hubMon, "Sure?", true)
  e.w:run(5)
  T.truthy(e.firecrest.G.lastCmd.reboot, "reboot token from the Nether Foreman")
  tapOn(e.w, e.hubMon, "Retire", true)
  tapOn(e.w, e.hubMon, "Sure?", true)
  e.w:run(5)
  T.eq(e.nether:readTable("nether.cfg").firecrests[9].retired, true)
  T.eq(e.firecrest.G.lastCmd.retired, true)
end)

T.test("remote: a dimension Foreman's presets can be edited from the remote", function()
  local e = world()
  e.hub:type("/presets"); e.hub:key(257)
  e.w:run(1)
  T.contains(e.hub.screen, "PRESETS OF STARLINGS")
  local x, y = e.hub.screen:find("Of:")
  e.hub:click(x, y); e.w:run(1)
  T.contains(e.hub.screen, "PRESETS OF MD")
  T.contains(e.hub.screen, "Diamonds")
  e.hub:type("/new Bottom"); e.hub:key(257)
  e.w:run(1)
  x, y = e.hub.screen:find("Save")
  e.hub:click(x, y); e.w:run(5)
  local p = e.md:readTable("mdforeman.cfg").presets
  T.eq(p[#p].name, "Bottom")
end)

T.test("remote: without the Overworld Foreman's list the MD Foreman numbers nobody, until /fresh", function()
  local w = cc.world()
  local net = w:net()
  local md = w:computer{ id = 3, label = "MD Foreman" }
  md:attach("back", cc.wired(net)); md:attach("top", cc.wireless{ ender = true })
  md:installRole("mdforeman")
  md:run("mdforeman")
  local c = MS.standIn(w, { id = 20, protocol = "tanis-miner", bird = "Canary", kind = "canary", dim = "allthemodium:mining" })
  w:run(15)
  T.eq(c.label, nil, "no number yet")
  T.contains(md.screen, "Waiting for the Overworld Foreman's Canary list")
  md:type("/fresh"); md:key(257)
  w:run(5)
  T.eq(c.label, "Canary-01")
end)

T.test("remote: storage's junk caps reach the Canaries through the Overworld and MD Foremans", function()
  local e = world()
  local st = e.w:computer{ id = 40, label = "Storage" }
  st:attach("top", cc.wireless{ ender = true })
  st:writeFile("st.lua", [[
    rednet.open("top")
    while true do
      rednet.broadcast({ type = "storage", overcap = { "minecraft:cobblestone" } }, "tanis-base")
      os.sleep(5)
    end
  ]])
  st:run("st")
  e.w:run(25)
  local capped = e.canary.G.lastCmd.capped
  T.eq(capped[1], "minecraft:cobblestone")
end)

T.test("remote: Re-dock on the Overworld Foreman reaches a Canary through the MD Foreman", function()
  local e = world()
  tapOn(e.w, e.hubMon, "Canary-01")
  tapOn(e.w, e.hubMon, "Re-dock", true)
  e.w:run(5)
  T.truthy(e.canary.G.lastCmd.redock, "re-dock token from the MD Foreman")
  T.eq(e.canary.G.cmdFrom, 3)
end)

T.test("remote: an old 'Digger' Canary the hand-over missed is never ordered by the Overworld Foreman", function()
  local w = cc.world()
  local hub = w:computer{ id = 1, label = "Foreman" }
  hub:attach("top", cc.wireless{ ender = true })
  hub:installRole("foreman")
  -- handed over already, but Canary-05 is still on the list under his pre-rename label
  hub:writeTable("foreman.cfg", { nextNum = 6, chunkRings = true, handedOver = true, retiredNums = {}, canaries = {
    [15] = { num = 5, label = "Digger-05", want = "run", minY = -59, maxY = -58, pMin = -59, pMax = -58, r1 = 0, r2 = 0, pR1 = 0, pR2 = 0, seq = 1 },
  } })
  hub:run("foreman")
  local c5 = MS.standIn(w, { id = 15, num = 5, label = "Canary-05", protocol = "tanis-miner", bird = "Canary",
    kind = "canary", dim = "allthemodium:mining" })
  w:run(15)
  T.eq(c5.G.lastCmd, nil, "the Overworld Foreman sent him an order")
  T.eq(hub:readTable("foreman.cfg").canaries[15], nil, "dropped from its list")
end)
