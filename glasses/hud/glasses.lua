-- glasses.lua  --  Smart Glasses role (Advanced Peripherals 0.8, worn on the head or in a Curios slot)
--
-- Stage 1 (now): reports what the glasses have - modules, what each module can do, and the
-- configuration - so the night vision toggle can be written against the real API.
-- The full report is saved to glasses_report.txt. On screen it pages: press any key for more.
--
-- Later stages (night vision toggle, HUD, mainframe link) replace this file via the repo;
-- just reboot the glasses (hold Ctrl+R) to pick them up.

local REPORT = "glasses_report.txt"

local function say(colour, text)
  if term.isColour() then term.setTextColour(colour) end
  print(text)
  term.setTextColour(colours.white)
end

local glasses = peripheral.find("smart_glasses")
if not glasses then
  printError("No smart_glasses peripheral found.")
  printError("Put the glasses on (head or Curios slot), then reboot.")
  return
end

local lines = {}
local function out(s) lines[#lines + 1] = tostring(s) end

-- Safe dump: nested tables, marks functions, no infinite loops.
local function dump(v, indent, seen)
  indent = indent or ""
  seen = seen or {}
  local t = type(v)
  if t == "function" then return "<function>" end
  if t == "string" then return ("%q"):format(v) end
  if t ~= "table" then return tostring(v) end
  if seen[v] then return "<loop>" end
  seen[v] = true
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  if #keys == 0 then return "{}" end
  local parts = { "{" }
  for _, k in ipairs(keys) do
    parts[#parts + 1] = indent .. "  " .. tostring(k) .. " = " .. dump(v[k], indent .. "  ", seen)
  end
  parts[#parts + 1] = indent .. "}"
  return table.concat(parts, "\n")
end

-- Call safely; report errors instead of crashing.
local function try(label, fn, ...)
  if type(fn) ~= "function" then out(label .. ": not available"); return end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
  out(label .. " ERROR: " .. tostring(a))
end

out("== Smart Glasses report ==")
out("label:    " .. tostring(os.getComputerLabel()))
out("id:       " .. tostring(os.getComputerID()))
out("equipped: " .. tostring(smartglasses and smartglasses.isEquipped and smartglasses.isEquipped()))
if smartglasses then
  local apiFns = {}
  for k, v in pairs(smartglasses) do if type(v) == "function" then apiFns[#apiFns + 1] = k end end
  table.sort(apiFns)
  out("smartglasses API: " .. table.concat(apiFns, ", "))
end
out("name:     " .. tostring(try("getName", glasses.getName)))
out("")

out("-- peripherals --")
for _, name in ipairs(peripheral.getNames()) do
  out(name .. " (" .. tostring(peripheral.getType(name)) .. ")")
end
out("")

out("-- getConfiguration() --")
out(dump(try("getConfiguration", glasses.getConfiguration)))
out("")

out("-- getModules() --")
local modules = try("getModules", glasses.getModules)
out(dump(modules))
out("")

-- Module names, whether getModules returns a list or a keyed table.
local names, seenName = {}, {}
local function addName(n)
  if type(n) == "string" and not seenName[n] then seenName[n] = true; names[#names + 1] = n end
end
if type(modules) == "table" then
  for k, v in pairs(modules) do
    if type(v) == "string" then addName(v)
    elseif type(v) == "table" then addName(v.name or v.id or v.type)
    end
    if type(k) == "string" then addName(k) end
  end
end
table.sort(names)

if #names == 0 then
  out("No modules found. Is the Night Vision Module slotted in?")
end

for _, name in ipairs(names) do
  out("== module: " .. name .. " ==")
  out("hasModule: " .. tostring(try("hasModule", glasses.hasModule, name)))
  local mod = try("getModule", glasses.getModule, name)
  if type(mod) == "table" then
    local fns = {}
    for k, v in pairs(mod) do if type(v) == "function" then fns[#fns + 1] = k end end
    table.sort(fns)
    out("functions: " .. (#fns > 0 and table.concat(fns, ", ") or "(none)"))
  end
  out(dump(mod))
  out("")
end

local f = fs.open(REPORT, "w")
f.write(table.concat(lines, "\n"))
f.close()

term.clear(); term.setCursorPos(1, 1)
textutils.pagedPrint(table.concat(lines, "\n"))
print("")
say(colours.lime, "Saved to " .. REPORT)
say(colours.lightGrey, "Read it again: edit " .. REPORT)
