#!/usr/bin/env bash
# Merge the repo's default branch into the current branch, push it, run CI on it on GitHub
# Actions and prove it passed, including the integration tests, with a verdict a model can
# only copy, not infer. On the default branch itself, or with --default, it tests the default
# branch as it is on origin and touches nothing.
#
#   greenlight.sh                   fetch the default branch, merge it into the current branch,
#                                   push; with an open pull request, judge the checks the push
#                                   makes GitHub run on it (its pull_request workflows), else
#                                   dispatch every CI workflow (one that runs on push or
#                                   pull_request and has workflow_dispatch) on that branch
#   greenlight.sh --default         test the default branch itself: fetch only, never merge
#   greenlight.sh ci integration    only those workflows: file name or name:, .yml optional;
#                                   a manual-only workflow runs only when named like this
#   greenlight.sh --latest          merge, push and dispatch nothing; verify the newest completed
#                                   run of each CI workflow on the branch's pushed sha, which
#                                   must already contain the default branch
#   greenlight.sh --match REGEX     what counts as an integration job
#                                   (default integration|e2e|end.to.end|functional|acceptance)
#   greenlight.sh --timeout MIN     how long to wait for the runs (default 45)
#
# Verdict rules, all from one `gh run view` snapshot per run taken after every run completed:
# the run and every job concluded success (skipped, cancelled and neutral fail); the run's sha
# is the sha tested (the pushed merge, or the default branch fetched from origin); at least one job matches the integration pattern and inside it
# no test step was skipped and the log does not report zero tests; every status check the
# default branch requires (branch protection or rulesets) ran and succeeded; every dispatched
# workflow actually started. Exit 0 only on GREENLIGHT PASS. It refuses to merge into a branch
# with uncommitted changes to tracked files. A merge that conflicts is left in progress and the
# script exits 3 with a MERGE CONFLICT block listing the files: resolve, commit, run again.
# Committed conflict markers are refused before pushing. --default never touches the working tree.
#
# Needs git, gh (logged in) and jq. GREENLIGHT_POLL=<seconds> sets the poll interval (default 30).
set -uo pipefail

MATCH='integration|e2e|end.to.end|functional|acceptance'
TIMEOUT_MIN=45
LATEST=0
MODE=branch
WANT=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,28s/^# \{0,1\}//p' "$0"; exit 0 ;;
    --latest) LATEST=1 ;;
    --default) MODE=default ;;
    --match) MATCH="$2"; shift ;;
    --timeout) TIMEOUT_MIN="$2"; shift ;;
    --*) echo "unknown option $1"; exit 2 ;;
    *) WANT+=("$1") ;;
  esac
  shift
done
POLL="${GREENLIGHT_POLL:-30}"
APPEAR_TRIES=12

