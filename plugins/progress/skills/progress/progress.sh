#!/usr/bin/env bash
# Everything there is to know about where a branch and its PR stand, as plain text for a
# model to summarise: the branch's commits against its base, what's uncommitted or unpushed,
# the PR's reviews, review threads, checks and mergeability, and what aj-log.md says.
#
#   progress.sh                 the checked-out branch and its PR
#   progress.sh 123             a PR by number (its branch too, if it's checked out somewhere)
#   progress.sh feature/x       a branch, local or remote
#   progress.sh <pr url>
#
# Needs git. GitHub parts need gh, logged in; without it they say so and the rest still runs.
set -uo pipefail

TARGET="${1:-}"
case "$TARGET" in -h|--help) sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 0 ;; esac

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not inside a git repository"; exit 0; }

HAVE_GH=0
command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 && HAVE_GH=1

# ---------- which PR, which branch ----------
PR_JSON=""
pr_view() { gh pr view "$@" --json number,title,url,state,isDraft,author,baseRefName,headRefName,headRepositoryOwner,createdAt,updatedAt,mergedAt,closedAt,body,labels,assignees,milestone,reviewDecision,reviewRequests,reviews,comments,mergeable,mergeStateStatus,statusCheckRollup,additions,deletions,changedFiles,autoMergeRequest 2>/dev/null; }

BRANCH=""
if [ -z "$TARGET" ]; then
  BRANCH="$(git branch --show-current)"
  [ "$HAVE_GH" = 1 ] && PR_JSON="$(pr_view)"
elif [ "$HAVE_GH" = 1 ] && PR_JSON="$(pr_view "$TARGET")" && [ -n "$PR_JSON" ]; then
  BRANCH="$(printf '%s' "$PR_JSON" | jq -r .headRefName)"
else
  BRANCH="$TARGET"
fi
[ -n "$PR_JSON" ] && [ "$(printf '%s' "$PR_JSON" | jq -r .number)" = "null" ] && PR_JSON=""

# A local ref for the branch: the branch itself, else its remote-tracking copy. Fetched
# first so "behind" numbers are current; a failed fetch (offline) is not fatal.
git fetch --quiet --all 2>/dev/null
HEAD_REF=""
if git rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then HEAD_REF="$BRANCH"
elif git rev-parse --verify --quiet "refs/remotes/origin/$BRANCH" >/dev/null; then HEAD_REF="origin/$BRANCH"
fi

# Base: the PR's base branch, else the remote's default branch, else main/master.
BASE=""
[ -n "$PR_JSON" ] && BASE="$(printf '%s' "$PR_JSON" | jq -r .baseRefName)"
[ -n "$BASE" ] || BASE="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
if [ -z "$BASE" ]; then for b in main master develop; do git rev-parse --verify --quiet "refs/heads/$b" >/dev/null && { BASE="$b"; break; }; done; fi
BASE_REF=""
git rev-parse --verify --quiet "refs/remotes/origin/$BASE" >/dev/null && BASE_REF="origin/$BASE"
[ -n "$BASE_REF" ] || { git rev-parse --verify --quiet "refs/heads/$BASE" >/dev/null && BASE_REF="$BASE"; }

CURRENT="$(git branch --show-current)"
echo "branch    ${BRANCH:-(detached $(git rev-parse --short HEAD))}$([ "$BRANCH" = "$CURRENT" ] && echo '  (checked out here)' || echo "  (not checked out here; this worktree is on ${CURRENT:-a detached HEAD})")"
echo "base      ${BASE:-?}"
if [ -n "$HEAD_REF" ] && [ -n "$BASE_REF" ]; then
  AB="$(git rev-list --left-right --count "$BASE_REF...$HEAD_REF" 2>/dev/null)"
  MB="$(git merge-base "$BASE_REF" "$HEAD_REF" 2>/dev/null)"
  MERGES="$(git rev-list --merges --count "$MB..$HEAD_REF" 2>/dev/null)"
  echo "vs base   ahead $(echo "$AB" | cut -f2) commits$([ "${MERGES:-0}" -gt 0 ] && echo " ($MERGES of them merges from $BASE, not listed below)"), behind $(echo "$AB" | cut -f1)  ($BASE_REF...$HEAD_REF)"
fi
if [ -n "$HEAD_REF" ] && [ "$HEAD_REF" = "$BRANCH" ]; then
  UP="$(git rev-parse --abbrev-ref --symbolic-full-name "$BRANCH@{upstream}" 2>/dev/null)"
  if [ -n "$UP" ]; then
    AB="$(git rev-list --left-right --count "$UP...$BRANCH" 2>/dev/null)"
    echo "vs remote $UP: unpushed $(echo "$AB" | cut -f2), unpulled $(echo "$AB" | cut -f1)"
  else
    echo "vs remote no upstream: never pushed"
  fi
fi
if [ -n "$HEAD_REF" ]; then
  echo "last      $(git log -1 --date=relative --format='%ad, %an: %s' "$HEAD_REF")"
