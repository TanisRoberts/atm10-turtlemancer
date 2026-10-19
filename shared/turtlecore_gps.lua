-- turtlecore_gps.lua  --  core.gps: gps.locate with a timeout, retries and the last fix to fall back on.
return function(core)
local G = { last = nil }     -- last = { x, y, z, at } (os.epoch ms) of the newest real fix
core.gps = G

-- ok, x, y, z, stale. A real fix: ok true, stale false. None: the last fix (ok true, stale true), or ok false
-- if he never had one. Callers that need the truth (where he is NOW) treat stale as no fix.
-- Each try waits `timeout` seconds (2 by default); `retries` more tries follow a miss, half a second apart.
function G.locate(timeout, retries)
  timeout, retries = timeout or 2, retries or 0
  for i = 0, retries do
    local ok, x, y, z = pcall(gps.locate, timeout)
    if ok and x then
      x, y, z = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
      G.last = { x = x, y = y, z = z, at = os.epoch("utc") }
      return true, x, y, z, false
    end
    if i < retries then os.sleep(0.5) end
  end
  local l = G.last
  if l then return true, l.x, l.y, l.z, true end
  return false
end
end
