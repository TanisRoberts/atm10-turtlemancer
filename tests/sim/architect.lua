-- sim/architect.lua  --  an Architect that is already set up (paired as Architect-01, a build loaded, a site set and started),
-- for the scenarios that look at its screens and monitor rather than the setup. The build is tests/data/placement.litematic
-- with its south-west corner at 106 65 210 and the dock at 100 65 200.
local cc = require("sim.cc")
local A = {}

function A.plan()
  local cache = {}
  local env = setmetatable({}, { __index = _G })
  env.require = function(name)
    if cache[name] == nil then
      local f = assert(loadfile(cc.ROOT .. "/shared/" .. name .. ".lua", "t", env))
      cache[name] = f() or true
    end
    return cache[name]
  end
  local f = assert(io.open(cc.ROOT .. "/tests/data/placement.litematic", "rb")); local bytes = f:read("*a"); f:close()
  local P = env.require("plan2")
  local plan = P.fromLitematic(bytes)
  return P.text(plan), plan.info.hash, plan
end

-- c: a computer with the architect role installed; writes its label and state files
function A.prepare(c)
  local text, hash = A.plan()
  c.label = "Architect-01"
  c:writeFile("builds/Placement Test.plan2", text)
  c:writeTable("architect.state", { n = 1, wid = 2, name = "Placement Test", hash = hash, file = "builds/Placement Test.plan2",
    started = true, site = { dx = 100, dy = 65, dz = 200, dh = 1, cx = 106, cy = 65, cz = 210, rot = 0 }, gaps = {}, held = {}, orderSeq = 0 })
  return hash
end

return A
