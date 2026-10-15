-- sim/env.lua  --  the global environment a CraftOS program sees: os, fs, term, peripheral, rednet,
-- parallel, textutils, keys, colors, shell, read, print ... all bound to one simulated computer.
local Term = require("sim.term")
local Env = {}

local function pack(...) return { n = select("#", ...), ... } end

Env.colors = { white = 1, orange = 2, magenta = 4, lightBlue = 8, yellow = 16, lime = 32, pink = 64, gray = 128,
  lightGray = 256, cyan = 512, purple = 1024, blue = 2048, brown = 4096, green = 8192, red = 16384, black = 32768 }
Env.colors.grey, Env.colors.lightGrey = Env.colors.gray, Env.colors.lightGray
function Env.colors.toBlit(c) local n = 0; while c > 1 do c = c / 2; n = n + 1 end; return ("%x"):format(n) end
function Env.colors.fromBlit(ch) return 2 ^ tonumber(ch, 16) end
function Env.colors.packRGB(r, g, b) return math.floor(r * 255) * 65536 + math.floor(g * 255) * 256 + math.floor(b * 255) end
function Env.colors.combine(...) local n = 0; for _, c in ipairs({ ... }) do n = bit32.bor(n, c) end return n end

-- GLFW key codes, as CC:Tweaked 1.9x uses
Env.keys = { space = 32, apostrophe = 39, comma = 44, minus = 45, period = 46, slash = 47,
  zero = 48, one = 49, two = 50, three = 51, four = 52, five = 53, six = 54, seven = 55, eight = 56, nine = 57,
  semicolon = 59, equals = 61, leftBracket = 91, backslash = 92, rightBracket = 93, grave = 96,
  enter = 257, tab = 258, backspace = 259, insert = 260, delete = 261, right = 262, left = 263, down = 264, up = 265,
  pageUp = 266, pageDown = 267, home = 268, ["end"] = 269, capsLock = 280, scrollLock = 281, numLock = 282,
  f1 = 290, f2 = 291, f3 = 292, f4 = 293, f5 = 294, f6 = 295, f7 = 296, f8 = 297, f9 = 298, f10 = 299, f11 = 300, f12 = 301,
  numPad0 = 320, numPad1 = 321, numPad2 = 322, numPad3 = 323, numPad4 = 324, numPad5 = 325, numPad6 = 326,
  numPad7 = 327, numPad8 = 328, numPad9 = 329, numPadDecimal = 330, numPadDivide = 331, numPadMultiply = 332,
  numPadSubtract = 333, numPadAdd = 334, numPadEnter = 335, leftShift = 340, leftCtrl = 341, leftAlt = 342,
  rightShift = 344, rightCtrl = 345, rightAlt = 346 }
for i = 0, 25 do Env.keys[string.char(97 + i)] = 65 + i end
Env.keys.getName = function(code)
  for n, c in pairs(Env.keys) do if c == code and type(n) == "string" then return n end end
end

