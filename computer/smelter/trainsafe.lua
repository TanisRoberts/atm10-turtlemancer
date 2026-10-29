-- trainsafe.lua  --  keeps what the smelter learned, and cleans up a training run a power cut interrupted.
--
-- Config file: written as smelter.cfg.new, then swapped in, so a cut at any moment leaves a readable copy.
--   load: smelter.cfg, else smelter.cfg.new, else smelter.cfg.bak. A file that exists but can't be read is
--         moved to smelter.cfg.bad (never overwritten by an empty config).
-- Training marker: cfg.training = { input } is set while the trainer holds something the program put there
--   (a run, or the hand-over back to storage). If it is still set when the smelter boots, the run is thrown
--   away: the trainer is emptied into storage and nothing from that run is learned unless learn() had
--   already saved it whole.
local X = {}

local function parse(path)
  if not fs.exists(path) then return nil end
  local f = fs.open(path, "r")
  if not f then return nil end
  local s = f.readAll() or ""; f.close()
  local t = textutils.unserialize(s)
  if type(t) == "table" then return t end
end

function X.load(path)
  for _, p in ipairs({ path, path .. ".new", path .. ".bak" }) do
    local t = parse(p)
    if t then return t, p ~= path and p or nil end
  end
  if fs.exists(path) then
    if fs.exists(path .. ".bad") then fs.delete(path .. ".bad") end
    fs.move(path, path .. ".bad")
    return nil, nil, true
  end
end

function X.save(path, cfg)
  local f = fs.open(path .. ".new", "w"); f.write(textutils.serialize(cfg)); f.close()
  if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
  if fs.exists(path) then fs.move(path, path .. ".bak") end
  fs.move(path .. ".new", path)
end

-- Called every trainStep. `train` is the state table; active = the trainer holds something of ours.
function X.sync(cfg, save, train)
  local stt = train.state
  local active = stt == "starting" or stt == "fuelling" or stt == "cooking" or train.giveBack or train.clear
    or train.autoNext ~= nil
  local input = train.autoNext or train.input
  if active and input and (not cfg.training or cfg.training.input ~= input) then
    cfg.training = { input = input, at = os.epoch("utc") }; save()
  elseif not active and cfg.training then
    cfg.training = nil; save()
  end
end

-- At boot: returns the state the trainer step should start in, or nil when nothing was interrupted.
function X.recover(cfg)
  if type(cfg.training) ~= "table" then cfg.training = nil; return nil end
  return { state = "idle", giveBack = true, input = cfg.training.input, seen = true, restarted = true }
end

return X
