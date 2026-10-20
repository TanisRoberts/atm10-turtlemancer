-- fm_remote.lua  --  Foreman engine: the remote link between the dimension Foremans and the Overworld Foreman
-- (protocol tanis-remote, docs/systems/miner.md). A part of fm.lua (one shared environment: see there).
--   A dimension Foreman (P.remote = "dimension") publishes its miners (`fleet`) and does what the remote asks
--   (`remote_cmd`) exactly as if it was tapped on its own screen.
--   The Overworld Foreman (P.remote = "hub") mirrors every fleet, shows those miners with its own (Starlings), and
--   turns a tap on one of them into a `remote_cmd` to his Foreman. It never sends `cmd` to another Foreman's miner.
--   Once only, the MD Foreman takes over the Canary registry from the Overworld Foreman (numbers, retired numbers).
REMOTE = "tanis-remote"
local RESEND, GIVE_UP, FLEET_STALE = 3, 30, 30   -- seconds
local KIND_RANK = { canary = 1, firecrest = 2, starling = 3 }

local function copyEntry(d)
  return { num = d.num, label = d.label, retired = d.retired, want = d.want, minY = d.minY, maxY = d.maxY,
           r1 = d.r1, r2 = d.r2, pMin = d.pMin, pMax = d.pMax, pR1 = d.pR1, pR2 = d.pR2, seq = d.seq, reboot = d.reboot }
end

