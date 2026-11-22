---
name: strataport
description: Package the current plan and conversation context into a brief committed on the current branch, commit the work in progress, and push, so the same branch can be checked out in Claude Code on the web (claude.ai/code) or on another machine and the work continued there. With `resume`, read the brief for the current branch and carry on. Use when the user says /strataport, wants to continue this work online or on the web, move the session to another machine, take the plan with them, or pick up where a strataport left off.
argument-hint: "[nothing = package and push | a note on what to do next | resume]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

The user invoked this with `$ARGUMENTS`.

- **`resume`** — go to [Resume](#resume).
- **nothing, or any other text** — package this session. Any text is the user's note on what
  the next session should do first; it goes into **Next step** word for word.

A new session on the web starts with the repo at this branch and nothing else: no chat, no
plan mode state, no todo list, no local files that aren't pushed. The brief is the whole
handoff. Write it for a capable engineer who has never seen this conversation.

## 1. Check the branch

```bash
git rev-parse --abbrev-ref HEAD
git status --porcelain=v1
git remote -v
gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null
```

- **No remote** — stop. Say the branch has nowhere to go and the web can't see it.
- **Detached HEAD** — stop and ask which branch to put the work on.
- **On the default branch** — create a branch named for the work (`<topic-in-kebab-case>`),
  switch to it, and say so. Never push the brief to the default branch.

## 2. Write the brief

Path: `.claude/strataport/<branch>.md`, with every `/` in the branch name replaced by `-`.
If the file already exists, this is a second trip: rewrite it to the current state, keeping
anything from the old brief that is still true.

Build it from this conversation. Where the conversation had a plan (plan mode, a plan file,
a todo list, a spec), copy the plan itself, not a summary of it. If a plan file was written
under `~/.claude/plans/` or `docs/`, include its text: files outside the repo don't travel.

```markdown
# Strataport: <one-line goal>

Branch `<branch>` · from `<machine-independent description, e.g. "local CLI">` · <date>

## Goal
What the user wants and why, in their terms. What "done" looks like.

## Plan
The steps, each marked [x] done, [~] in progress, [ ] todo. For the step in progress, say
exactly how far it got.

## Decisions
Each decision made and the reason, including choices the user made. One line each.

## Ruled out
Approaches tried or considered and dropped, and why — so the next session doesn't retry them.

## Where things are
The files that matter, as `path:line` with a few words each. Commands to build, run and test,
and whether they passed last time they ran here (quote the failing output if not).

## Not on the branch
What the web session won't have: env vars it needs (names only, never values), local
services or databases, credentials, untracked files left out on purpose, MCP servers or
tools that were used here. Say how to get by without each, if there is a way.

## Open questions
Anything still waiting on the user.

## Next step
The one concrete thing to do first. If the user gave a note, put it here verbatim.
```

Rules for the brief:
- Facts from the session only. If something wasn't verified, say "unverified".
- **Never put a secret in it** — no tokens, passwords, keys, connection strings, or the
  contents of `.env` files. Names of variables only.
- No transcript. Quote the user only where their exact words matter (a requirement, a
  constraint, a rejected idea).
- Leave out empty sections.

## 3. Commit and push

Stage the work in progress and the brief:

```bash
git add -A
git status --porcelain=v1
```

Before committing, read the staged list. Unstage anything that looks like a secret or a local
artifact — `.env*`, `*.pem`, `*.key`, credentials files, `.claude/settings.local.json`, large
binaries, build output the `.gitignore` missed — and name each one under **Not on the branch**
in the brief. If a file you're unsure about would be needed on the other side, ask.

Commit. If code was mid-change, the message says so:

```bash
git commit -m "strataport: <goal> — WIP, see .claude/strataport/<file>.md"
git push -u origin HEAD
```

If the project hooks fail the commit because the work is half done, don't skip them; say what
failed and ask whether to commit with `--no-verify` or finish first.

Check the push landed:

```bash
git fetch origin "$(git rev-parse --abbrev-ref HEAD)"
git rev-parse HEAD "origin/$(git rev-parse --abbrev-ref HEAD)"
```

The two hashes must match. If they don't, say so — don't report success.

## 4. Tell the user

Keep it short:

1. The branch and the commit that was pushed.
2. What's **not on the branch**, if anything — one line each.
3. Where to go: <https://claude.ai/code>, pick this repo and branch `<branch>`.
4. The prompt to paste, in its own fenced block so it gets a copy button:

```text
Read .claude/strataport/<file>.md, then continue from "Next step". Run /strataport again before handing back.
```

## Resume

On the receiving side (web or another machine):

1. Find the brief. A cloud session often starts on the default branch or a branch of its own,
   so don't assume the brief is on the branch you're on.
   - If `.claude/strataport/<current-branch>.md` exists, `git pull` and use it.
   - Otherwise find the newest brief on any remote branch. Cloud clones can be shallow or
     single-branch, so fetch every branch first:

     ```bash
     git remote set-branches origin '*'
     git fetch --quiet origin
     git log --remotes=origin --diff-filter=AM -1 --format='%H %cI' -- .claude/strataport/
     ```

     The brief that commit added or changed names its branch on the line that starts
     `Branch`. Check it out (it tracks `origin/<branch>`):

     ```bash
     git switch <branch>
     ```

     Say which branch and brief you picked and how old it is.
   - No brief anywhere: say so and stop.
   - If more than one brief changed in the last day, list them (branch, goal line, age) and
     ask which one, rather than guessing.
2. Check the brief against the branch: run the test or build command it names and look at
   the files it points to. Say in a few lines what matches and what doesn't.
3. Rebuild the plan as a todo list, then do the **Next step**.
4. Before handing back, run the package steps above again: the brief is updated, committed and
   pushed, and the other side runs `/strataport resume`, which finds it the same way. If the
   push to the brief's branch is refused (some cloud sessions may only push to a branch of
   their own), push to the branch you're allowed to and write that branch on the brief's
   `Branch` line; resume still finds it as the newest brief.

When the work is done and merged, delete the brief in the last commit; it's history now.
