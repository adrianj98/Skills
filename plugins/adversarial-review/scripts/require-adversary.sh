#!/usr/bin/env bash
# Stop hook: nudge once per distinct change before Claude declares a coding turn done.
# Fires at most once per unique state, so it can never loop.
#
# "Change" means everything new since the session started — commits included. Reviewing
# only `git diff HEAD` misses any work that got committed mid-turn, which on a repo that
# commits automatically is all of it. The anchor comes from scripts/session-base.sh
# (SessionStart); without it this degrades to the uncommitted diff.
#
# Deliberately bounded: the lenses run in parallel and each reviewer is capped at 40
# turns (see agents/adversary.md), so the cost is one round. It also stays
# quiet on small or docs-only diffs.
#
# Tuning:      ADVERSARY_MIN_LINES=n   skip diffs smaller than n changed lines
#                                      (default 25; set 0 to review everything)
# Off switch:  adversary off          (this repo)
#              adversary off --all    (everywhere)
#              ADVERSARY_REVIEW=0     (one session)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for CANDIDATE in \
  "${CLAUDE_PLUGIN_ROOT:-}/bin/adversary" \
  "$HERE/../bin/adversary" \
  "$HERE/adversary" \
  "$HERE/adversary.sh" \
  "$(command -v adversary 2>/dev/null || true)"
do
  [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE" ] && { TOGGLE="$CANDIDATE"; break; }
done
# No toggle found: fail open rather than nagging with no way to stop it.
[ -n "${TOGGLE:-}" ] || exit 0
bash "$TOGGLE" is-on || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
REPO_GIT_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0

INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"
SESSION="$(printf '%s' "$INPUT" |
  sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 |
  tr -cd 'A-Za-z0-9_-')"

MARK="$REPO_GIT_DIR/adversary-reviewed"

# What to review, from the tightest anchor that still covers everything new:
#   1. the commit HEAD was at when we last nudged — work before it has been through this
#   2. where this session started (scripts/session-base.sh)
#   3. HEAD, i.e. uncommitted only, when neither is available
# Both anchors have to be real commits HEAD descends from; a rebase, reset or pull can
# leave either dangling, and diffing against a commit off the current line of history
# produces noise, not a review.
usable() { git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1 &&
           git merge-base --is-ancestor "$1" HEAD 2>/dev/null; }

BASE=""; LAST=""; LAST_HASH=""
if [ -f "$MARK" ]; then LAST="$(sed -n 1p "$MARK")"; LAST_HASH="$(sed -n 2p "$MARK")"; fi
[ -n "$LAST" ] && usable "$LAST" && BASE="$LAST"
if [ -n "$SESSION" ] && [ -f "$REPO_GIT_DIR/adversary-base-$SESSION" ]; then
  SESSION_BASE="$(cat "$REPO_GIT_DIR/adversary-base-$SESSION")"
  if usable "$SESSION_BASE"; then
    # Whichever anchor is further along: the session start if we have not nudged since it,
    # the last nudge if we have.
    if [ -z "$BASE" ] || git merge-base --is-ancestor "$BASE" "$SESSION_BASE" 2>/dev/null; then
      BASE="$SESSION_BASE"
    fi
  fi
fi
[ -n "$BASE" ] || BASE=HEAD

