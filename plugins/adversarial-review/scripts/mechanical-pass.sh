#!/usr/bin/env bash
# Run the repo's own checks once, so four reviewers don't spend tool calls rediscovering
# what a linter already knows. Called by require-adversary.sh just before it nudges;
# prints a block for the nudge to embed, or nothing at all.
#
# Opt-in, and deliberately never from a tracked file: a `.adversary-checks` committed to a
# repo would run commands on the first Stop hook after a clone. Config comes from
#
#   ADVERSARY_CHECK="npm run lint --silent"     one command, this session
#   .git/adversary-checks                       one command per line, # for comments
#
# Tuning:  ADVERSARY_CHECK_TIMEOUT=n   seconds per command (default 10)
#
# This never blocks and never fails: a command that dies, hangs or is missing is reported as
# "did not complete" and the review goes ahead without it. Always exits 0.
set -uo pipefail

# 0 is not "unlimited": `timeout 0` and `alarm 0` both mean "no alarm at all", which would
# silently remove the only thing bounding a check. Anything that isn't a positive integer
# falls back to the default.
TIMEOUT="${ADVERSARY_CHECK_TIMEOUT:-10}"
case "$TIMEOUT" in ''|*[!0-9]*) TIMEOUT=10 ;; esac
[ "$TIMEOUT" -lt 1 ] && TIMEOUT=10

MAX_LINES_PER_CHECK=25
MAX_LINES_TOTAL=30

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
REPO_GIT_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0

CHECKS=""
[ -n "${ADVERSARY_CHECK:-}" ] && CHECKS="$ADVERSARY_CHECK"
if [ -f "$REPO_GIT_DIR/adversary-checks" ]; then
  FROM_FILE="$(grep -v '^[[:space:]]*\(#\|$\)' "$REPO_GIT_DIR/adversary-checks" 2>/dev/null || true)"
  [ -n "$FROM_FILE" ] && CHECKS="$(printf '%s\n%s' "$CHECKS" "$FROM_FILE" | grep '[^[:space:]]' || true)"
fi
[ -n "$CHECKS" ] || exit 0

# `timeout` is not on a stock macOS. perl's alarm is, and survives the exec.
#
# Output goes to a file, never up a pipe we read. A check that leaves a background child —
# a watcher, a daemon, anything `npm run` forks — hands that child the inherited stdout, and
# a command substitution then blocks reading the pipe until the child exits, however long
# after the timeout killed the shell. Measured: a 2s timeout on a check that backgrounds
# `sleep 8` returned after 8 seconds. Through a file there is nothing to block on.
run_check() { # run_check <command string> <output file>
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT" sh -c "$1" >"$2" 2>&1 </dev/null
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT" sh -c "$1" >"$2" 2>&1 </dev/null
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" sh -c "$1" >"$2" 2>&1 </dev/null
  else
    sh -c "$1" >"$2" 2>&1 </dev/null
  fi
}

# A fresh file per check, never one reused file. The child a timed-out check leaves behind
# keeps writing at its own offset; into a reused file that lands in the NEXT check's output,
# under the next check's name. Measured: check 2's output plus a NUL hole plus check 1's.
SCRATCH_DIR="$(mktemp -d "${TMPDIR:-/tmp}/adversary-checks.XXXXXX" 2>/dev/null)" || exit 0
trap 'rm -rf "$SCRATCH_DIR"' EXIT INT TERM
CHECK_N=0

OUT=""
while IFS= read -r CMD; do
  [ -n "$CMD" ] || continue
  # stdin is the check list; a check that reads stdin would eat the rest of it.
  CHECK_N=$(( CHECK_N + 1 ))
  SCRATCH="$SCRATCH_DIR/$CHECK_N"
  # 2>/dev/null is the shell's own job report ("Alarm clock: 14") when the timeout kills the
  # check, not the check's output — that already went to the file.
  run_check "$CMD" "$SCRATCH" 2>/dev/null; RC=$?
  RESULT="$(cat "$SCRATCH" 2>/dev/null)"
  # 124 is timeout(1); 142 is a shell reporting SIGALRM from the perl fallback.
  case "$RC" in
    0)         BODY="$(printf '%s' "$RESULT" | head -n "$MAX_LINES_PER_CHECK" | cut -c1-200)"
               [ -n "$BODY" ] || BODY="(clean)" ;;
    124|142)   BODY="(did not complete: still running after ${TIMEOUT}s)" ;;
    127)       BODY="(did not complete: command not found)" ;;
    *)         BODY="$(printf '%s' "$RESULT" | head -n "$MAX_LINES_PER_CHECK" | cut -c1-200)"
               [ -n "$BODY" ] || BODY="(did not complete: exit $RC, no output)" ;;
  esac
  OUT="$(printf '%s\n$ %s\n%s\n' "$OUT" "$CMD" "$BODY")"
done <<EOL
$CHECKS
EOL

printf '%s' "$OUT" | grep '[^[:space:]]' >/dev/null 2>&1 || exit 0
# OUT starts with the newline that built its first block; drop the leading blank lines.
printf '%s\n' "$OUT" | sed '/./,$!d' | head -n "$MAX_LINES_TOTAL"
exit 0
