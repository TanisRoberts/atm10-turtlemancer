# How we work: GitHub Issues

Tanis and three agent roles (PM, design, engineering) track everything in this repo's Issues. Nobody carries context between sessions in chat: it lives in issues, comments and the repo. Every session posts as Tanis, so a comment saying "Taking this." is how sessions tell each other apart.

Ideas usually start in the "Minecraft ATM10" claude.ai Project, where Tanis asks general questions. When something needs scripting, that chat writes a handover prompt for the PM, and Tanis pastes it into a PM session.

## Labels

Every open issue has exactly one `status:` label, and every issue past Backlog has exactly one `for:` label.

- **Status:** `status: backlog` (idea, not approved), `status: todo` (approved, can be taken), `status: in progress` (claimed), `status: test in game` (pushed, Tanis checks it in game), `status: done`.
- **Who acts next:** `for: pm`, `for: design`, `for: engineering`, `for: tanis`.
- **Priority (Todo only):** `priority: now`, `priority: next`, `priority: later`.
- **Kind:** `bug`, `feature`, `chore`, `question`.
- **Area:** `area: storage`, `area: smelter`, `area: miners`, `area: farm`, `area: neural`, `area: mainframe`, `area: weaver`, `area: ui`, `area: tooling`.

## The loop

1. **Find your work:** open issues with your `for:` label and `status: todo`, `priority: now` first, then `next`, then `later`, lowest number first. Skip anything whose body says "Blocked by #N" while #N is open.
2. **Claim it:** swap to `status: in progress`, comment "Taking this."
3. **Ask, don't guess:** one question per comment, starting with who it's for ("PM: …", "Tanis: …"), then swap the `for:` label to them.
4. **Finish it:**
   - Engineering works on its own branch `eng/<issue-number>-<short-name>`, then rebases on `origin/main` and merges into `main` (that's the release), comments what to reboot and any in-game steps, then sets `status: test in game` and `for: tanis`.
   - Tanis closes it when it works in game, or comments what went wrong and sets `status: todo` + `for: engineering`.
   - Design commits its spec to `docs/design/` and hands the issue to engineering.
   - Anything with no code change: close it with a one-line comment saying what was decided.

## Rules

- **Backlog → Todo is the PM's call.** An issue reaches Todo only with a "Done when" section and one priority. Tanis can bump anything.
- **One issue per session.** Start a fresh session for the next one; long sessions are what burns tokens.
- **Big features get split** into issues one session can finish.
- Don't edit shared docs just to log progress. The issue is the log.

## gh notes

Cloud sessions can't use GitHub GraphQL, so `gh issue create/list/edit` fail. Use the REST API:

- list: `gh api 'repos/TanisRoberts/atm10-turtlemancer/issues?labels=for:%20engineering,status:%20todo&per_page=50' --jq '.[] | "#\(.number) \(.title) [\(.labels|map(.name)|join(", "))]"'`
- read: `gh api repos/TanisRoberts/atm10-turtlemancer/issues/N` and `.../issues/N/comments`
- comment: `gh api repos/TanisRoberts/atm10-turtlemancer/issues/N/comments -f body='…'`
- swap a label: `gh api -X DELETE 'repos/TanisRoberts/atm10-turtlemancer/issues/N/labels/status:%20todo'` then `gh api repos/TanisRoberts/atm10-turtlemancer/issues/N/labels -f 'labels[]=status: in progress'`
- create: `gh api repos/TanisRoberts/atm10-turtlemancer/issues -f title='…' -f body='…' -f 'labels[]=status: backlog' -f 'labels[]=for: pm'`
- close: `gh api -X PATCH repos/TanisRoberts/atm10-turtlemancer/issues/N -f state=closed`
