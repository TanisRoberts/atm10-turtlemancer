-- storage_defrag.lua  --  /defrag in ME mode (#126, project #122). Docs: docs/systems/storage.md.
-- Moves piles out of low-priority drives (small cells) into the highest-priority storage with room.
-- AE2 inserts at the highest priority first and extracts from the lowest, so a round trip (export a chunk into the
-- "Defrag buffer", import it all back) moves it from the lowest tier that holds it into the top tier with room.
-- Cell bytes are only as fresh as AE2's last save (up to ~5 min), so nothing is measured per trip: each item moves a
-- fixed amount (its count, less what a void drawer keeps), then it is done. Infinity cells (count 2^31-1) are skipped.
--
--   local D = dofile("storage_defrag.lua")({ ME = ME, cfg = fn, info = tbl, call = fn, env = envfile,
--                                            broadcast = fn(msg), stackOf = fn(key) })
--   D.tick() -> true when it did something (storage calls it last in every worker pass, so it yields to every job)
--   D.running(), D.start(plan), D.stop(), D.plan(), D.msg(), D.screen(view, ui)
-- Never counted, never storage: the buffer is a job inventory (cfg.defragBuffer). Whatever is left in it goes back
-- into AE2 (at boot, after a run, every 30 s).
return function(o)
  local D = {}
  local ME = o.ME
  local KEEP_FREE = 0.05           -- stop when the upper tiers have less than this fraction free
  local BC_EVERY, DRAIN_EVERY = 3, 30
  local SPIN = 8                   -- drives per rack
  local INF = 2147483647           -- ExtendedAE infinity cells report this much of their item
  local TRIP_S = 1.5               -- seconds per round trip, for the time estimate (an export + an import + a drive read)

  local tune = o.env.new("storage.env", "Storage settings.", {
    { "DEFRAG_SKIP", "", "Items /defrag never moves: item ids or #tags, comma separated." },
    { "DEFRAG_MIN", 0, "/defrag skips piles smaller than this many items. 0 = one stack." },
    { "DEFRAG_VOID", "", "Items that sit behind a void drawer on a priority-9999 storage bus, <item id>=<items the drawer keeps>, comma separated (minecraft:deepslate=256000). /defrag warns that the rest is voided." },
  })
  tune.load()

  local function setOf(raw)
    local ids, tags = {}, {}
    for part in tostring(raw or ""):gmatch("[^,]+") do
      local w = part:match("^%s*(%S+)%s*$")
      if w then if w:sub(1, 1) == "#" then tags[w:sub(2)] = true else ids[w] = true end end
    end
    return ids, tags
  end
  local function voids()
    tune.refresh()
    local out = {}
    for part in tostring(tune.v.DEFRAG_VOID or ""):gmatch("[^,]+") do
      local id, keep = part:match("^%s*(%S+)%s*=%s*(%d+)%s*$")
      if id then out[id] = tonumber(keep) end
    end
    return out
  end
  local function nameOf(key) return (key:match("^(.-)#") or key) end
  local function label(key)
    if o.info[key] and o.info[key].label then return o.info[key].label end
    return (nameOf(key):gsub("^[^:]*:", ""):gsub("_", " "))
  end
  local function stackOf(key) return (o.stackOf and o.stackOf(key)) or (o.info[key] and o.info[key].max) or 64 end

  local function short(n)
    if n >= 1e9 then return ("%.1fG"):format(n / 1e9) end
    if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
    if n >= 1e3 then return ("%dk"):format(math.floor(n / 1e3)) end
    return tostring(math.floor(n))
  end
  D.short = short

  ---------------------------------------------------------------------------
  -- Tiers: drives grouped by priority, highest first
  ---------------------------------------------------------------------------
  function D.tiers()
    local drives = o.call(ME.name(), "getDrives")
    if type(drives) ~= "table" then return nil end
    local by, list = {}, {}
    for _, d in ipairs(drives) do
      local p = d.priority or 0
      local t = by[p]
      if not t then t = { prio = p, drives = 0, used = 0, total = 0, cells = 0 }; by[p] = t; list[#list + 1] = t end
      t.drives = t.drives + 1
      for _, c in pairs(d.cells or {}) do
        t.used = t.used + (c.usedBytes or 0); t.total = t.total + (c.maxBytes or 0); t.cells = t.cells + 1
      end
    end
    table.sort(list, function(a, b) return a.prio > b.prio end)
    -- Tiers with no sized cells (empty drives, Infinity/Bulk only) can't hold a pile: leave them out (#137)
    local sized, ignored = {}, {}
    for _, t in ipairs(list) do
      t.racks = math.ceil(t.drives / SPIN)
      if t.total > 0 then sized[#sized + 1] = t else ignored[#ignored + 1] = t end
    end
    return sized, ignored
  end
  local function lowUsed(tiers)
    local u = 0
    for i = 2, #tiers do u = u + tiers[i].used end
    return u
  end
  -- The destination is every sized tier except the lowest. Returns its combined free fraction and a text naming each tier.
  -- Bytes come from getDrives, stale up to one AE2 autosave: fine for a rough "is there room" guard, not for exact accounting.
  local function destFree(tiers)
    local used, total, parts = 0, 0, {}
    for i = 1, #tiers - 1 do
      local t = tiers[i]
      used = used + t.used; total = total + t.total
      parts[#parts + 1] = ("p%d: %d%% free"):format(t.prio, math.floor((t.total - t.used) / t.total * 100 + 0.5))
    end
    if total <= 0 then return 0, "" end
    return (total - used) / total, table.concat(parts, ", ")
  end

  ---------------------------------------------------------------------------
  -- The plan: what a run would move, biggest piles first, and what it would void
  ---------------------------------------------------------------------------
  function D.buffer() return o.cfg().defragBuffer end
  local function bufferSize()
    local b = D.buffer()
    if not b or not peripheral.isPresent(b) then return nil end
    return o.call(b, "size")
  end

  function D.plan()
    local p = { queue = {}, warn = {}, voids = {}, infinite = 0, toMove = 0 }
    p.tiers, p.ignored = D.tiers()
    if not p.tiers then p.warn[#p.warn + 1] = "ME offline."; return p end
    if #p.tiers < 2 then p.same = true; p.warn[#p.warn + 1] = "Nothing to defrag towards: fewer than two priorities with sized cells." end
    if not D.buffer() then p.warn[#p.warn + 1] = "No Defrag buffer: /assign one." p.noBuffer = true
    elseif not bufferSize() then p.warn[#p.warn + 1] = "The Defrag buffer is not on the cable."; p.noBuffer = true end
    local list = ME.items() or {}
    local skipIds, skipTags = setOf(tune.v.DEFRAG_SKIP)
    local minN = tonumber(tune.v.DEFRAG_MIN) or 0
    local vd = voids()
    local topRoom = 0
    for i = 1, #p.tiers - 1 do topRoom = topRoom + (p.tiers[i].total - p.tiers[i].used) * 8 end
    for _, e in ipairs(list) do
      local skip = skipIds[e.name] or skipIds[e.key]
      if e.count >= INF then skip = true; p.infinite = p.infinite + 1 end
      local tags = o.info[e.key] and o.info[e.key].tags
      if not skip and tags then for t in pairs(skipTags) do if tags[t] then skip = true end end end
      if not skip and e.count >= math.max(minN, minN == 0 and stackOf(e.key) or 0) then
        p.queue[#p.queue + 1] = { key = e.key, name = e.name, label = label(e.key), count = e.count, toMove = e.count }
      end
    end
    local size = bufferSize()
    local trips = 0
    table.sort(p.queue, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.key < b.key end)
    for _, e in ipairs(p.queue) do
      local keep = vd[e.name]
      if keep then
        e.void = keep
        e.toMove = math.max(0, e.count - keep)
        if e.count > keep then
          p.voids[#p.voids + 1] = ("%s: %s, drawer keeps %s, rest voided"):format(e.label, short(e.count), short(keep))
        end
      elseif e.count > topRoom and topRoom > 0 and not p.same then
        p.voids[#p.voids + 1] = ("%s: %s, more than the top tier can take (~%s)"):format(e.label, short(e.count), short(topRoom))
        e.big = true
      end
    end
    for _, e in ipairs(p.queue) do
      p.toMove = p.toMove + e.toMove
      if size then trips = trips + math.ceil(e.toMove / (size * stackOf(e.key))) end
    end
    p.minutes = math.max(1, math.ceil(trips * TRIP_S / 60))
    return p
  end

  ---------------------------------------------------------------------------
  -- The run
  ---------------------------------------------------------------------------
  local S = { running = false, done = 0, left = 0, freed = 0, moved = 0, remain = 0, item = nil, reason = nil, voided = {}, errors = {} }
  local queue, idx, cur = {}, 1, nil
  local stopReq, lastBc, lastDrain, drainDue = false, -100, -100, true
  D.state = S

  function D.running() return S.running end

  function D.msg()
    return { type = "defrag", running = S.running, item = S.item, done = S.done, left = S.left,
             moved = S.moved, toMove = S.moved + S.remain, freedBytes = S.freed }
  end
  local function broadcast()
    lastBc = os.clock()
    if o.broadcast then o.broadcast(D.msg()) end
  end

  -- Put whatever is in the buffer back into AE2. Returns true when it moved something.
  function D.drain()
    local b = D.buffer()
    drainDue = false; lastDrain = os.clock()
    if not b or not ME.online() or not peripheral.isPresent(b) then return false end
    local moved = false
    local list = o.call(b, "list")
    if type(list) ~= "table" then return false end
    for slot, it in pairs(list) do
      local key = it.name .. (it.nbt and ("#" .. it.nbt) or "")
      if ME.import(b, slot, it.count, key) > 0 then moved = true end
    end
    return moved
  end
  local function leftInBuffer()
    local b = D.buffer()
    local list = b and peripheral.isPresent(b) and o.call(b, "list")
    return type(list) == "table" and next(list) ~= nil
  end

  local function finish(reason)
    S.running, S.reason, S.item, cur = false, reason, nil, nil
    S.left = 0
    D.drain()
    broadcast()
  end

  function D.start(plan)
    if S.running then return false end
    plan = plan or D.plan()
    if plan.same or plan.noBuffer or not plan.tiers then return false, plan.warn[1] end
    if leftInBuffer() then D.drain() end
    queue, idx, cur, stopReq = plan.queue, 1, nil, false
    S = { running = true, done = 0, left = #queue, freed = 0, moved = 0, remain = plan.toMove or 0, item = nil,
          reason = nil, voided = {}, errors = {}, startLow = lowUsed(plan.tiers), total = #queue }
    D.state = S
    broadcast()
    os.queueEvent("storage_work")
    return true
  end

  function D.stop() if S.running then stopReq = true; os.queueEvent("storage_work") end end

  -- One step: one round trip of the current item (or move on to the next). Worker calls this when it has nothing else to do.
  -- An item is done once its whole amount has gone through the buffer: AE2 extracts lowest priority first and inserts
  -- highest first, so every unit has then had its chance to move up. The only live check is the grid's item count.
  local function step()
    if stopReq then stopReq = false; finish("stopped"); return true end
    if not ME.online() then return false end
    if not cur then
      local e = queue[idx]
      if not e then finish("done"); return true end
      idx = idx + 1
      local have = ME.count(e.key)
      S.item, S.left = e.label, #queue - idx + 1
      if not have or have <= 0 then S.remain = S.remain - e.toMove; S.done = S.done + 1; return true end
      cur = { e = e, have = have, left = math.min(e.toMove, have), trips = 0 }
      S.remain = S.remain - e.toMove + cur.left
      return true
    end
    local tiers = D.tiers()
    if not tiers then return false end
    local free, why = destFree(tiers)
    if free < KEEP_FREE then finish("upper tiers nearly full (" .. why .. ")"); return true end
    local b, size = D.buffer(), bufferSize()
    if not size then finish("buffer missing"); return true end
    local e = cur.e
    local cap = size * stackOf(e.key)
    local want = math.min(cur.left, cap)
    local moved = want > 0 and ME.export(e.key, want, b) or 0
    cur.trips = cur.trips + 1
    if moved <= 0 then S.done = S.done + 1; S.remain = S.remain - cur.left; cur = nil; return true end
    -- everything back in: the highest tier with room takes it (one call drains every slot)
    ME.importAll(b, e.key, moved)
    if leftInBuffer() then
      D.drain()
      if leftInBuffer() then finish("AE2 would not take the items back; they stay in the buffer"); return true end
    end
    cur.left = cur.left - moved
    S.moved = S.moved + moved
    S.remain = S.remain - moved
    local after = ME.count(e.key) or cur.have
    if after < cur.have then
      local lost = cur.have - after
      S.voided[#S.voided + 1] = { label = e.label, n = lost, expected = e.void ~= nil }
      cur.have = after
      if not e.void then S.done = S.done + 1; S.remain = S.remain - cur.left; cur = nil; return true end   -- a void nobody listed: leave this item alone
    end
    local t2 = D.tiers()
    if t2 then S.freed = math.max(0, S.startLow - lowUsed(t2)) end    -- bytes lag up to one AE2 save
    if cur.left <= 0 then S.done = S.done + 1; cur = nil end
    return true
  end

  -- Called by storage's worker as its last job each pass.
  function D.tick()
    if S.running then
      local ok, did = pcall(step)
      if not ok then S.errors[#S.errors + 1] = tostring(did); finish("error: " .. tostring(did)); return true end
      if S.running and os.clock() - lastBc >= BC_EVERY then broadcast() end
      return did
    end
    if D.buffer() and (drainDue or os.clock() - lastDrain >= DRAIN_EVERY) and ME.on() and ME.online() then
      return D.drain()
    end
    return false
  end

  ---------------------------------------------------------------------------
  -- The pages: Start (tiers, what would move, warnings) and Progress
  ---------------------------------------------------------------------------
  function D.screen(view, ui)
    local page = S.running and "run" or "start"
    local plan = (not S.running) and D.plan() or nil
    local function put(lines, kind, a, b, c) lines[#lines + 1] = { kind = kind, a = a, b = b, c = c } end
    local function lines()
      local out = {}
      if page == "start" then
        for _, w in ipairs(plan.warn) do put(out, "alert", w, nil, "warn") end
        put(out, "section", "Tiers")
        for _, t in ipairs(plan.tiers or {}) do
          local rack = t.racks == 1 and "rack" or "racks"
          put(out, "kv", ("P%d: %d %s, %d drives"):format(t.prio, t.racks, rack, t.drives),
            ("%s/%s bytes"):format(short(t.used), short(t.total)))
        end
        for _, t in ipairs(plan.ignored or {}) do
          put(out, "text", ("p%d: %d %s, no sized cells: ignored"):format(t.prio, t.drives, t.drives == 1 and "drive" or "drives"), nil, "dim")
        end
        if #plan.voids > 0 then
          put(out, "section", "Will be voided")
          for _, s in ipairs(plan.voids) do put(out, "alert", s, nil, "warn") end
        end
        if plan.infinite > 0 then
          put(out, "text", ("%d items from infinity cells: skipped"):format(plan.infinite), nil, "dim")
        end
        if #plan.queue > 0 then put(out, "text", ("%s items to move, about %d min"):format(short(plan.toMove), plan.minutes), nil, "dim") end
        put(out, "section", ("Would move (%d, biggest first)"):format(#plan.queue))
        for i, e in ipairs(plan.queue) do
          if i > 60 then put(out, "text", ("... and %d more"):format(#plan.queue - 60), nil, "dim"); break end
          put(out, "kv", e.label, short(e.count))
        end
      else
        local st = S
        if st.running then put(out, "kv", "Item now", st.item or "starting...")
        else put(out, "kv", "Finished", st.reason or "") end
        put(out, "kv", "Items done", ("%d of %d"):format(st.done, st.total or 0))
        put(out, "kv", "Items left", tostring(st.left))
        put(out, "kv", "Moved", ("%s of %s"):format(short(st.moved or 0), short((st.moved or 0) + (st.remain or 0))))
        put(out, "kv", "Freed since last save", short(st.freed or 0) .. " bytes")
        for _, vd in ipairs(st.voided or {}) do
          put(out, "alert", ("%s: %s voided"):format(vd.label, short(vd.n)), nil, vd.expected and "warn" or "bad")
        end
      end
      return out
    end
    local function draw(view)
      if page == "run" and not S.running and not S.reason then page = "start" end
      local running = S.running
      view:header("DEFRAG", { state = running and "working" or (page == "run" and "done" or nil),
        color = running and "busy" or (page == "run" and "good" or nil) })
      local r = view:rect()
      local rows = lines()
      local avail = math.max(r.y2 - r.y1 - 1, 1)
      local pages = math.max(1, math.ceil(#rows / avail))
      view.pages = pages
      view.page = math.min(math.max(view.page or 1, 1), pages)
      local w, y = view.W - 2, r.y1
      for i = (view.page - 1) * avail + 1, math.min(#rows, view.page * avail) do
        local l = rows[i]
        if l.kind == "section" then view:section(2, y, w, l.a)
        elseif l.kind == "kv" then view:kv(2, y, w, l.a, l.b, l.c)
        elseif l.kind == "alert" then view:alert(2, y, w, l.a, l.c)
        else view:put(2, y, ui.text.fit(l.a, w), l.c or "fg", "bg") end
        y = y + 1
      end
      if running then
        view:buttons(2, r.y2, { { label = "Stop", style = "danger", id = "stop", fn = function() D.stop() end } })
      elseif page == "start" then
        local can = not (plan.same or plan.noBuffer or not plan.tiers or #plan.queue == 0)
        view:buttons(2, r.y2, { { label = "Start", style = "primary", id = "start", enabled = can, fn = function()
          local ok, why = D.start(plan)
          if ok then page = "run"; view.page = 1 elseif why then ui.say(why, "bad") end
        end } })
      else
        view:buttons(2, r.y2, { { label = "Again", id = "again", fn = function() page = "start"; plan = D.plan(); view.page = 1 end } })
      end
      view:footer({ back = function() ui.quit() end })
    end
    view.page = 1
    ui.run({ view }, function(vw)
      if S.running and page == "start" then page = "run" end
      draw(vw)
    end, { tick = 1 })
  end

  return D
end
