# aj-log

## 2026-11-12 — work-band: a chosen port is remembered per worktree (v0.2.4)

- Why: every worktree of `alertd-core.git` started on 1999 instead of a random port from the
  configured range. A port picked once with Change port was stored under `port:<owner/repo>`,
  which all worktrees of a repo share, and a stored port wins over `server.ports`. The user:
  it should be per worktree; per repo makes no sense.
- `hooks/register.tsx`: the store key is `port:<worktree top folder>` (from
  `git rev-parse --show-toplevel`, new `worktreeTop`). Session start waits for that folder
  before reading the stored port; with no folder nothing is read or stored. The old
  `port:<owner/repo>` keys are no longer read.
- `hooks/register.test.ts`: the test git answers `--show-toplevel` with `/work/alertd-core`;
  the port tests use the new key; a new test checks that another worktree's port and an old
  per-repo key are both ignored.
- README sentence, the version bumped to 0.2.4, and the mod reinstalled. The stale
  `port:alert-d/alertd-core` (1999) was removed from the store file.

## 2026-11-10 — work-band: one ports list of ports and ranges (v0.2.3)

- Why: the user asked why there are two port settings, and wants one, like
  `1988, 3000, 1943-1960`.
- `hooks/settings.ts`:
  - `server.ports` holds single ports and `"from-to"` ranges, as an array
    (`[1988, 3000, "1943-1960"]`) or a string.
  - New `portEntries`, `firstPort` and `formatPorts`. `parsePorts` takes ranges.
  - The separate `server.portRange` setting is gone from the pane and setup. An old one still
    reads as a range at the front of the list, and saving the ports list folds it in.
- `hooks/register.tsx`:
  - `candidatePorts(preferred, entries, random)` tries the preferred port, then the entries in
    order, each range shuffled.
  - The session starts on the first entry, or a random free port when that entry is a range.
  - The toast for every port being busy shows the list.
- Tests: the candidate tests cover a mixed list. The settings tests cover parsing, the legacy
  `portRange` and formatting. The setup test answers `5173, 5174, 4100-4120`. 106 pass. The 10
  server and settings test failures are the same as before this change.
- README updated, the version bumped to 0.2.3, and the mod reinstalled.

## 2026-11-10 — work-band: no random port unless the config sets a range (v0.2.2)

- Why: the user wants the band never to fall back to a random port. Random has to be
  part of the config (`server.portRange`).
- `hooks/settings.ts`: `portRange()` is `undefined` unless `server.portRange` is set and
  parses. The built-in 1930-1980 default is gone, and `SUGGESTED_PORT_RANGE` only fills
  the setup prompt. The settings pane shows `off` instead of `off (fallback 1930-1980)`.
- `hooks/register.tsx`: `candidatePorts` with no range is the preferred port, then the
  configured `ports` list in order, with nothing shuffled. If every one is busy, the port stays
  and a toast says so (`/wb settings` can add ports or a range). With a range set, the behavior
  is the same as before.
- Tests: new tests cover the no-range candidates, a busy port moving to the next one in the
  list (1776 → 1791), and every port busy. The range tests now pass their range explicitly.
  107 pass. The 10 server and settings test failures are the same as before this change.
- Root README updated, the version bumped to 0.2.2, and the mod reinstalled.

## 2026-11-09 — diag: no second report when the full diag agrees (v0.1.4)

- Why: the user wants no repeat report when the full diag reaches the preliminary
  conclusion.
- `SKILL.md` §3 step 3: if the verdict and findings are the same, it says so in one line, plus
  the diag's path and any sharpened evidence such as the true first occurrence. Only a
  different conclusion gets a full final report, which starts with what changed.
- README updated, and the version bumped to 0.1.4.

## 2026-11-09 — diag: preliminary report while the full diag downloads (v0.1.3)

- Why: the user wants the download to run in the background while the agent writes a
  preliminary report.
- `SKILL.md` §3:
  1. Start the full download with `run_in_background`.
  2. Read the live server and post a **Preliminary** report without waiting.
  3. When the archive lands, confirm, correct or drop each preliminary finding against it,
     and post the final report saying what changed.
  4. If the download fails, finish from live reads.

  The duplicated fallback list is folded into step 4.
- README updated, and the version bumped to 0.1.3.

## 2026-11-09 — diag: the report shows its evidence (v0.1.2)

- Why: the user wants `/diag` to finish with evidence: logs and the like.
- `SKILL.md` §5: every finding has an **Evidence** block. It quotes the real log lines in a
  fenced `log` block with the archive path, line number and timestamp, gives the count and the
  first and last time, quotes the exact API fields, and shows cause before effect. A claim
  with no evidence is dropped. The report ends with what wasn't checked and the diag's path.
- README updated, and the version bumped to 0.1.2.

## 2026-11-09 — diag: download the full diag first (v0.1.1)

- Why: the user wants `/diag` to try the full diagnostics download before anything else.
- `SKILL.md` §3: step 1 is now `fs download` with no `--since`, into
  `~/.alertd/diag/<alias>/<timestamp>/`, unpacked and searched locally. It runs in the
  background while `health`, `ingest status`, `schedules` and `fs summary` run. Live log tails
  are only the fallback when the download fails (403, timeout, build limit), and the report
  says why.
