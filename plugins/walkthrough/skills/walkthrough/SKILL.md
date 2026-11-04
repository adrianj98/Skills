---
name: walkthrough
description: A highly visual code walkthrough published as an artifact page — a clickable diagram of the path the change takes, a file map with change bars, then a few short stops each with a locator, a diagram or before/after panel, annotated code, a file:line and why. Defaults to the PR branch; also takes a description ("the retry path", "how login works") that focuses the tour or, when there is no PR, picks the code to tour. Use when the user asks for a walkthrough, a code tour, to be walked through a PR, branch, feature or flow, or to explain a change to a reviewer or new teammate.
argument-hint: "[PR | branch] [description]   (nothing = the PR branch checked out now)"
allowed-tools: Bash, Read, Grep, Glob, Write, Artifact, Skill
---

The user invoked this with `$ARGUMENTS`.

A walkthrough is the tour the author gives a reviewer sitting beside them: *here is the
shape of it, start here, now look at this, this is why.* It is short enough to read in five
minutes and it **shows before it tells**: a page of diagrams, maps and annotated code with
short captions. It is always delivered as a published **artifact**, never a markdown file.
It never judges the code and never edits it.

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

The page shows before it tells. **Every section has a picture, and every stop has at least
one visual beside its code.** Prose is the caption, never the main thing. If a sentence
describes a shape, flow, order or comparison, draw it.

### The hero diagram (always, at the top)

Pick by what the change is, and draw **only the part the change touches**. Unchanged
context nodes get the plain style and changed ones are highlighted:

| the change is | draw |
|---|---|
| a call path across 2+ files or components | `flowchart LR` of the path, one node per function or module, edges labelled with what crosses them |
| a request, event or message between actors or services | `sequenceDiagram` |
| a lifecycle or status field | `stateDiagram-v2` |
| a data shape | before → after cards (below), plus a flowchart of who reads and writes it |
| one file, one function | a `flowchart TD` of the function's branches, the changed branch highlighted |

Rules:

- At most 12 nodes. More than that is a sign the tour is too wide.
- Nodes carry the code's own names: `uploadClient.send`, not "the upload layer".
- Changed nodes: `classDef changed` with the accent colour and a thick stroke. New nodes:
  `classDef added` in the "added" colour, with `(new)` in the label. Removed nodes:
  `classDef removed`, dashed and struck through.
- **Number the nodes by stop**: a node a stop covers gets a `①②③` badge in its label and a
  mermaid `click <node> href "#stop-N"`, so the diagram is the table of contents.
  Initialise mermaid with `securityLevel: 'loose'` so the clicks work.

### Per-stop visuals (one or more per stop, picked by what the stop does)

| the stop | its visual |
|---|---|
| any stop | a **locator**: the hero path as a row of small chips with this stop's node lit, so the reader always sees where they are |
| changes a condition, default or branch | a mini `flowchart TD` of the branches, the new path highlighted |
| adds a retry, loop, queue or async step | a mini `sequenceDiagram` of the timing |
| changes behaviour of existing code | a **before │ after** split panel, old code on the left and new on the right, the changed lines tinted |
| changes a type, schema or payload | **shape cards**: before and after side by side, fields as rows, added rows green, removed rows red and struck, changed rows amber with old → new |
| changes a number, limit or timeout | a small inline bar or number line showing old vs new value |
| everything else | the code with the diff's added lines tinted and **numbered callouts** (①②) on the 1–3 lines that matter, each explained in a one-line note under the code |

Never use a diagram that only restates the code in boxes. A visual must show something
the code doesn't: where it sits, what order things happen in, what changed.

### The file map (always)

A visual list of the changed files, not a text tree:

- Grouped by folder, each file a row: the name, a coloured **tag pill** (`core`, `shape`,
  `wire`, `test`, `noise`), three to six words on its role, and a **+/− bar** whose green
  and red widths scale with its added and removed lines (`git diff --numstat base...head`).
- Files that have a stop link to it and show its number badge. `noise` rows are dimmed and
  collapsed under one `<details>` line.

### The numbers strip (always)

Under the title: files changed, +added, −removed as large figures, and one stacked bar of
the change split by tag (how much is core vs tests vs wiring).

### Tests

