-- opplant.lua  --  the plant model: what is on the cable, as a list of units with stable ids and labels.
--   unit = { id = peripheral name, kind = "reactor"|"turbine"|"storage", label = "Reactor-1", present, driver, cfg }
-- Units are remembered in operator.cfg keyed by id; numbers are handed out once per kind and never reused.
-- Per-unit settings live in that config too (mode, enabled, onBelow, offAbove, input, output), so a
-- later driver or policy adds to it without a new file.
-- Ports: each reactor has an input port (fuel in) and an output port (waste out). They are read from the unit's
-- config, or worked out when only one reactor is on the cable; otherwise the Operator says "unknown", never guesses.
-- The Operator only READS the ports; Storage fills the inlet and drains the outlet.
local drivers = require("opdrivers")

local M = {}
local REACTOR = "BigReactors-Reactor"
local LABEL = { reactor = "Reactor", turbine = "Turbine", storage = "Storage" }

local function lower(s) return tostring(s or ""):lower() end

-- Items -------------------------------------------------------------------
function M.fuelValue(name)       -- uranium/yellorium ingots count 1, blocks 9; ores and dust are not fuel
  local n = lower(name)
  if not (n:find("uranium") or n:find("yellorium")) then return 0 end
  if n:find("raw") or n:find("ore") or n:find("dust") or n:find("nugget") then return 0 end
  if n:find("block") then return 9 end
  if n:find("ingot") then return 1 end
  return 0
end
function M.isWaste(name) return lower(name):find("cyanite") ~= nil end

local function listOf(name)
  local p = peripheral.wrap(name)
  if not p or type(p.list) ~= "function" then return nil end
  local ok, l = pcall(p.list)
  if ok and type(l) == "table" then return l end
end
M.listOf = listOf

function M.contents(name)       -- fuel (ingots), waste (items), or nil when it can't be read
  local l = listOf(name)
  if not l then return nil end
  local fuel, waste = 0, 0
  for _, it in pairs(l) do
    fuel = fuel + M.fuelValue(it.name) * (it.count or 0)
    if M.isWaste(it.name) then waste = waste + (it.count or 0) end
  end
  return fuel, waste
end

-- Config ------------------------------------------------------------------
function M.new(file, log)
  local self = setmetatable({ file = file, log = log or function() end, units = {}, byId = {}, found = {},
                              cfg = { nextNum = {}, units = {}, plant = {} } }, { __index = M })
  self:load()
  return self
end

local function stampOf(path)
  if not fs.exists(path) or not fs.attributes then return nil end
  local ok, a = pcall(fs.attributes, path)
  return ok and a and (tostring(a.modified) .. ":" .. tostring(a.size)) or nil
end

function M:load()
  if fs.exists(self.file) then
    local f = fs.open(self.file, "r"); local t = textutils.unserialize(f.readAll() or ""); f.close()
    if type(t) == "table" then
      self.cfg.nextNum = type(t.nextNum) == "table" and t.nextNum or {}
      self.cfg.units = type(t.units) == "table" and t.units or {}
      self.cfg.plant = type(t.plant) == "table" and t.plant or {}
    end
  end
  self.stamp = stampOf(self.file)
end

function M:save()
  local f = fs.open(self.file .. ".new", "w"); f.write(textutils.serialize(self.cfg)); f.close()
  if fs.exists(self.file) then fs.delete(self.file) end
  fs.move(self.file .. ".new", self.file)
  self.stamp = stampOf(self.file)
end

-- Picks up hand edits of the config file
function M:reloadIfEdited()
  if stampOf(self.file) ~= self.stamp then self:load(); return true end
  return false
end

-- Discovery ---------------------------------------------------------------
local function classify(name)
  local t = lower(table.concat({ peripheral.getType(name) }, " "))
  if peripheral.getType(name) == REACTOR then return "reactor" end
  if t:find("turbine") then return "turbine" end
  if t:find("energy_storage") then return "storage" end
  -- The cable is shared with Storage and its chests: only ER2 reactor ports count, everything else is ignored.
  -- (Whether the ports show as inventories is not assumed; the type name is what we go by.)
  if t:find("reactor") and (t:find("access") or t:find("port")) and not t:find("computer") then return "port" end
  return nil
end