- README updated, and the version bumped to 0.1.1.

## 2026-11-09 — diag: new `/diag` skill (v0.1.0)

- Why: the user wants `/diag <name>` to pull an AlertD server's diagnostics with
  `npm run alertd-server`, remember what each short name (e.g. `ltk`) points to after the
  first time, and with only a name, work out what is wrong from the diagnostics alone.
- New plugin `plugins/diag`: `skills/diag/SKILL.md`, `plugin.json`, `install.manifest`,
  `README.md`, plus marketplace and root README entries.
- Names: no new registry. The CLI already keeps aliases in `~/.alertd/servers.json`, so a new
  name is logged in with `login <url> --alias <name>` (asking for the URL once) and is known
  from then on.
- The script exists only in alertd-core, so the skill uses the current repo when it has the
  script, else a `~/projects/alertd-core.git` worktree (`develop` first). The build prints
  noise before the JSON, which the `ad` helper strips. Tested from this repo:
  `servers` and `--server develop health` returned clean JSON.
- Only a name: health → ingest → schedules → fs summary → newest log tails, and the
  `data/` archive (`fs download --since 6h`) into `~/.alertd/diag/<alias>/` when needed. The
  report starts with Healthy, Degraded or Down. Read-only.
- Installed globally with `./install.sh diag --global`.

## 2026-11-05 — work-band: the band comes back after an in-app /resume (v0.2.1)

- Why: the user saw the band missing in some alertd-core worktrees (e.g.
  feature-AL-4911-pg-connections). Each of those sessions had been switched to an older
  conversation with `/resume` inside a running Claude. That swaps in the resumed
  conversation's plugin state (`canServe` false) and fires no `session.start`. The
  module-level `answered = true` from the startup check survived the switch, so `isOn()`
  never checked the repo again: no band, `set_topic` unanswered, and `/wb` said "off for
  this repo". Reproduced in tmux: fresh session (band on) → `/resume <id>` → band gone.
- `hooks/register.tsx`: `answered` is now a session-state atom instead of a module
  variable, so it resets with `canServe` on `/resume`. The next prompt, turn or tool call
  checks the repo and turns the band back on. `types/index.d.ts` declares the new key.
- Verified live: after `/resume`, `set_topic` returns "The band shows: after fix" and the
  band draws again. The test kit can't simulate `/resume` (it refuses state writes from a
  test's hooks), so there is no unit test for it. The suite has the same 10 failures as
  before this change, all in the server and settings tests.
- Reinstalled the mod (`./install.sh work-band --global`): `~/.claude/mods/work-band` was
  an Oct 17 copy.

## 2026-11-04 — walkthrough: code is always syntax highlighted (v0.3.1)

- Why: the user asked for the walkthrough's code to use syntax highlighting.
- `SKILL.md` §6: every code block uses highlight.js 11.9.0 from cdnjs. The language class
  comes from the file extension, and the token colours come from the page's light and dark
  tokens. The code is highlighted first, then wrapped per line, so the added-line tint and
  callouts sit on top of the colours. Before │ after panels and diffs are highlighted too.
  Version 0.3.1.

## 2026-11-04 — walkthrough: always an artifact, as visual as possible (v0.3.0)

- Why: the user wants the walkthrough as a Claude artifact, not a markdown file, and as
  visual as possible. Another session had read the old markdown fallback as permission to
  skip the artifact.
- `SKILL.md` §4–6 rewritten. Every section and every stop gets a picture:
  - a numbers strip, and a hero diagram whose numbered nodes link to their stops
  - a route stepper, and a file map with tag pills and +/− bars
  - per stop: a locator plus a branch flowchart, timing sequence, before │ after panel,
    shape cards, value bar or line callouts, picked by what the stop does
  - a tests coverage grid
  Mermaid is themed from the page tokens. Prose is capped at ~350 words. It starts with
  Artifact `quickstart`.
- The markdown fallback is gone: with no Artifact tool it says so and stops. A PR comment,
  only when asked, holds the summary, the diagram and the link.
- Version 0.3.0; README, plugin.json and marketplace description updated; reinstalled into
  `~/.claude/skills/walkthrough`.

## 2026-11-04 — work-band: random port from a range

- Why: the user wants the band to pick a random port from a range, say 1930-1980, and check
  that it is free before using it.
- `settings.ts`: a new `server.portRange` setting (`"1930-1980"`), with `parsePortRange`,
  `portRange` (1930-1980 when unset or invalid) and `isRandomPort`. The settings pane has a
  "Random port range" row.
- `register.tsx`: at session start, a port picked with Change port still comes first. If
  there is none and `portRange` is set, the band shuffles the range and takes the first port
  `lsof` shows free, with no toast. Without a range it keeps the old behaviour, where a taken
  port falls back to the range (now 1930-1980, was a hardcoded 1920-1990).
  `candidatePorts` takes an optional preferred port and a range. `/wb settings` and
  `/wb setup` ask for the range ("Off" clears it).
- Tests: candidatePorts with no preferred port and with a custom range; a session with
  `portRange` set lands on the free port; parsePortRange and portRange. 105 pass. The 10
  that fail also failed before this change: those tests' `ui.ask` is never answered.

