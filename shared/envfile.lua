-- envfile.lua  --  an ".env-style" settings file: made on first run, missing keys appended, existing lines never
-- overwritten, edits picked up live.  Same rules as butler.env / plastic.env.
--   local env = require("envfile").new("operator.env", "Operator settings.", { {"KEY", default, "what it does"}, ... })
--   env.load()  -- once;  env.refresh() -- cheap, call often;  env.v.KEY is the value (number if the default is a number)
local M = {}

local function stampOf(path)
  if not fs.exists(path) or not fs.attributes then return nil end
  local ok, a = pcall(fs.attributes, path)
  return ok and a and (tostring(a.modified) .. ":" .. tostring(a.size)) or nil
end

function M.new(file, title, defaults)
  local self = { v = {}, stamp = nil }
  function self.load()
    local vals = {}
    if fs.exists(file) then
      local f = fs.open(file, "r")
      while true do
        local line = f.readLine()
        if not line then break end
        local k, val = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then vals[k:upper()] = val end
      end
      f.close()
    end
    local missing = {}
    for _, d in ipairs(defaults) do
      if vals[d[1]] == nil then missing[#missing + 1] = d; vals[d[1]] = tostring(d[2]) end
    end
    if #missing > 0 then
      local new = not fs.exists(file)
      local f = fs.open(file, new and "w" or "a")
      if new then f.writeLine("# " .. title .. " Edit and save: picked up within a few seconds.") end
      for _, d in ipairs(missing) do
        f.writeLine(""); f.writeLine("# " .. d[3]); f.writeLine(d[1] .. "=" .. tostring(d[2]))
      end
      f.close()
    end
    for _, d in ipairs(defaults) do
      local val = vals[d[1]]
      if type(d[2]) == "number" then self.v[d[1]] = tonumber(val) or d[2] else self.v[d[1]] = val end
    end
    self.stamp = stampOf(file)
  end
  function self.refresh()
    if stampOf(file) ~= self.stamp then self.load(); return true end
    return false
  end
  return self
end

return M
