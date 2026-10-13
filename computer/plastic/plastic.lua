-- plastic.lua  --  plastic factory controller (CC:Tweaked, ATM10 / MC 1.21.1, Industrial Foregoing)
--
-- One building, its OWN wired cable (keep it apart from the storage cable: storage treats every
-- inventory it can see as a storage barrel, and the smelter grabs every furnace it can see).
-- On the factory cable, each with a wired modem:
--   * Tree Fluid Extractors ("taps"), each with a log behind it        -> latex
--   * one or more Latex Processing Units (need power)                    latex + water -> dry rubber
--   * a water supply: any tank or block holding water                   (optional: you can also
--                                                                         fill the unit's tank by hand)
--   * optional buffer tanks: any other tank soaks up latex while the units are full
--   * furnaces (vanilla or Iron Furnaces)                                 dry rubber -> plastic
--   * the DOCK barrel: plastic goes out here, furnace fuel comes from here. Give it a second wired
--     modem on the STORAGE cable and add it on storage with /dock: storage then takes the plastic
--     away and keeps ~32 coal in it, so the factory runs itself.
-- No furnace on the cable (or FURNACE=no)? Dry rubber goes to the dock instead and the smelter turns
-- it into plastic with a "plastic all" line in smelt.txt.
--
-- Optional: a monitor touching the computer (tap PAUSE/RUN on it), a wireless/ender modem so the
-- mainframe shows it on the board, raises alerts and answers "island plastic".
-- Terminal: status | list | pause | resume | help.   Settings: plastic.env (live, like butler.env).
--
-- How a tap works (IF source, 1.21): it fills its 1,000 mB tank from the log behind it, 3x faster
-- with power. Every pull has a 1% chance to wear the log; after ~8 wears it turns into a stripped
-- log (which still gives 1 mB a pull) and then into air. A tap that stops giving latex gets flagged.
-- One dry rubber = 750 mB latex + 500 mB water.

local ENV_FILE = "plastic.env"
local CFG_FILE = "plastic.cfg"
local BASE     = "tanis-base"

local LATEX     = "industrialforegoing:latex"
local WATER     = "minecraft:water"
local RUBBER    = "industrialforegoing:dryrubber"
local PLASTIC   = "industrialforegoing:plastic"
local TAP_CAP   = 1000     -- tap tank (IF default config)
local UNIT_CAP  = 16000    -- each Latex Processing Unit tank (IF default config)
local PER_RUBBER_LATEX, PER_RUBBER_WATER = 750, 500

-- Furnace fuels the dock can hold: item -> how many items one of it smelts
local FUELS = {
  { "minecraft:charcoal", 8 }, { "minecraft:coal", 8 }, { "minecraft:coal_block", 80 },
  { "minecraft:blaze_rod", 12 },
}
local FUEL_PER = {}
for _, f in ipairs(FUELS) do FUEL_PER[f[1]] = f[2] end

local DEFAULTS = {
  { "TICK", 2, "Seconds between passes." },
  { "DOCK", "", "The dock barrel's name on this cable (plastic out, fuel in). Blank = find it: the one chest/barrel on the cable." },
  { "FURNACE", "yes", "yes = smelt the dry rubber here. no = send dry rubber to the dock for the smelter (smelt.txt: plastic all)." },
  { "STALL_AFTER", 300, "Flag a tap that has given no latex for this many seconds (log used up, or nothing behind it)." },
  { "WATER_LOW", 2000, "Warn when a unit's water drops under this many mB and there's no water supply." },
}

---------------------------------------------------------------------------
-- Settings (plastic.env): same rules as butler.env
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
    if new then f.writeLine("# Plastic factory settings. Edit and save: picked up within a few seconds.") end
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

local function refreshEnv()
  if stampOf(ENV_FILE) ~= envStamp then readEnv() end
end

local function yes(key)
  local v = tostring(E[key]):lower()
  return v == "yes" or v == "true" or v == "on" or v == "1"
end

---------------------------------------------------------------------------
-- Saved totals (plastic.cfg)
---------------------------------------------------------------------------
local cfg = { paused = false, plastic = 0, rubber = 0, latex = 0, waterTanks = {} }
local function loadCfg()
  if not fs.exists(CFG_FILE) then return end
  local f = fs.open(CFG_FILE, "r")
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
end
local lastSave = -100
local function saveCfg(now)
  if not now and os.clock() - lastSave < 60 then return end
  local f = fs.open(CFG_FILE, "w")
  f.write(textutils.serialize(cfg))
  f.close()
  lastSave = os.clock()
end

---------------------------------------------------------------------------
-- Peripherals
---------------------------------------------------------------------------
local function call(name, method, ...)
  local ok, a, b = pcall(peripheral.call, name, method, ...)
  if ok then return a, b end
  return nil, a
end

local function isTap(n)  return n:find("fluid_extractor") ~= nil end
local function isUnit(n) return n:find("latex_processing") ~= nil end
-- Same rule as storage and the smelter: furnaces and Iron Furnaces; blast furnaces/smokers left alone
local function isFurnace(n)
  return n:find("furnace") ~= nil and not n:find("blast") and not n:find("smoker")
end
local function isMachine(n)
  return isTap(n) or isUnit(n) or n:find("furnace") ~= nil or n:find("smoker") ~= nil
end

local function shortNum(n) return n:match("_(%d+)$") or n end

-- The factory: what's on the cable, sorted into jobs
local F = { taps = {}, units = {}, furnaces = {}, water = {}, buffers = {}, dock = nil, dockNote = nil }

local function fluids(n)
  local t = {}
  for _, tk in pairs(call(n, "tanks") or {}) do
    if type(tk) == "table" and tk.name then t[tk.name] = (t[tk.name] or 0) + (tk.amount or 0) end
  end
  return t
end

local function scan()
  local f = { taps = {}, units = {}, furnaces = {}, water = {}, buffers = {}, dock = nil, dockNote = nil }
  local chests = {}
  local sides = {}
  for _, s in ipairs(rs.getSides()) do sides[s] = true end
  for _, n in ipairs(peripheral.getNames()) do
    -- Only things on the cable: a block touching the computer has no name to tell what it is
    if not sides[n] then
      local other = isMachine(n) or n:find("industrialforegoing") ~= nil   -- other IF machines: hands off
      if isTap(n) then f.taps[#f.taps + 1] = n
      elseif isUnit(n) then f.units[#f.units + 1] = n
      elseif isFurnace(n) and peripheral.hasType(n, "inventory") then f.furnaces[#f.furnaces + 1] = n
      elseif not other and peripheral.hasType(n, "fluid_storage") then
        -- A tank that has ever held water stays a water tank (so it never gets latex once it runs dry)
        local fl = fluids(n)
        if (fl[WATER] or 0) > 0 then cfg.waterTanks[n] = true end
        if (fl[LATEX] or 0) > 0 then cfg.waterTanks[n] = nil end
        if cfg.waterTanks[n] or n:find("water") then f.water[#f.water + 1] = n
        else f.buffers[#f.buffers + 1] = n end
      elseif not other and peripheral.hasType(n, "inventory") then
        chests[#chests + 1] = n
      end
    end
  end
  for _, k in ipairs({ "taps", "units", "furnaces", "water", "buffers" }) do table.sort(f[k]) end
  table.sort(chests)
  local want = tostring(E.DOCK or "")
  if want ~= "" then
    if peripheral.isPresent(want) then f.dock = want
    else f.dockNote = "DOCK=" .. want .. " isn't on the cable" end
  elseif #chests == 1 then
    f.dock = chests[1]
  elseif #chests > 1 then
    f.dock = chests[1]
    f.dockNote = ("%d chests on the cable: using %s (set DOCK= in plastic.env)"):format(#chests, chests[1])
  end
  F = f
end

-- Only a monitor touching the computer (screens on a cable belong to other computers)
local mon
local function findMonitor()
  mon = nil
  for _, side in ipairs(rs.getSides()) do
    if not mon and peripheral.hasType(side, "monitor") then mon = peripheral.wrap(side); mon.setTextScale(0.5) end
  end
end

---------------------------------------------------------------------------
-- State for the screen and the network
---------------------------------------------------------------------------
local tapState = {}        -- name -> { after = mB left after last pass, lastGain = clock, amount, stuck }
local unitState = {}       -- name -> { latex, water, energy, cap, full }
local furnState = {}       -- name -> { cooking, fuel, fuelName, out }
local problems = {}        -- key -> message (for alerts)
local note = "Starting"
local samples = {}         -- { clock, latex total } for the latex rate
local dockFuel, dockPlastic = 0, 0
local rubberWaiting = 0

local function problem(key, on, msg)
  if on then problems[key] = msg else problems[key] = nil end
end

local function latexRate()  -- mB per minute over the last ~10 minutes
  local now = os.clock()
  while #samples > 1 and now - samples[1][1] > 600 do table.remove(samples, 1) end
  local first = samples[1]
  if not first or now - first[1] < 20 then return nil end
  return (cfg.latex - first[2]) / ((now - first[1]) / 60)
end

---------------------------------------------------------------------------
-- One pass
---------------------------------------------------------------------------
-- Fill the units: latex from taps (then buffers), water from the water supply.
local function moveLatex(from)
  local moved = 0
  for _, u in ipairs(F.units) do
    local m = call(from, "pushFluid", u, nil, LATEX) or 0
    moved = moved + m
  end
  return moved
end

local function passFluids()
  local now = os.clock()
  local seen = {}
  for _, t in ipairs(F.taps) do
    seen[t] = true
    local st = tapState[t]
    if not st then st = { after = nil, lastGain = now }; tapState[t] = st end
    local have = fluids(t)[LATEX] or 0
    if st.after and have > st.after then
      cfg.latex = cfg.latex + (have - st.after)
      st.lastGain = now
    elseif not st.after then
      st.lastGain = st.lastGain or now
    end
    local moved = 0
    if not cfg.paused and have > 0 then
      moved = moveLatex(t)
      if moved < have then           -- units full: park it in the buffer tanks
        for _, b in ipairs(F.buffers) do
          if moved >= have then break end
          moved = moved + (call(t, "pushFluid", b, have - moved, LATEX) or 0)
        end
      end
    end
    st.amount = have - moved
    st.after = st.amount
    st.full = st.amount >= TAP_CAP and moved == 0
    st.stalled = not st.full and now - st.lastGain > E.STALL_AFTER
    problem("tap:" .. t, st.stalled,
      ("Plastic factory: tap %s has given no latex for %d min. Log used up?"):format(shortNum(t), math.floor((now - st.lastGain) / 60)))
  end
  for t in pairs(tapState) do if not seen[t] then tapState[t] = nil; problem("tap:" .. t, false) end end

  if not cfg.paused then
    for _, b in ipairs(F.buffers) do
      if (fluids(b)[LATEX] or 0) > 0 then moveLatex(b) end
    end
  end

  local anyWater = #F.water > 0
  for _, u in ipairs(F.units) do
    local fl = fluids(u)
    local water = fl[WATER] or 0
    if not cfg.paused and anyWater and water < UNIT_CAP then
      for _, w in ipairs(F.water) do
        if water >= UNIT_CAP then break end
        water = water + (call(w, "pushFluid", u, UNIT_CAP - water, WATER) or 0)
      end
    end
    local us = { latex = fl[LATEX] or 0, water = water }
    if peripheral.hasType(u, "energy_storage") then
      us.energy, us.cap = call(u, "getEnergy"), call(u, "getEnergyCapacity")
    end
    unitState[u] = us
    problem("water:" .. u, not anyWater and us.water < E.WATER_LOW,
      ("Plastic factory: latex unit %s is low on water (%d mB) and there's no water supply on the cable."):format(shortNum(u), us.water))
    problem("power:" .. u, us.cap and us.cap > 0 and (us.energy or 0) == 0,
      ("Plastic factory: latex unit %s has no power."):format(shortNum(u)))
  end
  for u in pairs(problems) do
    local name = u:match("^water:(.*)") or u:match("^power:(.*)")
    if name and not unitState[name] then problems[u] = nil end
  end
  for u in pairs(unitState) do
    local here = false
    for _, x in ipairs(F.units) do if x == u then here = true end end
    if not here then unitState[u] = nil end
  end
end

-- Count what's in the dock: fuel (in items it can smelt) and plastic waiting for storage
local function readDock()
  dockFuel, dockPlastic = 0, 0
  if not F.dock then return {} end
  local list = call(F.dock, "list") or {}
  for _, it in pairs(list) do
    if FUEL_PER[it.name] then dockFuel = dockFuel + FUEL_PER[it.name] * it.count end
    if it.name == PLASTIC then dockPlastic = dockPlastic + it.count end
  end
  return list
end

-- Feed a furnace from the dock so it can smelt `need` more items
local function fuelFurnace(fz, need, dockList)
  local fd = call(fz, "getItemDetail", 2)
  local have = fd and (FUEL_PER[fd.name] or 8) * fd.count or 0
  if have >= need or not F.dock then return end
  for slot, it in pairs(dockList) do
    local per = FUEL_PER[it.name]
    if per and (not fd or fd.name == it.name) then
      local n = math.min(it.count, math.max(1, math.ceil((need - have) / per)))
      local moved = call(F.dock, "pushItems", fz, slot, n, 2) or 0
      it.count = it.count - moved
      if moved > 0 then return end
    end
  end
end

local function passItems()
  local dockList = readDock()
  local smeltHere = yes("FURNACE") and #F.furnaces > 0
  rubberWaiting = 0

  -- 1. Finished plastic (and anything else cooked) out of the furnaces into the dock
  for _, fz in ipairs(F.furnaces) do
    local out = call(fz, "getItemDetail", 3)
    if out and F.dock and not cfg.paused then
      local moved = call(fz, "pushItems", F.dock, 3) or 0
      if out.name == PLASTIC then cfg.plastic = cfg.plastic + moved end
    end
  end

  -- 2. Dry rubber out of the units: into the furnaces, or straight to the dock
  for _, u in ipairs(F.units) do
    for slot, it in pairs(call(u, "list") or {}) do
      rubberWaiting = rubberWaiting + it.count
      if not cfg.paused then
        local left = it.count
        if smeltHere then
          for _, fz in ipairs(F.furnaces) do
            if left <= 0 then break end
            local cur = call(fz, "getItemDetail", 1)
            if not cur or (cur.name == it.name and cur.count < 64) then
              local m = call(u, "pushItems", fz, slot, left, 1) or 0
              left = left - m
              if it.name == RUBBER then cfg.rubber = cfg.rubber + m end
            end
          end
        elseif F.dock then
          local m = call(u, "pushItems", F.dock, slot, left) or 0
          left = left - m
          if it.name == RUBBER then cfg.rubber = cfg.rubber + m; cfg.plastic = cfg.plastic + m end
        end
        rubberWaiting = rubberWaiting - (it.count - left)
      end
    end
  end

  -- 3. Fuel every furnace that has something to cook
  local needFuel = false
  for _, fz in ipairs(F.furnaces) do
    local cur = call(fz, "getItemDetail", 1)
    local fd = call(fz, "getItemDetail", 2)
    local fs_ = { cooking = cur and cur.count or 0, fuel = fd and fd.count or 0, fuelName = fd and fd.name,
                  out = 0 }
    local o = call(fz, "getItemDetail", 3)
    fs_.out = o and o.count or 0
    if cur and not cfg.paused then
      fuelFurnace(fz, cur.count, dockList)
      local fd2 = call(fz, "getItemDetail", 2)
      fs_.fuel, fs_.fuelName = fd2 and fd2.count or 0, fd2 and fd2.name
      if not fd2 then needFuel = true end
    end
    furnState[fz] = fs_
  end
  for fz in pairs(furnState) do
    local here = false
    for _, x in ipairs(F.furnaces) do if x == fz then here = true end end
    if not here then furnState[fz] = nil end
  end
  readDock()
  problem("fuel", needFuel and dockFuel == 0,
    "Plastic factory: the furnace is out of fuel and the dock has none. Is the dock on storage (/dock)?")
  problem("dock", not F.dock and (#F.furnaces > 0 or #F.units > 0),
    "Plastic factory: no dock barrel on the factory cable, so plastic has nowhere to go.")
end

local function pass()
  refreshEnv()
  scan()
  passFluids()
  passItems()
  samples[#samples + 1] = { os.clock(), cfg.latex }
  saveCfg()

  if #F.taps == 0 and #F.units == 0 then
    note = "Nothing on my cable yet: taps, latex unit, furnace, dock"
  elseif cfg.paused then
    note = "Paused"
  elseif #F.units == 0 then
    note = "No Latex Processing Unit on the cable"
  elseif #F.taps == 0 then
    note = "No taps (Tree Fluid Extractors) on the cable"
  else
    local stalled, full = 0, 0
    for _, st in pairs(tapState) do
      if st.stalled then stalled = stalled + 1 end
      if st.full then full = full + 1 end
    end
    local r = latexRate()
    note = ("%d tap%s%s, %s"):format(#F.taps, #F.taps == 1 and "" or "s",
      stalled > 0 and (" (" .. stalled .. " dry)") or "",
      r and ("%d mB/min"):format(math.floor(r + 0.5)) or "measuring")
    if full == #F.taps and #F.taps > 0 then note = note .. ", units full" end
  end
end

---------------------------------------------------------------------------
-- Status lines (screen, terminal, mainframe)
---------------------------------------------------------------------------
local function pct(a, b) if not b or b <= 0 then return 0 end return math.floor(a / b * 100 + 0.5) end

local function stateWord()
  if cfg.paused then return "paused" end
  if next(problems) then return "waiting" end
  if #F.units == 0 or #F.taps == 0 then return "waiting" end
  return "running"
end

local function statusLines()
  local L = {}
  local r = latexRate()
  L[#L + 1] = note
  L[#L + 1] = ("Made: %d plastic (%d dry rubber). Latex %s"):format(cfg.plastic, cfg.rubber,
    r and ("%d mB/min, ~%.1f plastic/h"):format(math.floor(r + 0.5), r * 60 / PER_RUBBER_LATEX) or "rate: measuring")
  for _, u in ipairs(F.units) do
    local s = unitState[u] or {}
    L[#L + 1] = ("Unit %s: latex %d%%, water %d%%%s"):format(shortNum(u), pct(s.latex or 0, UNIT_CAP),
      pct(s.water or 0, UNIT_CAP), s.cap and (", power " .. pct(s.energy or 0, s.cap) .. "%") or "")
  end
  for _, t in ipairs(F.taps) do
    local s = tapState[t] or {}
    local word = s.stalled and "NO LATEX - log used up?" or s.full and "full (units full)" or "ok"
    L[#L + 1] = ("Tap %s: %s, %d mB"):format(shortNum(t), word, s.amount or 0)
  end
  if #F.furnaces > 0 then
    for _, fz in ipairs(F.furnaces) do
      local s = furnState[fz] or {}
      L[#L + 1] = ("Furnace %s: %d cooking, fuel %d%s"):format(shortNum(fz), s.cooking or 0, s.fuel or 0,
        yes("FURNACE") and "" or " (FURNACE=no)")
    end
  else
    L[#L + 1] = "No furnace: dry rubber goes to the dock (smelter: plastic all)"
  end
  if F.dock then
    L[#L + 1] = ("Dock: fuel for %d items, %d plastic waiting"):format(dockFuel, dockPlastic)
  else
    L[#L + 1] = "Dock: none found"
  end
  if F.dockNote then L[#L + 1] = F.dockNote end
  if rubberWaiting > 0 then L[#L + 1] = ("%d dry rubber waiting in the units"):format(rubberWaiting) end
  if #F.water == 0 and #F.units > 0 then L[#L + 1] = "No water supply: fill the unit's water tank by hand" end
  return L
end

---------------------------------------------------------------------------
-- Monitor
---------------------------------------------------------------------------
local button = nil   -- { x1, x2, y }

local function bar(m, x, y, w, frac, col)
  local fill = math.max(0, math.min(w, math.floor(w * frac + 0.5)))
  m.setCursorPos(x, y)
  m.setBackgroundColour(col); m.write((" "):rep(fill))
  m.setBackgroundColour(colours.grey); m.write((" "):rep(w - fill))
  m.setBackgroundColour(colours.black)
end

local function draw()
  if not mon then return end
  local w, h = mon.getSize()
  if not w then findMonitor(); return end
  mon.setBackgroundColour(colours.black); mon.clear()
  mon.setCursorPos(1, 1); mon.setBackgroundColour(colours.grey); mon.clearLine()
  local st = stateWord()
  local label = cfg.paused and " RUN " or " PAUSE "
  local bx = w - #label + 1
  mon.setTextColour(colours.white); mon.write((w >= 24 and " PLASTIC FACTORY" or " PLASTIC"):sub(1, bx - 1))
  mon.setCursorPos(bx, 1)
  mon.setBackgroundColour(cfg.paused and colours.green or colours.orange); mon.setTextColour(colours.black)
  mon.write(label)
  button = { x1 = bx, x2 = w, y = 1 }
  mon.setBackgroundColour(colours.black)

  local y = 3
  local function line(text, col)
    if y > h then return end
    mon.setCursorPos(2, y); mon.setTextColour(col or colours.lightGrey)
    mon.write(tostring(text):sub(1, w - 2)); y = y + 1
  end
  local stCol = st == "running" and colours.lime or st == "paused" and colours.orange or colours.yellow
  line(st:upper() .. "  " .. note, stCol)
  local r = latexRate()
  line(("Made %d plastic%s"):format(cfg.plastic,
    r and ("  ~%.1f/h"):format(r * 60 / PER_RUBBER_LATEX) or ""), colours.white)

  -- Small screen: one line per thing, problems first
  if h < 16 then
    for _, msg in pairs(problems) do line((msg:gsub("^Plastic factory: ", "")), colours.red) end
    for _, u in ipairs(F.units) do
      local s = unitState[u] or {}
      line(("Unit %s L%d W%d%s"):format(shortNum(u), pct(s.latex or 0, UNIT_CAP), pct(s.water or 0, UNIT_CAP),
        s.cap and (" P" .. pct(s.energy or 0, s.cap)) or ""), colours.white)
    end
    local dry = 0
    for _, t in ipairs(F.taps) do if (tapState[t] or {}).stalled then dry = dry + 1 end end
    line(("Taps %d ok%s"):format(#F.taps - dry, dry > 0 and (", " .. dry .. " DRY") or ""), dry > 0 and colours.red or colours.lime)
    local cooking = 0
    for _, fz in ipairs(F.furnaces) do cooking = cooking + ((furnState[fz] or {}).cooking or 0) end
    line(#F.furnaces > 0 and ("Furnace: %d cooking"):format(cooking) or "No furnace")
    line(F.dock and ("Dock fuel %d"):format(dockFuel) or "No dock", F.dock and colours.lightGrey or colours.yellow)
    return
  end
  y = y + 1

  local bw = math.max(4, w - 14)
  for _, u in ipairs(F.units) do
    local s = unitState[u] or {}
    line("Latex unit " .. shortNum(u), colours.white)
    if y <= h then mon.setCursorPos(2, y); mon.setTextColour(colours.lightGrey); mon.write("latex "); bar(mon, 9, y, bw, (s.latex or 0) / UNIT_CAP, colours.lightGrey); y = y + 1 end
    if y <= h then mon.setCursorPos(2, y); mon.setTextColour(colours.lightGrey); mon.write("water "); bar(mon, 9, y, bw, (s.water or 0) / UNIT_CAP, colours.blue); y = y + 1 end
    if s.cap and y <= h then
      mon.setCursorPos(2, y); mon.setTextColour(colours.lightGrey); mon.write("power ")
      bar(mon, 9, y, bw, (s.energy or 0) / s.cap, (s.energy or 0) > 0 and colours.red or colours.grey); y = y + 1
    end
  end
  if #F.units == 0 then line("No latex unit on the cable", colours.yellow) end
  y = y + 1

  -- Taps: one compact cell each, as many per row as fit
  if #F.taps > 0 and y <= h then
    mon.setCursorPos(2, y); mon.setTextColour(colours.white); mon.write("Taps"); y = y + 1
    local cellW = 10
    local per = math.max(1, math.floor((w - 1) / cellW))
    for i, t in ipairs(F.taps) do
      local s = tapState[t] or {}
      local cx = 2 + ((i - 1) % per) * cellW
      if (i - 1) % per == 0 and i > 1 then y = y + 1 end
      if y > h then break end
      mon.setCursorPos(cx, y)
      mon.setTextColour(s.stalled and colours.red or s.full and colours.orange or colours.lime)
      mon.write(("#%s %s"):format(shortNum(t), s.stalled and "DRY" or s.full and "full" or "ok"):sub(1, cellW - 1))
    end
    y = y + 2
  end

  for _, fz in ipairs(F.furnaces) do
    local s = furnState[fz] or {}
    line(("Furnace %s: %d cooking, fuel %d"):format(shortNum(fz), s.cooking or 0, s.fuel or 0))
  end
  if #F.furnaces == 0 then line("No furnace: rubber -> dock -> smelter") end
  line(F.dock and ("Dock: fuel for %d, %d plastic out"):format(dockFuel, dockPlastic) or "Dock: none", F.dock and colours.lightGrey or colours.yellow)
  for _, msg in pairs(problems) do
    line((msg:gsub("^Plastic factory: ", "")), colours.red)
  end
end

---------------------------------------------------------------------------
-- Loops
---------------------------------------------------------------------------
local function workLoop()
  while true do
    local ok, err = pcall(pass)
    if not ok then note = "Error: " .. tostring(err); problem("error", true, "Plastic factory error: " .. tostring(err))
    else problem("error", false) end
    pcall(draw)
    os.sleep(math.max(1, E.TICK or 2))
  end
end

local function setPaused(p)
  cfg.paused = p
  saveCfg(true)
  note = p and "Paused" or "Running"
  pcall(draw)
end

local function eventLoop()
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" and mon and peripheral.getName(mon) == a then
      if button and c == button.y and b >= button.x1 and b <= button.x2 then setPaused(not cfg.paused) end
    elseif ev == "peripheral" or ev == "peripheral_detach" or ev == "monitor_resize" then
      findMonitor(); pcall(draw)
    end
  end
end

local netOn = false
local function netLoop()
  if not netOn then return os.pullEvent("never") end
  while true do
    local problemsOut = {}
    for k, v in pairs(problems) do problemsOut[k] = v end
    rednet.broadcast({ type = "factory", id = os.getComputerID(), label = os.getComputerLabel() or "Plastic",
      state = stateWord(), note = note, lines = statusLines(), problems = problemsOut,
      plastic = cfg.plastic, rate = latexRate(), paused = cfg.paused }, BASE)
    local _, msg = rednet.receive(BASE, 3)
    if type(msg) == "table" and msg.type == "factory_cmd" and (msg.to == nil or msg.to == os.getComputerID()) then
      if msg.want == "pause" then setPaused(true) elseif msg.want == "go" then setPaused(false) end
    end
  end
end

local function help()
  print("status    what's going on")
  print("list      what I found on my cable")
  print("pause     stop moving things (machines keep their contents)")
  print("resume    carry on")
  print("Settings: plastic.env (edit plastic.env)")
end

local function terminalLoop()
  term.clear(); term.setCursorPos(1, 1)
  print("Plastic factory online.")
  help()
  while true do
    print()
    write("plastic> ")
    local q = read():lower()
    if q:match("^%s*list") then
      scan()
      print("Taps:     " .. (#F.taps > 0 and table.concat(F.taps, ", ") or "none"))
      print("Units:    " .. (#F.units > 0 and table.concat(F.units, ", ") or "none"))
      print("Water:    " .. (#F.water > 0 and table.concat(F.water, ", ") or "none"))
      print("Buffers:  " .. (#F.buffers > 0 and table.concat(F.buffers, ", ") or "none"))
      print("Furnaces: " .. (#F.furnaces > 0 and table.concat(F.furnaces, ", ") or "none"))
      print("Dock:     " .. tostring(F.dock or "none"))
      if F.dockNote then printError(F.dockNote) end
    elseif q:match("^%s*pause") or q:match("^%s*stop") then
      setPaused(true); print("Paused.")
    elseif q:match("^%s*resume") or q:match("^%s*go") or q:match("^%s*run") then
      setPaused(false); print("Running.")
    elseif q:match("^%s*status") or q:match("^%s*$") then
      for _, l in ipairs(statusLines()) do print(l) end
      for _, msg in pairs(problems) do printError(msg) end
    else
      help()
    end
  end
end

-- Talk on every modem (a wireless/ender one reaches the mainframe; it's optional)
peripheral.find("modem", function(name, m)
  if m.isWireless and m.isWireless() then rednet.open(name); netOn = true end
  return false
end)
readEnv()
loadCfg()
findMonitor()
scan()
note = cfg.paused and "Paused" or "Starting"
parallel.waitForAny(workLoop, eventLoop, netLoop, terminalLoop)
