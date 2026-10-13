-- board.lua  --  status board for every machine on the island (runs from mainframe.lua)
-- Shows the storage computer, the smelter and every turtle: state, what they're doing, when last heard.

local REFRESH    = 2
local STALE      = 30    -- seconds without news before a row turns grey
local TEXT_SCALE = 0.5

local mon = peripheral.find("monitor")
if not mon then return os.pullEvent("never") end

local STATE_COLOUR = {
  mining = colours.lime, working = colours.lime, building = colours.lime, marking = colours.lime,
  surveying = colours.lime, clearing = colours.lime,
  returning = colours.yellow, docked = colours.lightBlue, done = colours.lightBlue,
  waiting = colours.orange, error = colours.red, lost = colours.red,
  running = colours.lime, paused = colours.orange,
}

local function ago(t)
  if not t then return "never" end
  local s = math.floor(os.clock() - t)
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end

-- One row per machine: { name, state, detail, seen }
local function rows()
  local out = {}
  local s = _G.STORAGE_STATS
  if s then
    local pct = (s.total and s.total > 0) and math.floor(s.used / s.total * 100) or 0
    local detail = ("%d%% full, %d item types"):format(pct, s.kinds or 0)
    if s.inputStuck then detail = detail .. ", INPUT STUCK" end
    if s.locked then detail = detail .. ", screen locked" end
    out[#out + 1] = { s.label or "Storage", s.paused and "setup" or (pct >= 90 and "waiting" or "ok"), detail, _G.STORAGE_SEEN }
  else
    out[#out + 1] = { "Storage", "?", "not heard from yet", nil }
  end
  local sm = _G.SMELTER
  if sm then
    out[#out + 1] = { sm.label or "Smelter", "ok", tostring(sm.note or ""), _G.SMELTER_SEEN }
  else
    out[#out + 1] = { "Smelter", "?", "not heard from yet", nil }
  end
  local fac = _G.FACTORY
  if fac then
    out[#out + 1] = { fac.label or "Plastic", fac.state, ("%s. %d plastic made"):format(tostring(fac.note or ""),
      tonumber(fac.plastic) or 0), _G.FACTORY_SEEN }
  end
  local digs = {}
  for _, e in pairs(_G.DIGGERS or {}) do
    if e.s.state ~= "retired" then digs[#digs + 1] = e end
  end
  table.sort(digs, function(a, b) return (a.s.num or 999) < (b.s.num or 999) end)
  for _, e in ipairs(digs) do
    local m = e.s
    out[#out + 1] = { m.label or "Digger", m.state, ("Y %s, fuel %s, cargo %s/16%s"):format(tostring(m.y), tostring(m.fuel),
      tostring(m.slots), (m.msg and m.msg ~= "") and (". " .. m.msg) or ""), e.seen }
  end
  local r = _G.RIGGER_STATUS
  if r then
    local where = r.phase == "layer" and ("layer %s/%s"):format(tostring(r.layer), tostring(r.layers))
      or r.phase == "ext" and ("edge wall %s/%s"):format(tostring(r.ext), tostring(r.extTotal)) or tostring(r.phase or "idle")
    out[#out + 1] = { r.label or "Rigger", r.state, where .. ((r.msg and r.msg ~= "") and (". " .. r.msg) or ""), _G.RIGGER_SEEN }
  end
  local farms = {}
  for k, st in pairs(_G.FARM_STATUS or {}) do farms[#farms + 1] = { k, st } end
  table.sort(farms, function(a, b) return a[1] < b[1] end)
  for _, f in ipairs(farms) do
    local k, st = f[1], f[2]
    out[#out + 1] = { st.label or k, st.state, tostring(st.msg or ""), _G.FARM_SEEN and _G.FARM_SEEN[k] }
  end
  return out
end

local function draw()
  mon.setTextScale(TEXT_SCALE)
  local w, h = mon.getSize()
  mon.setBackgroundColour(colours.black); mon.clear()
  mon.setCursorPos(1, 1); mon.setBackgroundColour(colours.grey); mon.clearLine()
  mon.setTextColour(colours.cyan); mon.write(" MACHINES")
  mon.setBackgroundColour(colours.black)
  local nameW = math.min(12, math.floor(w / 4))
  for i, r in ipairs(rows()) do
    local y = i + 2
    if y > h then break end
    local stale = not r[4] or os.clock() - r[4] > STALE
    mon.setCursorPos(2, y)
    mon.setTextColour(stale and colours.grey or colours.white)
    mon.write((r[1] .. (" "):rep(nameW)):sub(1, nameW))
    local st = tostring(r[2] or "?")
    mon.setTextColour(stale and colours.grey or (STATE_COLOUR[st] or (st == "ok" and colours.lime) or colours.white))
    mon.write((" " .. st:upper() .. (" "):rep(10)):sub(1, 11))
    local seen = " " .. ago(r[4])
    local room = w - (2 + nameW + 11) - #seen
    mon.setTextColour(stale and colours.grey or colours.lightGrey)
    mon.write((" " .. tostring(r[3] or "")):sub(1, math.max(0, room)))
    mon.setCursorPos(w - #seen + 1, y)
    mon.setTextColour(colours.grey)
    mon.write(seen)
  end
end

while true do
  local ok = pcall(draw)
  os.sleep(REFRESH)
end
