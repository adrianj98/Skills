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

### [`standup`](plugins/standup) · v0.1.0

`/standup` — a very short list of what you worked on since your last working day. It reads the
commits reachable from every worktree of the current repo, so work on a branch checked out
somewhere else still counts. It also reads the GitHub PRs you opened or reviewed (through `gh`),
the Jira issues you touched (through an Atlassian MCP server or a `jira`/`acli` CLI), and
whatever each worktree's `aj-log.md` gained. Related items become one bullet each. A source
that isn't available is skipped.

```bash
claude plugin install standup@adrianj98-skills
```

`/standup since friday` widens the window; `/standup everyone` includes every author.

### [`progress`](plugins/progress) · v0.1.0

`/progress` — where a branch and its pull request stand, in two sections. *What it's about*
is a paragraph from the PR description, the commit bodies and `aj-log.md`. *State* is a short
list: none yet / draft / open / merged, who approved or is still being waited on and how many
review threads are open, which checks fail, conflicts or commits behind the base, what's
uncommitted or unpushed, any unanswered question in the conversation, and the one thing left
before it merges. `/progress 189` takes a PR number, `/progress feature/x` a branch.

```bash
claude plugin install progress@adrianj98-skills
```

[Full README →](plugins/progress/README.md)

### [`deslop`](plugins/deslop) · v0.1.0

`/deslop` — what in this change reads like a machine wrote it, as a report you can act on;
`/deslop run` cuts it in the same pass. Comments that restate the line below them, `try/catch`
around calls that can't throw, wrappers with one caller, the `as any` that made the error go
away, README paragraphs about leveraging a robust and comprehensive toolkit.

```bash
claude plugin install deslop@adrianj98-skills
```

A deterministic scan over the lines your branch *added* produces candidates; the skill then
reads files the diff never touched to learn what this repo's authors actually write, and
throws out everything that only looks like slop next to some other codebase. `/deslop all`
audits the whole repo instead.

[Full README →](plugins/deslop/README.md)

### [`showmethedata`](plugins/showmethedata) · v0.1.0

`/showmethedata UserSession` — how that data is stored and used by the code. Where it lives
at rest, what shape it has in each layer and where those shapes disagree, who writes it, who
reads it and what for, one write and one read traced end to end, and what eventually deletes
it. Point it at a symbol, a table, a field, a file or a directory; with no target it maps the
repo one paragraph per store.

```bash
claude plugin install showmethedata@adrianj98-skills
```

Just a prompt, no script: it orients on the repo's stores and schema files, greps every
spelling of the target, follows each writer to where the data lands, reads the migration
rather than the model, and reports the drift between layers with a `file:line` on both sides.
It never edits anything.

[Full README →](plugins/showmethedata/README.md)

### [`doubt`](plugins/doubt) · v0.1.0

`/doubt` — question the analysis or diagnosis the AI just gave, before you act on it. It
splits the analysis into claims, checks the load-bearing ones in a fresh context that never
saw the reasoning, and names the explanations it skipped. The first line of the report is
**Holds**, **Shaky** or **Wrong**, and anything after it is only what failed or went unchecked.

```bash
claude plugin install doubt@adrianj98-skills
```

[Full README →](plugins/doubt/README.md)

### [`caveman`](plugins/caveman) · v0.1.0

`/caveman` — short, plain replies for the rest of the session, with no pleasantries, hedging
or recap and the answer first. Code, errors and technical names stay exact, and warnings stay
in full sentences. `/caveman off` turns it back.

```bash
claude plugin install caveman@adrianj98-skills
```

[Full README →](plugins/caveman/README.md)

### [`greenlight`](plugins/greenlight) · v0.5.0

`/greenlight`: a skill with no script behind it. It first says what it will do and lists the
workflows it will watch, each with its checks and which are required. Then it pulls the default branch (asking GitHub
which one that is), merges it into your branch, and pushes. If the merge conflicts, Claude
resolves it. If the pull request has a required `integration` check that came out
`skipping`, Claude reruns that run once. When a check fails, Claude fixes the code and
pushes again, up to three times. It then reports each check's result from `gh pr checks`.