---------------------------------------------------------------------------
-- textutils
---------------------------------------------------------------------------
local function serialize(v, seen)
  local t = type(v)
  if t == "table" then
    seen = seen or {}
    if seen[v] then error("Cannot serialize table with repeated entries", 0) end
    seen[v] = true
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = serialize(v[i], seen) end
    local keys = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local ks
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then ks = k else ks = "[" .. serialize(k, seen) .. "]" end
      parts[#parts + 1] = ks .. "=" .. serialize(v[k], seen)
    end
    seen[v] = nil
    return "{" .. table.concat(parts, ",") .. "}"
  elseif t == "string" then return ("%q"):format(v)
  elseif t == "number" then
    if v ~= v then return "0/0" elseif v == math.huge then return "1e9999" elseif v == -math.huge then return "-1e9999" end
    if v == math.floor(v) and math.abs(v) < 1e15 then return ("%d"):format(v) end
    return ("%.14g"):format(v)
  elseif t == "boolean" or t == "nil" then return tostring(v)
  end
  error("Cannot serialize type " .. t, 0)
end

local function unserialize(s)
  if type(s) ~= "string" then return nil end
  local f = load("return " .. s, "unserialize", "t", {})
  if not f then return nil end
  local ok, v = pcall(f)
  if ok then return v end
end

local function formatTime(t, twentyFour)
  local h = math.floor(t)
  local m = math.floor((t - h) * 60)
  if twentyFour then return ("%d:%02d"):format(h, m) end
  local suffix = h >= 12 and "PM" or "AM"
  h = h % 12
  if h == 0 then h = 12 end
  return ("%d:%02d %s"):format(h, m, suffix)
end

Env.serialize, Env.unserialize = serialize, unserialize

---------------------------------------------------------------------------
-- build
---------------------------------------------------------------------------
function Env.build(world, c)
  local env = {}
  for _, n in ipairs({ "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget",
                       "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "xpcall", "string", "table",
                       "math", "coroutine", "bit32" }) do
    env[n] = _G[n]
  end
  env._G, env._VERSION, env._HOST = env, "Lua 5.1", "ComputerCraft 1.115.0 (Minecraft 1.21.1)"
  env.unpack = table.unpack
  env.loadstring = function(s, name) return load(s, name, "t", env) end
  env.load = function(chunk, name, mode, e) return load(chunk, name, mode or "t", e or env) end
  env.colors, env.colours, env.keys = Env.colors, Env.colors, Env.keys

  local screen = c.screen
  local term = Term.api(screen)
  env.term = term

  ------------------------------------------------------------------ os
  local os = {}
  env.os = os
  local gen = c.gen
  function os.clock() return world.now - c.bootAt end
  function os.getComputerID() return c.id end
  os.computerID = os.getComputerID
  function os.getComputerLabel() return c.label end
  os.computerLabel = os.getComputerLabel
  function os.setComputerLabel(l) c.label = l end
  function os.queueEvent(name, ...) c:_queue(name, ...) end
  function os.startTimer(t)
    local rec = { comp = c, gen = c.gen }
    rec.id = world:_addTimer(world.now + math.max(t, 0.05), rec)
    return rec.id
  end
  function os.cancelTimer(id)
    for _, rec in ipairs(world.timers) do if rec.id == id and rec.comp == c then rec.cancelled = true end end
  end
  function os.time(kind)
    if kind == "utc" or kind == "local" then return (world.epoch0 + world.now) % 86400 / 3600 end
    return (6 + world.now / 50) % 24
  end
  function os.day() return math.floor((6 + world.now / 50) / 24) + 1 end
  function os.epoch(kind)
    if kind == "ingame" then return math.floor(world.now / 1200 * 86400000) end
    return math.floor((world.epoch0 + world.now) * 1000)
  end
  os.version = function() return "CraftOS 1.9" end
  local function pullEventRaw(filter) return coroutine.yield(filter) end
  local function pullEvent(filter)
    local ev = pack(coroutine.yield(filter))
    if ev[1] == "terminate" then error("Terminated", 0) end
    return table.unpack(ev, 1, ev.n)
  end
  os.pullEventRaw, os.pullEvent = pullEventRaw, pullEvent
  function os.sleep(t)
    local id = os.startTimer(t)
    repeat local _, p = pullEvent("timer") until p == id
  end
  env.sleep = os.sleep
  local function never() while true do coroutine.yield("sim_never") end end
  function os.reboot() c.rebootRequested = true; never() end
  function os.shutdown() c.shutDown = true; c.alive = false; never() end

  ------------------------------------------------------------------ fs
  local norm = require("sim.cc").normPath
  local fs = {}
  env.fs = fs
  local function isDir(p) p = norm(p); return p == "" or c.dirs[p] == true end
  function fs.exists(p) p = norm(p); return c.files[p] ~= nil or isDir(p) end
  function fs.isDir(p) return isDir(p) end
  function fs.isReadOnly() return false end
  function fs.getName(p) return norm(p):match("[^/]*$") end
  function fs.getDir(p) return norm(p):match("^(.*)/[^/]*$") or "" end
  function fs.getDrive() return "hdd" end
  function fs.getFreeSpace() return 1e9 end
  function fs.getCapacity() return 1e9 end
  function fs.combine(a, ...) local p = a; for _, b in ipairs({ ... }) do p = p .. "/" .. b end return norm(p) end
  function fs.getSize(p)
    local d = c.files[norm(p)]
    if not d then error("No such file", 2) end
    return #d
  end
  function fs.makeDir(p)
    p = norm(p)
    while p ~= "" do c.dirs[p] = true; p = p:match("^(.*)/[^/]*$") or "" end
  end
  function fs.list(p)
    p = norm(p)
    if not isDir(p) then error("/" .. p .. ": Not a directory", 2) end
    local prefix = p == "" and "" or (p .. "/")
    local seen, out = {}, {}
    local function add(path)
      if path:sub(1, #prefix) == prefix then
        local name = path:sub(#prefix + 1):match("^[^/]+")
        if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
      end
    end
    for f in pairs(c.files) do add(f) end
    for d in pairs(c.dirs) do add(d) end
    table.sort(out)
    return out
  end
  function fs.delete(p)
    p = norm(p)
    c.files[p] = nil
    if c.dirs[p] then
      c.dirs[p] = nil
      for f in pairs(c.files) do if f:sub(1, #p + 1) == p .. "/" then c.files[f] = nil end end
      for d in pairs(c.dirs) do if d:sub(1, #p + 1) == p .. "/" then c.dirs[d] = nil end end
    end
  end
  function fs.move(a, b)
    a, b = norm(a), norm(b)
    if c.files[a] == nil then error("No such file", 2) end
    if fs.exists(b) then error("File exists", 2) end
    c:writeFile(b, c.files[a]); c.files[a] = nil
  end
  function fs.copy(a, b)
    a, b = norm(a), norm(b)
    if c.files[a] == nil then error("No such file", 2) end
    if fs.exists(b) then error("File exists", 2) end
    c:writeFile(b, c.files[a])
  end
  function fs.find(pattern)
    local lua = "^" .. norm(pattern):gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0"):gsub("%*", "[^/]*"):gsub("%?", "[^/]") .. "$"
    local out = {}
    for f in pairs(c.files) do if f:match(lua) then out[#out + 1] = f end end
    table.sort(out)
    return out
  end
  function fs.open(path, mode)
    path = norm(path)
    mode = mode or "r"
    local m, bin = mode:sub(1, 1), mode:find("b", 1, true) ~= nil
    if m == "r" then
      local data = c.files[path]
      if not data then return nil, "/" .. path .. ": No such file" end
      local pos, h = 1, {}
      function h.readAll()
        if pos > #data then return (#data == 0 and pos == 1) and "" or nil end
        local s = data:sub(pos); pos = #data + 1; return s
      end
      function h.readLine(trailing)
        if pos > #data then return nil end
        local nl = data:find("\n", pos, true)
        local line = data:sub(pos, nl and nl - 1 or #data)
        pos = nl and nl + 1 or #data + 1
        line = line:gsub("\r$", "")
        if trailing and nl then line = line .. "\n" end
        return line
      end
      function h.read(n)
        if pos > #data then return nil end
        if bin and n == nil then local b = data:byte(pos); pos = pos + 1; return b end
        n = n or 1
        local s = data:sub(pos, pos + n - 1); pos = pos + #s; return s
      end
      function h.lines() return function() return h.readLine() end end
      function h.seek(whence, off)
        whence, off = whence or "cur", off or 0
        if whence == "set" then pos = off + 1 elseif whence == "cur" then pos = pos + off else pos = #data + off + 1 end
        return pos - 1
      end
      function h.close() end
      return h
    elseif m == "w" or m == "a" then
      if isDir(path) then return nil, "/" .. path .. ": Cannot write to directory" end
      local data = (m == "a" and c.files[path]) or ""
      c:writeFile(path, data)
      local h = {}
      function h.write(s) data = data .. tostring(s); c.files[path] = data end
      function h.writeLine(s) h.write(tostring(s) .. "\n") end
      function h.flush() end
      function h.close() end
      return h
    end
    error("Unsupported mode", 2)
  end

  ------------------------------------------------------------------ print / read
  local function cur() return term._cur() end
  local function newline()
    local t = cur()
    local _, h = t:getSize()
    local _, y = t:getCursorPos()
    if y >= h then t:scroll(1); t:setCursorPos(1, h) else t:setCursorPos(1, y + 1) end
  end
  local function writeText(s)
    local t = cur()
    local w = t:getSize()
    local first = true
    for seg in (s .. "\n"):gmatch("(.-)\n") do
      if not first then newline() end
      first = false
      while #seg > 0 do
        local x = t:getCursorPos()
        local room = w - x + 1
        if room <= 0 then newline(); x = 1; room = w end
        t:write(seg:sub(1, room))
        seg = seg:sub(room + 1)
        if #seg > 0 then newline() end
      end
    end
  end
  function env.write(s) writeText(tostring(s)) end
  function env.print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = table.concat(parts, " ")
    c.printLog[#c.printLog + 1] = line
    writeText(line); newline()
  end
  function env.printError(...)
    local t = cur()
    local old = t:getTextColour()
    t:setTextColour(16384)
    env.print(...)
    t:setTextColour(old)
  end
  function env.read(replace, history, complete, default)
    local t = cur()
    local x0, y = t:getCursorPos()
    local w = t:getSize()
    local text = default or ""
    local function redraw()
      t:setCursorPos(x0, y)
      local shown = replace and string.rep(replace, #text) or text
      t:write((shown .. string.rep(" ", math.max(0, w - x0 + 1 - #shown))):sub(1, w - x0 + 1))
      t:setCursorPos(math.min(x0 + #text, w), y)
    end
    redraw()
    while true do
      local ev, a = pullEvent()
      if ev == "char" then text = text .. a; redraw()
      elseif ev == "key" then
        if a == Env.keys.enter then break
        elseif a == Env.keys.backspace then text = text:sub(1, -2); redraw() end
      elseif ev == "paste" then text = text .. a; redraw()
      end
    end
    newline()
    return text
  end

  ------------------------------------------------------------------ parallel
  local parallel = {}
  env.parallel = parallel
  local function runUntilLimit(routines, limit)
    local count = #routines
    local living = count
    local filters, ev = {}, { n = 0 }
    while true do
      for n = 1, count do
        local r = routines[n]
        if r and (filters[r] == nil or filters[r] == ev[1] or ev[1] == "terminate") then
          local ok, param = coroutine.resume(r, table.unpack(ev, 1, ev.n))
          if not ok then
            if type(param) == "table" then error(param, 0) end
            error(debug.traceback(r, tostring(param)), 0)
          end
          filters[r] = param
          if coroutine.status(r) == "dead" then
            routines[n] = nil; living = living - 1
            if living <= limit then return n end
          end
        end
      end
      for n = 1, count do
        local r = routines[n]
        if r and coroutine.status(r) == "dead" then
          routines[n] = nil; living = living - 1
          if living <= limit then return n end
        end
      end
      ev = pack(pullEventRaw())
    end
  end
  local function create(...)
    local fns, cos = { ... }, {}
    for i, f in ipairs(fns) do cos[i] = coroutine.create(f) end
    return cos
  end
  function parallel.waitForAny(...) return runUntilLimit(create(...), select("#", ...) - 1) end
  function parallel.waitForAll(...) return runUntilLimit(create(...), 0) end

  ------------------------------------------------------------------ peripheral
  local peripheral = {}
  env.peripheral = peripheral
  local function methodsOf(dev)
    local set = {}
    for _, m in ipairs(dev.peripheralMethods or {}) do set[m] = true end
    return set
  end
  function peripheral.getNames() return c:peripheralNames() end
  function peripheral.isPresent(n) return c:resolve(n) ~= nil end
  function peripheral.getType(n)
    local d = c:resolve(n)
    if d then return table.unpack(d.types) end
  end
  function peripheral.hasType(n, ty)
    local d = c:resolve(n)
    if not d then return nil end
    for _, t in ipairs(d.types) do if t == ty then return true end end
    return false
  end
  function peripheral.getMethods(n)
    local d = c:resolve(n)
    if not d then return nil end
    return { table.unpack(d.peripheralMethods or {}) }
  end
  function peripheral.call(n, method, ...)
    local d = c:resolve(n)
    if not d then error("No peripheral attached", 2) end
    if not methodsOf(d)[method] then error("No such method " .. tostring(method), 2) end
    return d[method](d, ...)
  end
  function peripheral.wrap(n)
    local d = c:resolve(n)
    if not d then return nil end
    local w = {}
    for _, m in ipairs(d.peripheralMethods or {}) do w[m] = function(...) return d[m](d, ...) end end
    return w
  end
  local wrapNames = setmetatable({}, { __mode = "k" })
  local origWrap = peripheral.wrap
  function peripheral.wrap(n)
    local w = origWrap(n)
    if w then wrapNames[w] = n end
    return w
  end
  function peripheral.getName(w) return wrapNames[w] end
  function peripheral.find(ty, filter)
    local out = {}
    for _, n in ipairs(c:peripheralNames()) do
      if peripheral.hasType(n, ty) then
        local w = peripheral.wrap(n)
        if not filter or filter(n, w) then out[#out + 1] = w end
      end
    end
    return table.unpack(out)
  end

  ------------------------------------------------------------------ rednet
  local rednet = { CHANNEL_BROADCAST = 65535, CHANNEL_REPEAT = 65533 }
  env.rednet = rednet
  function rednet.open(n)
    local d = c:resolve(n)
    if not (d and d.isModem) then error("No such modem: " .. tostring(n), 2) end
    c.openModems[n] = true
  end
  function rednet.close(n)
    if n then c.openModems[n] = nil else c.openModems = {} end
  end
  function rednet.isOpen(n)
    if n then return c.openModems[n] == true end
    return next(c.openModems) ~= nil
  end
  function rednet.send(id, msg, protocol)
    local sent, delivered = false, {}
    for n in pairs(c.openModems) do
      local m = c:resolve(n)
      if m then
        sent = true
        for _, r in ipairs(world:_hearers(c, m)) do
          if (id == 65535 or id == r.id) and not delivered[r] then
            delivered[r] = true
            r:_queue("rednet_message", c.id, require("sim.cc").deepcopy(msg), protocol)
          end
        end
      end
    end
    if id == c.id then c:_queue("rednet_message", c.id, require("sim.cc").deepcopy(msg), protocol); sent = true end
    return sent
  end
  function rednet.broadcast(msg, protocol) return rednet.send(65535, msg, protocol) end
  function rednet.receive(protocolFilter, timeout)
    if type(protocolFilter) == "number" and timeout == nil then protocolFilter, timeout = nil, protocolFilter end
    local timer = timeout and os.startTimer(timeout)
    while true do
      local e, p1, p2, p3 = pullEvent()
      if e == "rednet_message" then
        if protocolFilter == nil or p3 == protocolFilter then return p1, p2, p3 end
      elseif e == "timer" and p1 == timer then
        return nil
      end
    end
  end
  world.hosts = world.hosts or {}
  function rednet.host(protocol, name)
    world.hosts[protocol] = world.hosts[protocol] or {}
    world.hosts[protocol][name] = c.id
  end
  function rednet.unhost(protocol)
    for _, h in pairs(world.hosts) do for n, id in pairs(h) do if id == c.id then h[n] = nil end end end
  end
  function rednet.lookup(protocol, name)
    local h = world.hosts[protocol] or {}
    if name then return h[name] end
    local ids = {}
    for _, id in pairs(h) do ids[#ids + 1] = id end
    return table.unpack(ids)
  end

  ------------------------------------------------------------------ gps, redstone, settings, textutils
  env.gps = { CHANNEL_GPS = 65534, locate = function() return world:gpsFix(c) end }
  local rs = { getSides = function() return { "top", "bottom", "left", "right", "front", "back" } end,
               getInput = function() return false end, setOutput = function() end, getOutput = function() return false end,
               getAnalogInput = function() return 0 end, setAnalogOutput = function() end }
  env.rs, env.redstone = rs, rs
  local settings = {}
  env.settings = { get = function(k, d) if settings[k] == nil then return d end return settings[k] end,
                   set = function(k, v) settings[k] = v end, save = function() end, load = function() return false end }
  env.textutils = { serialize = serialize, serialise = serialize, unserialize = unserialize, unserialise = unserialize,
                    formatTime = formatTime }

  ------------------------------------------------------------------ shell, require
  local running = {}
  local shell = {}
  env.shell = shell
  local function findProgram(name)
    name = norm(name)
    for _, cand in ipairs({ name, name .. ".lua" }) do
      if c.files[cand] then return cand, c.files[cand] end
    end
  end
  function shell.run(name, ...)
    local path, src = findProgram(name)
    if not path then env.printError("No such program: " .. tostring(name)); return false end
    local fn, err = load(src, "@" .. path, "t", env)
    if not fn then env.printError(err); return false end
    running[#running + 1] = path
    local res = pack(fn(...))
    running[#running] = nil
    return true
  end
  function shell.getRunningProgram() return running[#running] end
  function shell.resolve(p) return norm(p) end
  function shell.dir() return "" end
  function shell.exit() end
  function env.dofile(p)
    local path, src = findProgram(p)
    if not path then error("File not found: " .. tostring(p), 2) end
    return assert(load(src, "@" .. path, "t", env))()
  end
  local loaded = {}
  env.package = { loaded = loaded, path = "?;?.lua" }
  function env.require(name)
    if loaded[name] ~= nil then return loaded[name] end
    local path, src = findProgram((name:gsub("%.", "/")))
    if not path then error("module '" .. name .. "' not found", 2) end
    local fn = assert(load(src, "@" .. path, "t", env))
    local r = fn(name, path)
    if r == nil then r = true end
    loaded[name] = r
    return r
  end

  if c.body then env.turtle = require("sim.turtle").api(world, c) end
  return env
end

return Env