## 2026-10-17 — work-band works in any GitHub repo, with per-repo settings

- `hooks/settings.ts` (new, pure): the settings file `~/.claude/work-band.json`, keyed by
  `owner/repo`. It covers parsing the remote into `owner/repo`; Jira (`jiraSite`, `issueKey`
  with `keyPattern` and `projects`); the server (`serverKind` turbo, plain or none,
  `serverArgv`, `planArgv`, `serverEnv` with `portEnv`, `ports`, extra `env`, `serverMatch`
  for finding stray servers); and `detectServers` from `turbo.json` and `package.json`.
- `register.tsx`:
  - The band runs in any GitHub repo whose settings do not say `enabled: false`; no repo name
    is in the code.
  - Jira runs only when `jira.site` is set: no Jira calls and no Jira on the band otherwise.
    The merge notice says nothing of Jira then.
  - The server button shows only when a server is set. Its command, port variable, ports and
    env come from the settings. Turbo keeps its task row and plan; a plain server shows one
    `server` task whose lines are its logs.
  - The base branch with no PR comes from `gh repo view`, not `develop`. The remembered port
    is kept per repo (`port:<owner/repo>` in `$.store`).
- New commands:
  - `/wb settings` opens a pane listing this repo's settings; clicking one asks for a new
    value, through options or free text, and saves it.
  - `/wb setup` is a wizard: each setting in turn, the server's only when there is one, saved
    once at the end; dismissing it saves nothing.
  - `/wb` is registered in any GitHub repo, the band off included, so the settings can turn it
    back on.
- Wrote alertd-core's settings to `~/.claude/work-band.json`: Jira site, turbo serve,
  `WEB_PORT`, ports 1776/1791/1792 and `ORCHESTRATOR_SINGLETON_GATE=false`.
- Tests: the existing tests use that file through mocked `fs` and `env`. New tests cover
  another GitHub repo (band, no Jira, no server), a non-GitHub remote (nothing), a disabled
  repo (no band, `/wb` still there), Jira with no site (never called), a plain server (its
  command and `PORT`, a `server` task, no plan), the settings pane click-and-save, the wizard
  (questions in order, detected servers offered, saved once), and the wizard dismissed
  (nothing saved). Also `settings.test.ts` for the pure helpers. 111 pass.
- Version 0.2.0. Why: the user asked for the band to work outside alertd-core, Jira only
  with a declared site, alertd-core's settings created, and a settings UI and wizard.

## 2026-10-16 — work-band: the branch and Jira share the first row

- `register.tsx`: the band is now two rows, plus the task row when the server runs. The first
  has the branch and the Jira issue (key, status, title). The title is cut to whatever width
  the branch, key and status leave. The second has the PR, diff, checks, topic, server
  control and plan. The "move Jira to its own row when too wide" logic and `firstRowWidth` are
  gone, since Jira always has a row now. Why: the user asked for the branch and Jira on one
  line.
- Tests updated for the rows, and the width-measure test removed. 91 pass.

## 2026-10-16 — work-band shows the branch

- `register.tsx`: a `branch` atom is filled from `git branch --show-current` on each refresh
  (session start, every 2 min, after a turn). It is drawn dim at the start of the band's first
  row and cut to 40 characters. A detached HEAD shows nothing. `firstRowWidth` counts it, so
  the Jira title still moves to its own row when the row is too wide. Why: the user asked for
  the branch name on the band.
- `types/index.d.ts`: `branch: string` in the state contract.
- Tests: the band starts with the branch, and the width includes it. 92 pass.

## 2026-10-16 — work-band: a failed repo check no longer switches the band off for good

- `register.tsx`: `checkRepo` leaves `canServe` as it was when `git remote get-url origin`
  fails. Only a remote that answers and is not alertd-core turns the band off. Why: a session
  whose check failed (likely on `/clear` re-running session.start) kept the band off, and
  `set_topic` unanswered, for the rest of the session.
- While git has not answered, the band tries again from a 30 s timer armed at session start and
  from the turn, prompt and tool hooks. It stops at 5 tries, since outside a git repo git never
  answers. A match runs `activate` (`/wb`, `set_topic`, the PR poll, the port), which moved out
  of session.start.
- Once git has answered with another repo, the band never checks again. A hot reload forgets
  that, so it checks once more after one. The band's draw only reads the flag, since a render
  may not write state.
- Tests: a failed check is retried and turns the band on; another repo is checked once; a
  non-git folder stops after a few tries. 91 pass.
- Left `~/.claude/dev-mods/` alone: those are per-session dev copies, not this install.

## 2026-10-16 — work-band: the merge message states what happened, nothing to do

- `register.tsx`: `mergePrompt` now carries only facts: the PR number and title, the base
  branch, who merged it, when, the merge commit, the PR link, and the Jira key (or that there
  is none). It holds no instructions, Jira or otherwise. Who, when and the commit come from a
  single `gh pr view <n> --json mergedBy,mergedAt,mergeCommit` when the merge is seen
  (`parseMergeFacts`). Why: the user wants the band to report the action and leave what to
  do to the agent.
- `register.test.ts`: tests for the message with and without facts, for `parseMergeFacts`,
  and that the live merge message holds no instructions. 88 pass.

