---
name: adversary
description: Turn adversarial review on or off, check whether it's active, or adversarially review the current diff now. Use when the user asks to enable, disable, pause, or check adversarial review, or asks for an adversarial review of their changes.
argument-hint: "[on | off | off --all | on --all | clear | status | run [lens...]]"
allowed-tools: Bash, Agent, Read, Grep, Glob
---

Adversarial review state right now:

!`bash "${CLAUDE_PLUGIN_ROOT}/bin/adversary" status 2>/dev/null || echo "state: unknown (toggle not found)"`

The user invoked this with `$ARGUMENTS`. Run the toggle as
`bash "${CLAUDE_PLUGIN_ROOT}/bin/adversary" <args>` — invoke it via `bash` rather than
directly, since the file may not carry an exec bit after install.

- **`on` / `off`** — run the toggle with those arguments. Without `--all` it affects the
  current repo only; with `--all` it sets the global default. Report the new state in one line.
- **`clear`** — run the toggle with `clear` to drop this repo's override so it inherits the global setting.
- **`status`**, or no argument — the state is already shown above. Report it in one line and
  say what would change it. Run nothing else.
- **`run`** — ignore the toggle and review the current diff now.

  1. **Size the review.** Count reviewable code lines (`git diff <range> --numstat`, ignoring
     `.md`/`.txt`/`LICENSE` and friends) and changed files, then take the lens set from the
     ladder — four lenses on a two-file fix is most of what a review costs and none of what it
     is worth:

     | changed code lines | lenses |
     | --- | --- |
     | under 40 | ask whether it's worth a round at all |
     | 40–150 | `correctness` |
     | 150–600 | `correctness`, `failure-paths` |
     | over 600, or 8+ files | all four: add `lifetime-and-async`, `contract-drift` |

     One thing the count can't see: if the diff changes an exported signature, a return type, or
     a public nullability, add `contract-drift` whatever the size. `$ARGUMENTS` naming lenses, or
     `ADVERSARY_LENSES`, overrides the ladder.
  2. **Capture the diff once.** Write it to a scratch file (the session scratchpad, or
     `$TMPDIR`) — `git diff HEAD`, or, if that is empty because the work is already committed,
     the commits that are new (`git diff @{u}`, `git diff HEAD~1`, or the range the user names).
     Paste its contents into every lens prompt under a `## The diff` heading. Do not make four
     agents each fetch it.
  3. **Carry what is already known.** Two files, in two places, on purpose:

     - `adversary-facts.md`, next to the scratch diff — what earlier lenses *proved by running
       it*. Paste it under `## Already established — do not re-derive`. Session-scoped, because
       a fact about code that has since changed is worse than no fact. Without it every lens
       re-probes the same function every round; measured at ~16 redundant derivations of one
       lookup table across four rounds.
     - `.git/adversary-findings.md` — what the last round *found*. It lives in `.git/` because
       it has to outlive the session to do its job: if it exists and this diff is the fix for
       it, paste it under `## Prior findings` and send **one** reviewer, not four. That is a
       scored verdict pass, not a new round, and it is what stops a fix from triggering a fresh
       hunt. The Stop hook reads and writes the same path.
  4. **Fan out.** Spawn the chosen lenses in one message so they run in parallel (Agent tool,
     `subagent_type: adversary`). Name the scratch directory in each prompt; that is where their
     probe scripts go, not the repo.
  5. **Synthesize.** Group the returned findings by file *and mechanism* — a race and an
     off-by-one at the same line are two findings, not one. A finding two or more lenses raised
     independently is **promoted one severity level** and labelled `corroborated`; agreement is
     evidence that it matters. It is not evidence that it is *true* — lenses share assumptions,
     and in the session this rule came from, two of them agreed a branch was unreachable and both
     were wrong. So promotion moves severity only, never confidence: two `plausible`s stay
     `plausible`. Report the worst verdict word any lens returned, verbatim; you don't get to
     soften it.
  6. **Write both files back.** Append each lens's **Established by execution** lines to
     `adversary-facts.md`, one per line, with how it was verified — facts someone actually ran,
     nothing merely reasoned about. Write the synthesized findings to
     `.git/adversary-findings.md` so the next round scores them instead of hunting again.

     After a scoring round, that file is rewritten with what is still open, or **deleted** when
     everything came back resolved. Nothing else clears it, and a findings file left behind
     turns the next unrelated change into a verdict pass against stale findings.

  Each lens is capped at 22 turns and told to stop investigating at its 15th tool call, so this
  is one round and not an audit; let them finish and report, don't chase their findings further
  yourself. Fix nothing unless asked. For a heavier pass with refutation voting, use
  `/adversarial-review:review` instead.
- **anything else** — show the usage line and the current state.

Turning it off only silences the local Stop-hook nudge. The `/adversarial-review:review`
workflow and any CI job are unaffected — say so if the user seems to expect otherwise.
