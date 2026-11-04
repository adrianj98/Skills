# walkthrough

`/walkthrough` — a tour of a change that shows before it tells, always published as an
artifact page. A clickable diagram of the path the change takes (each node jumps to its
stop), a numbers strip, a file map with tag pills and +/− bars, then three to eight stop
cards. Each card has a locator showing where you are on the path, a picture of what the
stop does (a branch diagram, a timing sequence, a before │ after panel, before → after shape
cards), the code with added lines tinted and numbered callouts, a `file:line` linked at the
head commit, and one to three sentences of why. Tests are a coverage grid. Under ~350 words
of prose, readable in five minutes.

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

| where | the visual |
|---|---|
| top | numbers strip: files, +/−, a bar of the change split by tag |
| hero | `flowchart LR` / `sequenceDiagram` / `stateDiagram-v2` of only what the change touches; changed, new and removed nodes styled apart; numbered nodes link to their stops |
| route | the stops as a numbered stepper |
| files | rows grouped by folder, tag pill (`core`, `shape`, `wire`, `test`, `noise`), role, +/− bar; noise collapsed |
| each stop | locator chips, then by what the stop does: a branch flowchart, a timing sequence, a before │ after split, shape cards, an old-vs-new value bar, or callouts on the lines that matter |
| tests | a grid of behaviours, ✓ linked to the test or an amber gap |

At most 12 nodes per diagram, named as the code names them. Mermaid is themed from the
page's colour tokens, so diagrams match in light and dark.

## How it works

It's a prompt, not a script. It reads the PR description, the commit messages, any
`aj-log.md` lines the branch added, and every changed file in full around each hunk. It
orders the stops the way the code runs, starting at the entry point, with the main idea in
the first three. Where nothing says why a change was made, it says so instead of guessing.
It never judges or edits the code.

It is always an artifact; there is no markdown fallback. The reply in chat is the link, the
two In short sentences and the hero diagram in ASCII. Ask for it on the PR and it posts a
short comment there with the diagram and the link.

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- walkthrough --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
