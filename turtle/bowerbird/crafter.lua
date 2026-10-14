-- crafter.lua  --  Bowerbird, the prediction-matrix crafter (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- Keeps storage stocked with Hostile Neural Networks prediction matrices for the neural lab.
-- Recipe (HNN, unchanged by ATM10): iron ingot + gold ingot + 4 glass panes + clay ball -> 16.
-- He also turns glass into panes (6 glass -> 16) when he's out of panes.
--
-- Needs: a CRAFTY turtle (crafting table on one side) with a wireless or ender modem on the other.
--        He never moves, so no fuel and no pickaxe.
-- Dock:  a barrel in FRONT of him (or above/below), on the storage cable. On the storage computer:
--        /assign, pick the barrel, make it a Dock, and give it Keeps:
--            iron_ingot 16, gold_ingot 16, clay_ball 16, glass_pane 64   (or glass 24 for panes)
--        Storage tops those up; the matrices he drops in the dock get sorted into storage.
--
-- How it works: every few seconds he asks storage how many matrices it has. Under KEEP, he takes
-- everything out of the dock, crafts up to BATCH x 16, and puts everything back (the matrices and
-- whatever he didn't use). The neural lab gets them from storage as usual.
-- Screen: what he's doing. Keys: P = pause / run.  Settings: bowerbird.env (edit live).

local BASE     = "tanis-base"
local ENV_FILE = "bowerbird.env"
local CFG_FILE = "bowerbird.cfg"

local MATRIX = "hostilenetworks:prediction_matrix"
local IRON   = "minecraft:iron_ingot"
local GOLD   = "minecraft:gold_ingot"
local CLAY   = "minecraft:clay_ball"
local GLASS  = "minecraft:glass"
local PANE   = "minecraft:glass_pane"
local NICE   = { [IRON] = "iron ingot", [GOLD] = "gold ingot", [CLAY] = "clay ball", [PANE] = "glass panes", [GLASS] = "glass" }

-- Turtle slots: 1 2 3 4 / 5 6 7 8 / 9 10 11 12 / 13 14 15 16. Recipes sit in the top-left 3x3.
--   matrix:  I G .     panes:  g g g
--            G C G             g g g
--            . G N
local MATRIX_LAYOUT = { [1] = "I", [2] = "P", [5] = "P", [6] = "C", [7] = "P", [10] = "P", [11] = "N" }
local PANE_LAYOUT   = { [1] = "g", [2] = "g", [3] = "g", [5] = "g", [6] = "g", [7] = "g" }

local DEFAULTS = {
  { "KEEP", 256, "Keep this many prediction matrices in storage." },
  { "BATCH", 4, "Crafts per go (16 matrices each, at most 4 = one stack)." },
  { "TICK", 5, "Seconds between checks." },
  { "DOCK", "", "Where the dock barrel is: front, top or bottom. Blank = find it." },
}

---------------------------------------------------------------------------
-- Settings (bowerbird.env): same rules as the other .env files
---------------------------------------------------------------------------
local E, envStamp = {}, nil
local function stampOf(path)
  if not fs.exists(path) or not fs.attributes then return nil end
  local ok, a = pcall(fs.attributes, path)
  return ok and a and (tostring(a.modified) .. ":" .. tostring(a.size)) or nil
end
local function readEnv()
  local vals = {}
  if fs.exists(ENV_FILE) then
    local f = fs.open(ENV_FILE, "r")
    while true do
      local line = f.readLine()
      if not line then break end
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then vals[k:upper()] = v end
    end
    f.close()
  end
  local missing = {}
  for _, d in ipairs(DEFAULTS) do
    if vals[d[1]] == nil then missing[#missing + 1] = d; vals[d[1]] = tostring(d[2]) end
  end
  if #missing > 0 then
    local new = not fs.exists(ENV_FILE)
    local f = fs.open(ENV_FILE, new and "w" or "a")
    if new then f.writeLine("# Bowerbird settings. Edit and save: picked up within a few seconds.") end
    for _, d in ipairs(missing) do
      f.writeLine("")
      f.writeLine("# " .. d[3])
      f.writeLine(d[1] .. "=" .. tostring(d[2]))
    end
    f.close()
  end
  for _, d in ipairs(DEFAULTS) do
    local v = vals[d[1]]
    if type(d[2]) == "number" then E[d[1]] = tonumber(v) or d[2] else E[d[1]] = v end
  end
  envStamp = stampOf(ENV_FILE)
end
local function refreshEnv() if stampOf(ENV_FILE) ~= envStamp then readEnv() end end

local cfg = { paused = false, made = 0 }
local function loadCfg()
  if not fs.exists(CFG_FILE) then return end
  local f = fs.open(CFG_FILE, "r")
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
end
local function saveCfg()
  local f = fs.open(CFG_FILE, "w")
  f.write(textutils.serialize(cfg))
  f.close()
end

---------------------------------------------------------------------------
-- The dock
---------------------------------------------------------------------------
local SIDES = {
  front  = { drop = turtle.drop,     suck = turtle.suck },
  top    = { drop = turtle.dropUp,   suck = turtle.suckUp },
  bottom = { drop = turtle.dropDown, suck = turtle.suckDown },
}
local dockSide = nil
local function findDock()
  local want = tostring(E.DOCK or ""):lower()
  dockSide = nil
  if SIDES[want] then
    if peripheral.hasType(want, "inventory") then dockSide = want end
    return dockSide
  end
  for _, s in ipairs({ "front", "top", "bottom" }) do
    if peripheral.hasType(s, "inventory") then dockSide = s; return s end
  end
  return nil
end

local function dockList()
  if not dockSide then return nil end
  local ok, l = pcall(peripheral.call, dockSide, "list")
  return ok and l or nil
end

local function isPane(name) return name ~= nil and name:find("glass_pane$") ~= nil end

---------------------------------------------------------------------------
-- Storage's counts: asked for directly every 10 s (same counts-only ask the neural lab uses)
---------------------------------------------------------------------------
local WANT = { MATRIX, IRON, GOLD, CLAY, GLASS, PANE }
local counts, countsAt, storageId = {}, nil, nil
local lastAsk, askNow = -100, false
local function countsFresh() return countsAt and os.clock() - countsAt < 60 end

---------------------------------------------------------------------------
-- State for the screen and the network
---------------------------------------------------------------------------
local state, note, missing = "STARTING", "Starting", {}
local netOn = false          -- a wireless/ender modem is open
local stock = nil
local craftAt = nil       -- when he last crafted: wait for storage to count them before going again
local function say(s, n) state, note = s, n or s end

---------------------------------------------------------------------------
-- Inventory moves
---------------------------------------------------------------------------
local function item(s) return turtle.getItemDetail(s) end

-- Put everything back in the dock. Returns false if the dock wouldn't take something.
local function dropAll()
  local ok = true
  for s = 1, 16 do
    if turtle.getItemCount(s) > 0 then
      turtle.select(s)
      SIDES[dockSide].drop()
      if turtle.getItemCount(s) > 0 then ok = false end
    end
  end
  turtle.select(1)
  return ok
end

-- Take everything out of the dock (until it's empty or he's full)
local function suckAll()
  turtle.select(1)
  for _ = 1, 16 do
    if not SIDES[dockSide].suck() then break end
  end
end

local function totals()
  local t = {}
  for s = 1, 16 do
    local d = item(s)
    if d then t[d.name] = (t[d.name] or 0) + d.count end
  end
  return t
end

-- Lay out a recipe: `layout` maps slot -> key, `names` maps key -> item id, `per` items in each slot.
-- Everything else goes back to the dock first, so only the recipe is left (the turtle needs that).
local function arrange(layout, names, per)
  local need = {}
  for _, k in pairs(layout) do local n = names[k]; need[n] = (need[n] or 0) + per end
  -- 1. Back to the dock: anything not in the recipe, and anything over what's needed
  local have = {}
  for s = 1, 16 do
    local d = item(s)
    if d then
      local keep = math.max(0, math.min(d.count, (need[d.name] or 0) - (have[d.name] or 0)))
      have[d.name] = (have[d.name] or 0) + keep
      if d.count > keep then
        turtle.select(s)
        SIDES[dockSide].drop(d.count - keep)
        if turtle.getItemCount(s) > keep then return false, "the dock is full" end
      end
    end
  end
  for n, c in pairs(need) do if (have[n] or 0) < c then return false, "short of " .. (NICE[n] or n) end end
  -- 2. Merge each item into as few slots as possible
  for s = 16, 2, -1 do
    local d = item(s)
    if d then
      for t = 1, s - 1 do
        local e = item(t)
        if e and e.name == d.name and e.count < 64 then
          turtle.select(s); turtle.transferTo(t)
          if turtle.getItemCount(s) == 0 then break end
        end
      end
    end
  end
  -- 3. Fill each recipe slot with exactly `per` of its item
  local done = {}
  local slots = {}
  for s in pairs(layout) do slots[#slots + 1] = s end
  table.sort(slots)
  local function freeSlot()
    for s = 16, 1, -1 do
      if not layout[s] and turtle.getItemCount(s) == 0 then return s end
    end
  end
  for _, t in ipairs(slots) do
    local name = names[layout[t]]
    local d = item(t)
    if d and (d.name ~= name or d.count > per) then
      local f = freeSlot()
      if not f then return false, "no room to sort" end
      turtle.select(t)
      turtle.transferTo(f, d.name ~= name and d.count or d.count - per)
    end
    local guard = 0
    while turtle.getItemCount(t) < per and guard < 32 do
      guard = guard + 1
      local short = per - turtle.getItemCount(t)
      local from
      for s = 1, 16 do   -- loose stock first, then recipe slots not filled yet
        if s ~= t and not layout[s] then local e = item(s); if e and e.name == name then from = s; break end end
      end
      if not from then
        for s = 1, 16 do
          if s ~= t and layout[s] and not done[s] then local e = item(s); if e and e.name == name then from = s; break end end
        end
      end
      if not from then return false, "lost track of " .. (NICE[name] or name) end
      turtle.select(from); turtle.transferTo(t, short)
    end
    done[t] = true
  end
  for s = 1, 16 do
    if not layout[s] and turtle.getItemCount(s) > 0 then return false, "leftovers in slot " .. s end
  end
  return true
end

local function craft(n)
  turtle.select(16)   -- results land here first (empty: everything else is in the 3x3)
  local ok, err
  if turtle.craft then ok, err = turtle.craft(n)
  else
    local wb = peripheral.find("workbench")
    if not wb then return false, "no crafting table" end
    ok, err = wb.craft(n)
  end
  turtle.select(1)
  return ok, err
end

-- The panes he'll use: the plain kind if he has 4+, else whichever stained kind he has most of
local function pickPane(t)
  if (t[PANE] or 0) >= 4 then return PANE end
  local best, bestN = PANE, t[PANE] or 0
  for n, c in pairs(t) do if isPane(n) and c > bestN then best, bestN = n, c end end
  return best
end

-- One go: returns how many matrices he made (0 = couldn't), and a reason when 0
local function craftRound(want)
  suckAll()
  local t = totals()
  local pane = pickPane(t)
  -- Out of panes but has glass: make panes first (only when the rest of the recipe is here, or
  -- he'd turn all the glass into panes while waiting for clay)
  local rest = math.min(t[IRON] or 0, t[GOLD] or 0, t[CLAY] or 0)
  if (t[pane] or 0) < 4 * math.min(want, rest) and (t[GLASS] or 0) >= 6 then
    want = math.min(want, rest)
    local k = math.min(4, math.floor(t[GLASS] / 6), math.ceil((4 * want - (t[pane] or 0)) / 16))
    local ok, why = arrange(PANE_LAYOUT, { g = GLASS }, k)
    if ok then ok, why = craft(k) end
    if not ok then dropAll(); return 0, "panes: " .. tostring(why) end
    suckAll()   -- arranging put the iron, gold and clay back in the dock
    t = totals()
    pane = PANE
  end
  local n = math.min(want, t[IRON] or 0, t[GOLD] or 0, t[CLAY] or 0, math.floor((t[pane] or 0) / 4))
  missing = {}
  if n <= 0 then
    for _, id in ipairs({ IRON, GOLD, CLAY }) do
      if (t[id] or 0) == 0 then missing[#missing + 1] = NICE[id] end
    end
    if (t[pane] or 0) < 4 and (t[GLASS] or 0) < 6 then missing[#missing + 1] = "glass panes" end
    dropAll()
    return 0, "short"
  end
  local ok, why = arrange(MATRIX_LAYOUT, { I = IRON, N = GOLD, C = CLAY, P = pane }, n)
  if ok then ok, why = craft(n) end
  local made = totals()[MATRIX] or 0
  if not dropAll() then return made, "dock full" end
  if not ok then return 0, tostring(why) end
  return made
end

---------------------------------------------------------------------------
-- Work
---------------------------------------------------------------------------
local function storageHas(id) return countsFresh() and (counts[id] or 0) > 0 end

local function workPass()
  refreshEnv()
  if not findDock() then
    return say("NO DOCK", "No barrel in front, above or below me")
  end
  if not turtle.craft and not peripheral.find("workbench") then
    return say("NO TABLE", "I need a crafting table upgrade")
  end
  if not netOn then return say("NO MODEM", "I need a wireless or ender modem to hear storage") end
  if cfg.paused then return say("PAUSED", "Paused (P to run)") end
  local dl = dockList() or {}
  local inDock = 0
  for _, it in pairs(dl) do if it.name == MATRIX then inDock = inDock + it.count end end
  if not countsFresh() then
    stock = nil
    return say("NO COUNTS", "Waiting to hear from storage")
  end
  stock = (counts[MATRIX] or 0) + inDock
  local keep = math.max(0, math.floor(E.KEEP or 256))
  if stock >= keep then missing = {}; return say("STOCKED", ("Stocked: %d/%d"):format(stock, keep)) end
  -- Just crafted: wait until storage has counted them (they sit in the dock until it sorts them)
  if craftAt and (countsAt or 0) < craftAt + 3 then return say("COUNTING", "Waiting for storage to count") end
  local want = math.max(1, math.min(4, math.floor(E.BATCH or 4), math.ceil((keep - stock) / 16)))
  local made, why = craftRound(want)
  if made > 0 then
    cfg.made = (cfg.made or 0) + made
    saveCfg()
    craftAt, askNow = os.clock(), true
    missing = {}
    if why == "dock full" then return say("DOCK FULL", "Made " .. made .. ", but the dock is full") end
    return say("CRAFTING", ("Made %d (%d/%d)"):format(made, stock + made, keep))
  end
  if why == "short" then
    local hint = {}
    for _, m in ipairs(missing) do hint[#hint + 1] = m end
    -- Storage has it but the dock doesn't: the keep list is missing a line
    local inStorage = false
    for _, id in ipairs({ IRON, GOLD, CLAY, PANE, GLASS }) do
      for _, m in ipairs(missing) do if NICE[id] == m and storageHas(id) then inStorage = true end end
    end
    return say("NEED", "Need " .. table.concat(hint, ", ")
      .. (inStorage and " (in storage: add it to my dock's Keeps)" or ""))
  end
  return say("STUCK", "Couldn't craft: " .. tostring(why))
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------
local function wrap(text, w)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if #line + #word + 1 > w and #line > 0 then out[#out + 1] = line; line = word
    else line = #line > 0 and (line .. " " .. word) or word end
  end
  if #line > 0 then out[#out + 1] = line end
  return out
end

local COL = { CRAFTING = colours.lime, STOCKED = colours.lightBlue, COUNTING = colours.cyan, PAUSED = colours.orange }
local function draw()
  local w, h = term.getSize()
  local colour = term.isColour()
  term.setBackgroundColour(colours.black); term.clear()
  term.setCursorPos(1, 1)
  if colour then term.setBackgroundColour(colours.grey); term.clearLine() end
  term.setTextColour(colours.white)
  term.write((" BOWERBIRD  matrix crafter"):sub(1, w))
  term.setBackgroundColour(colours.black)
  term.setCursorPos(2, 3)
  if colour then term.setTextColour(COL[state] or colours.red) end
  term.write(state)
  local y = 4
  for _, l in ipairs(wrap(note, w - 2)) do
    if y > h - 4 then break end
    term.setCursorPos(2, y); term.setTextColour(colours.white); term.write(l); y = y + 1
  end
  y = y + 1
  term.setTextColour(colours.lightGrey)
  term.setCursorPos(2, y); term.write(("Matrices: %s / %d"):format(stock and tostring(stock) or "?", math.floor(E.KEEP or 256))); y = y + 1
  term.setCursorPos(2, y); term.write(("Made so far: %d"):format(cfg.made or 0)); y = y + 1
  term.setCursorPos(2, y); term.write(("Dock: %s"):format(dockSide or "none")); y = y + 1
  term.setCursorPos(2, h); term.setTextColour(colours.grey)
  term.write(("P = %s"):format(cfg.paused and "run" or "pause"))
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function workLoop()
  while true do
    local ok, err = pcall(workPass)
    if not ok then say("ERROR", tostring(err)) end
    pcall(draw)
    local t = os.startTimer(math.max(1, E.TICK or 5))
    while true do
      local ev, a = os.pullEvent()
      if (ev == "timer" and a == t) or ev == "bowerbird_work" then break end
    end
  end
end

local function netLoop()
  if not netOn then return os.pullEvent("never") end
  local lastSend = -100
  while true do
    if askNow or os.clock() - lastAsk >= 10 then
      local req = { type = "neural_ops", id = os.epoch("utc"), ops = {}, want = WANT }
      if storageId then rednet.send(storageId, req, BASE) else rednet.broadcast(req, BASE) end
      lastAsk, askNow = os.clock(), false
    end
    if os.clock() - lastSend >= 3 then
      rednet.broadcast({ type = "bowerbird", id = os.getComputerID(), label = os.getComputerLabel() or "Bowerbird",
        state = state, note = note, missing = missing, made = cfg.made, stock = stock, keep = E.KEEP,
        paused = cfg.paused }, BASE)
      lastSend = os.clock()
    end
    local from, msg = rednet.receive(BASE, 1)
    if type(msg) == "table" then
      if msg.type == "neural_done" and type(msg.counts) == "table" and msg.counts[MATRIX] ~= nil then
        for id, n in pairs(msg.counts) do counts[id] = tonumber(n) or 0 end
        countsAt, storageId = os.clock(), from
        if state == "COUNTING" or state == "NO COUNTS" then os.queueEvent("bowerbird_work") end
      elseif msg.type == "storage" and type(msg.items) == "table" then
        for _, id in ipairs(WANT) do counts[id] = tonumber(msg.items[id]) or 0 end
        countsAt, storageId = os.clock(), from
      end
    end
  end
end

local function keyLoop()
  while true do
    local _, k = os.pullEvent("key")
    if k == keys.p then
      cfg.paused = not cfg.paused
      saveCfg()
      os.queueEvent("bowerbird_work")
    end
  end
end

peripheral.find("modem", function(name, m)
  if m.isWireless and m.isWireless() then rednet.open(name); netOn = true end
  return false
end)
if not os.getComputerLabel() then os.setComputerLabel("Bowerbird") end
readEnv()
loadCfg()
parallel.waitForAny(workLoop, netLoop, keyLoop)