-- Scan the cable. Returns true if the set of devices changed.
function M:scan()
  local found = { reactor = {}, turbine = {}, storage = {}, port = {} }
  local names = peripheral.getNames()
  table.sort(names)
  for _, name in ipairs(names) do
    local k = classify(name)
    if k then found[k][#found[k] + 1] = name end
  end
  local sig = {}
  for _, k in ipairs({ "reactor", "turbine", "storage", "port" }) do sig[#sig + 1] = k .. ":" .. table.concat(found[k], ",") end
  sig = table.concat(sig, ";")
  local changed = sig ~= self.sig
  self.sig, self.found = sig, found

  -- units: everything known in the config, plus anything new
  local present = {}
  for _, k in ipairs({ "reactor", "turbine", "storage" }) do for _, n in ipairs(found[k]) do present[n] = k end end
  local dirty = false
  local ids = {}
  for id in pairs(present) do ids[#ids + 1] = id end
  table.sort(ids)                                   -- numbers go out in cable-name order, so they're repeatable
  for _, id in ipairs(ids) do
    local k = present[id]
    if not self.cfg.units[id] then
      local num = (self.cfg.nextNum[k] or 0) + 1
      self.cfg.nextNum[k] = num
      self.cfg.units[id] = { kind = k, num = num, label = LABEL[k] .. "-" .. num, mode = "auto", enabled = true }
      self.log(("New %s %s: peripheral %s"):format(k, self.cfg.units[id].label, id))
      dirty = true
    end
  end
  if dirty then self:save() end
  local list = {}
  for id, c in pairs(self.cfg.units) do
    local u = self.byId[id] or { id = id }
    u.kind, u.cfg, u.label, u.plantCfg = c.kind, c, c.label, self.cfg.plant
    u.present = present[id] ~= nil
    if u.present and u.kind == "reactor" then
      if not u.driver then u.driver = drivers.pick(id) end
    else
      u.driver = nil
    end
    self.byId[id] = u
    list[#list + 1] = u
  end
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    return (a.cfg.num or 0) < (b.cfg.num or 0)
  end)
  self.units = list
  self:resolvePorts()
  return changed or dirty
end

-- Ports -------------------------------------------------
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end end

function M:resolvePorts()
  local ports = self.found.port
  local reactors = {}
  for _, u in ipairs(self.units) do if u.kind == "reactor" and u.present then reactors[#reactors + 1] = u end end
  local claimed = {}
  for _, u in ipairs(self.units) do
    if u.cfg.input then claimed[u.cfg.input] = true end
    if u.cfg.output then claimed[u.cfg.output] = true end
  end
  for _, u in ipairs(reactors) do
    local c = u.cfg
    u.input, u.output, u.portNote = c.input, c.output, nil
    if not (c.input and c.output) then
      -- Only one reactor on the cable: its ports are the free ports. Tell input from output by what they hold.
      local free = {}
      for _, n in ipairs(ports) do if not claimed[n] then free[#free + 1] = n end end
      if #reactors == 1 and #free >= 1 and #free <= 2 then
        local fuelPort, wastePort
        for _, n in ipairs(free) do
          local fuel, waste = M.contents(n)
          if fuel and fuel > 0 and not fuelPort then fuelPort = n
          elseif waste and waste > 0 and not wastePort then wastePort = n end
        end
        if not fuelPort and wastePort and #free == 2 then
          for _, n in ipairs(free) do if n ~= wastePort then fuelPort = n end end
        end
        if not wastePort and fuelPort and #free == 2 then
          for _, n in ipairs(free) do if n ~= fuelPort then wastePort = n end end
        end
        local newly = false
        if not c.input and fuelPort then c.input = fuelPort; claimed[fuelPort] = true; u.input = fuelPort; newly = true end
        if not c.output and wastePort then c.output = wastePort; claimed[wastePort] = true; u.output = wastePort; newly = true end
        if newly then
          self.log(("%s ports: input %s, output %s (worked out from what they hold; assign them on the Needs tab to pin them)")
            :format(u.label, tostring(c.input), tostring(c.output)))
          self:save()
        end
      end
      if not (u.input and u.output) then
        u.portNote = (#free == 0 and "no reactor access port found on the cable")
          or (#reactors > 1 and "several reactors: assign its ports on the Needs tab")
          or "can't tell which port is input and which is output: assign them on the Needs tab"
      end
    end
    -- named in the config but not on the cable
    if u.input and not peripheral.isPresent(u.input) then u.inputGone = true else u.inputGone = nil end
    if u.output and not peripheral.isPresent(u.output) then u.outputGone = true else u.outputGone = nil end
  end
end

-- The numbers a unit's settings resolve to (percent in env, fraction here)
-- A setting for a unit: its own override in operator.cfg, else the plant-wide value set from the screen
-- (operator.cfg `plant`), else the default in operator.env. Also says where it came from: "unit", "plant" or "env".
function M.setting(u, key, E, envKey)
  local v = tonumber((u.cfg or {})[key])
  if v then return v, "unit" end
  v = tonumber((u.plantCfg or {})[key])
  if v then return v, "plant" end
  return tonumber(E[envKey]), "env"
end

function M.thresholds(u, E)
  local on = (M.setting(u, "onBelow", E, "ON_BELOW") or 30) / 100
  local off = (M.setting(u, "offAbove", E, "OFF_ABOVE") or 90) / 100
  return on, off
end

return M
