---
name: whyslow
description: Work out why this computer is running slow. Runs a read-only snapshot script first (CPU, memory pressure and swap, disk space and I/O, thermal and power, background hogs, process pile-ups, recent hangs), then diagnoses from the numbers and names the culprit and the fix. Use when the user says /whyslow, "why is my machine slow", "my mac is sluggish", "laptop is lagging", "what's eating my CPU/RAM", or asks why the computer is hot, the fans are loud or apps are beachballing.
argument-hint: "[what feels slow, e.g. 'typing lags', 'builds', 'since this morning']"
allowed-tools: Bash, Read
---

The user said: `$ARGUMENTS` (may be empty).

## 1. Collect: run the scripts first

Run the snapshot. It is read-only and takes about 12 seconds (two CPU samples, one disk sample):

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/snapshot.sh" 5 2>&1`

If that line is still a command rather than its output, this host didn't run it. The plugin
root is two directories above this skill's base directory: run `scripts/snapshot.sh 5` from
there with `bash` and use its output.

Don't diagnose from memory or from what is "usually" wrong. Every claim in the report comes
from a number in the snapshot or in a follow-up command you ran.

## 2. Diagnose

Go through the bottlenecks in this order and decide, for each, **clear**, **strained** or
**the problem**. Usually one is the problem and the rest follow from it.

| Bottleneck | Healthy | Strained | The problem |
|---|---|---|---|
| **Memory** | swap used < 1 GB, free % > 40, compressor < ~25% of RAM | swap 1–4 GB, free % 20–40 | swap near its total, free % < 20, compressor > ~40% of RAM, swapins/swapouts in the hundreds of millions |
| **CPU** | 1-min load < cores | load 1–2× cores | load > 2× cores, `sys` % > `user` %, idle < 10% |
| **Disk I/O** | MB/s low at idle | sustained > 200 MB/s with nothing obvious running | sustained heavy tps/MB/s while the user isn't copying anything — usually swap |
| **Disk space** | Data volume < 85% | 85–95% | > 95% or < 10 GB free (swap and caches can't grow) |
| **Thermal / power** | no warning recorded, AC or healthy battery | — | any thermal/performance warning, `CPU_Speed_Limit` < 100, low power mode on |

How the signs chain, so you name the cause and not the symptom:

- **Swap thrash looks like CPU.** Full swap + huge compressor + high `sys` % + `kernel_task`
  near the top + heavy disk MB/s = memory is the problem; the CPU and disk are busy paging.
  Fix memory, not CPU.
- **`kernel_task` high on its own** with a thermal warning = the Mac is throttling for heat.
  `kernel_task` high with no thermal warning = paging or a driver; look at memory first.
- **RSS lies under swap.** A process that is swapped out shows a small RSS. Use the
  "process groups by total memory" table and the counts in "process counts" to find who
  owns the pressure: many copies of the same thing (dozens of `node`, `claude`,
  `chrome-devtools-mcp`, `Python`) is the usual story on a dev machine.
- **Pile-ups are leaks of processes.** The same tool running 10+ times, or processes with
  elapsed times of days that should be short-lived (a `tsc`, an `npm exec`, an MCP server), are
  orphans from closed terminals or sessions. Name them.
- **VMs and containers** (OrbStack, Docker, `com.apple.Virtualization`, qemu) reserve a
  fixed memory block that `ps` mostly doesn't show. If one is running, say how much it is
  configured for if you can find out (`orb config get memory_mib`, `docker info`).
- **Spotlight / Photos / iCloud / Time Machine** (`mds*`, `mdworker`, `photoanalysisd`,
  `bird`, `cloudd`, `backupd`) are temporary. Call them out only if they are actually high.
- **Security agents** (CrowdStrike/falcon, SentinelOne, Jamf, Zscaler) are often heavy and
  usually not the user's to remove; say so rather than suggesting it.
- **Uptime of many days** with high swap: a restart clears it, but say what will refill it.
- **Hangs in "recent hangs / crashes"** for the app the user complains about point at that app.

If the user said what feels slow, weight the diagnosis toward it (typing lag → WindowServer,
memory; builds → CPU, disk; "since this morning" → processes with short elapsed times).

## 3. Dig, only where it decides something

Run at most a few targeted, read-only follow-ups to confirm the suspect, for example:

```bash
ps -Ao pid,ppid,rss,pcpu,etime,command | grep -i '<suspect>' | grep -v grep | head -20   # who started the copies
ps -o pid,etime,command -p <ppid>                                                          # is the parent still alive
lsof -p <pid> 2>/dev/null | wc -l                                                          # fd leak
sudo -n powermetrics -n 1 -i 1000 --samplers thermal,cpu_power 2>/dev/null | head -40      # only if sudo is cached
```

Never kill, quit, delete, unload or change a setting yourself. This skill only reports.

## 4. Report

First line, bold: **Healthy**, **Strained** or **Overloaded**, then one sentence naming the
main cause, e.g. **Overloaded** — memory: swap is 16.8 of 17 GB and the CPU is busy paging.

Then:

- **Why** — 2–5 bullets, each with the number that shows it (`load 55 on 8 cores`,
  `27 claude processes, 1.5 GB`). Cause first, then the symptoms it produces.
- **Fix** — ordered by payoff, each a concrete action naming the process or app. Put any
  command the user may run in a fenced `bash` block, never inline. Mark anything that loses
  work (quitting an app, killing a process) so the user decides.
- **Fine** — one line listing the bottlenecks that were clear, so the user knows they were
  checked.

Add one small chart (a mermaid `xychart-beta` bar) only when it makes the culprit obvious,
such as memory by process group. Keep the whole report under about 25 lines. Don't pad it
with generic advice ("close unused tabs", "restart regularly") that the numbers don't support.
