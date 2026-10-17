---
name: walkthrough
description: Write a code walkthrough of a pull request as a document — the change in the order a reader should take it, one stop per idea, each with the code, a file:line and why it is there. Point it at a PR number, a branch, or nothing for the current branch. Use when the user asks for a walkthrough, a code tour, a guided tour of a PR, a doc explaining a PR to reviewers or a new teammate, or "walk me through this PR".
argument-hint: "[PR number | PR URL | branch]   (nothing = the current branch)"
allowed-tools: Bash, Read, Grep, Glob, Write
---

The user invoked this with `$ARGUMENTS`.

A walkthrough is not a review and not a diff summary. It is the tour the author would give a
reviewer sitting beside them: *start here, this is the idea, now look at this, this is why.*
It never judges the code and never edits it. The only file it writes is the document.

## 1. Find the change

- **a number or PR URL** — `gh pr view <n> --json number,title,body,url,baseRefName,headRefName,author,commits,files`
  and `gh pr diff <n>`.
- **a branch** — its PR if it has one (`gh pr view <branch>`); otherwise the branch against
  the default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`,
  falling back to `origin/HEAD`): `git diff <base>...<branch>`.
- **nothing** — the current branch, the same way. On the default branch with no PR, say so
  and stop.

If `gh` is missing or not signed in, use the git diff and say the PR description was not read.

Read the diff against the **merge base** (`base...head`), never `base..head`: changes that
landed on the base since the branch forked are not part of this PR.

## 2. Understand it before ordering it

Read, in this order, until you can say in two sentences what the PR does and why:

1. The PR title and description, and any issue or Jira key it names.
2. The commit messages — they often say *why* where the description says *what*.
3. `aj-log.md` lines the branch added, if the repo has one.
4. Every changed file in full around each hunk, not just the hunk. A three-line change in a
   function is unreadable without the function. Open callers and callees the diff doesn't
   touch when a stop needs them.

Sort the files into:

| | |
|---|---|
| **core** | the change itself — new behaviour, the fix |
| **plumbing** | wiring the core in: registration, routes, DI, exports, config |
| **shape** | types, schemas, migrations the core depends on |
| **tests** | what proves it |
| **noise** | lockfiles, generated code, snapshots, renames, formatting-only hunks |

Noise gets one line at the end and no stops.

## 3. Choose the route

Order by how a reader builds understanding, never alphabetically or in diff order:

- Start at the **entry point** — the route, command, event, UI action or public function
  where the new behaviour begins — unless the PR is mostly a new data shape, in which case
  start with the shape.
- Follow the call path the way the code runs. Introduce a type or helper at the first stop
  that needs it, not before.
- Put the stop with the main idea early. A reader who stops after three stops should still
  have understood the PR.
- Tests come after the code they prove, as one stop that says what scenarios are covered and
  which aren't.
- Plumbing goes last, grouped.

One stop is one idea, usually 5–40 lines of one file. Split a big hunk that does two things;
merge small hunks across files that do one. Aim for 4–12 stops. A PR that needs more than
15 is several PRs; say so in the overview and group stops into parts.

## 4. Write each stop

````markdown
### 3. Retry the upload when the token has expired

`src/upload/client.ts:84-112`

```ts
<the changed code, trimmed to what this stop is about; elide with // …>
```

What it does, in two to five sentences, in terms of behaviour, not syntax. Then **why** —
from the description, a commit message or the code around it. If the why isn't written
anywhere, say "the PR doesn't say why" rather than inventing a reason.

**Before:** one line on how it behaved before, when that helps.
**Look at:** the one or two lines a reviewer should actually check here, if any.
````

- Quote the code **as it is after the PR**. Show the before side only when the change is the
  point (a condition flipped, a default changed), as a short `diff` block.
- Every stop has a `path:line` or `path:start-end` from the head of the PR. When the PR is on
  GitHub, also link it: `https://github.com/<owner>/<repo>/blob/<head sha>/<path>#L84-L112`
  (use the head commit sha, not the branch name, so links don't drift).
- Name things the way the code names them. No "this elegant approach", no "robust". Plain
  sentences.
- **Look at** is for things the reader needs to verify, not opinions: an ordering
  assumption, a value that crosses a boundary, a behaviour change for existing callers.

## 5. Assemble the document

```markdown
# Walkthrough: <PR title> (#<n>)

<link to PR> · <author> · <base> ← <head> · <files changed>, +<added> −<removed>

## In short
Two to four sentences: what changes for a user or caller, and why.

## The route
A numbered list of the stops' titles, so the reader sees the whole tour first.
Add one ```mermaid flowchart of the call path when the change spans 3+ components;
skip it otherwise.

## Stops
### 1. …
### 2. …

## Tests
What's covered, what isn't. How to run them, as a fenced command.

## Also in this PR
Plumbing and noise, one line each: `path` — what and why.

## Not answered by the code
Open questions — a missing why, behaviour the diff implies but doesn't show. Omit if none.
```

## 6. Deliver it

- If the session has a docs connector or an Artifact tool that its instructions say to use
  for documents, create the walkthrough there and give the link.
- Otherwise write it to `walkthrough-<PR number or branch>.md` at the repo root (replace `/`
  in branch names with `-`). Don't commit it and don't add it to `.gitignore`; tell the user
  the path in one line and that it's untracked.
- If the user asked for it posted on the PR, `gh pr comment <n> --body-file <file>` — only
  when asked.

Reply with the link or path and the "In short" paragraph. Don't repeat the document in chat.
