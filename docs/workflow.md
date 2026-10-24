# How we work: GitHub Issues

Tanis and three agent roles (PM, design, engineering) track everything in this repo's Issues. Nobody carries context between sessions in chat: it lives in issues, comments and the repo. Every session posts as Tanis, so a comment saying "Taking this." is how sessions tell each other apart.

Ideas usually start in the "Minecraft ATM10" claude.ai Project, where Tanis asks general questions. When something needs scripting, that chat writes a handover prompt for the PM, and Tanis pastes it into a PM session.

## Labels

Every open issue has exactly one `status:` label, and every issue past Backlog has exactly one `for:` label. **A closed issue carries no `status:`, `for:` or `priority:` label.** Closed is done; it just sits where it is.

- **Status:** `status: backlog` (idea, not approved), `status: todo` (approved, can be taken), `status: in progress` (claimed), `status: test in game` (pushed, and there is something specific for Tanis to check in game). There is no `status: done`: closing the issue is done.
- **Who acts next:** `for: pm`, `for: design`, `for: engineering`, `for: tanis`. Only set a `for:` label to hand the issue to another role, or to Tanis when Tanis has something specific to do (see the rule below).
- **Priority (Todo only):** `priority: now`, `priority: next`, `priority: later`.
- **Kind:** `bug`, `feature`, `chore`, `question`.
- **Area:** `area: storage`, `area: smelter`, `area: miners`, `area: farm`, `area: neural`, `area: mainframe`, `area: weaver`, `area: ui`, `area: tooling`.

## The loop

1. **Find your work:** open issues with your `for:` label and `status: todo`, `priority: now` first, then `next`, then `later`, lowest number first. Skip anything whose body says "Blocked by #N" while #N is open.
2. **Claim it:** swap to `status: in progress`, comment "Taking this."
3. **Ask, don't guess:** one question per comment, starting with who it's for ("PM: …", "Tanis: …"), then swap the `for:` label to them.
4. **Finish it:**
   - Engineering works on its own branch `eng/<issue-number>-<short-name>`, then rebases on `origin/main` and merges into `main` (that's the release), comments what to reboot and any in-game steps, then sets `status: test in game` and `for: tanis`.
   - **Tanis gets an issue only for a specific test or action.** `status: test in game` + `for: tanis` is allowed only when the hand-over comment lists what Tanis should do in game and what they should see, as numbered steps (for example: "1. Reboot the smelter. 2. Train raw iron. 3. Reboot again. Expect: still learned."). If you can't write those steps, don't hand it over.
   - **Nothing to test? Close it.** Docs, tests, tooling and refactors with no visible change are closed by the engineer with a short comment (what changed, nothing to reboot).
   - Tanis closes a tested issue when it works, or comments what went wrong and sets `status: todo` + `for: engineering`.
   - When closing, remove the `status:`, `for:` and `priority:` labels. Keep the kind and area labels.
   - Design commits its spec to `docs/design/` and hands the issue to engineering.
   - Anything with no code change: close it with a one-line comment saying what was decided.

## Rules

- **Backlog → Todo is the PM's call.** An issue reaches Todo only with a "Done when" section and one priority. Tanis can bump anything.
- **One issue per session.** Start a fresh session for the next one; long sessions are what burns tokens. Projects keep this: the lead starts a fresh engineer session per sub-issue (see Projects).
- **Big features get split** into issues one session can finish.
- Don't edit shared docs just to log progress. The issue is the log.

## Projects

A bigger piece of work runs as a **project**, so it can run for a while without Tanis.

- **Parent issue:** labelled `project` (plus `feature` and its areas), title "Project: <name>", body with the goal, "Done when", and the sub-issues in build order. Its `status:`, `for:` and `priority:` labels work like any issue's; it goes to `for: engineering` when it's ready to run.
- **Sub-issues:** ordinary issues attached as GitHub sub-issues, each one-session-sized with its own "Done when" and "Blocked by" lines. Design sub-issues stay in the project.
- **The PM** creates the parent and sub-issues and decides the order.
- **The lead engineer** (one session, on Opus, `docs/team/prompts/lead-start.md`) runs the project: makes the big decisions, does the design sub-issues with Tanis, and starts a fresh engineer session (on Sonnet) for each sub-issue that's ready. Engineers follow `engineering-start.md` for their one sub-issue and report back to the lead.
- **Tanis** is only needed for design choices and in-game tests. In-game steps collect into one checklist on the parent; the run doesn't stop for them unless a later sub-issue depends on the result.
- **Done:** the parent closes when every sub-issue is closed.

GitHub Projects (boards) need GraphQL, which cloud sessions can't use, so projects are parent issues.

## gh notes

Cloud sessions can't use GitHub GraphQL, so `gh issue create/list/edit` fail. Use the REST API:

- list: `gh api 'repos/TanisRoberts/atm10-turtlemancer/issues?labels=for:%20engineering,status:%20todo&per_page=50' --jq '.[] | "#\(.number) \(.title) [\(.labels|map(.name)|join(", "))]"'`
- read: `gh api repos/TanisRoberts/atm10-turtlemancer/issues/N` and `.../issues/N/comments`
- comment: `gh api repos/TanisRoberts/atm10-turtlemancer/issues/N/comments -f body='…'`
- swap a label: `gh api -X DELETE 'repos/TanisRoberts/atm10-turtlemancer/issues/N/labels/status:%20todo'` then `gh api repos/TanisRoberts/atm10-turtlemancer/issues/N/labels -f 'labels[]=status: in progress'`
- create: `gh api repos/TanisRoberts/atm10-turtlemancer/issues -f title='…' -f body='…' -f 'labels[]=status: backlog' -f 'labels[]=for: pm'`
- close: `gh api -X PATCH repos/TanisRoberts/atm10-turtlemancer/issues/N -f state=closed`
