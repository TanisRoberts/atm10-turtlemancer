-- shared/ui_motion.lua  --  UI kit motion (docs/design/ui-kit.md section 9), loaded by ui.lua after ui_parts.lua:
-- the shared beat, status glyphs, spinner, indeterminate bar and the ANIM setting.
-- Only active things move, all on one beat, one character per icon; a view draws at most 24 moving glyphs.
-- ui.run re-arms its timer for the next beat only while a view drew something that moves.
return function(ui)
local View = ui.View
local floor, max, min = math.floor, math.max, math.min

ui.anim = "full"                         -- full | calm | off (calm: dashboard glyphs only; off: nothing moves)
local BUDGET = 24

-- ui.beat(rate): an integer that goes up `rate` times a second, the same for every glyph in a frame.
function ui.beat(rate) return floor(os.clock() * rate) end
-- Seconds on the os.clock until the next beat at `rate` (used by ui.run).
function ui.nextBeat(rate) return (floor(os.clock() * rate) + 1) / rate + 0.005 end

-- ui.setAnim("calm"); anything but full/calm/off is full.
function ui.setAnim(mode)
  mode = tostring(mode or "full"):lower()
  ui.anim = (mode == "calm" or mode == "off") and mode or "full"
  return ui.anim
end

-- ui.loadAnim("smelter.env", "full"): read ANIM= from a device's .env-style file and set it. A missing key is
-- appended (an existing line is never overwritten).
function ui.loadAnim(path, default)
  local mode
  if fs.exists(path) then
    local f = fs.open(path, "r")
    for line in (f.readAll() .. "\n"):gmatch("(.-)\r?\n") do
      local v = line:match("^%s*ANIM%s*=%s*(%a+)")
      if v then mode = v end
    end
    f.close()
  end
  if not mode then
    local f = fs.open(path, "a")
    f.write("\n# ANIM: motion on the screens. full, calm (dashboard icons only) or off (nothing moves).\nANIM=" .. (default or "full") .. "\n")
    f.close()
    mode = default
  end
  return ui.setAnim(mode)
end

-- Frames and colours per animated state (section 9.2). Colours are roles.
local CLASS = {}
for _, s in ipairs({ "working", "running", "mining", "mapping", "surveying", "clearing", "marking" }) do CLASS[s] = "working" end
for _, s in ipairs({ "farming", "planting", "harvesting" }) do CLASS[s] = "farming" end
for _, s in ipairs({ "smelting", "cooking" }) do CLASS[s] = "smelting" end
for _, s in ipairs({ "rebooting", "updating" }) do CLASS[s] = "rebooting" end
CLASS.building, CLASS.waiting, CLASS.returning = "building", "waiting", "returning"
local FRAMES = {
  working = { "\\", "|", "/", "|" }, building = { "+", "x", "+", "x" }, farming = { ".", ",", "i", "Y" },
  smelting = { "\30", "^", "\30", "'" }, waiting = { ".", "o", "O", "o" }, returning = { "<", "\171", "<", "\171" },
  rebooting = { "|", "/", "-", "\\" } }
local COLOURS = { working = "good", building = "good", farming = "good2", smelting = { "bad", "warn", "gold", "warn" },
                  waiting = "warn", returning = "info", rebooting = "busy" }
local STILL = { docked = { "=", "idle" }, done = { "+", "idle" }, idle = { "-", "dim" }, stale = { "?", "bar" },
                lost = { "!", "bad" }, error = { "!", "bad" }, stopped = { "!", "bad" }, ok = { "+", "good" } }
-- A screen with state words of its own adds them: ui.glyphs.still["at target"] = { "o", "warn" } (a still glyph and
-- its colour role), ui.glyphs.class["training"] = "working" (a moving one).
ui.glyphs = { class = CLASS, still = STILL }

local begin = View.begin
function View:begin()
  begin(self)
  self.glyphN, self.animated, self.animRate = 0, nil, nil
end

local function moves(self)
  return ui.anim ~= "off" and self.colour
end
local function note(self, rate)
  self.animated = true
  self.animRate = max(self.animRate or 0, rate)
end

-- The glyph and its colour role for a state at the current beat. o: rate (beats a second, default 2), stale
-- (a still ?), since (os.clock when an error began: it pulses three times). Counts against the view's budget.
function View:glyphChar(state, o)
  o = o or {}
  local cls = CLASS[state]
  if o.stale then return "?", "bar" end
  if cls then
    local fr, col = FRAMES[cls], COLOURS[cls]
    local i = 1
    if moves(self) and self.glyphN < BUDGET then
      local rate = o.rate or 2
      i = ui.beat(rate) % 4 + 1
      self.glyphN = self.glyphN + 1
      note(self, rate)
    end
    return fr[i], type(col) == "table" and col[i] or col
  end
  local st = STILL[state] or { "-", "dim" }
  if (state == "lost" or state == "error") and o.since and moves(self) and os.clock() - o.since < 3 then
    note(self, 1)
    return "!", floor(os.clock() - o.since) % 2 == 0 and "bad" or "fg"
  end
  return st[1], st[2]
end

-- v:glyph(x, y, state, { rate, stale, since, bg }): one character in the state's colour. Returns x + 1.
function View:glyph(x, y, state, o)
  local ch, col = self:glyphChar(state, o)
  self:put(x, y, ch, col, o and o.bg or "bg")
  return x + 1
end

-- v:spinner(x, y, state): the waiting (or rebooting) glyph at 4 beats a second.
function View:spinner(x, y, state)
  return self:glyph(x, y, state or "waiting", { rate = 4 })
end

-- v:indeterminate(x, y, w): a track with a 6-cell block bouncing one cell per beat (4 a second). Still with
-- ANIM=calm or off, or without colour.
function View:indeterminate(x, y, w)
  local bw = min(6, max(1, floor(w / 3)))
  local span = w - bw
  local pos = 0
  if span > 0 and ui.anim == "full" and self.colour then
    local period = span * 2
    local b = ui.beat(4) % period
    pos = b <= span and b or period - b
    note(self, 4)
  end
  if self.colour then
    self:fill(x, y, w, "bar")
    self:fill(x + pos, y, bw, ui.barColour("progress"))
  else
    self:put(x, y, ("-"):rep(w), "fg", "bg")
    self:put(x + pos, y, ("="):rep(bw), "fg", "bg")
  end
  return y + 1
end

end
