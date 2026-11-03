---
name: walkthrough
description: A concise, visual code walkthrough — a diagram of the path the change takes, a map of the files, then a few short stops each with the code, a file:line and why. Defaults to the PR branch; also takes a description ("the retry path", "how login works") that focuses the tour or, when there is no PR, picks the code to tour. Use when the user asks for a walkthrough, a code tour, to be walked through a PR, branch, feature or flow, or to explain a change to a reviewer or new teammate.
argument-hint: "[PR | branch] [description]   (nothing = the PR branch checked out now)"
allowed-tools: Bash, Read, Grep, Glob, Write, Artifact, Skill
---

The user invoked this with `$ARGUMENTS`.

A walkthrough is the tour the author gives a reviewer sitting beside them: *here is the
shape of it, start here, now look at this, this is why.* It is short enough to read in five
minutes and it shows before it tells. It is delivered as an **artifact**: one published page
with the diagram rendered. It never judges the code and never edits it.

## 1. Read the arguments

Split `$ARGUMENTS` into a **target** and a **description**:

- The first token is the target when it is a number, a PR URL, or a branch that
  `git rev-parse --verify --quiet <token>` or `origin/<token>` resolves. Everything after
  it is the description.
- Otherwise the target is the checked-out branch and the whole text is the description.
- Nothing at all: the checked-out branch, no description.

Then find the code to tour:

| target | how |
|---|---|
| number or URL | `gh pr view <n> --json title,body,url,baseRefName,headRefName,author,headRefOid,additions,deletions,changedFiles` and `gh pr diff <n>` |
| branch | its PR if one exists (`gh pr view <branch>`), else the diff against the default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`, falling back to `origin/HEAD`) |
| checked-out branch | the same, for `git branch --show-current` |

Always diff against the **merge base**, `base...head`, never `base..head`. If `gh` is
missing or signed out, use the git diff and say the PR description wasn't read.

**The description decides the scope.**

- With a diff, and the description names part of it ("the retry path", "just the
  migration"): tour only the stops that part needs. Mention in one line what the rest of
  the PR does.
- With a diff, and the description names nothing in it, or the checked-out branch is the
  default branch with no PR: tour the **code as it is**, not a diff. Find the entry point the
  description names (`grep`, routes, commands, exports), follow it, and treat the files on
  that path as the change set. Say at the top that this is a tour of the code, not of a PR.
- No description and the default branch is checked out with no PR: say so and stop.

## 2. Understand it

Read until you can say in one sentence what it does and why:

1. The PR title and description, and any issue it names.
2. The commit messages: they often carry the *why*.
3. Lines the branch added to `aj-log.md`, if the repo has one.
4. Each changed file **in full around every hunk**, not the hunk alone, plus the callers and
   callees it needs. A three-line change inside a function is unreadable without the function.

Tag each file:

| tag | |
|---|---|
| `core` | the change itself: the new behaviour, the fix |
| `shape` | types, schemas, migrations the core depends on |
| `wire` | registration, routes, DI, exports, config that plug the core in |
| `test` | what proves it |
| `noise` | lockfiles, generated code, snapshots, renames, formatting-only hunks |

## 3. Choose the route

Order by how a reader builds understanding, never alphabetically or in diff order:

- Start where the behaviour **begins**: the route, command, event, UI action or public
  function. If the PR is mostly a new data shape, start with the shape.
- Follow the call path the way the code runs. Introduce a type or helper at the first stop
  that needs it.
- The main idea is in the first three stops. A reader who stops there has still understood
  the PR.
- Tests are one stop after the code they prove. `wire` and `noise` get no stops; the file
  map covers them.

**3 to 8 stops.** One stop is one idea in one file, 5 to 15 lines of code. Split a hunk that
does two things, merge small hunks that do one. If it needs more than 8, split the tour
into parts with a heading each, or say the PR is really several and tour the biggest.

## 4. Draw it

Diagrams are the point. Pick by what the change is, and draw **only the part the change
touches**, with unchanged context nodes in plain style and changed ones highlighted:

| the change is | draw |
|---|---|
| a call path across 2+ files or components | `flowchart LR` of the path, one node per function or module, edges labelled with what crosses them |
| a request, event or message between actors or services | `sequenceDiagram` |
| a lifecycle or status field | `stateDiagram-v2` |
| a data shape | a before \| after table, not a diagram |
| one file, one function | nothing: the file map is enough |

Rules for every diagram:

- At most 12 nodes. More than that is a sign the tour is too wide.
- Nodes carry the code's own names: `uploadClient.send`, not "the upload layer".
- Mark changed nodes: in mermaid, `classDef changed stroke-width:3px` and `:::changed`; a
  new node also gets `(new)` in its label.
- Where the output can't render mermaid (plain terminal chat), draw the same thing in ASCII
  with `-->` arrows and `[brackets]`, and mark changed nodes with `*`.

The **file map** is a second visual, always present: a tree of the changed files, each with
its tag and three to six words on its role.

```
src/upload/
  client.ts          core   retry once on an expired token
  token.ts           shape  TokenState gains expiresAt
  index.ts           wire   export the client
