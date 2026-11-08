-- weaver_numbers.lua  --  the mainframe's Weaver number list (docs/systems/weaver.md section 5). Runs from mainframe.lua.
--
-- weavers.reg holds every number ever handed out: { next = 3, list = { [2] = { turtle = 214, arch = 9, site = {...} } } }.
-- Numbers only go up and are never reused. First number ever: 01 (the island pair).
-- tanis-weaver, all broadcast or sent to us:
--   number_req {turtle}   from a fresh Architect  -> number {turtle, n}  (the same number if asked again for that turtle)
--   relink {n}            from a replacement Architect: remember its computer ID, answer site {n, site, build, hash}
--   site_set {n, site, build, hash}   an Architect that started a build keeps the site here, so a replacement can find it

local PROTOCOL = "tanis-weaver"
local FILE = "weavers.reg"

local reg = { next = 1, list = {} }
if fs.exists(FILE) then
  local f = fs.open(FILE, "r"); local t = textutils.unserialize(f.readAll() or ""); f.close()
  if type(t) == "table" and type(t.list) == "table" then reg = t; reg.next = tonumber(reg.next) or 1 end
end
local function save()
  local f = fs.open(FILE .. ".new", "w"); f.write(textutils.serialize(reg)); f.close()
  if fs.exists(FILE) then fs.delete(FILE) end
  fs.move(FILE .. ".new", FILE)
end

peripheral.find("modem", function(name) pcall(rednet.open, name); return false end)

local function numberFor(turtle)
  for n, e in pairs(reg.list) do if e.turtle == turtle then return n end end
  local n = reg.next
  reg.next = n + 1
  reg.list[n] = { turtle = turtle }
  save()
  return n
end

while true do
  local from, msg = rednet.receive(PROTOCOL)
  if type(msg) == "table" then
    if msg.type == "number_req" and tonumber(msg.turtle) then
      local n = numberFor(tonumber(msg.turtle))
      reg.list[n].arch = from; save()
      rednet.send(from, { type = "number", turtle = msg.turtle, n = n }, PROTOCOL)
    elseif msg.type == "relink" and tonumber(msg.n) and reg.list[msg.n] then
      local e = reg.list[msg.n]
      e.arch = from; save()
      rednet.send(from, { type = "site", n = msg.n, site = e.site, build = e.build, hash = e.hash }, PROTOCOL)
    elseif msg.type == "site_set" and tonumber(msg.n) and reg.list[msg.n] and type(msg.site) == "table" then
      local e = reg.list[msg.n]
      e.site, e.build, e.hash = msg.site, msg.build, msg.hash
      save()
    end
  end
end
