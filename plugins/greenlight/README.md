# Greenlight

`/greenlight` brings a branch up to date with the default branch and makes sure its
integration tests run. It is a skill only, with no script behind it.

0. It says what it is going to do and lists the workflows it will watch, as a table: each
   workflow, its checks, and which of them are required.
1. It asks GitHub for the default branch (`develop`, `main`, …) and fetches it.
2. It merges that branch into the current branch. Claude resolves any conflicts, and stops to
   ask when a conflict needs your decision.
3. It pushes.
4. It starts the merge gate. In alertd-core, integration and Playwright run on a pull request
   only when the `Merge gate (re-run to start)` run (`gated.yml`) is re-run, so it runs
   `gh run rerun` on that run, and again after every push it makes. Without a PR it dispatches
   `gh workflow run gated.yml` on the branch.
5. It waits on `gh pr checks`.
6. When a check fails, it reads the failing log, fixes the code (not the test), pushes, starts the gate
   again and waits. If the failure is in the infrastructure rather than the code, it reruns the check once
   instead. It stops after three attempts on the same check.
7. It reports each check's result.

```bash
claude plugin install greenlight@adrianj98-skills
```

or, without the plugin system:

```bash
./install.sh greenlight --global
```
