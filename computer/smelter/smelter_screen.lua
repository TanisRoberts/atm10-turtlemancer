-- smelter_screen.lua  --  smelter: screen basics: the kit's views (monitor and the computer's own screen), the page
-- router, the command bar, button rows and the event loop. The pages are drawn by smelter_home, smelter_trainui,
-- smelter_lists and smelter_facui, all built only from the UI kit (docs/systems/ui.md); nothing here writes to a
-- terminal. Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local FX, K, TEXT_SCALE = S.FX, S.K, S.TEXT_SCALE
local ui = FX.kit

---------------------------------------------------------------------------
-- Views: the monitor (touching a side) and the computer's own screen. Each keeps its own page.
---------------------------------------------------------------------------
local states = { term = { page = "home" }, monitor = { page = "home" } }
S.states = states
local views = { ui.view(term.current()) }
S.views = views

local function stateFor(v) return states[v.side and "monitor" or "term"] end

-- shared/screens.lua picks the monitor (docs/systems/screens.md): the biggest one touching the computer, else the
-- one picked from the cable. Asked once at start; a resized or lost monitor reboots (screensLoop below).
local screens = require("screens").new({ slots = { { id = "screen", label = "the smelter screen", required = false, scale = TEXT_SCALE } } })
screens:open()
local picked = { screens:get("screen") }        -- may ask, now, before anything else runs
local function syncMonitor()
  views[2] = picked[1] and ui.view(picked[1], { side = picked[2], scale = TEXT_SCALE }) or nil
end

-- Show a page on a view. The page's own state (a selected factory, the recipe being edited, ...) starts empty;
-- `extra` fills it.
local function go(v, page, extra)
  local st = stateFor(v)
  for k in pairs(st) do st[k] = nil end
  st.page = page
  for k, val in pairs(extra or {}) do st[k] = val end
  v.page, v.sel, v.armed, v.focus = 1, nil, nil, nil
end
local function termView() return views[1] end
local function monView() return views[2] end

-- A notice on both screens. The old programs said colours; the kit says tones.
local TONE = { [K.lime] = "good", [K.orange] = "warn", [K.red] = "bad" }
local function say(text, colour) ui.say(text, TONE[colour] or "plain") end
FX.notify = say
-- A printed line scrolls the terminal behind the kit's back: have every row drawn again afterwards.
FX.print = function(...)
  print(...)
  for _, v in ipairs(views) do v:invalidate() end
  os.queueEvent("smelter_draw")
end

-- Motion that is not the dashboard glyph (a blinking card, dots) only moves with ANIM=full.
local function beat(v, rate)
  if ui.anim ~= "full" or not v.colour then return 0 end
  v.animated = true
  v.animRate = math.max(v.animRate or 0, rate)
  return ui.beat(rate)
end

local function wrap(text, w)
  local out, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else out[#out + 1] = line; line = word end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end
-- Word-wrapped text in a tone, from row y down to row `last`. Returns the next free row.
local function text(v, x, y, w, last, str, tone)
  for _, l in ipairs(wrap(str, w)) do
    if y > last then break end
    v:put(x, y, l, tone or "fg", "bg")
    y = y + 1
  end
  return y
end

---------------------------------------------------------------------------
-- Button rows. A page lists its actions; they sit on the footer row beside Back (and the pager) when they fit one
-- row, else on the rows above it. plan() says how much room that leaves the content, draw() (after v:footer)
-- puts them there.
---------------------------------------------------------------------------
local function pillW(v, b)
  local n = #v:_label(b)
  if b.confirm then n = math.max(n, #(b.label or ""), 5) end
  return n + (v.colour and 2 or 4)
end
local function plan(v, list, o)
  o = o or {}
  local inp = v.side and 0 or 1                            -- the command bar sits above the footer
  local base = v.H - 1 - inp
  local x0 = o.back and ((v.wc == "regular" or v.wc == "wide") and 10 or 5) or 2
  local maxx = v.W - 1 - (o.pager and 12 or 0)
  local total = -1
  for _, b in ipairs(list) do total = total + pillW(v, b) + 1 end
  local p = { bottom = base, input = inp }
  if #list == 0 then p.draw = function() end; return p end
  if x0 + total - 1 <= maxx then
    p.draw = function() v:buttons(x0, v.H, list, { maxx = maxx }) end
    return p
  end
  local rows, cx = 1, 2
  for _, b in ipairs(list) do
    local w = pillW(v, b)
    if cx > 2 and cx + w - 1 > v.W - 1 then rows = rows + 1; cx = 2 end
    cx = cx + w + 1
  end
  local top = v.H - 1 - inp - (rows - 1)
  p.bottom, p.input = top - 1, v.H - 1 - (top - 1)
  p.draw = function() v:buttons(2, top, list) end
  return p
end

---------------------------------------------------------------------------
-- The command bar and the loop
---------------------------------------------------------------------------
S.field = ui.field{ hint = "type a command, / lists them", max = 60, on_commit = function(t)
  S.field.text = ""
  if t:match("^%s*$") then
    local st = states.term
    if st.page == "train" and S.train.state ~= "learned" then
      local ok, why = S.startTraining()
      if not ok then say(why, K.orange) end
    end
  elseif S.cmds then S.cmds:exec(t) end
end }

local PAGES = {}
S.pages = PAGES
local lastErr
local function draw(v)
  local st = stateFor(v)
  local ok, err = pcall(PAGES[st.page] or PAGES.home, v, st)
  if not ok and err ~= lastErr then lastErr = err; ui.say("Screen error: " .. tostring(err), "bad") end
  if not v.side and S.cmds then v:search(S.field, { commands = S.cmds:commands() }) end
end

local function uiLoop()
  ui.loadAnim("smelter.env")
  syncMonitor()
  ui.run(views, draw, { tick = 1 })
end

-- Answers other computers' monitor claims; a resized or unplugged monitor reboots, which fits or asks again.
local function screensLoop()
  parallel.waitForAny(function() screens:daemon() end, function() os.pullEvent("screens_changed") end)
  os.reboot()
end
function S.repickMonitor() screens:repick("screen"); os.reboot() end

S.go, S.say, S.wrap, S.text, S.beat, S.plan = go, say, wrap, text, beat, plan
S.termView, S.monView, S.stateFor = termView, monView, stateFor
S.uiLoop = function() parallel.waitForAny(uiLoop, screensLoop) end
end
