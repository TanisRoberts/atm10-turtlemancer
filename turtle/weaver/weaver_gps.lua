-- weaver_gps.lua  --  GPS for position and heading (#140). A part of weaver.lua.
-- The base's GPS towers use ender modems, so a fix reaches him anywhere in the Overworld. His dock's WORLD position
-- (C.wx, C.wy, C.wz, from the Architect's `site` and `build` messages) turns a fix into dock coordinates; the axes
-- are the world's, so headings need no turning. A stale fix counts as none (core.gps). With no answer everything
-- works as before: dead reckoning plus the #139 rules.

GPS_EVERY = 40                 -- moves between checks of the fix against dead reckoning
GP = { ok = false, moves = 0, need = true, fix = nil, trust = false }   -- need: a full check (position and heading) is due

local function note(msg)
  S.gnote = msg; print(msg)
end

-- a fresh fix (world x, y, z), or nil
function gpsFix()
  if core.chunk.busy then return nil end
  local ok, x, y, z, stale = core.gps.locate(1, 1)
  if ok and not stale then GP.ok, GP.fix = true, { x, y, z }; return x, y, z end
  GP.ok = false
  return nil
end

function setDock(dock)
  if type(dock) ~= "table" or not (dock.x and dock.y and dock.z) then return end
  if C.wx == dock.x and C.wy == dock.y and C.wz == dock.z then return end
  C.wx, C.wy, C.wz = dock.x, dock.y, dock.z
  writeT(CFG_FILE, C)
  GP.need = true
end

-- Heading: step one block and back, comparing fixes. Forward, else back, else the same one block up. Never digs.
-- nil if he couldn't move or GPS didn't answer.
local function probe(fx, fz)
  local function try(go, undo)
    if not go() then return nil end
    local x, _, z = gpsFix()
    undo()
    if not x then return nil end
    return x - fx, z - fz
  end
  local function both()
    local dx, dz = try(turtle.forward, turtle.back)
    if dx then return dx, dz end
    dx, dz = try(turtle.back, turtle.forward)
    if dx then return -dx, -dz end
  end
  local dx, dz = both()
  if dx == nil and turtle.up() then dx, dz = both(); turtle.down() end
  if dx == 1 and dz == 0 then return 1 elseif dx == -1 and dz == 0 then return 3
  elseif dx == 0 and dz == 1 then return 2 elseif dx == 0 and dz == -1 then return 0 end
end

-- Heading by GPS wherever he can move a block (nil when GPS doesn't answer): used by setup instead of asking
function gpsHeading()
  local fx, _, fz = gpsFix()
  if fx then return probe(fx, fz) end
end

-- One check against the fix. full: also work out the heading. true if the position is now a fix's.
function gpsSync(full)
  GP.moves, GP.need = 0, false
  local fx, fy, fz = gpsFix()
  if not fx then GP.moves = S.lost and -6 or -(GPS_EVERY * 4); return false end
  local fixed = false
  if C.wx then
    local nx, ny, nz = fx - C.wx, fy - C.wy, fz - C.wz
    if nx ~= S.x or ny ~= S.y or nz ~= S.z then
      note(("GPS: I thought %s %s %s, I am at %d %d %d"):format(tostring(S.x), tostring(S.y), tostring(S.z), nx, ny, nz))
      S.x, S.y, S.z = nx, ny, nz
    end
    fixed, GP.trust = true, true
  end
  if full then
    local h = probe(fx, fz)
    if h ~= nil then
      if h ~= S.h then note(("GPS: I thought I faced %s, I face %s"):format(HNAME[S.h or 0], HNAME[h])) end
      S.h, S.turning, S.pending = h, nil, nil
      if fixed then S.lost = nil end
    end
  end
  save()
  return fixed
end

-- Between moves (the main loop): a full check when something asks for it (boot, a new dock position, lost),
-- else every GPS_EVERY moves.
function gpsStep()
  if not S.x or core.chunk.busy then return end
  if S.lost and not GP.need then GP.moves = GP.moves + 1 end
  if (GP.need or S.lost) and GP.moves >= 0 then gpsSync(true)
  elseif GP.moves >= GPS_EVERY then gpsSync(false) end
end