fi

# ---------- working tree (only meaningful for the checked-out branch) ----------
if [ "$BRANCH" = "$CURRENT" ]; then
  echo
  echo "== working tree"
  ST="$(git status --porcelain=v1 2>/dev/null)"
  if [ -n "$ST" ]; then
    printf '%s\n' "$ST" | head -40
    N="$(printf '%s\n' "$ST" | wc -l | tr -d ' ')"; [ "$N" -gt 40 ] && echo "... $((N-40)) more"
  else
    echo "clean"
  fi
  SN="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
  [ "$SN" -gt 0 ] && echo "stashes   $SN"
fi

# ---------- commits on the branch ----------
echo
echo "== commits on the branch (oldest first)"
if [ -n "$HEAD_REF" ] && [ -n "${MB:-}" ]; then
  LOG="$(git log --reverse --no-merges --date=format-local:'%b %d %H:%M' \
          --format='%h  %ad  %an  %s%n%w(0,4,4)%b' "$MB..$HEAD_REF" |
         grep -v '^[[:space:]]*$' | grep -iv '^[[:space:]]*co-authored-by:')"
  if [ -n "$LOG" ]; then printf '%s\n' "$LOG"; else echo "(none: branch is at or behind $BASE)"; fi
  echo
  echo "== files changed vs $BASE"
  git diff --stat=100 "$MB" "$HEAD_REF" 2>/dev/null | tail -25
elif [ -n "$PR_JSON" ]; then
  echo "(branch not fetched locally; from GitHub)"
  gh pr view "$(printf '%s' "$PR_JSON" | jq -r .number)" --json commits,files \
    --jq '(.commits[] | "\(.oid[0:7])  \(.authors[0].name)  \(.messageHeadline)\n" + (.messageBody | split("\n") | map(select(length>0 and (test("(?i)^co-authored-by")|not))) | map("    "+.) | join("\n"))), "", "== files changed", (.files[] | "\(.path)  +\(.additions) -\(.deletions)")' 2>/dev/null | grep -v '^[[:space:]]*$'
else
  echo "(no local ref for $BRANCH)"
fi

# ---------- the PR ----------
echo
if [ "$HAVE_GH" = 0 ]; then
  echo "== pull request"; echo "(gh not available or not logged in)"
elif [ -z "$PR_JSON" ]; then
  echo "== pull request"; echo "(none for $BRANCH)"
  [ -n "$BRANCH" ] && gh pr list --head "$BRANCH" --state all --limit 5 --json number,state,title --jq '.[] | "  earlier: #\(.number) \(.state) \(.title)"' 2>/dev/null
