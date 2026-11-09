# diag

`/diag <name>` pulls an AlertD server's diagnostics with alertd-core's
`npm run alertd-server` and says what is wrong with it.

- **Names stick.** The first time you use a name, give its URL (or `/diag` asks for it). It logs in
  with `--alias <name>`, and the CLI's `~/.alertd/servers.json` remembers it. After that, `/diag ltk`
  is enough.
- **Only a name → a diagnosis.** It reads health, ingest, schedules, the data dir and the newest
  logs, and pulls the `data/` archive into `~/.alertd/diag/<name>/` when it needs more. Then it
  reports **Healthy**, **Degraded** or **Down** with up to five findings, each with its evidence.
- **Runs anywhere.** The CLI exists only in alertd-core, so outside it `/diag` runs from an
  `~/projects/alertd-core.git` worktree, `develop` first.
- **Read-only.** It never calls a route that writes unless you ask for that exact action.

```bash
claude plugin install diag@adrianj98-skills
```
