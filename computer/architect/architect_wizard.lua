-- architect_wizard.lua  --  the setup wizard: the frame, step 1 (Weaver) and step 2 (Build). docs/design/architect-fleet.md.
-- Steps 3 and 4 are in architect_site.lua. A part of architect.lua.

W_STEPS = { "Weaver", "Build", "Site", "Go" }
V.numField = ui.field({ hint = "the Weaver's number", max = 3, validate = function(t)
  if not t:match("^%d+$") then return "digits only" end
end, on_commit = function(t) local n = tonumber(t); if n then beginRelink(n) end end })

function reach()
  local r = 1
  if S.n then r = 2 end
  if S.n and P then r = 3 end
  if S.n and P and siteOK(S.site) then r = 4 end
  return r
end
function openWizard(step)
  V.mode, V.step, V.sub, V.sub2 = "wizard", step or (V.step or 1), nil, nil
  if V.step > reach() then V.step = reach() end
end
function initialMode()
  if S.started and P and siteOK(S.site) and S.n then V.mode, V.tab = "tabs", "status"
  else openWizard(reach()) end
end
function gotoStep(i)
  if i < 1 or i > reach() then return end
  V.step, V.sub, V.sub2 = i, nil, nil
end
function leaveWizard()
  if S.n and P and S.started then V.mode = "tabs" end
end
function backStep()
  if V.sub2 then V.sub2 = nil
  elseif V.sub then V.sub = nil; R.pair = nil; R.relink = nil
  elseif V.step > 1 then V.step = V.step - 1
  else leaveWizard() end
end

-- header, step bar, Back and Next. next = { ok = bool, fn = fn, label = "Next" }
function wizFrame(v, nxt)
  v:header(label(), { right = ("setup step %d of 4"):format(V.step) })
  local x, r = 2, reach()
  for i, l in ipairs(W_STEPS) do
    local x2 = v:put(x, 3, l, i == V.step and "gold" or "dim", "bg")
    if i <= r then v:_box({ x, 3, x2 - 1, 3 }, nil, { id = "step" .. i, fn = function() gotoStep(i) end }) end
    x = x2
    if i < 4 then x = v:put(x, 3, " > ", "bar", "bg") end
  end
  v:footer({ back = backStep })
  if nxt then
    local lab = nxt.label or "Next"
    v:buttons(v.W - #lab - 5, v.H, { { label = lab .. " >", style = nxt.ok and "primary" or "disabled", enabled = nxt.ok and true or false,
                                       fn = nxt.fn, id = "next" } })
  end
end

function nextStep() if V.step < 4 then V.step = V.step + 1; V.sub, V.sub2 = nil, nil end end

---------------------------------------------------------------------------
-- Step 1: Weaver
---------------------------------------------------------------------------
local function line(v, y, name, text, state, tone)
  v:put(2, y, name, "dim", "bg")
  if state == "wait" then v:spinner(11, y); v:put(13, y, fit(text, v.W - 13), "fg", "bg")
  else v:put(11, y, fit(text, v.W - 11), tone or "good", "bg") end
  return y + 1
end

local function dropLine(v, y, wantName)
  local rd = R.read
  if rd and rd.err then
    v:put(2, y, fit(rd.err, v.W - 2), "bad", "bg"); return y + 1
  elseif rd and not rd.done and rd.size then
    v:put(2, y, fit(("Reading %s (%s KB)"):format(rd.name, math.ceil(rd.size / 1024)), v.W - 2), "fg", "bg")
    v:indeterminate(2, y + 1, v.W - 2)
    v:put(2, y + 2, ("working, %d steps"):format(rd.step or 0), "dim", "bg")
    return y + 3
  end
  return y
end

