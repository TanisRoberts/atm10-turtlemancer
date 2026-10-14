-- setup.lua  --  first-time setup for a device. Run by startup.lua when the device has no role.
-- Asks what the device is (computer, turtle or glasses), then which role, then a label.
-- Saves device.cfg and reboots; startup.lua then downloads that role's files.
--
-- One option at a time, like a character select: up/down (or scroll) to browse, Enter, "Pick >" or a
-- click on the card to choose, Backspace or "< Back" to go back. Mouse works on advanced devices.

local REPO = "https://raw.githubusercontent.com/TanisRoberts/atm10-turtlemancer/main/"
local CFG  = "device.cfg"

local W, H = term.getSize()
local COLOUR = term.isColour()
local K = {
  bg = colours.black, bar = colours.grey, title = colours.cyan, text = colours.white,
  dim = colours.lightGrey, faint = colours.grey, pick = colours.cyan, pickText = colours.black,
  guess = colours.lime, warn = colours.orange, good = colours.lime,
}
if not COLOUR then for k in pairs(K) do K[k] = (k == "bg" or k == "pickText") and colours.black or colours.white end end

local function fetchManifest()
  if not http then return nil, "HTTP is turned off on this server" end
  local h, err = http.get(REPO .. "manifest.lua?t=" .. os.epoch("utc"), nil, true)
  if not h then return nil, tostring(err) end
  local body = h.readAll(); h.close()
  local fn = load(body or "", "@manifest.lua", "t", {})
  if not fn then return nil, "bad download" end
  local ok, m = pcall(fn)
  if not ok or type(m) ~= "table" then return nil, "bad manifest" end
  local f = fs.open("manifest.cache", "wb"); f.write(body); f.close()
  return m
end

