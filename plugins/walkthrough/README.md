# walkthrough

`/walkthrough` — a document that walks a reader through a pull request's code, in the order
they should read it. One stop per idea, each with the code as it is after the PR, a
`file:line` and a link at the head commit, what it does and why. Then the tests, the
plumbing and noise in one line each, and anything the code doesn't answer.

```bash
claude plugin install walkthrough@adrianj98-skills
```

| | |
|---|---|
| `/walkthrough` | the current branch's PR, or the branch against the default branch |
| `/walkthrough 189` | PR #189 |
| `/walkthrough feature/x` | that branch |

## How it works

It's a prompt, not a script. It reads the PR description, the commit messages, any
`aj-log.md` lines the branch added, and every changed file in full around each hunk. It sorts
the files into core, plumbing, shape, tests and noise, then orders the stops the way the code
runs, starting at the entry point, with the main idea early so a reader who stops after three
still understood the PR. Where nothing says why a change was made, it says so instead of
guessing. It never judges or edits the code.

The document goes to a docs connector or Artifact when the session has one; otherwise to an
untracked `walkthrough-<PR>.md` at the repo root.

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- walkthrough --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
