# deslop

`/deslop` — what in this change reads like a machine wrote it, as a report you can act on.
`/deslop run` finds it and cuts it in one pass.

```bash
claude plugin install deslop@adrianj98-skills
```

Slop is the stuff that survives code review because none of it is *wrong*: the comment that
says `// Increment the counter`, the `try/catch` around a call that can't throw, the wrapper
with one caller, the `as any` that made the error go away, the README paragraph about
leveraging a robust and comprehensive toolkit. Every piece of it is defensible on its own,
and together they are how a codebase stops sounding like anyone.

## How it works

Two halves, because the two halves are good at different things.

**The scan** (`scripts/scan.sh`) is deterministic and deliberately over-eager. It walks the
lines *added* since your branch left its base — working tree and untracked files included,
since a file nobody has `git add`ed yet is exactly what an assistant leaves behind — and
matches ~17 pattern families across code and prose: restating comments, section banners,
type escapes, swallowed errors, defensive fallbacks, placeholders, inflated naming,
re-implemented stdlib, log noise, emoji, test theater, back-compat shims, and the prose tells
from [Wikipedia's *Signs of AI writing*](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing).
It also prints a density table — em dashes, emoji and bolded bullet leads per file — because
one em dash is punctuation and seventy is a fingerprint.

It has no idea what any of it means. That's the point: it's recall, and it will happily flag
a banner comment a human wrote on purpose.

**The skill** does the judging, and it has one rule above the others: *slop is relative to
the codebase it's in*. Before ruling on anything it reads a few files the diff never touched,
to learn what this repo's authors actually write — comment density, how much the error
handling trusts its callers, whether the prose uses em dashes natively. A finding then has to
name the convention it breaks. "Inconsistent with the rest of this file" is a finding; "this
feels AI-written" is not.

It also goes looking for the shaped slop a line-matcher structurally cannot see: the
abstraction with exactly one caller, the block duplicated twice in the same diff, the export
nobody imports, the test whose only assertion is that a mock got called.

Findings come back ranked on two axes — `behavioral` / `maintenance` / `noise`, and
`high` / `medium` / `low` confidence — alongside a **Considered and kept** list, which is the
part that makes the rest of it trustworthy.

## Cutting it

`/deslop run` applies only what's safe to apply without asking: noise at any confidence, and
maintenance slop at high confidence. Anything that could change behavior — a defensive check
that is probably useless, a fallback that is probably dead — is reported and left alone,
because removing a useless check is still a behavior change and still your call.

Three rules it holds to while cutting:

- **Subtraction, never redesign.** Deleting a wrapper is in scope. Rewriting what it wrapped
  is not.
- **Code and tests don't get to justify each other.** A test that exists only to cover a
  defensive branch dies with that branch, in the same edit.
- **A failing test is right and the edit is wrong.** Revert; never adjust the assertion.

Then it runs whatever the repo defines as typecheck / lint / tests, and says so plainly if
the repo defines nothing.

## Scope

| | |
|---|---|
| `/deslop` | lines added since this branch left its base, working tree and untracked included |
| `/deslop all` | every line of every tracked file — a whole-repo audit |
| `/deslop src/api` | every line of those paths, changed or not |
| `/deslop --base HEAD~3` | measure against a different base |
| `/deslop code` · `/deslop prose` | only one side of it |
| `/deslop run …` | any of the above, then cut |

The scan skips lockfiles, builds, vendored trees, generated code and binaries, and honours
`.gitignore`. `DESLOP_MAX` and `DESLOP_MAX_TOTAL` cap how much of a large result gets listed
rather than counted.

`scripts/scan.sh` runs standalone, too, if you'd rather read the raw candidates yourself:

```bash
bash scripts/scan.sh --base origin/main
bash scripts/scan.sh --all
```

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- deslop --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