## 2026-10-16 — work-band: always tell the agent when the PR merges

- `register.tsx`: a hot reload of the mod cancelled the 2-minute PR poll, and nothing re-armed
  it, so an idle session never saw its PR merge. The poll is now armed through
  `ensurePolling`, at session start and on every draw of the band, so it comes back after a
  reload.
- `mergePrompt`: names the base branch. Besides updating the Jira issue, it tells the agent to
  do anything else the session or the project's instructions say should happen once the PR
  merges, and to say what it updated. Why: the user wants the agent to update whatever it
  needs to on a merge, not only Jira.
- 88 tests pass.

## 2026-10-15 — greenlight says what it will do and which workflows it watches

- `SKILL.md`: new step 0. Before anything else, Claude states the plan (merge, push, rerun a
  skipped integration check, fix failures, report). It shows a table of the workflows it will
  watch: one row per workflow, its check names, and which are required. The rows come from
  `gh pr checks --json workflow,name` and `--required`; without a PR, from the workflow files
  that trigger on `pull_request` or `push`. After the push, it names any check that is new or
  that never started.
- Version 0.5.0.
- Why: the user asked for the skill to explain what it will do and to list the workflows it
  will watch.

## 2026-10-15 — work-band: blinking that never stopped; duplicate servers after a reload

- `register.tsx`, the port check never ran. It waited for kill-port to finish, but turbo
  leaves kill-port marked running, so `server` blinked blue forever and never ran `curl`.
  The check now runs every 2 s from 2 s after the start, with no kill-port wait.
- `register.tsx`, the reload fix. Leaving the spawn stream kills only `npm exec`, not the
  turbo, yarn, orchestrator and `vite build --watch` under it. A hot reload also loses
  `child`, so pressing `server` started a second server beside the first: two were found in
  feature-tollforsettings, started by one session. Restart and Kill now find, through
  `ps`, every `turbo run serve` whose parent is this Claude process (`$PPID` of a `sh`
  run), and kill it with all its descendants. `serveTrees` is exported, with a test of
  its own. 88 pass.

## 2026-10-15 — work-band: `server` flashes blue until the port answers, then green

- `register.tsx`: starting the server begins a 500 ms blink. `server` alternates between blue
  and dim, and every 2 s it runs `curl -s -m 2 http://localhost:<port>`. While kill-port is
  still pending or running it skips the check, so an old server about to be killed does not
  count. The first answer (any HTTP response) sets `serve.up`, which turns `server` green
  and cancels the timer, so the port is never checked again. A restart clears `up`.
  Why: the user wants to see when the server actually serves, not just when turbo is running.
- `types/index.d.ts`: `Serve.up` and `Serve.blink`.
- `register.test.ts`: a new test checks that `server` is blue and not green before the port
  answers, green after, and that there are no checks after that. Two tests that expected
  green at once were updated. 87 pass.

## 2026-10-15 — work-band: keep the alertd-core gate across a hot reload

- `register.tsx`: the hooks now gate on the `canServe` atom instead of a module variable.
  Why: installing the mod hot-reloads it in running sessions without re-running
  `session.start`. The module variable reset to false, and the band disappeared in
  alertd-core sessions too. State survives a reload, so the band stays in alertd-core and
  stays off elsewhere. 85 tests pass.

## 2026-10-15 — work-band runs only in alert-d/alertd-core

- `plugins/work-band/hooks/register.tsx`: at session start the mod reads `git remote get-url
  origin`. Outside alert-d/alertd-core it returns at once: no `/wb`, no `set_topic` tool, no
  polling of gh or Jira, no band, and no topic prompt or nudge. Every other hook passes
  straight through. Why: the user wants the band only in that repo.
- `register.test.ts`: the "outside alertd-core" test now checks for no band, no command, no
  tool and no gh calls. 85 pass. Installed to `~/.claude/mods/work-band`.

## 2026-10-15 — greenlight fixes failing checks

- `SKILL.md`: added a step for failing checks. Claude reads `gh run view --log-failed`, fixes the
  code (never skipping or loosening the test), commits, pushes and waits again.
  - A failure in the infrastructure instead of the code is rerun once with `--failed`.
  - Claude stops after three attempts on the same check.
- Dropped `allowed-tools: Bash`, because fixing needs edits.
- Version 0.4.0.
- Why: the user asked for it to fix tests when they fail.

## 2026-10-15 — greenlight is a plain skill now, no script

- Deleted `plugins/greenlight/scripts/greenlight.sh` and its tests. `SKILL.md` is five steps:
  1. Fetch the default branch, read from `gh repo view`.
  2. Merge it into the current branch. Claude resolves conflicts and asks when a conflict
     needs a decision.
  3. Push.
  4. If the PR's required `integration` check shows `skipping`, run `gh run rerun` on that run
     once.
  5. Report from `gh pr checks`.
- Version 0.3.0. Updated the manifest, plugin.json, marketplace.json and both READMEs.
- Why: the user asked for it to be very simple. The script's PR mode also turned off when
  workflows were named, so it dispatched its own runs and never reran the PR's skipped
  integration check. The PR then showed 5 of its 8 checks.
- Reinstalling the script mid-run had also crashed a running copy, with "PENDING: unbound
  variable" and a syntax error. That cannot happen now that there is no script.

