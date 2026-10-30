-- storage_lock.lua  --  storage: the padlock screen the monitor shows while the butler says Tanis is away (or after /lock).
-- Drawn on a kit view with v:put at the biggest text scale it fits (gold, no motion); release() puts the normal scale
-- back. Part of computer/storage/storage.lua (docs/design/storage.md, "Locked screen").

local ART = {
  "   .-----.   ",
  "  / .---. \\  ",
  "  | |   | |  ",
  "  | |   | |  ",
  ".-'-'---'-'-.",
  "|           |",
  "|    .-.    |",
  "|    '-'    |",
  "|     |     |",
  "|     |     |",
  "'-----------'",
}
local LOCK_W, LOCK_H = 13, #ART + 4

local M = {}

local function centre(v, y, text, tone)
  if y < 1 or y > v.H then return end
  v:put(math.max(1, math.floor((v.W - #text) / 2) + 1), y, text, tone, "bg")
end

-- Draw the padlock on the whole view. The scale is worked out from the current size, so it changes once per lock
-- (every scale change fires a monitor_resize, which only re-measures the view).
function M.draw(v, why, base)
  local cur = v.t.getTextScale and v.t.getTextScale() or base
  local scale = 0.5
  for _, sc in ipairs({ 3, 2.5, 2, 1.5, 1, 0.5 }) do
    if math.floor(v.W * cur / sc) >= LOCK_W + 2 and math.floor(v.H * cur / sc) >= LOCK_H + 1 then scale = sc; break end
  end
  if scale ~= cur and v.t.setTextScale then
    pcall(v.t.setTextScale, scale)
    v:measure()
  end
  v.scaledForLock = true
  v:begin()
  if v.H < LOCK_H or v.W < LOCK_W then           -- tiny monitor: just the word
    centre(v, math.floor(v.H / 2) + 1, "LOCKED", "bad")
    return
  end
  local top = math.floor((v.H - LOCK_H) / 2) + 1
  local x = math.floor((v.W - LOCK_W) / 2) + 1
  for i, line in ipairs(ART) do v:put(x, top + i - 1, line, "gold", "bg") end
  centre(v, top + #ART + 1, "LOCKED", "bad")
  centre(v, top + #ART + 3, why == "manual" and "Locked from the computer" or "You are away from the island", "dim")
end

-- The monitor is unlocked: back to the normal text scale.
function M.release(v, base)
  if not v.scaledForLock then return end
  v.scaledForLock = false
  if v.t.setTextScale then pcall(v.t.setTextScale, base) end
  v:measure()
end

return M
