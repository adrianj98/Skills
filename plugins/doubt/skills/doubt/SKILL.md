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
claims ("X because Y") are almost always load-bearing and almost always only inferred, so
split every one into its own claim: Y exists, and Y is what produces X. Anchored diagnoses
usually get the first right and the second wrong.

Rewrite each load-bearing claim so it stands alone: name the file, function, line, commit,
config key or input it is about, so that someone who never saw the conversation could check it.

## 2. Check them, in a fresh context

Models that reread their own reasoning repeat its mistakes, and a model asked "are you sure?"
tends to cave whether it was right or not. Verification therefore happens away from both:
each claim is checked by a subagent that sees neither the analysis nor any hint that it is
in doubt.

Spawn one general-purpose subagent (Agent tool) per load-bearing claim, all in parallel.
Five at most; if there are more, batch claims that have nothing to do with each other.
Send each one the standalone claim turned into an **open question** about the system, never a
yes/no confirmation. Ask "What does `parseDate` in src/util/date.ts return for an empty
string?" rather than "Confirm that `parseDate` returns null for an empty string". Don't send
the analysis, its reasoning or the symptom story. Tell it:

- Answer from evidence gathered now: read the file itself, grep for other writers or
  callers, run the command or test that shows it, check the version or config actually in
  use. Reasoning alone is not an answer. If it can't be observed, say so.
- Don't modify files. Scratch commands go in the scratchpad.
- Return the answer, the evidence (a `file:line`, or the command and its output), and anything
  relevant it noticed that the question didn't ask about.

To test a causal claim, ask what happens with the cause removed. For example: "With the TTL
line in src/cache.ts:41 moved before the write, does test X still fail?"

Then compare each answer with its claim yourself, and check the **seen** claims directly: does
the quoted output say that, or was it paraphrased into something stronger?

**Evidence gate.** A claim becomes `wrong` only when evidence observed in this run
contradicts it. It becomes `holds` only when evidence observed in this run supports it.
Everything else is `unverified`. Doubt is not evidence. Don't flip a claim because you were
asked to question it, and don't keep one because you wrote it.

## 3. Competing explanations

List the explanations the analysis never ruled out: other code paths, environment
differences, a recent commit, caching, concurrency, the test itself being wrong, the symptom
being misread. For each, write one prediction that tells it apart from the analysis's
explanation: "if A, X happens; if B, it doesn't". Evidence that fits both explanations
proves neither, so discount it.

Run the cheapest distinguishing check or two, if a command or a file read will do it. Name
the rest.

## Report

Short. Lead with the verdict in one line:

- **Holds** — every load-bearing claim checked out.
- **Shaky** — the conclusion may be right but a load-bearing claim is unverified.
- **Wrong** — a load-bearing claim is false.

Then only what the user needs to act on:

- each claim that is `wrong` or `unverified`, one line: the claim, and the evidence or the
  missing check
- alternative explanations nothing rules out, one line each, with the check that would
  separate them
- if the verdict isn't **Holds**: the one check that would settle it, as a command or file
  to read

Leave out claims that held, the claim list itself, and the process. If everything held, the
verdict line is the whole report.
