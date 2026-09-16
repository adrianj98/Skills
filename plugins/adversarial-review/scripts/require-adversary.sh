#!/usr/bin/env bash
# Stop hook: nudge once per distinct change before Claude declares a coding turn done.
# Fires at most once per unique state, so it can never loop.
#
# "Change" means everything new since the session started — commits included. Reviewing
# only `git diff HEAD` misses any work that got committed mid-turn, which on a repo that
# commits automatically is all of it. The anchor comes from scripts/session-base.sh
# (SessionStart); without it this degrades to the uncommitted diff.
#
# Deliberately bounded three ways: the lenses run in parallel, each reviewer is capped at 22
# turns (see agents/adversary.md), and the number of lenses scales with the size of the
# change — a two-file fix gets one reviewer, a feature branch gets four. It also stays quiet
# on small or docs-only diffs.
#
# Fixing a finding is itself a change, so it re-triggers this hook. What ends that chain is
# the reviewer scoring the fixes instead of hunting again (agents/adversary.md, "Round two"),
# not a threshold high enough to hide them.
#
# Tuning:      ADVERSARY_MIN_LINES=n   skip diffs smaller than n changed lines
#                                      (default 40; set 0 to review everything)
#              ADVERSARY_LENSES=...    force a lens set: `all`, or a comma-separated list
#              ADVERSARY_CHECK=...     a lint/typecheck command whose output is handed to the
#                                      reviewers (see scripts/mechanical-pass.sh)
#              ADVERSARY_MODEL=...     spawn the reviewers on this model rather than the one
#                                      that wrote the code (self-preference is a measured bias)
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

BASE=""; LAST=""; LAST_HASH=""; SESSION_BASE=""; PRE_HASH=""
if [ -f "$MARK" ]; then LAST="$(sed -n 1p "$MARK")"; LAST_HASH="$(sed -n 2p "$MARK")"; fi
[ -n "$LAST" ] && usable "$LAST" && BASE="$LAST"
if [ -n "$SESSION" ] && [ -f "$REPO_GIT_DIR/adversary-base-$SESSION" ]; then
  # Line 1 is the commit, line 2 the fingerprint of what was already dirty at session start.
  SESSION_BASE="$(sed -n 1p "$REPO_GIT_DIR/adversary-base-$SESSION")"
  PRE_HASH="$(sed -n 2p "$REPO_GIT_DIR/adversary-base-$SESSION")"
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
FILES="$(git diff --name-only "$BASE" 2>/dev/null | skip_prose | grep -c '[^[:space:]]' || true)"
case "$FILES" in ''|*[!0-9]*) FILES=0 ;; esac
if [ -n "$NEW_FILES" ]; then
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    CHANGED=$(( CHANGED + $(wc -l < "$f" 2>/dev/null || echo 0) ))
    FILES=$(( FILES + 1 ))
  done <<EOL
$NEW_FILES
EOL
fi
[ "$CHANGED" -eq 0 ] && exit 0

# Small change: the nudge costs more than it returns. Stay quiet.
MIN_LINES="${ADVERSARY_MIN_LINES:-40}"
case "$MIN_LINES" in ''|*[!0-9]*) MIN_LINES=40 ;; esac
[ "$CHANGED" -lt "$MIN_LINES" ] && exit 0

# Fingerprint the whole reviewable state, new files included, so the nudge fires again
# when something actually changes and stays quiet when Claude just stops twice.
HASH="$({ git diff --name-only "$BASE" 2>/dev/null | skip_prose
          printf '%s\n' "$NEW_FILES"; } | fingerprint worktree)"

[ -f "$MARK" ] && [ "$(sed -n 2p "$MARK")" = "$HASH" ] && exit 0

# Edits that were already in the tree when the session opened are the user's, not this
# session's. Only comparable while the anchor is still the session start; once a nudge has
# moved it, anything pre-existing is inside a range that has been through a review.
[ -n "$PRE_HASH" ] && [ "$BASE" = "$SESSION_BASE" ] && [ "$HASH" = "$PRE_HASH" ] && exit 0

# How many lenses this change is worth. Four reviewers on a two-file fix is most of what a
# review costs and little of what it returns; a feature branch is the case they were for.
if [ "$CHANGED" -gt 600 ] || [ "$FILES" -ge 8 ]; then
  LENSES="correctness, failure-paths, lifetime-and-async, contract-drift"
elif [ "$CHANGED" -gt 150 ]; then
  LENSES="correctness, failure-paths"
else
  LENSES="correctness"
fi
# Normalise the override before trusting it: `ALL`, `all,` and ` , all , ` all mean the same
# thing, and a value that is nothing but separators must fall back to the ladder rather than
# name no lens at all.
FORCED="$(printf '%s' "${ADVERSARY_LENSES:-}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
          grep '[^[:space:]]' | paste -sd, - | sed 's/,/, /g')"
case "$(printf '%s' "$FORCED" | tr 'A-Z' 'a-z')" in
  "")   ;;   # unset, or separators only: the ladder stands
  all)  LENSES="correctness, failure-paths, lifetime-and-async, contract-drift" ;;
  *)    LENSES="$FORCED" ;;
esac
case "$LENSES" in
  *,*) CALL_WORD="one call per lens"
       PARALLEL="Send them in a SINGLE message so they run in parallel." ;;
  *)   CALL_WORD="one call"
       PARALLEL="A change this size is worth one reviewer, not four." ;;
esac

# Exactly one fan-out instruction, never both. A change that followed findings is a scoring
# round; a change that didn't is a review. Emitting both leaves the model to pick, and either
# pick is wrong half the time.
FINDINGS="$REPO_GIT_DIR/adversary-findings.md"

