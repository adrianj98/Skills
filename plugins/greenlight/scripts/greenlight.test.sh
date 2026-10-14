#!/usr/bin/env bash
# Tests for greenlight.sh against a fake gh on PATH. Each case builds a git repo with an
# origin, a fixtures dir the fake gh answers from, runs the script, and checks the verdict
# line and exit code.
#
#   bash greenlight.test.sh            run every case
#   bash greenlight.test.sh -v         also print each run's full output
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/greenlight.sh"
VERBOSE="${1:-}"
PASS=0; FAIL=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------- the fake gh ----------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'GH'
#!/usr/bin/env bash
# Answers from $FAKE_GH, a directory of fixtures:
#   repo.json                 gh repo view
#   dispatch                  lines "<workflow file> <run id>": what a dispatch creates
#   before.json               runs that exist before any dispatch (gh run list)
#   runs/<id>.json            gh run view <id> --json ...
#   logs/<job id>.txt         gh run view <id> --job <job id> --log
#   slow                      if present, the first view of each run is still in_progress
#   rules.json                gh api repos/o/r/rules/branches/main (rulesets)
#   protection.json           gh api .../branches/main/protection/required_status_checks (404 if absent)
#   annotations/<job id>.json gh api repos/o/r/check-runs/<job id>/annotations
F="$FAKE_GH"; S="$F/state"; mkdir -p "$S"
echo "gh $*" >> "$S/calls"
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view") cat "$F/repo.json" ;;
  "workflow run")
    wf="$3"
    id="$(awk -v w="$wf" '$1==w{print $2}' "$F/dispatch" 2>/dev/null)"
    if [ -z "$id" ]; then
      echo "could not create workflow dispatch event: HTTP 422: Workflow does not have 'workflow_dispatch' trigger" >&2; exit 1
    fi
    echo "$wf $id" >> "$S/dispatched" ;;
  "run list")
    wf=""; while [ $# -gt 0 ]; do [ "$1" = "--workflow" ] && wf="$2"; shift; done
    # before.json entries carry a "workflow" field; dispatched runs are added after.
    extra="[]"
    if [ -f "$S/dispatched" ]; then
      extra="$(awk -v w="$wf" '$1==w{print $2}' "$S/dispatched" | jq -R 'tonumber' | jq -s --arg w "$wf" --slurpfile all <(for f in "$F"/runs/*.json; do jq --arg id "$(basename "$f" .json)" --arg w "$wf" '. + {databaseId: ($id|tonumber), workflow: $w}' "$f" 2>/dev/null; done | jq -s .) '[.[] as $id | $all[0][] | select(.databaseId==$id)] | map({databaseId, headSha, status, conclusion, createdAt})')"
    fi
    jq -c --arg w "$wf" --argjson extra "$extra" '[.[] | select($w=="" or .workflow==$w) | {databaseId, headSha, status, conclusion, createdAt}] + $extra' "$F/before.json" ;;
  "run view")
    id="$3"; job=""; log=0; shift 3
    while [ $# -gt 0 ]; do case "$1" in --job) job="$2"; shift ;; --log) log=1 ;; esac; shift; done
    if [ "$log" = 1 ]; then cat "$F/logs/$job.txt" 2>/dev/null; exit 0; fi
    n=0; [ -f "$S/views-$id" ] && n="$(cat "$S/views-$id")"; echo $((n+1)) > "$S/views-$id"
    if [ -f "$F/slow" ] && [ "$n" = 0 ]; then
      jq -c '. + {status: "in_progress", conclusion: ""}' "$F/runs/$id.json"
    else
      jq -c . "$F/runs/$id.json"
    fi ;;
  "api repos/o/r/check-runs/"*"/annotations") j="${2#repos/o/r/check-runs/}"; j="${j%/annotations}"; [ -f "$F/annotations/$j.json" ] && cat "$F/annotations/$j.json" || echo '[]' ;;
  "api repos/o/r/rules/branches/main") [ -f "$F/rules.json" ] && cat "$F/rules.json" || echo '[]' ;;
  "api repos/o/r/branches/main/protection/required_status_checks") [ -f "$F/protection.json" ] && cat "$F/protection.json" || { echo '{"message":"Branch not protected"}' >&2; exit 1; } ;;
  *) echo "fake gh: unhandled: $*" >&2; exit 2 ;;
esac
GH
chmod +x "$TMP/bin/gh"

