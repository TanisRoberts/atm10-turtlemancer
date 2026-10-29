-- drip.lua  --  the factory "drip" trial: learn what an ore does in a Mekanism factory with as few items as possible.
--
-- One item goes into the feed barrel at a time. After each one I watch whether a process starts; if
-- not, one more. n = items added when one started. Then that one operation finishes and I read its
-- output: { used = n, made = output count }.
--
-- This file holds the decisions only (no peripherals, no config): smelter.lua reads the factory into a
-- snapshot, calls D.step, and does what the verdict says (see FX.trialStep there).
--
--   snapshot = { feedN = this ore in the feed barrel, inN = this ore in the factory's inputs,
--                otherIn = other items in its inputs, outs = { name = count } (outputs, this ore's
--                own name left out), progress = highest getRecipeProgress, ticks = getTicksRequired,
--                powered = false while the factory has no energy }
--
-- A trial is a table: { input, added, want, age, ... }. `age` only counts while the factory has power, so
-- nothing is refused or learned while it's dead.
local D = {}

D.CAP       = 16     -- items to drip before calling a trial off with nothing started
D.SETTLE    = 2      -- seconds after an item shows up in the input before another is added (progress detector)
D.REFUSE    = 20     -- seconds an item can fail to show up in the input before it counts as refused
D.RUN_MAX   = 90     -- seconds a started operation may take to show its output
D.STABLE    = 1.5    -- seconds the output count must stay put before I believe it
D.OP_FALLBACK = 200  -- ticks per operation when the factory doesn't say

-- Which way "a process has started" is told. false: wait one operation after each drip and watch the
-- input count drop or an output appear (slower, always works). true: getRecipeProgress(p) > 0, only once
-- #60 confirms it rises as soon as the input is enough. smelter.cfg `dripProgress = true` switches it on.
D.useProgress = false

function D.begin(input, opts)
  local t = { input = input, added = 0, want = true, age = 0, maxIn = 0, outAt = nil }
  for k, v in pairs(opts or {}) do t[k] = v end
  return t
end

-- The one function that decides "has a process started?" (swap the method here, nowhere else)
function D.started(t, snap)
  if next(snap.outs) then return true end
  if t.maxIn > 0 and snap.inN < t.maxIn then return true end       -- the input drained: an operation consumed it
  if D.useProgress and (snap.progress or 0) > 0 then return true end
  return false
end

-- How long to wait after the last drip landed before deciding nothing started
function D.waitFor(snap)
  if D.useProgress then return D.SETTLE end
  return (snap.ticks or D.OP_FALLBACK) / 20 + 1.5
end

-- The storage computer put `moved` items in the feed barrel (0 = it couldn't)
function D.sent(t, moved)
  t.pending = nil
  if moved > 0 then t.added, t.sentAge, t.fails = t.added + moved, t.age, 0
  else
    t.fails = (t.fails or 0) + 1
    t.want = true
  end
end

-- The result I learn: kept in one place so a later change (a "direct" final-product marker) adds a field here.
-- `used` and `made` are per operation; `drip` says used counts items for ONE process (older entries count a batch).
function D.result(t, product, made)
  return { out = product, used = t.n, made = made, drip = true, at = os.epoch("utc") }
end

local function biggest(outs)
  local name, n = nil, 0
  for k, c in pairs(outs) do if c > n then name, n = k, c end end
  return name, n
end

-- One look at the factory. Returns nil (carry on) or a verdict:
--   { kind = "learned", product, made }   { kind = "refused", feedN }   { kind = "capped" }
--   { kind = "nothing" }  (it started but nothing came out in time)   { kind = "lost" }  (storage keeps failing)
function D.step(t, snap, dt)
  if snap.powered == false then return nil end
  t.age = t.age + dt
  if t.pending then return nil end                  -- an item is on its way from storage
  if (t.fails or 0) >= 3 then return { kind = "lost" } end
  if t.added == 0 or t.want then t.want = true; return nil end

  t.maxIn = math.max(t.maxIn, snap.inN)
  if not t.running then
    if D.started(t, snap) then
      t.running, t.runAge, t.n = true, t.age, t.added
    elseif snap.inN == 0 and t.maxIn == 0 then
      -- Left the feed but never reached the input (or never left it): refused
      if t.age - t.sentAge > D.REFUSE then return { kind = "refused", feedN = snap.feedN } end
      return nil
    else
      if snap.inN >= t.added then t.arrivedAge = t.arrivedAge or t.age end
      if t.arrivedAge and t.age - t.arrivedAge >= D.waitFor(snap) then
        if t.added >= D.CAP then return { kind = "capped" } end
        t.want, t.arrivedAge = true, nil
      end
      return nil
    end
  end
  -- Started: let the operation finish and read what it made
  local product, made = biggest(snap.outs)
  if product then
    if made ~= t.lastMade then t.lastMade, t.outAge = made, t.age end
    if t.age - t.outAge >= D.STABLE then return { kind = "learned", product = product, made = made } end
  elseif t.age - t.runAge > D.RUN_MAX then
    return { kind = "nothing" }
  end
  return nil
end

---------------------------------------------------------------------------
-- The probe: the same drip, with every sample written down
---------------------------------------------------------------------------
-- One log line: seconds since the start, the feed, then every process's input / output / progress
function D.sampleLine(secs, snap, procs)
  local parts = {}
  for p = 1, #procs do
    local pr = procs[p]
    parts[#parts + 1] = ("p%d in=%s out=%s prog=%s"):format(p - 1, pr.input, pr.output, pr.progress)
  end
  return ("%6.1f  feed=%d  ticks=%s  %s"):format(secs, snap.feedN or 0, tostring(snap.ticks), table.concat(parts, " | "))
end

return D
