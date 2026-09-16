---
name: deslop
description: Find the AI slop in recent changes — comments that restate the code, defensive checks on trusted values, dead abstraction, placeholder stubs, inflated README prose — and report it, or with `run`, cut it. Use when the user asks to deslop, to find AI slop, to clean up AI-generated code or writing, or to check whether a change reads like a person wrote it.
argument-hint: "[run] [all | PATH...] [--base REF] [code | prose]"
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

Mechanical scan of what changed, already run:

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh" 2>&1`

The user invoked this with `$ARGUMENTS`.

- **no argument** — report only, on the scan above.
- **`run`** — report, then cut what the report justifies cutting.
- **`all`**, or paths — rerun as `scan.sh --all` or `scan.sh <path>...` and use that output
  instead. `--base REF` passes straight through. `code` / `prose` narrows which categories
  you bother with.

## What that output is

Candidates. Not findings. The scan is a recall net with the precision knob turned all the
way down — it cannot see a caller, a type, or the rest of the file, so it flags the house
style of a repo as readily as it flags slop. On this very repo it flags `# ---- section ----`
banners that a human wrote on purpose.

Your job is the part it can't do: decide which candidates are slop **in this codebase**, and
find the slop it structurally cannot match.

## 1. Learn the baseline first

Before judging a single line, read three to five files in the same tree that the diff did
*not* touch, plus `CLAUDE.md` / `CONTRIBUTING.md` / the lint config if they exist. You are
measuring one thing: what does code written by this repo's authors look like?

- How dense are comments, and do they explain *why* or narrate *what*?
- Does error handling trust internal callers, or check everything everywhere?
- Do log lines exist in this layer at all?
- Are docstrings the convention, or the exception?
- Does the prose here use em dashes and bolded bullet leads natively? (In this repo: yes,
  heavily. A density number means nothing until you've looked.)

Every finding you report is then phrased as a deviation from *that*, not from some idea of
how code should look. **"Inconsistent with the rest of this file" is a finding. "This feels
AI-written" is not.** If you can't say which neighbor file establishes the convention you're
appealing to, you don't have a finding.

## 2. Look for what grep can't see

The scan matches single lines. Most real slop is shaped, so go read the diff (`git diff`
against the scan's base) with these in mind:

- **Multi-line swallowed errors** — `try` blocks that catch, log, and continue as if nothing
  happened; `catch` bodies that re-throw the same error with a fatter message.
- **Abstraction with one caller** — a wrapper, interface, factory, or config object that
  exists once. `grep -c` the symbol. One definition plus one call site is a function that
  should be inlined, or a layer that should not exist.
- **Duplicated blocks inside the same diff** — the same twenty lines in two files, or two
  near-identical test setups. If `jscpd` is around (the scan's last section says what's
  installed), it will find these faster than you.
- **Dead on arrival** — exports nobody imports, params nobody reads, a flag with one branch,
  a back-compat shim for a symbol introduced in the same change. `knip`, `ts-prune` and
  `vulture` prove this properly; your own grep for the symbol is the cheap version.
- **Tests that assert the mock** — a test whose only assertion is that a function it stubbed
  was called, or that covers the same failure domain as the test above it.
- **Restated docs** — a README section, a docstring, or a comment block that says again what
  the code below it already says. Also: a summary paragraph at the end of a doc that adds
  nothing.

## 3. What is not slop, ever

Protected by default. Cutting one of these is a bug, not a cleanup:

- Security, authorization, and input validation at a **trust boundary** — anything touching
  data from a user, a network, a file, or another service.
- Concurrency, transaction, and ordering invariants, however over-cautious they look.
- Anything load-bearing for a persisted format, a public API, or a wire protocol.
- Comments that record a *reason*: a bug number, an RFC, a benchmark, a "looks wrong but",
  a workaround for a named upstream defect. Length is not the test — a forty-line comment
  explaining why a lock is taken in this order is the best line in the file.
- Licence headers, generated files, vendored code, fixtures that are duplicated on purpose.
- Error handling whose absence would lose data or corrupt state.

When a candidate is one of these, say so in the "kept" section rather than silently dropping
it. That list is what makes the rest of the report believable.

## 4. Rank what's left

Two axes, both stated per finding:

| severity | |
|---|---|
| `behavioral` | it can change what the program does — a swallowed error, an `as any` hiding a real type mismatch, a fallback that masks a missing value |
| `maintenance` | dead code, duplication, an abstraction with one caller, a shim for nothing |
| `noise` | restating comments, banners, emoji, log lines nobody reads, inflated prose |

| confidence | |
|---|---|
| `high` | mechanically corroborated — the symbol has no other reference, the type is inferable, the comment repeats the line under it verbatim |
| `medium` | your judgement, with a named neighbor file as the convention it breaks |
| `low` | taste |

## 5. Report

A table, most severe first:

```
file:line   category   severity/confidence   what it is   what to do instead
```

Then, briefly: counts by category, and a **Considered and kept** list with a clause each for
why. Close with two or three sentences on whether this change reads like the rest of the
codebase, and nothing else — no restating the table you just wrote.

Say the honest number. If the scan lit up and almost none of it survived adjudication, the
report is "18 candidates, 2 findings" and that is a good outcome, not a failed run.

## 6. `run` — cutting it

Report first, then apply. Only these get applied without asking:

- `noise`, at any confidence — comments, banners, emoji, dead log lines, prose rewrites.
- `maintenance` at `high` confidence — dead code a tool proved unreachable, an unused param,
  a single-call wrapper you inlined.

Everything `behavioral`, and anything at `low` confidence, is **reported as a suggestion and
left alone**. Removing a defensive check is a behavior change even when the check is useless,
and it is the user's call.

Then:

1. **Cut by subtraction, never by redesign.** Deleting a wrapper is in scope. Rewriting the
   function it wrapped is not. If a fix wants to become a refactor, stop and report it.
2. **Never make code and its tests justify each other.** A test that only exists to cover a
   defensive branch dies *with* that branch, in one edit. And if a test starts failing, the
   test is right and your edit is wrong — revert it; do not adjust the assertion.
3. **Verify.** Run the repo's typecheck, linter, and the tests covering the touched files —
   whatever `package.json` / `Makefile` / `pyproject.toml` actually defines. If nothing is
   defined, say so rather than claiming it's verified.
4. **Show the diff of your own cuts**, grouped by category, and state plainly what you left
   behind and why.

Prose gets the same restraint: rewrite in place, keep every factual claim and code sample
intact, and don't touch source files in a prose pass. Read the rewrite back once — a
de-slopped paragraph has a way of arriving with fresh tells.