## 2026-10-14 — greenlight starts PR checks that did not run and reruns jobs that did not run

- `plugins/greenlight/scripts/greenlight.sh`: with an open PR, a `pull_request` workflow with no
  run on the pushed commit is dispatched on the branch when it has `workflow_dispatch`. Any run
  that completes with a job cancelled, skipped or never reaching a runner (or the run itself
  cancelled or a startup failure) is rerun once with `gh run rerun`; the script waits for the
  new attempt before polling and judges it. Real failures are never rerun. Why: some checks do
  not run unless rerun or started by hand.
- `greenlight.test.sh`: the fake `gh` answers `run rerun` and then serves `runs/<id>.rerun.json`;
  cases for a missing PR check being dispatched, a rerun that fixes it, a rerun that does not
  (one rerun only), and a real failure not rerun. 40 pass.

## 2026-10-14 — greenlight judges the pull request's own checks

- `plugins/greenlight/scripts/greenlight.sh`: in branch mode, when the branch has an open pull
  request (`gh pr view`), greenlight dispatches nothing. The push of the merge makes GitHub run
  the PR's checks, so it waits for the `pull_request` run of each workflow that triggers on
  `pull_request` on the pushed sha and judges those. A workflow whose filters skip the PR is
  listed, not failed; the default branch's required checks still have to be present and green.
  No run at all is a FAIL. A closed or merged PR, or none, falls back to dispatching. Named
  workflows still dispatch. Why: asked that it only run the tests the PR asks for.
- `greenlight.test.sh`: the fake `gh` answers `pr view` from `pr.json`; cases for judging an open
  PR's checks (nothing dispatched, push-only and manual workflows ignored), an open PR with no
  checks, and a merged PR falling back to dispatch. 36 pass.

## 2026-10-14 — greenlight leaves a conflicting merge for Claude to resolve

- `plugins/greenlight/scripts/greenlight.sh`: a merge that conflicts is no longer aborted. The
  script leaves it in progress, prints a `MERGE CONFLICT` block with one `- conflicted: <file>`
  line per file, and exits 3. A rerun with the merge still in progress is refused; once resolved
  and committed, the rerun pushes and tests it. Conflict markers committed in files the merge
  touched are refused before pushing. Why: merges often conflict, and the AI should resolve them
  rather than stopping.
- `SKILL.md`: how Claude resolves a conflict (read both sides and their history, keep both
  intents, no markers, run quick local checks, commit, rerun), when to stop and ask instead
  (a decision, a delete-versus-edit, a migration or lock file), never abort, reset or force-push
  on its own, and to list each resolved file in the report.
- `greenlight.test.sh`: conflict left in progress, an unresolved rerun refused, a resolved
  rerun passing and pushing, committed markers refused. 33 pass.

## 2026-10-14 — greenlight merges the default branch into the current branch and tests that

- `plugins/greenlight/scripts/greenlight.sh`: on any branch other than the default one it now
  fetches the default branch (still asked of GitHub, never assumed to be `main`), merges it into
  the current branch, pushes with `-u`, and dispatches CI on the current branch; the verdict's sha
  check is against the pushed merge and the verdict line reads `<branch>@<sha>`. It refuses on
  uncommitted changes to tracked files or a merge already in progress, aborts a conflicting merge
  and names the files, and keeps the merge locally when the push is refused. `--default`, or
  running on the default branch, keeps the old behaviour (test origin's default branch, touch
  nothing). `--latest` in branch mode merges and pushes nothing and fails when the pushed branch
  does not contain the default branch. Required status checks are still read from the default
  branch's protection, since those are what the merge must pass.
  Why: asked that greenlight pull the default branch into the current branch and test that,
  instead of testing the default branch.
- `greenlight.test.sh`: the 21 existing cases run with `--default`; 8 new cases cover the merge
  and pass, a run on the unmerged commit, a conflict (aborted, nothing pushed or dispatched),
  uncommitted changes, a detached HEAD, running on the default branch, a refused push, and
  `--latest` without the default branch. The fake `gh` resolves `HEAD_OF_CWD` in a run's sha to
  the merged commit. 29 pass.
- SKILL.md, the plugin README, the repo README, install.manifest, plugin.json and
  marketplace.json describe the new flow; version 0.2.0. Reinstalled globally.

## 2026-10-14 — work-band re-asks for the topic on every prompt

- `plugins/work-band/hooks/register.tsx`: a `prompt.submit` hook attaches one hidden context
  line to every prompt the person sends (`topicNudge`): the topic the band shows now, and
  "if this prompt moves the work to something else, call set_topic first; if it is the same
  work, leave it", or "no topic yet, call it with what this prompt is about". Meta prompts
  (engine notices) get nothing. `TOPIC_PROMPT` also says to call it again as one piece of
  work moves on (designing → building → testing, one bug to the next). Why: the band's
  topic was set once at session start and never again through a long session; the model
  heard about the tool once, in the system prompt, and nothing re-prompted it. The nudge is
  ~35 tokens per prompt at the tail of the transcript, so caching is untouched. A reminder
  riding on tool results every N calls was considered and left out: it would touch
  tool-result shapes the engine validates per tool, for a smaller gain.
