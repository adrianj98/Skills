#!/usr/bin/env bash
# Stop hook: nudge once per distinct diff before Claude declares a coding turn done.
# Fires at most once per unique working-tree state, so it can never loop.
#
# Deliberately cheap: the lenses run in parallel and each reviewer is capped at 10
# turns (see agents/adversary.md), so the cost is one short round. It also stays
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

DIFF="$(git diff HEAD 2>/dev/null)"
[ -z "$DIFF" ] && exit 0

# Count only lines that can actually break at runtime: prose and licence files
# get no review, and they don't push a small code change over the threshold either.
CHANGED="$(git diff HEAD --numstat 2>/dev/null | awk -F'\t' '
  $3 ~ /\.(md|markdown|rst|txt|adoc)$/          { next }   # prose
  $3 ~ /(^|\/)(LICENSE|NOTICE|CHANGELOG|AUTHORS)$/ { next }   # boilerplate
  $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/            { n += $1 + $2 }  # "-" means binary
  END { print n + 0 }')"
[ "$CHANGED" -eq 0 ] && exit 0

# Small change: the nudge costs more than it returns. Stay quiet.
MIN_LINES="${ADVERSARY_MIN_LINES:-25}"
case "$MIN_LINES" in ''|*[!0-9]*) MIN_LINES=25 ;; esac
[ "$CHANGED" -lt "$MIN_LINES" ] && exit 0

HASH="$(printf '%s' "$DIFF" | shasum | cut -d' ' -f1)"
MARK="$(git rev-parse --git-dir)/adversary-reviewed"

if [ -f "$MARK" ] && [ "$(cat "$MARK")" = "$HASH" ]; then
  exit 0
fi
printf '%s' "$HASH" > "$MARK"

cat >&2 <<'MSG'
These changes have not been adversarially reviewed.

Delegate the diff to the `adversary` subagent (Task tool, subagent_type: adversary)
— one call per lens: correctness, failure-paths, lifetime-and-async, contract-drift.
Send all four in a SINGLE message so they run in parallel. Each one is capped at 10
turns, so the whole review is one short round, not an audit.

Do not review your own diff yourself; that is the whole point.

Fix what they confirm, mention what they call plausible, then finish. Don't run a
second round and don't re-review after fixing.

(To stop this: /adversarial-review:adversary off — or `adversary off` in a shell)
MSG
exit 2
