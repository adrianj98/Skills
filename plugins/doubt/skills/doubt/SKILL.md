---
name: doubt
description: Question an analysis, diagnosis or root-cause explanation the AI gave — break it into claims, check each load-bearing one against the code, logs or a command, look for explanations it skipped, and say what holds, what's wrong and what was never verified. Use when the user doubts a diagnosis, asks "are you sure?", "prove it", "question that", "challenge this analysis", or wants a conclusion double-checked before acting on it.
argument-hint: "[what to question — nothing = the last analysis in this conversation; or pasted text / a file]"
allowed-tools: Bash, Read, Grep, Glob, Agent
---

The user invoked this with `$ARGUMENTS`.

- **nothing** — question the most recent analysis, diagnosis or explanation in this
  conversation.
- **a path** — question the analysis written in that file.
- **anything else** — pasted text, or a pointer ("the race condition theory"). Question that.

This skill checks and reports. It never edits a file and never fixes the bug it is reading
about.

The analysis was written by a model that wanted it to be right. Treat it as a suspect's
statement, not a colleague's notes: every claim is unproven until something outside the
analysis proves it.

## 1. Pull out the claims

Rewrite the analysis as a numbered list of separate, checkable claims. One fact per line.
"The cache returns stale data because the TTL is set after the write" is two claims: the
cache returns stale data; the TTL is set after the write; and a third, that the second causes
the first.

Tag each:

- **seen** — backed by output that actually appears in this conversation (a command result,
  a file read, a log line). Quote where.
- **inferred** — reasoned from seen facts.
- **assumed** — stated with nothing behind it. Includes anything about runtime behaviour,
  config, versions or data that nobody looked at.

Mark the **load-bearing** claims: the ones that, if false, make the conclusion false. Causal
claims ("X because Y") are almost always load-bearing and almost always only inferred.

## 2. Check them, in a fresh context

Hand the load-bearing claims — the claim list only, not the analysis's reasoning — to one
general-purpose subagent (Agent tool). A context that never read the argument can't be
talked into it. Tell it:

- For each claim, find evidence **for and against** it: read the cited `file:line` yourself
  (it may not say what the analysis says it says), grep for other writers or callers, run
  the command that would show it, check the version or config actually in use.
- Prefer running something to reasoning about it. A claim "verified" by rereading the same
  code the analysis read is still only inferred.
- For each causal claim: would the effect still happen if the cause were removed? Is there
  a simpler cause that fits the same symptoms?
- Don't modify files. Scratch commands go in the scratchpad.
- Return per claim: `holds` / `wrong` / `unverified`, one line of evidence with a
  `file:line` or the command and its output, and anything it found that the claim list
  never mentioned.

Check the **seen** claims yourself, quickly: does the quoted output say that, or was it
paraphrased into something stronger?

## 3. Look for what it skipped

On your own, list the alternative explanations the analysis never ruled out — other code
paths, environment differences, a recent commit, caching, concurrency, the test itself being
wrong, the symptom being misread. For each, say in one line whether something already rules
it out. Don't chase them all; name them.

## Report

Short. Lead with the verdict in one line:

- **Holds** — every load-bearing claim checked out.
- **Shaky** — the conclusion may be right but a load-bearing claim is unverified.
- **Wrong** — a load-bearing claim is false.

Then only what the user needs to act on:

- each claim that is `wrong` or `unverified`, one line: the claim, and the evidence or the
  missing check
- alternative explanations nothing rules out, one line each
- if the verdict isn't **Holds**: the one check that would settle it, as a command or file
  to read

Leave out claims that held, the claim list itself, and the process. If everything held, the
verdict line is the whole report.
