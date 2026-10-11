-- manifest.lua  --  every device type, role and the files each one gets.
-- Read by startup.lua (on every boot) and setup.lua (to build the menu).
--
-- files: always kept up to date from the repo.
-- once:  only downloaded if missing (things you edit, or big data files).
-- run:   the program started after updating (a file name without .lua).
-- A file lands on the device under its own name (computer/storage/storage.lua -> storage.lua).
-- Adding a role = adding an entry here (and its folder in the repo). Nothing else to change.

return {
  common = { "startup.lua", "reset.lua" },

  types = {
    computer = {
      name = "Computer",
      order = { "mainframe", "storage", "smelter" },
      roles = {
        mainframe = {
          name = "Mainframe",
          about = "Chat commands, alerts, island strip, status board, miner panel",
          run = "mainframe",
          files = { "computer/mainframe/mainframe.lua", "computer/mainframe/island.lua",
                    "computer/mainframe/board.lua", "computer/mainframe/miner_panel.lua",
                    "computer/mainframe/base_link.lua", "computer/mainframe/rigger_link.lua",
                    "computer/mainframe/farm_link.lua" },
        },
        storage = {
          name = "Storage",
          about = "Sorts the input chests, touch screen, fuels the turtles, supplies Rigger",
          run = "storage",
          files = { "computer/storage/storage.lua" },
        },
        smelter = {
          name = "Smelter",
          about = "Auto-smelting rules (smelt.txt); storage moves the items",
          run = "smelter",
          files = { "computer/smelter/smelter.lua" },
          once = { "computer/smelter/smelt.txt" },
        },
      },
    },
    turtle = {
      name = "Turtle",
      order = { "digger", "rigger", "tigger", "figger" },
      roles = {
        digger = { name = "Digger", about = "Miner: shaft + expanding squares",  run = "miner",
                   files = { "turtle/digger/miner.lua" }, once = { "turtle/digger/junk.txt" } },
        rigger = { name = "Rigger", about = "Builder: follows a plan file",     run = "rigger",
                   files = { "turtle/rigger/rigger.lua" }, once = { "turtle/rigger/mossy.plan" } },
        tigger = { name = "Tigger", about = "Lumberjack: tree farm",            run = "lumberjack",
                   files = { "turtle/tigger/lumberjack.lua" } },
        figger = { name = "Figger", about = "Farmer: crops",                    run = "farmer",
                   files = { "turtle/figger/farmer.lua" } },
      },
    },
  },
}
