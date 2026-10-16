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

-- Rows for the status board: { name, state, detail, seen }. One row with the plant totals; with more than one
-- reactor, a row for each reactor under it.
function F.boardRows(op, seen)
  local R = F.reactors(op)
  local p = op.plant or {}
  local worst, running = "idle", 0
  for _, u in ipairs(R) do
    local s = F.state(u)
    if s == "running" then running = running + 1 end
    if s == "waiting" or s == "offline" then worst = s elseif worst == "idle" and s == "running" then worst = "running" end
    if worst == "running" and s == "waiting" then worst = "waiting" end
  end
  if #R == 0 then worst = "waiting" end
  local lead = #R > 1 and ("%d of %d on, "):format(running, #R) or ((running > 0 and "ON, " or "OFF, "))
  if #R == 0 then lead = "no reactor found, " end
  local rows = { { op.label or "Operator", worst, ("%s%s FE/t, buffer %s, %s"):format(lead, num(p.fe or 0), pct(p.buf), uranium(op)), seen } }
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
function F.plantLine(op, age)
  local R = F.reactors(op)
  local p = op.plant or {}
  if #R == 0 then return "Operator: no reactor on its cable." end
  if #R == 1 then return F.unitLine(R[1]) .. " " .. uranium(op):gsub("^%l", string.upper) .. "." end
  local running = 0
  for _, u in ipairs(R) do if u.active then running = running + 1 end end
  local line = ("Operator: %d reactors, %d on, %s FE/t, buffer %s. %s."):format(#R, running, num(p.fe or 0), pct(p.buf),
    uranium(op):gsub("^%l", string.upper))
  local bad = {}
  for _, u in ipairs(R) do
    local s = F.state(u)
    if s == "waiting" or s == "offline" then bad[#bad + 1] = u.label end
  end
  if #bad > 0 then line = line .. " Needs a look: " .. table.concat(bad, ", ") .. "." end
  return line
end

-- Problems for alerts: { [key] = text }. `low` = alert when the uranium supply is under this many ingots.
function F.problems(op, low)
  local out = {}
  for _, u in ipairs(F.reactors(op)) do
    if not u.present then out["gone:" .. u.label] = u.label .. " is not on the cable any more."
    elseif not u.answers then out["quiet:" .. u.label] = u.label .. " is not answering. Check its computer port and the cable."
    elseif u.wasteStuck then out["waste:" .. u.label] = u.label .. ": waste not clearing. The outlet port isn't emptying; is Storage running?" end
  end
  local sup = op.plant and op.plant.supply
  if sup ~= nil and sup < (low or 16) then
    out["fuel"] = ("Fuel supply low: only %s uranium ingots left in Storage (alert under %d)."):format(num(sup), low or 16)
  end
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
