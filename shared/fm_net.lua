-- fm_net.lua  --  Foreman engine: the miners' radio, keys and taps, the barrel worker, and start().
-- A part of fm.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Radio: orders out, numbers, status and dock requests in
---------------------------------------------------------------------------
function sendOrder(id)
  local dd = reg[id]
  if dd.reboot and os.epoch("utc") - (dd.rebootAt or 0) > REBOOT_WAIT then
    dd.reboot, dd.rebootAt = nil, nil
    saveCfg()
    say((dd.label or ("A " .. P.bird)) .. " never confirmed its reboot: old program? Reboot it by hand once.", K.orange)
  end
  local list = {}
  for name in pairs(capped) do list[#list + 1] = name end
  rednet.send(id, {
    type = "cmd", to = id, kind = kindOf(id), want = dd.retired and "dock" or dd.want, minY = dd.minY, maxY = dd.maxY,
    c1 = dd.r1 or 0, c2 = dd.r2 or DEF_R2, r1 = math.max(1, (dd.r1 or 0) * 16), r2 = (dd.r2 or DEF_R2) * 16 + 8,
    seq = dd.seq, reboot = dd.reboot, redock = dd.redock, retired = dd.retired == true, capped = list,
    junk = P.junk and cfg.junk or nil, hungryAt = cfg.hungryAt, fullAt = cfg.fullAt,
  }, PROTOCOL)
end
-- The bird an order is for (cmd.kind): a miner ignores orders meant for another bird
function kindOf(id)
  local l = live[id]
  return P.kind or (l and l.s.kind)
end
-- May I give this miner a number? (P.registers: the birds I number; the Overworld Foreman changes it)
function numbers(bird) return not P.registers or P.registers[bird or ""] == true end

-- A status from one of my miners: reboot confirmations, labels, adopting a numbered one I don't know
function ownStatus(from, msg)
  live[from] = { s = msg, seen = os.clock() }
  local dd = reg[from]
  if dd and dd.reboot and msg.rebootDone == dd.reboot then
    if msg.state == "rebooting" then
      dd.rebootSeen = true
    else
      -- Back up after the reboot: stop asking
      dd.reboot, dd.rebootAt, dd.rebootSeen = nil, nil, nil
      saveCfg()
      say((dd.label or P.bird) .. " is back up and carrying on.", K.lime)
      if remoteChanged then remoteChanged() end
    end
  end
  if dd and dd.redock and msg.redockDone == dd.redock then
    dd.redock = nil
    saveCfg()
    say(("%s: %s"):format(dd.label or P.bird, msg.msg or "re-docked"), K.lime)
    if remoteChanged then remoteChanged() end
  end
  if not dd and tonumber(msg.num) and not numTaken(tonumber(msg.num), from) and adoptOK() then
    adopt(from, msg)
    if remoteChanged then remoteChanged() end
  elseif dd and msg.label and msg.label ~= dd.label and not dd.retired then
    dd.label = msg.label; saveCfg()
  end
end
function adoptOK() return true end

function netLoop()
  local opened = 0
  radioOK = false
  peripheral.find("modem", function(name, m)
    rednet.open(name); opened = opened + 1
    if m.isWireless() then radioOK = true end
    return false
  end)
  if opened == 0 then
    say(("No modem! I need an ender modem to reach the %s."):format(P.birds), K.red)
    while true do draw(); os.sleep(5) end
  end
  local lastSend = -100
  while true do
    local from, msg, proto = rednet.receive(1)
    if type(msg) == "table" and proto == PROTOCOL then
      if msg.type == "register" and msg.id == from and numbers(msg.name) and numbersNow() then
        local num = assign(from, msg.want, msg.name)
        local label = nameOf(num, msg.name)
        rednet.send(from, { type = "assigned", id = from, num = num, label = label }, PROTOCOL)
        say(("%s joined the crew."):format(label))
        sendNow[from] = true
        if remoteChanged then remoteChanged() end
      elseif P.barrels and msg.type == "dock_req" and msg.id == from then
        if msg.seq ~= servedSeq[from] then
          servedSeq[from] = msg.seq
          requests[#requests + 1] = { id = from, seq = msg.seq, bucket = msg.bucket == true, fuel = tonumber(msg.fuel) or 0 }
          os.queueEvent(WORK)
        elseif lastReply[from] and lastReply[from].seq == msg.seq then
          rednet.send(from, lastReply[from], PROTOCOL)   -- he missed my answer: say it again
        end
      elseif P.barrels and (msg.type == "dock_mine" or msg.type == "dock_wrong") and msg.id == from then
        local p = probe   -- his answer to "is this dock yours?" (fm_barrels.lua serveRequest)
        if p and p.id == from and p.dock == msg.dock and not p.answer then
          p.answer = msg.type == "dock_mine" and "mine" or "wrong"
          if p.answer == "mine" then
            learnDock(p.dock, from)
            say(("Learned %s's dock."):format(reg[from] and reg[from].label or ("#" .. from)))
          else lastReply[from] = nil end
          os.queueEvent(WORK)
        end
      elseif P.barrels and msg.type == "dock_done" and msg.id == from then
        for dn, hd in pairs(holds) do if hd.id == from then holds[dn] = nil end end
        if probe and probe.id == from and not probe.answer then probe.answer = "wrong" end   -- a miner that can't answer
        os.queueEvent(WORK)
      elseif msg.type == "status" and msg.id == from then
        if ownsStatus(msg) then ownStatus(from, msg)
        elseif otherStatus then otherStatus(from, msg, proto) end
      end
    elseif type(msg) == "table" and proto == BASE and msg.type == "storage" then
      storageSeen = os.clock()
      local set = {}
      for _, n in ipairs(type(msg.overcap) == "table" and msg.overcap or {}) do set[n] = true end
      capped = set
    elseif type(msg) == "table" and remoteMessage then
      remoteMessage(from, msg, proto)
    end
    local all = os.clock() - lastSend >= SEND_EVERY
    for id in pairs(reg) do
      if all or sendNow[id] then sendOrder(id) end
    end
    sendNow = {}
    if all then lastSend = os.clock() end
    if remoteTick then remoteTick(all) end
    draw()
  end
end
-- Numbering can wait (the MD Foreman: until it has the Overworld Foreman's Canary list)
function numbersNow() return true end

-- Keys: typing into a preset field (whichever screen last tapped one), else the command bar
focusView = nil
function handleKey(e, a)
  local v = focusView
  if not (v and v.ui.page == "edit" and v.ui.edit and v.ui.edit.focus) then
    v = (termUi.page == "edit" and termUi.edit and termUi.edit.focus) and views[2] or nil
  end
  if v and not termUi.cmd then
    ui = v.ui
    local ed = ui.edit
    if e == "char" then
      local ok = ed.focus == "name" and #ed.buf < NAME_MAX
        or ed.focus ~= "name" and (a:match("%d") or (a == "-" and ed.buf == "")) and #ed.buf < 4
      if ok then ed.buf = ed.buf .. a end
    elseif e == "paste" and ed.focus == "name" then
      ed.buf = (ed.buf .. a):sub(1, NAME_MAX)
    elseif a == keys.backspace then ed.buf = ed.buf:sub(1, -2)
    elseif a == keys.enter or a == keys.numPadEnter or a == keys.tab then
      local fi = 1
      for i, f in ipairs(FIELDS) do if f == ed.focus then fi = i end end
      commitFocus(ed)
      if fi < #FIELDS then startFocus(ed, FIELDS[fi + 1]) end
    end
    ui.edit.err = nil
    return
  end
  -- Command bar (computer screen)
  ui = termUi
  if e == "char" or e == "paste" then
    if ui.cmd == nil and not (e == "char" and a == "/") then return end   -- commands start with /
    ui.cmd = ((ui.cmd or "") .. a):sub(1, 60)
  elseif a == keys.backspace and ui.cmd then
    ui.cmd = ui.cmd:sub(1, -2)
    if ui.cmd == "" then ui.cmd = nil end
  elseif (a == keys.enter or a == keys.numPadEnter) then
    if ui.cmd then
      local line = ui.cmd; ui.cmd = nil
      runCommand(line)
    elseif ui.page == "edit" and ui.edit then
      if ui.edit.confirmDel then
        deletePreset(ui.edit.idx); ui.edit, ui.page = nil, "presets"
      else
        savePreset()
      end
    end
  end
end

function inputLoop()
  while true do
    local e, a, b, c = os.pullEvent()
    local v, x, y
    if e == "monitor_touch" and a == monSide then v, x, y = views[1], b, c
    elseif e == "mouse_click" then v, x, y = views[2], b, c
    elseif e == "mouse_scroll" then
      local u = views[2].ui
      if u.page == "overview" then u.scroll = u.scroll + a
      elseif u.page == "presets" then u.lscroll = u.lscroll + a
      elseif u.page == "miner" then u.pscroll = u.pscroll + a
      elseif u.page == "rules" then u.kscroll = (u.kscroll or 1) + a end
      draw()
    elseif e == "char" or e == "key" or e == "paste" then
      handleKey(e, a); draw()
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      mon, monSide = findMonitor(); draw()
    end
    if v then
      ui = v.ui
      local wasEditing = ui.page == "edit" and ui.edit
      for _, r in ipairs(v.hits) do
        if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then
          if wasEditing then commitFocus(ui.edit) end
          r.fn()
          if ui.page == "edit" and ui.edit and ui.edit.focus then focusView = v end
          break
        end
      end
      draw()
    end
  end
end

-- Barrels: every TICK seconds (sooner when a miner asks for something)
function workerLoop()
  if not P.barrels then return os.pullEvent("never") end
  while true do
    if not paused then
      workerBusy = true
      local ok, err = pcall(barrelPass)
      workerBusy = false
      if not ok and err ~= PAUSED then say("Barrels: " .. tostring(err), K.red); writePassError("Barrel pass", err) end
      if lastNote then say(lastNote, K.orange); lastNote = nil end
      draw()
    end
    local t = os.startTimer(TICK)
    while true do
      local e, id = os.pullEvent()
      if (e == "timer" and id == t) or e == WORK then break end
    end
  end
end

-- Factory out, every half second: lava to Stock, empties back to Factory in (fm_barrels.lua factoryPass)
FACTORY_EVERY = 0.5
function factoryLoop()
  if not P.barrels then return os.pullEvent("never") end
  while true do
    if not paused and #cfg.factoryOuts > 0 then
      local ok, err = pcall(factoryPass)
      if not ok and err ~= PAUSED then say("Factory: " .. tostring(err), K.red); writePassError("Factory pass", err) end
    end
    os.sleep(FACTORY_EVERY)
  end
end

function start()
  loadCfg()
  draw()
  parallel.waitForAny(netLoop, inputLoop, workerLoop, factoryLoop)
end

