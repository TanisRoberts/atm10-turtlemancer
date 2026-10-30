-- operator_fmt.lua  --  how the mainframe reads the Operator's status (_G.OPERATOR): board rows, chat lines, problems
-- for alerts, and the words of a chat command. Used by board.lua and island.lua (issue #36).
local F = {}

local function num(n)
  if type(n) ~= "number" then return "?" end
  local s = tostring(math.floor(n + 0.5))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
local function pct(f) return f and (math.floor(f * 100 + 0.5) .. "%") or "?" end
F.num = num

function F.reactors(op)
  local out = {}
  for _, u in ipairs(op and op.units or {}) do if u.kind == "reactor" then out[#out + 1] = u end end
  return out
end

local function missingCount(u)
  local n = 0
  for _, x in ipairs(u.needs or {}) do if x.state == "missing" then n = n + 1 end end
  return n
end

-- running | idle | waiting (something is missing) | offline
function F.state(u)
  if u.awaiting then return "setup" end
  if not u.present or not u.answers then return "offline" end
  if u.wasteStuck or missingCount(u) > 0 then return "waiting" end
  return u.active and "running" or "idle"
end

-- Uranium left, from Storage's report, else what sits in the inlets
local function uranium(op)
  local p = op.plant or {}
  if p.supply ~= nil then return "uranium " .. num(p.supply) end
  if p.uranium then return "inlet " .. num(p.uranium) end
  return "uranium ?"
end

-- Storage's reactor_fuel report is heard every 10 s; this long without one and it is stale
F.FUEL_STALE = 60

-- The report as the board and chat show it: "fuel chest 48/64, store 412"; "fuel chest ?" when it has gone quiet.
-- nil when Storage has never reported (callers fall back to the uranium text).
function F.fuelText(rf, age)
  if not rf then return nil end
  if age and age > F.FUEL_STALE then return "fuel chest ?" end
  local units, keep = 0, 0
  for _, c in ipairs(rf.chests or {}) do units, keep = units + (c.units or 0), keep + (c.keep or 0) end
  local out = ("fuel chest %s/%s"):format(num(units), num(keep))
  if rf.supply ~= nil then out = out .. ", store " .. num(rf.supply) end
  return out
end

-- Rows for the status board: { name, state, detail, seen }. One row with the plant totals; with more than one
-- reactor, a row for each reactor under it. `rf`/`rfAge`: Storage's reactor_fuel report and its age in seconds.
function F.boardRows(op, seen, rf, rfAge)
  local R = F.reactors(op)
  local p = op.plant or {}
  local worst, running, setup = "idle", 0, 0
  for _, u in ipairs(R) do
    local s = F.state(u)
    if s == "running" then running = running + 1 end
    if s == "waiting" or s == "offline" then worst = s elseif worst == "idle" and s == "running" then worst = "running" end
    if worst == "running" and s == "waiting" then worst = "waiting" end
    if s == "setup" then setup = setup + 1; if worst == "idle" or worst == "running" then worst = "setup" end end
  end
  if #R == 0 then worst = "waiting" end
  local lead = #R > 1 and ("%d of %d on, "):format(running, #R) or ((running > 0 and "ON, " or "OFF, "))
  if #R == 0 then lead = "no reactor found, " end
  if setup > 0 then lead = ("%d awaiting setup, "):format(setup) .. lead end
  local rows = { { op.label or "Operator", worst, ("%s%s FE/t, buffer %s, %s"):format(lead, num(p.fe or 0), pct(p.buf), F.fuelText(rf, rfAge) or uranium(op)), seen } }
  if #R > 1 then
    for _, u in ipairs(R) do
      rows[#rows + 1] = { "  " .. u.label, F.state(u), ("%s %s FE/t, buffer %s%s"):format(u.active and "ON" or "OFF",
        num(u.fe or 0), pct(u.buf), u.level and (", level " .. math.floor(u.level + 0.5) .. "%") or ""), seen }
    end
  end
  return rows
end

-- Chat: one line for a reactor
function F.unitLine(u)
  if u.awaiting then return u.label .. ": New Reactor Awaiting Setup. Finish it on the Operator's screen; until then it is not switched." end
  local bits = { ("%s: %s"):format(u.label, F.state(u) == "offline" and "NOT ANSWERING" or (u.active and "ON" or "OFF")) }
  bits[#bits + 1] = ("%s FE/t, buffer %s"):format(num(u.fe or 0), pct(u.buf))
  if u.level then bits[#bits + 1] = "level " .. math.floor(u.level + 0.5) .. "%" end
  bits[#bits + 1] = "mode " .. tostring(u.mode or "auto"):upper()
  if u.fuel and u.fuelMax and u.fuelMax > 0 then bits[#bits + 1] = "fuel " .. pct(u.fuel / u.fuelMax) end
  local line = table.concat(bits, ", ") .. "."
  if u.wasteStuck then line = line .. " Waste not clearing." end
  for _, x in ipairs(u.needs or {}) do
    if x.state == "missing" and x.key ~= "wasteTo" then line = line .. " Missing: " .. x.title:lower() .. "." end
  end
  return line
end

-- Chat: one line for the plant
function F.plantLine(op, rf, rfAge)
  local fuel = F.fuelText(rf, rfAge)
  local function ura() return fuel and fuel:gsub("^%l", string.upper) or uranium(op):gsub("^%l", string.upper) end
  local R = F.reactors(op)
  local p = op.plant or {}
  if #R == 0 then return "Operator: no reactor on its cable." end
  if #R == 1 then return F.unitLine(R[1]) .. " " .. ura() .. "." end
  local running = 0
  for _, u in ipairs(R) do if u.active then running = running + 1 end end
  local line = ("Operator: %d reactors, %d on, %s FE/t, buffer %s. %s."):format(#R, running, num(p.fe or 0), pct(p.buf), ura())
  local bad = {}
  for _, u in ipairs(R) do
    local s = F.state(u)
    if s == "waiting" or s == "offline" then bad[#bad + 1] = u.label end
  end
  if #bad > 0 then line = line .. " Needs a look: " .. table.concat(bad, ", ") .. "." end
  return line
end

-- Problems for alerts: { [key] = text }.
function F.problems(op)
  local out = {}
  for _, u in ipairs(F.reactors(op)) do
    if not u.present then out["gone:" .. u.label] = u.label .. " is not on the cable any more."
    elseif not u.answers then out["quiet:" .. u.label] = u.label .. " is not answering. Check its computer port and the cable."
    elseif u.awaiting then -- not set up yet: nothing to report
    elseif u.wasteStuck then out["waste:" .. u.label] = u.label .. ": waste not clearing. The outlet port isn't emptying; is Storage running?" end
  end
  return out
end

-- Fuel problems from Storage's report (kept apart from the Operator's, so they hold while it is quiet).
-- Nothing is raised for a stale or missing report.
function F.fuelProblems(rf, age)
  local out = {}
  if not rf or (age and age > F.FUEL_STALE) then return out end
  for _, c in ipairs(rf.chests or {}) do
    if (c.units or 0) < (c.low or 0) then
      out["chest:" .. tostring(c.name or c.label)] = ("Fuel chest low: %s has %s/%s."):format(
        tostring(c.label or c.name), num(c.units or 0), num(c.keep or 0))
    end
  end
  if rf.supply == 0 then out["nostock"] = "Nothing left to stock: Storage has no reactor fuel left." end
  return out
end

-- The reactor named in a command: "reactor-1", "1", "Reactor 2". Returns the unit, or nil and the names we know.
function F.find(op, ref)
  local names = {}
  local want = tostring(ref):lower():gsub("^reactor[%s%-]*", "")
  for _, u in ipairs(F.reactors(op)) do
    names[#names + 1] = u.label
    local have = tostring(u.label):lower():gsub("^reactor[%s%-]*", "")
    if tostring(ref):lower() == tostring(u.label):lower() or want == have then return u end
  end
  return nil, names
end

local VERBS = { on = "on", start = "on", run = "on", off = "off", stop = "off", auto = "auto", demand = "auto",
                status = "status" }

-- "reactor-1 on" / "off" / "2 auto" / "" -> reference (or nil = all reactors), verb (default "status")
function F.parse(rest)
  rest = tostring(rest or ""):lower():gsub("reactor[%s%-]*(%d+)", "reactor-%1")
  local ref, verb
  for word in rest:gmatch("%S+") do
    if VERBS[word] then verb = VERBS[word]
    elseif word:match("^reactor%-%d+$") then ref = word
    elseif word:match("^%d+$") then ref = "reactor-" .. word end
  end
  return ref, verb or "status"
end

return F
