---
name: greenlight
description: Merge the repository's default branch into the current branch, push it, and make sure the pull request's required integration check actually runs, rerunning it when it was skipped. Use when the user asks to run CI on their branch, to bring a branch up to date with develop or main and test it, or for a greenlight before a merge.
allowed-tools: Bash
---

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

4. **Make sure integration runs.** This step applies only when the branch has an open pull request
   and one of its required checks is named like `integration`. Wait about a minute for the checks
   to appear on the pushed commit, then look:

   ```bash
   gh pr checks --required
   ```

   If the integration check shows `skipping` or `skipped`, rerun its workflow run. The run id is in
   the check's link (`.../actions/runs/<id>/job/...`):

   ```bash
   gh run rerun <id>
   ```

   Some workflows skip integration on a PR's first attempt and run it only on a rerun. Rerun once.
   If it is still skipped after that, say so.

5. **Report.** Wait for the checks with `gh pr checks --watch`, run in the background because it
   takes minutes. Then report the following:
   - the merge, with any conflicts you resolved;
   - the pushed sha;
   - each check with its result, copied from `gh pr checks`, not guessed.

   Say the integration check passed only if it ran on that sha and shows `pass`.
