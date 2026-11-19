---
name: greenlight
description: Say what it will do and list the workflows it will watch, then merge the repository's default branch into the current branch, push it, and start the merge gate so the pull request's required integration and Playwright checks actually run (re-running it after every push), and fix the code when a check fails. Use when the user asks to run CI on their branch, to bring a branch up to date with develop or main and test it, or for a greenlight before a merge.
---

0. **Say what you are going to do, before doing anything.** Gather the facts:

   ```bash
   gh repo view --json defaultBranchRef -q .defaultBranchRef.name    # the default branch
   git branch --show-current                                         # this branch
   gh pr view --json number,url,state -q '"#\(.number) \(.url) \(.state)"'
   gh pr checks --json workflow,name -q '.[] | "\(.workflow)\t\(.name)"'
   gh pr checks --required --json name -q '.[].name'
   ```

   Then tell the user, in this shape:

   > Greenlight on `<branch>` (PR #N):
   > 1. Fetch `origin/<default>` and merge it into `<branch>`. I resolve any conflicts, and ask
   >    you when one needs your decision.
   > 2. Push the merge. That makes GitHub run the PR's checks on the new commit.
   > 3. Start the merge gate (re-run `Merge gate (re-run to start)`) so integration and
   >    Playwright run, and again after every push I make.
   > 4. Wait for the checks. If one fails, fix the code and push again, up to three times.
   > 5. Report each check's result.
   >
   > Workflows I will watch:
   >
   > | Workflow | Checks | Required |
   > |---|---|---|
   > | Unit Test | vitest, prettier | vitest |
   > | Merge gate (re-run to start) | integration / integration, integration / integration (server), playwright / playwright | integration / integration, playwright / playwright |
   > | Claude Code Review | claude-review | |
   > | … | … | |

   Build the table from the PR's checks: one row per workflow, its check names, and which of
   them are required. Before the gate is started, its rows show only as `integration` and
   `playwright`, skipped; list the required names anyway, from `gh pr checks --required` or from
   the comment at the top of `gated.yml`. Without an open PR, list the files in `.github/workflows/` whose `on:`
   has `pull_request` or `push`, and say that no PR exists, so no checks are required. Then go
   straight on to step 1; do not wait for a reply. After the push (step 3), compare the checks
   that appear with this list. Name any that are new or that never started.

1. **Pull the default branch.** Ask GitHub which branch is the default; never assume `main`.

   ```bash
   base=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
   git fetch origin "$base"
   ```

   Stop if tracked files have uncommitted changes, or if you are on the default branch itself.

2. **Merge it in.**

   ```bash
   git merge --no-edit "origin/$base"
   ```

   If it conflicts, resolve each file yourself, keeping what both sides meant. Then `git add` the
   files and run `git commit --no-edit`. If a conflict needs a decision only the user can make,
   stop and ask. Never abort, reset or force-push.

3. **Push.**

   ```bash
   git push -u origin HEAD
   ```

4. **Start the merge gate.** In alertd-core, integration and Playwright never run by themselves on
   a pull request. They run only through the workflow `Merge gate (re-run to start)`
   (`.github/workflows/gated.yml`), and only when that run is re-run: its jobs are gated on
   `github.run_attempt > 1`. The required checks are `integration / integration` and
   `playwright / playwright`. On the first attempt the gate's jobs show as `integration` and
   `playwright`, skipped, and the required names are not reported at all, so the PR waits. Every
   push starts a new first attempt, so the gate has to be started again after each push.

   Wait about a minute after the push for the gate's run to appear on the pushed commit, then find
   it:

   ```bash
   sha=$(git rev-parse HEAD)
   gh run list --workflow gated.yml --commit "$sha" --event pull_request \
     --json databaseId,attempt,status -q '.[0] | "\(.databaseId) attempt \(.attempt) \(.status)"'
   ```

   If its attempt is 1, re-run all of its jobs (not `--failed`: skipped jobs are not failed):

   ```bash
   gh run rerun <id>
   ```

   Then check that both required names appear:

   ```bash
   gh pr checks --required
   ```

   If `integration / integration` or `playwright / playwright` is still missing a few minutes
   after the rerun, say so. Without an open pull request, start it by dispatch instead, and say
   that a PR will not list these checks:

   ```bash
   gh workflow run gated.yml --ref "$(git branch --show-current)"
   ```

   In a repository without `gated.yml`: if a required check named like `integration` shows
   `skipping`, rerun the run in its link (`.../actions/runs/<id>/job/...`) once with
   `gh run rerun <id>`.

5. **Wait.** Wait for the checks with `gh pr checks --watch`, run in the background because it
   takes minutes.

6. **Fix what fails.** For each failing check, read the failing log:

   ```bash
   gh run view <id> --log-failed
   ```

   Find the cause, fix it in the code and run that test locally if you can. Then commit, push and
   go back to step 4: the push resets the merge gate.
   - Fix the code, not the test. Change a test only when the test itself is wrong, and say so.
     Never skip, delete or loosen a test to make it pass.
   - If the failure is not in the code (a runner that never started, a timeout, an outage), rerun
     the run once with `gh run rerun <id> --failed` instead.
   - If the same check still fails after three fix attempts, or the fix needs a decision only the
     user can make, stop and say what you found.

7. **Report** the following:
   - the merge, with any conflicts you resolved;
   - each fix you pushed and why;
   - the final sha;
   - each check with its result, copied from `gh pr checks`, not guessed.

   Say integration or Playwright passed only if `integration / integration` or
   `playwright / playwright` ran on that sha and shows `pass`.
