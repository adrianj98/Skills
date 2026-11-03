# walkthrough

`/walkthrough` — a concise, visual tour of a change. One diagram of the path the change
takes, a map of the changed files, then three to eight short stops, each with the code as it
is after the change, a `file:line` linked at the head commit, what it does and why. Under
about 120 lines, readable in five minutes, published as an artifact.

```bash
claude plugin install walkthrough@adrianj98-skills
```

| | |
|---|---|
| `/walkthrough` | the checked-out branch's PR, or the branch against the default branch |
| `/walkthrough 189` | PR #189 |
| `/walkthrough feature/x` | that branch |
| `/walkthrough 189 the retry path` | PR #189, only the stops the retry path needs |
| `/walkthrough how login works` | a tour of the login code as it is, no PR needed |

The first argument is the target when it's a PR number, URL or branch; anything else is a
description. A description that names part of the diff narrows the tour to it. One that
names nothing in the diff, or given on the default branch, tours the code itself: it finds
the entry point the description names, follows it, and treats the files on that path as the
change set.

## What it draws

| the change is | the diagram |
|---|---|
| a call path across files | `flowchart LR`, changed nodes highlighted, new ones marked |
| a request or event between services | `sequenceDiagram` |
| a lifecycle or status field | `stateDiagram-v2` |
| a data shape | a before / after table |
| one function | none; the file map is enough |

At most 12 nodes, named as the code names them. Where mermaid can't render, the same
diagram in ASCII. The file map is always there: a tree of the changed files, each tagged
`core`, `shape`, `wire`, `test` or `noise` with a few words on its role.

## How it works

It's a prompt, not a script. It reads the PR description, the commit messages, any
`aj-log.md` lines the branch added, and every changed file in full around each hunk. It
orders the stops the way the code runs, starting at the entry point, with the main idea in
the first three. Where nothing says why a change was made, it says so instead of guessing.
It never judges or edits the code.

The walkthrough is published as an artifact: one HTML page, the diagram rendered with
mermaid, the route as a list of links at the top, every `file:line` linked to GitHub at the
head sha. Where there is no Artifact tool it falls back to an untracked `walkthrough-<PR>.md`
at the repo root. Ask for it on the PR and it posts there as a comment too.

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- walkthrough --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
