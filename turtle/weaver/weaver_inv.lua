-- weaver_inv.lua  --  what he carries, and the dock visit: empty what he won't need into the ender chest under the
-- dock, ask storage for the next batch, suck it out once it has arrived (docs/systems/weaver.md section 7).
-- A part of weaver.lua.

KEEP_ALWAYS = { ["minecraft:bucket"] = false }
function isGear(name) return name == core.chunk.ITEM or core.chunk.isModem(name) end

function counts()
  local c = {}
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d then c[d.name] = (c[d.name] or 0) + d.count end
  end
  return c
end
function slotOf(name)
  for s = 1, 16 do local d = turtle.getItemDetail(s); if d and d.name == name then return s end end
end

-- Things dug on the way (sand, leaves ...) are thrown away; his gear, fuel, empty buckets and the build's blocks stay
function dropJunk()
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isGear(d.name) and not BUILD[d.name] and not (WANTNOW and WANTNOW[d.name])
        and d.name ~= "minecraft:bucket" then
      turtle.select(s)
      if not turtle.refuel(0) then turtle.dropUp() end
    end
  end
  turtle.select(1)
end

-- The blocks for the cells he'll build next (this work list, then the held layers), as many as fit in SLOT_BLOCKS slots
function planBatch()
  local want, used = {}, 0
  for c in aheadCells() do
    local need = (c[5] == "2") and 2 or 1
    local old = want[c[4]] or 0
    local nu = used - math.ceil(old / STACK) + math.ceil((old + need) / STACK)
    if nu > SLOT_BLOCKS then break end
    want[c[4]], used = old + need, nu
  end
  return want
end

-- Burn the fuel he carries (never an item the build needs), then stack the empty buckets
function burnFuel(target)
  local F = core.fuel
  target = math.min(target or ENV.v.FUEL_TARGET, F.limit())
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and F.isFuel(d.name) and not (WANTNOW and WANTNOW[d.name]) and F.level() < target then F.burnSlot(s, target) end
  end
  F.stackEmpties()
  turtle.select(1)
end

-- Everything he won't need goes down into the chest (empty buckets and spare fuel too)
local function dropUnwanted(want)
  for s = 1, 16 do
    local d = turtle.getItemDetail(s)
    if d and not isGear(d.name) and not want[d.name] then
      turtle.select(s); turtle.dropDown()
    end
  end
  turtle.select(1)
end

local function waitReply(sup)
  local last = -1e9
  while not sup.reply do
    if orderWaiting() then return false end
    if os.clock() - last >= 5 then
      last = os.clock()
      send({ type = "supply", seq = sup.seq, items = sup.items, fuel = sup.fuel })
    end
    setStatus("supply", "Asked storage, waiting for the answer")
    os.sleep(0.5)
  end
  return true
end

-- Suck from the chest until everything storage says it sent has arrived (up to SUPPLY_WAIT s)
local function collect(sup)
  local deadline = os.clock() + ENV.v.SUPPLY_WAIT
  local function complete()
    for n, c in pairs(sup.reply.sent or {}) do if (sup.got[n] or 0) < c then return false end end
    return true
  end
  while true do
    local before = counts()
    if turtle.suckDown() then
      for n, c in pairs(counts()) do
        local d = c - (before[n] or 0)
        if d > 0 then sup.got[n] = (sup.got[n] or 0) + d end
      end
      burnFuel(); save()
      deadline = math.max(deadline, os.clock() + 2)
    else
      if complete() or os.clock() > deadline then break end
      setStatus("supply", "Waiting for the delivery to arrive")
      os.sleep(0.5)
    end
  end
  return complete()
end

-- An open supply request (also after a reboot): wait for the answer, collect, record what is missing
function finishSupply()
  local sup = S.sup
  if not atDock() then local ok = goHome(); if not ok then return false end end
  if not waitReply(sup) then return false end
  save()
  collect(sup)
  for n in pairs(sup.items) do S.short[n] = nil end
  for n, c in pairs(sup.reply.missing or {}) do if c > 0 then S.short[n] = true end end
  S.sup = nil; save()
  burnFuel()
  return true
end

function dockVisit()
  setStatus("dock", "Going home for supplies")
  local ok, why = goHome()
  if not ok then setStatus("blocked", "Can't get home: " .. tostring(why)); os.sleep(10); return false end
  WANTNOW = nil
  burnFuel()
  local want = planBatch()
  WANTNOW = want
  dropUnwanted(want)
  local have, items = counts(), {}
  for n, c in pairs(want) do if c > (have[n] or 0) then items[n] = c - (have[n] or 0) end end
  local lvl, limit = fuelLevel(), core.fuel.limit()
  local fuel = (lvl < ENV.v.FUEL_LOW or lvl < fuelHome() + 500) and (math.min(ENV.v.FUEL_TARGET, limit) - lvl) or 0
  S.visitKey = S.work .. ":" .. tostring(S.layer) .. ":" .. tostring(S.idx)
  if next(items) == nil and fuel <= 0 then return true end
  S.supSeq = S.supSeq + 1
  S.sup = { seq = S.supSeq, items = items, fuel = fuel, got = {} }
  save()
  return finishSupply()
end
