-- architect_net.lua  --  the radio: pairing, re-link, the Weaver's status, build and layers out, gaps, orders, the bill.
-- Protocol tanis-weaver (docs/systems/weaver.md sections 5-8); storage's stock and the bill go over tanis-base.
-- A part of architect.lua.

function openModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" and not rednet.isOpen(name) then pcall(rednet.open, name) end
  end
end
function radioOK()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" and rednet.isOpen(name) then return true end
  end
  return false
end

function tx(msg)
  msg.n = msg.n or S.n
  pcall(rednet.broadcast, msg, PROTOCOL)
end
local function due(key, every)
  if now() - (R.askedAt[key] or -1e9) >= (every or RESEND) then R.askedAt[key] = now(); return true end
  return false
end

---------------------------------------------------------------------------
-- Pairing (wizard step 1)
---------------------------------------------------------------------------
-- R.pair = { turtle, n, paired, t0 }   R.relink = { n, state, from, site, t0 }
function beginPair(turtle) R.pair = { turtle = turtle, t0 = now() }; R.askedAt.pair = nil end
function beginRelink(n) R.relink = { n = n, t0 = now() }; R.askedAt.relink = nil; R.read = nil end
function unpaired()
  local list = {}
  for id, h in pairs(R.heard) do if now() - h < 12 then list[#list + 1] = { id = id, t = h } end end
  table.sort(list, function(a, b) return a.t > b.t end)
  return list
end
function finishPair(n, turtle)
  S.n, S.wid = n, turtle
  os.setComputerLabel(label())
  save(); addLog("paired with Weaver-" .. ("%02d"):format(n))
  R.relink = nil
end

local function pumpPairing()
  local p, r = R.pair, R.relink
  if p and not p.paired then
    if not p.n then
      if due("pair") then pcall(rednet.broadcast, { type = "number_req", turtle = p.turtle }, PROTOCOL) end
    elseif due("pair") then
      pcall(rednet.send, p.turtle, { type = "pair", n = p.n }, PROTOCOL)         -- to him alone: the others stay unpaired
    end
  end
  if r and due("relink", 3) then pcall(rednet.broadcast, { type = "relink", n = r.n }, PROTOCOL) end
end

---------------------------------------------------------------------------
-- Orders
---------------------------------------------------------------------------
-- his dock's WORLD position and facing (wizard step 3), for his GPS; also rides in `build`
function sendSite()
  local s = S.site
  if S.n and siteOK(s) then tx({ type = "site", dock = { x = s.dx, y = s.dy, z = s.dz }, dh = s.dh }) end
end
local WANT = { build = "build", stop = "stop", home = "stop", reboot = "reboot", status = "status", test = "test", clear = "clear" }
-- the 4 bottom corner cells of the turned footprint, in dock coordinates (the bottom-layer cells; the Weaver marks on top)
function testCorners()
  local s = S.site
  if not (P and siteOK(s)) then return nil end
  local ew, ns = footprint(s.rot)
  local x1, x2, z1, z2 = s.cx - s.dx, s.cx + ew - 1 - s.dx, s.cz - ns + 1 - s.dz, s.cz - s.dz
  local y = s.cy + P.ys[1] - s.dy
  return { { x1, y, z1 }, { x2, y, z1 }, { x2, y, z2 }, { x1, y, z2 } }
end
function sendOrder(word)
  local want = WANT[word]
  if not want then return false end
  local corners
  if word == "test" then
    corners = testCorners()
    if not (corners and S.n) then return false end
    tx({ type = "site_set", site = S.site, build = S.name, hash = S.hash })    -- the site first: the mainframe keeps it
  end
  S.orderSeq = math.max(S.orderSeq + 1, os.epoch and os.epoch("utc") or 0)
  S.order = { want = want, word = word, seq = S.orderSeq, at = now(), first = now(), corners = corners }
  save(); addLog("order: " .. word)
  tx({ type = "order", want = want, seq = S.orderSeq, corners = corners })
  return true
end
local function pumpOrder()
  local o = S.order
  if not o or o.want == "status" then return end
  local st = R.status
  local confirmed = st and ((o.want == "reboot" and R.rebootSeen) or (o.want ~= "reboot" and st.want == o.want))
  if confirmed or now() - o.first > 60 then
    if confirmed then addLog("  " .. o.word .. " confirmed") end
    S.order = nil; save(); return
  end
  if due("order") then tx({ type = "order", want = o.want, seq = o.seq, corners = o.corners }) end
end

---------------------------------------------------------------------------
-- A started build: the build message, layers (his layer and the next), gaps, the bill
---------------------------------------------------------------------------
local function sendParts(k)
  local out = R.out and R.out[k]
  if not out then
    local cells = layerToSend(k)
    local parts, chunks = math.max(1, math.ceil(#cells / PART_MAX)), {}
    for p = 1, parts do
      local c = {}
      for i = (p - 1) * PART_MAX + 1, math.min(#cells, p * PART_MAX) do c[#c + 1] = cells[i] end
      chunks[p] = c
    end
    out = { parts = parts, chunks = chunks, got = {}, n = 0 }
    R.out = R.out or {}
    R.out[k] = out
    save()
  end
  for p = 1, out.parts do
    if not out.got[p] then
      tx({ type = "layer", hash = S.hash, layer = k, total = P.total, part = p, parts = out.parts, cells = out.chunks[p] })
    end
  end
end
local function layerDone(k) local o = R.out and R.out[k]; return o and o.n >= o.parts end

local function item(c) return cellItem(c) end
function gapsReady()
  local need, list = {}, {}
  local stock = R.stock or {}
  local sorted = {}
  for i, g in ipairs(S.gaps) do sorted[#sorted + 1] = { g, i } end
  table.sort(sorted, function(a, b) if a[1][2] ~= b[1][2] then return a[1][2] < b[1][2] end; return a[2] < b[2] end)   -- by height, then the planner's order
  for i, e in ipairs(sorted) do sorted[i] = e[1] end
  local skipped = {}
  for _, g in ipairs(sorted) do
    local it = item(g)
    if skipped[it] then
    elseif (stock[it] or 0) >= (need[it] or 0) + (g.n or 1) then
      need[it] = (need[it] or 0) + (g.n or 1); list[#list + 1] = g
    else
      skipped[it] = true
    end
  end
  return list
end

local function pumpBuild()
  local st = R.status
  if not (S.started and P and st and alive()) then return end
  if st.hash ~= S.hash then
    if due("build") then tx({ type = "build", name = S.name, hash = S.hash, total = P.total }) end
    return
  end
  local sl = math.max(st.layer or 1, 1)
  for k = sl, math.min(sl + 1, P.total) do
    if not layerDone(k) and due("layer" .. k) then sendParts(k) end
  end
  if #S.gaps > 0 and not R.gapOut and st.work ~= "gap" and due("gaps", 10) then
    local list = gapsReady()
    if #list > 0 and (st.layer or 1) >= 1 then
      R.gapOut = { cells = list, at = now() }
      tx({ type = "gaps", cells = list })
    end
  end
  if R.gapOut and not R.gapOut.acked and due("gapsre", 5) then tx({ type = "gaps", cells = R.gapOut.cells }) end
  if now() - R.bills >= 30 then
    R.bills = now()
    pcall(rednet.broadcast, { type = "bill", n = S.n, bill = billLeft() }, BASE)
  end
end

function startBuild()
  if not (P and siteOK(S.site) and S.n) then return false end
  S.started = true
  R.out, R.acked = nil, {}
  save()
  tx({ type = "site_set", site = S.site, build = S.name, hash = S.hash })      -- the mainframe keeps it for a replacement
  addLog("build started: " .. tostring(S.name))
  tx({ type = "build", name = S.name, hash = S.hash, total = P.total, dock = { x = S.site.dx, y = S.site.dy, z = S.site.dz }, dh = S.site.dh })
  sendOrder("build")
  return true
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------
local function onLayerDone(msg)
  local k = msg.layer
  local cells = P and layerCells(k) or {}
  local byKey = {}
  for _, c in ipairs(cells) do byKey[c[1] .. "," .. c[2] .. "," .. c[3]] = c end
  local added = 0
  for _, s in ipairs(msg.skipped or {}) do
    local key = s[1] .. "," .. s[2] .. "," .. s[3]
    local c = byKey[key] or { s[1], s[2], s[3], s[4] }
    local dup
    for _, g in ipairs(S.gaps) do if g[1] == c[1] and g[2] == c[2] and g[3] == c[3] then dup = true end end
    if not dup then S.gaps[#S.gaps + 1] = c; added = added + 1 end
    R.shortName = s[4]
  end
  addLog(("Weaver: layer %d done%s"):format(k, added > 0 and (", " .. added .. " gaps") or ""))
  for _, b in ipairs(msg.blocked or {}) do addLog(("  blocked at %d %d %d: %s"):format(b[1], b[2], b[3], tostring(b[5]))) end
  if R.out then R.out[k] = nil end
  save()
end

local function onGapsFilled(msg)
  R.gapOut = nil
  local filled = {}
  for _, c in ipairs(msg.cells or {}) do filled[c[1] .. "," .. c[2] .. "," .. c[3]] = true end
  local rest = {}
  for _, g in ipairs(S.gaps) do if not filled[g[1] .. "," .. g[2] .. "," .. g[3]] then rest[#rest + 1] = g end end
  S.gaps = rest
  local cols = gapColumns()
  local held = {}
  for _, h in ipairs(S.held) do
    if cols[h[1] .. "," .. h[3]] then held[#held + 1] = h else S.gaps[#S.gaps + 1] = h end   -- the column is open: they are gaps now
  end
  S.held = held
  addLog(("Weaver: filled %d gaps, %d left"):format(#(msg.cells or {}), #S.gaps))
  save()
end

function onWeaver(from, msg)
  local t = msg.type
  if t == "hello" and not S.n then R.heard[tonumber(msg.id) or from] = now(); return end
  if t == "number" then
    if R.pair and msg.turtle == R.pair.turtle then R.pair.n = msg.n; R.mfSeen = now() end
    return
  end
  if t == "paired" then
    if R.pair and from == R.pair.turtle and msg.n == R.pair.n then R.pair.paired = true; finishPair(msg.n, from) end
    return
  end
  if t == "site" then
    if R.relink and msg.n == R.relink.n then R.relink.site, R.mfSeen = msg.site, now() end
    return
  end
  if t == "state" and R.relink and msg.n == R.relink.n then
    R.relink.state, R.relink.from = msg, from
    return
  end
  if msg.n == nil or msg.n ~= S.n then return end
  if t == "dock_req" then sendSite(); return end
  if t == "status" then
    local was = R.status
    if msg.gnote and msg.gnote ~= S.gnote then S.gnote = msg.gnote; addLog(msg.gnote) end
    R.status, R.seen = msg, now()
    S.wid = from
    if msg.state == "supply" and (msg.msg or ""):find("Asked storage") then R.supSince = R.supSince or now() else R.supSince = nil end
    if was and was.state ~= msg.state then
      if msg.state == "waiting" or msg.state == "blocked" or msg.state == "lost" then addLog("Weaver: " .. tostring(msg.msg)) end
    end
    if was and not R.rebootSeen and S.order and S.order.want == "reboot" and was.state ~= "reboot" and msg.state == "starting" then R.rebootSeen = true end
  elseif t == "layer_ack" then
    local o = R.out and R.out[msg.layer]
    if o and not o.got[msg.part] then o.got[msg.part] = true; o.n = o.n + 1 end
  elseif t == "layer_done" then onLayerDone(msg)
  elseif t == "gaps_ack" then if R.gapOut then R.gapOut.acked = true end
  elseif t == "gaps_filled" then onGapsFilled(msg)
  elseif t == "done" then if not R.doneLogged then R.doneLogged = true; addLog("Weaver: the build is finished") end
  end
end

function onBase(from, msg)
  if msg.type == "storage" and type(msg.items) == "table" then R.stock, R.stockSeen = msg.items, now() end
end

function pump()
  openModem()
  pumpPairing()
  pumpOrder()
  pumpBuild()
end
