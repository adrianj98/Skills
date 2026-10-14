---
name: greenlight
description: Merge the repository's default branch into the current branch, push it, run CI on it on GitHub Actions, integration tests included, and report whether it passed from a script's verdict rather than a reading of the logs. With --default, or on the default branch itself, it tests the default branch. Use when the user asks to run CI on their branch or on the default branch, to check that the integration tests pass, to prove a branch is green against the latest default branch, or for a greenlight before a release or a merge.
argument-hint: "[workflow ...] [--default] [--latest] [--match REGEX] [--timeout MIN]"
allowed-tools: Bash
---

Run the script in the background, since a CI run takes minutes, and wait for it to exit:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/greenlight.sh" $ARGUMENTS
```

If `${CLAUDE_PLUGIN_ROOT}` is not set on this host (Devin, for one), the plugin root is two
directories above this skill's base directory: run `scripts/greenlight.sh` from there.

The script asks GitHub which branch is the default (it never assumes `main`) and fetches it.
On any other branch it merges the default branch into the current branch, pushes the
result, and dispatches every CI workflow on the current branch, so CI tests the branch as
it would be after merging. It refuses when tracked files have uncommitted changes, and
aborts a merge that conflicts. On the default branch itself, or with `--default`, it tests
the default branch as it is on origin and touches nothing. It waits for the runs, takes one
final `gh run view` snapshot per run, judges only that, and exits 0 only when its last block
reads `GREENLIGHT PASS`. `--latest` merges, pushes and dispatches nothing: it verifies the
newest completed runs on the branch's pushed sha, which must already contain the default
branch. A workflow name narrows it to that workflow, and is the only way a manual-only
workflow (a release, say) gets dispatched.

The report is the script's verdict, copied:

1. The line after `== verdict`, verbatim, as the first line: `GREENLIGHT PASS  <branch>@abc1234  <run urls>`
   or `GREENLIGHT FAIL  <branch>@abc1234`.
2. When it merged, the `merge` line, saying the default branch was merged into the branch and
   pushed, since that changed the user's branch.
3. On FAIL, each `- reason` line under it, verbatim, as a bullet.
4. One line naming the integration job(s) the script tagged `[integration]` and how long they
   took, read from the `== jobs` table.

The verdict is the script's, so the report is what the script printed:

- Output with no `== verdict` block (killed, timed out by the tool, not finished) is
  reported as "CI did not complete", with the last lines the script printed. It is never
  reported as passed.
- A green jobs table above a `GREENLIGHT FAIL` is still a FAIL. The reasons say why.
- `--latest` with a FAIL that says no run exists is reported as that; the next step is to run
  it without `--latest`, which the user decides.
- A merge conflict, uncommitted changes or a refused push is a FAIL before any CI ran; the
  reason says which, and resolving it is the user's.
- No job tagged `[integration]` means the integration tests did not run as far as this
  verdict goes; `--match` names a different job pattern, and the user picks it.