---------------------------------------------------------------------------
-- A dimension Foreman (MD, Nether)
---------------------------------------------------------------------------
if P.remote == "dimension" then
  local dirty, lastFleet, lastAsk = true, -100, -100
  local done = {}          -- rseq -> true: remote orders already carried out (a resend is only acked again)

  function remoteChanged() dirty = true end

  local function publish()
    local miners = {}
    for id, d in pairs(reg) do miners[id] = copyEntry(d) end
    local line, col = barrelLine()
    rednet.broadcast({ type = "fleet", kind = P.kind, bird = P.bird, birds = P.birds, short = P.short, title = P.title,
      name = P.name, dim = P.dim, foreman = os.getComputerID(), miners = miners, presets = cfg.presets,
      line = line, full = barrel.outFull == true, fullAt = cfg.fullAt, hungryAt = cfg.hungryAt, lava = P.lava,
      fuelTarget = P.fuelTarget, imported = numbersNow() }, REMOTE)
    dirty, lastFleet = false, os.clock()
  end

  function remoteTick(all)
    if not rednet.isOpen() then return end
    if dirty or os.clock() - lastFleet >= SEND_EVERY then publish() end
    if P.kind == "canary" and not cfg.imported and os.clock() - lastAsk >= 10 then
      rednet.broadcast({ type = "registry_req", kind = P.kind, foreman = os.getComputerID() }, REMOTE)
      lastAsk = os.clock()
    end
  end

  local OPS = { order = true, pick = true, reboot = true, retire = true, presets = true }
  local function carryOut(m)
    local d = m.id and reg[m.id]
    if m.op == "presets" then
      if type(m.presets) ~= "table" then return false, "no presets" end
      cfg.presets = {}
      for _, p in ipairs(m.presets) do cfg.presets[#cfg.presets + 1] = copyPreset(p) end
      saveCfg(); remoteChanged()
      say("Presets changed on the Overworld Foreman.", K.lightBlue)
      return true
    end
    if not d then return false, "I don't know that miner" end
    if m.op == "pick" or (m.op == "order" and m.pMin) then
      pick(m.id, tonumber(m.pMin) or d.pMin, tonumber(m.pMax) or d.pMax, tonumber(m.pR1) or d.pR1, tonumber(m.pR2) or d.pR2)
    end
    if m.op == "order" then
      order(m.id, m.want == "run" and "run" or "dock")
      say(("%s: %s from the Overworld Foreman."):format(d.label or P.bird, m.want == "run" and "START" or "STOP + DOCK"), K.lightBlue)
    elseif m.op == "reboot" then
      requestReboot(m.id)
      say(("%s: reboot from the Overworld Foreman."):format(d.label or P.bird), K.purple)
    elseif m.op == "retire" then
      retire(m.id)
      say(("%s retired from the Overworld Foreman."):format(d.label or P.bird), K.orange)
    end
    return true
  end

  -- The MD Foreman: the Overworld Foreman's Canary registry, once. Numbers and retired numbers are kept;
  -- a Canary I already know keeps my entry.
  local function import(m)
    for id, d in pairs(type(m.miners) == "table" and m.miners or {}) do
      id = tonumber(id)
      if id and not reg[id] and type(d) == "table" and tonumber(d.num) then
        local e = newEntry(tonumber(d.num))
        for k, v in pairs(d) do e[k] = v end
        reg[id] = e
      end
    end
    for n, l in pairs(type(m.retiredNums) == "table" and m.retiredNums or {}) do cfg.retiredNums[n] = cfg.retiredNums[n] or l end
    cfg.nextNum = math.max(cfg.nextNum, tonumber(m.nextNum) or 1)
    for _, d in pairs(reg) do cfg.nextNum = math.max(cfg.nextNum, (d.num or 0) + 1) end
    cfg.imported = true
    saveCfg(); remoteChanged()
    say(("Took over the %s list from the Overworld Foreman."):format(P.bird), K.lime)
  end

  function remoteMessage(from, m, proto)
    if proto ~= REMOTE then return end
    if m.type == "remote_cmd" and m.kind == P.kind and OPS[m.op] and m.rseq then
      local ok, why = true, nil
      if not done[m.rseq] then
        ok, why = carryOut(m)
        done[m.rseq] = true
      end
      rednet.send(from, { type = "remote_ack", rseq = m.rseq, kind = P.kind, ok = ok, msg = why }, REMOTE)
      publish()
    elseif m.type == "caps" and type(m.capped) == "table" and not (storageSeen and os.clock() - storageSeen < 30) then
      local set = {}
      for _, n in ipairs(m.capped) do set[n] = true end
      capped = set
    elseif m.type == "registry" and m.kind == P.kind and P.kind == "canary" then
      if not cfg.imported then import(m) end
      rednet.send(from, { type = "registry_ack", kind = P.kind }, REMOTE)
    end
  end

  -- Until it has the Overworld Foreman's list, the MD Foreman neither numbers nor adopts Canaries (the Overworld
  -- Foreman still owns them, so there's only ever one brain). /fresh starts without it.
  if P.kind == "canary" then
    function numbersNow() return cfg.imported == true end
    function adoptOK() return cfg.imported == true end
    function remoteCommand(cmd)
      if cmd ~= "fresh" then return false end
      cfg.imported = true
      saveCfg(); remoteChanged()
      say("Numbering Canaries from here on, without the Overworld Foreman's list.", K.orange)
      return true
    end
  end
end

---------------------------------------------------------------------------
-- The Overworld Foreman: the remote for every miner
---------------------------------------------------------------------------
if P.remote == "hub" then
  fleets = {}              -- kind -> { m = last fleet message, from = its computer, seen = os.clock() }
  local pending = {}       -- rseq -> { to, msg, nextAt, untilT, label }
  local rseqN, lastCaps = 0, -100

  -- Mirrored miners: id -> entry (with _kind), from every fleet heard
  local function mirrorOf(id)
    for kind, f in pairs(fleets) do
      local d = f.m.miners[id]
      if d then d._kind = kind; return d, f end
    end
  end
  local own = entry
  function entry(id) return own(id) or (mirrorOf(id)) end
  function allIds()
    local out, seen = {}, {}
    for id in pairs(reg) do out[#out + 1] = id; seen[id] = true end
    for _, f in pairs(fleets) do
      for id in pairs(f.m.miners) do if not seen[id] then out[#out + 1] = id; seen[id] = true end end
    end
    return out
  end
  local function kindOfEntry(id)
    if reg[id] then local l = live[id]; return l and l.s.kind or "starling" end
    local d = mirrorOf(id)
    return d and d._kind
  end
  function sortKey(id) return (KIND_RANK[kindOfEntry(id) or ""] or 9) * 10000 + (entry(id).num or 0) end

  -- Mine: Starlings, and the Canaries until the MD Foreman has taken them over
  local function mine(kind) return kind == "starling" or (kind == "canary" and not cfg.handedOver) end
  function ownsStatus(s) return mine(s and s.kind) end
  function numbers(bird) return bird == "Starling" or (bird ~= nil and bird ~= "Firecrest" and not cfg.handedOver) end
  function otherStatus(from, msg) if mirrorOf(from) then live[from] = { s = msg, seen = os.clock() } end end

  function ownerLine(id)
    if reg[id] then return "me (no End base)" end
    local _, f = mirrorOf(id)
    if not f then return "?" end
    local ago = math.floor(os.clock() - f.seen)
    return ((f.m.name or "?"):gsub("^the ", "")) .. (ago > FLEET_STALE and (", not heard " .. fmtAgo(ago)) or "")
  end
  function presetsOf(id)
    if reg[id] then return cfg.presets end
    local _, f = mirrorOf(id)
    return f and f.m.presets or {}
  end
  -- The presets page edits one Foreman's list: mine, or a dimension Foreman's (ui.pset = its kind)
  function presetList()
    local f = ui.pset and fleets[ui.pset]
    return f and f.m.presets or cfg.presets
  end
  function presetSetName()
    local f = ui.pset and fleets[ui.pset]
    return f and f.m.short or "Starlings"
  end
  function nextPresetSet()
    local kinds = {}
    for k in pairs(fleets) do kinds[#kinds + 1] = k end
    table.sort(kinds, function(a, b) return (KIND_RANK[a] or 9) < (KIND_RANK[b] or 9) end)
    local nxt = nil
    if not ui.pset then nxt = kinds[1] else
      for i, k in ipairs(kinds) do if k == ui.pset then nxt = kinds[i + 1] end end
    end
    ui.pset = nxt
  end

  -- Ask a miner's own Foreman to do something; resent until it says it did
  local function send(id, op, args, label)
    local d, f = mirrorOf(id)
    local kind = d and d._kind or (op == "presets" and args.kind)
    f = f or (kind and fleets[kind])
    if not f then say("I haven't heard that miner's Foreman yet.", K.red); return false end
    rseqN = rseqN + 1
    local rseq = os.getComputerID() .. ":" .. os.epoch("utc") .. ":" .. rseqN
    local msg = { type = "remote_cmd", kind = kind, op = op, id = id, rseq = rseq }
    for k, v in pairs(args or {}) do msg[k] = v end
    pending[rseq] = { to = f.from, msg = msg, nextAt = os.clock() + RESEND, untilT = os.clock() + GIVE_UP, label = label or f.m.title }
    rednet.send(f.from, msg, REMOTE)
    return true
  end

  local baseOrder, basePick, baseReboot, baseRetire = order, pick, requestReboot, retire
  function order(id, want)
    if reg[id] then return baseOrder(id, want) end
    local d = mirrorOf(id)
    if not d or d.retired then return end
    local args = { want = want }
    if want == "run" then
      args.pMin, args.pMax, args.pR1, args.pR2 = d.pMin, d.pMax, d.pR1, d.pR2
      d.minY, d.maxY, d.r1, d.r2 = d.pMin, d.pMax, d.pR1, d.pR2
    end
    d.want = want
    send(id, "order", args, d.label)
  end
  function pick(id, a, b, r1, r2)
    if reg[id] then return basePick(id, a, b, r1, r2) end
    local d = mirrorOf(id)
    if not d then return end
    d.pMin, d.pMax, d.pR1, d.pR2 = a, b, r1, r2
    send(id, "pick", { pMin = a, pMax = b, pR1 = r1, pR2 = r2 }, d.label)
  end
  function requestReboot(id)
    if reg[id] then return baseReboot(id) end
    local d = mirrorOf(id)
    if not d then return end
    d.reboot = d.reboot or os.epoch("utc")
    send(id, "reboot", {}, d.label)
  end
  function retire(id)
    if reg[id] then return baseRetire(id) end
    local d = mirrorOf(id)
    if not d then return end
    d.retired = true
    send(id, "retire", {}, d.label)
  end
  -- After an edit on the presets page: mine are saved, a dimension Foreman's are sent to it
  function presetsChanged()
    if not ui.pset then saveCfg(); return end
    local f = fleets[ui.pset]
    if f then send(nil, "presets", { kind = ui.pset, presets = f.m.presets }, f.m.title) end
  end

  -- The second row of the overview: how each dimension Foreman is doing, and storage
  function hubLine()
    local parts = {}
    local kinds = {}
    for k in pairs(fleets) do kinds[#kinds + 1] = k end
    table.sort(kinds, function(a, b) return (KIND_RANK[a] or 9) < (KIND_RANK[b] or 9) end)
    local col = K.lightGrey
    for _, k in ipairs(kinds) do
      local f = fleets[k]
      local st = os.clock() - f.seen > FLEET_STALE and "not heard" or f.m.full and "OUTPUT FULL" or "ok"
      if st ~= "ok" then col = K.orange end
      parts[#parts + 1] = (f.m.short or k) .. " " .. st
    end
    if #parts == 0 then parts[1] = "No MD or Nether Foreman heard yet" end
    parts[#parts + 1] = storageSeen and (os.clock() - storageSeen < 30) and "storage ok" or "storage ?"
    return table.concat(parts, "   "), col
  end

  -- Hand the Canaries over to the MD Foreman: everyone whose label isn't a Starling's
  local function canaryList()
    local miners = {}
    for id, d in pairs(reg) do
      if not (d.label or ""):find("^Starling%-") then miners[id] = copyEntry(d) end
    end
    return miners
  end
  local function handOver(from)
    local miners = cfg.handed or canaryList()
    rednet.send(from, { type = "registry", kind = "canary", miners = miners, retiredNums = cfg.retiredNums,
      nextNum = cfg.nextNum, presets = cfg.presets }, REMOTE)
  end
  local function handedOver()
    if cfg.handedOver then return end
    cfg.handed = canaryList()
    for id in pairs(cfg.handed) do reg[id] = nil end
    cfg.handedOver = true
    saveCfg()
    say("The Canaries are the MD Foreman's now: I'm their remote.", K.lime)
  end

  function remoteMessage(from, m, proto)
    if proto == "tanis-nether" then
      if m.type == "status" and m.id == from then otherStatus(from, m) end
      return
    end
    if proto ~= REMOTE then return end
    if m.type == "fleet" and type(m.miners) == "table" and m.kind then
      local was = fleets[m.kind]
      fleets[m.kind] = { m = m, from = from, seen = os.clock() }
      -- a miner I mirror that I also still own (the hand-over is in flight): the dimension Foreman wins
      if m.kind == "canary" and m.imported and not cfg.handedOver then handedOver() end
      if not was then say(("Heard %s."):format(m.title or m.kind), K.lime) end
    elseif m.type == "remote_ack" and m.rseq and pending[m.rseq] then
      local p = pending[m.rseq]
      pending[m.rseq] = nil
      if m.ok == false then say(("%s: %s"):format(p.label or "?", m.msg or "refused"), K.red) end
    elseif m.type == "registry_req" and m.kind == "canary" then
      handOver(from)
    elseif m.type == "registry_ack" and m.kind == "canary" then
      handedOver()
    end
  end

  function remoteTick()
    for rseq, p in pairs(pending) do
      if os.clock() > p.untilT then
        pending[rseq] = nil
        say(("%s didn't answer: is it running?"):format(p.label or "The Foreman"), K.red)
      elseif os.clock() >= p.nextAt then
        rednet.send(p.to, p.msg, REMOTE)
        p.nextAt = os.clock() + RESEND
      end
    end
    -- storage's junk caps, passed on to every dimension Foreman
    if storageSeen and os.clock() - lastCaps >= 10 then
      local list = {}
      for name in pairs(capped) do list[#list + 1] = name end
      rednet.broadcast({ type = "caps", capped = list }, REMOTE)
      lastCaps = os.clock()
    end
  end
end
