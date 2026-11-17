# whyslow

`/whyslow` — work out why this computer is running slow.

```bash
claude plugin install whyslow@adrianj98-skills
```

It runs `scripts/snapshot.sh` first: a read-only, ~12 second snapshot of CPU (sampled, not
instantaneous), memory pressure, swap and the compressor, process memory grouped by name,
disk space and I/O, thermal and power state, known background hogs (Spotlight, Time Machine,
iCloud, VMs, security agents), process pile-ups, launch agents and recent hang reports.
macOS first, with a Linux fallback.

Then it diagnoses from those numbers: each bottleneck is clear, strained or the problem, and
it follows the chain to the cause rather than the symptom (full swap makes `kernel_task`, the
CPU and the disk look busy; 25 orphaned copies of an MCP server look like "node is slow").

The report starts with **Healthy**, **Strained** or **Overloaded** and one sentence naming
the cause, then **Why** with the numbers, **Fix** ordered by payoff, and one line of what was
fine. It never kills, quits or changes anything.

| | |
|---|---|
| `/whyslow` | diagnose from the snapshot alone |
| `/whyslow typing lags` | weight the diagnosis toward what feels slow |

Run the script on its own with `bash plugins/whyslow/scripts/snapshot.sh [seconds]`.
