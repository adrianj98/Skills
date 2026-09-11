#!/usr/bin/env bash
# SessionStart hook: remember where the repo stood when this session began.
#
# The Stop hook reviews everything that changed since this mark, so work that gets
# committed mid-session is still reviewed. Without it, `git diff HEAD` goes blank the
# moment anything is committed and the nudge never fires again.
#
# One file per session under .git/, holding one commit sha. Stale ones are pruned.
set -uo pipefail

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Hook input arrives as JSON on stdin. Never block on a terminal (someone running this
# by hand) and never let a malformed payload matter: no session id just means no baseline.
INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"
SESSION="$(printf '%s' "$INPUT" |
  sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 |
  tr -cd 'A-Za-z0-9_-')"
[ -n "$SESSION" ] || exit 0

REPO_GIT_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
BASE="$REPO_GIT_DIR/adversary-base-$SESSION"

# First sighting of this session wins: a resume or a compact must not move the baseline
# forward over work this session already did.
[ -f "$BASE" ] || git rev-parse HEAD > "$BASE" 2>/dev/null || true

# Sessions end without telling us, so sweep instead of cleaning up.
find "$REPO_GIT_DIR" -maxdepth 1 -name 'adversary-base-*' -mtime +7 -delete 2>/dev/null || true
exit 0
