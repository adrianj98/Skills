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
it would be after merging. It refuses when tracked files have uncommitted changes. A merge
that conflicts is left in progress for you to resolve (below). On the default branch itself, or with `--default`, it tests
the default branch as it is on origin and touches nothing. It waits for the runs, takes one
final `gh run view` snapshot per run, judges only that, and exits 0 only when its last block
reads `GREENLIGHT PASS`. `--latest` merges, pushes and dispatches nothing: it verifies the
newest completed runs on the branch's pushed sha, which must already contain the default
branch. A workflow name narrows it to that workflow, and is the only way a manual-only
workflow (a release, say) gets dispatched.

## When the merge conflicts

The script exits 3 and its last block starts `MERGE CONFLICT`, followed by one
`- conflicted: <file>` line per file. The merge is still in progress. Resolve it, then run
the script again with the same arguments:

1. For each conflicted file, read both sides and what each side changed:
   `git diff <file>` for the conflict, and `git log --oneline -5 MERGE_HEAD -- <file>` and
   `git log --oneline -5 HEAD -- <file>` for why. Keep both sides' intent: the default
   branch's change and the branch's change usually both have to survive, combined. Never
   resolve by taking one side wholesale unless the other side's change is clearly superseded.
2. Remove every conflict marker. Check with `git diff --check`.
3. When it builds or has fast checks (a type check, a compile, the unit tests near the
   conflict), run them locally before committing.
4. `git add` the resolved files and `git commit --no-edit`.
5. Run the script again. It sees the branch already contains the default branch, refuses
   committed conflict markers, pushes, and runs CI.

Stop and ask the user, leaving the merge in progress, when a conflict needs a product or
design decision rather than combining two edits (both sides rewrote the same logic
differently, one side deleted what the other changed, a migration or a lock file you
cannot regenerate). Say which files and what each side wants. Never `git merge --abort`,
reset or force-push on your own.

In the report, list each conflicted file and one line on how it was resolved, before the
verdict of the run that followed.

## The report

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
- Uncommitted changes, a merge already in progress, committed conflict markers or a refused
  push is a FAIL before any CI ran; the reason says which. Uncommitted changes and a refused
  push are the user's to sort out; a merge you left in progress is yours to finish.
- No job tagged `[integration]` means the integration tests did not run as far as this
  verdict goes; `--match` names a different job pattern, and the user picks it.