# ---------- a repo with an origin ----------
make_repo() { # $1 = case dir; writes workflows from $2 (a dir) into the origin's main
  local d="$1" wf="$2"
  rm -rf "$d/origin.git" "$d/work" "$d/seed"
  git init --quiet --bare -b main "$d/origin.git"
  git init --quiet -b main "$d/seed"
  mkdir -p "$d/seed/.github/workflows"; cp "$wf"/* "$d/seed/.github/workflows/"
  git -C "$d/seed" -c user.name=t -c user.email=t@t add -A
  git -C "$d/seed" -c user.name=t -c user.email=t@t commit --quiet -m seed
  git -C "$d/seed" push --quiet "$d/origin.git" main
  git clone --quiet "$d/origin.git" "$d/work"
  # a dirty, diverged checkout: the script must not care
  git -C "$d/work" checkout --quiet -b feature
  echo dirty > "$d/work/dirty.txt"
  git -C "$d/seed" rev-parse HEAD
}
SHA_OF() { git -C "$1/seed" rev-parse HEAD; }

run_case() { # name, fixtures dir, expected exit, expected verdict regex, [args...]
  local name="$1" fx="$2" want_exit="$3" want="$4"; shift 4
  local out code
  rm -rf "$fx/state"
  out="$(cd "$fx/work" && PATH="$TMP/bin:$PATH" FAKE_GH="$fx" GREENLIGHT_POLL=0 bash "$SCRIPT" "$@" 2>&1)"; code=$?
  [ "$VERBOSE" = "-v" ] && { echo "----- $name"; echo "$out"; echo "----- exit $code"; }
  local verdict; verdict="$(echo "$out" | sed -n '/^== verdict/,$p' | tail -n +2)"
  if [ "$code" = "$want_exit" ] && echo "$verdict" | grep -Eq "$want"; then
    echo "ok   $name"; PASS=$((PASS+1))
  else
    echo "FAIL $name: exit $code (wanted $want_exit), verdict:"; echo "$verdict" | sed 's/^/     /'; FAIL=$((FAIL+1))
    [ "$VERBOSE" = "-v" ] || { echo "$out" | sed 's/^/     | /'; }
  fi
}

# ---------- fixtures ----------
WF="$TMP/wf"; mkdir -p "$WF"
cat > "$WF/ci.yml" <<'Y'
name: CI
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
jobs:
  unit: {runs-on: ubuntu-latest}
Y
cat > "$WF/release.yml" <<'Y'
name: Release
on:
  workflow_dispatch:
jobs:
  publish: {runs-on: ubuntu-latest}
Y
cat > "$WF/tagrelease.yml" <<'Y'
name: Tag release
on:
  push:
    tags: ['v*']
  workflow_dispatch:
    inputs:
      version: {required: true, type: string}
jobs:
  publish: {runs-on: ubuntu-latest}
Y
cat > "$WF/docs.yml" <<'Y'
name: Docs
on:
  push:
    branches: [main]
    paths: ['docs/**']
jobs:
  build: {runs-on: ubuntu-latest}
Y

fixture() { # $1 name, $2 sha, $3 (good|...) → prints dir
  local d="$TMP/$1"; mkdir -p "$d/runs" "$d/logs"
  echo '{"nameWithOwner":"o/r","defaultBranchRef":{"name":"main"}}' > "$d/repo.json"
  echo "ci.yml 100" > "$d/dispatch"
  echo '[]' > "$d/before.json"
  echo "$d"
}
run_json() { # sha, run conclusion, jobs json
  jq -n --arg sha "$1" --arg c "$2" --argjson jobs "$3" '{status:"completed", conclusion:$c, url:"https://github.com/o/r/actions/runs/100", headSha:$sha, workflowName:"CI", createdAt:"2026-10-14T10:00:00Z", jobs:$jobs}'
}
JOBS_GOOD='[
 {"databaseId":1,"name":"lint","status":"completed","conclusion":"success","startedAt":"2026-10-14T10:00:00Z","completedAt":"2026-10-14T10:01:02Z","url":"https://github.com/o/r/actions/runs/100/job/1","steps":[{"name":"Set up job","status":"completed","conclusion":"success","number":1},{"name":"Run lint","status":"completed","conclusion":"success","number":2}]},
 {"databaseId":2,"name":"unit tests","status":"completed","conclusion":"success","startedAt":"2026-10-14T10:00:00Z","completedAt":"2026-10-14T10:03:10Z","url":"https://github.com/o/r/actions/runs/100/job/2","steps":[{"name":"Run unit tests","status":"completed","conclusion":"success","number":1}]},
 {"databaseId":3,"name":"integration tests","status":"completed","conclusion":"success","startedAt":"2026-10-14T10:00:00Z","completedAt":"2026-10-14T10:08:44Z","url":"https://github.com/o/r/actions/runs/100/job/3","steps":[{"name":"Start services","status":"completed","conclusion":"success","number":1},{"name":"Run integration tests","status":"completed","conclusion":"success","number":2}]}
]'
LOG_GOOD=$'integration tests\tRun integration tests\tTests: 42 passed, 42 total\nintegration tests\tRun integration tests\tDone in 512s'

# 1. everything green
d="$(fixture pass)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$JOBS_GOOD" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"; touch "$d/slow"
run_case "pass" "$d" 0 "^GREENLIGHT PASS  main@${sha:0:7}  https://github.com/o/r/actions/runs/100$"
grep -q "^gh workflow run release.yml" "$d/state/calls" && { echo "FAIL pass: dispatched the manual-only release.yml"; FAIL=$((FAIL+1)); }
grep -q "^gh workflow run tagrelease.yml" "$d/state/calls" && { echo "FAIL pass: dispatched the tag-only tagrelease.yml"; FAIL=$((FAIL+1)); }
grep -q "^gh workflow run docs.yml" "$d/state/calls" && { echo "FAIL pass: dispatched docs.yml, which has no workflow_dispatch"; FAIL=$((FAIL+1)); }
grep -q "^gh workflow run ci.yml --ref main" "$d/state/calls" || { echo "FAIL pass: did not dispatch ci.yml on main"; FAIL=$((FAIL+1)); }
[ -f "$d/work/dirty.txt" ] && [ "$(git -C "$d/work" branch --show-current)" = feature ] || { echo "FAIL pass: touched the working tree"; FAIL=$((FAIL+1)); }

# 2. the run failed
d="$(fixture runfail)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" failure "$(echo "$JOBS_GOOD" | jq '.[1].conclusion="failure"')" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
run_case "run failed" "$d" 1 '^GREENLIGHT FAIL'
run_case "run failed names the job" "$d" 1 'job "unit tests".*failure'

# 3. integration job skipped
d="$(fixture skipped)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$(echo "$JOBS_GOOD" | jq '.[2].conclusion="skipped"')" > "$d/runs/100.json"
run_case "integration job skipped" "$d" 1 'job "integration tests".*skipped'

# 4. no integration job at all
d="$(fixture nointeg)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$(echo "$JOBS_GOOD" | jq '.[0:2]')" > "$d/runs/100.json"
run_case "no integration job" "$d" 1 'no job matched'

# 5. integration step skipped inside a green job
d="$(fixture stepskip)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$(echo "$JOBS_GOOD" | jq '.[2].steps[1].conclusion="skipped"')" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
run_case "integration step skipped" "$d" 1 'step "Run integration tests".*skipped'

# 6. zero tests in the log
d="$(fixture zero)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$JOBS_GOOD" > "$d/runs/100.json"; printf 'integration tests\tRun integration tests\tNo tests found, exiting with code 0\n' > "$d/logs/3.txt"
run_case "zero tests ran" "$d" 1 'zero tests'

# 7. the run was on another sha
d="$(fixture sha)"; sha="$(make_repo "$d" "$WF")"
run_json "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" success "$JOBS_GOOD" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
run_case "sha mismatch" "$d" 1 'deadbee.*not.*'"${sha:0:7}"

# 8. --match picks another name
d="$(fixture match)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$(echo "$JOBS_GOOD" | jq '.[2].name="browser suite"')" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
run_case "--match" "$d" 0 '^GREENLIGHT PASS' --match browser

# 9. nothing dispatchable
d="$(fixture nodispatch)"; WF2="$TMP/wf2"; mkdir -p "$WF2"; sed '/workflow_dispatch/d' "$WF/ci.yml" > "$WF2/ci.yml"; sha="$(make_repo "$d" "$WF2")"
: > "$d/dispatch"
run_case "no workflow_dispatch" "$d" 1 'workflow_dispatch'

# 10. a named manual-only workflow is dispatched when asked
d="$(fixture named)"; sha="$(make_repo "$d" "$WF")"
echo "release.yml 100" > "$d/dispatch"
run_json "$sha" success "$JOBS_GOOD" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
run_case "named workflow" "$d" 0 '^GREENLIGHT PASS' release
grep -q "^gh workflow run ci.yml" "$d/state/calls" && { echo "FAIL named: dispatched ci.yml too"; FAIL=$((FAIL+1)); }

# 11. --latest verifies the existing run on the sha, dispatching nothing
d="$(fixture latest)"; sha="$(make_repo "$d" "$WF")"
: > "$d/dispatch"
jq -n --arg sha "$sha" '[{databaseId:100, workflow:"ci.yml", headSha:$sha, status:"completed", conclusion:"success", createdAt:"2026-10-14T10:00:00Z"}]' > "$d/before.json"
run_json "$sha" success "$JOBS_GOOD" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
run_case "--latest" "$d" 0 '^GREENLIGHT PASS' --latest
grep -q "^gh workflow run" "$d/state/calls" && { echo "FAIL latest: dispatched something"; FAIL=$((FAIL+1)); }
run_case "--latest, a named workflow with no run" "$d" 1 'docs.yml: no completed run' --latest docs

# 12. --latest with no run on the sha
d="$(fixture latestnone)"; sha="$(make_repo "$d" "$WF")"
: > "$d/dispatch"
jq -n '[{databaseId:100, workflow:"ci.yml", headSha:"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef", status:"completed", conclusion:"success", createdAt:"2026-10-14T10:00:00Z"}]' > "$d/before.json"
run_case "--latest, no run on sha" "$d" 1 'no completed run'  --latest

# 13. timeout
d="$(fixture timeout)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$JOBS_GOOD" | jq '.status="in_progress" | .conclusion=""' > "$d/runs/100.json"
run_case "timeout" "$d" 1 'timed out' --timeout 0

# 14. a required check (branch protection) that never ran
d="$(fixture required)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$JOBS_GOOD" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
echo '{"strict":true,"contexts":["unit tests","integration tests","security scan"]}' > "$d/protection.json"
run_case "required check missing" "$d" 1 'required check "security scan"'

# 15. required checks from a ruleset, all present
d="$(fixture ruleset)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$JOBS_GOOD" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"unit tests"},{"context":"integration tests"}]}}]' > "$d/rules.json"
run_case "ruleset checks present" "$d" 0 '^GREENLIGHT PASS'
grep -q 'required  unit tests, integration tests' <(cd "$d/work" && PATH="$TMP/bin:$PATH" FAKE_GH="$d" GREENLIGHT_POLL=0 bash "$SCRIPT" 2>&1) || { echo "FAIL ruleset: required checks not listed"; FAIL=$((FAIL+1)); }

# 16. a required check that ran but failed names both reasons
d="$(fixture requiredfail)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" failure "$(echo "$JOBS_GOOD" | jq '.[1].conclusion="failure"')" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
echo '{"strict":true,"contexts":["unit tests"]}' > "$d/protection.json"
run_case "required check failed" "$d" 1 'required check "unit tests".*failure'

# 17. dispatch accepted but no run ever appears
d="$(fixture neverstarted)"; sha="$(make_repo "$d" "$WF")"
echo "ci.yml 999" > "$d/dispatch"   # 999 has no runs/999.json, and the fake's list omits it
run_case "never started" "$d" 1 'never started' --timeout 0

# 18. the verdict comes from one final snapshot per run, taken after completion
d="$(fixture snapshot)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" success "$JOBS_GOOD" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"; touch "$d/slow"
run_case "snapshot" "$d" 0 '^GREENLIGHT PASS'
# first view: in_progress (poll); second: completed (poll sees it); third: the verifying snapshot
[ "$(cat "$d/state/views-100")" = 3 ] || { echo "FAIL snapshot: expected 3 views, got $(cat "$d/state/views-100")"; FAIL=$((FAIL+1)); }

# 19. a job that failed without a single step never reached a runner
d="$(fixture norunner)"; sha="$(make_repo "$d" "$WF")"
run_json "$sha" failure "$(echo "$JOBS_GOOD" | jq '.[2].conclusion="failure" | .[2].steps=[]')" > "$d/runs/100.json"; printf '%s\n' "$LOG_GOOD" > "$d/logs/3.txt"
mkdir -p "$d/annotations"; echo '[{"annotation_level":"failure","message":"The job was not started because recent account payments have failed or your spending limit needs to be increased."}]' > "$d/annotations/3.json"
run_case "job never reached a runner" "$d" 1 'job "integration tests".*never started on a runner.*GitHub says: "The job was not started because recent account payments'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
