---
name: mutants
description: Mutation-test JS/TS modules with Stryker and fix the tests from the result — run it module by module, read the surviving mutants and the tests that killed nothing, delete the zero-kill tests that are safe to drop, consolidate duplicates, and rewrite weak assertions until they kill the survivors, proving each change with a rerun. Use when the user says /mutants, asks for mutation testing or Stryker, wants to know whether their tests actually catch bugs, or wants useless tests pruned and weak assertions strengthened.
argument-hint: "[file or directory — nothing = source files changed on this branch; 'all' = every module, one at a time]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

The user invoked this with `$ARGUMENTS`.

- **nothing**: the `.ts`/`.tsx`/`.js`/`.jsx` source files changed on this branch against the
  default branch, minus tests, generated code and config:

  ```bash
  base=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
  git diff --name-only "origin/$base"...HEAD
  ```

- **a file or directory**: the source files in it.
- **all**: every source module, one at a time. Say first that this can take hours.

JavaScript and TypeScript only. This skill changes tests only; it never edits the source under
test. If a survivor shows a real bug in the source, report it and leave the source alone.

## 1. Set up Stryker

Run from the package that owns the module (in a monorepo, its workspace directory). Use the
runner its tests already use: `@stryker-mutator/vitest-runner`, `jest-runner` or
`mocha-runner`. If Stryker is not in `devDependencies`, install it with the package's own
manager and tell the user you did:

```bash
yarn add -D @stryker-mutator/core @stryker-mutator/vitest-runner   # or npm i -D / pnpm add -D
```

Leave that `package.json` and lockfile change out of your commits unless the user wants it kept.

## 2. Run it, one module at a time

One module per run keeps each run short and each report readable. Per-test coverage is what
makes zero-kill tests visible, so always pass it:

```bash
npx stryker run --mutate '<path/to/module.ts>' --testRunner vitest \
  --coverageAnalysis perTest --reporters json,clear-text,progress \
  --jsonReporter.fileName "reports/mutation/<module>.json"
```

Then summarize the report:

```bash
python3 "${CLAUDE_SKILL_DIR}/summarize.py" reports/mutation/<module>.json
```

If `${CLAUDE_SKILL_DIR}` is not filled in, `summarize.py` is in this skill's base directory.

The summary gives the module's score, each `Survived` or `NoCoverage` mutant with its line,
mutator, replacement and the tests that covered it, and the zero-kill tests: tests that ran
against mutants in this run and killed none. Record the score; it is the baseline for step 6.

Work through steps 3 to 5 on one test file at a time. After each step that changes something,
run that file's tests. If they fail, revert the step. If they pass, commit it on its own
(`test(<module>): remove zero-kill tests`, `… consolidate`, `… kill survivors`), so any one
step can be reverted later.

## 3. Prune the zero-kill tests

A zero-kill test is a **candidate**, not a verdict. It killed nothing among this module's
mutants; it may still be the only guard on something else. Delete it only when every one of
these holds:

- Every module it exercises was mutated in this run (read its imports and what it calls). A
  test of module B that also touches A is not judged by A's run.
- It does not check something mutation cannot reach: a thrown error type, an emitted event or
  metric, a call to a command (a mock with a side effect), a snapshot, a regression with an
  issue reference.
- Another test asserts the same behaviour, at least as strictly.

Tests that usually pass all three: trivial getters and setters, tests that only check a value
is defined, tests of implementation details (call order of internals, cache hits, private
helpers exported only for the test). Test private helpers through the public function that
uses them.

If a candidate checks the right behaviour with a weak assertion, strengthen it in step 5
instead of deleting it.

## 4. Consolidate

Merge tests that run the same code path and differ only in which field of the result they
check: one test, one `toEqual` on the whole result. Aim for about one test per path through
the code. As a sanity check, count the module's decision points (`if`, `else`, `case`, `catch`,
`for`, `while`, `&&`, `||`, `??`, `?:`); one plus that number is a rough ceiling on how many
unit tests it needs. Far above it usually means duplicates, not thoroughness. It is a hint, not
a target to delete down to.

## 5. Strengthen against the survivors

For each survivor, read the mutated line and ask what input makes the mutant behave
differently from the original. Then:

- **Tighten an existing assertion** when a test already reaches the line: the exact value, not
  that one exists; the boundary (`<` vs `<=` needs the equal case); the branch not taken.
- **Add a test case** when no test reaches it (`NoCoverage`) or none uses an input that tells
  the two apart. Follow the file's style and helpers; put big fixtures in a builder and keep
  only the fields that matter to the test in it.
- **Mark it equivalent** when no input can tell them apart. Say why in one line. Do not write
  a test for it.
- **Report a bug** when the only way to kill it shows the source is wrong. Do not fix the
  source.

While rewriting, fix these on the way, since each hides survivors:

- `expect(fn).toHaveBeenCalledWith(...)` on a function that returns a value: stub it and
  assert what the code does with the value. Keep call assertions for commands (side effects).
- `expect(list).toHaveLength(n)` followed by checks on each element: one `toEqual` on the list.
- Loops, `if`s or `try`/`catch` inside a test: a test has one path. Use `it.each` or separate
  tests, and `rejects.toThrow` / `toThrow`.
- Mocks of the code's own modules: mock only what crosses a boundary (network, filesystem,
  clock, randomness, database). Use real objects otherwise.

Assert what a caller depends on. A test that pins the exact line the mutant changed, and
nothing a caller would notice, is a worse test.

## 6. Prove it

Rerun step 2 on the module, and the module's whole test suite.

- Every test passes.
- No mutant `Killed` in the baseline is now `Survived`. If one is, a deleted or merged test
  was doing work: restore it.
- Each survivor you worked on is killed now, or marked equivalent, or reported as a bug.

## 7. Report

| Module | Score before | Score after | Tests before | Tests after | Survivors killed | Equivalent | Left |
|---|---|---|---|---|---|---|---|

Copy the scores from the reports; do not compute them by hand. Then list each deleted test
(file:line, name, which test covers it now), each equivalent mutant (file:line, why), any
source bug, and any survivor left and why. If a module needed nothing, say so in one line.
