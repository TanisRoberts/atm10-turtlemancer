-- farmhand_screens.lua  --  what the Farmhand shows, built only from the UI kit (shared/ui.lua, ui_widgets.lua).
--
-- Overview: a tile per farm turtle (what it's doing, fuel, next round, its farm drawn small with an arrow where it
-- is right now, its last round), and buttons for every turtle at once. Tap a tile to open that turtle: the map (or
-- the Info / Haul / Settings tab) on the left, what it's doing and the order buttons on the right (a "Do" tab on a
-- narrow screen). Every view (the monitor and the computer's own screen) keeps its own page and tab.
--
--   local screens = dofile/require "farmhand_screens"(F)    F: the Farmhand's data and orders (see farmhand.lua)
--   ui.run(views, screens.draw, ...)                        screens.wanted(views): turtle ids whose map is on show
local ui = require("ui")
local M = require("farmhand_map")

return function(F)
  local S = {}
  local cfg, live, maps = F.cfg, F.live, F.maps
  local fit = ui.text.fit

  -- Per-view state, by kind: { page = "overview"|"turtle", id, tab, visible = { ids on show } }
  local states = {}
  local function stateFor(v)
    local kind = v.side and "monitor" or "term"
    states[kind] = states[kind] or { page = "overview", tab = "map", visible = {} }
    return states[kind]
  end

  ---------------------------------------------------------------------------
  -- Formatting
  ---------------------------------------------------------------------------
  -- farm state -> word, kit colour role
  local STATES = {
    working = { "working", "good" }, surveying = { "mapping", "good" }, docked = { "docked", "idle" },
    waiting = { "waiting", "warn" }, error = { "error", "bad" }, lost = { "lost", "bad" },
    rebooting = { "rebooting", "busy" },
  }
  local function fmtNum(n)
    if type(n) ~= "number" then return tostring(n or "?") end
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
  end
  local function fmtAgo(s)
    if s < 60 then return s .. "s" end
    if s < 3600 then return math.floor(s / 60) .. "m" end
    return math.floor(s / 3600) .. "h"
  end
  local function fmtMins(secs)
    if not secs then return "-" end
    if secs < 60 then return "under a min" end
    return math.ceil(secs / 60) .. " min"
  end
  local function pretty(id)
    local s = tostring(id):gsub("^.-:", ""):gsub("_", " ")
    return (s:gsub("^%l", string.upper))
  end
  local function posText(s)
    if not s or not s.pos then return "position unknown" end
    return ("%d, %d, %d"):format(s.pos.x, s.pos.y, s.pos.z)
  end
  local function isStale(id)
    local l = live[id]
    return not l or os.clock() - l.seen > F.STALE
  end
  -- word and colour role for a turtle's state
  local function stateOf(id)
    local l = live[id]
    if not l then return "no signal", "dim" end
    local st = l.s.state
    if l.s.paused and st == "docked" then st = "paused" end
    local m = STATES[st] or (st == "paused" and { "paused", "warn" }) or { tostring(st or "?"), "dim" }
    if isStale(id) then return m[1], "dim" end
    return m[1], m[2]
  end
  local function lastRoundText(s)
    local r = s and s.lastRound
    if not r then return "no round yet" end
    if s.role == "lumberjack" then
      return ("chopped %d, planted %d"):format(r.chopped or 0, r.planted or 0)
        .. (r.picked and (", %d saplings found"):format(r.picked) or "")
    end
    return ("harvested %d, planted %d"):format(r.harvested or 0, r.planted or 0)
  end
  local function nextText(s)
    if not s then return "" end
    if s.state == "working" and s.progress then return "round " .. s.progress end
    if s.paused then return "paused" end
    if s.nextRound then return "next in " .. fmtMins(s.nextRound) end
    return ""
  end
  local function fuelPct(s)
    if s and type(s.fuel) == "number" and type(s.fuelLimit) == "number" and s.fuelLimit > 0 then
      return s.fuel / s.fuelLimit
    end
  end
  local function wrap(text, w)
    local out, line = {}, ""
    for word in tostring(text):gmatch("%S+") do
      if line == "" then line = word
      elseif #line + 1 + #word <= w then line = line .. " " .. word
      else out[#out + 1] = line; line = word end
    end
    if line ~= "" then out[#out + 1] = line end
    return out
  end
  -- label left (dim), value right
  local function kv(v, x, y, w, label, value, role)
    value = fit(tostring(value), math.max(w - 2, 1))
    v:put(x, y, (" "):rep(w), "fg", "bg")
    v:put(x, y, fit(label, math.max(w - #value - 1, 0)), "dim", "bg")
    v:put(x + w - #value, y, value, role or "fg", "bg")
  end
  local function title(v, x, y, w, text) v:put(x, y, fit(text, w), "dim", "bg") end

  -- Notices: tones in the kit's words
  local say = ui.say

  ---------------------------------------------------------------------------
  -- Maps
  ---------------------------------------------------------------------------
  -- The turtle's cell on its map: column, row, heading (nil if it isn't on it)
  local function turtleCell(id, m)
    local l = live[id]
    local s = l and l.s
    if m and s and s.mp and s.mapStamp then return s.mp.x - m.x0 + 1, s.mp.z - m.z0 + 1, s.mp.h or 0 end
  end

  ---------------------------------------------------------------------------
  -- Overview
  ---------------------------------------------------------------------------
  local function openTurtle(v, st, id)
    st.page, st.id, st.tab = "turtle", id, "map"
    v.panTo, v.page, v.sel = nil, 1, nil
  end

  local function tileFields(v, st, id)
    local l = live[id]
    local s = l and l.s
    local word, role = stateOf(id)
    local f = { name = F.nameOf(id), state = word, color = role, fuel = fuelPct(s) or false }
    if f.fuel == false then f.fuel = nil; f.fuelText = "-" end
    local stale = isStale(id)
    if stale then f.stale = l and fmtAgo(math.floor(os.clock() - l.seen)) or "yet"
    else f.activity = tostring(s.msg or "") end
    local nt = s and nextText(s) or ""
    if nt ~= "" then f.numbers = nt:gsub("^%l", string.upper) end
    if l then f.seen = "seen " .. fmtAgo(math.floor(os.clock() - l.seen)) .. " ago" end
    if f.fuel == nil and f.fuelText == "-" then f.fuel = nil end
    f.extra = function(view, x, y, w, h)
      local m = maps[id]
      local yy = y
      local mapRows = h - 1                                      -- the last row is the last round
      if mapRows >= 3 then
        if m and not m.none then
          local tc, tr, th = turtleCell(id, m)
          M.thumb(view, id, m, x, yy, w, mapRows, tc, tr, th, stale)
        else
          local t = (m and m.none) and "not mapped yet" or (s and s.mapStamp == nil) and "reboot it once for the map" or "asking for its map..."
          view:put(x, yy + math.floor(mapRows / 2), fit(t, w), "bar", "bg")
        end
        yy = yy + mapRows
      end
      if s and s.lastRound then view:put(x, yy, fit("Last: " .. lastRoundText(s), w), "dim", "bg") end
    end
    return f
  end

  local function drawOverview(v, st)
    local list = F.ids()
    if F.radioOK() == false and not (ui.notice and ui.notice.tone == "bad") then
      ui.say("No wireless/ender modem on me: the turtles can't hear me", "bad")
    end
    local typed = not v.side and F.commands   -- only the computer's own screen has a keyboard
    local nProb = F.problems()
    v:header("Farmhand", { state = nProb > 0 and (nProb .. " need" .. (nProb == 1 and "s" or "") .. " you") or "all fine",
                           color = nProb > 0 and "warn" or "good",
                           right = ("%d turtle%s"):format(#list, #list == 1 and "" or "s") })
    st.visible = {}
    if #list == 0 then
      local lines = { "No farm turtles heard yet.", "Set up a turtle as Partridge (crops) or Woodpecker (trees):",
                      "it shows up here as soon as it's on the air." }
      for i, l in ipairs(lines) do v:put(2, 3 + i, fit(l, v.W - 2), i == 1 and "fg" or "dim", "bg") end
    else
      v:tiles(list, { grow = true, input = typed and 2 or true,
        on = function(id) openTurtle(v, st, id) end,
        render = function(id) st.visible[#st.visible + 1] = id; return tileFields(v, st, id) end })
      local short = v.wc == "narrow"
      v:buttons(2, v.H - (typed and 2 or 1), {
        { label = "Rounds all", short = "Rounds", style = "primary", fn = function()
          for _, id in ipairs(F.ids()) do F.order(id, "rounds") end
          say("Every farm turtle is off on its rounds.", "good")
        end },
        { label = "Pause all", short = "Pause", fn = function()
          for _, id in ipairs(F.ids()) do F.order(id, "stop") end
          say("Every farm turtle will stay docked (Go to start again).", "warn")
        end },
        { label = "Reboot all", short = "Boot", fn = function()
          for _, id in ipairs(F.ids()) do F.requestReboot(id) end
          say("Reboot sent: each finishes what it's doing, then restarts.", "busy")
        end },
      })
    end
    if typed then
      st.field = st.field or ui.field({ hint = "search" })
      v:search(st.field, { hint = "/ = commands (/status, /help)", commands = F.commands })
    end
    v:footer({})
  end

  ---------------------------------------------------------------------------
  -- One turtle
  ---------------------------------------------------------------------------
  local function drawStatus(v, id, x, y, w, maxY)
    local l = live[id]
    local s = l and l.s
    local function row(label, value, role)
      if y <= maxY then kv(v, x, y, w, label, value, role) end
      y = y + 1
    end
    row("Seen", l and (fmtAgo(math.floor(os.clock() - l.seen)) .. " ago") or "never")
    local f = s and s.fuel
    row("Fuel", type(f) == "number" and (fmtNum(f) .. " / " .. fmtNum(s.fuelLimit)) or (f or "-"))
    if s and s.role == "lumberjack" then
      row("Zone", s.mapped and ("%s blocks, %s trees"):format(fmtNum(s.cells), fmtNum(s.spots)) or "not mapped")
      row("Saplings", fmtNum(s.saplings))
    else
      local crop = s and s.crop and pretty(tostring(s.crop):gsub("_seeds$", ""):gsub("^.-:", "")) or nil
      row("Farm", s and s.mapped and (fmtNum(s.plots) .. " plots" .. (crop and (", " .. crop) or "")) or "not mapped")
      row("Seeds", s and fmtNum(s.seeds) or "-")
    end
    row("Last round", s and lastRoundText(s) or "-")
    row("Next", s and (nextText(s) ~= "" and nextText(s) or "-") or "-")
    row("Rounds done", s and fmtNum(s.rounds) or "-")
    y = y + 1
    row("At", posText(s))
    row("Facing", s and s.facing or "?")
    row("Home", s and s.home and ("%d, %d, %d"):format(s.home.x, s.home.y, s.home.z) or "?")
    row("GPS", not s and "-" or s.anchored and "pinned: never lost" or s.gps and "seen, not pinned yet" or "none: counting moves",
        s and not s.anchored and "warn" or "fg")
    row("Computer", "#" .. id, "dim")
    return y
  end

  local function drawHaul(v, id, x, y, w, maxY)
    local s = live[id] and live[id].s
    local function list(name, items)
      if y > maxY then return end
      title(v, x, y, w, name:upper()); y = y + 1
      if (not items or #items == 0) and y <= maxY then v:put(x, y, "Nothing yet", "bar", "bg"); y = y + 1 end
      for _, e in ipairs(items or {}) do
        if y > maxY then break end
        kv(v, x, y, w, pretty(e[1]), fmtNum(e[2]), "info")
        y = y + 1
      end
      y = y + 1
    end
    list("Last haul", s and s.lastHaul)
    list("Brought in so far", s and s.totals)
  end

  local function drawSettings(v, id, x, y, w, maxY)
    local s = live[id] and live[id].s
    title(v, x, y, w, "SETTINGS (changed live)"); y = y + 2
    for _, def in ipairs(F.SETTINGS[s and s.role or ""] or {}) do
      local k, label, unit, step, mn, mx = def[1], def[2], def[3], def[4], def[5], def[6]
      local val, pending = F.settingValue(id, k)
      local text = unit ~= "" and (label .. " (" .. unit .. ")") or label
      if type(val) == "number" then
        if y + (v.wc == "narrow" and 1 or 0) > maxY then break end
        local _, last = v:stepper(x, y, text, val, { min = mn, max = mx, step = step, pending = pending, id = "set:" .. k,
          on = function(n) F.changeSetting(id, k, n) end })
        y = last + 2
      else
        v:put(x, y, fit(text .. "  ?", w), "dim", "bg"); y = y + 2
      end
    end
    local hints = "0 = never (re-map) or off (sweeps). Gold = sent, waiting for the turtle to confirm. Written into its own .env file."
    for _, t in ipairs(wrap(hints, w)) do
      if y > maxY then break end
      v:put(x, y, fit(t, w), "bar", "bg"); y = y + 1
    end
  end

  local function drawMapTab(v, st, id, x, y, w, maxY)
    local m = maps[id]
    local l = live[id]
    local s = l and l.s
    if not m or m.none then
      local t = (m and m.none) and "It hasn't mapped its farm yet."
        or (s and s.mapStamp == nil) and "No map from it: reboot it once so it gets the new program."
        or "Asking " .. F.nameOf(id) .. " for its map..."
      for i, line in ipairs(wrap(t, w)) do v:put(x, y + i, fit(line, w), "dim", "bg") end
      return
    end
    local stale = isStale(id)
    local tc, tr, th = turtleCell(id, m)
    local key = M.key(m, s, stale, tc ~= nil)
    local keyRows = M.drawKey(v, key, x, 0, w, 3, false)
    local area = { x1 = x, y1 = y, x2 = x + w - 1, y2 = maxY - keyRows }
    local get = M.getter(m)
    v:map({ get = get, area = area, wide = true,
      bounds = { x1 = 1, z1 = 1, x2 = m.w, z2 = m.h },
      at = tc and { x = tc, z = tr, facing = M.ARROW[th] or "@", fg = "fg", bg = stale and "bar" or "mark" } or { x = -999, z = -999 },
      on_cell = function(c, r)
        local ch = (m.rows[r] or ""):sub(c, c)
        local what = M.describe(m, ch, (m.states[r] or ""):sub(c, c))
        if tc and c == tc and r == tr then what = F.nameOf(id) .. " is here" end
        local wx, wz
        if tc and s.pos and m.north then wx, wz = s.pos.x + (c - tc), s.pos.z + (r - tr) end
        say((wx and ("%d, %d: "):format(wx, wz) or "") .. what, "plain")
      end })
    M.drawKey(v, key, x, area.y2 + 1, w, keyRows, true)
  end

  -- Right column: what it's doing, fuel, and the order buttons
  local function drawSide(v, st, id, x, y, w, maxY)
    local l = live[id]
    local s = l and l.s
    local t = cfg.turtles[id] or {}
    local word, role = stateOf(id)
    v:put(x, y, fit(word, w), role, "bg"); y = y + 1
    local msg = s and s.msg or "Waiting to hear from it"
    for i, line in ipairs(wrap(msg, w)) do
      if i > 2 then break end
      v:put(x, y, fit(line, w), "dim", "bg"); y = y + 1
    end
    v:bar(x, y, w, "Fuel", fuelPct(s)); y = y + 1
    kv(v, x, y, w, "Next", s and (nextText(s) ~= "" and nextText(s) or "-") or "-"); y = y + 1
    if s and s.role == "lumberjack" then kv(v, x, y, w, "Saplings", fmtNum(s.saplings))
    elseif s then kv(v, x, y, w, "Seeds", fmtNum(s.seeds)) end
    y = y + 2

    local name = F.nameOf(id)
    local btns = {
      { label = "Rounds now", short = "Rounds", style = "primary", fn = function()
        F.order(id, "rounds"); say(name .. " is off on its rounds.", "good") end },
      s and s.paused and { label = "Go", fn = function() F.order(id, "go"); say(name .. " is back on its timer.", "good") end }
        or { label = "Pause", fn = function() F.order(id, "stop"); say(name .. " will stay docked.", "warn") end },
      { label = "Re-map", fn = function() F.order(id, "survey"); say(name .. " will walk its farm again.", "busy") end },
    }
    if s and s.state == "lost" then
      btns[#btns + 1] = { label = "Found", fn = function()
        F.order(id, "found"); say("Put " .. name .. " on its home spot first: it works out the rest.", "warn") end }
    end
    btns[#btns + 1] = { label = "Reboot", busy = t.reboot ~= nil, fn = function()
      F.requestReboot(id); say(name .. " reboots once it's finished what it's doing.", "busy") end }
    local gap = (#btns * 2 - 1 <= maxY - y + 1) and 1 or 0
    for _, b in ipairs(btns) do
      if y > maxY then break end
      v:buttons(x, y, { b }, { maxx = x + w - 1 })
      y = y + 1 + gap
    end
  end

  local TABS_WIDE = { { id = "map", label = "Map" }, { id = "info", label = "Info" }, { id = "haul", label = "Haul" },
                      { id = "settings", label = "Settings", short = "Set" } }
  local TABS_NARROW = { { id = "map", label = "Map" }, { id = "do", label = "Do" }, { id = "info", label = "Info" },
                        { id = "settings", label = "Settings", short = "Set" } }

  local function drawTurtle(v, st)
    local id, W, H = st.id, v.W, v.H
    if not cfg.turtles[id] then st.page = "overview"; return drawOverview(v, st) end
    local side = W >= 44
    if not side and st.tab == "haul" then st.tab = "info" end
    if side and st.tab == "do" then st.tab = "map" end
    st.tab = st.tab or "map"
    local word, role = stateOf(id)
    local m = maps[id]
    v:header(F.nameOf(id), { state = word, color = role,
      right = (st.tab == "map" and m and not m.none) and (m.north and "north is up" or "up = way it faced") or nil })
    local sw = side and math.max(18, math.min(24, math.floor(W * 0.36))) or 0
    local px, pw = 2, side and (W - sw - 3) or (W - 2)
    local top, bottom = 3, H - 1
    if side then drawSide(v, st, id, W - sw, top, sw - 1, bottom) end
    if not side and st.tab == "do" then drawSide(v, st, id, px, top, pw, bottom)
    elseif st.tab == "info" then
      local y = drawStatus(v, id, px, top, pw, bottom)
      local l = live[id]
      if (not l or os.clock() - l.seen > 120) and y + 1 <= bottom then
        v:buttons(px, y + 1, { { label = "Forget this turtle", short = "Forget", confirm = true, style = "danger", fn = function()
          F.forget(id); st.page = "overview"
          say("Forgotten. If it talks again it comes back.", "warn")
        end } })
      end
    elseif st.tab == "haul" then drawHaul(v, id, px, top, pw, bottom)
    elseif st.tab == "settings" then drawSettings(v, id, px, top, pw, bottom)
    else drawMapTab(v, st, id, px, top, pw, bottom) end
    v:footer({ back = function() st.page = "overview"; v.page, v.panTo, v.sel = 1, nil, nil end,
               tabs = side and TABS_WIDE or TABS_NARROW, tab = st.tab,
               on_tab = function(tid) st.tab = tid end })
  end

  function S.draw(v)
    local st = stateFor(v)
    if st.page == "turtle" then drawTurtle(v, st) else drawOverview(v, st) end
  end

  -- Ids of the turtles whose maps are on show (overview tiles, or the one open), for the map requests
  function S.wanted(views)
    local want = {}
    for _, v in ipairs(views) do
      local st = stateFor(v)
      if st.page == "turtle" and st.id then want[st.id] = true
      else for _, vid in ipairs(st.visible or {}) do want[vid] = true end end
    end
    return want
  end

  return S
end
