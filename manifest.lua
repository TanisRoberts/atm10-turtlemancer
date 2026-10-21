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
  gone = { "rigger.lua", "pigger.lua", "riggerplan.lua", "rigger_link.lua", "firecrest.lua" },
  -- Saved state/config under an old name: startup renames it (only if the new one doesn't exist yet).
  moved = { ["rigger.state"] = "weaver.state", ["rigger.cfg"] = "weaver.cfg", ["pigger.state"] = "miner.state",
            ["firecrest.state"] = "miner.state",
            ["rigger_link.cfg"] = "weaver_link.cfg", ["zigger.env"] = "seagull.env", ["zigger.state"] = "seagull.state",
            ["zigger.map"] = "seagull.map", ["tigger.env"] = "woodpecker.env", ["figger.env"] = "partridge.env" },

  types = {
    computer = {
      name = "Computer",
      about = "A computer that sits at the base",
      details = "The base's brains: storage, smelting, the mainframe, the Foreman, the MD and Nether Foremans, the Farmhand, the Architect, the Operator, GPS, the plastic factory, the neural lab and the art wall.",
      order = { "mainframe", "storage", "smelter", "foreman", "mdforeman", "nether", "farmhand", "architect", "operator", "gps", "plastic", "neural", "art" },
      roles = {
        mainframe = {
          name = "Mainframe",
          about = "Chat, alerts, island strip, status board",
          details = "The server. Chat commands and alerts (Chat Box), weather and nearby players "
            .. "(Environment Detector), a monitor wall showing every machine, and the butler: $dump, "
            .. "torch top-ups and warnings (Inventory Manager), welcomes, visitors and the storage "
            .. "lock (Player Detector). Needs an ender or wireless modem.",
          run = "mainframe",
          files = { "computer/mainframe/mainframe.lua", "computer/mainframe/island.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua",
                    "computer/mainframe/board.lua", "computer/mainframe/butler.lua",
                    "computer/mainframe/base_link.lua",
                    "computer/mainframe/dig_link.lua", "computer/mainframe/weaver_link.lua",
                    "computer/mainframe/farm_link.lua", "computer/mainframe/operator_link.lua", "computer/mainframe/operator_fmt.lua",
                    "computer/mainframe/ring.lua", "shared/envfile.lua" },
        },
        storage = {
          name = "Storage",
          about = "Sorts chests, search screen, fuels turtles",
          details = "The only computer that moves items. Sorts the input chests into barrels and "
            .. "drawers, search + take on its screen, tops up turtle fuel barrels, supplies Weaver "
            .. "and does the smelter's moves. Wired modem on the storage cable + wireless modem.",
          run = "storage",
          files = { "computer/storage/storage.lua", "shared/assignui.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua" },
        },
        smelter = {
          name = "Smelter",
          about = "Auto-smelting, fastest furnaces first, + a training furnace",
          details = "Keeps the furnaces busy from smelt.txt rules and one-off jobs, fastest tier "
            .. "first. Teach it new recipes with a training furnace. Storage moves the items. "
            .. "Wired modem on the storage cable; advanced monitor optional (3x2 is ideal).",
          run = "smelter",
          files = { "computer/smelter/smelter.lua", "computer/smelter/probe.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua" },
          once = { "computer/smelter/smelt.txt" },
        },
        foreman = {
          name = "Foreman",
          about = "The remote for every miner, in every dimension",
          details = "Every Canary, Firecrest and Starling on its monitor, with its dimension; tap one to set its "
            .. "layers, start or dock it, reboot or retire it. Canaries and Firecrests through their own Foreman "
            .. "(MD, Nether); Starlings directly. Needs an ender modem and an advanced monitor.",
          run = "foreman",
          files = { "computer/foreman/foreman.lua", "shared/assignui.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua",
                    "shared/fm.lua", "shared/fm_reg.lua", "shared/fm_barrels.lua", "shared/fm_draw.lua", "shared/fm_pages.lua",
                    "shared/fm_edit.lua", "shared/fm_cmd.lua", "shared/fm_net.lua", "shared/fm_remote.lua" },
        },
        mdforeman = {
          name = "MD Foreman",
          about = "Canary control + the Mining Dimension dock barrels",
          details = "Lives in the Mining Dimension by the Canaries' docks. Canary cards on its monitor (layers, START, "
            .. "dock, reboot, retire), and the barrels on its cable: empties the docks, gives the Canaries lava buckets, "
            .. "keeps the lava factory in empty buckets, sends the haul home through the output barrel (hopper -> "
            .. "ender chest), with an overflow barrel for when home is full. Ender modem + wired modem; /assign.",
          run = "mdforeman",
          files = { "computer/mdforeman/mdforeman.lua", "shared/assignui.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua",
                    "shared/fm.lua", "shared/fm_reg.lua", "shared/fm_barrels.lua", "shared/fm_draw.lua", "shared/fm_pages.lua",
                    "shared/fm_edit.lua", "shared/fm_cmd.lua", "shared/fm_net.lua", "shared/fm_remote.lua" },
        },
        nether = {
          name = "Nether Foreman",
          about = "Firecrest control + the Nether dock barrels",
          details = "Lives in the Nether by Firecrest's dock. Firecrest cards on its monitor (layers, START, "
            .. "dock, reboot, retire), and the barrels on its cable: empties Firecrest's dock, keeps "
            .. "what the Rules say in Nether stock, sends the rest home through the output barrel "
            .. "(hopper -> ender chest). Ender modem + wired modem; /assign for the barrels.",
          run = "nether",
          files = { "computer/nether/nether.lua", "shared/assignui.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua",
                    "shared/fm.lua", "shared/fm_reg.lua", "shared/fm_barrels.lua", "shared/fm_draw.lua", "shared/fm_pages.lua",
                    "shared/fm_edit.lua", "shared/fm_cmd.lua", "shared/fm_net.lua", "shared/fm_remote.lua" },
        },
        farmhand = {
          name = "Farmhand",
          about = "Control screen for the farm turtles",
          details = "Every farm turtle (Partridge, Woodpecker) on its monitor; tap one for rounds now, "
            .. "pause, re-map, reboot, its settings, where it is and what it has brought in. "
            .. "Needs a wireless or ender modem and an advanced monitor.",
          run = "farmhand",
          files = { "computer/farmhand/farmhand.lua", "computer/farmhand/farmhand_screens.lua", "computer/farmhand/farmhand_map.lua",
                    "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua" },
        },
        architect = {
          name = "Architect",
          about = "Weaver's control screen: map, orders, bill",
          details = "Everything about Weaver the builder on the computer's own screen: what he's "
            .. "doing, a map of the layer he's on, the island from the side, materials still "
            .. "needed, the corner markers, and build / stop / test / clear / reboot orders. "
            .. "Needs a wireless or ender modem; no monitor.",
          run = "architect",
          files = { "computer/architect/architect.lua", "computer/art/art_gfx.lua", "shared/weaverplan.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua" },
        },
        operator = {
          name = "Operator",
          about = "Runs the Extreme Reactors power plant",
          details = "Finds every reactor on its cable, switches each on below 30% and off above 90% of its "
            .. "buffer (operator.env), watches the inlet and outlet ports (Storage fills and drains them), lists "
            .. "what each reactor needs, has and is missing, and reports to the mainframe. Wired modem on the "
            .. "cable shared with the reactor and Storage + wireless or ender modem; a monitor shows the status.",
          run = "operator",
          files = { "computer/operator/operator.lua", "computer/operator/opplant.lua", "computer/operator/opdrivers.lua",
                    "computer/operator/oppolicy.lua", "computer/operator/opneeds.lua", "computer/operator/oprods.lua", "computer/operator/opctl.lua",
                    "computer/operator/opscreen.lua", "computer/operator/opwall.lua", "computer/operator/opdraw.lua", "computer/operator/opwizard.lua", "shared/envfile.lua",
                    "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua" },
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
          files = { "computer/plastic/plastic.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua" },
        },
        neural = {
          name = "Neural lab",
          about = "Sim chambers + fabs, kept to item targets",
          details = "Runs a wall of Hostile Neural Networks columns (chamber on top, its fab below, "
            .. "optional lamp) on its OWN cable: drips matrices into a column until storage has "
            .. "enough of what its fab makes (neural.txt), learns new columns and fab changes by "
            .. "itself. Dock barrel shared with storage. Needs a wireless or ender modem.",
          run = "neural",
          files = { "computer/neural/neural.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua" },
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
      details = "Mining, building, lumberjacking, farming, map-making and crafting turtles.",
      order = { "canary", "weaver", "woodpecker", "partridge", "seagull", "bowerbird" },
      roles = {
        -- One miner for every dimension (Oct 2026): Canary, Firecrest in the Nether, Starling in the End.
        -- The role id stays "canary" so existing Canaries' device.cfg keeps working.
        canary = { name = "Miner", about = "Miner: named by his dimension", run = "miner",
                   alsoNames = { "canary", "firecrest", "starling" }, labelName = "Canary",
                   details = "Digs a shaft at its dock and mines chunk by chunk at the layers its Foreman picks. "
                     .. "Named by dimension: Mining Dimension (or anywhere else) = Canary, one dock barrel; "
                     .. "Nether = Firecrest (Nether Foreman, one dock barrel, drinks lava with one empty bucket); "
                     .. "End = Starling (dump + fuel barrels). Pickaxe + ender modem.",
                   label = "auto",
                   files = { "turtle/miner/miner.lua", "turtle/miner/miner_base.lua", "turtle/miner/miner_move.lua",
                             "turtle/miner/miner_inv.lua", "turtle/miner/miner_lava.lua", "turtle/miner/miner_plan.lua",
                             "turtle/miner/miner_dock.lua", "turtle/miner/miner_setup.lua", "turtle/miner/miner_loop.lua" },
                   once = { "turtle/miner/junk.txt" } },
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
        bowerbird = { name = "Bowerbird", about = "Crafts matrices for the neural lab", run = "crafter",
                   details = "Keeps storage stocked with prediction matrices (iron, gold, glass panes, "
                     .. "clay). Crafty turtle + wireless or ender modem, parked at a dock barrel that "
                     .. "keeps those topped up. Never moves, needs no fuel.",
                   files = { "turtle/bowerbird/crafter.lua" } },
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
          files = { "glasses/hud/glasses.lua", "shared/ui.lua", "shared/ui_widgets.lua", "shared/ui_parts.lua", "shared/ui_motion.lua" },
        },
      },
    },
  },
}

-- Every turtle role gets the turtle core (docs/systems/turtle.md): one list here, appended to each role's files.
-- A new core file is added to this list only. (Aliases below share the role tables, so they get it too.)
local T = M.types.turtle
T.core = { "shared/turtlecore.lua", "shared/turtlecore_gps.lua", "shared/turtlecore_fuel.lua", "shared/turtlecore_dock.lua",
          "shared/turtlecore_chunk.lua" }
-- (The manifest runs with an empty environment: no ipairs, only plain Lua.)
for i = 1, #T.order do
  local files = T.roles[T.order[i]].files
  for j = 1, #T.core do files[#files + 1] = T.core[j] end
end

-- The turtles were renamed in Oct 2026 (birds). Devices still set up under an old role id boot through
-- the alias once; startup.lua then switches their device.cfg (and a label starting with the old
-- name, e.g. Digger-04 -> Canary-04) to the new one. Aliases aren't in `order`, so setup never offers them.
T.renamed = { digger = "canary", pigger = "canary", firecrest = "canary", rigger = "weaver",
              tigger = "woodpecker", figger = "partridge", zigger = "seagull" }
T.oldNames = { canary = "Digger", weaver = "Rigger",
               woodpecker = "Tigger", partridge = "Figger", seagull = "Zigger" }
T.roles.digger, T.roles.pigger, T.roles.firecrest, T.roles.rigger = T.roles.canary, T.roles.canary, T.roles.canary, T.roles.weaver
T.roles.tigger, T.roles.figger, T.roles.zigger = T.roles.woodpecker, T.roles.partridge, T.roles.seagull

return M
