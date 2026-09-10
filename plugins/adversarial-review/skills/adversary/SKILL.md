---
name: adversary
description: Turn adversarial review on or off, check whether it's active, or adversarially review the current diff now. Use when the user asks to enable, disable, pause, or check adversarial review, or asks for an adversarial review of their changes.
argument-hint: "[on | off | off --all | on --all | clear | status | run]"
allowed-tools: Bash, Task, Read, Grep, Glob
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
- **`run`** — ignore the toggle and review the current diff now. Spawn four subagents in
  one message so they run in parallel (Task tool, `subagent_type: adversary`), one per lens
  — correctness, failure-paths, lifetime-and-async, contract-drift — each starting from
  `git diff HEAD`. Each is capped at 40 turns, so this is one round and not an audit; let them
  finish and report, don't chase their findings further yourself. Fix nothing unless asked.
  For a heavier pass with refutation voting, use `/adversarial-review:review` instead.
- **anything else** — show the usage line and the current state.

Turning it off only silences the local Stop-hook nudge. The `/adversarial-review:review`
workflow and any CI job are unaffected — say so if the user seems to expect otherwise.
