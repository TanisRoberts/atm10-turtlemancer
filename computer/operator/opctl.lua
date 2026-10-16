-- opctl.lua  --  what a person (the screen, or a command from the mainframe) can change on a reactor: the run mode,
-- a held power level, and the settings. One place, so the screen and the radio do exactly the same thing.
-- Settings live in operator.cfg: per reactor (an override) or `plant` (every reactor's default). Both beat operator.env.
local plantlib = require("opplant")
local rods = require("oprods")

-- key -> { env key, step, lowest, highest }. holdMin counts minutes, the rest percent.
local KEYS = {
  onBelow  = { "ON_BELOW",  5, 0, 100 }, offAbove = { "OFF_ABOVE", 5, 0, 100 },
  levelMin = { "LEVEL_MIN", 5, 0, 100 }, levelMax = { "LEVEL_MAX", 5, 5, 100 },
  holdMin  = { "HOLD_MIN",  5, 5, 60 },
}

return function(plant, E, hooks)
  local C = { KEYS = KEYS }
  hooks = hooks or {}
  local function log(m) if hooks.log then hooks.log(m) end end
  local function kick() if hooks.kick then hooks.kick() end end      -- act now, not at the next pass
  local function rescan() if hooks.dirty then hooks.dirty() end end -- look at the cable again

  local function reactors(ref)
    local out = {}
    for _, u in ipairs(plant.units) do
      if u.kind == "reactor" and (ref == nil or ref == u.label or ref == u.id) then out[#out + 1] = u end
    end
    return out
  end
  C.reactors = reactors

  -- mode: auto | on | off. Saved. Ends a manual hold.
  function C.mode(ref, mode)
    if mode ~= "auto" and mode ~= "on" and mode ~= "off" then return false end
    local n = 0
    for _, u in ipairs(reactors(ref)) do
      u.cfg.mode, u.hold = mode, nil
      n = n + 1
      log(u.label .. ": mode " .. mode)
      if hooks.event then hooks.event(u.label, "mode " .. string.upper(mode)) end
    end
    if n > 0 then plant:save(); kick() end
    return n > 0
  end

  -- Hold a power level for HOLD_MIN minutes (the reactor is forced ON, then control returns to Auto).
  function C.hold(ref, level)
    for _, u in ipairs(reactors(ref)) do
      local lo, hi = rods.limits(u, E)
      rods.hold(u, math.max(lo, math.min(hi, math.floor(level + 0.5))), os.clock(), E)
      log(("%s: level %d%% held for %s min"):format(u.label, u.hold.level, tostring(plantlib.setting(u, "holdMin", E, "HOLD_MIN"))))
    end
    kick()
  end

  -- One step of the level (delta percent). Returns a notice text when it hit a limit or can't.
  function C.step(ref, delta)
    local u = reactors(ref)[1]
    if not u then return "no such reactor" end
    if (u.hold and u.hold.mode or u.cfg.mode) == "off" then return "The reactor is off" end
    local lo, hi = rods.limits(u, E)
    local cur = (u.hold and u.hold.level) or u.level or (u.status and u.status.level)
    if not cur then return "Can't read the rods" end
    local want = math.max(lo, math.min(hi, cur + delta))
    if want == cur then return delta < 0 and ("Lowest is " .. lo .. "%") or ("Highest is " .. hi .. "%") end
    C.hold(u.label, want)
    if hooks.event then hooks.event(u.label, ("level held at %d%%"):format(want)) end
  end

  -- What a setting reads for a reactor, and where it comes from ("unit", "plant" or "env").
  function C.value(u, key)
    return plantlib.setting(u, key, E, KEYS[key][1])
  end

  -- Step a setting. all = true sets the plant-wide default and clears this setting from every reactor's own overrides.
  -- Returns a notice text when the step is refused.
  function C.change(ref, all, key, delta)
    local k = KEYS[key]
    local u = reactors(ref)[1]
    if not k or not u then return "no such setting" end
    local cur = C.value(u, key)
    local want = math.max(k[3], math.min(k[4], cur + delta * k[2]))
    if want == cur then return nil end
    -- keep the switching band at least 10 points wide, and the level limits in order
    local on, off = C.value(u, "onBelow"), C.value(u, "offAbove")
    local lo, hi = C.value(u, "levelMin"), C.value(u, "levelMax")
    if key == "onBelow" then on = want elseif key == "offAbove" then off = want
    elseif key == "levelMin" then lo = want elseif key == "levelMax" then hi = want end
    if off - on < 10 then return "ON below stays at least 10 points under OFF above" end
    if hi < lo then return "Highest can't go under Lowest" end
    if all then
      plant.cfg.plant[key] = want
      for _, r in ipairs(reactors(nil)) do r.cfg[key] = nil end
    else
      u.cfg[key] = want
    end
    plant:save(); kick()
    log(("%s %s = %s"):format(all and "all reactors" or u.label, key, tostring(want)))
  end

  -- "Run it": false = leave the reactor alone while still reporting it.
  function C.manage(ref, on)
    for _, u in ipairs(reactors(ref)) do
      if on then u.cfg.manage = nil else u.cfg.manage = false end
      u.hold = nil
    end
    plant:save(); kick()
  end

  -- Ignore (or stop ignoring) a warning or problem on the Needs tab.
  function C.ignore(ref, key, on)
    for _, u in ipairs(reactors(ref)) do
      u.cfg.ignore = u.cfg.ignore or {}
      u.cfg.ignore[key] = on and true or nil
      if next(u.cfg.ignore) == nil then u.cfg.ignore = nil end
    end
    plant:save(); rescan()
  end

  -- Total items in each device that can list them, { [name] = count }: what the wizard's "Find it" watches
  function C.snapshot()
    local out = {}
    for _, n in ipairs(peripheral.getNames()) do
      local types = { peripheral.getType(n) }
      local skip = false
      for _, t in ipairs(types) do
        local l = tostring(t):lower()
        if l == "modem" or l == "monitor" or l:find("reactor$") or l:find("turbine") or l:find("energy_storage") then skip = true end
      end
      if not skip then
        local ok, list = pcall(peripheral.call, n, "list")
        if ok and type(list) == "table" then
          local c = 0
          for _, it in pairs(list) do c = c + (it.count or 1) end
          out[n] = c
        end
      end
    end
    return out
  end

  -- Save a finished wizard: { input, output, name }. Returns a notice text when it refuses.
  function C.finishSetup(ref, t)
    local u = reactors(ref)[1]
    if not u then return "no such reactor" end
    if not (t.input and t.output) then return "Pick both ports first" end
    if t.input == t.output then return "The inlet and the outlet can't be the same port" end
    local name = tostring(t.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" and name ~= u.cfg.label then
      for _, r in ipairs(reactors(nil)) do if r ~= u and r.cfg.label == name then return name .. " is already a reactor's name" end end
      u.cfg.label = name
    end
    for _, r in ipairs(reactors(nil)) do
      if r ~= u then
        for _, k in ipairs({ "input", "output" }) do
          if r.cfg[k] == t.input or r.cfg[k] == t.output then r.cfg[k] = nil end
        end
      end
    end
    u.cfg.input, u.cfg.output, u.cfg.setup = t.input, t.output, true
    u.wTrack, u.wasteStuck = nil, false
    log(("%s set up: inlet %s, outlet %s"):format(u.cfg.label, t.input, t.output))
    if hooks.event then hooks.event(u.cfg.label, "set up") end
    plant:save(); rescan(); kick()
  end

  -- Show the wizard for this reactor again (the ports are kept until it is finished)
  function C.rerunSetup(ref)
    for _, u in ipairs(reactors(ref)) do u.cfg.setup = false end
    plant:save(); rescan(); kick()
  end

  -- Everything on the cable that could be a port, ER2 access ports first.
  -- { name, type, port, taken, holds ("12 uranium", "3 cyanite", "empty" or nil), guess = "input"|"output"|nil }
  function C.candidates(ref)
    local taken, isPort = {}, {}
    for _, r in ipairs(reactors(nil)) do
      if r.cfg.input then taken[r.cfg.input] = r.label .. " inlet" end
      if r.cfg.output then taken[r.cfg.output] = r.label .. " outlet" end
    end
    for _, n in ipairs(plant.found and plant.found.port or {}) do isPort[n] = true end
    local u = ref and reactors(ref)[1]
    local guess = u and u.guess or {}
    local out = {}
    for _, n in ipairs(peripheral.getNames()) do
      local types = { peripheral.getType(n) }
      local skip = false
      for _, t in ipairs(types) do
        local l = tostring(t):lower()
        if l == "modem" or l == "monitor" or l:find("reactor$") or l:find("turbine") or l:find("energy_storage") then skip = true end
      end
      if not skip then
        local fuel, waste = plantlib.contents(n)
        local holds
        if fuel and fuel > 0 then holds = fuel .. " uranium"
        elseif waste and waste > 0 then holds = waste .. " cyanite"
        elseif fuel ~= nil then holds = "empty" end
        local g = (guess.input == n and "input") or (guess.output == n and "output") or
          ((fuel or 0) > 0 and "input") or ((waste or 0) > 0 and "output") or nil
        out[#out + 1] = { name = n, type = isPort[n] and "port" or (tostring(types[1]):gsub("^.-:", "")), port = isPort[n] or false,
          taken = taken[n], holds = holds, guess = g }
      end
    end
    table.sort(out, function(a, b)
      if a.port ~= b.port then return a.port end
      return a.name < b.name
    end)
    return out
  end

  -- Say which port is a reactor's inlet or outlet (role "input" | "output"); name nil = back to auto-detect.
  -- A port another reactor held is taken from it. Returns a notice text when it took one.
  function C.assign(ref, role, name)
    if role ~= "input" and role ~= "output" then return end
    local u = reactors(ref)[1]
    if not u then return end
    local note
    if name then
      for _, r in ipairs(reactors(nil)) do
        if r ~= u then
          for _, k in ipairs({ "input", "output" }) do
            if r.cfg[k] == name then r.cfg[k] = nil; note = name .. " was " .. r.label .. "'s " .. (k == "input" and "inlet" or "outlet") end
          end
        end
      end
      local other = role == "input" and "output" or "input"
      if u.cfg[other] == name then u.cfg[other] = nil end
    end
    u.cfg[role] = name
    u.wTrack, u.wasteStuck = nil, false
    log(("%s %s port %s"):format(u.label, role == "input" and "inlet" or "outlet", name and ("= " .. name) or "back to auto"))
    plant:save(); rescan(); kick()
    return note
  end

  function C.reset(ref)
    for _, u in ipairs(reactors(ref)) do
      for key in pairs(KEYS) do u.cfg[key] = nil end
      u.cfg.manage, u.cfg.level = nil, nil
    end
    plant:save(); kick()
  end

  return C
end
