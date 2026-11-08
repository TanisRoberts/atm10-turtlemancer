-- weaver_net.lua  --  the radio: pairing, orders, layers from the Architect, supply answers, status.
-- Protocol tanis-weaver; every message carries n (the Weaver number). Formats: docs/systems/weaver.md.
-- A part of weaver.lua.

SUPPLIED = nil
NEWORDER = false
REBOOT = false
LP = {}                 -- layer parts on their way: LP[layer] = { got = {}, count = 0 }

function openModem()
  for _, sd in ipairs(peripheral.getNames()) do
    if peripheral.getType(sd) == "modem" and not rednet.isOpen(sd) then pcall(rednet.open, sd) end
  end
end

function send(msg)
  if core.chunk.busy then return end   -- the modem is off for a moment during a chunk swap
  msg.n = msg.n or S.n
  pcall(rednet.broadcast, msg, PROTOCOL)
end

function myNumber()
  local n = (os.getComputerLabel() or ""):match("^Weaver%-(%d+)$")
  return n and tonumber(n) or S.n
end

function statusMsg()
  local cells = S.work == "layer" and getLayer(S.layer) or nil
  return { type = "status", n = S.n, label = os.getComputerLabel(), id = os.getComputerID(), state = S.status, msg = S.msg,
           want = S.want, build = S.build, hash = S.hash, layer = S.layer, total = S.total, idx = S.idx,
           cells = cells and #cells or nil, work = S.work, x = S.x, y = S.y, z = S.z, fuel = fuelLevel(),
           gaps = #GAPS, need = S.needLayer, done = S.lastDone, lost = S.lost,
           marks = S.marks and #S.marks or 0, marked = S.markDone, marking = S.markCells and #S.markCells or 0 }
end

local function resetBuild(msg)
  for k in pairs(LAYERS) do LAYERS[k] = nil end
  for _, f in ipairs(fs.list("")) do if f:match("^weaver%.L%d+$") then fs.delete(f) end end
  if fs.exists(GAPLIST) then fs.delete(GAPLIST) end
  GCELLS = nil
  GAPS = {}; saveGaps()
  S.layer, S.idx, S.work, S.skip, S.blocked, S.lastDone, S.short = 1, 1, "layer", {}, {}, nil, {}
  S.build, S.hash, S.total = msg.name, msg.hash, msg.total
end

local function addPart(msg)
  local k = msg.layer
  if k < S.layer and S.work == "layer" then send({ type = "layer_ack", layer = k, part = msg.part }); return end
  if not LAYERS[k] and not fs.exists(layerFile(k)) then
    local st = LP[k] or { got = {}, count = 0 }
    LP[k] = st
    if not st.got[msg.part] then st.got[msg.part] = msg.cells; st.count = st.count + 1 end
    if st.count >= msg.parts then
      local all = {}
      for i = 1, msg.parts do for _, c in ipairs(st.got[i]) do all[#all + 1] = c; BUILD[c[4]] = true end end
      writeT(layerFile(k), all); LAYERS[k] = all; LP[k] = nil
      if msg.total then S.total = msg.total end
      save()
    end
  end
  send({ type = "layer_ack", layer = k, part = msg.part })
end

local function handle(id, msg)
  local t = msg.type
  if t == "pair" then
    if S.n == nil or msg.n == S.n then
      S.n, S.arch = msg.n, id
      os.setComputerLabel(("Weaver-%02d"):format(msg.n)); save()
      send({ type = "paired", n = msg.n })
    end
    return
  end
  if msg.n == nil or msg.n ~= S.n then return end
  if t == "relink" then
    S.arch = id; save()
    local m = statusMsg(); m.type = "state"; send(m)
  elseif t == "build" then
    if msg.hash ~= S.hash then resetBuild(msg) else S.total = msg.total or S.total end
    save(); send({ type = "build_ack", hash = S.hash })
  elseif t == "layer" then
    if S.hash == nil then S.hash = msg.hash end
    if msg.hash == nil or msg.hash == S.hash then addPart(msg) end
  elseif t == "gaps" then
    writeT(GAPLIST, msg.cells or {}); GCELLS = nil
    for _, c in ipairs(msg.cells or {}) do S.short[c[4]] = nil end   -- ask storage for them again at the next visit
    save()
    send({ type = "gaps_ack", count = #(msg.cells or {}) })
  elseif t == "order" then
    if (msg.seq or 0) > S.orderSeq then
      S.orderSeq = msg.seq
      if msg.want == "reboot" then REBOOT = true
      elseif msg.want == "status" then send(statusMsg())
      else
        if msg.want == "test" and msg.corners and S.want ~= "build" then
          S.markCells, S.markDone = {}, #(S.marks or {})
          for _, c in ipairs(msg.corners) do S.markCells[#S.markCells + 1] = c end
        end
        if msg.want ~= "test" then S.markCells = nil end
        S.want = msg.want; NEWORDER = true
      end
      save()
    end
  elseif t == "supplied" then
    if S.sup and S.sup.seq == msg.seq and not S.sup.reply then S.sup.reply = msg; save() end
  end
end

function netLoop()
  local lastStatus, lastHello = -1e9, -1e9
  while true do
    local id, msg = rednet.receive(PROTOCOL, 1)
    if type(msg) == "table" then handle(id, msg) end
    local now = os.clock()
    if S.n == nil then
      if now - lastHello >= 3 then
        lastHello = now
        send({ type = "hello", id = os.getComputerID() })
        setStatus("pairing", "Waiting to pair, ID " .. os.getComputerID())
      end
    elseif now - lastStatus >= STATUS_EVERY then
      lastStatus = now
      send(statusMsg())
    end
  end
end
