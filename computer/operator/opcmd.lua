-- opcmd.lua  --  the Operator's typed commands (shared/slash.lua, docs/systems/ui.md): the same orders as the
-- screen's ON / OFF / AUTO and level buttons, through opctl, so a typed order and a tap do the same thing.
local slash = require("slash")

return function(ctl)
  local cmds = slash.new()

  -- "reactor-1", "reactor 1", "1" or a label -> the unit; no words = every reactor (nil)
  local function target(a, i)
    if not a.words[i] then return nil, nil end
    local ref = table.concat(a.words, " ", i):lower():gsub("^reactor[%s%-]*", "")
    for _, u in ipairs(ctl.reactors()) do
      if tostring(u.label):lower():gsub("^reactor[%s%-]*", "") == ref or tostring(u.id) == a.words[i] then return u.label, nil end
    end
    return nil, "No reactor '" .. table.concat(a.words, " ", i) .. "'"
  end

  local function status()
    local n, on, fe, buf, nb = 0, 0, 0, 0, 0
    for _, u in ipairs(ctl.reactors()) do
      if not u.awaiting then
        n = n + 1
        local s = u.status or {}
        if s.active then on = on + 1 end
        fe = fe + (s.fe or 0)
        if s.buf then buf, nb = buf + s.buf, nb + 1 end
      end
    end
    if n == 0 then return true, "No reactors yet", "warn" end
    return true, ("%d of %d reactor%s on, %d FE/t%s"):format(on, n, n == 1 and "" or "s", math.floor(fe + 0.5),
      nb > 0 and (", buffer " .. math.floor(buf / nb * 100 + 0.5) .. "%") or ""), on > 0 and "good" or "plain"
  end
  cmds:add({ name = "status", help = "reactors on, power, buffer", max = 0, run = status })

  for _, mode in ipairs({ "on", "off", "auto" }) do
    cmds:add({ name = mode, args = "[reactor]", max = 3, help = "switch " .. (mode == "auto" and "back to auto" or mode)
      .. " (none = every reactor)",
      run = function(a)
        local ref, err = target(a, 1)
        if err then return false, err end
        if not ctl.mode(ref, mode) then return false, "No reactor to switch" end
        return true, (ref or "Every reactor") .. ": " .. mode:upper(), mode == "off" and "warn" or "good"
      end })
  end

  cmds:add({ name = "level", args = "percent [reactor]", min = 1, max = 4, help = "hold a power level for a while",
    run = function(a)
      local p, e = a:int(1)
      if not p then return false, e end
      if p < 0 or p > 100 then return false, "Level is 0 to 100" end
      local ref, err = target(a, 2)
      if err then return false, err end
      if #ctl.reactors(ref) == 0 then return false, "No reactor to hold" end
      ctl.hold(ref, p)
      return true, (ref or "Every reactor") .. ": level " .. p .. "% held"
    end })

  return cmds
end
