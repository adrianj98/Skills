---
name: greenlight
description: Say what it will do and list the workflows it will watch, then merge the repository's default branch into the current branch, push it, start every required check that did not run by itself (alertd-core's merge gate after every push), and keep fixing the code and pushing until every required check has passed on the final commit and no other check fails. Use when the user asks to run CI on their branch, to bring a branch up to date with develop or main and test it, or for a greenlight before a merge.
---

The goal is a branch whose **final commit** has every required check passed, with no other check
failing. A greenlight is never given on checks from an older commit or on checks that were skipped
or never reported.

## Two commands you use throughout

**The required checks.** Take them from the repository's rules, not from `gh pr checks --required`:
that only lists required checks that have already reported, so a check that never started (like
alertd-core's integration and Playwright before the gate is started) is silently left out.

```bash
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
base=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
required=$( {
  gh api "repos/$repo/rules/branches/$base" \
    -q '.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' 2>/dev/null
  out=$(gh api "repos/$repo/branches/$base/protection/required_status_checks" -q '.contexts[]' 2>/dev/null) && echo "$out"
} | sort -u )
printf '%s\n' "$required"
```

If both come back empty (no rules or protection the token can read), fall back to
`gh pr checks --required` and to the comment at the top of `gated.yml`, and say the list may be
incomplete.

**The verdict on a commit.** For each required check, the latest check run or status reported on
that exact sha:

```bash
verdict() {  # usage: verdict <sha>
  local sha=$1 runs stat c line
  runs=$(gh api --paginate "repos/$repo/commits/$sha/check-runs" \
    -q '.check_runs[] | "\(.name)\t\(.status)\t\(.conclusion)\t\(.started_at)"')
  stat=$(gh api "repos/$repo/commits/$sha/status" \
    -q '.statuses[] | "\(.context)\tcompleted\t\(.state)\t\(.updated_at)"')
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    line=$(printf '%s\n%s\n' "$runs" "$stat" | awk -F'\t' -v c="$c" '$1==c' | sort -t$'\t' -k4 | tail -1)
    if [ -z "$line" ]; then printf 'MISSING\t\t%s\n' "$c"
    else printf '%s\n' "$line" | awk -F'\t' '{print $3"\t"$2"\t"$1}'; fi
  done <<< "$required"
}
verdict "$(git rev-parse HEAD)"
```

Each line is `<conclusion> <status> <check>`. A required check counts as passed only when its
conclusion is `success`. `MISSING`, `skipped`, `neutral`, `cancelled`, `null` (still running) and
anything else are not a pass.

## Steps

0. **Say what you are going to do, before doing anything.** Gather the facts:

   ```bash
   git branch --show-current
   gh pr view --json number,url,state -q '"#\(.number) \(.url) \(.state)"'
   gh pr checks --json workflow,name -q '.[] | "\(.workflow)\t\(.name)"'
   ```

   plus `$required` from above. Then tell the user, in this shape:

   > Greenlight on `<branch>` (PR #N):
   > 1. Fetch `origin/<default>` and merge it into `<branch>`. I resolve any conflicts, and ask
   >    you when one needs your decision.
   > 2. Push the merge. That makes GitHub run the PR's checks on the new commit.
   > 3. Start every required check that does not start by itself (in alertd-core, re-run
   >    `Merge gate (re-run to start)` so integration and Playwright run), after every push I make.
   > 4. Wait until every required check has finished on the pushed commit. If any check fails,
   >    fix the code and push again, up to three times per check.
   > 5. Report each check's result on the final commit.
   >
   > Required checks (from the repository's rules): `integration / integration`,
   > `playwright / playwright`, `vitest`.
   >
   > Workflows I will watch:
   >
   > | Workflow | Checks | Required |
   > |---|---|---|
   > | Unit Test | vitest, prettier | vitest |
   > | Merge gate (re-run to start) | integration / integration, integration / integration (server), playwright / playwright | integration / integration, playwright / playwright |
   > | Claude Code Review | claude-review | |
   > | … | … | |

   One row per workflow, its check names, and which of them are required. A required check that
   no workflow has reported yet still gets listed: put it in the row of the workflow that will
   produce it (for alertd-core's gate, before it is started its rows show only as `integration`
   and `playwright`, skipped). Without an open PR, list the files in `.github/workflows/` whose
   `on:` has `pull_request` or `push`, and say that no PR exists, so GitHub will not enforce the
   required checks, but you will still run them. Then go straight on to step 1; do not wait for
   a reply.

1. **Pull the default branch.** Ask GitHub which branch is the default; never assume `main`.

   ```bash
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
   sha=$(git rev-parse HEAD)
   ```

   Check that `git ls-remote origin "refs/heads/$(git branch --show-current)"` shows `$sha`.

4. **Start every required check that did not start.** Wait about a minute after the push, then run
   `verdict "$sha"`. Every required check that is `MISSING` or `skipped` must be started.

   **alertd-core's merge gate.** Integration and Playwright never run by themselves on a pull
   request. They run only through the workflow `Merge gate (re-run to start)`
   (`.github/workflows/gated.yml`), and only when that run is re-run: its jobs are gated on
   `github.run_attempt > 1`. On the first attempt the jobs show as `integration` and
   `playwright`, skipped, and `integration / integration` and `playwright / playwright` are not
   reported at all. Every push starts a new first attempt, so start the gate again after **every**
   push.

   ```bash
   gh run list --workflow gated.yml --commit "$sha" --event pull_request \
     --json databaseId,attempt,status -q '.[0] | "\(.databaseId) attempt \(.attempt) \(.status)"'
   ```

   If its attempt is 1, re-run all of its jobs (not `--failed`: skipped jobs are not failed):

   ```bash
   gh run rerun <id>
   ```

   Without an open pull request, dispatch it instead:

   ```bash
   gh workflow run gated.yml --ref "$(git branch --show-current)"
   ```

   **Any other missing or skipped required check.** Find the workflow that produces it
   (`grep -rl` its job name under `.github/workflows/`) and its run on `$sha`
   (`gh run list --commit "$sha"`). If the run exists but the job was skipped, `gh run rerun <id>`
   once. If no run exists and the workflow has `workflow_dispatch`, `gh workflow run <file> --ref
   <branch>`. If it still cannot be started, read its `on:` and `if:` conditions and say why it
   does not run; that is a blocker, not a pass.

   A few minutes after starting, run `verdict "$sha"` again. Every required check must now show
   up (running or finished). Name any that are still `MISSING`.

5. **Wait until every required check has finished on `$sha`.** `gh pr checks --watch` alone is not
   enough: it can return before checks started by a rerun appear. Run this in the background, since
   it takes minutes:

   ```bash
   until ! verdict "$sha" | awk -F'\t' '$2!="completed"' | grep -q .; do sleep 60; done
   verdict "$sha"; gh pr checks
   ```

   If something stays queued or `MISSING` for over 30 minutes, stop waiting and say which.

6. **Fix what fails.** Every check that fails on `$sha` needs fixing, required or not: the goal
   is that everything passes. For each one, read the failing log:

   ```bash
   gh run view <id> --log-failed
   ```

   Find the cause, fix it in the code and run that test locally if you can. Then commit, push and
   go back to step 3 with the new sha: the push resets the merge gate and every check.
   - Fix the code, not the test. Change a test only when the test itself is wrong, and say so.
     Never skip, delete or loosen a test, and never mark a check as not required, to make it pass.
   - If the failure is not in the code (a runner that never started, a timeout, an outage), rerun
     the run once with `gh run rerun <id> --failed` instead.
   - A failing check that is not required and not about the code (an AI review bot's verdict, a
     coverage upload) does not block the greenlight, but say it failed and why.
   - If the same check still fails after three fix attempts, or the fix needs a decision only the
     user can make, stop and say what you found.

   Keep going until, on the latest pushed sha, `verdict` shows `success` for every required check
   and `gh pr checks` shows no `fail`.

7. **Report** the following:
   - the merge, with any conflicts you resolved;
   - each fix you pushed and why;
   - the final sha;
   - the output of `verdict "<final sha>"`, one line per required check, and the result of every
     other check, copied from `gh pr checks`, not guessed.

   Start the report with one line: **Greenlit** only when every required check is `success` on
   the final sha and no other code check fails; otherwise **Not greenlit**, followed by which
   checks are missing, skipped, running or failing.
