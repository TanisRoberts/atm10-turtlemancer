-- Smelter dashboard motion (docs/design/ui-kit.md 9.5): a cooking tile gets the smelting glyph on the shared beat,
-- the flame row is gone, ANIM comes from smelter.env, and ANIM=off keeps the dashboard still.
local cc = require("sim.cc")
local T = require("sim.test")

local function setup(env)
  local w = cc.world()
  local net = w:net()
  local inv = {}
  for i = 0, 3 do inv[i] = net:add("minecraft:barrel_" .. i, cc.Inv.new{ size = 27, types = { "minecraft:barrel", "inventory" } }) end
  for i = 0, 2 do net:add("minecraft:furnace_" .. i, w:furnace()) end
  local st = w:computer{ id = 1, label = "Storage" }
  st:attach("back", cc.wired(net)); st:installRole("storage")
  st:writeTable("storage.cfg", { inputs = { "minecraft:barrel_0" }, output = "minecraft:barrel_1" })
  local sm = w:computer{ id = 2, label = "Smelter" }
  sm:attach("back", cc.wired(net)); sm:installRole("smelter")
  sm:writeFile("smelt.txt", "iron all\n")
  if env then sm:writeFile("smelter.env", env) end
  local mon = sm:monitor("top", 57, 24)
  inv[2]:give("minecraft:raw_iron", 192); inv[2]:give("minecraft:coal", 64)
  st:run("storage"); sm:run("smelter")
  return w, sm, mon
end
local FLAMES = { ["\30"] = true, ["^"] = true, ["'"] = true }
local function flames(mon, rows)
  local n, at = 0, {}
  for y = 1, 24 do
    for x = 1, 57 do
      local ch = mon.ch[y][x]
      if FLAMES[ch] then n = n + 1; at[#at + 1] = { x, y } end
    end
  end
  return n, at
end

T.test("smelter motion: ANIM is read from smelter.env (missing key appended), tiles show one glyph each", function()
  local w, sm, mon = setup()
  w:run(40)
  T.running(sm)
  T.truthy(sm:readFile("smelter.env"):find("ANIM=full", 1, true), "ANIM=full appended to smelter.env")
  local n = flames(mon)
  T.truthy(n >= 1, "a cooking furnace shows its glyph")
  -- no furnace has more than its one glyph: no second flame on line 3
  local _, at = flames(mon)
  local rows = {}
  for _, p in ipairs(at) do rows[p[2]] = (rows[p[2]] or 0) + 1 end
  for y, k in pairs(rows) do T.truthy(k <= 3, "row " .. y .. " has at most one glyph per tile") end
end)

-- The glyph cells of the first snapshot: do they keep their character over the next two seconds?
local function glyphsHold(w, mon)
  local _, at = flames(mon)
  local first = {}
  for i, p in ipairs(at) do first[i] = mon.ch[p[2]][p[1]] end
  local changed = false
  for _ = 1, 4 do
    w:run(0.5)
    for i, p in ipairs(at) do if mon.ch[p[2]][p[1]] ~= first[i] then changed = true end end
  end
  return #at, changed
end

T.test("smelter motion: cooking glyphs step on the beat; ANIM=off keeps them still", function()
  local w, sm, mon = setup()
  w:run(40)
  local n, changed = glyphsHold(w, mon)
  T.truthy(n >= 1 and changed, "the glyph cells change between beats")
  local w2, sm2, mon2 = setup("ANIM=off\n")
  w2:run(40)
  T.truthy(sm2:readFile("smelter.env"):find("ANIM=off", 1, true), "an existing line is kept")
  local n2, changed2 = glyphsHold(w2, mon2)
  T.truthy(n2 >= 1, "still cooking")
  T.eq(changed2, false, "ANIM=off: the glyph cells never change")
end)
