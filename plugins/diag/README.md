# diag

`/diag <name>` pulls an AlertD server's diagnostics with alertd-core's
`npm run alertd-server` and says what is wrong with it.

- **Names stick.** The first time you use a name, give its URL (or `/diag` asks for it). It logs in
  with `--alias <name>`, and the CLI's `~/.alertd/servers.json` remembers it. After that, `/diag ltk`
  is enough.
- **Full diag first, in the background.** It starts downloading the whole `data/` archive into
  `~/.alertd/diag/<name>/<time>/`. While that builds, it reads the live server (health, ingest,
  schedules, log tails) and posts a **Preliminary** report. When the archive lands, it searches
  all of it and posts the final report, saying what changed. If the download fails, it
  finishes from live reads and says why.
- **Only a name → a diagnosis.** From that, it reports **Healthy**, **Degraded** or **Down**
  with up to five findings. Each one shows its evidence: the real log lines in a code block,
  with their path, line number and timestamp, how many times and since when, and the exact API
  fields.
- **Runs anywhere.** The CLI exists only in alertd-core, so outside it `/diag` runs from an
  `~/projects/alertd-core.git` worktree, `develop` first.
- **Read-only.** It never calls a route that writes unless you ask for that exact action.

```bash
claude plugin install diag@adrianj98-skills
```
