# greenlight

`/greenlight` — merge the repository's default branch into your branch, push it, run CI on
it on GitHub Actions, integration tests included, and get a verdict a model can only copy,
not infer.

```bash
claude plugin install greenlight@adrianj98-skills
```

The script asks GitHub which branch is the default, so it works whatever that branch is
called, and fetches it. On any other branch it merges the default branch into the current
branch and pushes, so CI tests your branch as it would be after merging; it refuses when
tracked files have uncommitted changes, and aborts a merge that conflicts. On the default
branch itself, or with `--default`, it tests the default branch as it is and touches
nothing. Then it dispatches every CI workflow on that branch — one that runs on
`pull_request` or on `push` to branches and has a `workflow_dispatch` trigger — waits for
the runs, takes **one final `gh run view` snapshot per run** and judges only that. A workflow that only runs on tags or
only by hand (a release) is listed but never dispatched unless you name it.

It prints `GREENLIGHT PASS` and exits 0 only when, in those snapshots:

- every run and every job concluded `success` — skipped, cancelled and neutral all fail
- the run's sha is the sha it tested: the merge it pushed, or the default branch it fetched
- at least one job matches the integration pattern (`integration|e2e|end.to.end|functional|acceptance`, or `--match`), and inside it no test step was skipped and the log does not say zero tests ran
- every status check the default branch requires, by branch protection or ruleset, ran in these runs and succeeded
- every dispatched workflow actually started

Anything else is `GREENLIGHT FAIL` with one reason per line, and exit 1. The skill tells the
model to report the verdict line verbatim, and output with no verdict block as "did not
complete", never as passed.

| | |
|---|---|
| `/greenlight` | merge the default branch into this branch, push, dispatch every CI workflow on it, wait, judge |
| `/greenlight --default` | test the default branch itself; fetch only, never merge |
| `/greenlight ci` | only that workflow (file name or `name:`); the only way a manual-only workflow runs |
| `/greenlight --latest` | merge, push and dispatch nothing; judge the newest completed run of each CI workflow on the pushed sha, which must already contain the default branch |
| `/greenlight --match 'browser\|e2e'` | what counts as the integration job |
| `/greenlight --timeout 90` | wait up to 90 minutes (default 45) |

Needs `git`, `gh` logged in, and `jq`. If no CI workflow has `workflow_dispatch`, the verdict
says which file to add it to.

```text
== jobs
run 36939535547 functional.yml  https://github.com/o/r/actions/runs/36939535547
  ✓ default build                    success    4m40s    [integration] [required]
  ✓ no BLE, no GUI                   success    3m28s

== verdict
GREENLIGHT PASS  main@608aa51  https://github.com/o/r/actions/runs/36939535547
```

`bash scripts/greenlight.test.sh` runs the script against a fake `gh` for every verdict rule.

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- greenlight --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
