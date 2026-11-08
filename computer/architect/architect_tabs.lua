-- architect_tabs.lua  --  the tabs after setup: Status, Map, Side, Bill, Log, and the monitor (the map alone).
-- Screens: docs/design/architect-fleet.md "After setup". A part of architect.lua.

V = { mode = "tabs", tab = "status", step = 1, layer = nil, follow = true, setupSub = nil }
TABS = { { id = "status", label = "Status", short = "Stat" }, { id = "map", label = "Map" }, { id = "side", label = "Side" },
         { id = "bill", label = "Bill" }, { id = "log", label = "Log" } }

local floor, max, min = math.floor, math.max, math.min

function headerFor(v, title)
  local st = R.status
  local right, state, color
  if S.n then
    right = ("Weaver-%02d seen %s ago"):format(S.n, ago(R.seen))
    if st and alive() then state = tostring(st.state or "?") else state, color = R.seen and "stale" or "listening", "warn" end
  end
  return v:header(title or label(), { state = state, color = color, right = right })
end

local function barRow(v, y, name, frac, text)
  v:put(2, y, name, "fg", "bg")
  v:bar(10, y, v.W - 10, nil, frac, { kind = "progress", text = text })
end

local function supplyLines()
  local st = R.status
  if R.supSince and now() - R.supSince > 300 then return "bad", "no answer from storage", true end
  if (st and st.gaps or 0) > 0 and R.shortName then
    return "warn", "storage is out of " .. pretty(R.shortName), false, ("leaving %d gaps, fills them later"):format(st.gaps)
  end
  return "good", "ok"
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
function drawStatus(v)
  local st = R.status
  headerFor(v)
  local W = v.W
  if not (S.n and P) then v:put(2, 4, "Not set up yet. Type setup.", "warn", "bg"); return end
  if not st or not alive() and not R.seen then
    v:spinner_line(2, 4, "Weaver-" .. ("%02d"):format(S.n) .. " has not been heard yet")
    v:put(2, 6, "Look at his own screen. He needs an ender modem", "dim", "bg")
    v:put(2, 7, "to be heard from far away.", "dim", "bg")
    return
  end
  local y = 3
  local tone, why, stuck, why2 = supplyLines()
  local kind = {}
  v:put(2, y, "Build", "dim", "bg"); v:put(14, y, fit(("%s  %s blocks, %d high"):format(S.name or "?", comma(P.blocks), P.plan.info.size.y), W - 14), "fg", "bg")
  y = y + 1
  local layer, total = st.layer or 1, P.total
  local cells = st.cells
  local nowText
  if finished() then nowText = "finished"
  elseif st.work == "gap" then nowText = ("gaps, block %d of %d"):format(st.idx or 1, cells or 0)
  elseif cells then nowText = ("Layer %d of %d, block %s of %s"):format(layer, total, comma(st.idx or 1), comma(cells))
  else nowText = ("Layer %d of %d, %s"):format(layer, total, tostring(st.msg or "")) end
  v:put(2, y, "Now", "dim", "bg"); v:put(14, y, fit(nowText, W - 14), "fg", "bg"); y = y + 1
  local done = progress()
  local lay = cells and cells > 0 and min((st.idx or 1) - 1, cells) / cells or 0
  barRow(v, y, "Layer", st.work == "layer" and lay or 0); y = y + 1
  v:put(2, y, "Build", "dim", "bg"); local t = ("%s / %s"):format(comma(done), comma(P.blocks)); v:put(W - #t, y, t, "fg", "bg"); y = y + 1
  barRow(v, y, "Overall", P.blocks > 0 and done / P.blocks or 0); y = y + 1
  v:put(2, y, "Fuel", "fg", "bg"); v:bar(10, y, W - 10, nil, (st.fuel or 0) / 20000, { kind = "fuel", text = comma(st.fuel or 0) }); y = y + 2
  v:put(2, y, "At", "dim", "bg"); v:put(14, y, ("%d %d %d from the dock"):format(st.x or 0, st.y or 0, st.z or 0), "fg", "bg"); y = y + 1
  if stuck then
    v:put(2, y, "Supply", "dim", "bg"); v:put(14, y, why, tone, "bg"); y = y + 2
    v:put(2, y, "Things to check", "gold", "bg"); y = y + 1
    for _, l in ipairs({ "- Is storage on? Its screen shows the queue.", ("- /assign: is an ender chest set as Weaver supply %02d?"):format(S.n),
                         "- Same dye code on both ender chests?" }) do v:put(3, y, fit(l, W - 4), "fg", "bg"); y = y + 1 end
    y = y + 1
  else
    v:put(2, y, "Supply", "dim", "bg"); v:put(14, y, fit(why, W - 14), tone, "bg"); y = y + 1
    if why2 then v:put(14, y, fit(why2, W - 14), "dim", "bg"); y = y + 1 end
    y = y + 1
  end
  if st.lost then v:alert(2, y, W - 2, "Weaver is lost: carry him to the dock, then run weaver found on him", "bad"); y = y + 2 end
  local o = S.order
  local function busy(word) return o and o.word == word end
  v:buttons(2, y, {
    { label = "Build", style = busy("build") and "busy" or "primary", fn = function() sendOrder("build") end, id = "b-build" },
    { label = "Stop", style = busy("stop") and "busy" or "idle", fn = function() sendOrder("stop") end, id = "b-stop" },
    { label = "Home", style = busy("home") and "busy" or "idle", fn = function() sendOrder("home") end, id = "b-home" },
    { label = "Reboot", style = busy("reboot") and "busy" or "idle", confirm = true, fn = function() sendOrder("reboot") end, id = "b-reboot" },
  })
end

---------------------------------------------------------------------------
-- Bill
---------------------------------------------------------------------------
function drawBill(v, report)
  headerFor(v)
  if not P then v:put(2, 4, "No build loaded. Type setup.", "warn", "bg"); return end
  local left = (S.started and R.status) and billLeft() or P.plan.info.items or P.plan.info.bill
  local stock = R.stock or {}
  local rows, total, covered = {}, 0, 0
  for item, n in pairs(left) do
    local have = stock[item] or 0
    rows[#rows + 1] = { item = item, n = n, have = have, short = max(n - have, 0) }
    total = total + n; covered = covered + min(n, have)
  end
  table.sort(rows, function(a, b) if (a.short > 0) ~= (b.short > 0) then return a.short > 0 end; return a.n > b.n end)
  local W = v.W
  v:put(2, 3, fit(R.stock and ("%s blocks left, storage covers %d%%"):format(comma(total), total > 0 and floor(covered * 100 / total) or 100)
                  or (comma(total) .. " blocks left, storage not heard yet"), W - 2), "fg", "bg")
  v:put(2, 4, "Material", "dim", "bg"); v:put(W - 24, 4, "left", "dim", "bg"); v:put(W - 15, 4, "storage", "dim", "bg")
  local r = v:rect(true)
  local per = max(r.y2 - 5 + 1, 1)
  v.pages = max(1, math.ceil(#rows / per))
  v.page = min(v.page or 1, v.pages)
  for i = 1, per do
    local row = rows[(v.page - 1) * per + i]
    if not row then break end
    local y = 4 + i
    local tone = row.have == 0 and row.short > 0 and "bad" or (row.short > 0 and "warn" or "good")
    local word = row.have < row.n / 10 and row.short > 0 and "NEEDED" or (row.short > 0 and "short" or "ok")
    v:put(2, y, fit(pretty(row.item), W - 35), "fg", "bg")
    v:put(W - 24 + 5 - #comma(row.n), y, comma(row.n), "fg", "bg")
    v:put(W - 15 + 7 - #comma(row.have), y, comma(row.have), "fg", "bg")
    v:put(W - 6, y, word, tone, "bg")
  end
end

---------------------------------------------------------------------------
-- Log
---------------------------------------------------------------------------
function drawLog(v)
  headerFor(v)
  local r = v:rect(true)
  local per = max(r.y2 - 3 + 1, 1)
  v.pages = max(1, math.ceil(#LOG / per))
  if V.logOpen ~= LOG_N or not v.page then v.page = v.pages; V.logOpen = LOG_N end
  v.page = min(v.page, v.pages)
  if #LOG == 0 then v:put(2, 3, "Nothing yet.", "dim", "bg") end
  for i = 1, per do
    local e = LOG[(v.page - 1) * per + i]
    if not e then break end
    v:put(2, 2 + i, fit(e[1] .. " " .. e[2], v.W - 2), "fg", "bg")
  end
end

---------------------------------------------------------------------------
-- The monitor: the map alone, following the Weaver
---------------------------------------------------------------------------
function drawMonitor(v)
  local W, H = v.W, v.H
  v:fill(1, 1, W, "bg")
  local st = R.status
  if not (P and siteOK(S.site) and S.started and st) then
    v:put(1, 1, fit(label():upper() .. " setting up", W), "gold", "bg")
    if P and siteOK(S.site) then
      local k = 1
      drawMapBody(v, { x1 = 1, y1 = 2, x2 = W, y2 = H }, k, 1)
    end
    return
  end
  local done = progress()
  v:bar(1, 1, W, fit((st.label or "Weaver") .. " " .. tostring(st.state), W - 6), P.blocks > 0 and done / P.blocks or 0, { kind = "progress" })
  local k, cur = viewLayer()
  if V.follow then k = cur end
  local g = mapGrid(k, cur)
  drawMapBody(v, { x1 = 1, y1 = 2, x2 = W, y2 = H - 1 }, k, cur)
  v:put(1, H, fit(alive() and ("Layer %d/%d  Y %d  %d gaps"):format(k, P.total, S.site.cy + P.ys[k], g.gaps) or ("not heard " .. ago(R.seen)), W),
        alive() and "dim" or "bad", "bg")
end

function drawTab(v)
  local t = V.tab
  if t == "status" then drawStatus(v) elseif t == "map" then drawMap(v) elseif t == "side" then drawSide(v)
  elseif t == "bill" then drawBill(v) else drawLog(v) end
end