---------------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------------
local hits = {}
local function at(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setBackgroundColour(bg or K.bg); term.setTextColour(fg or K.text)
  term.write(s)
end
local function fill(y, bg) at(1, y, (" "):rep(W), K.text, bg) end
local function wrap(text, width)
  local lines, line = {}, ""
  for word in tostring(text or ""):gmatch("%S+") do
    if #line == 0 then line = word
    elseif #line + 1 + #word <= width then line = line .. " " .. word
    else lines[#lines + 1] = line; line = word end
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end
local function button(x, y, label, bg, action)
  at(x, y, " " .. label .. " ", bg == K.bar and K.text or colours.black, bg)
  hits[#hits + 1] = { y = y, x1 = x, x2 = x + #label + 1, action = action }
  return x + #label + 3
end

local QY = H <= 13 and 2 or 3   -- question row (a turtle's short screen has no spare line)

-- The frame every step shares: title bar with the step, a question, a footer with buttons.
local function frame(step, steps, question)
  hits = {}
  term.setBackgroundColour(K.bg); term.clear()
  fill(1, K.bar)
  at(2, 1, "TURTLEMANCER SETUP", K.title, K.bar)
  local s = ("%d/%d"):format(step, steps)
  at(W - #s, 1, s, K.dim, K.bar)
  at(2, QY, question, K.text)
end

---------------------------------------------------------------------------
-- A picker, character-select style: one option at a time as a full card, the neighbours peeking
-- in above and below. options = { { key, name, about, details, note } }.
-- Up/down (or left/right, scroll, number keys, clicking the names above/below) changes the card;
-- Enter, "Pick >" or clicking the card picks it. Returns a key, or nil for "back".
---------------------------------------------------------------------------
local function trim(text, width)
  text = tostring(text or "")
  if #text <= width then return text end
  return (text:sub(1, width - 2):match("^(.*%S)%s") or text:sub(1, width - 2)) .. ".."
end

local function menu(step, steps, question, options, default, canBack)
  local sel = 1
  for i, o in ipairs(options) do if o[1] == default then sel = i end end
  local n = #options
  local small = H <= 13                -- a turtle's screen: squeeze the spacing
  local CW = W - 2                     -- card width (columns 2 .. W-1)
  local TX = 4                         -- card text starts here (after the accent stripe)
  local TW = W - TX - 1                -- card text width
  local function move(d) sel = (sel - 1 + d) % n + 1 end
  while true do
    frame(step, steps, question)
    local o = options[sel]
    local counter = n > 1 and ("%d of %d"):format(sel, n) or ""
    if #question + #counter + 4 <= W then at(W - #counter, QY, counter, K.dim) end

    local y = QY + (small and 1 or 2)
    local nextY = H - (small and 1 or 2)
    -- The one before (wraps round)
    if n > 1 then
      local p = options[(sel - 2) % n + 1]
      at(2, y, trim("\30 " .. p[2], CW), K.faint)
      hits[#hits + 1] = { y = y, x1 = 1, x2 = W, action = function() move(-1) end }
    end
    y = y + 1
    -- The card: name bar, then an accent stripe down the left beside the words
    local cardTop = y
    local tag = (o[1] == default and n > 1) and "suggested " or ""
    at(2, y, (" "):rep(CW), K.pickText, K.pick)
    at(3, y, trim(o[2]:upper(), CW - 2 - #tag), K.pickText, K.pick)
    if #tag > 0 and #o[2] + #tag + 3 <= CW then at(W - #tag, y, tag, K.pickText, K.pick) end
    y = y + 1
    local function cardLine(text, colour)
      if y >= nextY then return false end
      at(2, y, " ", K.text, K.pick)
      at(TX, y, text, colour)
      y = y + 1
      return true
    end
    local lines = {}
    for _, l in ipairs(wrap(o[3], TW)) do lines[#lines + 1] = { l, K.text } end
    if o[4] and o[4] ~= o[3] then
      if not small then lines[#lines + 1] = { "", K.text } end
      for _, l in ipairs(wrap(o[4], TW)) do lines[#lines + 1] = { l, K.dim } end
    end
    if o[5] then
      lines[#lines + 1] = { "", K.text }
      for _, l in ipairs(wrap(o[5], TW)) do lines[#lines + 1] = { l, K.warn } end
    end
    local room = nextY - y
    if #lines > room and room > 0 then   -- too long for this screen: end on "..."
      local t = lines[room][1]
      if #t > TW - 3 then t = t:sub(1, TW - 3):match("^(.*%S)%s") or t:sub(1, TW - 3) end
      lines[room][1] = t:gsub("[%.,;:]*$", "") .. "..."
    end
    for i = 1, math.min(#lines, room) do cardLine(lines[i][1], lines[i][2]) end
    while y < nextY do cardLine("", K.text) end
    hits[#hits + 1] = { y1 = cardTop, y2 = nextY - 1, x1 = 1, x2 = W, action = function() return "pick" end }
    -- The one after
    if n > 1 then
      local nx = options[sel % n + 1]
      at(2, nextY, trim("\31 " .. nx[2], CW), K.faint)
      hits[#hits + 1] = { y = nextY, x1 = 1, x2 = W, action = function() move(1) end }
    end
    -- Footer
    fill(H, K.bg)
    if canBack then button(2, H, "< Back", K.bar, function() return "back" end) end
    local hint = n > 1 and "\24\25 to browse" or ""
    local left, right = canBack and 11 or 2, W - 9       -- room between "< Back" and "Pick >"
    local hx = math.max(left, math.floor((W - #hint) / 2) + 1)
    if #hint > 0 and hx + #hint - 1 <= right then at(hx, H, hint, K.faint) end
    button(W - 7, H, "Pick >", K.pick, function() return "pick" end)

    local e, a, b, c = os.pullEvent()
    local act
    if e == "key" then
      if a == keys.up or a == keys.left then move(-1)
      elseif a == keys.down or a == keys.right or a == keys.tab then move(1)
      elseif a == keys.enter or a == keys.numPadEnter then act = "pick"
      elseif a == keys.backspace and canBack then act = "back" end
    elseif e == "char" and tonumber(a) and options[tonumber(a)] then
      sel = tonumber(a)
    elseif e == "mouse_click" then
      for _, r in ipairs(hits) do
        local inY = r.y and c == r.y or (r.y1 and c >= r.y1 and c <= r.y2)
        if inY and b >= r.x1 and b <= r.x2 then act = r.action(); break end
      end
    elseif e == "mouse_scroll" then
      move(a > 0 and 1 or -1)
    end
    if act == "pick" then return options[sel][1] end
    if act == "back" then return nil end
  end
end

---------------------------------------------------------------------------
-- A text box. Returns the text, or nil for "back".
---------------------------------------------------------------------------
local function ask(step, steps, question, about, default)
  local text = default or ""
  while true do
    frame(step, steps, question)
    local y = 5
    for _, line in ipairs(wrap(about, W - 2)) do at(2, y, line, K.dim); y = y + 1 end
    y = y + 1
    fill(y, K.bar)
    at(2, y, text:sub(-(W - 3)), K.text, K.bar)
    fill(H, K.bg)
    button(2, H, "< Back", K.bar, function() return "back" end)
    button(W - 7, H, "Next >", K.pick, function() return "pick" end)
    term.setCursorPos(2 + math.min(#text, W - 3), y)
    term.setTextColour(K.text); term.setBackgroundColour(K.bar)
    term.setCursorBlink(true)
    local e, a, b, c = os.pullEvent()
    term.setCursorBlink(false)
    local act
    if e == "char" then text = text .. a
    elseif e == "paste" then text = text .. a
    elseif e == "key" then
      if a == keys.backspace then text = text:sub(1, -2)
      elseif a == keys.enter or a == keys.numPadEnter then act = "pick" end
    elseif e == "mouse_click" then
      for _, r in ipairs(hits) do
        if c == r.y and b >= r.x1 and b <= r.x2 then act = r.action(); break end
      end
    end
    if act == "back" then return nil end
    if act == "pick" then
      text = text:match("^%s*(.-)%s*$")
      if text ~= "" then return text end
    end
  end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
term.setBackgroundColour(K.bg); term.clear(); term.setCursorPos(1, 1)
at(2, 1, "TURTLEMANCER SETUP", K.title)
term.setCursorPos(1, 3)

local M, why
while true do
  M, why = fetchManifest()
  if M then break end
  printError("Couldn't download the role list: " .. tostring(why))
  print("Press Enter to try again (Ctrl+T to give up).")
  read()
end

-- What is this device? Turtles have the turtle API; Smart Glasses have the smartglasses API.
local isTurtle  = turtle ~= nil
local isGlasses = smartglasses ~= nil
local function fits(tk)
  if tk == "turtle" then return isTurtle end
  if tk == "glasses" then return isGlasses end
  return not isTurtle and not isGlasses
end

-- Best guess, so re-setting up an existing machine is mostly pressing Enter
local label = os.getComputerLabel()
local first = ((label or ""):match("^%a+") or ""):lower()
-- A turtle from before the Oct 2026 rename (Digger-04, Rigger): suggest its new role and name
for _, t in pairs(M.types) do
  local nk = t.renamed and t.renamed[first]
  if nk and t.roles[nk] then
    label = t.roles[nk].name .. label:sub(#first + 1)
    first = nk
  end
end
local guessType = isTurtle and "turtle" or (isGlasses and "glasses" or "computer")
local guessRole = nil
for tk, t in pairs(M.types) do
  for _, rk in ipairs(t.order or {}) do
    local r = t.roles[rk]
    if r and first ~= "" and (rk == first or r.name:lower() == first) and fits(tk) then guessType, guessRole = tk, rk end
  end
end
-- Only one role on this type? Pre-pick it.
if not guessRole and M.types[guessType] and #(M.types[guessType].order or {}) == 1 then
  guessRole = M.types[guessType].order[1]
end

local NOTES = {
  computer = "This isn't a plain computer: computer roles may not work here.",
  turtle   = "This is a computer: turtle roles won't work here.",
  glasses  = "These aren't Smart Glasses: glasses roles won't work here.",
}
local typeOptions = {}
for _, tk in ipairs({ "computer", "turtle", "glasses" }) do
  local t = M.types[tk]
  if t then
    typeOptions[#typeOptions + 1] = { tk, t.name, t.about, t.details, (not fits(tk)) and NOTES[tk] or nil }
  end
end

local tk, rk, T, R, l
local step = 1
while true do
  if step == 1 then
    tk = menu(1, 3, "What are you setting up?", typeOptions, tk or guessType, false)
    -- Turtle and glasses roles need the real hardware; computer roles are allowed anywhere.
    if (tk == "turtle" and not isTurtle) or (tk == "glasses" and not isGlasses) then tk = nil else step = 2 end
    T = tk and M.types[tk]
  elseif step == 2 then
    local opts = {}
    for _, k in ipairs(T.order) do
      local r = T.roles[k]
      if r then opts[#opts + 1] = { k, r.name, r.about, r.details } end
    end
    rk = menu(2, 3, "Which role?", opts, rk or (guessType == tk and guessRole or nil), true)
    if rk then R = T.roles[rk]; step = 3 else step = 1 end
  elseif step == 3 then
    if R.label == "auto" then
      -- Named by its own program (Canaries get their number from the Foreman)
      local keep = label and label:lower():find(R.name:lower(), 1, true) and label or R.name
      local opts = { { "ok", "Save and reboot", "Label: " .. keep,
        ("A %s gets its name from the network when it starts, so there's nothing to type."):format(R.name) } }
      local a = menu(3, 3, "Ready", opts, "ok", true)
      if a then l = keep; break else step = 2 end
    else
      local suggest = (label and label:lower():find(R.name:lower(), 1, true)) and label or R.name
      l = ask(3, 3, "Name this " .. T.name:lower(), "Shown on the status board and in chat. Enter keeps the suggestion.", l or suggest)
      if l then break else step = 2 end
    end
  end
end

os.setComputerLabel(l)
local f = fs.open(CFG, "w")
f.write(textutils.serialize({ type = tk, role = rk, setAt = os.epoch("utc") }))
f.close()
if fs.exists("setup.lua") then fs.delete("setup.lua") end

term.setBackgroundColour(K.bg); term.clear()
fill(1, K.bar)
at(2, 1, "TURTLEMANCER SETUP", K.title, K.bar)
local y = 3
for _, line in ipairs(wrap(("Saved: %s, %s, labelled %s."):format(T.name, R.name, l), W - 2)) do
  at(2, y, line, K.good); y = y + 1
end
at(2, y + 1, "Rebooting to download its files...", K.text)
term.setCursorPos(1, y + 3)
os.sleep(2)
os.reboot()
