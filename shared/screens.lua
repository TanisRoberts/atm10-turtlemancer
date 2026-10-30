-- shared/screens.lua  --  which monitor does this computer draw on? (issue #98, docs/systems/screens.md)
--
--   local screens = require("screens")            -- shared files land flat on a device: shared/screens.lua -> screens.lua
--   local s = screens.new({ slots = { { id = "wall", label = "the main wall", required = false, scale = 0.5 } } })
--   local mon, name = s:get("wall")               -- touching monitor first, else the saved pick, else the picker
--   s:daemon()                                    -- (in parallel) answers other computers' claim queries
--   s:handle(ev...)                               -- the same, for a controller with its own event loop
--   s:repick("wall")                              -- forget the saved pick; the next get asks again
--
-- Rules: a monitor touching the computer wins for slot 1 with no prompt and nothing saved. Otherwise the choice
-- is saved in monitors.cfg (one `slot=peripheral_name` per line, `-` = skipped). A saved monitor that is gone
-- or owned by another computer is asked about again. Computers on one cable agree who owns which monitor
-- over the wired modems on CHANNEL (no rednet, no mainframe):
--   { op = "claims?", from = id }                           query: who owns what?
--   { op = "claims", from = id, owned = {names}, numbering = {names} }   answer (also sent when a pick is made)
--   { op = "numbering", from = id, names = {names} }        "I am showing numbers on these"
-- Events sent to the controller: ("screens_changed", slotId) after a monitor_resize or a detach.
local screens = {}
screens.CHANNEL = 4747
screens.CFG = "monitors.cfg"
screens.WAIT = 1            -- seconds to collect answers to a claims query

local SIDES = { "top", "bottom", "left", "right", "front", "back" }
local isSide = {}
for _, n in ipairs(SIDES) do isSide[n] = true end

local okUi, ui = pcall(require, "ui")
local C = colours or colors
local role = (okUi and ui.c) or { bg = C.black, dim = C.lightGrey, fg = C.white, gold = C.yellow }

-- 3x5 digits, one string per row, # = lit
local FONT = {
  ["0"] = { "###", "# #", "# #", "# #", "###" }, ["1"] = { " # ", "## ", " # ", " # ", "###" },
  ["2"] = { "###", "  #", "###", "#  ", "###" }, ["3"] = { "###", "  #", "###", "  #", "###" },
  ["4"] = { "# #", "# #", "###", "  #", "  #" }, ["5"] = { "###", "#  ", "###", "  #", "###" },
  ["6"] = { "###", "#  ", "###", "# #", "###" }, ["7"] = { "###", "  #", "  #", "  #", "  #" },
  ["8"] = { "###", "# #", "###", "# #", "###" }, ["9"] = { "###", "# #", "###", "  #", "###" },
}

local function setOf(list)
  local t = {}
  for _, n in ipairs(list or {}) do t[n] = true end
  return t
end
local function listOf(set)
  local t = {}
  for n in pairs(set) do t[#t + 1] = n end
  table.sort(t)
  return t
end

---------------------------------------------------------------------------------------------------------
-- monitors.cfg
---------------------------------------------------------------------------------------------------------
local function readCfg()
  local t = {}
  if fs.exists(screens.CFG) then
    local f = fs.open(screens.CFG, "r")
    if f then
      for line in (f.readAll() or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_%-]+)%s*=%s*(%S+)")
        if k then t[k] = v end
      end
      f.close()
    end
  end
  return t
end

local function writeCfg(t, order)
  local keys, seen = {}, {}
  for _, k in ipairs(order) do if t[k] and not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
  local rest = {}
  for k in pairs(t) do if not seen[k] then rest[#rest + 1] = k end end
  table.sort(rest)
  for _, k in ipairs(rest) do keys[#keys + 1] = k end
  local f = fs.open(screens.CFG, "w")
  if not f then return end
  for _, k in ipairs(keys) do f.writeLine(k .. "=" .. t[k]) end
  f.close()
end

---------------------------------------------------------------------------------------------------------
-- Object
---------------------------------------------------------------------------------------------------------
local S = {}
S.__index = S

function screens.new(opts)
  opts = opts or {}
  local s = setmetatable({ slots = opts.slots or {}, res = {}, owned = {}, numbering = {}, peers = {}, size = {},
                           skipped = {}, queriedAt = nil }, S)
  s.index = {}
  for i, sl in ipairs(s.slots) do s.index[sl.id] = i end
  s.cfg = readCfg()
  return s
end

function S:slot(id) return self.slots[self.index[id] or error("no screen slot called " .. tostring(id), 3)] end

local function wiredModems()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "modem") then
      local m = peripheral.wrap(n)
      if m and m.isWireless and not m.isWireless() then out[#out + 1] = m end
    end
  end
  return out
end

function S:open()
  for _, m in ipairs(wiredModems()) do pcall(m.open, screens.CHANNEL) end
end

function S:send(msg)
  msg.from = os.getComputerID()
  for _, m in ipairs(wiredModems()) do pcall(m.transmit, screens.CHANNEL, screens.CHANNEL, msg) end
end

function S:state()
  return { op = "claims", owned = listOf(self.owned), numbering = listOf(self.numbering) }
end

-- Everything a peer has told us it owns or is numbering, minus nothing: callers decide what that means.
function S:peerTaken()
  local t = {}
  for _, p in pairs(self.peers) do
    for n in pairs(p.owned) do t[n] = true end
    for n in pairs(p.numbering) do t[n] = true end
  end
  return t
end

-- Names a peer with a LOWER id has claimed (owned or numbering) or higher ids that own: used while numbering.
local function peerWins(self, name)
  for id, p in pairs(self.peers) do
    if p.owned[name] then return true end
    if p.numbering[name] and id < os.getComputerID() then return true end
  end
  return false
end

---------------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------------
-- Feed every event here. Answers claim queries, tracks peers, reports resize/detach of owned monitors.
function S:handle(ev, a, b, c, d)
  if ev == "modem_message" then
    if b ~= screens.CHANNEL or type(d) ~= "table" or type(d.from) ~= "number" or d.from == os.getComputerID() then return end
    local p = self.peers[d.from] or { owned = {}, numbering = {} }
    self.peers[d.from] = p
    if d.op == "claims?" then
      self:send(self:state())
    elseif d.op == "claims" then
      p.owned, p.numbering = setOf(d.owned), setOf(d.numbering)
    elseif d.op == "numbering" then
      p.numbering = setOf(d.names)
      -- someone is numbering a monitor we own: tell them now
      for n in pairs(p.numbering) do
        if self.owned[n] then self:send(self:state()); break end
      end
    end
    if self.onPeer then self.onPeer() end
  elseif ev == "monitor_resize" then
    local slot = self:slotOf(a)
    if slot then
      self:measure(slot)
      os.queueEvent("screens_changed", slot)
    end
  elseif ev == "peripheral_detach" then
    local slot = self:slotOf(a)
    if slot then
      self.res[slot] = nil
      self.owned[a] = nil
      self.size[slot] = nil
      os.queueEvent("screens_changed", slot)
      self:send(self:state())
    end
  end
end

function S:daemon()
  self:open()
  while true do self:handle(os.pullEvent()) end
end

function S:slotOf(name)
  for id, r in pairs(self.res) do
    if r.name == name then return id end
  end
end

function S:measure(id)
  local r = self.res[id]
  if r then
    local w, h = r.mon.getSize()
    self.size[id] = { w = w, h = h }
  end
  return self.size[id]
end

---------------------------------------------------------------------------------------------------------
-- Finding monitors
---------------------------------------------------------------------------------------------------------
local function monitorNames()
  local touch, net = {}, {}
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "monitor") then
      if isSide[n] then touch[#touch + 1] = n else net[#net + 1] = n end
    end
  end
  table.sort(net)
  return touch, net
end

local function sizeOf(name)
  local m = peripheral.wrap(name)
  if not m then return 0, 0 end
  return m.getSize()
end

local function biggestTouching(touch, taken)
  local best, area
  for _, n in ipairs(touch) do
    if not taken[n] then
      local w, h = sizeOf(n)
      if not area or w * h > area then best, area = n, w * h end
    end
  end
  return best
end

-- Ask the cable who owns what, wait WAIT seconds for answers. Other events are held and re-queued by the caller.
function S:query(held)
  self:open()
  self.peers = {}
  self.queriedAt = os.clock()
  if #wiredModems() == 0 then return end
  self:send({ op = "claims?" })
  local timer = os.startTimer(screens.WAIT)
  while true do
    local ev = table.pack(os.pullEvent())
    if ev[1] == "timer" and ev[2] == timer then return end
    if ev[1] == "modem_message" or ev[1] == "monitor_resize" or ev[1] == "peripheral_detach" then
      self:handle(table.unpack(ev, 1, ev.n))
    elseif ev[1] ~= "terminate" then
      held[#held + 1] = ev
    else
      error("Terminated", 0)
    end
  end
end

local function requeue(held)
  for i = 1, math.min(#held, 200) do os.queueEvent(table.unpack(held[i], 1, held[i].n)) end
end

---------------------------------------------------------------------------------------------------------
-- The picker
---------------------------------------------------------------------------------------------------------
local function cut(s, w) if #s > w then return s:sub(1, math.max(0, w)) end return s end

local function palette(mon)
  if okUi and ui.palette and mon.isColour and mon.isColour() and mon.setPaletteColour then
    for _, p in ipairs(ui.palette) do pcall(mon.setPaletteColour, C[p[1]], p[2]) end
  end
end

local function blank(mon)
  mon.setBackgroundColour(role.bg)
  mon.clear()
  mon.setCursorPos(1, 1)
end

-- Big block digits centred on a monitor, one line under it. Pixels are drawn with the background colour.
function screens.drawNumber(mon, n, caption)
  palette(mon)
  pcall(mon.setTextScale, 0.5)
  blank(mon)
  local w, h = mon.getSize()
  local text = tostring(n)
  local d = #text
  -- a pixel is about as tall as it is wide when it is 3 columns by 2 rows; shrink until the number fits
  local ky, kx = 1, 2
  for m = 1, 12 do
    local tx, ty = math.floor(1.5 * m + 0.5), m
    if (4 * d - 1) * tx <= w - 2 and 5 * ty + 2 <= h then kx, ky = tx, ty end
  end
  if (4 * d - 1) * kx > w then kx = 1 end
  local totalW, totalH = (4 * d - 1) * kx, 5 * ky + 2
  local x0 = math.max(1, math.floor((w - totalW) / 2) + 1)
  local y0 = math.max(1, math.floor((h - totalH) / 2) + 1)
  for row = 1, 5 do
    for dy = 0, ky - 1 do
      mon.setCursorPos(1, y0 + (row - 1) * ky + dy)
      for i = 1, d do
        local glyph = FONT[text:sub(i, i)][row]
        for col = 1, 3 do
          local lit = glyph:sub(col, col) == "#"
          mon.setCursorPos(x0 + ((i - 1) * 4 + col - 1) * kx, y0 + (row - 1) * ky + dy)
          mon.setBackgroundColour(lit and role.gold or role.bg)
          mon.write(string.rep(" ", kx))
        end
      end
    end
  end
  mon.setBackgroundColour(role.bg)
  mon.setTextColour(role.dim)
  local line = cut(caption, w)
  mon.setCursorPos(math.max(1, math.floor((w - #line) / 2) + 1), y0 + 5 * ky + 1)
  mon.write(line)
end

-- the computer's own screen during a pick
local function drawComputer(slot, cands, typed)
  local t = term.native and term.native() or term
  local w, h = t.getSize()
  t.setBackgroundColour(role.bg)
  t.clear()
  t.setTextColour(role.fg)
  local head, row = "Pick " .. slot.label .. ": tap a monitor or type its number", 1
  while #head > 0 and row < 4 do                  -- word-wrap on a narrow screen
    local n = #head
    if n > w then
      n = w
      while n > 1 and head:sub(n + 1, n + 1) ~= " " do n = n - 1 end
      if n == 1 then n = w end
    end
    t.setCursorPos(1, row)
    t.write(head:sub(1, n))
    head, row = head:sub(n + 1):gsub("^ ", ""), row + 1
  end
  for i, c in ipairs(cands) do
    if row + i > h - 3 then break end
    local mw, mh = sizeOf(c)
    t.setTextColour(role.dim)
    t.setCursorPos(1, row + i)
    t.write(cut(("%d %s (%dx%d)"):format(i, c, mw, mh), w))
  end
  t.setTextColour(role.fg)
  t.setCursorPos(1, h - 1)
  t.write(cut("> " .. typed, w))
  if not slot.required then
    t.setTextColour(role.dim)
    t.setCursorPos(1, h)
    t.write(cut("Enter to skip", w))
  end
  t.setCursorPos(math.min(w, 3 + #typed), h - 1)
end

local function candidates(self, taken)
  local _, net = monitorNames()
  local out = {}
  for _, n in ipairs(net) do
    if not taken[n] and not self.owned[n] and not peerWins(self, n) then out[#out + 1] = n end
  end
  return out
end

-- Show numbers and wait for a tap or a typed number. Returns a monitor name, "-" (skipped) or nil (nothing to pick).
function S:pick(slot, taken, held)
  local typed, shown = "", {}
  local function refresh()
    local cands = candidates(self, taken)
    local changed = #cands ~= #shown
    for i, n in ipairs(cands) do if shown[i] ~= n then changed = true end end
    local keep = setOf(cands)
    if changed then
      for _, n in ipairs(shown) do      -- a monitor a peer won is theirs to draw on
        if not keep[n] and not peerWins(self, n) then local m = peripheral.wrap(n); if m then pcall(blank, m) end end
      end
      for i, n in ipairs(cands) do
        local m = peripheral.wrap(n)
        if m then screens.drawNumber(m, i, "Tap to pick " .. slot.label) end
      end
      shown = cands
      self.numbering = keep
      self:send({ op = "numbering", names = cands })
    end
    -- a peer that lost the tie may have drawn over our number just now: draw it again
    for i, n in ipairs(shown) do
      for id, p in pairs(self.peers) do
        if id > os.getComputerID() and p.numbering[n] then
          local m = peripheral.wrap(n)
          if m then screens.drawNumber(m, i, "Tap to pick " .. slot.label) end
        end
      end
    end
    drawComputer(slot, shown, typed)
  end
  local result
  self.onPeer = refresh
  local ping = os.startTimer(1)
  refresh()
  while result == nil do
    local ev = table.pack(os.pullEvent())
    local e = ev[1]
    if e == "monitor_touch" then
      for _, n in ipairs(shown) do if n == ev[2] then result = n end end
    elseif e == "char" then
      if ev[2]:match("%d") then typed = typed .. ev[2]; drawComputer(slot, shown, typed) end
    elseif e == "key" then
      if ev[2] == keys.backspace then typed = typed:sub(1, -2); drawComputer(slot, shown, typed)
      elseif ev[2] == keys.enter or ev[2] == keys.numPadEnter then
        local n = tonumber(typed)
        if n and shown[n] then result = shown[n]
        elseif typed == "" and not slot.required then result = "-"
        else typed = ""; drawComputer(slot, shown, typed) end
      end
    elseif e == "timer" and ev[2] == ping then
      self:send({ op = "numbering", names = shown })     -- keep saying so; a lost message is not a lost monitor
      ping = os.startTimer(1)
      refresh()
    elseif e == "modem_message" or e == "monitor_resize" or e == "peripheral_detach" or e == "peripheral" then
      self:handle(table.unpack(ev, 1, ev.n))
      refresh()
    elseif e == "terminate" then
      error("Terminated", 0)
    elseif e ~= "key_up" and e ~= "mouse_click" and e ~= "mouse_up" and e ~= "mouse_drag" and e ~= "mouse_scroll" then
      held[#held + 1] = ev
    end
    if result == nil and #shown == 0 then result = false end    -- a peer won every monitor we were showing
  end
  self.onPeer = nil
  os.cancelTimer(ping)
  -- picked: every other candidate is blanked so other computers can claim it
  for _, n in ipairs(shown) do
    if n ~= result then local m = peripheral.wrap(n); if m then pcall(blank, m) end end
  end
  self.numbering = {}
  self:send(self:state())
  local t = term.native and term.native() or term
  t.setBackgroundColour(role.bg); t.clear(); t.setCursorPos(1, 1)
  return result or nil
end

---------------------------------------------------------------------------------------------------------
-- get / repick
---------------------------------------------------------------------------------------------------------
local function takenNames(self)
  local t = {}
  for _, r in pairs(self.res) do t[r.name] = true end
  return t
end

local function adopt(self, id, name, own)
  local slot = self:slot(id)
  local mon = peripheral.wrap(name)
  if not mon then return nil end
  palette(mon)
  pcall(mon.setTextScale, slot.scale or 0.5)
  mon.setBackgroundColour(role.bg)
  mon.clear()
  mon.setCursorPos(1, 1)
  self.res[id] = { mon = mon, name = name, touching = not own }
  if own then self.owned[name] = id end
  self:measure(id)
  return mon
end

function S:cfgSave(id, name)
  self.cfg[id] = name
  local order = {}
  for _, sl in ipairs(self.slots) do order[#order + 1] = sl.id end
  writeCfg(self.cfg, order)
end

-- The monitor for a slot: returns the wrapped monitor and its peripheral name, or nil.
function S:get(id)
  local slot = self:slot(id)
  local r = self.res[id]
  if r then
    if peripheral.isPresent(r.name) then return r.mon, r.name end
    self.res[id] = nil; self.owned[r.name] = nil
  end
  if self.skipped[id] then return nil end
  local taken = takenNames(self)
  local touch, net = monitorNames()
  -- rule 1: slot 1 uses the biggest touching monitor
  if self.index[id] == 1 then
    local best = biggestTouching(touch, taken)
    if best then return adopt(self, id, best, false), best end
  end
  local held = {}
  local function done(mon, name) requeue(held); return mon, name end
  -- rule 2: the saved pick, if it is still there and nobody else owns it
  local saved = self.cfg[id]
  if saved == "-" then self.skipped[id] = true; return nil end
  if #net == 0 and not saved then
    if slot.required then self:waitForMonitor(id, held) else return nil end
  end
  if not self.queriedAt or os.clock() - self.queriedAt > 3 then self:query(held) end
  if saved and peripheral.hasType(saved, "monitor") and not taken[saved] and not self.owned[saved]
     and not self:peerTaken()[saved] then
    return done(adopt(self, id, saved, true), saved)
  end
  -- rule 3: ask
  while true do
    self:query(held)
    local cands = candidates(self, taken)
    if #cands == 0 and not slot.required then
      self.numbering = {}
      return done(nil, nil)
    end
    if #cands > 0 then
      local pick = self:pick(slot, taken, held)
      if pick == "-" then
        self.skipped[id] = true
        self:cfgSave(id, "-")
        return done(nil, nil)
      end
      if pick then
        self:cfgSave(id, pick)
        local mon = adopt(self, id, pick, true)
        self:send(self:state())
        return done(mon, pick)
      end
      if not slot.required then return done(nil, nil) end
    end
    -- required and everything is taken: wait for something to change
    self:waitForMonitor(id, held)
  end
end

-- Required slot with nothing to offer: say so on the computer and wait until a monitor appears.
function S:waitForMonitor(id, held)
  local slot = self:slot(id)
  local t = term.native and term.native() or term
  t.setBackgroundColour(role.bg); t.clear(); t.setTextColour(role.fg); t.setCursorPos(1, 1)
  local w = t.getSize()
  t.write(cut("Waiting for a monitor for " .. slot.label, w))
  while true do
    local ev = table.pack(os.pullEvent())
    if ev[1] == "peripheral" or ev[1] == "peripheral_detach" then
      local _, net = monitorNames()
      if #net > 0 then break end
    elseif ev[1] == "terminate" then
      error("Terminated", 0)
    elseif ev[1] ~= "key_up" then
      held[#held + 1] = ev
    end
  end
  t.setBackgroundColour(role.bg); t.clear(); t.setCursorPos(1, 1)
end

-- Forget the saved pick for a slot (and let go of its monitor); the next get asks again.
function S:repick(id)
  self:slot(id)
  local r = self.res[id]
  if r then
    self.owned[r.name] = nil
    self.res[id] = nil
    self:send(self:state())
  end
  self.skipped[id] = nil
  self.cfg[id] = nil
  local order = {}
  for _, sl in ipairs(self.slots) do order[#order + 1] = sl.id end
  writeCfg(self.cfg, order)
end

return screens
