---
name: claude-local
description: Create or edit a personal CLAUDE.local.md — uncommitted instructions for Claude, either in this repo or globally for every repo. Use when the user asks for personal/local Claude instructions, a private CLAUDE.md, a memory file that isn't committed, or wants to add something to their local Claude notes.
argument-hint: "[init | init --global | link | status | <something to add>]"
allowed-tools: Bash, Read, Edit, Write
---

Where things stand:

!`bash "${CLAUDE_PLUGIN_ROOT}/bin/claude-local" status 2>/dev/null || echo "state: unknown (claude-local not found)"`

The user invoked this with `$ARGUMENTS`. Drive the helper as
`bash "${CLAUDE_PLUGIN_ROOT}/bin/claude-local" <args>` — via `bash`, since the file may not
carry an exec bit after install.

- **`init`** — create `<repo root>/CLAUDE.local.md` and git-exclude it. **`init --global`**
  creates `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.local.md`, which applies in every repo.
  If the user didn't say which, ask — repo-specific facts and personal habits belong in
  different files.
- **`link`** — append `@CLAUDE.local.md` to the neighbouring `CLAUDE.md` so it actually gets
  loaded. Offer this after `init`: without an import, a `CLAUDE.local.md` may just sit there.
  For repo scope say first that `CLAUDE.md` is usually tracked, so the import line is a commit.
- **`status`**, or no argument — already shown above. Report it in a line or two.
- **anything else** — treat it as content to add. Find the file with
  `bash "${CLAUDE_PLUGIN_ROOT}/bin/claude-local" path` (add `--global` for the global one),
  `init` it if missing, then edit it: put the note under the section it belongs to, adding a
  section if none fits. Keep the user's wording. Show the diff, don't restate the whole file.

Write only what the user asked for — this file steers every future session in that scope, so
don't pad it with inferred preferences.