- `register.test.ts`: the nudge with and without a topic, attached on a prompt, updated
  after set_topic, absent on a meta prompt. Installed copy in `~/.claude/mods/work-band`
  updated; a session restart loads it.

## 2026-10-14 — greenlight plugin

- `plugins/greenlight/`: new `/greenlight` skill. Runs CI on the repo's default branch on
  GitHub Actions, integration tests included, and prints `GREENLIGHT PASS` or `GREENLIGHT
  FAIL` with reasons. Why: asked for a skill that pulls the default branch and runs CI with
  the integration tests, with a script so the AI cannot assume the tests passed. CI runs on
  Actions rather than locally (chosen when asked), so the script only `git fetch`es the
  default branch to learn its sha and never pulls, merges or checks out: a dirty or diverged
  local checkout cannot block it (raised while reviewing the design).
- `scripts/greenlight.sh`: reads the default branch from `gh repo view`; parses each
  workflow's `on:` block (an awk pass, since yq isn't a given) so push-to-tags-only and
  manual-only workflows such as releases are never dispatched unless named; dispatches the
  CI ones with `gh workflow run`, waits for a new run id to appear (a dispatch that never
  starts is a FAIL), polls to completion, then takes one final `gh run view --json` snapshot
  per run and judges only that (asked: the verdict must come from a single call that shows
  everything passed, not pieced together from polling). Rules: run and every job `success`;
  run sha equals the fetched sha; an integration-pattern job exists, none of its test steps
  skipped, its log doesn't report zero tests; every required status check from branch
  protection and rulesets ran and succeeded (asked: make sure all required are started); a
  job that failed with zero steps is reported as never reaching a runner, quoting GitHub's
  annotation. `--latest` judges the newest completed runs on the sha instead of dispatching;
  a workflow whose triggers didn't fire for that commit is a note, not a FAIL, unless named.
  Default integration pattern widened to `functional|acceptance` after real repos used those.
- `scripts/greenlight.test.sh`: 21 cases against a fake `gh` on PATH answering from fixture
  dirs, each in a throwaway git repo with an origin and a dirty, diverged checkout.
