-- Typed "/" commands, once, for every screen (docs/systems/ui.md).
--
--   local slash = require("slash")
--   local cmds = slash.new({ say = ui.say })
--   cmds:add{ name = "goto", args = "x z", min = 2, max = 2, help = "send the turtle to x z",
--             run = function(a) local x, z = a:xz(1); if not x then return false, z end; ... return true, "On my way" end }
--   cmds:exec("/goto 10 -5")                -- parses, runs, shows the result with `say`
--   v:search(field, { commands = cmds:commands() })   -- the kit's command bar (computer terminal)
--
-- A line may start with "/" or not; the name is case-insensitive; words split on spaces, "double quotes" keep
-- spaces. A handler gets (a, ctx): a.words, a.raw (everything after the name), a.n, and the readers a:int(i),
-- a:num(i), a:xz(i) which return the value or nil and a message. It returns ok, text, tone:
--   true, "text"       shown (tone "good" unless given)
--   false, "text"      shown as an error with the usage line under it
--   false              just the usage line
-- Wrong word count (min/max) never reaches the handler: the usage line is shown.
local slash = {}

-- Split a typed line into name and words. Returns nil for a blank line.
function slash.parse(line)
  line = tostring(line or ""):gsub("^%s+", ""):gsub("^/+", ""):gsub("%s+$", "")
  if line == "" then return nil end
  local name, rest = line:match("^(%S+)%s*(.*)$")
  local words, i, n = {}, 1, #rest
  while i <= n do
    local c = rest:sub(i, i)
    if c == " " or c == "\t" then
      i = i + 1
    elseif c == '"' then
      local close = rest:find('"', i + 1, true)
      words[#words + 1] = rest:sub(i + 1, (close or n + 1) - 1)
      i = (close or n) + 1
    else
      local s, e = rest:find("^%S+", i)
      words[#words + 1] = rest:sub(s, e)
      i = e + 1
    end
  end
  return name:lower(), words, rest
end

local Args = {}
Args.__index = Args

-- Whole numbers only (a block coordinate, a count).
function Args:int(i)
  local w = self.words[i]
  local n = w and tonumber(w)
  if n and n == math.floor(n) and not w:find("[eExXnN]") then return n end
  return nil, w and ("'" .. w .. "' is not a whole number") or "a number is missing"
end
function Args:num(i)
  local w = self.words[i]
  local n = w and tonumber(w)
  if n then return n end
  return nil, w and ("'" .. w .. "' is not a number") or "a number is missing"
end
-- A position as "x,z" or "x z", starting at word i. Returns x, z, and the index of the next word.
function Args:xz(i)
  local w = self.words[i]
  if w and w:find(",", 1, true) then
    local a, b = w:match("^(%-?%d+),(%-?%d+)$")
    if not a then return nil, "'" .. w .. "' is not x,z" end
    return tonumber(a), tonumber(b), i + 1
  end
  local x, ex = self:int(i)
  if not x then return nil, ex end
  local z, ez = self:int(i + 1)
  if not z then return nil, ez end
  return x, z, i + 2
end
function Args:is(i, word) return self.words[i] ~= nil and self.words[i]:lower() == word end

local Set = {}
Set.__index = Set

-- o.say(text, tone): where results go (default: ui.say if the kit is loaded, else print).
-- o.help = false leaves out the built-in /help.
function slash.new(o)
  o = o or {}
  local s = setmetatable({ list = {}, byName = {}, say = o.say }, Set)
  if o.help ~= false then
    s:add({ name = "help", help = "list the commands", args = "[command]", max = 1,
            run = function(a)
              if a.words[1] then
                local c = s.byName[a.words[1]:lower():gsub("^/", "")]
                if not c then return false, "No command " .. a.words[1] end
                return true, s:usage(c) .. ": " .. c.help, "plain"
              end
              return true, table.concat(s:helpLines(), "  "), "plain"
            end })
  end
  return s
end

function Set:add(c)
  assert(type(c.name) == "string" and c.name:match("^[%w_%-]+$"), "slash: bad command name")
  assert(type(c.run) == "function", "slash: " .. c.name .. " has no run")
  c.name = c.name:lower()
  c.help = c.help or ""
  if self.byName[c.name] then   -- a screen can replace the built-in /help
    for i, old in ipairs(self.list) do if old.name == c.name then table.remove(self.list, i); break end end
  end
  self.byName[c.name] = c
  self.list[#self.list + 1] = c
  return self
end

function Set:usage(c)
  return "/" .. c.name .. (c.args and (" " .. c.args) or "")
end

-- One line per command: "/goto x z  send the turtle to x z".
function Set:helpLines()
  local out = {}
  for _, c in ipairs(self.list) do out[#out + 1] = self:usage(c) end
  return out
end

function Set:out(text, tone)
  if self.say then self.say(text, tone)
  else
    local ok, ui = pcall(require, "ui")
    if ok and ui.say then ui.say(text, tone) else print(text) end
  end
end

-- Run a typed line. Returns ok, text, tone without showing anything.
function Set:run(line, ctx)
  local name, words, raw = slash.parse(line)
  if not name then return false, "Type a command: " .. table.concat(self:helpLines(), "  "), "warn" end
  local c = self.byName[name]
  if not c then
    return false, "Unknown command /" .. name .. ". " .. table.concat(self:helpLines(), "  "), "warn"
  end
  local n = #words
  if n < (c.min or 0) or (c.max and n > c.max) then
    return false, "Usage: " .. self:usage(c) .. "  (" .. c.help .. ")", "warn"
  end
  local a = setmetatable({ words = words, raw = raw, n = n, name = name }, Args)
  local ran, ok, text, tone = pcall(c.run, a, ctx)
  if not ran then return false, "/" .. name .. " failed: " .. tostring(ok), "bad" end
  if ok == false then
    if text then return false, text .. "  (" .. self:usage(c) .. ")", tone or "warn" end
    return false, "Usage: " .. self:usage(c) .. "  (" .. c.help .. ")", "warn"
  end
  return true, text, tone or "good"
end

-- Run a typed line and show the result. Returns ok.
function Set:exec(line, ctx)
  local ok, text, tone = self:run(line, ctx)
  if text and text ~= "" then self:out(text, tone) end
  return ok
end

-- The list the kit's command bar takes: v:search(f, { commands = cmds:commands() }).
function Set:commands()
  local out = {}
  for _, c in ipairs(self.list) do
    out[#out + 1] = { name = c.name, help = (c.args and (c.args .. "  ") or "") .. c.help,
                      fn = function(arg) self:exec(c.name .. " " .. (arg or "")) end }
  end
  return out
end

return slash
