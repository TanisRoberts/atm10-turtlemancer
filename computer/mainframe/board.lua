-- board.lua  --  status board for every machine on the island (runs from mainframe.lua)
-- Hands the wall (wall.lua) the storage computer, the smelter and every turtle: state, what they're doing, when last heard.

local REFRESH    = 2

-- One row per machine: { name, state, detail, seen }
local function rows()
  local out = {}
  local s = _G.STORAGE_STATS
  if s then
    local pct = (s.total and s.total > 0) and math.floor(s.used / s.total * 100) or 0
    local detail = ("%d%% full, %d item types"):format(pct, s.kinds or 0)
    if s.inputStuck then detail = detail .. ", INPUT STUCK" end
    if s.locked then detail = detail .. ", screen locked" end
    out[#out + 1] = { s.label or "Storage", s.paused and "setup" or (pct >= 90 and "waiting" or "ok"), detail, _G.STORAGE_SEEN, "Storage" }
  else
    out[#out + 1] = { "Storage", "?", "not heard from yet", nil, "Storage" }
  end
  local sm = _G.SMELTER
  if sm then
    out[#out + 1] = { sm.label or "Smelter", sm.state or "ok", tostring(sm.note or ""), _G.SMELTER_SEEN, "Storage" }
  else
    out[#out + 1] = { "Smelter", "?", "not heard from yet", nil, "Storage" }
  end
  local fac = _G.FACTORY
  if fac then
    out[#out + 1] = { fac.label or "Plastic", fac.state, ("%s. %d plastic made"):format(tostring(fac.note or ""),
      tonumber(fac.plastic) or 0), _G.FACTORY_SEEN, "Labs" }
  end
  local nl = _G.NEURAL
  if nl then
    out[#out + 1] = { nl.label or "Neural lab", nl.state, ("%s. Power %s"):format(tostring(nl.note or ""),
      nl.power and (nl.power .. "%") or "?"), _G.NEURAL_SEEN, "Labs" }
  end
  local op = _G.OPERATOR
  if op then
    local rf, rfSeen = _G.REACTOR_FUEL, _G.REACTOR_FUEL_SEEN
    for _, r in ipairs(require("operator_fmt").boardRows(op, _G.OPERATOR_SEEN, rf, rfSeen and os.clock() - rfSeen)) do r[5] = "Labs"; out[#out + 1] = r end
  end
  local digs = {}
  for _, e in pairs(_G.CANARIES or {}) do
    if e.s.state ~= "retired" then digs[#digs + 1] = e end
  end
  table.sort(digs, function(a, b) return (a.s.num or 999) < (b.s.num or 999) end)
  for _, e in ipairs(digs) do
    local m = e.s
    out[#out + 1] = { m.label or "Canary", m.state, ("Y %s, fuel %s, cargo %s/16%s"):format(tostring(m.y), tostring(m.fuel),
      tostring(m.slots), (m.msg and m.msg ~= "") and (". " .. m.msg) or ""), e.seen, "Mining" }
  end
  local r = _G.WEAVER_STATUS
  if r then
    local where = r.phase == "layer" and ("layer %s/%s"):format(tostring(r.layer), tostring(r.layers))
      or r.phase == "ext" and ("edge wall %s/%s"):format(tostring(r.ext), tostring(r.extTotal)) or tostring(r.phase or "idle")
    out[#out + 1] = { r.label or "Weaver", r.state, where .. ((r.msg and r.msg ~= "") and (". " .. r.msg) or ""), _G.WEAVER_SEEN, "Building" }
  end
  local cg = _G.CARTOGRAPHER
  local z = _G.CARTO
  if cg then
    -- One row for the map room: Seagull's state, and how much of the world the Cartographer holds
    local sg = cg.seagull or {}
    local pct = (sg.mapping and tonumber(sg.wps) and sg.wps > 0) and (" %d%%,"):format(math.floor(((sg.wp or 1) - 1) / sg.wps * 100)) or ""
    out[#out + 1] = { cg.label or "Cartographer", sg.state or "no Seagull",
      ("%s %d regions, %d chunks, fuel %s%s"):format(pct, tonumber(cg.regions) or 0, tonumber(cg.chunks) or 0,
        tostring(sg.fuel or "?"), (sg.msg and sg.msg ~= "") and (". " .. sg.msg) or ""), _G.CARTOGRAPHER_SEEN, "Building" }
  elseif z then
    local pct = (z.mapping and tonumber(z.wps) and z.wps > 0) and (" %d%%,"):format(math.floor(((z.wp or 1) - 1) / z.wps * 100)) or ""
    out[#out + 1] = { z.label or "Seagull", z.state, ("%s %d chunks, fuel %s%s"):format(pct, tonumber(z.chunks) or 0,
      tostring(z.fuel), (z.msg and z.msg ~= "") and (". " .. z.msg) or ""), _G.CARTO_SEEN, "Building" }
  end
  local fh = _G.FARMHAND
  if fh then
    out[#out + 1] = { fh.label or "Farmhand", (tonumber(fh.problems) or 0) > 0 and "waiting" or "ok", tostring(fh.note or ""),
      _G.FARMHAND_SEEN, "Farming" }
  end
  local farms = {}
  for k, st in pairs(_G.FARM_STATUS or {}) do farms[#farms + 1] = { k, st } end
  table.sort(farms, function(a, b) return a[1] < b[1] end)
  for _, f in ipairs(farms) do
    local k, st = f[1], f[2]
    local state = (st.paused and st.state == "docked") and "paused" or st.state
    local detail = tostring(st.msg or "")
    if st.state == "working" and st.progress then detail = "Round " .. st.progress
    elseif st.state == "docked" and st.lastRound and not st.paused then
      local r = st.lastRound
      local last = st.role == "lumberjack" and ("chopped %d"):format(r.chopped or 0) or ("harvested %d"):format(r.harvested or 0)
      detail = ("Last round %s%s"):format(last, st.nextRound and (", next in %dm"):format(math.ceil(st.nextRound / 60)) or "")
    end
    if type(st.fuel) == "number" and type(st.fuelLimit) == "number" and st.fuelLimit > 0 then
      detail = detail .. (", fuel %d%%"):format(math.floor(st.fuel / st.fuelLimit * 100))
    end
    out[#out + 1] = { st.label or k, state, detail, _G.FARM_SEEN and _G.FARM_SEEN[k], "Farming" }
  end
  return out
end

-- The wall (wall.lua) draws the board; this hands it the rows. Rows are { name, state, detail, seen, group }.
local function hand()
  local list = rows()
  local out = {}
  for _, r in ipairs(list) do
    local st = tostring(r[2] or "?")
    out[#out + 1] = { name = r[1], state = st, detail = tostring(r[3] or ""), seen = r[4], group = r[5] }
  end
  _G.WALL_BOARD = out
end

while true do
  pcall(hand)
  os.sleep(REFRESH)
end
