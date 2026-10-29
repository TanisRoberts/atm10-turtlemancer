-- smelter_screen.lua  --  smelter: screen basics (views, drawing helpers, touch/keys loop and the draw cycle)
-- Part of computer/smelter/smelter.lua; the shared state S is passed in (see smelter.lua).

return function(S)
local FRAME, FX, K, TEXT_SCALE, cfg, startTraining = S.FRAME, S.FX, S.K, S.TEXT_SCALE, S.cfg, S.startTraining

---------------------------------------------------------------------------
-- Screens: the monitor (touching a side) and the computer's own terminal share one design,
-- each with its own page.
---------------------------------------------------------------------------
local function newUi() return { page = "home", scroll = 1, notice = nil, confirm = nil } end
local function findMonitor()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.hasType(side, "monitor") then return peripheral.wrap(side), side end
  end
end
local mon, monSide = findMonitor()
local views = {
  { dev = function() return mon end, kind = "monitor", hits = {}, ui = newUi() },
  { dev = function() return term end, kind = "term", hits = {}, ui = newUi() },
}
S.ui = views[2].ui
S.frame = 0
S.cmdLine = nil          -- what's being typed on the terminal (nil = not typing)

local hits
S.d, hits = nil, nil
local HEX = "0123456789abcdef"
local BLIT = {}
for i = 0, 15 do BLIT[2 ^ i] = HEX:sub(i + 1, i + 1) end

local function at(x, y, text, fg, bg)
  S.d.setCursorPos(x, y)
  S.d.setBackgroundColour(bg or K.black)
  S.d.setTextColour(fg or K.white)
  S.d.write(text)