# Existing is not the same as current. A findings file nothing deleted — the session ended, the
# fix round never happened, the model forgot — would otherwise turn the next unrelated change
# into a scoring pass against findings that describe different code: one reviewer, no hunt.
# Two cheap guards, both failing towards a full review, which is the safe direction:
#   - it has to have been written after this session started, i.e. these fixes are this session's
#   - a fix round is a small change; one at the four-lens rung is not a fix round
findings_live() {
  [ -f "$FINDINGS" ] || return 1
  [ "$CHANGED" -gt 600 ] && return 1
  [ "$FILES" -ge 8 ] && return 1
  if [ -n "$SESSION" ] && [ -f "$REPO_GIT_DIR/adversary-base-$SESSION" ]; then
    [ -n "$(find "$FINDINGS" -newer "$REPO_GIT_DIR/adversary-base-$SESSION" 2>/dev/null)" ]
  else
    [ -n "$(find "$FINDINGS" -mtime -1 2>/dev/null)" ]
  fi
}

if findings_live; then
  DIRECTIVE="The last round's findings are in $FINDINGS, and this change is what came of
fixing them — so this is a verdict pass, not a new review. Send ONE \`adversary\` subagent
(Agent tool, subagent_type: adversary) and paste that file into its prompt under a
\"## Prior findings\" heading. It will score each one — resolved, partial or unresolved —
instead of hunting from scratch, and that is what ends the fix-review chain.

Afterwards: delete $FINDINGS if everything came back resolved, or rewrite it with
what is still open. If this change plainly is not those fixes, delete it and review
normally ($CALL_WORD: $LENSES)."
else
  DIRECTIVE="Delegate them to the \`adversary\` subagent (Agent tool, subagent_type: adversary),
$CALL_WORD: $LENSES
$PARALLEL Add contract-drift if this diff changed an exported signature, a return type or a
public nullability — that is the one thing the line count above cannot see.

When they report, write their findings to $FINDINGS. The next round scores that file
instead of hunting again, and it has to outlive this session to do that."
  [ -f "$FINDINGS" ] && DIRECTIVE="$DIRECTIVE

($FINDINGS is left over from an earlier round and does not describe this change —
delete it, then review normally.)"
fi

# Anything the repo's own tooling already knows, so nobody spends a tool call finding it.
# Opt-in and silent unless configured; see scripts/mechanical-pass.sh.
MECHANICAL=""
for CANDIDATE in \
  "${CLAUDE_PLUGIN_ROOT:-}/scripts/mechanical-pass.sh" \
  "$HERE/mechanical-pass.sh"
do
  [ -f "$CANDIDATE" ] && { MECHANICAL="$(bash "$CANDIDATE" 2>/dev/null || true)"; break; }
done

RANGE="git diff $BASE"
# A repo with no commits has nothing to diff against; the untracked list is the whole change.
git rev-parse --verify --quiet HEAD >/dev/null 2>&1 ||
  RANGE="(no commits yet, so there is no diff — the new files below are the whole change)"

# The reviewer inherits the session's model unless told otherwise. Judging code with the model
# that wrote it is a measured bias (self-preference), so the override is one variable away.
MODEL_LINE=""
[ -n "${ADVERSARY_MODEL:-}" ] && MODEL_LINE="
Spawn every reviewer with model: ${ADVERSARY_MODEL} (the Agent tool's model parameter), so the
code is not judged by the model that wrote it."

# Only now, with the message about to go out, record that this state was covered. Writing it
# earlier means a hook killed in between (a slow mechanical check, a harness timeout) records
# the change as reviewed and the nudge never fires for it again.
# Line 1 anchors the next review, line 2 says what this one covered.
{ git rev-parse HEAD 2>/dev/null || echo ""; printf '%s\n' "$HASH"; } > "$MARK"

# Hook output is capped at 10,000 characters and truncated from the end, so the order below is
# by importance: what to do, then how to answer, then the off switch, and the optional linter
# output last — it is the one block that can run long, and losing its tail costs nothing.
cat >&2 <<MSG
These changes have not been adversarially reviewed.

$DIRECTIVE$MODEL_LINE

Run this range ONCE yourself and paste the diff into every prompt under a
"## The diff" heading — don't make the agents each fetch it. Start from exactly
this, not from \`git diff HEAD\`; some of this work is already committed, so HEAD
alone shows nothing:

  $RANGE
$([ -n "$NEW_FILES" ] && printf '\n  ...and these new files, which no diff covers yet:\n%s\n' "$(printf '%s' "$NEW_FILES" | sed 's/^/    /')")
Do not review your own work yourself; that is the whole point.

Each reviewer returns a verdict word — block, concerns or clean. Report the worst one
verbatim; you do not get to soften it. Fix only what a reviewer marked confirmed; mention
what it called plausible and leave it alone — a reviewer told to assume the code is wrong
returns some findings that are not there, and a guard deleted on a plausible is a bug you
introduced. Don't chase findings yourself and don't re-run the review after fixing: if the
fixes change the tree, this hook fires again and asks for a scoring pass, not a new hunt.

This hook interrupted the answer you were about to give, so write that answer now. Your
last message is about the work that was asked for — what you did, what you found, what is
left — and the review is a short block at the end of it: the verdict word, what you fixed,
what you left open. The review is an aside about the work, not a replacement for it; a
reply that is nothing but a review report leaves the user with no answer to what they asked.

(To stop this: /adversarial-review:adversary off — or \`adversary off\` in a shell)
$([ -n "$MECHANICAL" ] && printf '\nPaste this in too, under "## Already known mechanically", so nobody spends a\ntool call rediscovering it:\n\n%s\n' "$(printf '%s' "$MECHANICAL" | sed 's/^/    /')")
MSG
exit 2
