-- architect_gaps.lua  --  the gap list: cells already filled or buried are dropped, buried ones are listed for Tanis, Forget gaps.
-- A part of architect.lua. Gaps (S.gaps) are cells the Weaver skipped for want of a block; S.buried are gaps nobody can reach
-- any more (the build stands on top of them): fix them by hand. docs/systems/architect.md.

local function key3(c) return c[1] .. "," .. c[2] .. "," .. c[3] end

-- the block names of the build, for the Weaver's "never dig the build" (sent in site and build)
function buildNames()
  return P and P.names or nil
end

-- "x,z" -> the highest cell already sent to the Weaver in that column (held cells were left out on purpose)
local function sentCols()
  local st = R.status
  local top = math.min(math.max(st and st.layer or 1, 1) + 1, P.total)
  local ck = table.concat({ top, siteKey(), #S.held }, ":")
  if R.cols and R.cols.key == ck then return R.cols.map end
  local held, map = {}, {}
  for _, h in ipairs(S.held) do held[key3(h)] = true end
  for k = 1, top do
    for _, c in ipairs(layerCells(k)) do
      if not held[key3(c)] then
        local col = c[1] .. "," .. c[3]
        if not map[col] or c[2] > map[col] then map[col] = c[2] end
      end
    end
  end
  R.cols = { key = ck, map = map }
  return map
end

-- Remove cells from the gap list. Held cells whose column is open again become gaps.
local function drop(set, buried)
  local rest = {}
  for _, g in ipairs(S.gaps) do
    if set[key3(g)] then
      if buried then
        S.buried[#S.buried + 1] = g
        local wx, wz = worldOf(g[1], g[3])
        addLog(("buried, fix by hand: %s at %d %d %d"):format(pretty(g[4]), wx, S.site.dy + g[2], wz))
      end
    else
      rest[#rest + 1] = g
    end
  end
  S.gaps = rest
  local cols, held = gapColumns(), {}
  for _, h in ipairs(S.held) do
    if cols[h[1] .. "," .. h[3]] then held[#held + 1] = h else S.gaps[#S.gaps + 1] = h end   -- the column is open: they are gaps now
  end
  S.held = held
  save()
end

-- Gaps with the build already on top of them (sent ahead): nobody can place into them
function sweepBuried()
  if not (P and siteOK(S.site) and #S.gaps > 0) then return end
  local map, set, any = sentCols(), {}, false
  for _, g in ipairs(S.gaps) do
    local top = map[g[1] .. "," .. g[3]]
    if top and top > g[2] then set[key3(g)] = true; any = true end
  end
  if any then drop(set, true) end
end

function onGapsFilled(msg)
  R.gapOut = nil
  local filled, buried = {}, {}
  for _, c in ipairs(msg.cells or {}) do filled[key3(c)] = true end
  for _, c in ipairs(msg.buried or {}) do buried[key3(c)] = true end
  drop(filled, false)
  if next(buried) then drop(buried, true) end
  addLog(("Weaver: filled %d gaps, %d left%s"):format(#(msg.cells or {}), #S.gaps,
    #(msg.buried or {}) > 0 and (", " .. #msg.buried .. " buried") or ""))
end

-- Tanis fixed them by hand: clear the lists (cells held back above a gap are gaps now)
function forgetGaps()
  local n, b = #S.gaps, #S.buried
  S.gaps, S.buried, R.gapOut = {}, {}, nil
  drop({}, false)
  tx({ type = "gaps_forget" })
  addLog(("gaps forgotten (%d gaps, %d buried)"):format(n, b))
  return n, b
end

function gapsSummary()
  local t = {}
  for i, g in ipairs(S.buried) do
    if i > 3 then t[#t + 1] = "..."; break end
    t[#t + 1] = pretty(g[4])
  end
  return ("%d gaps, %d buried%s"):format(#S.gaps, #S.buried, #t > 0 and (" (" .. table.concat(t, ", ") .. ")") or "")
end