```bash
claude plugin install greenlight@adrianj98-skills
```

[Full README →](plugins/greenlight/README.md)

### [`work-band`](plugins/work-band) · v0.2.0

A mod, not a skill: a hooks module that draws a band above the prompt in any GitHub repo. It shows
the checked-out branch, its PR and checks, and the lines added and removed against the PR's base
(or the repo's default branch). Clicking opens a pane beside the transcript: the checks (with a
re-run button), the changed files as a tree, or the dev server's logs. `/wb` hides and shows the
band. Claude tells the band what it is working on through the mod's `set_topic` tool, drawn in
cyan; every prompt you send carries a hidden line with that topic, so Claude re-checks it.

Per repo, set in `~/.claude/work-band.json` (nothing is written to the repo), it also shows the
Jira issue the branch names, only once you set the Jira site, and a button that starts or restarts
the dev server: a turbo `serve` task or any command, with its port variable, ports and extra env.
`/wb settings` lists this repo's settings in a pane, where a click changes one; `/wb setup` asks
each in turn and offers the servers it finds in `turbo.json` and `package.json`.

```bash
claude plugin install work-band@adrianj98-skills
```

Or `./install.sh work-band --global`, which copies the folder to `~/.claude/mods/work-band` and
adds it to `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`.

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

./install.sh all --global                             every plugin at once
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

### Skills from other repos

A manifest can also pull skills straight from someone else's GitHub repo with a `remote`
line. [`superpowers`](plugins/superpowers/install.manifest) installs
[obra/superpowers](https://github.com/obra/superpowers) that way — all of it, or just the
skills you name:

```bash
./install.sh superpowers --global                                    # every skill
./install.sh superpowers --skill brainstorming,systematic-debugging --global
./install.sh superpowers --list                                      # what there is to pick
./install.sh superpowers --uninstall --skill brainstorming --global
```

It downloads one tarball per repo (no git, no API token), copies each skill directory into
`skills/`, and rewrites `superpowers:<skill>` references to the bare `/<skill>` names.
What it installed is recorded in `.claude/.install-receipts/<plugin>`, so `--uninstall`
removes exactly that even after upstream adds or drops skills.

### Into Devin

Devin reads these plugins as they are, so `--devin` hands each one to Devin's own plugin
system instead of copying files:

```bash
./install.sh all --devin                  # or one plugin by name
./install.sh standup --devin --uninstall
```

That records them in your personal plugins, which Devin Cloud sessions and every machine
you sign in to load. Skills arrive namespaced (`/standup:standup`). The hooks and the
`adversary` subagent only run in local Devin sessions, and the review workflow is Claude
Code only. `SKILLS_DEVIN_SOURCE=you/Skills` installs from a fork.

| | |
|---|---|
| `--global` | into `~/.claude/` (or `$CLAUDE_CONFIG_DIR`) |
| `--local [PATH]` | into `./.claude/`, or `PATH/.claude/` — `--repo` is an alias |
| `--devin` | into Devin, through `devin plugins install` |
| `--private` | register hooks in `settings.local.json` (gitignored) instead |
| `--no-hook` | skip any hooks; install everything else |
| `--dry-run` | print what would happen, change nothing |
| `--skill NAME` | only that skill from a manifest's `remote` lines (`a,b` for several) |
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
   remote    owner/repo@v1  skills/*  skills     every skill dir in that GitHub repo
   remote    owner/repo     skills/x  skills/x   or just one

   rewrite  ${CLAUDE_PLUGIN_ROOT}/bin/x  @ROOT@/bin/x
   tip      /x — try this first
   ```

   `@ROOT@` is the `.claude/` directory, `@BASE@` the repo root (or the config dir when
   installing globally).

## License

MIT
