-- opneeds.lua  --  what each reactor needs, has and is missing, worked out from what the device and the cable show.
-- A list of small checks; each is  { key, title, fn(ctx) -> state, why }  with state "ok" | "missing" | "unknown" | "na" (not needed for this reactor).
-- "unknown" means the Operator can't tell (not "missing"). Add a check by adding one entry to CHECKS.
--   ctx = { unit, status, plant (found devices), driver, supply (uranium in storage, or nil), E }
local plantlib = require("opplant")

local function ok(why) return "ok", why or "" end
local function missing(why) return "missing", why end
local function unknown(why) return "unknown", why end

local function bare(id) return (tostring(id):gsub("^BigReactors%-", "")) end
local function deg(n) return n ~= nil and (math.floor(n + 0.5) .. "C") or "" end

-- The order here is the order on the Needs tab. `value` is what an ok row shows, `why` what a missing or unknown row says.
local CHECKS = {
  { "computer", "Computer port", function(c)
      if c.status and c.status.answers then return ok(bare(c.unit.id)) end
      return missing("the reactor doesn't answer on the cable (needs a reinforced computer port and a modem)")
    end },
  { "fuelIn", "Fuel inlet port", function(c)
      local u = c.unit
      if u.inputGone then return missing("input port " .. tostring(u.input) .. " is not on the cable") end
      if u.input then
        local n = plantlib.contents(u.input)
        return ok(u.input .. (n and (", " .. n .. " uranium") or ""))
      end
      return unknown(u.portNote or "no input port known")
    end },
  { "fuel", "Fuel in reactor", function(c)
      local s, u = c.status or {}, c.unit
      local inPort = u.input and plantlib.contents(u.input)
      if (inPort or 0) > 0 or (s.fuel or 0) > 0 then return ok(s.fuelMax and s.fuelMax > 0 and (math.floor((s.fuel or 0) / s.fuelMax * 100 + 0.5) .. "%") or "") end
      if not u.input then return unknown("no inlet port known to look in") end
      if inPort == nil then return unknown("can't read the inlet port") end
      return missing("no uranium in the inlet port or the reactor")
    end },
  { "supply", "Fuel supply", function(c)
      local sup = c.supply
      if sup == nil then return unknown("Storage silent") end
      if sup > 0 then return ok("Storage: " .. sup .. " ingots") end
      return missing("no uranium left in storage")
    end },
  { "wasteOut", "Waste outlet port", function(c)
      local u = c.unit
      if u.outputGone then return missing("output port " .. tostring(u.output) .. " is not on the cable") end
      if u.output then return ok(u.output) end
      return unknown(u.portNote or "no output port known")
    end },
  { "wasteTo", "Waste clearing", function(c)
      local u = c.unit
      if u.wasteStuck then return missing("outlet not emptying") end
      if not u.output then return unknown("no outlet port known to watch") end
      if u.outputCount == nil then return unknown("can't read outlet") end
      return ok("draining")
    end },
  { "power", "Power output", function(c)
      -- A passive reactor's power tap isn't on the cable; all we can say is that it reports output.
      if c.driver and c.driver.kind == "passive" then
        if c.status and c.status.fe ~= nil then return unknown("tap not on cable") end
        return unknown("no power reading")
      end
      return ok()
    end },
  { "rods", "Control rods", function(c)
      local n = c.driver and c.driver:rods()
      if n then return ok(n .. " found") end
      return unknown("can't read the control rods")
    end },
  { "ftemp", "Fuel temperature", function(c)
      local t = c.status and c.status.fuelTemp
      if t ~= nil then return ok(deg(t)) end
      return unknown("not readable")
    end },
  { "ctemp", "Casing temperature", function(c)
      local t = c.status and c.status.casing
      if t ~= nil then return ok(deg(t)) end
      return unknown("not readable")
    end },
  { "turbine", "Coolant and turbine", function(c)
      if not (c.driver and c.driver.kind == "active") then return "na", "not needed, passive" end
      local s = c.status or {}
      if #(c.plant.turbine or {}) == 0 then return missing("no turbine on the cable") end
      if s.coolant == nil and s.hot == nil then return unknown("coolant not readable") end
      return ok(#c.plant.turbine .. " turbine" .. (#c.plant.turbine == 1 and "" or "s"))
    end },
}

local M = { CHECKS = CHECKS }

-- Returns a list of { key, title, state, why }  (why = the value when ok) for one reactor unit
function M.evaluate(ctx)
  local out = {}
  for _, ch in ipairs(CHECKS) do
    local okc, state, why = pcall(ch[3], ctx)
    if not okc then state, why = "unknown", "check failed" end
    out[#out + 1] = { key = ch[1], title = ch[2], state = state, why = why or "" }
  end
  return out
end

-- Short text: the first thing missing ("" when nothing is)
function M.summary(needs)
  for _, n in ipairs(needs or {}) do if n.state == "missing" then return n.title .. ": " .. n.why end end
  return ""
end

return M
