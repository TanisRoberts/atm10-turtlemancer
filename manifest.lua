-- manifest.lua  --  every device type, role and the files each one gets.
-- Read by startup.lua (on every boot) and setup.lua (to build the menu).
--
-- files:   always kept up to date from the repo.
-- once:    only downloaded if missing (things you edit, or big data files).
-- run:     the program started after updating (a file name without .lua).
-- about:   one line for the setup menu.  details: a few more words, shown under the menu.
-- label:   "auto" = no label question; the program names the device itself (Canaries get a number
--          from the Foreman).
-- A file lands on the device under its own name (computer/storage/storage.lua -> storage.lua).
-- Adding a role = adding an entry here (and its folder in the repo). Nothing else to change.

local M = {
  common = { "startup.lua", "reset.lua" },

  -- Files from before the Oct 2026 rename: startup deletes them from any device that still has them.
  gone = { "rigger.lua", "pigger.lua", "riggerplan.lua", "rigger_link.lua" },
  -- Saved state/config under an old name: startup renames it (only if the new one doesn't exist yet).
  moved = { ["rigger.state"] = "weaver.state", ["rigger.cfg"] = "weaver.cfg", ["pigger.state"] = "firecrest.state",
            ["rigger_link.cfg"] = "weaver_link.cfg", ["zigger.env"] = "seagull.env", ["zigger.state"] = "seagull.state",
            ["zigger.map"] = "seagull.map", ["tigger.env"] = "woodpecker.env", ["figger.env"] = "partridge.env" },

  types = {
    computer = {
      name = "Computer",
      about = "A computer that sits at the base",
      details = "The base's brains: storage, smelting, the mainframe, the Foreman, the Nether Foreman, the Farmhand, the Architect, GPS, the plastic factory, the neural lab and the art wall.",
      order = { "mainframe", "storage", "smelter", "foreman", "nether", "farmhand", "architect", "gps", "plastic", "neural", "art" },
      roles = {
        mainframe = {
          name = "Mainframe",
          about = "Chat, alerts, island strip, status board",
          details = "The server. Chat commands and alerts (Chat Box), weather and nearby players "
            .. "(Environment Detector), a monitor wall showing every machine, and the butler: $dump, "
            .. "torch top-ups and warnings (Inventory Manager), welcomes, visitors and the storage "
            .. "lock (Player Detector). Needs an ender or wireless modem.",
          run = "mainframe",
          files = { "computer/mainframe/mainframe.lua", "computer/mainframe/island.lua",
                    "computer/mainframe/board.lua", "computer/mainframe/butler.lua",
                    "computer/mainframe/base_link.lua",
                    "computer/mainframe/dig_link.lua", "computer/mainframe/weaver_link.lua",
                    "computer/mainframe/farm_link.lua" },
        },
        storage = {
          name = "Storage",
          about = "Sorts chests, search screen, fuels turtles",
          details = "The only computer that moves items. Sorts the input chests into barrels and "
            .. "drawers, search + take on its screen, tops up turtle fuel barrels, supplies Weaver "
            .. "and does the smelter's moves. Wired modem on the storage cable + wireless modem.",
          run = "storage",
          files = { "computer/storage/storage.lua", "shared/assignui.lua" },
        },
        smelter = {
          name = "Smelter",
          about = "Auto-smelting rules (smelt.txt)",
          details = "Watches the furnaces and keeps them busy from smelt.txt rules and one-off "
            .. "jobs. Storage moves the items. Just a wired modem on the storage cable.",
          run = "smelter",
          files = { "computer/smelter/smelter.lua" },
          once = { "computer/smelter/smelt.txt" },
        },
        foreman = {
          name = "Foreman",
          about = "Mining control for every Canary",
          details = "Overview of all Canaries on its monitor; tap one to set its layers, start or "
            .. "dock it, see where it is, or retire it. Hands out Canary numbers. Needs an ender "
            .. "modem and an advanced monitor.",
          run = "foreman",
          files = { "computer/foreman/foreman.lua" },
        },
        nether = {
          name = "Nether Foreman",
          about = "Firecrest control + the Nether dock barrels",
          details = "Lives in the Nether by Firecrest's dock. Firecrest cards on its monitor (layers, START, "
            .. "dock, reboot, retire), and the barrels on its cable: empties Firecrest's dock, keeps "
            .. "what the Rules say in Nether stock, sends the rest home through the output barrel "
            .. "(hopper -> ender chest). Ender modem + wired modem; /assign for the barrels.",
          run = "nether",
          files = { "computer/nether/nether.lua", "shared/assignui.lua" },
        },
        farmhand = {
          name = "Farmhand",
          about = "Control screen for the farm turtles",
          details = "Every farm turtle (Partridge, Woodpecker) on its monitor; tap one for rounds now, "
            .. "pause, re-map, reboot, its settings, where it is and what it has brought in. "
            .. "Needs a wireless or ender modem and an advanced monitor.",
          run = "farmhand",
          files = { "computer/farmhand/farmhand.lua" },
        },
        architect = {
          name = "Architect",
          about = "Weaver's control screen: map, orders, bill",
          details = "Everything about Weaver the builder on the computer's own screen: what he's "
            .. "doing, a map of the layer he's on, the island from the side, materials still "
            .. "needed, the corner markers, and build / stop / test / clear / reboot orders. "
            .. "Needs a wireless or ender modem; no monitor.",
          run = "architect",
          files = { "computer/architect/architect.lua", "computer/art/art_gfx.lua", "shared/weaverplan.lua" },
        },
        gps = {
          name = "GPS host",
          about = "One of 4 GPS towers for exact positions",
          details = "Tells turtles their exact X/Y/Z. Build 4, high up and not in a flat square "
            .. "(e.g. three at one height, one higher), each with an ender modem. It asks for its "
            .. "own coordinates once.",
          run = "gps_host",
          files = { "computer/gps/gps_host.lua" },
        },
        plastic = {
          name = "Plastic factory",
          about = "Latex taps -> rubber -> plastic, hands-off",
          details = "Runs the Industrial Foregoing plastic line on its OWN cable: drains the tree taps "
            .. "into the Latex Processing Unit, tops up its water, smelts the dry rubber and puts the "
            .. "plastic in a dock barrel that storage empties and keeps fuelled (/dock on storage).",
          run = "plastic",
          files = { "computer/plastic/plastic.lua" },
        },
        neural = {
          name = "Neural lab",
          about = "Sim chambers + fabs, kept to item targets",
          details = "Runs a wall of Hostile Neural Networks columns (chamber on top, its fab below, "
            .. "optional lamp) on its OWN cable: drips matrices into a column until storage has "
            .. "enough of what its fab makes (neural.txt), learns new columns and fab changes by "
            .. "itself. Dock barrel shared with storage. Needs a wireless or ender modem.",
          run = "neural",
          files = { "computer/neural/neural.lua" },
        },
        art = {
          name = "Art controller",
          about = "Monitor wall: turtle map, world map, art",
          details = "Shows off the island on an advanced monitor wall: every turtle live by height, "
            .. "the GPS pylons, Seagull's world map, and generative art you can poke. Three bars in "
            .. "the bottom-right corner switch screens. Needs an ender modem and an advanced monitor.",
          run = "art",
          files = { "computer/art/art.lua", "computer/art/art_gfx.lua", "computer/art/art_scenes.lua",
                    "shared/mapchunk.lua" },
        },
      },
    },
    turtle = {
      name = "Turtle",
      about = "A turtle that goes out and works",
      details = "Mining, building, lumberjacking, farming and map-making turtles.",
      order = { "canary", "firecrest", "weaver", "woodpecker", "partridge", "seagull" },
      roles = {
        canary = { name = "Canary", about = "Miner: shaft + expanding squares", run = "miner",
                   details = "Digs a shaft at its dock and mines squares at the layers the Foreman "
                     .. "picks. Gets its number from the Foreman. Pickaxe + ender modem.",
                   label = "auto",
                   files = { "turtle/canary/miner.lua" }, once = { "turtle/canary/junk.txt" } },
        firecrest = { name = "Firecrest", about = "Nether miner: drinks lava for fuel", run = "firecrest",
                   details = "Canary's cousin for the Nether: shaft + squares at the layers the Nether "
                     .. "Foreman picks, refuels from lava with his bucket, one dock barrel. Advanced "
                     .. "turtle, pickaxe + ender modem, one empty bucket.",
                   label = "auto",
                   files = { "turtle/firecrest/firecrest.lua" } },
        weaver = { name = "Weaver", about = "Builder: follows a plan file", run = "weaver",
                   details = "Builds the island from a plan file, layer by layer, and fetches "
                     .. "materials from storage.",
                   files = { "turtle/weaver/weaver.lua", "shared/weaverplan.lua" },
                   once = { "turtle/weaver/mossy.plan" } },
        woodpecker = { name = "Woodpecker", about = "Lumberjack: tree farm", run = "lumberjack",
                   details = "Plants, chops and replants a tree farm and drops logs at its dock. "
                     .. "Axe + wireless or ender modem; GPS makes it unlosable. Run from the Farmhand.",
                   files = { "turtle/woodpecker/lumberjack.lua", "shared/farmbot.lua" } },
        partridge = { name = "Partridge", about = "Farmer: crops", run = "farmer",
                   details = "Harvests and replants crops, hoes new soil, drops produce at its dock. "
                     .. "Hoe + wireless or ender modem; GPS makes it unlosable. Run from the Farmhand.",
                   files = { "turtle/partridge/farmer.lua", "shared/farmbot.lua" } },
        seagull = { name = "Seagull", about = "Cartographer: maps the island", run = "cartographer",
                   details = "Zig-zags over the island with a Geo Scanner and paints the world map on "
                     .. "the art wall. Geo Scanner + ender modem, no pickaxe. Needs GPS and a fuel dock "
                     .. "with open sky above it.",
                   files = { "turtle/seagull/cartographer.lua", "shared/mapchunk.lua" } },
      },
    },
    glasses = {
      name = "Glasses",
      about = "Smart Glasses you wear",
      details = "Advanced Peripherals Smart Glasses, worn on your head or in a Curios slot. "
        .. "Night vision, HUD, and a link back to the mainframe.",
      order = { "hud" },
      roles = {
        hud = {
          name = "HUD",
          about = "Night vision, HUD stats, aggro alerts",
          details = "Night vision AUTO / ON / OFF (glasses' screen, 1/2/3). HUD: clock, coords + "
            .. "facing, free inventory bar (with an Inventory Manager), and a top-middle alert when a "
            .. "mob is attacking you. Settings in glasses.env.",
          run = "glasses",
          files = { "glasses/hud/glasses.lua" },
        },
      },
    },
  },
}

-- The turtles were renamed in Oct 2026 (birds). Devices still set up under an old role id boot through
-- the alias once; startup.lua then switches their device.cfg (and a label starting with the old
-- name, e.g. Digger-04 -> Canary-04) to the new one. Aliases aren't in `order`, so setup never offers them.
local T = M.types.turtle
T.renamed = { digger = "canary", pigger = "firecrest", rigger = "weaver",
              tigger = "woodpecker", figger = "partridge", zigger = "seagull" }
T.oldNames = { canary = "Digger", firecrest = "Pigger", weaver = "Rigger",
               woodpecker = "Tigger", partridge = "Figger", seagull = "Zigger" }
T.roles.digger, T.roles.pigger, T.roles.rigger = T.roles.canary, T.roles.firecrest, T.roles.weaver
T.roles.tigger, T.roles.figger, T.roles.zigger = T.roles.woodpecker, T.roles.partridge, T.roles.seagull

return M
