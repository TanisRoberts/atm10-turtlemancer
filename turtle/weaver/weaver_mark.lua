-- weaver_mark.lua  --  the test and clear orders: put one marker on each of the footprint's 4 bottom corners, take them away.
-- The Architect sends the 4 corner cells in the order (dock coordinates, the bottom-layer cell); the marker goes on top of
-- each cell. S.markCells = the corners still to mark, S.marks = { {x,y,z,name} } the markers standing. A part of weaver.lua.

local function markerItem()
  local best, bn, cobble = nil, 0, nil
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isGear(d.name) then
      turtle.select(s)
      local fuel = turtle.refuel(0)
      if not fuel and d.name:find("bucket", 1, true) == nil then
        local n = counts()[d.name] or 0
        if n > bn then best, bn = d.name, n end
        if d.name == "minecraft:cobblestone" then cobble = d.name end
      end
    end
  end
  turtle.select(1)
  return best or cobble
end

-- one corner at a time, saved after each, so a reboot carries on
function markStep()
  local cells = S.markCells or {}
  local c = cells[1]
  if not c then S.markCells, S.markAsked = nil, nil; save(); return end
  local name = markerItem()
  if not name and not S.markAsked then
    S.markAsked = true                               -- nothing on him: ask storage for cobblestone (finishSupply fetches it)
    S.supSeq = S.supSeq + 1
    S.sup = { seq = S.supSeq, items = { ["minecraft:cobblestone"] = 4 }, fuel = 0, got = {} }
    save(); return
  end
  if not name then
    setStatus("blocked", "Nothing to mark with: put blocks in my inventory")
    S.markCells, S.want, S.markAsked = nil, "idle", nil; save(); os.sleep(2); return
  end
  S.marks = S.marks or {}
  local k = #S.marks + 1
  setStatus("marking", ("Marker %d/4"):format(math.min(k, 4)))
  local ok = goTo(c[1], c[2] + 2, c[3])
  if ok then
    turtle.select(slotOf(name))
    if not turtle.inspectDown() and turtle.placeDown() then
      S.marks[#S.marks + 1] = { c[1], c[2] + 1, c[3], name }
    end
    turtle.select(1)
  end
  table.remove(S.markCells, 1)
  S.markDone = (S.markDone or 0) + 1
  save()
end

-- take the markers away, only where they stand
function clearStep()
  local m = S.marks[1]
  if not m then S.marks = nil; save(); return end
  setStatus("clearing", ("%d markers left"):format(#S.marks))
  local ok = goTo(m[1], m[2] + 1, m[3])
  if ok then
    local has, d = turtle.inspectDown()
    if has and d.name == m[4] then turtle.digDown() end
  end
  table.remove(S.marks, 1)
  if #S.marks == 0 then S.marks = nil end
  save()
end