# Prose is never reviewed, so it must not count towards any of this: not the threshold,
# and not the fingerprints — a README edit that made them differ would wedge the anchor.
skip_prose() { awk '
  /\.(md|markdown|rst|txt|adoc)$/             { next }   # prose
  /(^|\/)(LICENSE|NOTICE|CHANGELOG|AUTHORS)$/ { next }   # boilerplate
  { print }'; }

# Fingerprint by content, not by diff text: the same code is the same review whether it
# is sitting untracked in the tree or already committed. Paths on stdin, read either from
# the working tree or from a revision.
fingerprint() {
  local at="$1" f
  sort -u | while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$f"
    if [ "$at" = worktree ]; then [ -f "$f" ] && cat "$f"
    else git show "$at:$f" 2>/dev/null; fi
  done | shasum | cut -d' ' -f1
}

# The last nudge covered a dirty tree, which no commit can anchor. Once that exact work is
# committed, the commit is the anchor we wanted — without this, every review after a commit
# re-reviews what the previous one already covered.
if [ -n "$LAST_HASH" ] && [ "$BASE" != HEAD ]; then
  COMMITTED="$(git diff --name-only "$BASE" HEAD 2>/dev/null | skip_prose | fingerprint HEAD)"
  [ "$COMMITTED" = "$LAST_HASH" ] && BASE="$(git rev-parse HEAD)"
fi

DIFF="$(git diff "$BASE" 2>/dev/null)"

# Files Claude created but never staged are invisible to git diff, and a new file is
# exactly the kind of thing worth reviewing. Carry them alongside.
UNTRACKED="$(git ls-files --others --exclude-standard 2>/dev/null | head -50)"

[ -z "$DIFF" ] && [ -z "$UNTRACKED" ] && exit 0

# Count only lines that can actually break at runtime: prose and licence files
# get no review, and they don't push a small code change over the threshold either.
CHANGED="$(git diff "$BASE" --numstat 2>/dev/null | awk -F'\t' '
  $3 ~ /\.(md|markdown|rst|txt|adoc)$/          { next }   # prose
  $3 ~ /(^|\/)(LICENSE|NOTICE|CHANGELOG|AUTHORS)$/ { next }   # boilerplate
  $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/            { n += $1 + $2 }  # "-" means binary
  END { print n + 0 }')"
NEW_FILES="$(printf '%s' "$UNTRACKED" | grep '[^[:space:]]' | skip_prose || true)"
if [ -n "$NEW_FILES" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    CHANGED=$(( CHANGED + $(wc -l < "$f" 2>/dev/null || echo 0) ))
  done <<EOL
$NEW_FILES
EOL
fi
[ "$CHANGED" -eq 0 ] && exit 0

# Small change: the nudge costs more than it returns. Stay quiet.
MIN_LINES="${ADVERSARY_MIN_LINES:-25}"
case "$MIN_LINES" in ''|*[!0-9]*) MIN_LINES=25 ;; esac
[ "$CHANGED" -lt "$MIN_LINES" ] && exit 0

# Fingerprint the whole reviewable state, new files included, so the nudge fires again
# when something actually changes and stays quiet when Claude just stops twice.
HASH="$({ git diff --name-only "$BASE" 2>/dev/null | skip_prose
          printf '%s\n' "$NEW_FILES"; } | fingerprint worktree)"

[ -f "$MARK" ] && [ "$(sed -n 2p "$MARK")" = "$HASH" ] && exit 0
# Line 1 anchors the next review, line 2 says what this one covered.
{ git rev-parse HEAD 2>/dev/null || echo ""; printf '%s\n' "$HASH"; } > "$MARK"

RANGE="git diff $BASE"
cat >&2 <<MSG
These changes have not been adversarially reviewed.

Delegate them to the \`adversary\` subagent (Task tool, subagent_type: adversary)
— one call per lens: correctness, failure-paths, lifetime-and-async, contract-drift.
Send all four in a SINGLE message so they run in parallel. Each one is capped at 40
turns, so the whole review is one round, not an audit.

Tell each reviewer to start from exactly this, not from \`git diff HEAD\` — some of
this work is already committed, so HEAD alone shows nothing:

  $RANGE
$([ -n "$NEW_FILES" ] && printf '\n  ...and these new files, which no diff covers yet:\n%s\n' "$(printf '%s' "$NEW_FILES" | sed 's/^/    /')")
Do not review your own work yourself; that is the whole point.

Fix what they confirm, mention what they call plausible, then finish. Don't run a
second round and don't re-review after fixing.

(To stop this: /adversarial-review:adversary off — or \`adversary off\` in a shell)
MSG
exit 2
