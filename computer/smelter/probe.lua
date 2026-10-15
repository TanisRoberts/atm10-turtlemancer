-- probe.lua  --  one-off test of a Mekanism enriching factory fed by a barrel + hopper (round 3)
--
-- Run it on the smelter computer (hold Ctrl+T to stop the smelter, then type: probe).
--   probe                         feed barrel sophisticatedstorage:barrel_64, eject barrel _63, raw iron
--   probe <feed> <out> [item] [n] e.g. probe sophisticatedstorage:barrel_64 sophisticatedstorage:barrel_63 minecraft:raw_iron 9
--
-- What we know so far (claude/atm10-reference-enrichment.md): the factory is read-only over the
-- cable (Mekanism's own peripheral, CC asks for its slots with no side). So items go in through a
-- barrel on the cable with a hopper under it pointing into an Input face, and come out by auto-eject
-- into a barrel on an Output face. This round times the whole trip:
--   storage -> feed barrel -> hopper -> factory input -> dust -> eject -> out barrel
-- It turns auto-eject on if it's off (and says so), leaves the dust in the out barrel (storage
-- sorts it once that barrel is an Input), writes probe.log and uploads it to pastebin at the end.
-- Reboot afterwards (hold Ctrl+R) to start the smelter again.

local LOG        = "probe.log"
local WATCH_TIME = 90        -- seconds to wait for everything to come out
local args       = { ... }
local FEED       = args[1] or "sophisticatedstorage:barrel_64"
local OUT        = args[2] or "sophisticatedstorage:barrel_63"
local ITEM       = args[3] or "minecraft:raw_iron"
local AMOUNT     = tonumber(args[4]) or 9          -- 9 raw = a batch of 3 for each of 3 processes