REASONS=()
reason() { REASONS+=("$1"); }
WHERE=""
verdict() { # prints the verdict block and exits
  echo
  echo "== verdict"
  if [ ${#REASONS[@]} -eq 0 ]; then
    echo "GREENLIGHT PASS  $WHERE  ${RUN_URLS:-}"
    exit 0
  fi
  echo "GREENLIGHT FAIL  ${WHERE:-?}"
  for r in "${REASONS[@]}"; do echo "- $r"; done
  exit 1
}

# ---------- prerequisites ----------
for t in git gh jq; do command -v "$t" >/dev/null 2>&1 || { reason "$t is not installed"; verdict; }; done
git rev-parse --git-dir >/dev/null 2>&1 || { reason "not inside a git repository"; verdict; }
gh auth status >/dev/null 2>&1 || { reason "gh is not logged in (gh auth login)"; verdict; }

REPO_JSON="$(gh repo view --json nameWithOwner,defaultBranchRef 2>&1)" || { reason "gh repo view failed: $REPO_JSON"; verdict; }
REPO="$(printf '%s' "$REPO_JSON" | jq -r .nameWithOwner)"
BRANCH="$(printf '%s' "$REPO_JSON" | jq -r .defaultBranchRef.name)"
[ -n "$BRANCH" ] && [ "$BRANCH" != null ] || { reason "could not read the default branch of $REPO"; verdict; }

# ---------- the default branch, fetched ----------
FETCH_ERR="$(git fetch --quiet origin "$BRANCH" 2>&1)" || { reason "git fetch origin $BRANCH failed: $FETCH_ERR"; verdict; }
DEFAULT_SHA="$(git rev-parse "origin/$BRANCH" 2>/dev/null)" || { reason "origin/$BRANCH is not a ref after fetching"; verdict; }
echo "repo      $REPO"

# ---------- what to test: the current branch with the default branch merged in, or the default branch ----------
CUR="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"
if [ "$MODE" = branch ]; then
  [ -n "$CUR" ] || { reason "not on a branch (detached HEAD): check out the branch to test, or pass --default to test $BRANCH itself"; verdict; }
  [ "$CUR" != "$BRANCH" ] || { MODE=default; echo "note      on $BRANCH itself, so testing origin/$BRANCH as it is"; }
fi
if [ "$MODE" = default ]; then
  TARGET="$BRANCH"; SHA="$DEFAULT_SHA"; TREE="origin/$BRANCH"
  echo "branch    $BRANCH  origin/$BRANCH@${SHA:0:7}  (fetched; the working tree is untouched)"
else
  TARGET="$CUR"
  if [ "$LATEST" = 1 ]; then
    FETCH_ERR="$(git fetch --quiet origin "$CUR" 2>&1)" || { reason "git fetch origin $CUR failed (is it pushed?): $FETCH_ERR"; verdict; }
    SHA="$(git rev-parse "origin/$CUR")"
    git merge-base --is-ancestor "$DEFAULT_SHA" "$SHA" || { reason "origin/$CUR@${SHA:0:7} does not contain origin/$BRANCH@${DEFAULT_SHA:0:7}; run without --latest to merge it in and test"; WHERE="$CUR@${SHA:0:7}"; verdict; }
    echo "branch    $CUR  origin/$CUR@${SHA:0:7}  (contains origin/$BRANCH@${DEFAULT_SHA:0:7}; nothing merged or pushed)"
  else
    [ ! -e "$(git rev-parse --git-path MERGE_HEAD)" ] || { reason "a merge is already in progress on $CUR; resolve the conflicts and commit (or git merge --abort), then run again"; WHERE="$CUR"; verdict; }
    if ! git diff --quiet HEAD -- 2>/dev/null; then
      reason "$CUR has uncommitted changes to tracked files; commit or stash them first, since greenlight merges $BRANCH into $CUR"; verdict
    fi
    if git merge-base --is-ancestor "$DEFAULT_SHA" HEAD; then
      echo "merge     $CUR already contains origin/$BRANCH@${DEFAULT_SHA:0:7}"
    elif MERGE_OUT="$(git merge --no-edit "origin/$BRANCH" 2>&1)"; then
      echo "merge     merged origin/$BRANCH@${DEFAULT_SHA:0:7} into $CUR"
    else
      CONFLICTS="$(git diff --name-only --diff-filter=U 2>/dev/null)"
      if [ -n "$CONFLICTS" ]; then
        # Left in progress on purpose: resolving it is the next step, then running again.
        echo
        echo "== verdict"
        echo "MERGE CONFLICT  merging origin/$BRANCH@${DEFAULT_SHA:0:7} into $CUR"
        printf '%s\n' "$CONFLICTS" | sed 's/^/- conflicted: /'
        echo "- the merge is left in progress: resolve these files, git add them, git commit --no-edit, then run greenlight again (git merge --abort undoes it)"
        exit 3
      fi
      git merge --abort >/dev/null 2>&1
      reason "merging origin/$BRANCH into $CUR failed: $(printf '%s' "$MERGE_OUT" | tail -1)"
      WHERE="$CUR"; verdict
    fi
    SHA="$(git rev-parse HEAD)"
    MARKERS="$(git diff --name-only "$DEFAULT_SHA" HEAD 2>/dev/null | while IFS= read -r f; do
      [ -f "$f" ] && grep -Eq '^(<<<<<<<|>>>>>>>)( |$)|^=======$' "$f" && echo "$f"; done | paste -sd, - | sed 's/,/, /g')"
    [ -z "$MARKERS" ] || { reason "conflict markers were committed in $MARKERS; fix them and commit before running again (nothing was pushed)"; WHERE="$CUR@${SHA:0:7}"; verdict; }
    PUSH_ERR="$(git push --quiet -u origin "$CUR" 2>&1)" || { reason "git push origin $CUR failed (the merge is kept locally): $(printf '%s' "$PUSH_ERR" | tail -1)"; WHERE="$CUR@${SHA:0:7}"; verdict; }
    echo "branch    $CUR@${SHA:0:7}  (pushed; contains origin/$BRANCH@${DEFAULT_SHA:0:7})"
  fi
  TREE="$SHA"
fi
SHORT="${SHA:0:7}"
WHERE="$TARGET@$SHORT"

# ---------- an open pull request decides which tests run ----------
# Pushing the branch makes GitHub run the PR's checks on the pushed commit, so with an open PR
# greenlight dispatches nothing and judges those runs: the workflows the PR triggers.
PR_MODE=0
if [ "$MODE" = branch ] && [ ${#WANT[@]} -eq 0 ]; then
  PR_JSON="$(gh pr view "$TARGET" --json number,url,baseRefName,state 2>/dev/null)" || PR_JSON=""
  if [ -n "$PR_JSON" ] && [ "$(printf '%s' "$PR_JSON" | jq -r .state)" = OPEN ]; then
    PR_MODE=1
    PR_NUM="$(printf '%s' "$PR_JSON" | jq -r .number)"
    echo "pr        #$PR_NUM $(printf '%s' "$PR_JSON" | jq -r .url) (base $(printf '%s' "$PR_JSON" | jq -r .baseRefName)): judging the checks it runs, dispatching nothing"
  fi
fi

# Does a workflow run as CI: on pull_request, or on push to branches (push to tags only, as a
# release workflow does, is not CI). Reads the on: block; prints 1 or 0.
ci_trigger() {
  awk '
    function ind(s) { match(s, /^[ \t]*/); return RLENGTH }
    function endpush() { if (inpush && (!hastags || hasbr)) ci=1; inpush=0 }
    /^on:/ { inon=1; rest=$0; sub(/^on:[ \t]*/, "", rest); if (rest ~ /pull_request|push/) ci=1; next }
    inon && /^[A-Za-z_]/ { endpush(); inon=0 }
    !inon { next }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    inpush && ind($0) <= pushind { endpush() }
    inpush { if ($0 ~ /^[ \t]*tags(-ignore)?[ \t]*:/) hastags=1; if ($0 ~ /^[ \t]*branches(-ignore)?[ \t]*:/) hasbr=1; next }
    /^[ \t]*-[ \t]*(push|pull_request)/ { ci=1 }
    /^[ \t]*pull_request(_target)?[ \t]*:/ { ci=1 }
    /^[ \t]*push[ \t]*:/ { inpush=1; pushind=ind($0); hastags=0; hasbr=0 }
    END { endpush(); print (ci ? 1 : 0) }'
}

# ---------- workflows on that sha ----------
# Does a workflow run on pull_request: reads the on: block; prints 1 or 0.
pr_trigger() {
  awk '/^on:/ { inon=1; if ($0 ~ /pull_request/) pr=1; next }
       inon && /^[A-Za-z_]/ { inon=0 }
       inon && /^[ \t]*(-[ \t]*)?pull_request(_target)?([ \t]*:|[ \t]*$)/ { pr=1 }
       END { print (pr ? 1 : 0) }'
}

WF_FILES=(); WF_NAMES=(); WF_DISPATCH=(); WF_CI=(); WF_PR=()
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in *.yml|*.yaml) ;; *) continue ;; esac
  body="$(git show "$TREE:$path" 2>/dev/null)" || continue
  WF_FILES+=("$(basename "$path")")
  WF_NAMES+=("$(printf '%s\n' "$body" | sed -n 's/^name:[[:space:]]*//p' | head -1 | sed 's/^["'"'"']//; s/["'"'"'][[:space:]]*$//')")
  if printf '%s\n' "$body" | grep -Eq 'workflow_dispatch'; then WF_DISPATCH+=(1); else WF_DISPATCH+=(0); fi
  WF_CI+=("$(printf '%s\n' "$body" | ci_trigger)")
  WF_PR+=("$(printf '%s\n' "$body" | pr_trigger)")
done < <(git ls-tree --name-only "$TREE" .github/workflows/ 2>/dev/null)

[ ${#WF_FILES[@]} -gt 0 ] || { reason "no workflows under .github/workflows on $WHERE"; verdict; }

# which to run / verify
SELECTED=()   # indexes into WF_*
if [ ${#WANT[@]} -gt 0 ]; then
  shopt -s nocasematch
  for w in "${WANT[@]}"; do
    hit=""
    for i in "${!WF_FILES[@]}"; do
      f="${WF_FILES[$i]}"; stem="${f%.*}"
      if [[ "$w" == "$f" || "$w" == "$stem" || ( -n "${WF_NAMES[$i]}" && "$w" == "${WF_NAMES[$i]}" ) ]]; then hit="$i"; break; fi
    done
    [ -n "$hit" ] || { reason "no workflow named \"$w\" on $WHERE (have: ${WF_FILES[*]})"; continue; }
    SELECTED+=("$hit")
  done
  shopt -u nocasematch
  [ ${#REASONS[@]} -eq 0 ] || verdict
else
  for i in "${!WF_FILES[@]}"; do
    if [ "$PR_MODE" = 1 ]; then [ "${WF_PR[$i]}" = 1 ] && SELECTED+=("$i")
    elif [ "$LATEST" = 1 ]; then [ "${WF_CI[$i]}" = 1 ] && SELECTED+=("$i")
    else [ "${WF_CI[$i]}" = 1 ] && [ "${WF_DISPATCH[$i]}" = 1 ] && SELECTED+=("$i"); fi
  done
fi

line="workflows "
for i in "${!WF_FILES[@]}"; do
  f="${WF_FILES[$i]}"; tag="not selected"
  for s in "${SELECTED[@]:-}"; do [ "$s" = "$i" ] && tag="$({ [ "$LATEST" = 1 ] || [ "$PR_MODE" = 1 ]; } && echo verify || echo dispatch)"; done
  if [ "$tag" = "not selected" ] && [ "$PR_MODE" = 1 ]; then tag="not run by the pull request"
  elif [ "$tag" = "not selected" ]; then
    if [ "${WF_DISPATCH[$i]}" = 1 ] && [ "${WF_CI[$i]}" = 0 ]; then tag="manual-only, not run unless named"
    elif [ "${WF_DISPATCH[$i]}" = 0 ] && [ "$LATEST" = 0 ]; then tag="no workflow_dispatch trigger"
    fi
  fi
  line="$line$f ($tag), "
done
echo "${line%, }"

if [ ${#SELECTED[@]} -eq 0 ]; then
  if [ "$PR_MODE" = 1 ]; then reason "no workflow on $WHERE runs on pull_request, so pull request #$PR_NUM runs no checks"
  elif [ "$LATEST" = 1 ]; then reason "no workflow on $WHERE runs on push or pull_request"
  else reason "no CI workflow on $WHERE has a workflow_dispatch trigger; add \`workflow_dispatch:\` under \`on:\` in the one that runs the tests, or use --latest to verify the newest run instead"; fi
  verdict
fi

# ---------- required status checks ----------
REQUIRED=()
RULES="$(gh api "repos/$REPO/rules/branches/$BRANCH" 2>/dev/null)" || RULES="[]"
PROT="$(gh api "repos/$REPO/branches/$BRANCH/protection/required_status_checks" 2>/dev/null)" || PROT="{}"
while IFS= read -r c; do [ -n "$c" ] && REQUIRED+=("$c"); done < <(
  { printf '%s' "$RULES" | jq -r '.[]? | select(.type=="required_status_checks") | .parameters.required_status_checks[]?.context' 2>/dev/null
    printf '%s' "$PROT" | jq -r '(.contexts[]? // empty), (.checks[]?.context // empty)' 2>/dev/null
  } | awk 'NF && !seen[$0]++')
if [ ${#REQUIRED[@]} -gt 0 ]; then echo "required  $(IFS=,; echo "${REQUIRED[*]}" | sed 's/,/, /g')"
else echo "required  no status checks are required on $BRANCH (no branch protection or ruleset lists any)"; fi

# ---------- find or start a run per workflow ----------
RUN_IDS=(); RUN_WF=()
echo
echo "== runs"
if [ "$PR_MODE" = 1 ]; then
  # Wait for each workflow's pull_request run on the pushed sha; a workflow whose paths or
  # branches filters skip this PR never gets one, and the required checks below catch any
  # that had to run.
  PENDING=("${SELECTED[@]}")
  for ((t=0; t<APPEAR_TRIES && ${#PENDING[@]} > 0; t++)); do
    LEFT=()
    for i in "${PENDING[@]}"; do
      f="${WF_FILES[$i]}"
      id="$(gh run list --workflow "$f" --branch "$TARGET" --event pull_request --json databaseId,headSha,status,conclusion,createdAt --limit 20 2>/dev/null \
        | jq -r --arg sha "$SHA" '[.[] | select(.headSha==$sha)] | sort_by(.createdAt) | last | .databaseId // empty')"
      if [ -n "$id" ]; then RUN_IDS+=("$id"); RUN_WF+=("$f"); echo "$f: pull request #$PR_NUM run $id on $SHORT"
      else LEFT+=("$i"); fi
    done
    PENDING=(${LEFT[@]+"${LEFT[@]}"})
    [ ${#PENDING[@]} -eq 0 ] || sleep "$POLL"
  done
  for i in ${PENDING[@]+"${PENDING[@]}"}; do echo "${WF_FILES[$i]}: no pull request run on $SHORT (its filters may skip this PR)"; done
  [ ${#RUN_IDS[@]} -gt 0 ] || { reason "no checks ran on pull request #$PR_NUM for $WHERE (waited $((APPEAR_TRIES*POLL))s)"; verdict; }
fi
for i in "${SELECTED[@]}"; do
  [ "$PR_MODE" = 0 ] || break
  f="${WF_FILES[$i]}"
  if [ "$LATEST" = 1 ]; then
    id="$(gh run list --workflow "$f" --branch "$TARGET" --json databaseId,headSha,status,conclusion,createdAt --limit 30 2>/dev/null \
      | jq -r --arg sha "$SHA" '[.[] | select(.headSha==$sha and .status=="completed")] | sort_by(.createdAt) | last | .databaseId // empty')"
    if [ -z "$id" ]; then
      named=0; for w in "${WANT[@]:-}"; do [ -n "$w" ] && named=1; done
      if [ "$named" = 1 ]; then reason "$f: no completed run on $WHERE (drop --latest to dispatch one)"; fi
      echo "$f: no completed run on $SHORT$([ "$named" = 1 ] || echo ' (its triggers did not fire for this commit; name it to require one)')"
      continue
    fi
    echo "$f: verifying run $id (newest completed on $SHORT)"
  else
    before="$(gh run list --workflow "$f" --branch "$TARGET" --event workflow_dispatch --json databaseId --limit 20 2>/dev/null | jq -c '[.[].databaseId]')"
    [ -n "$before" ] || before="[]"
    err="$(gh workflow run "$f" --ref "$TARGET" 2>&1 >/dev/null)" || { reason "$f: could not dispatch: $err"; echo "$f: dispatch refused"; continue; }
    id=""
    for ((t=0; t<APPEAR_TRIES; t++)); do
      id="$(gh run list --workflow "$f" --branch "$TARGET" --event workflow_dispatch --json databaseId,createdAt --limit 20 2>/dev/null \
        | jq -r --argjson before "$before" '[.[] | select(.databaseId as $i | $before | index($i) | not)] | sort_by(.createdAt) | last | .databaseId // empty')"
      [ -n "$id" ] && break
      sleep "$POLL"
    done
    if [ -z "$id" ]; then reason "$f: dispatch was accepted but the run never started (waited $((APPEAR_TRIES*POLL))s)"; echo "$f: dispatched, never started"; continue; fi
    echo "$f: dispatched on $TARGET, run $id started"
  fi
  RUN_IDS+=("$id"); RUN_WF+=("$f")
done
if [ ${#RUN_IDS[@]} -eq 0 ]; then
  [ ${#REASONS[@]} -gt 0 ] || reason "no completed run of any CI workflow on $WHERE (drop --latest to dispatch)"
  verdict
fi

# ---------- wait ----------
DEADLINE=$(( $(date +%s) + TIMEOUT_MIN*60 ))
START=$(date +%s)
DONE=(); LAST=()
for i in "${!RUN_IDS[@]}"; do DONE+=(0); LAST+=(""); done
while :; do
  pending=0
  for i in "${!RUN_IDS[@]}"; do
    [ "${DONE[$i]}" = 1 ] && continue
    st="$(gh run view "${RUN_IDS[$i]}" --json status,conclusion 2>/dev/null | jq -r '"\(.status) \(.conclusion // "")"')"
    status="${st%% *}"
    if [ "$status" = completed ]; then
      DONE[$i]=1
      echo "run ${RUN_IDS[$i]} ${RUN_WF[$i]}: completed (${st#* }) after $(( ($(date +%s)-START)/60 ))m$(( ($(date +%s)-START)%60 ))s"
    else
      pending=1
      [ "$status" != "${LAST[$i]}" ] && { echo "run ${RUN_IDS[$i]} ${RUN_WF[$i]}: ${status:-unknown}"; LAST[$i]="$status"; }
    fi
  done
  [ "$pending" = 0 ] && break
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    for i in "${!RUN_IDS[@]}"; do [ "${DONE[$i]}" = 1 ] || reason "run ${RUN_IDS[$i]} (${RUN_WF[$i]}) timed out: still ${LAST[$i]:-not started} after ${TIMEOUT_MIN}m (--timeout to wait longer)"; done
    break
  fi
  sleep "$POLL"
done

# ---------- one snapshot per completed run; everything below reads only these ----------
SNAPS=()
for i in "${!RUN_IDS[@]}"; do
  [ "${DONE[$i]}" = 1 ] || { SNAPS+=(""); continue; }
  snap="$(gh run view "${RUN_IDS[$i]}" --json status,conclusion,url,headSha,workflowName,createdAt,jobs 2>/dev/null)"
  [ -n "$snap" ] && printf '%s' "$snap" | jq -e . >/dev/null 2>&1 || { reason "run ${RUN_IDS[$i]}: could not read its final state from gh"; snap=""; }
  SNAPS+=("$snap")
done

ALL_JOBS="[]"   # [{run, wf, name, conclusion, id, steps, secs}]
RUN_URLS=""
echo
echo "== jobs"
for i in "${!RUN_IDS[@]}"; do
  snap="${SNAPS[$i]}"; [ -n "$snap" ] || continue
  id="${RUN_IDS[$i]}"; f="${RUN_WF[$i]}"
  rstatus="$(printf '%s' "$snap" | jq -r .status)"
  rconc="$(printf '%s' "$snap" | jq -r '.conclusion // ""')"
  rsha="$(printf '%s' "$snap" | jq -r '.headSha // ""')"
  url="$(printf '%s' "$snap" | jq -r '.url // ""')"
  RUN_URLS="${RUN_URLS:+$RUN_URLS }$url"
  echo "run $id $f  $url"
  [ "$rstatus" = completed ] || reason "run $id ($f) is $rstatus, not completed, in the final snapshot"
  [ "$rsha" = "$SHA" ] || reason "run $id ($f) ran ${rsha:0:7}, not the tested $WHERE"
  [ "$rconc" = success ] || reason "run $id ($f) concluded ${rconc:-nothing}, not success"
  jobs="$(printf '%s' "$snap" | jq -c --arg run "$id" --arg wf "$f" '[.jobs[]? | {run:$run, wf:$wf, name, conclusion:(.conclusion // ""), id:(.databaseId|tostring), steps:(.steps // []),
      secs:(if .startedAt and .completedAt then ((.completedAt|fromdateiso8601) - (.startedAt|fromdateiso8601)) else null end)}]')"
  [ "$(printf '%s' "$jobs" | jq length)" -gt 0 ] || reason "run $id ($f) has no jobs"
  ALL_JOBS="$(jq -cn --argjson a "$ALL_JOBS" --argjson b "$jobs" '$a + $b')"
  while IFS=$'\t' read -r name conc secs nsteps jid; do
    mark="✗"; [ "$conc" = success ] && mark="✓"
    tags=""
    if printf '%s' "$name" | grep -Eiq "$MATCH"; then tags="$tags [integration]"; fi
    for c in "${REQUIRED[@]:-}"; do [ -n "$c" ] && [ "$c" = "$name" ] && tags="$tags [required]"; done
    dur=""; [ -n "$secs" ] && [ "$secs" != null ] && dur="$((secs/60))m$((secs%60))s"
    printf '  %s %-32s %-10s %-8s%s\n' "$mark" "$name" "${conc:-?}" "$dur" "$tags"
    if [ "$conc" != success ]; then
      if [ "$nsteps" = 0 ]; then
        why="$(gh api "repos/$REPO/check-runs/$jid/annotations" 2>/dev/null | jq -r '[.[] | select(.annotation_level=="failure" or .annotation_level=="warning") | .message] | first // empty' | head -c 200)"
        reason "job \"$name\" in run $id ($f) concluded ${conc:-nothing} without running a single step: it never started on a runner${why:+ — GitHub says: \"$why\"}"
      else reason "job \"$name\" in run $id ($f) concluded ${conc:-nothing}"; fi
    fi
  done < <(printf '%s' "$jobs" | jq -r '.[] | [.name, .conclusion, (.secs // ""), (.steps|length), .id] | @tsv')
done

# ---------- integration jobs: present, ran, ran something ----------
INTEG="$(printf '%s' "$ALL_JOBS" | jq -c --arg m "$MATCH" '[.[] | select(.name | test($m; "i"))]')"
if [ "$(printf '%s' "$INTEG" | jq length)" = 0 ]; then
  [ "$(printf '%s' "$ALL_JOBS" | jq length)" = 0 ] || reason "no job matched the integration pattern /$MATCH/ in any run (--match to change it)"
else
  while IFS=$'\t' read -r run wf name jid; do
    while IFS=$'\t' read -r sname sconc; do
      reason "step \"$sname\" in job \"$name\" (run $run) was $sconc, so the integration tests did not run"
    done < <(printf '%s' "$INTEG" | jq -r --arg n "$name" --arg r "$run" '.[] | select(.name==$n and .run==$r) | .steps[] | select((.name | test("test"; "i")) and .conclusion != "success") | [.name, .conclusion] | @tsv')
    hit="$(gh run view "$run" --job "$jid" --log 2>/dev/null | grep -Ei -m1 'no tests? found|0 passing|Tests:[[:space:]]+0 total|Ran 0 tests|collected 0 items|\b0 tests? (ran|run|passed|executed)|No test files found' | cut -f3- | head -c 160)"
    [ -z "$hit" ] || reason "job \"$name\" (run $run) log reports zero tests: \"$hit\""
  done < <(printf '%s' "$INTEG" | jq -r '.[] | [.run, .wf, .name, .id] | @tsv')
fi

# ---------- required checks all ran and passed ----------
for c in "${REQUIRED[@]:-}"; do
  [ -n "$c" ] || continue
  conc="$(printf '%s' "$ALL_JOBS" | jq -r --arg c "$c" '[.[] | select(.name==$c)] | if length==0 then "__missing__" else (map(.conclusion) | if all(.=="success") then "success" else (map(select(.!="success")) | first) end) end')"
  case "$conc" in
    __missing__) reason "required check \"$c\" did not run in any of these runs" ;;
    success) ;;
    *) reason "required check \"$c\" concluded ${conc:-nothing}" ;;
  esac
done

verdict