else
  printf '%s' "$PR_JSON" | jq -r '
    def ago: . as $d | ($d | fromdateiso8601) as $t | (now - $t) as $s |
      if $s < 3600 then "\($s/60|floor)m ago" elif $s < 86400 then "\($s/3600|floor)h ago" else "\($s/86400|floor)d ago" end;
    "== pull request #\(.number)  \(.url)",
    "title     \(.title)",
    "state     \(if .isDraft then "DRAFT" else .state end)\(if .mergedAt then " \(.mergedAt|ago)" elif .closedAt then " \(.closedAt|ago)" else "" end)  by \(.author.login)  \(.headRefName) -> \(.baseRefName)",
    "opened    \(.createdAt|ago), updated \(.updatedAt|ago)",
    "size      \(.changedFiles) files, +\(.additions) -\(.deletions)",
    (if (.labels|length)>0 then "labels    \(.labels|map(.name)|join(", "))" else empty end),
    (if (.assignees|length)>0 then "assignees \(.assignees|map(.login)|join(", "))" else empty end),
    (if .milestone then "milestone \(.milestone.title)" else empty end),
    (if .autoMergeRequest then "auto-merge enabled" else empty end),
    "merge     mergeable=\(.mergeable) status=\(.mergeStateStatus)",
    "",
    "-- review: \(if .reviewDecision == "" then "none" else .reviewDecision end)",
    (if (.reviewRequests|length)>0 then "waiting on \(.reviewRequests|map(.login // .name)|join(", "))" else empty end),
    (
      # latest non-comment review per reviewer
      [.reviews[] | select(.state != "COMMENTED")] | group_by(.author.login) | map(max_by(.submittedAt)) | .[] |
      "\(.author.login): \(.state) \(.submittedAt|ago)\(if (.body|length)>0 then "  \"\(.body|gsub("\n";" ")|.[0:160])\"" else "" end)"
    ),
    "",
    "-- checks: " + (
      (.statusCheckRollup // []) as $c |
      if ($c|length)==0 then "none" else
        ($c | map(if .__typename=="CheckRun" then (.conclusion // .status) else .state end)) as $s |
        "\($s|map(select(.=="SUCCESS"))|length) passed, \($s|map(select(.=="FAILURE" or .=="ERROR" or .=="TIMED_OUT" or .=="CANCELLED" or .=="ACTION_REQUIRED"))|length) failed, \($s|map(select(.=="PENDING" or .=="IN_PROGRESS" or .=="QUEUED" or .=="EXPECTED" or .=="WAITING"))|length) pending, \($s|map(select(.=="SKIPPED" or .=="NEUTRAL"))|length) skipped"
      end),
    ((.statusCheckRollup // [])[] | select((.conclusion // .state // .status) as $x | $x != "SUCCESS" and $x != "SKIPPED" and $x != "NEUTRAL") |
      "  \(.conclusion // .state // .status)  \(.name // .context)  \(.detailsUrl // .targetUrl // "")"),
    "",
    "-- description",
    (.body | if length==0 then "(empty)" else (split("\n") | map(select(test("^🤖 Generated with")|not)) | join("\n")) end)
  '

  # Review threads: how many are still open, and what they're about. The REST/CLI view
  # doesn't carry isResolved; GraphQL does.
  OWNER="$(printf '%s' "$PR_JSON" | jq -r '.url | split("/")[3]')"
  REPO="$(printf '%s' "$PR_JSON" | jq -r '.url | split("/")[4]')"
  NUM="$(printf '%s' "$PR_JSON" | jq -r .number)"
  echo
  echo "-- review threads"
  gh api graphql -F owner="$OWNER" -F repo="$REPO" -F n="$NUM" -f query='
    query($owner:String!,$repo:String!,$n:Int!){ repository(owner:$owner,name:$repo){ pullRequest(number:$n){
      reviewThreads(first:100){ nodes{ isResolved isOutdated path line
        comments(first:50){ totalCount nodes{ author{login} body } } } } } } }' 2>/dev/null |
  jq -r '
    .data.repository.pullRequest.reviewThreads.nodes as $t |
    if ($t|length)==0 then "none" else
      "\($t|map(select(.isResolved|not))|length) unresolved of \($t|length)",
      ($t[] | select(.isResolved|not) |
        "  \(.path // "general")\(if .line then ":\(.line)" else "" end)  \(.comments.nodes[0].author.login): \(.comments.nodes[0].body|gsub("\n";" ")|.[0:200])" +
        (if .comments.totalCount>1 then "  (\(.comments.totalCount-1) repl\(if .comments.totalCount==2 then "y" else "ies" end), last by \(.comments.nodes[-1].author.login))" else "" end))
    end' 2>/dev/null || echo "(could not read)"

  # Conversation comments, newest last and in full, so a "ready for another look" or a
  # question nobody answered is visible, and a "blocked because..." isn't cut mid-sentence.
  echo
  echo "-- conversation (last 5 of $(printf '%s' "$PR_JSON" | jq '.comments|length'))"
  printf '%s' "$PR_JSON" | jq -r '
    def ago: . as $d | ($d | fromdateiso8601) as $t | (now - $t) as $s |
      if $s < 3600 then "\($s/60|floor)m ago" elif $s < 86400 then "\($s/3600|floor)h ago" else "\($s/86400|floor)d ago" end;
    if (.comments|length)==0 then "none" else
      (.comments | .[-5:] | .[] | "\(.author.login) (\(.createdAt|ago)):\n" + (.body | .[0:1500] | split("\n") | map("    "+.) | join("\n")))
    end'
fi

# ---------- aj-log.md ----------
# Lines the branch added to any aj-log.md, plus whatever is uncommitted in the checked-out one.
echo
echo "== aj-log.md"
found=0
if [ -n "$HEAD_REF" ] && [ -n "${MB:-}" ]; then
  ADDED="$(git log --reverse -p --format= "$MB..$HEAD_REF" -- 'aj-log.md' '*/aj-log.md' 2>/dev/null | grep '^+' | grep -v '^+++' | sed 's/^+//')"
  [ -n "$ADDED" ] && { found=1; printf '%s\n' "$ADDED" | tail -60; }
fi
if [ "$BRANCH" = "$CURRENT" ]; then
  for f in aj-log.md "$(git rev-parse --path-format=absolute --git-common-dir)/aj-log.md"; do
    [ -f "$f" ] || continue
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      D="$(git diff HEAD -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//')"
    else
      D="$(tail -n 30 "$f")"
    fi
    [ -n "$D" ] && { found=1; echo "-- $f (uncommitted)"; printf '%s\n' "$D"; }
  done
fi
[ "$found" = 1 ] || echo "(nothing from this branch)"

# ---------- issue keys ----------
KEYS="$( { echo "$BRANCH"; [ -n "$PR_JSON" ] && printf '%s' "$PR_JSON" | jq -r '.title, .body'; } | grep -oE '\b[A-Z][A-Z0-9]+-[0-9]+\b' | sort -u | tr '\n' ' ')"
[ -n "$KEYS" ] && { echo; echo "== issue keys  $KEYS"; }
exit 0
