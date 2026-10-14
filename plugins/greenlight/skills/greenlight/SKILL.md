---
name: greenlight
description: Run CI on the repository's default branch on GitHub Actions, integration tests included, and report whether it passed from a script's verdict rather than a reading of the logs. Use when the user asks to run CI on main, to prove the default branch is green, to check that the integration tests pass, or for a greenlight before a release or a merge.
argument-hint: "[workflow ...] [--latest] [--match REGEX] [--timeout MIN]"
allowed-tools: Bash
---

Run the script in the background, since a CI run takes minutes, and wait for it to exit:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/greenlight.sh" $ARGUMENTS
```

If `${CLAUDE_PLUGIN_ROOT}` is not set on this host (Devin, for one), the plugin root is two
directories above this skill's base directory: run `scripts/greenlight.sh` from there.

The script fetches the default branch (it never pulls, merges or checks anything out),
dispatches every CI workflow on it, waits for the runs to complete, then takes one final
`gh run view` snapshot per run and judges only that. It exits 0 only when its last block
reads `GREENLIGHT PASS`. `--latest` verifies the newest completed runs on the current sha
instead of starting new ones. A workflow name narrows it to that workflow, and is the only
way a manual-only workflow (a release, say) gets dispatched.

The report is the script's verdict, copied:

1. The line after `== verdict`, verbatim, as the first line: `GREENLIGHT PASS  main@abc1234  <run urls>`
   or `GREENLIGHT FAIL  main@abc1234`.
2. On FAIL, each `- reason` line under it, verbatim, as a bullet.
3. One line naming the integration job(s) the script tagged `[integration]` and how long they
   took, read from the `== jobs` table.

The verdict is the script's, so the report is what the script printed:

- Output with no `== verdict` block (killed, timed out by the tool, not finished) is
  reported as "CI did not complete", with the last lines the script printed. It is never
  reported as passed.
- A green jobs table above a `GREENLIGHT FAIL` is still a FAIL. The reasons say why.
- `--latest` with a FAIL that says no run exists is reported as that; the next step is to run
  it without `--latest`, which the user decides.
- No job tagged `[integration]` means the integration tests did not run as far as this
  verdict goes; `--match` names a different job pattern, and the user picks it.
