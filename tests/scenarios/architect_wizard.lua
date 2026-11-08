-- Architect v2 (#88): a fresh Architect pairs with a fresh Weaver (both get 01 from the mainframe), a .litematic is dropped on
-- it, the site is typed in, and the real Weaver builds it so the world matches the file. A second fresh Architect then
-- re-links to that Weaver by typing its number, is given the same file again and carries on.
local cc = require("sim.cc")
local T  = require("sim.test")
local W  = require("sim.weaver")

local function slurp(n)
  local f = assert(io.open(cc.ROOT .. "/tests/data/" .. n, "rb")); local s = f:read("*a"); f:close(); return s
end
local function loader()
  local cache = {}
  local env = setmetatable({}, { __index = _G })
  local function req(name)
    if cache[name] == nil then
      local f = assert(loadfile(cc.ROOT .. "/shared/" .. name .. ".lua", "t", env))
      cache[name] = f() or true
    end
    return cache[name]
  end
  env.require = req
  return req
end

local STORAGE = [[
  rednet.open("top")
  local P = "tanis-weaver"
  local CH = "enderstorage:ender_chest_0"
  local chest, stock = peripheral.wrap(CH), peripheral.wrap("minecraft:barrel_0")
  local replies = {}
  local function totals()
    local have = {}
    for _, it in pairs(stock.list()) do have[it.name] = (have[it.name] or 0) + it.count end
    return have
  end
  local function announce()
    while true do rednet.broadcast({ type = "storage", items = totals() }, "tanis-base"); sleep(5) end
  end
  local function serve()
    while true do
      local id, m = rednet.receive(P)
      if type(m) == "table" and m.type == "supply" then
        local key = m.n .. ":" .. m.seq
        if replies[key] then rednet.broadcast(replies[key], P)
        else
          for slot in pairs(chest.list()) do stock.pullItems(CH, slot) end        -- the clear
          local have = totals()
          local want, sent, missing = {}, {}, {}
          for name, n in pairs(m.items) do want[name] = n end
          if (m.fuel or 0) > 0 then want["minecraft:lava_bucket"] = math.ceil(m.fuel / 1000) end
          for name, n in pairs(want) do
            local g = math.min(n, have[name] or 0)
            if g > 0 then sent[name] = g end
            if g < n then missing[name] = n - g end
          end
          replies[key] = { type = "supplied", n = m.n, seq = m.seq, sent = sent, missing = missing }
          rednet.broadcast(replies[key], P)
          for name, g in pairs(sent) do
            while g > 0 do
              for slot, it in pairs(stock.list()) do
                if it.name == name and g > 0 then g = g - stock.pushItems(CH, slot, g); sleep(2) end
              end
            end
          end
        end
      end
    end
  end
  parallel.waitForAny(announce, serve)
]]

local NAMES = { [0] = "north", "east", "south", "west" }

-- the expected world for a corner at (cx, cy, cz) (south-west, bottom) and a turn, from the file's own block states
local function expected(req, bytes, rot, cx, cy, cz)
  local lit = req("litematic")
  local f = lit.read(bytes)
  local t = lit.trim(f)
  local steps = math.floor(rot / 90) % 4
  local FIDX = { north = 0, east = 1, south = 2, west = 3 }
  local exp, minx, maxz = {}, 1e9, -1e9
  local cells = {}
  for y = 0, t.size.y - 1 do for z = 0, t.size.z - 1 do for x = 0, t.size.x - 1 do
    local i = t.get(x, y, z)
    if i and not t.isAir(i) then
      local rx, rz = x, z
      if steps == 1 then rx, rz = -z, x elseif steps == 2 then rx, rz = -x, -z elseif steps == 3 then rx, rz = z, -x end
      minx, maxz = math.min(minx, rx), math.max(maxz, rz)
      cells[#cells + 1] = { x, y, z, rx, rz, i }
    end
  end end end
  for _, c in ipairs(cells) do
    local e = f.palette[c[6]]
    local name = lit.rename(e.name)
    local want = { name = name }
    exp[(cx + c[4] - minx) .. "," .. (cy + c[2]) .. "," .. (cz + c[5] - maxz)] = want
  end
  return exp, t
end

LATE = { ["minecraft:oak_log"] = true, ["minecraft:hay_block"] = true }     -- storage gets these only later: gaps
local function setup(plan)
  local site = W.site{ code = { "red", "blue", "white" }, label = "Weaver-tmp", fuel = 20000, radius = 24 }
  local w = site.w
  site:home(0)
  local stock = site.net:add("minecraft:barrel_0", cc.Inv.new{ size = 160, types = { "minecraft:barrel", "inventory" } })
  for name in pairs(plan.info.items) do
    if not LATE[name] then stock:give(name, 200) end            -- (the 54 slots hold about 25 kinds this way)
  end
  stock:give("minecraft:lava_bucket", 4)
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(site.net)); st:attach("top", cc.wireless{ ender = true })
  st:writeFile("s.lua", STORAGE); st:run("s")
  local mf = w:computer{ id = 3, label = "Mainframe" }
  mf:attach("top", cc.wireless{ ender = true })
  mf:install("computer/mainframe/weaver_numbers.lua", "weaver_numbers.lua"); mf:run("weaver_numbers")
  local t = site.turtle
  t.label = nil
  t:installRole("weaver")
  t:writeTable("weaver.cfg", { dh = 0 })
  t:writeFile("startup.lua", 'shell.run("weaver")\n')
  t:reboot()
  return site, w, t, st, mf, stock
end

local function architect(w, id)
  local a = w:computer{ id = id }
  a:attach("top", cc.wireless{ ender = true })
  a:installRole("architect")
  a:run("architect")
  return a
end

-- tap the row of the first screen line holding `text`, at the column where it starts
local function tapText(w, a, text, bottom)
  local scr = a.screen
  for y = (bottom and scr.h or 1), (bottom and 1 or scr.h), (bottom and -1 or 1) do
    local x = scr:line(y):find(text, 1, true)
    if x then a:click(x, y); w:run(0.5); return end
  end
  error("nothing on screen says " .. text .. ":\n" .. scr:text())
end
local function key(w, a, code) a:key(code); w:run(0.4) end
local function typeText(w, a, s) a:type(s); w:run(0.3) end

PLAN_FILE = "placement.litematic"
local function shot(a, title) if os.getenv("ARCH_DUMP") then print("---- " .. title); print(a.screen:text()) end end
local function A(c) return c.G.ARCHITECT or {} end
local FIELDS = { 0, 65, 0, 0, 65, 0 }       -- dock x y z, corner x y z (standing on the ground at y 64)
local function enterSite(w, a, cx, cz)
  local vals = { 0, 65, 0, cx, 65, cz }
  key(w, a, 258)
  for i, v in ipairs(vals) do
    typeText(w, a, tostring(v))
    key(w, a, 258)
    if i == 3 then key(w, a, 258) end            -- the heading switch sits between the two triples
  end
end

-- pair a fresh Architect with the fresh Weaver, drop the file, type the site, start the build
local function bringUp(w, a, t, bytes)
  w:run(3)
  T.contains(a.screen, "Which Weaver does this computer run?")
  shot(a, "step 1")
  tapText(w, a, "A new Weaver")
  w:run(4)
  shot(a, "step 1 new")
  T.contains(a.screen, "Turtle #7")
  tapText(w, a, "Turtle #7")
  w:runUntil(function() return A(a).S and A(a).S.n end, 30)
  w:run(2)
  T.eq(A(a).S.n, 1, "the mainframe hands out 01")
  T.eq(t.label, "Weaver-01")
  T.eq(a.label, "Architect-01")
  T.contains(a.screen, "Weaver-01")
  shot(a, "paired")
  tapText(w, a, "Next")
  shot(a, "step 2")
  T.contains(a.screen, "Drag a .litematic file onto this")
  a:drop("Placement.litematic", bytes)
  w:run(2)
  T.contains(a.screen, "Most used")
  T.contains(a.screen, "Placing")
  shot(a, "step 2 summary")
  tapText(w, a, "Next")
  T.contains(a.screen, "Read F3")
  enterSite(w, a, 6, 10)
  T.contains(a.screen, "wide E-W")
  shot(a, "step 3")
  tapText(w, a, "Next")
  T.contains(a.screen, "SW corner")
  w:run(5)
  shot(a, "step 4")
  tapText(w, a, "Start build")
  w:run(60)
  shot(a, "status")
  a:type("/"); w:run(1); shot(a, "slash"); a:key(256); w:run(0.5)
  for _, tab in ipairs({ "Map", "Side", "Bill", "Log" }) do tapText(w, a, tab, true); shot(a, tab) end
  tapText(w, a, "Status", true)
  T.contains(a.screen, "Status")
end

local function finished(a)
  local st = (A(a).R or {}).status
  return st and st.state == "done" and st.gaps == 0 and #A(a).S.gaps == 0
end

T.test("architect: pairs, takes a dropped build, the Weaver builds it and fills the gaps when storage has the blocks", function()
  local req = loader()
  local bytes = slurp(PLAN_FILE)
  local plan = req("plan2").fromLitematic(bytes)
  local site, w, t, st, mf, stock = setup(plan)
  w:run(5)
  local a = architect(w, 2)
  bringUp(w, a, t, bytes)
  local exp = expected(req, bytes, 0, 6, 65, 10)
  w:runUntil(function() local s = (A(a).R or {}).status; return s and s.state == "done" end, 20000)
  T.truthy(#A(a).S.gaps > 0, "storage lacked logs and hay: gaps")
  T.contains(a.screen, "gaps")
  stock:give("minecraft:oak_log", 64); stock:give("minecraft:hay_block", 64)         -- storage has them now
  w:runUntil(function() return finished(a) end, 2000)
  T.truthy(finished(a), "the gaps were filled")
  local ok, bad, total = W.diff(w, exp, { max = 10 })
  if not ok then error(total .. " cells differ:\n  " .. table.concat(bad, "\n  ")) end
  T.eq(mf:readTable("weavers.reg").next, 2, "one number handed out")
end)

T.test("architect: a second fresh Architect re-links by number mid-build, gets the file again and carries on", function()
  local req = loader()
  local bytes = slurp(PLAN_FILE)
  local plan = req("plan2").fromLitematic(bytes)
  LATE = {}                                         -- storage has everything this time
  local site, w, t, st, mf, stock = setup(plan)
  w:run(5)
  local a = architect(w, 2)
  bringUp(w, a, t, bytes)
  w:runUntil(function() local s = A(a).R.status; return s and (s.layer or 0) >= 2 end, 4000)
  a:detach("top")                                   -- the first Architect is lost
  a.alive = false
  local b = architect(w, 4)
  w:run(3)
  T.contains(b.screen, "Which Weaver does this computer run?")
  tapText(w, b, "An existing Weaver")
  w:run(1)
  typeText(w, b, "1")
  key(w, b, 257)
  w:run(6)
  T.contains(b.screen, "Weaver-01 answered")
  T.contains(b.screen, "Building")
  T.contains(b.screen, "Drag")
  b:drop("Other.litematic", slurp("mini.litematic"))
  w:run(2)
  T.contains(b.screen, "That is not Placement Test")
  b:drop("Placement.litematic", bytes)
  w:run(2)
  T.contains(b.screen, "Build file matches")
  tapText(w, b, "Next")
  w:run(2)
  T.eq(b.label, "Architect-01")
  T.contains(b.screen, "Status")
  w:runUntil(function() local s = A(b).R.status; return s and s.state == "done" end, 20000)
  T.truthy(A(b).R.status.state == "done", "the Weaver finished with the second Architect")
  local exp = expected(req, bytes, 0, 6, 65, 10)
  w:runUntil(function() return finished(b) end, 2000)
  local ok, bad, total = W.diff(w, exp, { max = 10 })
  if not ok then error(total .. " cells differ:\n  " .. table.concat(bad, "\n  ")) end
end)

T.test("architect: a reboot mid-build comes back on Status and the build carries on", function()
  local req = loader()
  local bytes = slurp(PLAN_FILE)
  local plan = req("plan2").fromLitematic(bytes)
  LATE = {}
  local site, w, t, st, mf, stock = setup(plan)
  w:run(5)
  local a = architect(w, 2)
  bringUp(w, a, t, bytes)
  w:runUntil(function() local s = A(a).R.status; return s and (s.layer or 0) >= 2 end, 4000)
  a:reboot()
  w:run(8)
  T.contains(a.screen, "Placement Test")
  T.contains(a.screen, "Layer")
  w:run(3000)
  T.contains(a.screen, "finished")
  local ok, bad, total = W.diff(w, (expected(req, bytes, 0, 6, 65, 10)), { max = 10 })
  if not ok then error(total .. " cells differ:\n  " .. table.concat(bad, "\n  ")) end
end)

T.test("architect: a turned build lands turned: the same file at 90 degrees comes out as the file says", function()
  local req = loader()
  local bytes = slurp(PLAN_FILE)
  local plan = req("plan2").fromLitematic(bytes)
  LATE = {}
  local site, w, t, st, mf, stock = setup(plan)
  w:run(5)
  local a = architect(w, 2)
  w:run(3)
  -- write the state a finished wizard would leave (a paired Architect, a build, a site turned 90) and start it
  tapText(w, a, "A new Weaver"); w:run(4); tapText(w, a, "Turtle #7")
  w:runUntil(function() return A(a).S and A(a).S.n end, 30); w:run(2)
  tapText(w, a, "Next"); a:drop("Placement.litematic", bytes); w:run(2); tapText(w, a, "Next")
  enterSite(w, a, 6, 10)
  tapText(w, a, "90", true)
  tapText(w, a, "Next"); w:run(5); tapText(w, a, "Start build")
  w:runUntil(function() local s = (A(a).R or {}).status; return s and s.state == "done" end, 20000)
  w:runUntil(function() return finished(a) end, 20000)
  local ok, bad, total = W.diff(w, (expected(req, bytes, 90, 6, 65, 10)), { max = 10 })
  if not ok then error(total .. " cells differ:\n  " .. table.concat(bad, "\n  ")) end
end)

T.test("architect (#138): Test marks the 4 bottom corners of the turned footprint, Clear removes them, the build then runs", function()
  local req = loader()
  local bytes = slurp(PLAN_FILE)
  local plan = req("plan2").fromLitematic(bytes)
  LATE = {}
  local site, w, t, st, mf, stock = setup(plan)
  stock:give("minecraft:cobblestone", 16)                    -- he carries nothing yet: he fetches cobblestone for the markers
  w:run(5)
  local a = architect(w, 2)
  w:run(3)
  tapText(w, a, "A new Weaver"); w:run(4); tapText(w, a, "Turtle #7")
  w:runUntil(function() return A(a).S and A(a).S.n end, 30); w:run(2)
  tapText(w, a, "Next"); a:drop("Placement.litematic", bytes); w:run(2); tapText(w, a, "Next")
  enterSite(w, a, 6, 10)
  tapText(w, a, "90", true)
  local sz = plan.info.size
  local ew, ns = sz.z, sz.x                                  -- turned 90: the sides swap
  local y = 66                                               -- on top of the bottom-layer cell (y 65)
  local corners = { { 6, 10 }, { 6 + ew - 1, 10 }, { 6, 10 - ns + 1 }, { 6 + ew - 1, 10 - ns + 1 } }
  local function markers()
    local n = 0
    for x = -2, 40 do for z = -30, 30 do
      local b = w:getBlock(x, y, z)
      if b then n = n + 1 end
    end end
    return n
  end
  tapText(w, a, "Test")
  w:runUntil(function() local s = (A(a).R or {}).status; return s and (s.marks or 0) == 4 end, 3000)
  T.eq(markers(), 4, "exactly 4 markers")
  for _, c in ipairs(corners) do T.truthy(w:getBlock(c[1], y, c[2]), "marker at " .. c[1] .. "," .. c[2]) end
  w:run(10)
  T.contains(a.screen, "markers out, type clear")
  tapText(w, a, "Clear")
  w:runUntil(function() local s = (A(a).R or {}).status; return s and (s.marks or 0) == 0 and s.x == 0 and s.z == 0 end, 3000)
  T.eq(markers(), 0, "markers cleared")
  tapText(w, a, "Next"); w:run(5); tapText(w, a, "Start build")
  w:runUntil(function() local s = (A(a).R or {}).status; return s and s.state == "done" end, 20000)
  w:runUntil(function() return finished(a) end, 20000)
  local ok, bad, total = W.diff(w, (expected(req, bytes, 90, 6, 65, 10)), { max = 10 })
  if not ok then error(total .. " cells differ:\n  " .. table.concat(bad, "\n  ")) end
end)
