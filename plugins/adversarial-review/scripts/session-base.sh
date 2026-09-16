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
#
# Line 1 is the commit. Line 2 fingerprints whatever was already dirty in the tree at that
# moment, computed exactly the way scripts/require-adversary.sh fingerprints the reviewable
# state. Edits the user had in flight before the session opened are not this session's work;
# without this line the first Stop — even one that only answered a question — asks for a
# review of them.
skip_prose() { awk '
  /\.(md|markdown|rst|txt|adoc)$/             { next }
  /(^|\/)(LICENSE|NOTICE|CHANGELOG|AUTHORS)$/ { next }
  { print }'; }
fingerprint() {
  local f
  sort -u | while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$f"
    [ -f "$f" ] && cat "$f"
  done | shasum | cut -d' ' -f1
}
if [ ! -f "$BASE" ] && HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)"; then
  PRE="$({ git diff --name-only HEAD 2>/dev/null | skip_prose
           git ls-files --others --exclude-standard 2>/dev/null | head -50 | grep '[^[:space:]]' | skip_prose
         } | fingerprint)"
  printf '%s\n%s\n' "$HEAD_SHA" "$PRE" > "$BASE" 2>/dev/null || true
fi

# Sessions end without telling us, so sweep instead of cleaning up. A findings file goes the
# same way: the round it belonged to is long over, and a stale one costs a real review.
find "$REPO_GIT_DIR" -maxdepth 1 -name 'adversary-base-*' -mtime +7 -delete 2>/dev/null || true
find "$REPO_GIT_DIR" -maxdepth 1 -name 'adversary-findings.md' -mtime +7 -delete 2>/dev/null || true
exit 0
