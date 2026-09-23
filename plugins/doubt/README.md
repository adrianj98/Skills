# doubt

`/doubt` — question the analysis or diagnosis the AI just gave you, before you act on it.

```bash
claude plugin install doubt@adrianj98-skills
```

It splits the analysis into separate claims and tags each as **seen** (backed by output in
the conversation), **inferred** or **assumed**. It then marks the load-bearing ones, the
claims that would sink the conclusion if they were false, and splits every "X because Y" into
two claims: Y is there, and Y is what causes X. Each claim goes to its own subagent as an open
question about the code. The subagent never sees the analysis and gets no hint that anyone
doubts it, and it has to answer from a file it read or a command it ran.

Separately, it lists the explanations the analysis never ruled out, gives each one a
prediction that tells it apart from the main explanation, and runs the cheapest of those
checks.

The report is short. The first line is **Holds**, **Shaky** or **Wrong**, followed by only the
claims that failed or were never checked, the alternatives nothing rules out, and the one
check that would settle it. If everything held, the report is that first line and nothing more.

It never edits a file.

| | |
|---|---|
| `/doubt` | the last analysis in this conversation |
| `/doubt the race condition theory` | one part of it |
| `/doubt notes/postmortem.md` | an analysis written to a file |

## Why it works this way

- **Fresh context, open questions.** In Chain-of-Verification, answering verification
  questions without the draft in view beat checking with it in view. Models that could see
  their own hallucination tended to repeat it, and yes/no questions got agreement whether
  the fact was true or false.
  [Dhuliawala et al. 2023](https://arxiv.org/abs/2309.11495)
- **Evidence, not reflection.** When a model corrects itself with no outside feedback, it
  doesn't get better and sometimes gets worse. What works is outside feedback such as running
  the code or using a tool.
  [Huang et al. 2023](https://arxiv.org/abs/2310.01798),
  [Kamoi et al. 2024](https://arxiv.org/abs/2406.01297)
- **Neither rubber-stamp nor cave.** LLM judges rate their own output higher than equal work
  from others ([Panickssery et al. 2024](https://arxiv.org/abs/2404.13076)). They also drop
  correct answers when asked "are you sure?"
  ([Sharma et al. 2023](https://arxiv.org/abs/2310.13548),
  [Laban et al. 2023](https://arxiv.org/abs/2311.08596)). So there's an evidence gate:
  a claim changes status only on evidence observed in this run.
- **Standalone atomic claims.** From SAFE: each claim is rewritten so it can be checked with
  no surrounding context. [Wei et al. 2024](https://arxiv.org/abs/2403.18802)
- **Competing hypotheses.** Premature closure is the most common cognitive cause of
  diagnostic error ([Graber et al. 2005](https://jamanetwork.com/journals/jamainternalmedicine/fullarticle/486642)),
  and anchoring hurts LLM root-cause agents the same way
  ([2026](https://arxiv.org/abs/2601.22208)). Heuer's Analysis of Competing Hypotheses
  counts only the evidence that tells hypotheses apart.

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- doubt --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
