# aj-log

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
