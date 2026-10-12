# progress

`/progress` — where a branch and its pull request stand, in two sections: what it's about,
and its state.

```bash
claude plugin install progress@adrianj98-skills
```

**What it's about** is a paragraph: the problem, what changed, and why, read from the PR
description, the commit bodies and any `aj-log.md` lines the branch added. **State** is a
short list, in a fixed order: where the PR is (none yet, draft, open, merged), who approved
or is still being waited on and how many review threads are open, which checks fail,
whether it conflicts with or trails its base, what's uncommitted or unpushed locally, any
question in the conversation nobody answered, the Jira issues it names, and the one thing
left before it merges.

A script gathers it all first — `git` for the branch, `gh` for the PR, a GraphQL call for
review-thread resolution — so the model reads one page instead of running a dozen
commands. Without `gh` the GitHub parts are skipped and the branch is still described.

| | |
|---|---|
| `/progress` | the checked-out branch and its PR |
| `/progress 189` | a PR by number, whether or not its branch is local |
| `/progress feature/x` | a branch, local or remote |
| `/progress https://github.com/o/r/pull/189` | a PR by URL |

It never edits, fetches only to refresh the ahead/behind numbers, and suggests no commands.

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- progress --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
