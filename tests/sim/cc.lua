-- sim/cc.lua  --  a small CraftOS world: computers and turtles running the repo's real programs
-- on a virtual clock, with peripherals, wired networks, rednet and a voxel world for turtles.
--
--   local cc = require("sim.cc")
--   local w  = cc.world()
--   local c  = w:computer{ id = 1, label = "Storage" }
--   c:installRole("storage"); c:run("storage")
--   w:run(30)                       -- 30 virtual seconds
--
-- Everything is deterministic: nothing runs unless you call w:run / w:runUntil.
local Term  = require("sim.term")
local Inv   = require("sim.inv")
local Env   = require("sim.env")

local cc = { Term = Term, Inv = Inv }

local World = {}
World.__index = World
local Computer = {}
Computer.__index = Computer
local Net = {}
Net.__index = Net

local SIDES = { "top", "bottom", "left", "right", "front", "back" }
cc.SIDES = SIDES

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[deepcopy(k)] = deepcopy(x) end
  return o
end
cc.deepcopy = deepcopy

---------------------------------------------------------------------------
-- Wired network ("the cable"): named peripherals that any computer with a wired modem on it can see
---------------------------------------------------------------------------
function Net:add(name, dev)
  if self.devices[name] then error("net already has a device called " .. name, 2) end
  self.devices[name] = dev
  self.order[#self.order + 1] = name
  dev.net, dev.netName = self, name
  for _, m in ipairs(self.modems) do m.comp:_queue("peripheral", name) end
  return dev
end
function Net:remove(name)
  local dev = self.devices[name]
  self.devices[name] = nil
  for i, n in ipairs(self.order) do if n == name then table.remove(self.order, i); break end end
  for _, m in ipairs(self.modems) do m.comp:_queue("peripheral_detach", name) end
  return dev
end
function Net:get(name) return self.devices[name] end
function Net:names()
  local t = {}
  for _, n in ipairs(self.order) do t[#t + 1] = n end
  return t
end

---------------------------------------------------------------------------
-- Modems
---------------------------------------------------------------------------
-- cc.wired(net) / cc.wireless() : the modem object attached to a computer side (or a turtle upgrade slot)
local Modem = {}
Modem.__index = Modem
Modem.peripheralMethods = { "isWireless", "open", "close", "isOpen", "closeAll", "transmit", "getNameLocal",
  "getNamesRemote", "isPresentRemote", "getTypeRemote", "callRemote" }
function Modem:isWireless() return not self.wired end
function Modem:open() end
function Modem:close() end
function Modem:isOpen() return true end
function Modem:closeAll() end
function Modem:transmit() end
function Modem:getNameLocal() return self.comp and ("computer_" .. self.comp.id) or nil end
function Modem:getNamesRemote() return self.wired and self.net:names() or {} end
function Modem:isPresentRemote(n) return self.wired and self.net:get(n) ~= nil end
function Modem:getTypeRemote(n)
  local d = self.wired and self.net:get(n)
  if d then return table.unpack(d.types) end
end
function Modem:callRemote(n, method, ...)
  local d = self.wired and self.net:get(n)
  if not d then error("Remote peripheral '" .. tostring(n) .. "' does not exist", 2) end
  return d[method](d, ...)
end
function cc.wired(net) return setmetatable({ types = { "modem" }, wired = true, net = net, isModem = true }, Modem) end
function cc.wireless(opts)
  return setmetatable({ types = { "modem" }, wired = false, ender = opts and opts.ender, isModem = true }, Modem)
end

---------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------
function cc.world(opts)
  opts = opts or {}
  local w = setmetatable({ now = 0, computers = {}, byId = {}, timers = {}, timerSeq = 0, nets = {}, blocks = {},
                           turtles = {}, gpsOn = false, rr = 0, epoch0 = opts.epoch0 or 1792000000 }, World)
  cc.worlds[#cc.worlds + 1] = w
  return w
end
cc.worlds = {}

function World:net(name)
  name = name or ("net" .. (#self.nets + 1))
  local n = self.nets[name]
  if not n then
    n = setmetatable({ name = name, devices = {}, order = {}, modems = {} }, Net)
    self.nets[name] = n
  end
  return n
end

function World:furnace(opts)
  opts = opts or {}
  opts.clock = function() return self.now end
  return Inv.Furnace.new(opts)
end

function World:factory(opts)
  opts = opts or {}
  opts.clock = function() return self.now end
  return require("sim.factory").new(opts)
end

function World:reactor(opts)
  opts = opts or {}
  opts.clock = function() return self.now end
  return require("sim.reactor").new(opts)
end

-- Timers (and one-off world callbacks) live in one list ordered by time.
function World:_addTimer(at, rec)
  self.timerSeq = self.timerSeq + 1
  rec.at, rec.seq = at, self.timerSeq
  local t = self.timers
  local i = #t + 1
  while i > 1 and (t[i - 1].at > at) do i = i - 1 end
  table.insert(t, i, rec)
  return self.timerSeq
end
-- run fn() at virtual time `at` (seconds from the start)
function World:at(at, fn) self:_addTimer(at, { fn = fn }) end
function World:after(dt, fn) self:at(self.now + dt, fn) end

function World:computer(opts)
  opts = opts or {}
  local id = opts.id or #self.computers + 1
  if self.byId[id] then error("computer id " .. id .. " already exists", 2) end
  local c = setmetatable({
    world = self, id = id, label = opts.label, files = {}, dirs = {}, q = {}, sides = {}, openModems = {},
    pos = opts.pos, printLog = {}, alive = false, bootAt = self.now,
  }, Computer)
  c.screen = Term.new(opts.w or (opts.turtle and 39 or 51), opts.h or (opts.turtle and 13 or 19), { colour = opts.colour })
  self.computers[#self.computers + 1] = c
  self.byId[id] = c
  return c
end

-- A turtle: a computer with a body in the voxel world. See sim/turtle.lua for opts.
function World:turtle(opts)
  local c = self:computer({ id = opts.id, label = opts.label, turtle = true, w = opts.w, h = opts.h })
  require("sim.turtle").attach(self, c, opts)
  return c
end

-- Voxel world --------------------------------------------------------------------------------
local function key(x, y, z) return x .. "," .. y .. "," .. z end
-- block: a name, or a table { name=, inv=, drop=, unbreakable= }
function World:setBlock(x, y, z, block, inv)
  if block == nil or block == "air" or block == "minecraft:air" then self.blocks[key(x, y, z)] = nil; return end
  if type(block) == "string" then block = { name = block } end
  if inv then block.inv = inv end
  self.blocks[key(x, y, z)] = block
  return block
end
function World:fill(x1, y1, z1, x2, y2, z2, block)
  for x = math.min(x1, x2), math.max(x1, x2) do
    for y = math.min(y1, y2), math.max(y1, y2) do
      for z = math.min(z1, z2), math.max(z1, z2) do
        self:setBlock(x, y, z, type(block) == "table" and deepcopy(block) or block)
      end
    end
  end
end
function World:getBlock(x, y, z) return self.blocks[key(x, y, z)] end
function World:turtleAt(x, y, z)
  for _, t in ipairs(self.turtles) do if t.x == x and t.y == y and t.z == z then return t end end
end
-- how many blocks called `name` are left inside a box
function World:count(name, x1, y1, z1, x2, y2, z2)
  local n = 0
  for x = math.min(x1, x2), math.max(x1, x2) do
    for y = math.min(y1, y2), math.max(y1, y2) do
      for z = math.min(z1, z2), math.max(z1, z2) do
        local b = self.blocks[key(x, y, z)]
        if b and b.name == name then n = n + 1 end
      end
    end
  end
  return n
end

---------------------------------------------------------------------------
-- Computer: files, peripherals, input
---------------------------------------------------------------------------
function Computer:_queue(...)
  self.q[#self.q + 1] = table.pack(...)
end

local function norm(path)
  local parts = {}
  for seg in tostring(path):gmatch("[^/]+") do
    if seg == ".." then parts[#parts] = nil elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return table.concat(parts, "/")
end
cc.normPath = norm

function Computer:writeFile(path, data)
  path = norm(path)
  local dir = path:match("^(.*)/[^/]*$")
  while dir and dir ~= "" do self.dirs[dir] = true; dir = dir:match("^(.*)/[^/]*$") end
  self.files[path] = data
end
function Computer:readFile(path) return self.files[norm(path)] end
-- Save/load a Lua table the way programs do (textutils.serialize), e.g. their .cfg and .state files.
function Computer:writeTable(path, t) self:writeFile(path, Env.serialize(t)) end
function Computer:readTable(path) local s = self:readFile(path); return s and Env.unserialize(s) end

local function readRepo(rel)
  local f = io.open(cc.ROOT .. "/" .. rel, "rb")
  if not f then error("no such file in the repo: " .. rel, 3) end
  local s = f:read("*a"); f:close()
  return s
end

-- Copy a repo file onto this computer (as dest, or under its own name).
function Computer:install(rel, dest)
  self:writeFile(dest or rel:match("[^/]*$"), readRepo(rel))
end

-- Install what manifest.lua says a role gets: its files (and `once` files) land under their own names.
-- startup.lua/reset.lua are left out (a scenario boots programs itself) unless opts.common is set.
function Computer:installRole(role, opts)
  opts = opts or {}
  local kind = opts.kind
  local manifest = assert(load(readRepo("manifest.lua"), "@manifest.lua", "t", {}))()
  local types = manifest.types
  local r
  for k, ty in pairs(types) do
    if (not kind or kind == k) and ty.roles and ty.roles[role] then r = ty.roles[role]; break end
  end
  if not r then error("no role '" .. role .. "' in manifest.lua", 2) end
  if opts.common then for _, f in ipairs(manifest.common or {}) do self:install(f) end end
  for _, f in ipairs(r.files or {}) do self:install(f) end
  for _, f in ipairs(r.once or {}) do self:install(f) end
  return r
end

-- Peripherals on a side: a Term (monitor), a modem (cc.wired / cc.wireless), an Inv, anything with `types`.
function Computer:attach(side, dev)
  self.sides[side] = dev
  dev.side = side
  if dev.isModem and dev.wired then
    dev.comp = self
    dev.net.modems[#dev.net.modems + 1] = dev
  end
  self:_queue("peripheral", side)
  return dev
end
function Computer:detach(side)
  local dev = self.sides[side]
  self.sides[side] = nil
  if self.openModems then self.openModems[side] = nil end   -- like CC: a removed modem isn't open any more
  if dev and dev.isModem and dev.wired then
    for i, m in ipairs(dev.net.modems) do if m == dev then table.remove(dev.net.modems, i); break end end
  end
  self:_queue("peripheral_detach", side)
end

-- A monitor touching this computer. Returns the Term so a scenario can read it and touch it.
function Computer:monitor(side, w, h)
  local m = Term.new(w or 57, h or 24)
  m.comp = self
  m.types = { "monitor" }
  self:attach(side, m)
  return m
end
function Term:touch(x, y)
  local c = self.comp or (self.net and error("touch the monitor via a computer it is attached to"))
  c:_queue("monitor_touch", self.side or self.netName, x, y)
end

-- Resize a screen as the game does (monitor blocks added or removed; a window resized): the program gets
-- term_resize (its own screen) or monitor_resize (a monitor).
function Term:setSize(w, h)
  self:resize(w, h)
  local c = self.comp
  if c then c:_queue("monitor_resize", self.side or self.netName) end
end
function Computer:resize(w, h)
  self.screen:resize(w, h)
  self:_queue("term_resize")
end

-- Input as if typed at the computer
function Computer:type(text)
  for ch in text:gmatch(".") do self:_queue("char", ch) end
end
function Computer:key(code)
  self:_queue("key", code, false)
  self:_queue("key_up", code)
end
function Computer:click(x, y, button) self:_queue("mouse_click", button or 1, x, y) end
function Computer:scroll(dir, x, y) self:_queue("mouse_scroll", dir, x or 1, y or 1) end
function Computer:queue(...) self:_queue(...) end
function Computer:screenText() return self.screen:text() end

-- Everything print()ed since boot, as one string
function Computer:output() return table.concat(self.printLog, "\n") end

-- peripheral resolution: a side name, or a name on a wired network through a modem on one of the sides
local DX, DZ = { [0] = 0, 1, 0, -1 }, { [0] = -1, 0, 1, 0 }
function Computer:resolve(name)
  local d = self.sides[name]
  if d then return d end
  -- like CC: a turtle sees the inventory in front of, above or below it as a peripheral on that side
  local b = self.body
  if b and (name == "front" or name == "top" or name == "bottom") then
    local x, y, z = b.x, b.y, b.z
    if name == "top" then y = y + 1 elseif name == "bottom" then y = y - 1 else x, z = x + DX[b.facing], z + DZ[b.facing] end
    local blk = self.world:getBlock(x, y, z)
    return blk and blk.inv or nil
  end
  for _, side in ipairs(SIDES) do
    local m = self.sides[side]
    if m and m.isModem and m.wired then
      local r = m.net:get(name)
      if r then return r end
    end
  end
end
function Computer:peripheralNames()
  local out = {}
  for _, side in ipairs(SIDES) do
    if self.sides[side] then out[#out + 1] = side end
  end
  for _, side in ipairs(SIDES) do
    local m = self.sides[side]
    if m and m.isModem and m.wired then
      for _, n in ipairs(m.net:names()) do
        local seen = false
        for _, o in ipairs(out) do if o == n then seen = true end end
        if not seen then out[#out + 1] = n end
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Running programs
---------------------------------------------------------------------------
-- Boot (or reboot): fresh memory, files kept. Runs startup.lua if the computer has one.
function Computer:reboot()
  self:_stop()
  self.q, self.printLog, self.openModems, self.error = {}, {}, {}, nil
  self.bootAt = self.world.now
  self.screen:clear(); self.screen:setCursorPos(1, 1)
  self.screen.fg, self.screen.bg = 1, 32768
  if self.files["startup.lua"] or self.files["startup"] then self:run("startup") end
  return self
end

function Computer:_stop()
  self.alive, self.co, self.filter = false, nil, nil
  self.gen = (self.gen or 0) + 1       -- timers set by the old run are ignored
end

-- Run a shell command line ("storage", "miner arg") as the computer's main program.
function Computer:run(cmd)
  self:_stop()
  self.q, self.error, self.finished = {}, nil, false
  self.env = Env.build(self.world, self)
  local env = self.env
  local words = {}
  for w in cmd:gmatch("%S+") do words[#words + 1] = w end
  self.co = coroutine.create(function()
    local ok, err = xpcall(function() return env.shell.run(table.unpack(words)) end, function(e)
      if type(e) == "table" then return e end
      return debug.traceback(tostring(e), 2)
    end)
    if not ok then error(err, 0) end
  end)
  self.alive, self.fresh = true, true
  return self
end

function World:_resume(c, ...)
  self.current = c
  local ok, res = coroutine.resume(c.co, ...)
  self.current = nil
  if not ok then
    c.alive = false
    if type(res) == "table" and res.sim == "reboot" then
      c.rebootRequested = true
    elseif type(res) == "table" and res.sim == "shutdown" then
      c.shutDown = true
    else
      c.error = tostring(res)
      c.screen:setTextColour(16384)
    end
  elseif coroutine.status(c.co) == "dead" then
    c.alive, c.finished = false, true
  else
    c.filter = res
  end
end

-- Run whoever has an event waiting (round robin). Returns true if anything ran.
function World:_step()
  local n = #self.computers
  for k = 1, n do
    local i = (self.rr + k - 1) % n + 1
    local c = self.computers[i]
    if c.alive then
      if c.fresh then
        c.fresh = false
        self.rr = i
        self:_resume(c)
        return true
      end
      while #c.q > 0 do
        local ev = table.remove(c.q, 1)
        if c.filter == nil or ev[1] == c.filter or ev[1] == "terminate" then
          self.rr = i
          self:_resume(c, table.unpack(ev, 1, ev.n))
          return true
        end
      end
    end
    if c.rebootRequested then c.rebootRequested = false; c:reboot(); return true end
  end
  return false
end

function World:_fire(rec)
  if rec.fn then return rec.fn() end
  if rec.cancelled then return end
  local c = rec.comp
  if c.alive and c.gen == rec.gen then c:_queue("timer", rec.id) end
end

-- Advance virtual time by `seconds`, running everything that wants to run along the way.
function World:run(seconds) return self:runUntil(nil, seconds) end

-- Run until pred() is true (checked after every step) or `max` virtual seconds pass.
-- Returns true if pred became true.
function World:runUntil(pred, max)
  local limit = self.now + (max or 60)
  local guard = 0
  while true do
    if pred and pred() then return true end
    if self:_step() then
      guard = guard + 1
      if guard > 2000000 then error("runaway: 2,000,000 scheduler steps without time passing", 2) end
    else
      local t = self.timers[1]
      if not t or t.at > limit then self.now = limit; break end
      table.remove(self.timers, 1)
      if t.at > self.now then self.now = t.at; guard = 0 end
      self:_fire(t)
    end
  end
  return pred and pred() or false
end

-- Reachability for rednet. Returns the computers that hear `from`'s message on modem `m`.
function World:_hearers(from, m)
  local out = {}
  for _, c in ipairs(self.computers) do
    if c ~= from and c.alive then
      for name, mod in pairs(c.openModems) do
        local dev = c:resolve(name)
        if dev and dev.isModem and mod then
          if m.wired and dev.wired and dev.net == m.net then out[#out + 1] = c; break end
          if (not m.wired) and (not dev.wired) then out[#out + 1] = c; break end
        end
      end
    end
  end
  return out
end

function World:_transmit(from, modem, dest, msg, protocol)
  for _, c in ipairs(self:_hearers(from, modem)) do
    if dest == 65535 or dest == c.id then
      c:_queue("rednet_message", from.id, deepcopy(msg), protocol)
    end
  end
end

-- gps.locate for a computer: its true position when the scenario turned GPS on
function World:gpsFix(c)
  if not self.gpsOn then return nil end
  if c.body then return c.body.x, c.body.y, c.body.z end
  if c.pos then return c.pos[1], c.pos[2], c.pos[3] end
end

cc.Computer, cc.World = Computer, World
return cc
