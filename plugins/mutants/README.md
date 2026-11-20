# Mutants

`/mutants` checks whether your JavaScript/TypeScript tests catch bugs, then fixes the ones
that don't. It changes tests only, never the source.

1. It runs Stryker one module at a time with per-test coverage. Stryker injects small bugs
   ("mutants") into the source and checks that some test fails.
2. `scripts/summarize.py` turns Stryker's JSON report into the surviving mutants and the
   zero-kill tests (tests that covered mutants and killed none).
3. It deletes zero-kill tests only when everything they exercise was mutated, they check
   nothing mutation can't reach, and another test covers the same behaviour.
4. It merges tests that differ only in which field they check, aiming for about one test per
   code path.
5. It tightens weak assertions or adds cases until the survivors die, fixing the test smells
   that hide them on the way. Equivalent mutants are marked; real bugs are reported.
6. It reruns Stryker to prove nothing that was killed now survives. Each step is tested and
   committed on its own, and reverted if the tests fail.

Steps 4 and part of 5 borrow from
[refactor-tests](https://github.com/SDiamante13/dotfiles/blob/main/claude/skills/refactor-tests/SKILL.md)
by SDiamante13: one file and one commit per step, consolidating to roughly one test per path,
and its list of assertion anti-patterns.

```bash
claude plugin install mutants@adrianj98-skills
```

or, without the plugin system:

```bash
./install.sh mutants --global
```
