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
  -- C.t* is what the Architect sent; C.w* may have been corrected on the dock (one block up): keep that correction
  -- unless the Architect sends a different position
  local tx, ty, tz = C.tx or C.wx, C.ty or C.wy, C.tz or C.wz
  if tx == dock.x and ty == dock.y and tz == dock.z then return end
  C.tx, C.ty, C.tz = dock.x, dock.y, dock.z
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
  -- Sitting on his dock's chest, in the dock's column: HIS cell is the dock (dock coordinates 0 0 0 are where he
  -- sits, as when he counted moves). The position typed on the Architect may be the chest's, one block lower:
  -- trusting it put every fix one block too high (the arena, layer 11). Learn the dock from the fix instead.
  if C.wx and fx == C.wx and fz == C.wz and (fy == C.wy or fy == C.wy + 1) then
    local okc, d = turtle.inspectDown()
    if okc and d and (d.name:find("chest", 1, true) or d.name:find("barrel", 1, true)) then
      if fy ~= C.wy then
        C.wy = fy; writeT(CFG_FILE, C)
        note("GPS: my dock is the block I sit in, Y " .. fy .. ": layer " .. tostring(S.layer) .. " again from its start")
        if S.work == "layer" then S.idx = 1 end   -- cells placed while a block off: redo the layer (good ones are skipped)
      end
    end
  end
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
