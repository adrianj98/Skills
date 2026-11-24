# Greenlight

`/greenlight` brings a branch up to date with the default branch and keeps going until every
required check has passed on its final commit. It is a skill only, with no script behind it.

The required checks come from the repository's rules and branch protection
(`gh api repos/<repo>/rules/branches/<base>`), not from `gh pr checks --required`, which only
lists required checks that have already reported. In alertd-core that would hide
`integration / integration` and `playwright / playwright` until the merge gate is started.

0. It says what it is going to do, names the required checks and lists the workflows it will
   watch, as a table: each workflow, its checks, and which of them are required.
1. It asks GitHub for the default branch (`develop`, `main`, …) and fetches it.
2. It merges that branch into the current branch. Claude resolves any conflicts, and stops to
   ask when a conflict needs your decision.
3. It pushes.
4. It starts every required check that is missing or skipped on the pushed commit. In alertd-core
   that means re-running the `Merge gate (re-run to start)` run (`gated.yml`) after every push, or
   dispatching it without a PR. Other skipped required checks get one rerun or a dispatch.
5. It waits until every required check has finished on that exact commit (not just until
   `gh pr checks --watch` returns).
6. When any check fails, required or not, it reads the failing log, fixes the code (not the
   test), pushes and goes back to step 4. Infrastructure failures get one rerun instead. It stops
   after three attempts on the same check.
7. It reports each required check's result on the final commit, and starts with **Greenlit** only
   when all of them are `success` and nothing else fails.

```bash
claude plugin install greenlight@adrianj98-skills
```

or, without the plugin system:

```bash
./install.sh greenlight --global
```
