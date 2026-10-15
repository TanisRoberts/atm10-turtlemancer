-- sim/test.lua  --  scenario registry and assertions.
--
--   local T = require("sim.test")
--   T.test("storage sorts the input chest", function() ... end)
--
-- A test fails on any assertion, any Lua error, or if a simulated computer died with an error.
local cc = require("sim.cc")

local T = { tests = {} }

function T.test(name, fn) T.tests[#T.tests + 1] = { name = name, fn = fn } end

local function show(v)
  if type(v) == "string" then return ("%q"):format(v) end
  return tostring(v)
end

function T.eq(got, want, msg)
  if got ~= want then
    error((msg and (msg .. ": ") or "") .. "expected " .. show(want) .. ", got " .. show(got), 2)
  end
end
function T.truthy(v, msg) if not v then error(msg or "expected a true value", 2) end end
function T.falsy(v, msg) if v then error(msg or ("expected false, got " .. show(v)), 2) end end
-- `haystack` may be a string or a Term (searched as screen text)
function T.contains(haystack, needle, msg)
  local text = type(haystack) == "table" and haystack:text() or haystack
  if not text:find(needle, 1, true) then
    error((msg and (msg .. ": ") or "") .. "expected to find " .. show(needle) .. " in:\n" .. text, 2)
  end
end
function T.absent(haystack, needle, msg)
  local text = type(haystack) == "table" and haystack:text() or haystack
  if text:find(needle, 1, true) then
    error((msg and (msg .. ": ") or "") .. "did not expect " .. show(needle) .. " in:\n" .. text, 2)
  end
end
-- a computer is still running its program (it didn't crash or return)
function T.running(c)
  if c.error then error("computer " .. tostring(c.label or c.id) .. " crashed:\n" .. c.error, 2) end
  if not c.alive then error("computer " .. tostring(c.label or c.id) .. " is not running", 2) end
end
-- run the world until pred() or fail with `msg` (and the virtual time spent)
function T.waitFor(world, pred, max, msg)
  if not world:runUntil(pred, max or 60) then
    for _, c in ipairs(world.computers) do
      if c.error then error("computer " .. tostring(c.label or c.id) .. " crashed while waiting:\n" .. c.error, 2) end
    end
    error((msg or "condition never became true") .. " (waited " .. (max or 60) .. " virtual seconds)", 2)
  end
end

-- Run every registered test. Returns passed, failed, and prints one line per test.
function T.runAll(prefix)
  local passed, failed = 0, 0
  for _, t in ipairs(T.tests) do
    cc.worlds = {}
    local ok, err = xpcall(t.fn, function(e) return debug.traceback(tostring(e), 2) end)
    if ok then
      for _, w in ipairs(cc.worlds) do
        for _, c in ipairs(w.computers) do
          if c.error then ok, err = false, "computer " .. tostring(c.label or c.id) .. " crashed:\n" .. c.error end
        end
      end
    end
    if ok then
      passed = passed + 1
      print("  PASS  " .. (prefix or "") .. t.name)
    else
      failed = failed + 1
      print("  FAIL  " .. (prefix or "") .. t.name)
      print((tostring(err):gsub("\n", "\n        ")))
    end
  end
  T.tests = {}
  return passed, failed
end

return T
