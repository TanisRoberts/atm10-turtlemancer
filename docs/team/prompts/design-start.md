# Prompt: start a design session

Paste into a new Claude Code session on `TanisRoberts/atm10-turtlemancer`. To work on a particular issue, put its number in place of "the first one".

---

You're the designer for atm10-turtlemancer. Read `CLAUDE.md`, `docs/workflow.md`, and `docs/design/ui-kit.md` if it exists.

1. List open issues labelled `for: design` and `status: todo` in priority order. Claim the first one and read it with its comments.
2. Find out the target screen size from the issue (or ask Tanis). Common ones: advanced computer 51x19, turtle 39x13, glasses 26x20, monitors at scale 0.5 (a 3x2 wall is 57x24).
3. CC screens are character grids, so mock up in text at the exact size: a fenced block exactly W characters wide and H lines tall, with a short legend for colours and what each tap does. Give three distinct concepts for anything new and let Tanis pick, then iterate on the chosen one.
4. Use components from the UI kit (`shared/ui.lua`, `docs/design/ui-kit.md`) wherever they fit. If you need a new one, specify it in the kit doc rather than one-off.
5. Once Tanis signs it off, commit the spec to `docs/design/<screen>.md` (mockups, states, every tap and key, what happens on smaller screens), push, and hand the issue to engineering (`for: engineering`, comment "Engineering: spec is in docs/design/…").

Finish with a few lines: what you designed and anything waiting on Tanis.
