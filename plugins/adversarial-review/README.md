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
hooks/hooks.json             registers the Stop hook
scripts/require-adversary.sh the Stop hook itself
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

### The turn ceiling

`maxTurns: 40`, in the frontmatter. Same trick as `disallowedTools`: a structural limit,
not a request the agent can reason its way past.

This is the setting that decides whether you keep the plugin, and it's a real trade. Reviewer
agents don't get slow by finding too much — they get slow by *looking*. One agent opens the
diff, then a caller, then the caller's caller, then greps the repo for a type, then runs the
suite. Multiply by four lenses and a ceiling that's too high costs you an hour at the end of
every turn; parallelism doesn't save you, since the lenses run concurrently and the slowest
single agent *is* the wall-clock cost. But too low a ceiling buys that speed with
`plausible` — a reviewer that can't reach the caller can't tell you whether the contract
actually broke.

40 turns is enough to follow a diff outward — callers, types, the tests that cover it — and
still nowhere near an audit. The prompt spends it explicitly: turn 1 reads the diff, turns
2–32 follow the threads that are still about *this diff*, by turn 33 stop reading and write.
Anything unchecked still ships as `plausible` rather than costing more turns. Opening files
the diff doesn't touch, running the full suite, and building a repro harness stay out of
scope, finishing early is the normal case, and "nothing found" is a legitimate two-line
answer rather than something it has to justify.

The ceiling is hard, and hitting it returns *nothing* — so the prompt has to make it land
before the cliff, not just aim vaguely at brevity. The deep workflow keeps the same ceiling
and buys depth by adding agents instead of lengthening them: one file under one lens should
finish well inside 40.

If the nudge starts feeling slow on your repo, this is the number to lower.

**Cheapest form**, one agent, one pass:

```
Have the adversary subagent review my uncommitted changes.
```

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
`PLAUSIBLE` (2/3).

Pass options as workflow args: `{"range": "main...HEAD"}`, `{"refuters": 1}` to see more,
or a custom `lenses` array.

### `hooks/` — the local nudge

A Stop hook. Stop hooks fire when Claude tries to end its turn; exit `2` means *you're not
done* and Claude keeps working with the message as its instruction.

This one hashes the working-tree diff, compares it to a marker in `.git/`, and on a new
state tells Claude to hand the diff to the `adversary` subagent instead of reviewing its
own work. It writes the marker *before* blocking, so it fires at most once per distinct
diff and can't loop — which also makes it a nudge rather than a wall. Deliberate. The wall
is CI.

A nudge you hit automatically has to be cheap, or you start turning it off. Two things keep
it that way. The lenses run **in parallel**, so four of them cost about one agent's
wall-clock. And each reviewer is capped at **40 turns** (see below), so a lens can follow a
contract to its callers but can't wander off into the codebase for an hour. Four capped
agents at once is one round; four uncapped ones sequentially is the afternoon you stopped
using this.

It also stays quiet on changes that don't earn it: docs and licence files are never
counted, and a diff under 25 changed code lines is skipped entirely. Move that line with
`ADVERSARY_MIN_LINES` (`0` reviews everything):

```bash
ADVERSARY_MIN_LINES=100 claude    # only sizeable diffs
```

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
| 2 | `.git/adversary-review` | one repo — lives in `.git/`, so untracked by construction |
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
| Stop hook | ~4 agents, capped at 40 turns each | automatically, once per diff ≥25 code lines | yes, one command |
| GitHub Action | ~50+ agents | every PR | not from your laptop |

Same reviewer underneath all four. The escalation is purely about how hard it is to not
run it.

## How the pieces map to Bun's design

| Bun | Here | Why it's load-bearing |
|---|---|---|
| separate context window | `Task`/`agent()` subagent | it never saw your reasoning, so it can't inherit your assumptions |
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
