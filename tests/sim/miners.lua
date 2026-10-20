-- sim/miners.lua  --  helpers for the miner scenarios: a miner turtle, a stand-in Foreman, setup answers.
--
--   local MS = require("sim.miners")
--   local f = MS.foreman(w)                  -- numbers miners, sends _G.order, records _G.lastStatus
--   MS.setup(w, t, "1")                      -- answers the setup's dimension question (1 = Mining)
local cc = require("sim.cc")

local MS = {}

function MS.barrel() return cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } } end

-- A mining turtle with an ender modem, set up for the miner role.
function MS.turtle(w, o)
  o = o or {}
  local t = w:turtle{ id = o.id or 7, x = o.x or 0, y = o.y or 64, z = o.z or 0, facing = o.facing or 0,
                      fuel = o.fuel or 400, fuelLimit = o.fuelLimit, items = o.items,
                      left = "minecraft:diamond_pickaxe", right = "computercraft:wireless_modem_advanced" }
  t:installRole("canary")
  return t
end

-- Start the miner and answer the first question (the dimension): "1" Mining, "2" Overworld, "3" Nether, "4" End.
function MS.setup(w, t, dim)
  t:run("miner"); w:run(1)
  t:type(dim or "1"); t:key(257)
end

-- A stand-in Foreman: numbers every miner that registers (Canary-0N), and once _G.order is set sends it to
-- every miner it has heard. o.protocol (tanis-miner), o.kind (sent as cmd.kind when given), o.id (1).
-- o.dock = { [turtle id] = inv }: answers dock_req by putting o.lava lava buckets (default: what it asks for)
-- in that inventory; _G.requests counts them.
function MS.foreman(w, o)
  o = o or {}
  local f = w:computer{ id = o.id or 1, label = o.label or "Foreman" }
  f:attach("top", cc.wireless{ ender = true })
  f:writeFile("foreman.lua", ([[
    rednet.open("top")
    local P = %q
    local seen, nextNum = {}, 1
    while true do
      local from, msg = rednet.receive(P, 1)
      if type(msg) == "table" and msg.type == "register" then
        rednet.send(from, { type = "assigned", id = from, num = nextNum, label = "Canary-0" .. nextNum }, P)
        nextNum = nextNum + 1
      elseif type(msg) == "table" and msg.type == "status" then
        seen[from] = msg
        _G.lastStatus = msg
      elseif type(msg) == "table" and msg.type == "dock_req" and _G.docks[from] then
        _G.requests = _G.requests + 1
        local n = _G.lava or math.ceil((msg.fuel or 0) / 1000)
        if n > 0 then _G.docks[from]:give("minecraft:lava_bucket", n) end
        rednet.send(from, { type = "dock_ready", id = from, seq = msg.seq, got = { ["minecraft:lava_bucket"] = n }, missing = {} }, P)
      end
      if _G.order then
        for id in pairs(seen) do
          rednet.send(id, { type = "cmd", to = id, kind = _G.kind, want = _G.order.want, minY = _G.order.minY, maxY = _G.order.maxY,
                            c1 = 0, c2 = _G.order.c2 or 0, r1 = 1, r2 = 8, seq = _G.order.seq, capped = {} }, P)
        end
      end
    end
  ]]):format(o.protocol or "tanis-miner"))
  f:run("foreman")
  f.env._G.docks = o.dock or {}
  f.env._G.kind = o.kind
  f.env._G.requests = 0
  return f
end

function MS.order(f, o)
  o = o or {}
  f.env._G.order = { want = o.want or "run", minY = o.minY or 60, maxY = o.maxY or 63, seq = o.seq or 1, c2 = o.c2 }
end

-- pred: the miner has finished its range and is back at its dock
function MS.finished(f)
  return function()
    local s = f.env._G.lastStatus
    return s and s.state == "docked" and s.msg and s.msg:find("Range finished") ~= nil
  end
end

return MS
