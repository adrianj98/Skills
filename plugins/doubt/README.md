# doubt

`/doubt` — question the analysis or diagnosis the AI just gave you, before you act on it.

```bash
claude plugin install doubt@adrianj98-skills
```

It splits the analysis into separate claims and tags each as **seen** (backed by output in
the conversation), **inferred** or **assumed**. It then marks the load-bearing ones, the
claims that would sink the conclusion if they were false. Those go to a subagent with a fresh
context that gets the claims but not the reasoning, so the argument can't talk it round. The
subagent reads the cited lines itself, runs the command that would show each claim, and asks
of every "X because Y" whether X still happens without Y.

Separately, it lists the explanations the analysis never ruled out.

The report is short. The first line is **Holds**, **Shaky** or **Wrong**, followed by only the
claims that failed or were never checked, the alternatives nothing rules out, and the one
check that would settle it. If everything held, the report is that first line and nothing more.

It never edits a file.

| | |
|---|---|
| `/doubt` | the last analysis in this conversation |
| `/doubt the race condition theory` | one part of it |
| `/doubt notes/postmortem.md` | an analysis written to a file |

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- doubt --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