end
local function pad(s, w)
  s = tostring(s)
  if w <= 0 then return "" end
  if #s > w then return s:sub(1, w) end
  return s .. (" "):rep(w - #s)
end
local function centre(s, w)
  s = tostring(s):sub(1, w)
  local l = math.floor((w - #s) / 2)
  return (" "):rep(l) .. s .. (" "):rep(w - #s - l)
end
local function lr(x, y, w, left, right, fgL, fgR, bg)
  left = tostring(left)
  if right then
    right = tostring(right):sub(1, w)
    local room = w - #right - 1
    if #left > room then left = room > 0 and left:sub(1, room) or "" end
  end
  at(x, y, pad(left, w), fgL or K.lightGrey, bg)
  if right then at(x + w - #right, y, right, fgR or K.white, bg) end
end
local function bar(x, y, w, frac, colour)
  if w <= 0 then return end
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  at(x, y, (" "):rep(w), K.white, K.grey)
  if n > 0 then at(x, y, (" "):rep(n), K.white, colour) end
end
local function hit(x1, y1, x2, y2, fn) hits[#hits + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, fn = fn } end
local function button(x, y, w, rows, label, bg, fn, fg)
  for r = 0, rows - 1 do at(x, y + r, (" "):rep(w), K.black, bg) end
  label = label:sub(1, w)
  at(x + math.floor((w - #label) / 2), y + math.floor(rows / 2), label, fg or K.black, bg)
  hit(x, y, x + w - 1, y + rows - 1, fn)
end
local function smallButton(x, y, label, bg, fn, fg)
  at(x, y, " " .. label .. " ", fg or K.black, bg)
  hit(x, y, x + #label + 1, y, fn)
  return x + #label + 3
end
local function header(w, title, right, rightCol)
  at(1, 1, (" "):rep(w), K.cyan, K.grey)
  at(2, 1, title, K.cyan, K.grey)
  if right and #right + #title + 4 < w then at(w - #right, 1, right, rightCol or K.lightGrey, K.grey) end
  if S.ui.notice and os.clock() < S.ui.notice.untilT then at(2, 2, pad(S.ui.notice.text, w - 2), S.ui.notice.colour) end
end
local function say(text, colour, only)
  for _, v in ipairs(views) do
    if not only or v.ui == only then v.ui.notice = { text = text, colour = colour or K.lime, untilT = os.clock() + 6 } end
  end
end
FX.notify = function(text, colour) say(text, colour) end
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
local function go(page, extra)
  S.ui.page, S.ui.confirm, S.ui.scroll = page, nil, 1
  for k, v in pairs(extra or {}) do S.ui[k] = v end
end

-- Little helpers for the animations: a cheap repeatable "random" number
local function nz(a, b, c) return (a * 73 + b * 151 + (c or 0) * 37 + a * b * 7) % 97 end
local FLAME_FG = { K.red, K.orange, K.yellow, K.orange }
local FLAME_CH = { "\30", "^", "\30", "'" }


---------------------------------------------------------------------------
-- Draw everything
---------------------------------------------------------------------------
local function drawCmdLine(w, h)
  if not S.cmdLine then return end
  at(1, h, (" "):rep(w), K.white, K.grey)
  local shown = S.cmdLine
  if #shown > w - 4 then shown = shown:sub(-(w - 4)) end
  at(1, h, "> " .. shown, K.white, K.grey)
  at(3 + #shown, h, (S.frame % 4 < 2) and "_" or " ", K.yellow, K.grey)
end

local function draw()
  S.frame = FX.kit.anim == "off" and 0 or FX.kit.beat(4)      -- the kit's shared beat (4 a second)
  for _, v in ipairs(views) do
    S.d = v.dev()
    if S.d then
      hits = {}
      S.ui = v.ui
      local ok, err = pcall(function()
        if v.kind == "monitor" then S.d.setTextScale(TEXT_SCALE) end
        local w, h = S.d.getSize()
        if not w then return end
        S.d.setBackgroundColour(K.black); S.d.clear()
        if S.ui.page == "train" then S.drawTrain(w, h)
        elseif S.ui.page == "pick" then S.drawPick(w, h)
        elseif S.ui.page == "recipes" then S.drawRecipes(w, h)
        elseif S.ui.page == "rule" then S.drawRule(w, h)
        elseif S.ui.page == "factories" then FX.drawFactories(w, h)
        elseif S.ui.page == "fadd" then FX.drawFactoryAdd(w, h)
        else S.drawHome(w, h) end
        if v.kind == "term" then drawCmdLine(w, h) end
      end)
      v.hits = hits
      v.err = not ok and err or nil
      if not ok and v.kind == "monitor" then mon, monSide = findMonitor() end
    end
  end
end

-- Seconds until the screen next needs drawing without an event: the next beat while something moves (the
-- Train and Pick pages and the trainer card at 4 a second, cooking tiles at 2), else 1.
local function nextDraw()
  if FX.kit.anim == "off" then return 1 end
  local fast = S.cmdLine ~= nil or (cfg.trainer and S.trainSlots.inp ~= nil)
  for _, v in ipairs(views) do
    if v.ui.page == "train" or v.ui.page == "pick" then fast = true end
  end
  if fast then return math.max(FX.kit.nextBeat(4) - os.clock(), 0.05) end
  if S.activeCount > 0 then return math.max(FX.kit.nextBeat(2) - os.clock(), 0.05) end
  return 1
end

local function uiLoop()
  FX.kit.loadAnim("smelter.env")
  draw()
  local timer = os.startTimer(FRAME)
  while true do
    local e, a, b, c = os.pullEvent()
    local v, x, y
    if e == "timer" and a == timer then
      draw()
      timer = os.startTimer(nextDraw())
    elseif e == "smelter_draw" then
      draw()
    elseif e == "monitor_touch" and a == monSide then v, x, y = views[1], b, c
    elseif e == "mouse_click" then v, x, y = views[2], b, c
    elseif e == "mouse_scroll" then
      local u = views[2].ui
      u.scroll = math.max(1, (u.scroll or 1) + a)
      draw()
    elseif e == "char" then
      S.cmdLine = (S.cmdLine or "") .. a
      draw()
    elseif e == "paste" then
      S.cmdLine = (S.cmdLine or "") .. a
      draw()
    elseif e == "key" then
      if S.cmdLine then
        if a == keys.enter or a == keys.numPadEnter then
          local l = S.cmdLine; S.cmdLine = nil; S.runCommand(l); draw()
        elseif a == keys.backspace then
          S.cmdLine = #S.cmdLine > 0 and S.cmdLine:sub(1, -2) or nil; draw()
        end
      elseif a == keys.backspace then
        S.ui = views[2].ui
        if S.ui.page ~= "home" then go(S.ui.page == "pick" and "train" or (S.ui.page == "fadd" and "factories" or "home")) end
        draw()
      elseif a == keys.enter or a == keys.numPadEnter then
        S.ui = views[2].ui
        if S.ui.page == "train" and S.train.state ~= "learned" then
          local ok, why = startTraining()
          if not ok then say(why, K.orange, S.ui) end
        end
        draw()
      end
    elseif e == "peripheral" or e == "peripheral_detach" or e == "monitor_resize" then
      mon, monSide = findMonitor(); draw()
    end
    if v then
      S.ui = v.ui
      for _, r in ipairs(v.hits) do
        if x >= r.x1 and x <= r.x2 and y >= r.y1 and y <= r.y2 then r.fn(x, y); break end
      end
      draw()
    end
  end
end

S.BLIT, S.FLAME_CH, S.FLAME_FG, S.at, S.bar, S.button = BLIT, FLAME_CH, FLAME_FG, at, bar, button
S.centre, S.go, S.header, S.hit, S.lr, S.nz = centre, go, header, hit, lr, nz
S.pad, S.say, S.smallButton, S.views, S.wrap, S.uiLoop = pad, say, smallButton, views, wrap, uiLoop
end
