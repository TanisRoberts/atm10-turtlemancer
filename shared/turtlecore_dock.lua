-- turtlecore_dock.lua  --  core.dock: his one dock barrel: how to reach it, what's in it, and telling Storage where it is.
-- Storage's side of the "dock_report" message is in docs/systems/turtle.md.
return function(core)
local D = { known = nil, reportedAt = nil, hooks = {} }
core.dock = D
local BASE = "tanis-base"          -- the protocol Storage listens on

-- drop and suck for the side the dock is on: "up", "down", or in front (a compass number counts as front:
-- the role turns to face it first)
function D.ops(dir)
  if dir == "up" then return turtle.dropUp, turtle.suckUp end
  if dir == "down" then return turtle.dropDown, turtle.suckDown end
  return turtle.drop, turtle.suck
end

local SIDE = { up = "top", down = "bottom" }

-- What's in the dock barrel (a turtle can read the inventory next to it), or nil if it can't tell
function D.list(dir)
  local side = SIDE[dir] or "front"
  if not peripheral.hasType or not peripheral.hasType(side, "inventory") then return nil end
  local ok, l = pcall(peripheral.call, side, "list")
  return ok and type(l) == "table" and l or nil
end

-- How many of an item he carries, not counting slot `except`
function D.holding(name, except)
  local n = 0
  for s = 1, 16 do
    if s ~= except then
      local d = turtle.getItemDetail(s)
      if d and d.name == name then n = n + d.count end
    end
  end
  return n
end

-- The dock's world position { x, y, z } and the side it is on (what he reports to Storage)
function D.set(pos, dir) D.known = pos and { x = pos.x, y = pos.y, z = pos.z, dir = dir } or nil end

-- The role says how to get to the dock and back: { go = function, back = function } (either may be left out)
function D.setHooks(h) D.hooks = h or {} end

-- Go to the dock, do fn there, come back. The way back runs even if fn fails; returns the pcall result of fn.
function D.visit(fn)
  if D.hooks.go then pcall(D.hooks.go) end
  local ok, err = pcall(fn)
  if D.hooks.back then pcall(D.hooks.back) end
  return ok, err
end

-- Tell Storage where his dock is: broadcasts { type = "dock_report", ... } and waits for { type = "dock_ack" }.
-- Returns the ack ({ assigned = <barrel name or nil> }) or nil (no modem, no dock position, nobody answered).
-- o: timeout (seconds per try, default 2), tries (default 2).
function D.report(o)
  o = o or {}
  local p = D.known
  if not p then return nil, "no dock position" end
  if not rednet.isOpen() then return nil, "no modem" end
  local me = os.getComputerID()
  local msg = { type = "dock_report", id = me, label = os.getComputerLabel(), role = o.role,
                x = p.x, y = p.y, z = p.z, dir = p.dir }
  for _ = 1, o.tries or 2 do
    rednet.broadcast(msg, BASE)
    local deadline = os.clock() + (o.timeout or 2)
    while os.clock() < deadline do
      local _, reply = rednet.receive(BASE, math.max(0.1, deadline - os.clock()))
      if type(reply) == "table" and reply.type == "dock_ack" and reply.id == me then
        D.reportedAt = os.epoch("utc")
        return reply
      end
    end
  end
  return nil, "no answer"
end

-- report() at most every `every` seconds (600 by default; a miss is tried again after a third of that)
function D.maybeReport(o)
  o = o or {}
  local every = (o.every or 600) * 1000
  local now = os.epoch("utc")
  if D.reportedAt and now - D.reportedAt < every then return nil end
  if D.lastTry and now - D.lastTry < every / 3 then return nil end
  local ack, why = D.report(o)
  if why == "no answer" then D.lastTry = now end     -- only a try that went out counts
  return ack, why
end
end
