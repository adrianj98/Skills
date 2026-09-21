#!/usr/bin/env bash
# Run one adversarial-review lens through the Antigravity CLI (`agy`) instead of a Claude
# subagent. Opt-in: the skill calls this when ADVERSARY_RUNNER=agy. The report goes to stdout
# in the same format the `adversary` subagent uses, so everything downstream is unchanged.
#
#   agy-review.sh <lens> <diff-file> [--prior FILE] [--facts FILE] [--mechanical FILE]
#
# Why this is safe to run unattended: in print mode agy cannot prompt, so every tool that needs
# permission — any shell command — is auto-denied. The reviewer is left with agy's built-in file
# viewing and search tools, which is a structural read-only limit, the same kind the subagent
# gets from its tool list. `--mode plan` and `--sandbox` sit behind that as a second wall.
# What it costs: nothing can be *run*, so a finding is `confirmed` only by tracing.
#
# Exit codes: 0 report on stdout · 3 agy unusable (missing, timed out, empty) — fall back to
# the subagent · 2 bad usage.
#
# Tuning:  ADVERSARY_AGY_MODEL=...    default gemini-3.8-flash-medium  (see `agy models`)
#          ADVERSARY_AGY_TIMEOUT=...  default 300s
set -uo pipefail

LENS="${1:-}"; DIFF="${2:-}"
[ -n "$LENS" ] && [ -f "$DIFF" ] || { echo "usage: agy-review.sh <lens> <diff-file> [--prior F] [--facts F] [--mechanical F]" >&2; exit 2; }
shift 2
PRIOR=""; FACTS=""; MECH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prior)      PRIOR="${2:-}"; shift 2 ;;
    --facts)      FACTS="${2:-}"; shift 2 ;;
    --mechanical) MECH="${2:-}";  shift 2 ;;
    *) echo "agy-review: unknown option $1" >&2; exit 2 ;;
  esac
done

command -v agy >/dev/null 2>&1 || { echo "agy-review: agy is not on PATH" >&2; exit 3; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT=""
for CANDIDATE in "${CLAUDE_PLUGIN_ROOT:-}/agents/adversary.md" "$HERE/../agents/adversary.md"; do
  [ -f "$CANDIDATE" ] && { AGENT="$CANDIDATE"; break; }
done
[ -n "$AGENT" ] || { echo "agy-review: cannot find agents/adversary.md" >&2; exit 3; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIFF_ABS="$(cd "$(dirname "$DIFF")" && pwd)/$(basename "$DIFF")"

# The reviewer's own instructions, minus the frontmatter, which is Claude Code's and not prose.
BODY="$(awk 'BEGIN{n=0} /^---[[:space:]]*$/ && n<2 {n++; next} n>=2' "$AGENT")"

section() { # section <heading> <file>
  [ -n "$2" ] && [ -s "$2" ] && printf '\n## %s\n\n%s\n' "$1" "$(cat "$2")"
}

# A diff small enough to ride in argv goes inline and saves the reviewer a tool call; a big one
# is named by path, inside a directory the reviewer is allowed to read.
if [ "$(wc -c < "$DIFF_ABS")" -lt 150000 ]; then
  DIFF_BLOCK="$(printf '\n## The diff\n\n```diff\n%s\n```\n' "$(cat "$DIFF_ABS")")"
else
  DIFF_BLOCK="$(printf '\n## The diff\n\nIt is in the file %s — read it once, first.\n' "$DIFF_ABS")"
fi

PROMPT="$BODY

---

## How this run differs

You are running headless, outside Claude Code. **Shell commands are denied** — do not try one;
a denied command ends the run with no report. Use only your built-in file viewing and search
tools, and only to read. That means nothing can be executed: \`confirmed\` is for what you traced
through the code you actually opened, everything else is \`plausible\`, and *Established by
execution* stays empty. Do not write a plan, do not ask for approval, do not create any file.
Your whole reply is the report, starting with the \`verdict:\` line.

Lens: **$LENS** — stay on it and leave the other lenses' territory alone.
Repository root: $ROOT
$DIFF_BLOCK$(section 'Prior findings' "$PRIOR")$(section 'Already established — do not re-derive' "$FACTS")$(section 'Already known mechanically' "$MECH")"

OUT="$(agy -p "$PROMPT" \
  --add-dir "$ROOT" --add-dir "$(dirname "$DIFF_ABS")" \
  --mode plan --sandbox \
  --model "${ADVERSARY_AGY_MODEL:-gemini-3.8-flash-medium}" \
  --print-timeout "${ADVERSARY_AGY_TIMEOUT:-300s}" </dev/null 2>&1)"
STATUS=$?

# A report has a verdict line. Anything else — a denied tool, a timeout, a login prompt — is a
# failed run, and saying so lets the caller fall back rather than read noise as a clean review.
if [ $STATUS -ne 0 ] || ! printf '%s' "$OUT" | grep -qiE '^[[:space:]*`]*verdict:[[:space:]]*(block|concerns|clean)'; then
  printf 'agy-review: no usable report (exit %s). Last output:\n%s\n' "$STATUS" "$(printf '%s' "$OUT" | tail -5)" >&2
  exit 3
fi
printf '%s\n' "$OUT"
