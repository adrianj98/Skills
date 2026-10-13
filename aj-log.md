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
- `register.tsx`, `register.test.ts`: the Jira tool is `mcp__claude_ai_Atlassian_Rovo__getJiraIssue`.
  Why: the claude.ai connector was renamed from "Atlassian" to "Atlassian Rovo", so the old
  tool name no longer exists, `$.tool.check` never allowed it, and the band showed
  "allow getJiraIssue to show status" on every refresh. Calling the Rovo tool with the mod's
  exact input (site URL as cloudId, fields: status) returns the status JSON the regex reads.
- `register.tsx`: the Jira tool is no longer a hardcoded name. `pickJiraTool` takes the first
  `mcp__*__getJiraIssue` from `$.tool.list()`, so the band works with claude.ai "Atlassian Rovo",
  the older "Atlassian", or a local `atlassian` server. With none connected the band says
  "no Jira MCP connected"; when the tool isn't allowed it names the exact tool to allow.
  Why: the connector name differs between sessions and machines, and renaming broke the band.
- `register.test.ts`: the harness answers `tool.list` with nothing unless a test owns Jira;
  tests for picking the tool, reading status via a local server, and both error texts.
- `register.tsx`, `types/index.d.ts`: the band shows the Jira issue's title (its `summary`)
  after the key, not its status. `parseJiraTitle` reads it from getJiraIssue's JSON and
  undoes JSON escapes; the text truncates at the band's edge. Why: asked for the title.
- `register.tsx`: when the first row (PR · Jira · server · plan) would be wider than the band's
  `bodyColumns`, the Jira issue moves to a row of its own, its title cut to the band with an
  ellipsis (`fitWidth`), so the band is three rows and nothing word-wraps. `firstRowWidth`
  measures the row as drawn. Why: a long title wrapped the band onto extra lines.
- `register.test.ts`: `mountBand` takes a column count; tests for the measure, the cut, and
  the two-row / three-row layouts at 200 and 60 columns.
- `register.tsx`: the Jira title is drawn dim (grey), on the first row and on its own row,
  so the key stands out. Why: asked for a lighter grey.
- `register.tsx`: the Files button runs `/filetree` when the filetree mod
  (data-goblin/claude-code-filetree) is installed, found through `$.command.list()`; its
  refusal text (no fullscreen layout, terminal under 110 columns) is shown as a toast.
  Without it the band's own Files pane opens as before. Another plugin's pane can't be
  listed or closed, so the button opens or refocuses filetree rather than toggling it.
  Why: asked to use filetree when present.
- `install.manifest`: a tip says so. `register.test.ts`: both paths tested.
- `register.tsx`, `types/index.d.ts`: the band shows the Jira issue's status, abbreviated,
  between the key and the title: `AL-4169 TODO MATEOAS: route tables`. getJiraIssue is asked
  for `status` as well as `summary`; `parseJiraStatus` reads the status's own name (not its
  category's), and `abbreviateStatus` maps the common names (To Do → TODO, In Progress → PROG,
  In Review → REV, Done, Backlog → BKLG, Blocked → BLKD, ...) and otherwise takes a multi-word
  name's initials or a single word's first four letters. The status is drawn plain, between
  the bold key and the dim title, on the first row and on the issue's own row, and the
  own-row cut and `firstRowWidth` account for it. Why: asked for an abbreviated Jira status.
- `register.test.ts`: tests for the status parse, the abbreviations, the measure and both
  layouts with a status; the installed copy in `~/.claude/mods/work-band` was updated too.
- `register.tsx`: the Jira status on the band is a button. Clicking it calls
  getTransitionsForJiraIssue, drops the issue's current status, and shows the rest in a
  picker (at most four options, so a longer list is three at a time with `More…`; a name
  typed under Other also works). The picked transition goes to transitionJiraIssue, a toast
  says `AL-4169 → QA`, and the band re-reads the issue. Both tools are found on whichever
  Jira MCP is connected (`pickJiraTool` now takes the operation name); the click may open
  their permission dialog. Why: asked to change the status from the band.
- `register.test.ts`: tests for `parseTransitions`, `transitionPage` and the click-to-move
  flow; the installed copy in `~/.claude/mods/work-band` was updated too.
