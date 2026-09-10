# claude-local

A personal `CLAUDE.local.md` — instructions Claude reads every session, that nobody else
sees. Per repo, or globally for every repo.

`CLAUDE.md` is the shared, committed brief for a project. This is the other half: your own
habits, the local paths and credentials-adjacent facts your teammates don't need, the
scratch context you'd otherwise retype every session.

```bash
claude plugin install claude-local@adrianj98-skills
```

Or without the plugin system:

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh \
  | bash -s -- claude-local --global
```

## Use

```
/claude-local init              <repo root>/CLAUDE.local.md, kept out of git
/claude-local init --global     ~/.claude/CLAUDE.local.md, applies in every repo
/claude-local link              add @CLAUDE.local.md to the neighbouring CLAUDE.md
/claude-local status            what exists, where, and whether it's loaded
/claude-local <anything else>   treated as a note to add to the file
```

The last form is the point of it. `/claude-local always run the tests with bun, never npm`
finds the file, creates it if it's missing, and files that line under the section it belongs
to.

## What it does to your repo

`init` writes `CLAUDE.local.md` at the repo root and adds it to `.git/info/exclude` — not
the tracked `.gitignore`, so your teammates' repos are untouched and nothing shows up in
`git status`.

`link` is separate and opt-in because it edits `CLAUDE.md`, which usually *is* tracked. It
appends one line:

```
@CLAUDE.local.md
```

That import is what guarantees the file is loaded. Without it a `CLAUDE.local.md` may sit
there unread, depending on your Claude Code version — `status` tells you which case you're in.

Globally, the same pair lives in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`: `CLAUDE.local.md`
next to the `CLAUDE.md` that applies everywhere. Nothing there is version-controlled, so
there's no exclude step.

## Files

```
skills/claude-local/SKILL.md   /claude-local — init, link, status, or add a note
bin/claude-local               the helper: init | link | path | status [--global]
```

The helper is a plain bash script with no dependencies; you can run it directly from a shell.

## Uninstall

```bash
claude plugin uninstall claude-local@adrianj98-skills
# or, for a direct install:
./install.sh claude-local --uninstall --global
```

Your `CLAUDE.local.md` files are left alone either way.
