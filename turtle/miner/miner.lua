-- miner.lua  --  shaft + expanding-square mining turtle (CC:Tweaked, ATM10 / MC 1.21.1)
--
-- One program for every miner. Who he is depends on the dimension he's set up in:
--   The Mining Dimension (allthemodium:mining), the Overworld, anything else: a CANARY (Canary-04).
--     Orders from the MD Foreman. ONE dock barrel: he empties his haul into it and asks for fuel (lava
--     buckets); nobody answering, he takes whatever fuel is in it. Empty buckets go back in.
--   The Nether: a FIRECREST (Firecrest-01). Orders from the Nether Foreman. Advanced turtle, ONE dock
--     barrel (a Dock on the Nether Foreman's cable: it empties it and puts in what he asks for), and
--     ONE empty bucket he never lets go of: under 25% fuel he scoops and drinks every lava source he
--     sees (1,000 each), whole pools at a time, until he's over 75% (both set on the Nether Foreman).
--     Junk (netherrack, basalt ...) is thrown away underground; the Nether Foreman sends the list.
--   The End: a STARLING (Starling-05). Orders from the Foreman. Dock: the DUMP barrel on one side and
--     the FUEL barrel on another (or above), both filled/emptied by hand (storage can't reach the End).
-- Carried to another dock or dimension, he offers to set up there (keeping his number); he never
-- tunnels to a dock far away (docs/systems/miner.md).
-- Needs: a mining turtle (diamond pickaxe) with an ender modem on its other side. Below the dock must
-- be free to dig. His number comes from his Foreman the first time he starts and is kept for good.
--
-- Position: he knows his dock's X/Y/Z, the way he faced and the dimension, and reports his exact
-- position. With GPS towers (the "GPS host" role, 4 of them) he also checks himself against GPS:
-- if he was carried somewhere he notices, works out which way he faces, and waits for an order;
-- then he digs down, tunnels to his shaft and comes up it. Without GPS he counts his moves.
--
-- What he does, once you press START on the Foreman (CHUNK BY CHUNK, "CBC"):
--   * his area is chunk rings around his dock's chunk, set on the Foreman: ring 0 = that chunk,
--     ring 1 = the 8 around it (3x3 chunks), ring 5 = 11x11 chunks ...
--   * digs a shaft straight down from the dock to the chosen Y range, then works ONE CHUNK at a time,
--     every level of it, before moving on: down through the levels in one chunk, up in the next.
--     Each level is a snake over the chunk's 16x16, 3 levels per pass: he walks the middle one and
--     digs the block above/below only if it's an ore
--   * with a chunk controller (Advanced Peripherals) in his bag he keeps his own chunk loaded: he
--     swaps it onto his modem's side for a moment in every new chunk (and every 45 s), so only the
--     chunk he's in is force-loaded. Without one: keep his area loaded (or stay near it)
--   * with a shulker box in his bag (any kind; Sophisticated Storage ones upgrade to huge) he puts
--     his ore in it when his slots run out, and only comes home when the box is full too
--   * comes home through the shaft when full or low on fuel, unloads (and unpacks the box), refuels,
--     goes back to the same chunk, level and block
--   * saves his position after every move, so he resumes after chunk unloads / restarts
--   * never digs another turtle (waits for it), or a cable, pipe, modem, computer, barrel, hopper,
--     ender chest or storage block (goes under or over it), so storage can run right through his area
--   * a chest (dungeon, fortress, bastion, stronghold...) in his way gets emptied BEFORE he digs it,
--     and one just above or below his tunnel gets emptied and left standing. Loot always comes home.
--     Too full to take it all: he goes home, unloads and comes back for the rest
-- Hold Ctrl+T to stop the program (the turtle stays where it is).
-- REBOOT from the Foreman: he finishes the block he's on (never mid-move or mid-turn), reboots,
-- pulls the latest files and carries on exactly where he was.

-- The program is in parts (miner_*.lua), loaded into ONE shared environment so a name defined in one part
-- (S, move, setStatus ...) is seen by all of them, as if they were one file. The computer's globals (turtle,
-- rednet ...) show through it. Fuel, GPS, the dock's report and chunk loading come from the turtle core.
local PARTS = { "miner_base.lua", "miner_move.lua", "miner_inv.lua", "miner_lava.lua", "miner_plan.lua",
  "miner_dock.lua", "miner_setup.lua", "miner_loop.lua" }
local M = setmetatable({ core = dofile("turtlecore.lua") }, { __index = _ENV })
for _, name in ipairs(PARTS) do
  local f = fs.open(name, "r")
  if not f then error("Missing " .. name .. ": reboot to update", 0) end
  local src = f.readAll(); f.close()
  assert(load(src, "@" .. name, "t", M))()
end
M.start()
