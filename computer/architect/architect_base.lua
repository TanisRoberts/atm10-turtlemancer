-- architect_base.lua  --  constants, saved state, little helpers, the log. A part of architect.lua.

PROTOCOL  = "tanis-weaver"
BASE      = "tanis-base"
STATE_FILE = "architect.state"
LOG_FILE  = "architect.log"
BUILDS    = "builds"
STALE     = 15        -- seconds without a status before the Weaver greys out
RESEND    = 2         -- seconds between repeats of anything we are waiting on
PART_MAX  = 256       -- cells in one layer message
LOG_KEEP  = 200

ui = require("ui")
plan2 = require("plan2")
plan2place = require("plan2place")

function readT(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  if not f then return nil end
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  return t
end
function writeT(path, t)
  local f = fs.open(path .. ".new", "w")
  if not f then return false end
  f.write(textutils.serialize(t)); f.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(path .. ".new", path)
  return true
end

-- S: what survives a reboot. n (number), wid (the Weaver's computer ID), name/hash/file (the build), site, started,
-- orderSeq, gaps (cells he skipped, full entries), held (cells left out above a gap, until it is filled)
S = readT(STATE_FILE) or {}
S.gaps, S.held, S.buried = S.gaps or {}, S.held or {}, S.buried or {}
S.orderSeq = S.orderSeq or 0
function save() writeT(STATE_FILE, S) end

-- R: what is live and not saved
R = { status = nil, seen = nil, stock = nil, stockSeen = nil, heard = {}, acked = {}, askedAt = {}, bills = -100,
      out = nil, read = nil, mfSeen = nil, supplyNote = nil, problemSince = nil }

function now() return os.clock() end
function comma(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
function ago(t)
  if not t then return "never" end
  local s = math.max(0, math.floor(now() - t))
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h"
end
function pretty(name)
  local s = tostring(name):gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end
function fit(s, n) return ui.text.fit(tostring(s), n) end
function hms(secs)
  local m = math.floor(secs / 60)
  if m < 60 then return m .. " min" end
  return math.floor(m / 60) .. " h " .. ("%02d"):format(m % 60)
end
function finished() return R.status and R.status.state == "done" end
function alive() return R.seen and now() - R.seen < STALE end
function label() return S.n and ("Architect-%02d"):format(S.n) or "Architect" end

-- The log: what he reported and every order sent (newest last), kept on disk
LOG = readT(LOG_FILE) or {}
LOG_N = 0
function clockText()
  local t = os.date and os.date("%H:%M", os.epoch and math.floor(os.epoch("local") / 1000) or nil) or ""
  return t
end
function addLog(text)
  LOG[#LOG + 1] = { clockText(), text }
  LOG_N = LOG_N + 1
  while #LOG > LOG_KEEP do table.remove(LOG, 1) end
  writeT(LOG_FILE, LOG)
end
