-- manifest.lua  --  every device type, role and the files each one gets.
-- Read by startup.lua (on every boot) and setup.lua (to build the menu).
--
-- files:   always kept up to date from the repo.
-- once:    only downloaded if missing (things you edit, or big data files).
-- run:     the program started after updating (a file name without .lua).
-- about:   one line for the setup menu.  details: a few more words, shown under the menu.
-- label:   "auto" = no label question; the program names the device itself (Diggers get a number
--          from the Foreman).
-- A file lands on the device under its own name (computer/storage/storage.lua -> storage.lua).
-- Adding a role = adding an entry here (and its folder in the repo). Nothing else to change.

return {
  common = { "startup.lua", "reset.lua" },

  types = {
    computer = {
      name = "Computer",
      about = "A computer that sits at the base",
      details = "The base's brains: storage, smelting, the mainframe, the Foreman, GPS and the plastic factory.",
      order = { "mainframe", "storage", "smelter", "foreman", "gps", "plastic" },
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
                    "computer/mainframe/dig_link.lua", "computer/mainframe/rigger_link.lua",
                    "computer/mainframe/farm_link.lua" },
        },
        storage = {
          name = "Storage",
          about = "Sorts chests, search screen, fuels turtles",
          details = "The only computer that moves items. Sorts the input chests into barrels and "
            .. "drawers, search + take on its screen, tops up turtle fuel barrels, supplies Rigger "
            .. "and does the smelter's moves. Wired modem on the storage cable + wireless modem.",
          run = "storage",
          files = { "computer/storage/storage.lua" },
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
          about = "Mining control for every Digger",
          details = "Overview of all Diggers on its monitor; tap one to set its layers, start or "
            .. "dock it, see where it is, or retire it. Hands out Digger numbers. Needs an ender "
            .. "modem and an advanced monitor.",
          run = "foreman",
          files = { "computer/foreman/foreman.lua" },
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
      },
    },
    turtle = {
      name = "Turtle",
      about = "A turtle that goes out and works",
      details = "Mining, building, lumberjacking and farming turtles.",
      order = { "digger", "rigger", "tigger", "figger" },
      roles = {
        digger = { name = "Digger", about = "Miner: shaft + expanding squares", run = "miner",
                   details = "Digs a shaft at its dock and mines squares at the layers the Foreman "
                     .. "picks. Gets its number from the Foreman. Pickaxe + ender modem.",
                   label = "auto",
                   files = { "turtle/digger/miner.lua" }, once = { "turtle/digger/junk.txt" } },
        rigger = { name = "Rigger", about = "Builder: follows a plan file", run = "rigger",
                   details = "Builds the island from a plan file, layer by layer, and fetches "
                     .. "materials from storage.",
                   files = { "turtle/rigger/rigger.lua" }, once = { "turtle/rigger/mossy.plan" } },
        tigger = { name = "Tigger", about = "Lumberjack: tree farm", run = "lumberjack",
                   details = "Plants, chops and replants a tree farm and drops logs at its dock.",
                   files = { "turtle/tigger/lumberjack.lua" } },
        figger = { name = "Figger", about = "Farmer: crops", run = "farmer",
                   details = "Harvests and replants crops, hoes new soil, drops produce at its dock.",
                   files = { "turtle/figger/farmer.lua" } },
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
          about = "Night vision + heads-up display",
          details = "Night vision AUTO (on when dark or in the Deep Dark, via an Environment "
            .. "Detector in the glasses) / ON / OFF, switched on the glasses' screen (1/2/3), and a "
            .. "HUD line (Overlay Module). Settings in glasses.env.",
          run = "glasses",
          files = { "glasses/hud/glasses.lua" },
        },
      },
    },
  },
}