test/upload.test.ts  test   expired, refreshed, refresh fails
package-lock.json    noise
```

## 5. Write it

````markdown
# <PR title> · #<n>

<PR link> · <author> · `<base>` ← `<head>` · <files> files, +<added> −<removed>

**In short.** One or two sentences: what changes for a caller or user, and why.

## Shape

```mermaid
<the one diagram from §4, or the before | after table>
```

## Files

```
<the file map>
```

## Stops

### 1. <Verb phrase: what this stop does> · `src/upload/client.ts:84`

```ts
<5–15 lines as they are after the change; elide with // …>
```

One to three sentences: what it does in terms of behaviour, then why, from the
description, a commit message or the surrounding code. If nothing says why, write "the
PR doesn't say why" rather than inventing one.

**Before →** one line on the old behaviour, only when the change is to existing behaviour.
**Check →** the one line a reviewer should actually verify here, only when there is one.

### 2. …

## Tests

One line on what's covered, one on what isn't, and the command to run them.

## Open

- A missing why, or behaviour the diff implies but doesn't show. Omit the section if none.
````

Budgets, hard:

- **Whole document under ~120 lines**, diagrams and code included. Cut stops before cutting
  the diagram.
- In short: 2 sentences. Each stop: 1 to 3 sentences of prose. Tests: 3 lines.
- Code is quoted **as it is after the change**. Show the before side only when the change
  is the point (a flipped condition, a changed default), as a 4-line `diff` block.
- Every stop has `path:line` or `path:start-end` at the head of the branch. When the PR is
  on GitHub, link it at the head **sha**, not the branch name, so links don't drift:
  `https://github.com/<owner>/<repo>/blob/<headRefOid>/<path>#L84-L112`.
- Names as the code names them. No "elegant", no "robust", no "simply". Plain sentences.
- **Check →** is for things to verify, never opinions: an ordering assumption, a value that
  crosses a boundary, a change in behaviour for existing callers.

For a tour of the code rather than a PR (§1): the title is the description, the header
line is the entry point's `path:line`, there is no Tests or Open section unless the code
has an obvious gap, and the file map lists the files on the path with their role instead
of a tag.

## 6. Deliver it as an artifact

The walkthrough is a page, not a chat message. Build it with the `Artifact` tool:

1. Load the `artifact-design` skill first if it's available; its page contract applies.
2. Write one HTML file in the scratchpad directory, `walkthrough-<PR number or branch>.html`
   (replace `/` in branch names with `-`), holding the §5 content in order: the title line,
   the **In short** paragraph, the Shape diagram, the Files map, the stops, Tests, Open.
   - Render the diagram with mermaid loaded from cdnjs at an exact version, for example
     `mermaid/11.4.1/mermaid.min.js`, initialised with `theme: 'neutral'` in light and
     `'dark'` in dark mode. Keep the mermaid source in the page as a `<pre class="mermaid">`.
   - Put the stop titles under the title line as a numbered list of in-page links, so the
     route is visible before the first stop.
   - Each stop's `path:line` is a link to GitHub at the head sha when the PR is there,
     otherwise plain text. Code goes in `<pre><code>` with the language as a class; a syntax
     highlighter from cdnjs is fine but not required.
   - Colours as tokens on `:root`, a dark variant under `prefers-color-scheme: dark`, an
     explicit `body` background, and nothing wider than a phone at a 16px gutter. The Files
     map and code blocks scroll sideways rather than the page.
3. Publish it: `Artifact` with that `file_path`, `icon: "map"`, and a one-sentence
   `description` from **In short**. The page `<title>` is `Walkthrough · #<n>` or
   `Walkthrough · <branch>`. Republish to the same path when the user asks for changes.

If there is no `Artifact` tool, write the same content as markdown to
`walkthrough-<PR number or branch>.md` at the repo root instead. Don't commit it or add it to
`.gitignore`; say the path in one line and that it's untracked.

The user asked for it on the PR as well: `gh pr comment <n> --body-file <markdown file>`.
GitHub renders mermaid. Only when asked.

Reply with the artifact link (or the file path), the **In short** sentences, and the ASCII
form of the diagram so the reader in a terminal sees the shape without opening the page.
Don't repeat the document in chat.