A **coverage grid**: one row per behaviour the change adds or alters, with a ✓ when a test
covers it (linking to the test's `path:line`) and an empty, amber cell when nothing does.
Then the command to run them.

## 5. What goes on the page

In this order:

1. **Title line**: `<PR title> · #<n>`, then the PR link, author, `base ← head`.
2. **Numbers strip** (§4).
3. **In short**: one or two sentences, set large. What changes for a caller or user, and why.
4. **Hero diagram** (§4), with its clickable stop numbers.
5. **Route**: the stops as a horizontal numbered stepper (wraps on a phone), each linking to
   its stop.
6. **Files** map (§4).
7. **Stops**, each a card:
   - Header: the number badge, a verb phrase saying what the stop does, and `path:line` as a
     link to GitHub at the head **sha**
     (`https://github.com/<owner>/<repo>/blob/<headRefOid>/<path>#L84-L112`), else plain text.
   - Locator chips, then the stop's visual(s) from §4.
   - The code, syntax highlighted: 5–15 lines as they are after the change, elided with `// …`, added lines
     tinted, callouts on the lines that matter.
   - One to three sentences: what it does in terms of behaviour, then why, taken from the
     description, a commit message or the surrounding code. If nothing says why, write "the
     PR doesn't say why" rather than inventing one.
   - Optional chips: **Before →** the old behaviour in one line, only when existing behaviour
     changed; **Check →** the one thing a reviewer should verify here (an ordering
     assumption, a value crossing a boundary, a change for existing callers), never an opinion.
8. **Tests** coverage grid (§4).
9. **Open**: missing whys, or behaviour the diff implies but doesn't show. Shown as amber
   notes. Omit when there are none.

Budgets, hard:

- **Prose under ~350 words on the whole page**, code and diagram labels not counted. In
  short: 2 sentences; each stop 1 to 3. When it runs long, cut words, never pictures.
- Names as the code names them. No "elegant", no "robust", no "simply". Plain sentences.

For a tour of the code rather than a PR (§1): the title is the description, the header line
is the entry point's `path:line`, the numbers strip shows files and lines on the path
instead of a diff, the file map gives each file's role instead of a tag and drops the +/−
bars, and there are no Tests or Open sections unless the code has an obvious gap. Stops
show the code as it is, with callouts instead of tinted added lines.

## 6. Deliver it as an artifact

The walkthrough is always a published **artifact**: never a markdown file, never a
document pasted in chat.

1. Start the page the way the `Artifact` tool says: `quickstart` with `intent: "other"`,
   then follow what it returns (and load `artifact-design` when it says to). Its page
   contract applies over anything here.
2. Write one HTML file in the scratchpad directory, `walkthrough-<PR number or branch>.html`
   (replace `/` in branch names with `-`), with the §5 content in order.
   - Mermaid from cdnjs at an exact version, for example `mermaid/11.4.1/mermaid.min.js`,
     with `securityLevel: 'loose'` and `theme: 'base'`, its `themeVariables` taken from the
     page's colour tokens so the diagrams match the page in light and dark. Re-render when
     the colour scheme changes. Keep each diagram's source in a `<pre class="mermaid">`.
   - **Every code block is syntax highlighted**, no plain monochrome code. Use highlight.js
     from cdnjs at an exact version (`highlight.js/11.9.0/highlight.min.js`). Give each
     block its language class (`language-ts`, `language-go`, `language-sql`, `language-diff`)
     taken from the file's extension, never left to auto-detect. Load the language files
     the core build lacks, also from cdnjs.
   - Colour the tokens from the page's own tokens (keyword, string, number, comment, type,
     function, punctuation) with a light and a dark set, so highlighting follows the
     colour scheme. Don't load a fixed-theme stylesheet that ignores dark mode.
   - Highlight first, then add the per-line wrappers: split the highlighted HTML into lines,
     wrap each one in a `<span class="line">` carrying the line number, the added or removed
     tint and any callout badge. Tint is a background, so the token colours still show
     through. Before │ after panels and diff blocks are highlighted the same way.
   - Colour tokens on `:root`: background, surface, text, muted, accent (changed), added
     (green), removed (red), warn (amber), and one colour per file tag. A dark variant
     under `prefers-color-scheme: dark`, an explicit `body` background.
   - Works at phone width with a 16px gutter: before │ after and shape cards stack, code
     blocks and diagrams scroll sideways rather than the page.
   - No interaction beyond links, `<details>` and the diagram clicks, plus a small
     "hide noise" toggle on the file map. Nothing is stored.
3. Publish it: `Artifact` with that `file_path`, `icon: "map"`, and a one-sentence
   `description` from **In short**. The page `<title>` is `Walkthrough · #<n>` or
   `Walkthrough · <branch>`. Republish to the same path when the user asks for changes.

If there is no `Artifact` tool, say the walkthrough needs one and stop. Don't write a
markdown file instead.

If the user also asks for it on the PR, post a short comment with `gh pr comment <n>`
holding the In short sentences, the hero diagram as a mermaid block (GitHub renders it) and
the artifact link. Only post when asked.

Reply with the artifact link, the **In short** sentences, and the hero diagram in ASCII
(`-->` arrows, `[brackets]`, `*` on changed nodes) so a reader in a terminal sees the shape
without opening the page. Don't repeat the page in chat.
