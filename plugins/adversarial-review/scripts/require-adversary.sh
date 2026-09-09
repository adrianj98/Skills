#!/usr/bin/env bash
# Stop hook: nudge once per distinct diff before Claude declares a coding turn done.
# Fires at most once per unique working-tree state, so it can never loop.
#
# Off switch:  adversary off          (this repo)
#              adversary off --all    (everywhere)
#              ADVERSARY_REVIEW=0     (one session)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for CANDIDATE in \
  "${CLAUDE_PLUGIN_ROOT:-}/bin/adversary" \
  "$HERE/../bin/adversary" \
  "$HERE/adversary.sh" \
  "$(command -v adversary 2>/dev/null || true)"
do
  [ -n "$CANDIDATE" ] && [ -f "$CANDIDATE" ] && { TOGGLE="$CANDIDATE"; break; }
done
# No toggle found: fail open rather than nagging with no way to stop it.
[ -n "${TOGGLE:-}" ] || exit 0
bash "$TOGGLE" is-on || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

DIFF="$(git diff HEAD 2>/dev/null; git diff --cached 2>/dev/null)"
[ -z "$DIFF" ] && exit 0

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
Do not review your own diff yourself; that is the whole point.

Address anything it confirms, then finish.
(To stop this: /adversarial-review:adversary off — or `adversary off` in a shell)
MSG
exit 2