- Real runs: `--latest` on driveday_arduino and open-atc; a live dispatch of `functional` on
  driveday_arduino, which FAILed because GitHub did not start the jobs ("recent account
  payments have failed or your spending limit needs to be increased"), which is what led to
  the zero-steps reason and the annotation quote.
- SKILL.md is a recipe (verdict line verbatim first, reasons as bullets, integration jobs
  from the table) with the no-verdict case spelled out as "did not complete". Registered in
  `marketplace.json`, `plugins/index`, root README; `install.manifest` for `install.sh greenlight`.

## 2026-10-12 — work-band mod, `mod` verb in install.sh

- `plugins/work-band/`: the work-band mod copied in from `~/.claude/mods/work-band`
  (plugin.json, hooks module, tests, state contract, tsconfig). `.claude-plugin/types/` is
  left out and gitignored: the engine writes it when the mod loads. Why: the mod lived only
  on this machine; the repo is where the other plugins are kept and installed from.
- `install.sh`: new `mod <dest> <desc>` manifest verb. Copies the plugin folder whole into
  `<install root>/<dest>` (minus the manifest and the engine's types) and adds that path to
  `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`, keeping the entries already
  there. `--uninstall` removes both. Why: a mod is loaded as a folder from that env var, not
  file by file through hooks in settings.json, so neither `file` nor `hook` fit. The env var
  is read only from the global settings, so a `--local` install registers its absolute path
  there. With no clone, the folder comes out of the repo's tarball, the owner/repo/ref read
  off `SKILLS_RAW`.
- Registered in `marketplace.json`, `plugins/index`, root README.

## 2026-10-12 — progress plugin

- `plugins/progress/`: new `/progress` skill. Two sections: what the PR/branch is about, then
  its state. Why: one command to answer "where is this PR at" instead of reading the PR page,
  the checks tab and `git status` separately.
- `scripts/progress.sh`: gathers branch vs base and vs remote, working tree, commits with
  bodies, diffstat, `gh pr view` fields, review threads via GraphQL (the CLI view has no
  `isResolved`), the last conversation comments, aj-log.md lines the branch added, and any
  Jira-style keys. Takes nothing (checked-out branch), a PR number, a branch or a PR URL.
  Why a script: the baseline run without it took five tool calls and 40k tokens to reach
  the same facts.
- SKILL.md is a positive recipe (fixed section shapes, bullet order) rather than a list of
  don'ts. Why: the baseline failure was shape, not discipline: shas, every passing check
  named, suggested shell commands.
- Registered in `marketplace.json`, `plugins/index`, root README; `install.manifest` for
  `install.sh progress`.

## 2026-10-08 — remote skills in install manifests

- `install.sh`: new `remote <owner/repo[@ref]> <path> <dest> <desc>` manifest verb. Downloads
  the repo tarball from codeload.github.com once per repo@ref and copies `<path>` (or every
  directory under `<path>/*`) into the install root, running text files through the
  manifest's `rewrite` rules. Why: to install skills from other people's repos, e.g.
  obra/superpowers, without vendoring them here.
- `install.sh`: `--skill NAME[,NAME]` narrows remote lines to the named skills. Why: install
  individual skills, not only the whole set. Refused with `all`, since it picks from one plugin.
- `install.sh`: `<plugin> --list` lists the skills a plugin's remote repos offer.
- `install.sh`: remote installs are recorded in `.claude/.install-receipts/<plugin>`;
  `--uninstall` (optionally with `--skill`) removes exactly what's recorded. Why: a `*` line's
  contents change upstream, so the manifest alone can't say what was installed.
- `plugins/superpowers/install.manifest` + `plugins/index`: installs obra/superpowers'
  skills, rewriting `superpowers:<skill>` to bare names.
- Verb reference in `plugins/adversarial-review/install.manifest` and README updated.

## 2026-10-12 — work-band shows the plan alone

- `plugins/work-band/hooks/register.tsx`: the account text at the end of the band is now
  just the plan (`Max`, `Team`, ...), no ` · <org>` after it. Why: a personal org is named
  `<email>'s Organization`, which swamped the band; only the first word was wanted.
- `register.test.ts`: the band test now expects `   Team` at the end, not `Team · AlertD`.
  `parseAuthStatus` still returns `org` for anything that wants it later.
- `register.tsx`: the plan is drawn in `magenta` (a raw colour, so it stays purple in every
  theme) and no longer dimmed. Why: asked for it in purple.
- `register.tsx`, `register.test.ts`: the Jira tool is `mcp__claude_ai_Atlassian_Rovo__getJiraIssue`.
  Why: the claude.ai connector was renamed from "Atlassian" to "Atlassian Rovo", so the old
  tool name no longer exists, `$.tool.check` never allowed it, and the band showed
  "allow getJiraIssue to show status" on every refresh. Calling the Rovo tool with the mod's
  exact input (site URL as cloudId, fields: status) returns the status JSON the regex reads.
- `register.tsx`: the Jira tool is no longer a hardcoded name. `pickJiraTool` takes the first
  `mcp__*__getJiraIssue` from `$.tool.list()`, so the band works with claude.ai "Atlassian Rovo",
  the older "Atlassian", or a local `atlassian` server. With none connected the band says
  "no Jira MCP connected"; when the tool isn't allowed it names the exact tool to allow.
  Why: the connector name differs between sessions and machines, and renaming broke the band.
- `register.test.ts`: the harness answers `tool.list` with nothing unless a test owns Jira;
  tests for picking the tool, reading status via a local server, and both error texts.
- `register.tsx`, `types/index.d.ts`: the band shows the Jira issue's title (its `summary`)
  after the key, not its status. `parseJiraTitle` reads it from getJiraIssue's JSON and
  undoes JSON escapes; the text truncates at the band's edge. Why: asked for the title.
- `register.tsx`: when the first row (PR · Jira · server · plan) would be wider than the band's
  `bodyColumns`, the Jira issue moves to a row of its own, its title cut to the band with an
  ellipsis (`fitWidth`), so the band is three rows and nothing word-wraps. `firstRowWidth`
  measures the row as drawn. Why: a long title wrapped the band onto extra lines.
- `register.test.ts`: `mountBand` takes a column count; tests for the measure, the cut, and
  the two-row / three-row layouts at 200 and 60 columns.
- `register.tsx`: the Jira title is drawn dim (grey), on the first row and on its own row,
  so the key stands out. Why: asked for a lighter grey.
- `register.tsx`: the Files button runs `/filetree` when the filetree mod
  (data-goblin/claude-code-filetree) is installed, found through `$.command.list()`; its
  refusal text (no fullscreen layout, terminal under 110 columns) is shown as a toast.
  Without it the band's own Files pane opens as before. Another plugin's pane can't be
  listed or closed, so the button opens or refocuses filetree rather than toggling it.
  Why: asked to use filetree when present.
- `install.manifest`: a tip says so. `register.test.ts`: both paths tested.
- `register.tsx`, `types/index.d.ts`: the band shows the Jira issue's status, abbreviated,
  between the key and the title: `AL-4169 TODO MATEOAS: route tables`. getJiraIssue is asked
  for `status` as well as `summary`; `parseJiraStatus` reads the status's own name (not its
  category's), and `abbreviateStatus` maps the common names (To Do → TODO, In Progress → PROG,
  In Review → REV, Done, Backlog → BKLG, Blocked → BLKD, ...) and otherwise takes a multi-word
  name's initials or a single word's first four letters. The status is drawn plain, between
  the bold key and the dim title, on the first row and on the issue's own row, and the
  own-row cut and `firstRowWidth` account for it. Why: asked for an abbreviated Jira status.
- `register.test.ts`: tests for the status parse, the abbreviations, the measure and both
  layouts with a status; the installed copy in `~/.claude/mods/work-band` was updated too.
- `register.tsx`: the Jira status on the band is a button. Clicking it calls
  getTransitionsForJiraIssue, drops the issue's current status, and shows the rest in a
  picker (at most four options, so a longer list is three at a time with `More…`; a name
  typed under Other also works). The picked transition goes to transitionJiraIssue, a toast
  says `AL-4169 → QA`, and the band re-reads the issue. Both tools are found on whichever
  Jira MCP is connected (`pickJiraTool` now takes the operation name); the click may open
  their permission dialog. Why: asked to change the status from the band.
- `register.test.ts`: tests for `parseTransitions`, `transitionPage` and the click-to-move
  flow; the installed copy in `~/.claude/mods/work-band` was updated too.
- `register.tsx`: when the transitions call is refused (e.g. auto mode denied it with its
  classifier unavailable) the band toasts the reason instead of "No status changes offered".
  Why: a click was denied by auto mode and the band showed nothing useful. Test added.

## 2026-10-13 — work-band picks a random port

- `plugins/work-band/hooks/register.tsx`: when the remembered port is taken at session
  start, `candidatePorts` now tries the remembered port and then 1920-1990 in a random order
  (Fisher-Yates over the range, `Math.random` by default, a test passes its own source),
  instead of 1776, 1791, 1792, 1793 on in a fixed order. The menu's choices and the 1776
  default are unchanged. Why: asked that the auto-chosen port be random and in 1920-1990,
  so two sessions on the same machine stop landing on the same next port.
- `register.test.ts`: the candidate test checks the range, no duplicates, and that the order
  follows the random source; the session-start test accepts any port in the range. The
  installed copy in `~/.claude/mods/work-band` was updated too.

## 2026-10-13 — work-band shows Claude's topic

- `plugins/work-band/hooks/register.tsx`: the mod registers a `set_topic` tool
  (`mcp__work-band__set_topic`, listed from turn one, in front of ToolSearch) that takes one
  to three short labels; a `prompt.compose` hook appends a session section telling Claude to
  call it when it starts on something and whenever the topic changes, only when the tool is
  on offer. The call is answered inside the existing `tool.call` hook (the engine takes one
  matcher-less hook per event per module), which trims and caps the labels (`parseTopics`),
  stores them in a `topic` atom and answers `The band shows: a · b`; a bad input is denied with
  the shape it wants. The band draws the labels in cyan after the Jira part, and
  `firstRowWidth` counts them when deciding whether Jira takes its own row.
  Why: asked for the band to show what Claude is working on now, by Claude telling it.
- `types/index.d.ts`: `topic: string[]` in the contract. `README.md`: one sentence on it.
- `register.test.ts`: `tool.register` is mocked in `startIn`; tests for `parseTopics`, the
  compose section (added with the tool on offer, not without), the band before and after two
  `set_topic` calls plus a denied one, and the width. The installed copy in
  `~/.claude/mods/work-band` was updated too; a session restart loads it.
- `register.tsx`: `set_topic` answers its result as text, not `{ topics }`: the engine checks
  an `mcp__`-named tool's result against MCP's output shape (a string or content blocks) and
  refused the object (`expected string, received object`), so the call failed in a live
  session though the tests passed. Test updated; installed copy updated.
- `plugins/walkthrough/`: new `walkthrough` skill plugin (SKILL.md, plugin.json, install.manifest,
  README) plus its marketplace entry and a README section. `/walkthrough [PR|branch]` writes a
  document touring a PR's code in reading order, one stop per idea with code, `file:line`, and why;
  it goes to a docs connector/Artifact when available, else an untracked `walkthrough-<PR>.md`.
  Why: asked for a skill that creates a code-walkthrough document for a PR.
- `plugins/work-band/hooks/register.tsx`: the band now shows the session's model before the
  subscription plan at the end of the second row (`Opus 5.5 · Max`). `modelLabel` turns the id
  from `$.session.model()` (`claude-opus-5-5[1m]`) into `Opus 5.5 1M`; it is read on every draw so
  a `/model` switch shows on the next one. Tests for `modelLabel` and the band's ending; README
  sentence; installed copy in `~/.claude/mods/work-band` updated.
  Why: asked for the work band to show the model in use, with the subscription.
- `plugins/walkthrough/`: `/walkthrough` reworked to be concise and visual, v0.2.0. The document
  is under ~120 lines: a **Shape** diagram chosen by what the change is (`flowchart LR` for a call
  path, `sequenceDiagram` for a request between services, `stateDiagram-v2` for a lifecycle, a
  before/after table for a data shape, nothing for one function), at most 12 nodes named as the
  code names them with changed nodes highlighted, ASCII where mermaid can't render; a **Files**
  map tagging each file `core`/`shape`/`wire`/`test`/`noise`; then 3–8 stops of 5–15 lines and
  1–3 sentences. It takes a description after the target: one naming part of the diff narrows the
  tour, one naming nothing in it (or given on the default branch) tours the code as it is from the
  entry point it names. Plugin README, manifest tips, marketplace entry and README section updated;
  `walkthrough` added to `plugins/index`, which it was missing from, so `install.sh` can install it.
  Why: asked for a code-walkthrough skill that defaults to the PR branch, can take a description,
  and is concise and visual.
- `plugins/walkthrough/skills/walkthrough/SKILL.md`: the walkthrough is delivered as an artifact.
  §6 now builds one HTML page in the scratchpad (mermaid from cdnjs at an exact version, the route
  as in-page links, `file:line` linked at the head sha, light/dark tokens) and publishes it with
  the `Artifact` tool; the markdown file at the repo root is the fallback when there is no
  Artifact tool. `allowed-tools` gains Artifact and Skill. README, plugin README, descriptions.
  Why: asked for it to create an artifact.
