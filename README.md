# skills

Claude Code plugins I use across projects. This repo is a plugin marketplace.

```bash
claude plugin marketplace add adrianj98/skills
```

## Plugins

### [`adversarial-review`](plugins/adversarial-review) · v0.1.0

A reviewer that assumes your code is wrong, in a context window that never saw you write
it. Modelled on the split-context review [Bun used](https://bun.com/blog/bun-in-rust) to
port a million lines from Zig to Rust — *"1 implementer, 2 or more adversarial reviewers
per implementer. The implementer doesn't review. The reviewer doesn't implement."*

```bash
claude plugin install adversarial-review@adrianj98-skills
```

Or without the plugin system — see [Installing without the plugin system](#installing-without-the-plugin-system).

Ships four levels of the same idea, escalating by how hard it is to skip:

| | invoke | |
|---|---|---|
| reviewer subagent | "have the adversary review my changes" | one pass, cheap |
| review workflow | `/adversarial-review:review` | 4 lenses in parallel, then refutation voting |
| Stop-hook nudge | automatic, once per diff over ~25 code lines | `adversary off` to silence |
| PR gate | [`examples/github-pr-review.yml`](examples/github-pr-review.yml) | not skippable from your laptop |

[Full README →](plugins/adversarial-review/README.md)

## Installing without the plugin system

`install.sh` copies a plugin's files into `~/.claude/` or a repo's `.claude/`, rewrites its
plugin-relative paths to real ones, and merges any hooks into your existing `settings.json`
rather than overwriting it. It runs from a clone or straight from a `curl`, and takes the
plugin you want:

```bash
# every repo, just you
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh \
  | bash -s -- adversarial-review --global

# this repo, committed for teammates
./install.sh adversarial-review --local

./install.sh --list                                   what's installable
./install.sh adversarial-review --uninstall --global  reverse it
```

Not everything installable is a plugin. [`claude-local`](plugins/claude-local) is just a
starter `CLAUDE.local.md` — personal notes for Claude, uncommitted:

```bash
./install.sh claude-local --local     # <repo root>/CLAUDE.local.md, kept out of git
./install.sh claude-local --global    # ~/.claude/CLAUDE.local.md, applies everywhere
```

It lands beside the repo rather than in `.claude/`, adds itself to `.git/info/exclude`
rather than the tracked `.gitignore`, and is never overwritten or deleted once it's yours.

| | |
|---|---|
| `--global` | into `~/.claude/` (or `$CLAUDE_CONFIG_DIR`) |
| `--local [PATH]` | into `./.claude/`, or `PATH/.claude/` — `--repo` is an alias |
| `--private` | register hooks in `settings.local.json` (gitignored) instead |
| `--no-hook` | skip any hooks; install everything else |
| `--dry-run` | print what would happen, change nothing |
| `--uninstall` | remove the files and unregister the hooks |

Re-running is idempotent. `SKILLS_RAW=…` points the standalone install at a fork or branch.

## Adding a plugin to this repo

1. `plugins/<name>/` with a `.claude-plugin/plugin.json`
2. Auto-discovered subdirs: `skills/<name>/SKILL.md`, `agents/*.md`, `commands/*.md`,
   `workflows/*.js`, `hooks/hooks.json`, `bin/`, `.mcp.json`
3. Add an entry to [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json)
4. `claude plugin validate .`
5. Optional: a `plugins/<name>/install.manifest`, plus the name in
   [`plugins/index`](plugins/index), so `install.sh <name>` works too. `install.sh` knows
   nothing about any particular plugin — the manifest lists what to copy where, which
   hooks to register, and which plugin-relative paths to rewrite:

   ```
   name   Some Plugin
   about  One line, shown by install.sh --list.

   file      skills/x/SKILL.md  skills/x/SKILL.md   /x
   bin       bin/x              bin/x               the helper
   hook      Stop  scripts/x.sh  hooks/x.sh         the nudge
   personal  NOTES.md           NOTES.md            beside the repo, never clobbered

   rewrite  ${CLAUDE_PLUGIN_ROOT}/bin/x  @ROOT@/bin/x
   tip      /x — try this first
   ```

   `@ROOT@` is the `.claude/` directory, `@BASE@` the repo root (or the config dir when
   installing globally).

## License

MIT
