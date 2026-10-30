-- nether_screens.lua  --  what the Nether Foreman shows and takes typed, built only from the UI kit
-- (shared/ui*.lua, docs/design/nether.md, docs/systems/nether.md).
--
-- The Nether Foreman is the Overworld Foreman's screens (computer/foreman/foreman_screens.lua: a tile per Firecrest,
-- a Firecrest's page, presets and the editor, the usual commands) plus what is its own: a line about the barrels
-- under the header, Rules (when Firecrests drink lava, what the Nether keeps, what Firecrest throws away), the
-- Barrels button and /keep /junk /unjunk /rules /assign. The engine (shared/fm_barrels.lua) does the barrels.
--
--   P.screens = require("nether_screens")      in the profile; shared/fm.lua calls it with the engine's environment F
local ui = require("ui")
local slash = require("slash")

return function(F)
  local P = F.P
  local X = { pages = {} }
  F.ext = X
  require("foreman_screens")(F)
  local K = F.kit
  local fit = ui.text.fit
  local say = F.say
  local cmds = F.cmds

  -- engine colour -> kit tone
  local TONE = { [colours.red] = "bad", [colours.orange] = "warn", [colours.yellow] = "warn" }

  ---------------------------------------------------------------------------
  -- Overview: header, the barrels line, buttons
  ---------------------------------------------------------------------------
  function X.header(v, st, n)
    local b = F.barrel
    local word, role = "ok", "good"
    if b.outFull then word, role = "output full", "bad" end
    local right = ("%d %s"):format(n, n == 1 and "firecrest" or "firecrests")
    if (b.outSlots or 0) > 0 then right = right .. ("  out %d/%d free"):format(b.outFree or 0, b.outSlots) end
    v:header(P.title, { state = word, color = role, right = right })
  end

  function X.statusLine(v, y)
    local text, colour = F.barrelLine()
    if text and text ~= "" then v:put(2, y, fit(text, v.W - 2), TONE[colour] or "dim", "bg") end
  end

  -- Assign: the shared screen (shared/assignui.lua) takes the computer's own screen for as long as it is open
  local function openAssign(v)
    if v and v.side then say("Barrels: type /assign on the Nether computer", "warn"); return end
    local tv = K.views[1]
    F.ui = F.termUi
    tv:close()                                   -- assignui draws with the stock palette
    F.openAssign()
    K.views[1] = ui.view(term.current())         -- and the kit puts its palette back
  end

  function X.buttons(list, v, st)
    local out = {}
    for _, b in ipairs(list) do
      if b.label ~= "Dock all" then out[#out + 1] = b end
      if b.label == "Presets" then
        out[#out + 1] = { label = "Rules", short = "Rule", fn = function() K.go(v, st, "rules") end }
        if v.H > 14 then
          out[#out + 1] = { label = "Barrels", short = "Bar", fn = function() openAssign(v) end }
        end
      end
    end
    for i = #list, 1, -1 do list[i] = nil end
    for i, b in ipairs(out) do list[i] = b end
  end

  ---------------------------------------------------------------------------
  -- A Firecrest's page: lava and the dock barrel
  ---------------------------------------------------------------------------
  function X.statusRows(v, id, row)
    local l = F.live[id]
    local s = l and l.s
    local cfg = F.cfg
    local lava = "-"
    if s then lava = s.hungry and ("drinking to " .. cfg.fullAt .. "%") or ("drinks under " .. cfg.hungryAt .. "%") end
    row("Lava", lava, s and s.hungry and "warn" or nil)
    local b = s and s.bucket
    row("Bucket", b == "empty" and "empty, ready" or b == "lava" and "full of lava" or b == "none" and "NONE" or "-",
      b == "none" and "bad" or nil)
    local dock = F.dockOf(id)
    local n = dock and F.barrel.docks[dock] or 0
    if dock then
      row("Barrel", dock:gsub("^minecraft:", "") .. (n > 0 and (", " .. n .. " in it") or ""), "dim")
    else
      row("Barrel", #F.cfg.docks > 0 and "not learned yet" or "no dock barrel: /assign", "warn")
    end
  end

  ---------------------------------------------------------------------------
  -- Rules
  ---------------------------------------------------------------------------
  local function junkLines(w)
    local words = {}
    for _, j in ipairs(F.cfg.junk) do words[#words + 1] = (j:gsub("^minecraft:", ""):gsub("_", " ")) end
    if #words == 0 then return { "nothing: Firecrest brings everything home" } end
    local lines, line = {}, ""
    for _, word in ipairs(words) do
      if line == "" then line = word
      elseif #line + 2 + #word <= w then line = line .. "  " .. word
      else lines[#lines + 1] = line; line = word end
    end
    lines[#lines + 1] = line
    return lines
  end

  -- put "/keep " or "/junk " in the command bar, ready to be finished
  local function typeCommand(v, st, text, hint)
    if v.side then say(hint, "warn"); return end
    st.field.text = text
    v.focus = "search"
  end

  local function drawRules(v, st)
    local cfg = F.cfg
    local keeps = F.keepList()
    local typed = not v.side
    local W, H = v.W, v.H
    local narrow = v.wc == "narrow"
    v:header("RULES", { right = ("%d kept, %d junk"):format(#keeps, #cfg.junk) })
    local by = H - (typed and 2 or 1)         -- the row for + Keep and + Junk
    local y = v:section(2, 3, W - 2, "Lava")
    local function pct(x, label, key, id)
      local nx, last = v:stepper(x, y, label, cfg[key], { min = 5, max = 95, step = 5, small = true, id = id,
        on = function(n) F.setLava(key, n) end })
      v:put(nx + 1, last, "%", "dim", "bg")
      return nx + 3, last
    end
    if W >= 44 then
      local nx, last = pct(2, "Drink under", "hungryAt", "lava:under")
      pct(nx + 4, "until", "fullAt", "lava:until")
      y = last + 1
    else
      local _, last = pct(2, "Drink under", "hungryAt", "lava:under")
      y = last + 1
      _, last = pct(2, "Until       ", "fullAt", "lava:until")
      y = last + 1
    end
    y = v:section(2, y + 1, W - 2, "Keep in the Nether")
    local showButtons = H > 14
    local jw = W - 2
    local jl = junkLines(jw)
    local jrows = 0
    if H >= 22 then jrows = 2 + math.min(#jl, 3)       -- blank, section, lines
    elseif H >= 17 then jrows = 1 end                  -- a one-line summary
    local top = y + 1                                  -- below the column titles
    v:put(2, y, "Item", "dim", "bg")
    local kx = narrow and 2 or W - 21
    if not narrow then v:put(kx + 4, y, "keep", "dim", "bg") end
    v:put(W - 4, y, "have", "dim", "bg")
    local last = (showButtons and by - 1 or (typed and H - 2 or H - 1)) - jrows
    local rowH = narrow and 2 or 1
    local per = math.max(1, math.floor((last - top + 1) / rowH))
    local pages = math.max(1, math.ceil(#keeps / per))
    v.pages = pages
    v.page = math.max(1, math.min(v.page or 1, pages))
    if #keeps == 0 then v:put(2, top, "Nothing kept: everything goes home", "dim", "bg") end
    for i = 1, per do
      local e = keeps[(v.page - 1) * per + i]
      if not e then break end
      local name, c = e[1], e[2]
      local ry = top + (i - 1) * rowH
      local have = F.barrel.stock[name] or 0
          local label = ""
      if narrow then label = fit(F.pretty(name), W - 8) else v:put(2, ry, fit(F.pretty(name), kx - 3), "fg", "bg") end
      v:stepper(kx, ry, label, c, { min = 0, max = 9999, step = c >= 16 and 16 or 1, small = true, id = "keep:" .. name,
        on = function(n) F.setKeep(name, n) end })
      v:put(W - 5, ry, ("%5d"):format(have), have < c and "warn" or "good", "bg")
    end
    if jrows > 0 then
      local jy = last + 1
      if jrows == 1 then
        v:put(2, jy, fit(("Throws away: %s"):format(table.concat(jl, "  ")), W - 2), "dim", "bg")
      else
        jy = v:section(2, jy + 1, W - 2, P.bird .. " throws away")
        for i = 1, math.min(#jl, 3) do
          local line = jl[i]
          if i == 3 and #jl > 3 then line = line .. " ..." end
          v:put(2, jy, fit(line, W - 2), "fg", "bg"); jy = jy + 1
        end
      end
    end
    if showButtons then
      v:buttons(2, by, {
        { label = "+ Keep", style = "primary", fn = function()
          typeCommand(v, st, "/keep ", "Type it on the computer: /keep <item> <count>") end },
        { label = "+ Junk", fn = function()
          typeCommand(v, st, "/junk ", "Type it on the computer: /junk <item>  (/unjunk to undo)") end },
      })
    end
    if typed then v:search(st.field, { hint = "/ = commands (/help)", commands = F.commands }) end
    v:footer({ back = function() K.go(v, st, "overview") end })
  end
  X.pages.rules = drawRules

  ---------------------------------------------------------------------------
  -- Typed commands
  ---------------------------------------------------------------------------
  local function alias(name, ...) for _, a in ipairs({ ... }) do cmds.byName[a] = cmds.byName[name] end end
  local function openPage(page)
    local st = K.termState()
    K.home(); st.page = page
  end
  local function junkCommand(adding)
    return function(a)
      local item = F.resolveItem(a.raw)
      if not item then return false, "No item called " .. a.raw end
      local short = item:gsub("^minecraft:", "")
      local junk = F.cfg.junk
      for i = #junk, 1, -1 do
        local j = junk[i]
        if j == short or j == item or ("minecraft:" .. j) == item then table.remove(junk, i) end
      end
      if adding then junk[#junk + 1] = short end
      F.saveCfg()
      for id in pairs(F.reg) do F.sendNow[id] = true end
      openPage("rules")
      if adding then return true, ("%s throws %s away now."):format(P.bird, F.pretty(item)), "warn" end
      return true, ("%s brings %s home now."):format(P.bird, F.pretty(item)), "good"
    end
  end

  cmds:add({ name = "rules", help = "lava, what is kept, what is junk", max = 0, run = function()
    openPage("rules"); return true end })
  alias("rules", "keeps")
  cmds:add({ name = "assign", help = "give the barrels jobs", max = 0, run = function()
    openAssign(nil); return true end })
  alias("assign", "barrels", "dock")
  cmds:add({ name = "keep", args = "<item> [count]", help = "keep this many here (0 = send it home)", min = 1,
    run = function(a)
      local text, n = a.raw:match("^(.-)%s+(%d+)$")
      local item = F.resolveItem(text or a.raw)
      if not item then return false, "No item called " .. (text or a.raw) end
      n = tonumber(n) or 64
      F.setKeep(item, n)
      openPage("rules")
      if n > 0 then return true, ("Keeping %d %s in %s."):format(n, F.pretty(item), P.place), "good" end
      return true, ("Not keeping %s: it goes home."):format(F.pretty(item)), "warn"
    end })
  cmds:add({ name = "junk", args = "<item>", help = P.bird .. " throws it away underground", min = 1, run = junkCommand(true) })
  cmds:add({ name = "unjunk", args = "<item>", help = P.bird .. " brings it home again", min = 1, run = junkCommand(false) })
  F.commands = cmds:commands()
end
