#!/usr/bin/env bash
# Every commit reachable from any worktree of this repo since a cutoff, oldest first, then
# your GitHub PRs touched since then and what each worktree's aj-log.md gained.
#
#   standup.sh                      since yesterday 06:00, your commits only
#   standup.sh --since "friday 6am" any git date: "3 days ago", "2026-09-01", ...
#   standup.sh --everyone           every author, not just you
#
# Worktrees share one object store, so a single `git log` over every worktree's HEAD walks
# them all and lists a commit once, however many worktrees can reach it.
set -uo pipefail

SINCE="yesterday 06:00"; EVERYONE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --since)    [ -n "${2:-}" ] || { echo "--since needs a date" >&2; exit 2; }; SINCE="$2"; shift ;;
    --since=*)  SINCE="${1#--since=}" ;;
    --everyone|--all) EVERYONE=1 ;;
    -h|--help)  sed -n '2,10s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *)          echo "usage: standup.sh [--since WHEN] [--everyone]" >&2; exit 2 ;;
  esac
  shift
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "not inside a git repository"; exit 0; }

# git parses the date itself; ask it for the epoch so the cutoff printed is the one it used.
EPOCH="$(git rev-parse --since="$SINCE" 2>/dev/null | sed -n 's/^--max-age=//p')"
[ -n "$EPOCH" ] || { echo "could not read a date from: $SINCE" >&2; exit 2; }
fmt() { date -r "$EPOCH" "$1" 2>/dev/null || date -d "@$EPOCH" "$1"; }
CUTOFF="$(fmt '+%a %b %d %H:%M')"
DAY="$(fmt '+%Y-%m-%d')"

# One tip per worktree: its branch when it has one, so %S below names the branch, else the
# detached sha. Bash 3.2 (macOS) has no mapfile, and an empty array trips `set -u`, hence
# the ${arr[@]+...} guards.
TIPS=(); WTS=(); WT=""; HEAD=""; BRANCH=""
flush() {
  [ -n "$WT" ] || return 0
  WTS+=("$WT")
  local tip="${BRANCH:-$HEAD}"
  if [ -n "$tip" ] && git rev-parse --verify --quiet "$tip^{commit}" >/dev/null; then
    TIPS+=("$tip")
    printf 'worktree  %s  (%s)\n' "$WT" "$([ -n "$BRANCH" ] && echo "${BRANCH#refs/heads/}" || echo "detached ${HEAD:0:7}")"
  fi
  WT=""; HEAD=""; BRANCH=""
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush; WT="${line#worktree }" ;;
    "HEAD "*)     HEAD="${line#HEAD }" ;;
    "branch "*)   BRANCH="${line#branch }" ;;
  esac
done <<EOF
$(git worktree list --porcelain)
EOF
flush
[ ${#TIPS[@]} -gt 0 ] || { echo "no worktree has a commit yet"; exit 0; }

# Name or email, so commits made with either still count as yours. --author is a regex.
AUTHOR=()
if [ "$EVERYONE" = 0 ]; then
  esc() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }
  NAME="$(git config user.name 2>/dev/null)"; EMAIL="$(git config user.email 2>/dev/null)"
  [ -n "$NAME" ]  && AUTHOR+=("--author=$(esc "$NAME")")
  [ -n "$EMAIL" ] && AUTHOR+=("--author=$(esc "$EMAIL")")
fi

echo "since     $CUTOFF$([ "$EVERYONE" = 1 ] && echo '  (everyone)' || echo '  (your commits)')"
echo

# Label each commit with the nearest branch that contains it (main~3 -> main). Not
# `log --source`: that credits a shared commit to whichever tip the walk reached first,
# which is usually the newest worktree, not the branch the work landed on. A commit no
# branch contains keeps its sha, shortened. --annotate-stdin is git 2.40+; --stdin before.
TAB="$(printf '\t')"
# Captured, not piped to `grep -q`: under pipefail its early exit SIGPIPEs git and the test fails.
case "$(git name-rev -h 2>&1)" in *--annotate-stdin*) STDIN_FLAG=--annotate-stdin ;; *) STDIN_FLAG=--stdin ;; esac
LOG="$(git log "${TIPS[@]}" ${AUTHOR[@]+"${AUTHOR[@]}"} --no-merges --since="@$EPOCH" --reverse \
  --date=format-local:'%a %H:%M' --format='%H%x09%ad%x09%h%x09%s' |
  git name-rev "$STDIN_FLAG" --name-only --refs='refs/heads/*' |
  sed -e "s|^\([0-9a-f]\{7\}\)[0-9a-f]\{33\}$TAB|detached \1$TAB|" \
      -e "s|^\([^$TAB~^]*\)[~^][^$TAB]*$TAB|\1$TAB|")"
if [ -n "$LOG" ]; then printf '%s\n' "$LOG"; else echo "(no commits)"; fi

# ---------- GitHub PRs ----------
# Yours that were opened, updated or merged since the cutoff, and others' you reviewed.
# Silent about why when gh is missing or not logged in: the standup works without it.
echo
echo "== github prs (updated since $DAY)"
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  PRS="$(gh search prs --author=@me --updated=">=$DAY" --limit 30 \
           --json number,title,state,repository,isDraft \
           --jq '.[] | "mine      \(.repository.nameWithOwner)#\(.number)  \(if .isDraft then "draft" else .state end)  \(.title)"' 2>/dev/null
         gh search prs --reviewed-by=@me --updated=">=$DAY" --limit 30 \
           --json number,title,state,repository,author \
           --jq '.[] | "reviewed  \(.repository.nameWithOwner)#\(.number)  \(.state)  \(.title)  (by \(.author.login))"' 2>/dev/null)"
  PRS="$(printf '%s\n' "$PRS" | grep -v "^reviewed .*(by $(gh api user --jq .login 2>/dev/null))$" | grep '[^[:space:]]')"
  if [ -n "$PRS" ]; then printf '%s\n' "$PRS"; else echo "(none)"; fi
else
  echo "(gh not available or not logged in)"
fi

# ---------- aj-log.md ----------
# A worktree's running log of changes and why. Only what was added since the cutoff: from
# git when the file is tracked, otherwise the tail of a file that was touched since then.
echo
echo "== aj-log.md"
found=0
for wt in ${WTS[@]+"${WTS[@]}"}; do
  f="$wt/aj-log.md"
  [ -f "$f" ] || continue
  m="$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f")"
  [ "$m" -ge "$EPOCH" ] || continue
  found=1
  echo "-- $f"
  if git -C "$wt" ls-files --error-unmatch aj-log.md >/dev/null 2>&1; then
    { git -C "$wt" log --since="@$EPOCH" --reverse -p --format= -- aj-log.md
      git -C "$wt" diff HEAD -- aj-log.md; } | grep '^+' | grep -v '^+++' | sed 's/^+//'
  else
    tail -n 60 "$f"
  fi
done
[ "$found" = 1 ] || echo "(no aj-log.md changed since $CUTOFF)"
exit 0
