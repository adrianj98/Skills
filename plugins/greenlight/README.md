# Greenlight

`/greenlight` brings a branch up to date with the default branch and makes sure its
integration tests run. It is a skill only, with no script behind it.

1. It asks GitHub for the default branch (`develop`, `main`, …) and fetches it.
2. It merges that branch into the current branch. Claude resolves any conflicts, and stops to
   ask when a conflict needs your decision.
3. It pushes.
4. If the pull request has a required check named like `integration` that came out `skipping`,
   it runs `gh run rerun` on that run once. Some workflows skip integration on a PR's first
   attempt.
5. It waits on `gh pr checks`.
6. When a check fails, it reads the failing log, fixes the code (not the test), pushes and waits
   again. If the failure is in the infrastructure rather than the code, it reruns the check once
   instead. It stops after three attempts on the same check.
7. It reports each check's result.

```bash
claude plugin install greenlight@adrianj98-skills
```

or, without the plugin system:

```bash
./install.sh greenlight --global
```
