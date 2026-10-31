-- The simulator's program environments match CraftOS (tests/sim/env.lua): `require` and `shell` exist only in a
-- program the shell runs and in the modules it require()s; a dofile()d file runs in _G and sees neither, nor the
-- program's own globals. The old sim gave dofile() files `require`, which hid Storage's boot crash
-- ("storage_screens.lua:7: attempt to call global 'require'"). tests/run.py's dofile check catches it statically too.
local cc = require("sim.cc")
local T  = require("sim.test")

local function run(files)
  local world = cc.world()
  local c = world:computer{ id = 1 }
  for name, src in pairs(files) do c:writeFile(name, src) end
  c:run("main")
  world:run(1)
  return c
end

T.test("sim env: a dofile()d file has no require, no shell and not the program's globals; _G is shared", function()
  local c = run({
    ["main.lua"] = 'mine = 1; _G.shared = 2; R = dofile("part.lua"); M = require("mod")',
    ["part.lua"] = 'return { req = type(require), sh = type(shell), mine = mine, shared = shared }',
    ["mod.lua"]  = 'return { req = type(require), sh = type(shell), mine = mine }',
  })
  T.eq(c.error, nil)
  T.eq(c.G.R.req, "nil", "no require in a dofile()d file")
  T.eq(c.G.R.sh, "nil", "no shell in a dofile()d file")
  T.eq(c.G.R.mine, nil, "the program's own globals are not in _G")
  T.eq(c.G.R.shared, 2, "_G.x is")
  T.eq(c.G.M.req, "function", "a require()d module has require")
  T.eq(c.G.M.sh, "table", "and shell")
  T.eq(c.G.M.mine, 1, "and sees the program's globals")
end)

T.test("sim env: calling require from a dofile()d file crashes like it does in game", function()
  local c = run({
    ["main.lua"] = 'dofile("part.lua")',
    ["part.lua"] = 'local ui = require("ui")',
  })
  T.contains(tostring(c.error), "attempt to call global 'require'")
  c.error = nil                                  -- the crash is the point of this test
end)
