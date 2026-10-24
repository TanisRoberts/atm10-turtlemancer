-- fm_cmd.lua  --  Foreman engine: commands typed on the computer, drawing every screen, the /assign screen.
-- A part of fm.lua (one shared environment: see there).
---------------------------------------------------------------------------
-- Commands typed on the computer (bottom row): /presets, /new, /edit, /delete, /home, /help
---------------------------------------------------------------------------
HELP = P.help or "/rules /keep <item> <n> /junk /unjunk <item> /assign /presets /new /edit /delete /reboot /redock /home"

function runCommand(line)
  local cmd, arg = line:match("^/?(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  ui = termUi
  if cmd == "" or cmd == "help" or cmd == "?" then say(HELP, K.lightBlue)
  elseif cmd == "presets" or cmd == "preset" or cmd == "settings" or cmd == "p" then ui.page, ui.edit = "presets", nil
  elseif cmd == "home" or cmd == "back" or cmd == "overview" then ui.page, ui.edit = "overview", nil
  elseif P.barrels and (cmd == "rules" or cmd == "keeps") then ui.page = "rules"
  elseif P.barrels and (cmd == "assign" or cmd == "barrels" or cmd == "dock") then openAssign()
  elseif P.barrels and cmd == "keep" then
    local item, n = arg:match("^(.-)%s+(%d+)$")
    item = resolveItem(item or arg)
    if not item then say("/keep <item> <count>, e.g. /keep bucket 4  (0 = stop keeping it)", K.red); return end
    n = tonumber(n) or 64
    setKeep(item, n)
    ui.page = "rules"
    say(n > 0 and ("Keeping %d %s in %s."):format(n, pretty(item), P.place) or ("Not keeping %s: it goes home."):format(pretty(item)),
      n > 0 and K.lime or K.orange)
  elseif P.junk and (cmd == "junk" or cmd == "unjunk") then
    local item = resolveItem(arg)
    if not item then say("/" .. cmd .. " <item>, e.g. /" .. cmd .. " netherrack", K.red); return end
    local short = item:gsub("^minecraft:", "")
    for i = #cfg.junk, 1, -1 do
      local j = cfg.junk[i]
      if j == short or j == item or ("minecraft:" .. j) == item then table.remove(cfg.junk, i) end
    end
    if cmd == "junk" then cfg.junk[#cfg.junk + 1] = short end
    saveCfg()
    for id in pairs(reg) do sendNow[id] = true end
    ui.page = "rules"
    say(cmd == "junk" and ("%s throws %s away now."):format(P.bird, pretty(item)) or ("%s brings %s home now."):format(P.bird, pretty(item)),
      cmd == "junk" and K.orange or K.lime)
  elseif cmd == "new" or cmd == "add" then openEditor(nil, arg)
  elseif cmd == "reboot" or cmd == "restart" then
    local a = arg:lower()
    if a == "" then say(("/reboot <%s number or name> or /reboot all"):format(ONE:lower()), K.red); return end
    local hits = {}
    for _, id in ipairs(allIds()) do
      local dd = entry(id)
      if not dd.retired then
        local lbl = (dd.label or nameOf(dd.num)):lower()
        if a == "all" or lbl == a or tonumber(a) == dd.num or lbl:find(a, 1, true) then hits[#hits + 1] = id end
      end
    end
    if #hits == 0 then say(("No %s matches %s"):format(ONE, arg), K.red); return end
    if a ~= "all" and #hits > 1 then say(("%s matches %d %s: be more exact"):format(arg, #hits, P.birds), K.red); return end
    for _, id in ipairs(hits) do requestReboot(id) end
    say(#hits == 1 and ((entry(hits[1]).label or ONE) .. ": reboot sent.") or
      ("Reboot sent to %d %s."):format(#hits, P.birds), K.purple)
  elseif cmd == "redock" then
    local a = arg:lower()
    if a == "" then say(("/redock <%s number or name> or /redock all"):format(ONE:lower()), K.red); return end
    local n = 0
    for _, id in ipairs(allIds()) do
      local dd = entry(id)
      local lbl = (dd.label or nameOf(dd.num)):lower()
      if not dd.retired and (a == "all" or lbl == a or tonumber(a) == dd.num or lbl:find(a, 1, true)) then
        requestRedock(id); n = n + 1
      end
    end
    say(n == 0 and ("No %s matches %s"):format(ONE, arg) or ("Re-dock sent to %d: each sets his dock up where he stands."):format(n),
      n == 0 and K.red or K.lightBlue)
  elseif cmd == "edit" or cmd == "delete" or cmd == "remove" or cmd == "del" then
    local idx = findPreset(arg)
    if not idx then say(arg == "" and ("/" .. cmd .. " <preset name>") or ("No preset called " .. arg), K.red); return end
    openEditor(idx)
    if cmd ~= "edit" then ui.edit.confirmDel = true; say("Tap Sure? (or Enter) to delete " .. cfg.presets[idx].name, K.orange) end
  elseif remoteCommand and remoteCommand(cmd, arg) then
    return
  else
    say("Unknown command. " .. HELP, K.red)
  end
end

-- Bottom row of the computer's own screen
function drawCmdBar(w, h)
  local y = h - 1
  if ui.page == "presets" or ui.page == "edit" then y = h end
  if ui.page == "miner" and not ui.cmd then return end
  if ui.page == "presets" and not ui.cmd then return end
  if ui.page == "rules" and not ui.cmd then return end
  if ui.cmd then
    at(1, y, pad("> " .. ui.cmd .. "_", w), K.white, K.grey)
  elseif ui.page == "overview" then
    at(1, y, pad(P.barrels and " /rules /assign /presets  /help for the rest" or " /presets  /help for the rest", w), K.grey)
  elseif ui.page == "edit" then
    at(1, y, pad(ui.edit and ui.edit.focus and " Enter/Tab: next field" or " Enter: save   /home   /presets", w), K.grey)
  end
end


uiBusy = false   -- /assign has the computer's screen
function draw()
  for _, v in ipairs(views) do
    d = v.dev()
    if d and not (uiBusy and v.kind == "term") then
      hits = {}
      ui = v.ui
      local ok = pcall(function()
        if v.kind == "monitor" then d.setTextScale(TEXT_SCALE) end
        local w, h = d.getSize()
        if not w then return end
        d.setBackgroundColour(K.black); d.clear()
        if ui.page == "miner" then drawMiner(w, h)
        elseif ui.page == "presets" then drawPresets(w, h)
        elseif ui.page == "edit" then drawEdit(w, h, v.kind)
        elseif ui.page == "rules" then drawRules(w, h, v.kind)
        else drawOverview(w, h) end
        if v.kind == "term" then drawCmdBar(w, h) end
      end)
      v.hits = hits
      if not ok and v.kind == "monitor" then mon, monSide = findMonitor() end
    end
  end
end

-- /assign: the same screen as storage's (assignui.lua). It takes over the computer's own screen.
AUI = dofile("assignui.lua")
assignRunning = false
openAssign = function()
  if ui ~= termUi or assignRunning then
    say(("Barrels: type /assign on %s computer"):format(P.name), K.yellow)
    return
  end
  assignRunning, uiBusy = true, true
  local ok, err = pcall(AUI.run, {
    title = P.short .. " BARRELS",
    hint = "Click one to change it.",
    emptyText = "Nothing assigned yet. + Add: a Dock, an Output, a Stock" .. (LISTS.factory_in and ", the factory's two." or "."),
    types = TYPES, names = cfg.names, call = call,
    typeOf = typeOf, assign = assignJob, unassign = unassign,
    inventories = inventories,
    assignedNames = function()
      local out = {}
      for _, field in pairs(LISTS) do for _, n in ipairs(cfg[field]) do out[#out + 1] = n end end
      return out
    end,
    candidate = function(n) return true end,
    single = function() return nil end,
    defaultKey = function()
      if #cfg.docks == 0 then return "dock" end
      if #cfg.outputs == 0 then return "output" end
      if #cfg.stocks == 0 then return "stock" end
      if LISTS.factory_in and #cfg.factoryIns == 0 then return "factory_in" end
      if LISTS.factory_out and #cfg.factoryOuts == 0 then return "factory_out" end
      if LISTS.overflow and #cfg.overflows == 0 then return "overflow" end
      return "input"
    end,
    problem = function()
      if #cfg.docks == 0 then return ("No DOCK yet: %s's barrel."):format(P.bird) end
      if #cfg.outputs == 0 then return "No OUTPUT yet: nothing can go home." end
      if #cfg.stocks == 0 then return "No STOCK yet: spare buckets and fuel go home too." end
      if LISTS.factory_in and #cfg.factoryIns == 0 then return "No FACTORY IN yet: empty buckets stay in Stock." end
      if LISTS.factory_out and #cfg.factoryOuts == 0 then return "No FACTORY OUT yet: no lava for the docks." end
      if LISTS.overflow and #cfg.overflows == 0 then return "No OVERFLOW yet: a full Output stops the docks." end
    end,
    warn = function(e, d)
      if e.key ~= e.orig and (d.count or 0) > 0 and (e.key == "dock" or e.key == "input") then
        return ("Its %d items get kept or sent home."):format(d.count)
      end
    end,
    extra = {
      key = "dock", plain = false,
      init = function(n) return { id = cfg.dockFor[n] } end,
      show = function(st)
        local dd = st.id and reg[st.id]
        return "For", dd and (dd.label or nameOf(dd.num)) or ("any %s (tap to pick one)"):format(P.bird)
      end,
      click = function(n, st)   -- cycle: any -> each miner -> any
        local ids = {}
        for id, dd in pairs(reg) do if not dd.retired then ids[#ids + 1] = id end end
        table.sort(ids, function(a, b) return reg[a].num < reg[b].num end)
        local nextId = ids[1]
        for i, id in ipairs(ids) do if id == st.id then nextId = ids[i + 1] end end
        st.id = nextId
      end,
      save = function(n, st) cfg.dockFor[n] = st.id end,
    },
    hold = function() paused = true; while workerBusy do os.sleep(0.2) end end,
    release = function() paused = false end,
    beforeSave = function() while workerBusy do os.sleep(0.1) end end,
    afterSave = function() saveCfg(); if remoteChanged then remoteChanged() end end,
    itemTotals = itemTotals,
  })
  assignRunning, uiBusy = false, false
  paused = false
  termUi.page = "overview"
  if not ok then say("Assign screen error: " .. tostring(err), K.red) end
  draw()
end
