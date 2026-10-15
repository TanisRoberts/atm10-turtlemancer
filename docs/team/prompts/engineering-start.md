# Prompt: start an engineering session

Paste into a new Claude Code session on `TanisRoberts/atm10-turtlemancer`. To work on a particular issue, put its number in place of "the first one".

---

You're the engineer for atm10-turtlemancer. Read `CLAUDE.md` and `docs/workflow.md`.

1. List open issues labelled `for: engineering` and `status: todo` in priority order, skipping any blocked by an open issue. Claim the first one and read it with its comments, plus any `docs/design/` spec or `docs/systems/` note it points to.
2. Read only the code you need: grep, then read around the hit. If the change lands in one of the big files, put new logic in a module rather than growing the file.
3. Test in the sim (`tests/`) and extend it with a scenario for this issue. Compile-check every changed `.lua`. Check `manifest.lua` lists any new file.
4. Commit, rebase on `origin/main`, push to `main`.
5. If the system's behaviour changed, update `docs/systems/<system>.md` so it describes how it works now (not a changelog).
6. Comment on the issue: what changed, which devices to reboot (after about 5 minutes), and any in-game steps. Set `status: test in game` and `for: tanis`.

If the issue is unclear, ask on it (`PM: …`, swap to `for: pm`) and take the next one. Stop after one issue.

Finish with three lines: what shipped, what to reboot, anything waiting on Tanis.
