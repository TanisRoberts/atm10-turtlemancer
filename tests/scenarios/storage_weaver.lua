-- Storage: supply Weavers through their own chests (one per Weaver number), clear then fill, queue, resend.
local cc = require("sim.cc")
local T = require("sim.test")

-- storage on a cable: barrel_0 input, barrel_1 output, barrel_2..3 storage, barrel_4/5 = Weaver 1/2 supply chests.
local function base()
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 5 do
    inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } })
  end
  local c = w:computer{ id = 1, label = "Storage" }
  c:attach("back", cc.wired(net))
  c:attach("top", cc.wireless{ ender = true })
  c:installRole("storage")
  c:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1",
    weaverSupply = { ["minecraft:barrel_4"] = 1, ["minecraft:barrel_5"] = 2 } })
  inv[2]:give("minecraft:stone", 64 * 3)
  inv[2]:give("minecraft:oak_planks", 20)
  inv[3]:give("minecraft:lava_bucket", 2)
  inv[3]:give("minecraft:coal", 64)
  -- two Weavers' radios: each asks, then keeps the replies it hears
  local ws = w:computer{ id = 3, label = "Weavers" }
  ws:attach("top", cc.wireless{ ender = true })
  ws:writeFile("ask.lua", [[
    rednet.open("top")
    _G.replies = {}
    parallel.waitForAny(function()
      while true do
        local _, msg = rednet.receive("tanis-weaver")
        if type(msg) == "table" and msg.type == "supplied" then _G.replies[#_G.replies + 1] = msg end
      end
    end, function()
      while true do
        local _, cmd = os.pullEvent("send")
        rednet.broadcast(cmd, "tanis-weaver")
      end
    end)
  ]])
  ws:run("ask")
  return w, c, inv, ws
end

local function replyFor(ws, n, seq)
  for _, r in ipairs(ws.G.replies or {}) do if r.n == n and r.seq == seq then return r end end
end

T.test("storage: two Weavers asking at once each get their own items in their own chest", function()
  local w, c, inv, ws = base()
  inv[4]:give("minecraft:dirt", 10)            -- leftovers he dropped in: the clear takes them back
  c:run("storage")
  w:run(5)
  ws:queue("send", { type = "supply", n = 1, seq = 1, items = { ["minecraft:stone"] = 100 }, fuel = 1000 })
  ws:queue("send", { type = "supply", n = 2, seq = 1, items = { ["minecraft:oak_planks"] = 30 }, fuel = 0 })
  T.waitFor(w, function() return replyFor(ws, 1, 1) and replyFor(ws, 2, 1) end, 60, "both Weavers should be answered")
  local r1, r2 = replyFor(ws, 1, 1), replyFor(ws, 2, 1)
  T.eq(r1.sent["minecraft:stone"], 100)
  T.eq(r1.sent["minecraft:lava_bucket"], 1)
  T.eq(inv[4]:count("minecraft:stone"), 100)
  T.eq(inv[4]:count("minecraft:lava_bucket"), 1)
  T.eq(inv[4]:count("minecraft:dirt"), 0, "the chest was cleared first")
  T.eq(r2.sent["minecraft:oak_planks"], 20)
  T.eq(r2.missing["minecraft:oak_planks"], 10)
  T.eq(inv[5]:count("minecraft:oak_planks"), 20)
  T.eq(inv[5]:count("minecraft:stone"), 0, "Weaver 2 got none of Weaver 1's items")
end)

T.test("storage: a repeated seq gets the same reply and moves nothing twice", function()
  local w, c, inv, ws = base()
  c:run("storage")
  w:run(5)
  local req = { type = "supply", n = 1, seq = 7, items = { ["minecraft:stone"] = 50 }, fuel = 0 }
  ws:queue("send", req)
  T.waitFor(w, function() return replyFor(ws, 1, 7) end, 60)
  local n = #ws.G.replies
  inv[4]:clear()                               -- he took it
  ws:queue("send", req)
  T.waitFor(w, function() return #ws.G.replies > n end, 30, "no repeat reply")
  w:run(10)
  T.eq(inv[4]:count("minecraft:stone"), 0, "not sent again")
  T.eq(ws.G.replies[#ws.G.replies].sent["minecraft:stone"], 50)
end)

T.test("storage: a number with no chest assigned gets everything as missing", function()
  local w, c, inv, ws = base()
  c:run("storage")
  w:run(5)
  ws:queue("send", { type = "supply", n = 9, seq = 1, items = { ["minecraft:stone"] = 5 }, fuel = 0 })
  T.waitFor(w, function() return replyFor(ws, 9, 1) end, 60)
  T.eq(replyFor(ws, 9, 1).missing["minecraft:stone"], 5)
end)