local logLines = {}
local function detail(s) logLines[#logLines + 1] = tostring(s) end
local function say(s, col)
  detail(s)
  if col and term.isColour() then term.setTextColour(col) end
  print(s)
  term.setTextColour(colours.white)
end
local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local ok, s = pcall(textutils.serialize, v, { compact = true })
  if not ok then ok, s = pcall(textutils.serialize, v) end
  if not ok then return "<table>" end
  s = s:gsub("%s+", " ")
  if #s > 300 then s = s:sub(1, 300) .. " ..." end
  return s
end
local function call(name, method, ...)
  local res = table.pack(pcall(peripheral.call, name, method, ...))
  if not res[1] then return false, tostring(res[2]) end
  return true, table.unpack(res, 2, res.n)
end
local function short(id) return (tostring(id):gsub("^[^:]*:", "")) end
local function typeText(n) return table.concat({ peripheral.getType(n) }, ", ") end

-- Save the log and put it on pastebin (prints the link/code)
local function finish()
  local f = fs.open(LOG, "w")
  f.write(table.concat(logLines, "\n") .. "\n")
  f.close()
  print()
  if http and shell then
    say("Uploading " .. LOG .. " to pastebin...", colours.cyan)
    local ok = shell.run("pastebin", "put", LOG)
    if not ok then say("Upload failed: run  pastebin put " .. LOG .. "  yourself.", colours.orange) end
  else
    say("Run  pastebin put " .. LOG .. "  to share it.", colours.cyan)
  end
  say("Hold Ctrl+R to start the smelter again.")
end

---------------------------------------------------------------------------
-- 1. Find everything
---------------------------------------------------------------------------
local names = peripheral.getNames()
table.sort(names)
detail("== probe.lua round 3  " .. os.date("%Y-%m-%d %H:%M") .. "  computer " .. os.getComputerID())
detail("== Peripherals on my cable:")
for _, n in ipairs(names) do detail("  " .. n .. "  [" .. typeText(n) .. "]") end

local function looksLikeEnricher(n)
  if n:lower():find("enrich") then return true end
  for _, t in ipairs({ peripheral.getType(n) }) do if tostring(t):lower():find("enrich") then return true end end
  return false
end
local machine
for _, n in ipairs(names) do if looksLikeEnricher(n) and not machine then machine = n end end
for _, n in ipairs(names) do if looksLikeEnricher(n) and n:find("[Ff]actory") then machine = n; break end end

local bad = false
if not machine then say("No enriching factory on my cable (modem on it, ring red?).", colours.red); bad = true end
if not peripheral.isPresent(FEED) then say("Feed barrel " .. FEED .. " isn't on my cable.", colours.red); bad = true end
if not peripheral.isPresent(OUT) then say("Out barrel " .. OUT .. " isn't on my cable.", colours.red); bad = true end
if bad then finish(); return end
say("Factory: " .. machine, colours.cyan)
say("Feed:    " .. FEED .. "   Out: " .. OUT)

---------------------------------------------------------------------------
-- 2. Factory settings: power, sides, eject
---------------------------------------------------------------------------
local has = {}
for _, m in ipairs(peripheral.getMethods(machine) or {}) do has[m] = true end
local function get(m, ...)
  if not has[m] then return nil end
  local ok, v = call(machine, m, ...)
  detail(("  %s(%s) = %s"):format(m, table.concat({ ... }, ", "), ok and show(v) or ("error: " .. tostring(v))))
  if ok then return v end
end
detail("== Factory settings")
local pct = get("getEnergyFilledPercentage")
local ticks = get("getTicksRequired")
get("getDirection"); get("getInstalledUpgrades"); get("isAutoSortEnabled")
local SIDES = { "FRONT", "BACK", "LEFT", "RIGHT", "TOP", "BOTTOM" }
local parts = {}
for _, s in ipairs(SIDES) do
  local ok, v = call(machine, "getMode", "ITEM", s)
  parts[#parts + 1] = s:sub(1, 1) .. s:sub(2):lower() .. "=" .. (ok and tostring(v) or "?")
end
detail("  item sides: " .. table.concat(parts, " "))
say(("Energy %s, %s ticks per op"):format(pct and ("%.0f%%"):format(pct * 100) or "?", tostring(ticks or "?")),
  (pct or 1) <= 0 and colours.orange or nil)
say("Item sides: " .. table.concat(parts, " "))

local ejecting = get("isEjecting", "ITEM")
local ejectNote = "was already on"
if ejecting == false then
  local ok, err = call(machine, "setEjecting", "ITEM", true)
  local now = get("isEjecting", "ITEM")
  if ok and now then ejectNote = "was OFF: I turned it on"
  else ejectNote = "is OFF and I couldn't turn it on (" .. tostring(err) .. "): turn it on in Side Config" end
end
say("Auto-eject: " .. ejectNote, ejecting == false and colours.yellow or colours.lime)

---------------------------------------------------------------------------
-- 3. What's where (feed barrel, factory, out barrel)
---------------------------------------------------------------------------
local PROCS = 0
for p = 0, 15 do
  if not call(machine, "getInput", p) then break end
  PROCS = p + 1
end
local function invCount(n, name)
  local ok, l = call(n, "list")
  local c, all = 0, {}
  if ok and type(l) == "table" then
    for _, it in pairs(l) do
      all[it.name] = (all[it.name] or 0) + it.count
      if not name or it.name == name then c = c + it.count end
    end
  end
  return c, all
end
local function factoryNow()
  local ins, outs = {}, {}
  for p = 0, PROCS - 1 do
    local _, i = call(machine, "getInput", p)
    local _, o = call(machine, "getOutput", p)
    if type(i) == "table" and i.name and i.name ~= "minecraft:air" and (i.count or 0) > 0 then ins[i.name] = (ins[i.name] or 0) + i.count end
    if type(o) == "table" and o.name and o.name ~= "minecraft:air" and (o.count or 0) > 0 then outs[o.name] = (outs[o.name] or 0) + o.count end
  end
  return ins, outs
end
local function bag(t)
  local s = {}
  for k, v in pairs(t) do s[#s + 1] = v .. " " .. short(k) end
  table.sort(s)
  return #s > 0 and table.concat(s, ", ") or "-"
end

local _, feed0 = invCount(FEED)
local _, out0 = invCount(OUT)
local fin0, fout0 = factoryNow()
detail("== Before: feed {" .. bag(feed0) .. "}  factory in {" .. bag(fin0) .. "} out {" .. bag(fout0) .. "}  out barrel {" .. bag(out0) .. "}")
if next(feed0) then say("Feed barrel already has: " .. bag(feed0), colours.yellow) end

---------------------------------------------------------------------------
-- 4. Put the ore in the feed barrel
---------------------------------------------------------------------------
local function skip(n)
  return n == FEED or n == OUT or n == machine or n:find("furnace") or n:find("smoker") or looksLikeEnricher(n)
    or n:find("^mekanism:") or n:find("^hostilenetworks:") or n:find("^powah:") or n:find("^industrialforegoing:")
end
local src
for _, n in ipairs(names) do
  if not src and peripheral.hasType(n, "inventory") and not skip(n) then
    local ok, l = call(n, "list")
    if ok and type(l) == "table" then
      for slot, it in pairs(l) do
        if it.name == ITEM and it.count >= AMOUNT then src = { inv = n, slot = slot }; break end
      end
    end
  end
end
if not src then
  say(("No stack of %d+ %s in storage to test with."):format(AMOUNT, ITEM), colours.red)
  finish(); return
end
local okp, moved = call(src.inv, "pushItems", FEED, src.slot, AMOUNT)
moved = okp and tonumber(moved) or 0
detail(("  %s.pushItems(%s, %d, %d) -> %s"):format(src.inv, FEED, src.slot, AMOUNT, okp and tostring(moved) or ("error: " .. tostring(moved))))
if moved == 0 then
  say("Couldn't put any " .. short(ITEM) .. " in the feed barrel.", colours.red)
  finish(); return
end
say(("Put %d %s in the feed barrel. Watching (up to %d s)..."):format(moved, short(ITEM), WATCH_TIME), colours.cyan)

---------------------------------------------------------------------------
-- 5. Watch the trip
---------------------------------------------------------------------------
local t0 = os.clock()
local marks = {}
local function mark(key, text)
  if not marks[key] then
    marks[key] = os.clock() - t0
    say(("  %5.1fs  %s"):format(marks[key], text), colours.lime)
  end
end
local last
local made, product = 0, nil
local feedVanishedTooFast = false
while os.clock() - t0 < WATCH_TIME do
  local feedN = invCount(FEED, ITEM) - (feed0[ITEM] or 0)
  local fin, fout = factoryNow()
  local _, outAll = invCount(OUT)
  local inF = (fin[ITEM] or 0) - (fin0[ITEM] or 0)
  local dustF, dustO = 0, 0
  for k, v in pairs(fout) do if k ~= ITEM then dustF = dustF + v - (fout0[k] or 0); product = product or k end end
  for k, v in pairs(outAll) do
    local extra = v - (out0[k] or 0)
    if k ~= ITEM and extra > 0 then dustO = dustO + extra; product = product or k end
  end
  local line = ("feed %d | factory in %d, out %d | out barrel %d"):format(feedN, inF, dustF, dustO)
  if line ~= last then detail(("  %5.1fs  %s"):format(os.clock() - t0, line)); last = line end

  if feedN < moved then mark("hopper", "hopper started taking it from the feed barrel") end
  if feedN <= 0 then
    mark("feedEmpty", "feed barrel empty")
    -- a hopper moves 1 item / 0.4 s: much faster than that means something else took it
    if marks.feedEmpty < (moved - 1) * 0.4 * 0.5 then feedVanishedTooFast = true end
  end
  if inF > 0 then mark("factoryIn", "first ore in the factory") end
  if dustF > 0 then mark("dustMade", "first dust made (" .. short(product) .. ")") end
  if dustO > 0 then mark("dustOut", "first dust ejected into the out barrel") end
  made = dustO
  local rawLeft = math.max(0, feedN) + math.max(0, inF)
  if marks.dustOut and rawLeft == 0 and dustF <= 0 then
    os.sleep(1)
    local _, outAll2 = invCount(OUT)
    made = 0
    for k, v in pairs(outAll2) do if k ~= ITEM then made = made + math.max(0, v - (out0[k] or 0)) end end
    break
  end
  os.sleep(0.5)
end

---------------------------------------------------------------------------
-- 6. Summary
---------------------------------------------------------------------------
print()
local total = os.clock() - t0
local feedLeft = invCount(FEED, ITEM) - (feed0[ITEM] or 0)
local finEnd = factoryNow()
local stuckIn = (finEnd[ITEM] or 0) - (fin0[ITEM] or 0)
detail("== Summary")
detail("marks=" .. show(marks))
detail(("moved=%d made=%d product=%s feedLeft=%d inFactory=%d total=%.1f eject=%s"):format(moved, made,
  tostring(product), feedLeft, stuckIn, total, ejectNote))
say("Summary", colours.cyan)
if product and made > 0 then
  say((" %d %s -> %d %s in %.1f s"):format(moved, short(ITEM), made, short(product), total), colours.lime)
else
  say(" Nothing reached the out barrel.", colours.orange)
end
if marks.hopper then say((" hopper picked it up after %.1f s"):format(marks.hopper)) end
if feedVanishedTooFast then
  say(" The feed barrel emptied faster than a hopper can: storage may be taking from it.", colours.orange)
  say(" Set the feed barrel to Ignore in storage's /assign.", colours.orange)
end
if feedLeft > 0 then say((" %d still in the feed barrel"):format(feedLeft), colours.orange) end
if stuckIn > 0 then
  local per = {}
  for p = 0, PROCS - 1 do
    local _, i = call(machine, "getInput", p)
    per[#per + 1] = tostring((type(i) == "table" and i.name == ITEM) and i.count or 0)
  end
  detail("  left in each process: " .. table.concat(per, "/"))
  say((" %d still in the factory's inputs (%s per process): each needs 3 for a batch."):format(stuckIn, table.concat(per, "/")), colours.yellow)
  if has.isAutoSortEnabled then say(" Auto-sort spreads ore across the processes, so feed it in multiples of " .. (3 * PROCS) .. ".", colours.yellow) end
end
if not marks.hopper then say(" The hopper never took anything: is it pointing into the factory, and unpowered?", colours.orange) end
if marks.factoryIn and not marks.dustMade then say(" Ore went in but no dust came out: power?", colours.orange) end
if marks.dustMade and not marks.dustOut then say(" Dust was made but not ejected: eject on? Right face Output?", colours.orange) end
finish()
