# Adversarial review

A reviewer that assumes your code is wrong, in a context window that never saw you
write it. Install it once and it applies to every repo you touch.

---

## What Bun actually did

From [Rewriting Bun in Rust](https://bun.com/blog/bun-in-rust) — Jarred Sumner's own
write-up of the Zig→Rust port. The section is called **Split context windows**:

> 1 implementer, 2 or more adversarial reviewers per implementer. The reviewer's only
> job: find bugs & reasons why the code does not work.

> The implementer doesn't review. The reviewer doesn't implement.

The reviewer's setup, verbatim:

> its context: only the diff. told to assume the code is wrong.

The loop (his pseudocode):

```js
let task;
while ((task = todoList.pop())) {
  const result = task();
  const feedback = await Promise.all([review(result), review(result)]);
  await apply(feedback, result);
}
```

Note the shape: **review is fan-out, apply is a separate step.** Two reviewers run
concurrently, neither of them fixes anything, and a third role applies the feedback.
During the compiler-error phase this ran per Rust crate as *1 fixes / 2 review / 1
applies* — 16 Claudes per workflow, 4 workflows in separate git worktrees, ~64
concurrent at peak, ~50 dynamic workflows over 11 days.

His stated reason it works is not about capability. It's about incentive:

> Usually with humans, the person reviewing the code is not the person who authored
> the code. The person writing the code wants to merge the code, which can bias their
> actions to ship before it's ready. **Claude is the same way.**

And one guardrail against reviewers rationalizing a bad fix:

> If you need a paragraph-long comment to justify why the workaround is OK, the code
> is wrong — fix the code.

**Three bugs it caught that compiled clean** — his examples, all of which "compiled;
all three looked plausible":

- `Box<uv::Pipe>` dropped while libuv still held the pointer → use-after-free, then
  double-free on the close callback. Fix: `Box::leak(pipe)`.
- `trunc` on a negative timespec: `-1.5` → `{sec: -1, nsec: -500_000_000}`, an invalid
  timespec. Fix: `floor`, which keeps nsec in `[0, 1e9)`.
- `unwrap_or` evaluating its argument eagerly, so the guarded `unwrap()` ran anyway.
  Fix: `unwrap_or_else`.

None of those are findable by a compiler, a linter, or a type system. They're semantic,
and they're exactly what a reviewer with no attachment to the code goes looking for.

### The part that gets left out of the summaries

Adversarial review was not what made a million lines trustworthy on its own. It was one
of three legs:

> A language-independent test suite with a million assertions, adversarial code review
> and when something does go wrong, fixing the process that generates the code instead
> of hand-fixing the code.

The test suite is the load-bearing one. Bun's tests are written in **TypeScript**, so
they don't depend on the runtime's implementation language — the same suite validates
the Zig version and the Rust version identically. 1,386,826 `expect()` calls on Debian
x64 alone (macOS arm64: 1,259,953; Windows: 1,007,544), 0 tests skipped or deleted.
That's a differential oracle: it can tell you the new implementation disagrees with the
old one, mechanically, at scale.

Adversarial review caught what the oracle couldn't. It didn't replace it.

Result: 19 known regressions across 6,502 commits (6,778 including merges), all fixed
before ship. ~$165,000 in API spend pre-merge — 5.9B uncached input tokens, 690M output,
72B cached reads.

**So: before you build the reviewer, ask what your oracle is.** A test suite that
actually fails when behavior changes, a golden-output corpus, a staging replay, property
tests. If you don't have one, an adversarial reviewer is a good habit and a real bug
catcher — but it is not the thing that lets you trust a million lines.

---

## Install

```bash
claude plugin marketplace add adrianj98/skills
claude plugin install adversarial-review@adrianj98-skills
```

Then `claude plugin disable adversarial-review@adrianj98-skills` to shelve the whole
thing, or the finer-grained toggle below to just stop the nudging.

### Without the plugin system

[`install.sh`](../../install.sh) copies the same files straight into `~/.claude/` or a
repo's `.claude/` — no marketplace, no plugin manager.

```bash
# every repo on this machine
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh \
  | bash -s -- adversarial-review --global

# just this repo, committed so teammates get it on clone
./install.sh adversarial-review --local

# just this repo, but keep the hook out of git
./install.sh adversarial-review --local --private
```

It merges into any `settings.json` you already have rather than overwriting it, skips the
hook entirely with `--no-hook`, shows you the plan with `--dry-run`, and reverses cleanly
with `--uninstall --global` / `--uninstall --local`. Local installs bake
`$CLAUDE_PROJECT_DIR` into the paths instead of absolute ones, so a committed `.claude/`
works from anyone's checkout.

The names differ slightly from the plugin install, since nothing is namespaced:
`/adversary` for the toggle, `/adversarial-review` for the workflow. What gets copied where
is [`install.manifest`](install.manifest) — `install.sh` itself is generic.

## What you get

```
agents/adversary.md          the reviewer — read-only, assumes the code is wrong
skills/adversary/SKILL.md    /adversarial-review:adversary — toggle, status, one-off run
workflows/review.js          /adversarial-review:review — 4 lenses + refutation voting
hooks/hooks.json             registers the Stop and SessionStart hooks
scripts/require-adversary.sh the Stop hook itself
scripts/mechanical-pass.sh   opt-in: runs your own linters first, hands the output over
scripts/agy-review.sh        opt-in: reviews with the Antigravity CLI instead of a subagent
scripts/session-base.sh      SessionStart: records where the session began
bin/adversary                the on/off switch (on PATH inside Claude's Bash tool)
```

---

### `agents/adversary.md` — the reviewer

A subagent definition. Invoking it spawns a *separate* Claude with its own context window
that never saw your conversation — no idea what you were trying to do, what you already
tried, or that you're in a hurry. That amnesia is the product. This is Bun's "split
context window."

Its frontmatter sets `disallowedTools: Write, Edit, NotebookEdit`. It physically cannot
modify code — not "instructed not to", the tools aren't in its hands. That's *"the
reviewer doesn't implement"* enforced structurally, so it can't drift into fixing things
and start defending its own fix.

The body carries the behavior: find concrete reasons the diff breaks, every finding needs a
concrete failure scenario, no style notes, plus a list of where bugs actually hide in
generated code — skimmed against the diff, not worked through end to end.

It opens with an **input contract** — what the prompt should carry (the diff itself, a scratch
directory, optionally the facts earlier rounds established, the previous round's findings, and
anything the repo's own linters already know) and what to do when one of those is missing: name
it in a line and review what is reviewable, never stop to ask.

It closes with a **verdict word**, and the vocabulary is exactly three: `block` when a confirmed
finding loses data, corrupts state that outlives the process, or crashes a path ordinary input
reaches; `concerns` when there are findings and none clear that bar; `clean` when there are none.
Derived, not felt — the reviewer computes it from its own findings, and the parent reports the
worst one verbatim rather than paraphrasing four reports into a shrug. Findings carry a severity
(`critical`/`high`/`medium`/`low`) from the same enum the deep workflow already uses, so both
paths speak one vocabulary.

### The turn ceiling

`maxTurns: 16`, in the frontmatter. Same trick as `disallowedTools`: a structural limit,
not a request the agent can reason its way past.

This is the setting that decides whether you keep the plugin, and it's a real trade. Reviewer
agents don't get slow by finding too much — they get slow by *looking*. One agent opens the
diff, then a caller, then the caller's caller, then greps the repo for a type, then runs the
suite. Multiply by four lenses and a ceiling that's too high costs you an hour at the end of
every turn; parallelism doesn't save you, since the lenses run concurrently and the slowest
single agent *is* the wall-clock cost. But too low a ceiling buys that speed with
`plausible` — a reviewer that can't reach the caller can't tell you whether the contract
actually broke.

Latency here is exploration-bound, not input-bound: across 24 instrumented runs a
5,266-line diff and a 94-line one took the same time to review (333s against 327s), and
tool calls tracked duration at about 8.6s each. The ceiling is the lever; the size of what
you feed it is not. Those runs were made under a 22-turn ceiling: mean 19 tool calls per run,
reaching 35, while the three best findings of that session came from the *shortest* runs, at
12, 13 and 15 calls. Every turn is also tokens, so the ceiling now sits at 16 — enough to
follow a diff outward to its callers, types and tests, and no tail past where the findings
came from.

A turn ceiling doesn't bound time, though, and agents can't read a clock. So the prompt
gives them something they can count: **at the 12th tool call, stop investigating and write
up.** Not "wrap up soon" — stop, with anything unchecked shipped as `plausible` or named in
one line. That checkpoint is what clips the straggler, which was 18% of all wall-clock and
run-to-run variance rather than any one slow lens. Opening files the diff doesn't touch,
running the full suite, and building a repro harness stay out of scope, finishing early is
the normal case, and "nothing found" is a legitimate two-line answer rather than something
it has to justify.

The ceiling is hard, and hitting it hands back whatever was written so far marked *partial* —
an investigation log with no findings section, which is the review wasted — so the prompt has
to make it land before the ceiling, not just aim vaguely at brevity. A turn is one
reasoning-and-tools cycle, however many calls it batches, so counting tool calls over-counts
in the safe direction. The deep workflow keeps the same ceiling
and buys depth by adding agents instead of lengthening them: one file under one lens should
finish well inside 16.

If the nudge starts feeling slow on your repo, this is the number to lower — and if findings
start drying up too, restore turns five at a time. If your diffs vary wildly in size, pass
the ceiling per invocation instead of fixing it in frontmatter.

Two more things the agent is told, both cheap and both paid for by measurement. When a
finding turns on *which* inputs reach a branch, enumerate input classes — empty,
whitespace-only, comment-only, delimiter-only, bare scalar, null, BOM, CRLF, zero value,
one, max — rather than trying two and concluding "unreachable"; that mistake gets a guard
deleted and costs whole rounds to undo, and it happened between lenses running the *same
model*, so it's a methodology failure a bigger model won't fix. And probe scripts go in the
scratch directory named in the prompt, never the repo, with `git checkout --`, `restore`,
`stash` and `reset` off-limits: read-only tooling still leaves `Bash` wide open, and
someone is editing these files while the reviewer reads them.

### Don't fetch the diff four times

`/adversarial-review:adversary run` captures the diff **once**, into a scratch file, and gives
each lens that file's path under a `## The diff` heading; the Stop hook's nudge hands off to the
same procedure. It used to paste the contents instead, which made the session re-emit the whole
diff as output once per lens — the dearest tokens there are — where a reviewer's one Read costs
almost nothing. Four agents
each running the same `git diff` is four copies of the same latency on the critical path, and
shrinking or sharding the input buys nothing anyway — see the ceiling above. The deep workflow
is the one exception: each of its agents is scoped to a single file and fetches that file's
diff itself, since a workflow script has no filesystem access to fetch it for them.

The same logic applies across rounds. Each lens ends its report with **Established by
execution**: the facts it settled by actually running something — a function's real return
values, a library's actual error text, which callers exist — one line each, with how. Those
get appended to `adversary-facts.md` in the scratch directory and pasted into the next
round under `## Already established — do not re-derive`. Without it, four lenses write four
throwaway probes for the same function every round; one measured session re-derived a single
lookup table about sixteen times.

Two files end up in that scratch directory, and they do different jobs: `adversary-facts.md`
carries what was *proven by running it*, so nobody proves it twice, and `adversary-findings.md`
carries what was *found*, so the next round can score it rather than hunt it.

**Cheapest form**, one agent, one pass:

```
Have the adversary subagent review my uncommitted changes.
```

### Round two is scored, not re-hunted

Fixing a finding is itself a change, so the hook fires again — and a reviewer that hunts from
scratch every time turns one review into a chain of ever-smaller ones. In the measured session
behind this design, rounds 4, 5 and 6 reviewed 94, 62 and 94 lines inside a function that only
existed because of round 1. Six rounds, 24 minutes, 1.32M tokens.

So the second round is a different job. Hand the reviewer the previous findings under a
`## Prior findings` heading and it scores them instead of hunting: one line each — `resolved`,
`partial` or `unresolved` — tied to what the code visibly does now, then at most two regressions
the fix batch itself introduced, then nothing. A fix the parent *claims* but the reviewer can't
see is `unresolved`; a fix answered mechanically, where the shape changed but the failure
scenario still runs, is `partial`. The budget drops from 12 tool calls to 6, and one reviewer
does it rather than four.

Two things put it back into a full review, and only these two: the fix *rewrote* rather than
patched — the diff touches files or functions no finding named — or every prior finding was
`plausible`, which means nothing was ever verified and there is nothing to score.

This is the mechanism that ends the chain. The line threshold below is no longer asked to do it
by staying silent.

The hook arms it: when a round reports, its findings go to `.git/adversary-findings.md` — inside
`.git/` because it has to outlive the session to be there when the fixes land — and the next
nudge asks for a scoring pass instead of a review. It emits **one** of those two instructions,
never both, because a model handed both picks one and either pick is wrong half the time.

A findings file that exists isn't automatically current, though, and a stale one is expensive: it
downgrades the next unrelated change to one reviewer that has been told not to hunt. So the hook
checks two things before believing it — the file was written after this session started, and the
change is small enough to plausibly *be* a fix round (not at the four-lens rung). Both failures
fall through to a full review, and the nudge says to delete the leftover. `SessionStart` sweeps
one older than a week.

### Findings two lenses found independently

The lenses run blind to each other, which makes their overlap worth something. When the same
finding comes back from two or more of them — matched on file *and* mechanism, since a race and
an off-by-one at the same line are two different findings — it's promoted one severity level and
marked `corroborated`.

Promotion moves **severity only, never confidence**. Agreement is evidence that a thing matters,
not evidence that it's true: in the same measured session, two lenses agreed a branch was
unreachable, a guard was deleted on their word, and they were both wrong — it cost three further
rounds to undo. Two `plausible`s stay `plausible`, at a higher severity.

### `workflows/review.js` — the thorough version

`/adversarial-review:review`

Control flow is plain JavaScript; only what's inside each `agent()` call is model-powered.
The model doesn't get to decide how many reviewers run or what clears the bar.

**Scope** — resolve the diff range and list changed files, skipping lockfiles and vendored
dirs. **Attack** — four adversaries per file, in parallel, each assigned one lens and told
the others cover the rest:

| lens | hunting for |
|---|---|
| `correctness` | evaluation order, boundaries, off-by-one, sign/overflow, empty and zero cases |
| `failure-paths` | error branches, cleanup, early returns, partial failure, swallowed errors |
| `lifetime-and-async` | ownership, use-after-close, races, unawaited work, cancellation, retries |
| `contract-drift` | changed types or return shapes that callers *outside* the diff still expect |

Splitting the lenses is deliberate: one reviewer told to "find everything" spreads thin and
returns four shallow observations. Four told to ignore three quarters of the space go deep.

**Verify** — every finding goes to three fresh agents whose job is to **kill** it. They
default to refuted when uncertain, each from a different angle: does that state even reach
this line / do the callers and tests make that input possible / can you actually reproduce
it. A finding needs 2 of 3 non-refuting votes to surface, tagged `CONFIRMED` (3/3) or
`PLAUSIBLE` (2/3). The refuters are the same read-only reviewer as the attackers — the third
angle is told to build a repro, and a repro belongs in scratch, not in your tree.

Pass options as workflow args: `{"range": "main...HEAD"}`, `{"refuters": 1}` to see more,
or a custom `lenses` array. The vote threshold follows the refuter count (never more than the
votes there are); set `threshold` to pin it.

### `hooks/` — the local nudge

A Stop hook, plus a SessionStart hook that exists only to give it an anchor. Stop hooks
fire when Claude tries to end its turn; exit `2` means *you're not done* and Claude keeps
working with the message as its instruction.

On a new state it tells Claude to hand the changes to the `adversary` subagent instead of
reviewing its own work. It writes its marker *before* blocking, so it fires at most once
per distinct state and can't loop — which also makes it a nudge rather than a wall.
Deliberate. The wall is CI.

Firing at Stop means the review lands *inside* the answer Claude was about to write, so the
message has to say what comes out the other side. Without that, the review report becomes the
whole reply: the user asked for a feature and gets back a verdict word and four findings, with
nothing about what was built. So the closing instruction puts it back in its place — the last
message is still about the work, and the verdict, the fixes and anything left open ride along
as a short block at the end of it.

**What counts as "the changes"** is the part that's easy to get wrong. `git diff HEAD` is
the obvious answer and it's wrong: the moment anything is committed — and plenty of setups
commit automatically at the end of a turn — it returns nothing, and the nudge goes silent
exactly when there is most to review. So the range is anchored instead:

1. the commit HEAD was at when this hook last nudged; anything before that has been through
   a review already,
2. failing that, where the session started — `scripts/session-base.sh` records `HEAD` on
   SessionStart, one file per session under `.git/`, swept after a week,
3. failing that, `HEAD`, i.e. the old uncommitted-only behaviour.

Both anchors are checked with `merge-base --is-ancestor` first, so a rebase, reset or pull
can't leave the hook diffing against a commit that is no longer on this line of history.
The nudge names the resulting range (`git diff <sha>`) in its message, because a reviewer
left to guess will run `git diff HEAD` and find nothing.

Untracked files are carried alongside the diff and listed by name: a file Claude created
but never staged is invisible to `git diff`, and a brand-new file is exactly what you want
read. The marker fingerprints file *contents* rather than diff text, so the same code
doesn't come back for a second review when it crosses from untracked to committed, and the
anchor advances to the commit once the work it covered lands there.

Edits that were already in the tree when the session opened are yours, not the session's.
`SessionStart` fingerprints them alongside the anchor, and a Stop that leaves them exactly as
they were stays quiet — asking a question no longer gets you a review of your own half-finished
branch. Once Claude changes anything, they're inside the range like everything else.

A nudge you hit automatically has to be cheap, or you start turning it off. Two things keep
it that way. The lenses run **in parallel**, so two of them cost about one agent's
wall-clock. And each reviewer runs on **Haiku**, capped at **16 turns** (see below), so a lens
can follow a contract to its callers but can't wander off into the codebase for an hour, and
what it does spend is spent at the cheapest rate going. Wall-clock is only half of cheap; the
other half is tokens, which is why the automatic path stops at two lenses.

It also stays quiet on changes that don't earn it: docs and licence files are never counted —
not towards the threshold and not in the fingerprints — and a change under 40 code lines is
skipped entirely. Move that line with `ADVERSARY_MIN_LINES` (`0` reviews everything):

```bash
ADVERSARY_MIN_LINES=0 claude      # review everything
ADVERSARY_MIN_LINES=300 claude    # only sizeable diffs
```

Above the line, the *number of lenses* scales rather than the decision to review at all. Four
reviewers on a two-file fix is most of what a review costs and little of what it returns:

| changed code lines | lenses |
| --- | --- |
| under 40 | none — the hook stays quiet |
| 40–600 | `correctness` |
| over 600, or 8+ files | `correctness`, `failure-paths` |
| only when asked (`ADVERSARY_LENSES=all`, `run all`) | all four |

One thing a line count can't see, so the skill says it in a line: add `contract-drift` at any
size when the diff changed an exported signature, a return type, or a public nullability.
`ADVERSARY_LENSES=all`, or a comma-separated list, overrides the ladder when it guesses wrong.

Two more things the nudge says — it is otherwise a few lines that hand off to the skill, which
holds the procedure — both from the literature rather than from this plugin's own
measurements. **Fix only what a reviewer marked `confirmed`.** Same-model reviewers fanned out
without a filter share their true positives and add their false ones — on real PRs, adding a
second reviewer lowered F1 — so the hook path, which has no refutation vote, leans on the
reviewer's own confirmed/plausible split instead: a plausible finding is mentioned, never acted
on. And the reviewer runs on **Haiku** by default (`model: haiku` in the agent's frontmatter):
cheap, and not the model that wrote the code — self-preference in LLM judges is measured, not
hypothetical. **`ADVERSARY_MODEL`** spawns the reviewers on something stronger when a change
deserves it.

```bash
ADVERSARY_MODEL=opus claude    # a stronger reviewer than the default Haiku, for this session
```

### Handing over what a linter already knows

impeccable — the design plugin — runs a compiled detector on *every* edit and a model reviewer
only at Stop, and tells the reviewer plainly: "do not run a second detector pass; mechanical
findings belong to the parent's hooks." That's the right split. A reviewer that spends three of
its fifteen tool calls rediscovering what `tsc` prints in half a second is wasting the half of
the budget that could have followed a contract to its callers.

`scripts/mechanical-pass.sh` is the cheap tier. Give it your own checks and it runs them once,
before the nudge, and embeds the output under a heading the reviewers are told to treat as
already taken:

```bash
ADVERSARY_CHECK="npm run lint --silent" claude     # one command, this session
echo 'cargo clippy --quiet' >> .git/adversary-checks  # persistent, per repo
```

Two deliberate constraints. **It is opt-in** — there is no default command, because guessing a
repo's build tooling and running it in a Stop hook is how you get a plugin people turn off. And
**the config never comes from a tracked file**: `.git/adversary-checks` lives inside `.git/`,
which no clone carries, so a repo you check out can't ship commands that run on your first Stop
hook. Each check gets 10 seconds (`ADVERSARY_CHECK_TIMEOUT`), output is capped, and a command
that hangs, exits non-zero or doesn't exist is reported as "did not complete" — the review goes
ahead without it. It never blocks.

Two details that only showed up by measuring, both about the same thing — a check you kill is not
a check that stopped. Its output goes to a file rather than up a pipe, because a background child
holding the inherited stdout blocks the read long after the timeout fired (measured: 8 seconds
under a 2-second timeout). And each check gets its *own* file, because that same orphan keeps
writing at its own offset, straight into the next check's output if they share one. A timeout of
`0` is rejected rather than honored: both `timeout 0` and perl's `alarm 0` mean "no alarm at all",
which would quietly remove the only bound there is.

### Reviewing with the Antigravity CLI instead

Opt-in. If you have Google's Antigravity CLI (`agy`) installed, the reviewers can run there
rather than as Claude subagents:

```bash
ADVERSARY_RUNNER=agy claude                  # this session
# or persist it: "env": { "ADVERSARY_RUNNER": "agy" } in ~/.claude/settings.json
```

`/adversarial-review:adversary run` — and so the Stop hook's nudge, which hands off to it — then
calls `scripts/agy-review.sh` once per lens instead of spawning a subagent. The script sends the
same reviewer instructions (`agents/adversary.md`, minus its frontmatter) and the diff to
`agy -p`, and prints a report in the same format, so synthesis, the findings file and scored
rounds all work unchanged. Nothing is installed into Antigravity; Claude Code stays the driver.

Two reasons to want it. The review spends Antigravity quota instead of Claude tokens — the
Claude side is one Bash call per lens plus reading the report. And the reviewer is a different
model family from the one that wrote the code, which is the strongest answer to self-preference
there is.

It stays read-only structurally, not by request. In print mode `agy` cannot prompt, so any tool
that needs permission — every shell command — is auto-denied; the reviewer is left with agy's
built-in file viewing and search. `--mode plan` and `--sandbox` sit behind that. The price is
that nothing can be *run*: a finding is `confirmed` by tracing only, and **Established by
execution** is always empty. There is no turn ceiling either, only `--print-timeout`.

| variable | default | |
| --- | --- | --- |
| `ADVERSARY_AGY_MODEL` | `gemini-3.8-flash-medium` | anything `agy models` lists |
| `ADVERSARY_AGY_TIMEOUT` | `300s` | the backstop a turn ceiling would have been |

If `agy` is missing, times out, or answers without a verdict line, the script exits 3 and the
skill runs that lens as the ordinary subagent — a failed run is never read as a clean review.

### `bin/adversary` — the off switch

Claude Code has no per-hook toggle: `/hooks` is a read-only viewer, there's no
`enabled: false` key, and the only built-in switch is `disableAllHooks: true`, which kills
every hook you have. So the toggle is homemade, and the Stop hook asks it before doing
anything.

From a session: `/adversarial-review:adversary off` (also `on`, `status`, `clear`, `run`).

From a shell, where `$P` is the installed plugin root under `~/.claude/plugins/`:

```bash
bash $P/bin/adversary status    # what's active and why
bash $P/bin/adversary off       # this repo only
bash $P/bin/adversary on
bash $P/bin/adversary off --all # everywhere
bash $P/bin/adversary clear     # drop the repo override, inherit global again
```

Want plain `adversary on|off`? `chmod +x $P/bin/adversary` once — git-over-API can't set
the exec bit, so nothing in the plugin depends on it. Resolution order, first match wins:

| | where | scope |
|---|---|---|
| 1 | `ADVERSARY_REVIEW=0` | one session — `ADVERSARY_REVIEW=0 claude` |
| 2 | `.git/adversary-review` | one repo, every worktree of it — lives in the common git dir, so untracked by construction |
| 3 | `~/.claude/adversary-review` | every repo |
| 4 | — | default: on |

If the toggle can't be found at all, the hook fails open rather than nagging with no way
to stop it.

### `examples/github-pr-review.yml` — the actual gate

Not part of the plugin; copy it into a repo's `.github/workflows/`. Runs
`anthropics/claude-code-action@v1` on every PR with full history checked out, spawns the
same four lenses plus refuters, posts survivors as inline comments. It delegates to
subagents rather than invoking the workflow because the `ultracode` keyword doesn't trigger
workflows from webhook-origin runs.

CI deliberately ignores the local toggle — a switch you can flip from the machine being
reviewed isn't a gate. Its escape hatches are visible to reviewers instead: the
`skip-adversary` label on a PR, or repo variable `ADVERSARY_REVIEW=off`. Drafts skip
automatically. **Turning off the hook does not turn off CI.** That asymmetry is the design.

Needs the [Claude GitHub App](https://github.com/apps/claude) and `ANTHROPIC_API_KEY` in
repo secrets; `claude /install-github-app` does both.

### How they stack

| | cost | when | can you skip it |
|---|---|---|---|
| subagent alone | ~1 agent | you ask | yes, trivially |
| workflow | ~76 agents on a 10-file diff | you ask | yes, trivially |
| Stop hook | 1–2 Haiku agents by diff size, capped at 16 turns each | automatically, once per change ≥40 code lines | yes, one command |
| GitHub Action | ~50+ agents | every PR | not from your laptop |

Same reviewer underneath all four. The escalation is purely about how hard it is to not
run it.

## How the pieces map to Bun's design

| Bun | Here | Why it's load-bearing |
|---|---|---|
| separate context window | `Agent`/`agent()` subagent | it never saw your reasoning, so it can't inherit your assumptions |
| "the reviewer doesn't implement" | `disallowedTools: Write, Edit` | structural, not a prompt it can talk itself out of |
| "its context: only the diff" | reviewer starts from `git diff` | reviewing the file invites judging intent; reviewing the diff invites finding breakage |
| "assume the code is wrong" | the agent's framing: *find reasons this breaks* | "review this" gets you an approval; "find why this breaks" gets you findings |
| 2+ reviewers per implementer | 4 lenses in parallel | one reviewer covering everything covers nothing; each lens is told to ignore the others' territory |
| "1 fixes / 2 review / 1 applies" | findings return as data; you or the author agent apply | the reviewer proposing the fix re-merges the roles |

### The one thing I added

Bun's write-up says nothing about false positives — the words don't appear in the post.
But an agent told to assume code is wrong *will* find things that aren't there, and a
reviewer you learn to ignore is worse than no reviewer.

So the workflow adds a **refutation pass**: every finding goes to 3 fresh agents whose
job is to kill it, defaulting to refuted when uncertain, each from a different angle —
read the code, check the callers and tests, try to reproduce it. A finding needs 2 of 3
non-refuting votes to reach you. Same trick as the review itself, one level up: the
agent grading the finding is not the agent that made it.

Turn it down with `args: {"refuters": 1}` if you'd rather see everything.

## Cost

Four lenses × N files, plus 3 refuters per finding. On a 10-file diff producing 12 raw
findings that's ~76 agent calls. Fine for a PR you're about to merge, wasteful on a
one-line change. For routine work use the single-subagent form; save the workflow for
diffs you actually need to trust.

## Notes

- The reviewer keeps `Bash` — it needs `git diff`, and running a test to confirm a finding
  is the difference between `plausible` and `confirmed`. For provable read-only, add a
  `Bash` deny rule in settings.
- Hooks **merge** across scopes rather than replacing each other, so this plugin's Stop
  hook runs alongside any you already have.

## License

MIT
