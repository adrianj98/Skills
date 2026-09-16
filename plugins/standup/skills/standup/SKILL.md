---
name: standup
description: Write a very short standup list of what was worked on since yesterday morning, from the commits in every worktree of the current repo. Use when the user asks for a standup, a daily update, or what they worked on yesterday.
argument-hint: "[since WHEN] [everyone]"
allowed-tools: Bash
---

Commits since yesterday morning, across every worktree of this repo (branch, time, sha, subject):

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/standup.sh" 2>&1`

The user invoked this with `$ARGUMENTS`. If that asks for a different window ("since friday",
"last 3 days") or for everyone's commits, rerun
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/standup.sh" --since "<when>"` and/or `--everyone`
and use that output instead.

Turn the commits into a standup list:

- **One bullet per piece of work, not per commit.** A fix and its follow-ups, a feature and
  its tests, the same change landing on two branches: one bullet.
- **A few plain words each**, past tense, the way you'd say it out loud. No shas, times,
  branch names, or file paths.
- **Drop the noise** — typo fixes, formatting, version bumps, "wip" — unless that's all there is.
- **Nothing but the list.** No heading, no intro, no summary after.

If there are no commits, say so in one line with the cutoff date, e.g. `No commits since Mon Sep 14 06:00.`
