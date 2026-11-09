---
name: diag
description: Pull the diagnostics of an AlertD server by its short name (ltk, rsqa, develop…) with alertd-core's `npm run alertd-server`, and, given only the name, work out what is wrong with that server from the diagnostics alone. Remembers each name's URL after the first time. Use when the user says /diag, "check ltk", "what's wrong with rsqa", "pull the diag for develop", or asks to diagnose an AlertD deployment by name.
argument-hint: "<server name> [url] [what to look at]"
allowed-tools: Bash, Read, Grep, Glob
---

The user invoked this with `$ARGUMENTS`: a server's short name, then maybe a URL, then maybe
a question.

## 1. Run the CLI from an alertd-core checkout

`npm run alertd-server` exists only in alertd-core. Use the current repo when it has the
script. Otherwise use a worktree of `~/projects/alertd-core.git`, preferring `develop`:

```bash
top=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -n "$top" ] && grep -q '"alertd-server"' "$top/package.json" 2>/dev/null; then AD=$top
else
  wts=$(git -C ~/projects/alertd-core.git worktree list --porcelain | awk '/^worktree/{print $2}')
  for w in $(echo "$wts" | grep '/develop$'; echo "$wts" | grep -v '/develop$'); do
    grep -q '"alertd-server"' "$w/package.json" 2>/dev/null && { AD=$w; break; }
  done
fi
echo "${AD:-none}"
```

If there is none, say so and stop. The build prints noise on stdout before the JSON, so keep
only from the first `{` or `[` line. Shell state doesn't carry between Bash calls, so start
each call with `AD=<that path>` and this helper:

```bash
ad() { e=$(mktemp); (cd "$AD" && npm run -s alertd-server -- "$@" 2>"$e"; rc=$?; [ $rc -ne 0 ] && cat "$e" >&2; exit $rc) | sed -n '/^[[{]/,$p'; rm -f "$e"; }
```

For `fs tail … --text`, which is not JSON, run it without the `sed`.

## 2. Resolve the name: remember it after the first time

The CLI keeps every server in `~/.alertd/servers.json`, keyed by alias. That file is the
memory: a name logged in once is known from then on.

1. `ad servers`, then find the name the user gave among the aliases (case-insensitive).
2. **Known and logged in:** use `--server <alias>` on every call. Don't ask for the URL.
3. **Known but expired**, or any call exits `2`: run `ad login <url> --alias <name>` with the
   URL from `servers`. Tell the user to finish the sign-in in the browser (it waits up to
   5 minutes).
4. **Unknown:**
   - If a URL was given, run `ad login <url> --alias <name>` so the name sticks.
   - If no URL was given, ask once: "What's the URL for `<name>`?" Then log in with that alias.

   Never invent a URL, and never guess one alias for another.

Never print tokens or the raw `servers.json`.

## 3. Pull the diag

Everything uses `--server <alias>`.

1. **Download the full diag first.** Pull the whole `data/` archive, with no `--since`, and
   unpack it:

   ```bash
   d=~/.alertd/diag/<alias>/$(date +%Y%m%d-%H%M%S)/ && mkdir -p "$d" && ad --server <alias> fs download --out "$d" && tar -xzf "$d"/*.tar.gz -C "$d"
   ```

   It takes minutes on a big deployment, so run it in the background and tell the user
   it's building. While it builds, run `health`, `ingest status`, `schedules --events 2` and
   `fs summary`. Search the unpacked archive with Grep and Read, not with more API calls.
   Say where it landed.
2. **Only if the download fails** (a 403, a timeout, or the server's two-builds limit), fall
   back to live reads:
   - `fs ls logs`
   - `fs tail <log> --offset -60000 --text` on the newest log files that `fs ls` shows, not
     a guessed name
   - `fs cat` for small files

   Say the download failed and why.

Everything is read-only. Never call `api POST`, an `mcp call` that changes state, or any
route that writes, unless the user asks for that exact action.

## 4. Only a name given: find what is wrong

With no question, the diag is the only input. Don't ask the user what's wrong; work it out:

- **Ingest:** sources stalled, lagging or failing; the last success and the last error per
  source.
- **Schedules:** runs that failed, were skipped or are overdue; repeated errors.
- **Logs:** `ERROR`/`FATAL`/stack traces, crash or restart loops, OOM or heap warnings,
  timeouts, auth or 401/403 errors, DB or broker connection errors. Count them and find
  when they started.
- **Data dir:** a quota near full, or files that should be fresh but are stale.
- **Health:** anything not ok.

Tie each finding to a timestamp and to the line or field that shows it. Find the first error
in the chain, not just the loudest one.

With a question, aim the same reads at it.

## 5. Report

Start with one line: **Healthy**, **Degraded** or **Down**, plus the main reason. Then up
to five findings, worst first. Every finding carries its evidence. A claim with no evidence
under it is left out:

````markdown
### 1. <what is wrong> — since <first timestamp>

<one or two sentences: what it means for the server>

**Evidence**
- `<archive path or command>:<line>`: 412 matches from 09:14 to 11:02 (first · last)
```log
<the real log lines, copied exactly: the first occurrence, plus any stack trace or cause line>
```
- `ingest status`: `"source": "s3-prod", "lastSuccess": "…", "lastError": "…"`
````

- **Logs:** copy the real lines in a fenced `log` block, never paraphrased. Include the
  timestamp, the archive path (relative to the unpacked dir) and the line number. Give 1–5
  lines, plus the line above or below when it shows the cause.
- **Counts and time:** how many times it happened, the first and last time, and whether it is
  still happening.
- **API output:** quote the exact JSON fields that show it, and name the command.
- **Chains:** when one error causes another, show both, cause first.

End with:
- **Not checked:** what couldn't be read, and why. A 403 means the signed-in user lacks
  admin, not that the server is broken.
- **Diag:** the archive's path and the unpacked folder, so the user can open the evidence.
