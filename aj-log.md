# aj-log

## 2026-10-12 — work-band mod, `mod` verb in install.sh

- `plugins/work-band/`: the work-band mod copied in from `~/.claude/mods/work-band`
  (plugin.json, hooks module, tests, state contract, tsconfig). `.claude-plugin/types/` is
  left out and gitignored: the engine writes it when the mod loads. Why: the mod lived only
  on this machine; the repo is where the other plugins are kept and installed from.
- `install.sh`: new `mod <dest> <desc>` manifest verb. Copies the plugin folder whole into
  `<install root>/<dest>` (minus the manifest and the engine's types) and adds that path to
  `env.CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json`, keeping the entries already
  there. `--uninstall` removes both. Why: a mod is loaded as a folder from that env var, not
  file by file through hooks in settings.json, so neither `file` nor `hook` fit. The env var
  is read only from the global settings, so a `--local` install registers its absolute path
  there. With no clone, the folder comes out of the repo's tarball, the owner/repo/ref read
  off `SKILLS_RAW`.
- Registered in `marketplace.json`, `plugins/index`, root README.

## 2026-10-12 — progress plugin

- `plugins/progress/`: new `/progress` skill. Two sections: what the PR/branch is about, then
  its state. Why: one command to answer "where is this PR at" instead of reading the PR page,
  the checks tab and `git status` separately.
- `scripts/progress.sh`: gathers branch vs base and vs remote, working tree, commits with
  bodies, diffstat, `gh pr view` fields, review threads via GraphQL (the CLI view has no
  `isResolved`), the last conversation comments, aj-log.md lines the branch added, and any
  Jira-style keys. Takes nothing (checked-out branch), a PR number, a branch or a PR URL.
  Why a script: the baseline run without it took five tool calls and 40k tokens to reach
  the same facts.
- SKILL.md is a positive recipe (fixed section shapes, bullet order) rather than a list of
  don'ts. Why: the baseline failure was shape, not discipline: shas, every passing check
  named, suggested shell commands.
- Registered in `marketplace.json`, `plugins/index`, root README; `install.manifest` for
  `install.sh progress`.

## 2026-10-08 — remote skills in install manifests

- `install.sh`: new `remote <owner/repo[@ref]> <path> <dest> <desc>` manifest verb. Downloads
  the repo tarball from codeload.github.com once per repo@ref and copies `<path>` (or every
  directory under `<path>/*`) into the install root, running text files through the
  manifest's `rewrite` rules. Why: to install skills from other people's repos, e.g.
  obra/superpowers, without vendoring them here.
- `install.sh`: `--skill NAME[,NAME]` narrows remote lines to the named skills. Why: install
  individual skills, not only the whole set. Refused with `all`, since it picks from one plugin.
- `install.sh`: `<plugin> --list` lists the skills a plugin's remote repos offer.
- `install.sh`: remote installs are recorded in `.claude/.install-receipts/<plugin>`;
  `--uninstall` (optionally with `--skill`) removes exactly what's recorded. Why: a `*` line's
  contents change upstream, so the manifest alone can't say what was installed.
- `plugins/superpowers/install.manifest` + `plugins/index`: installs obra/superpowers'
  skills, rewriting `superpowers:<skill>` to bare names.
- Verb reference in `plugins/adversarial-review/install.manifest` and README updated.

## 2026-10-12 — work-band shows the plan alone

- `plugins/work-band/hooks/register.tsx`: the account text at the end of the band is now
  just the plan (`Max`, `Team`, ...), no ` · <org>` after it. Why: a personal org is named
  `<email>'s Organization`, which swamped the band; only the first word was wanted.
- `register.test.ts`: the band test now expects `   Team` at the end, not `Team · AlertD`.
  `parseAuthStatus` still returns `org` for anything that wants it later.
- `register.tsx`: the plan is drawn in `magenta` (a raw colour, so it stays purple in every
  theme) and no longer dimmed. Why: asked for it in purple.