function drawStep1(v)
  local y = 5
  if V.sub == "new" then
    local p = R.pair
    if not p then
      local list = unpaired()
      if #list == 0 then
        v:spinner_line(2, y, "Listening for Weavers with no number.")
        v:put(2, y + 1, "Put the turtle down and boot it.", "dim", "bg")
      else
        v:put(2, y - 1, "Pick a turtle (its ID is on its own screen):", "fg", "bg")
        local rows = {}
        for _, h in ipairs(list) do rows[#rows + 1] = { name = "Turtle #" .. h.id, value = ("heard %ss ago, no number"):format(math.floor(now() - h.t)), id = h.id, tone = "dim" } end
        v:list(rows, { top = y, once = true, on = function(row) beginPair(row.id) end })
      end
      return false
    end
    y = 5
    v:put(2, y - 1, ("Turtle #%d"):format(p.turtle), "fg", "bg")
    y = line(v, y, "Number", p.n and (("%02d from the mainframe"):format(p.n)) or "asking the mainframe", p.n and "ok" or "wait")
    if not p.n and now() - p.t0 > 10 then
      v:put(11, y, "the mainframe hasn't answered, is it on?", "warn", "bg"); y = y + 1
    end
    y = line(v, y, "Turtle", p.paired and (("#%d is now Weaver-%02d"):format(p.turtle, p.n)) or "relabelling", p.paired and "ok" or "wait")
    y = line(v, y, "Me", S.n and label() or "waiting", S.n and "ok" or "wait")
    return S.n and p.paired
  elseif V.sub == "relink" then
    local r = R.relink
    v:put(2, y - 1, "Re-link to Weaver number", "fg", "bg")
    if not r then V.focusNum = true end
    v:field(2, y + 1, "Number", 16, V.numField)
    if V.focusNum then v.focus = "field:Number"; V.focusNum = false end
    if not r then return false end
    y = y + 3
    if not r.state then
      if now() - r.t0 > 10 then v:put(2, y, fit(("No Weaver-%02d answered. Is he on, with an ender modem?"):format(r.n), v.W - 2), "warn", "bg")
      else v:spinner_line(2, y, ("Asking Weaver-%02d"):format(r.n)) end
      return false
    end
    local st = r.state
    v:put(2, y, ("Weaver-%02d answered (turtle #%s)"):format(r.n, tostring(st.id or r.from)), "good", "bg"); y = y + 1
    if st.hash then
      v:put(2, y, "Building", "dim", "bg"); v:put(13, y, fit(("%s, layer %s"):format(st.build or "?", tostring(st.layer)), v.W - 13), "fg", "bg"); y = y + 1
      v:put(2, y, "Site", "dim", "bg")
      v:put(13, y, r.site and "kept by the mainframe" or "not known", r.site and "fg" or "warn", "bg"); y = y + 2
      local ok = P and S.hash == st.hash
      if ok then v:put(2, y, "Build file matches: " .. tostring(S.name), "good", "bg"); return true end
      local y2 = dropLine(v, y, st.build)
      if y2 == y then
        v:put(2, y, "I don't have the build file. Drag", "fg", "bg")
        v:put(2, y + 1, fit(tostring(st.build or "it") .. ".litematic onto this screen to carry on where he is.", v.W - 2), "gold", "bg")
      end
      return false
    end
    v:put(2, y, "He holds no build yet. Next to load one.", "dim", "bg")
    return true
  end
  -- the two choices
  if S.n then
    v:put(2, y, ("Paired: %s and Weaver-%02d (turtle #%s)"):format(label(), S.n, tostring(S.wid)), "good", "bg")
    return true
  end
  v:put(2, y - 1, "Which Weaver does this computer run?", "fg", "bg")
  v:list({ { name = "A new Weaver", note = "a turtle with no number", id = "new", value = ">" },
           { name = "An existing Weaver", note = "replaces a lost Architect", id = "relink", value = ">" } },
         { top = y + 1, once = true, on = function(row) V.sub = row.id end })
  return false
end

function step1Next()
  if V.sub == "relink" and R.relink and R.relink.state then
    local r = R.relink
    S.n, S.wid = r.n, r.from
    os.setComputerLabel(label())
    if r.state.hash and P and S.hash == r.state.hash and siteOK(r.site) then
      S.site, S.started = r.site, true
      save(); addLog("re-linked to Weaver-" .. ("%02d"):format(r.n))
      R.pair, R.relink, R.out = nil, nil, nil
      V.mode, V.tab = "tabs", "status"
      return
    end
    save(); R.pair, R.relink = nil, nil
  end
  V.sub, R.pair = nil, nil
  nextStep()
end

---------------------------------------------------------------------------
-- Step 2: Build
---------------------------------------------------------------------------
local function mostUsed(info)
  local list = {}
  for name, n in pairs(info.bill or {}) do list[#list + 1] = { name = name, n = n } end
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end; return a.name < b.name end)
  return list
end

function drawStep2(v)
  local rd = R.read
  local W, y = v.W, 5
  if V.sub2 then return drawStep2List(v) end
  if P and not (rd and rd.size and not rd.done) then
    local info = P.plan.info
    local u = info.stats and info.stats.U or 0
    v:kv(2, y, W - 2, "Build", fit(("%s  by %s"):format(S.name or "?", info.author or "unknown"), W - 12)); y = y + 1
    v:kv(2, y, W - 2, "Size", ("%d x %d, %d high"):format(info.size.x, info.size.z, info.size.y)); y = y + 1
    v:kv(2, y, W - 2, "Blocks", ("%s of %d kinds"):format(comma(info.blocks), info.types or #info.palette)); y = y + 1
    v:kv(2, y, W - 2, "Placing", ("%s as the file says"):format(comma(info.blocks - u)), "good"); y = y + 1
    if u > 0 then v:kv(2, y, W - 2, "", ("%d a simpler way (see list)"):format(u), "warn"); y = y + 1 end
    y = y + 1
    v:put(2, y, "Most used", "dim", "bg"); y = y + 1
    for i, e in ipairs(mostUsed(info)) do
      if i > 4 then break end
      local have = R.stock and (R.stock[e.name] or 0)
      local tone = not have and "dim" or have >= e.n and "good" or have * 10 < e.n and "bad" or "warn"
      v:put(3, y, fit(pretty(e.name), 24), "fg", "bg")
      v:put(28, y, ("%7s"):format(comma(e.n)), "fg", "bg")
      v:put(38, y, have and ("storage " .. comma(have)) or "", tone, "bg")
      y = y + 1
    end
    v:buttons(2, v.H - 2, { { label = "All " .. (info.types or #info.palette), fn = function() V.sub2 = "all" end },
                           { label = "Simpler " .. u, fn = function() V.sub2 = "simpler" end, enabled = u > 0 },
                           { label = "Other file", fn = function() P, S.file, S.hash, S.started = nil, nil, nil, false; R.read = nil end } })
    return true
  end
  if rd and (rd.err or rd.size) then
    dropLine(v, y, rd.name)
    if rd.err then v:put(2, y + 1, "Drag another file onto this screen.", "dim", "bg") end
    return false
  end
  v:put(8, y + 1, "Drag a .litematic file onto this", "fg", "bg")
  v:put(8, y + 2, "screen to load a build.", "fg", "bg")
  return false
end

function drawStep2List(v)
  local info = P.plan.info
  local rows = {}
  if V.sub2 == "all" then
    for _, e in ipairs(mostUsed(info)) do rows[#rows + 1] = { key = pretty(e.name), value = comma(e.n) } end
  else
    -- a build loaded from its saved .plan2 (after a reboot) has the marks but not the reasons: work them out again
    if not P.plan.ulist then plan2place.classify(P.plan) end
    for _, u in ipairs(P.plan.ulist or {}) do
      rows[#rows + 1] = { key = pretty(u.name) .. (" at %d %d %d"):format(u.x, u.y, u.z), value = tostring(u.why or ""), tone = "warn" }
    end
  end
  v:report({ title = V.sub2 == "all" and "Bill" or "Placed a simpler way", rows = rows, back = function() V.sub2 = nil end })
  return nil
end
