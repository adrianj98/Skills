#!/usr/bin/env bash
# Mechanical first pass for /deslop: every line that *might* be AI slop, with no judgement
# applied. Recall, not precision — roughly a third of what this prints is fine as it stands,
# and the skill that calls it is what decides which third.
#
#   scan.sh                   lines added since this branch left its base, working tree included
#   scan.sh --base REF        measure against REF instead
#   scan.sh --all             every tracked file, every line (whole-repo audit)
#   scan.sh PATH...           every line of these files, changed or not
#
# Only *added* lines are reported in the default scope. Slop you didn't write this branch is
# somebody else's problem, and a diff-scoped report is one a person will actually read.
#
# Tuning:  DESLOP_BASE=REF        default base, when --base isn't passed
#          DESLOP_MAX=n           hits per category before the rest are counted, not listed (12)
#          DESLOP_MAX_TOTAL=n     hits overall before the same happens (150)
set -uo pipefail

# Matched lines carry whatever bytes the file had, and truncating one at 110 characters can
# cut a multibyte character in half. In a UTF-8 locale that makes `cut` and `sort` fail with
# "Illegal byte sequence" and take the report down with them; in C they are just bytes. The
# emoji patterns below are byte sequences either way, so nothing is lost.
export LC_ALL=C

MAX="${DESLOP_MAX:-12}"
MAX_TOTAL="${DESLOP_MAX_TOTAL:-150}"
case "$MAX" in ''|*[!0-9]*) MAX=12 ;; esac
case "$MAX_TOTAL" in ''|*[!0-9]*) MAX_TOTAL=150 ;; esac

BASE="${DESLOP_BASE:-}"; ALL=0; PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --base)   [ -n "${2:-}" ] || { echo "--base needs a ref" >&2; exit 2; }; BASE="$2"; shift ;;
    --base=*) BASE="${1#--base=}" ;;
    --all)    ALL=1 ;;
    -h|--help) sed -n '2,17s/^# \{0,1\}//p' "$0"; exit 0 ;;
    -*)       echo "usage: scan.sh [--base REF] [--all] [PATH...]" >&2; exit 2 ;;
    *)        PATHS+=("$1") ;;
  esac
  shift
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not inside a git repository"; exit 0; }
cd "$(git rev-parse --show-toplevel)" || exit 0

# Paths that are not anyone's writing: lockfiles, builds, vendored trees, generated code,
# binaries. Slop in a lockfile is not slop, and one minified bundle would fill the report.
SKIP='(^|/)(node_modules|vendor|third_party|bower_components|dist|build|out|target|\.next|\.nuxt|\.venv|venv|__pycache__|coverage|htmlcov|\.terraform|Pods|Carthage)/|(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|npm-shrinkwrap\.json|poetry\.lock|Pipfile\.lock|Cargo\.lock|go\.sum|composer\.lock|Gemfile\.lock|uv\.lock|flake\.lock)$|\.(min|bundle|chunk)\.(js|css)$|\.(snap|svg|png|jpe?g|gif|webp|ico|pdf|woff2?|ttf|eot|zip|gz|tgz|bz2|xz|7z|jar|class|so|dylib|dll|exe|bin|wasm|mp4|mov|mp3|wav|parquet|db|sqlite3?)$|(^|/)\.git/|_pb2?(_grpc)?\.pyi?$|\.pb\.go$|\.generated\.|\.g\.dart$|(^|/)generated/'

is_prose() { case "$1" in *.md|*.markdown|*.mdx|*.txt|*.rst|*.adoc) return 0 ;; *) return 1 ;; esac; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/deslop.XXXXXX" 2>/dev/null)" || { echo "could not make a scratch dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT INT TERM
PAIRS="$TMP/pairs"      # file<TAB>line in scope, or file<TAB>* for "all of it"
COUNTS="$TMP/counts"    # file<TAB>how many lines of it are in scope
FILES="$TMP/files"      # one path per line
: > "$PAIRS"; : > "$COUNTS"; : > "$FILES"

# ---------- what is in scope ----------
# Three modes, one shape of answer: a list of files, and the set of lines in them that this
# scan is allowed to report. --all and explicit paths put every line in scope; the default
# scope is the added side of a diff, so `git blame`-worthy lines nobody touched stay out.
whole_files() { # paths on stdin — every line of each file goes in scope
  local list="$TMP/wf"
  grep -vE "$SKIP" > "$list"
  [ -s "$list" ] || return 0
  # Batched on purpose. One `grep -Iq` and one `wc -l` per file is two processes per file,
  # which on a whole-repo scan of a few thousand files costs more than every pattern in this
  # script put together — measured at 22s for 1200 files, against 3s for the same run here.
  # `grep -Il .` names the files that are text, in one pass, and skips the ones that vanished.
  tr '\n' '\0' < "$list" | xargs -0 grep -Il . 2>/dev/null > "$list.text"
  [ -s "$list.text" ] || return 0
  cat "$list.text" >> "$FILES"
  sed 's/$/\t*/' "$list.text" >> "$PAIRS"
  # `wc -l` over many files prints "<count> <path>", plus a "total" line per xargs batch.
  tr '\n' '\0' < "$list.text" | xargs -0 wc -l 2>/dev/null |
    awk '{ n = $1; $1 = ""; sub(/^[[:space:]]+/, ""); if ($0 != "total" && $0 != "") printf "%s\t%d\n", $0, n }' >> "$COUNTS"
}

SCOPE=""; HINT=""
if [ ${#PATHS[@]} -gt 0 ]; then
  # A directory expands to the tracked files under it; a file is taken as given.
  EXPANDED=()
  for p in "${PATHS[@]}"; do
    if [ -d "$p" ]; then
      while IFS= read -r f; do [ -n "$f" ] && EXPANDED+=("$f"); done <<EOF
$(git ls-files -- "$p")
EOF
    else
      EXPANDED+=("$p")
    fi
  done
  [ ${#EXPANDED[@]} -gt 0 ] && printf '%s\n' "${EXPANDED[@]}" | whole_files
  SCOPE="every line of: ${PATHS[*]}"
elif [ "$ALL" = 1 ]; then
  git ls-files | whole_files
  SCOPE="every line of every tracked file"
else
  # Default base: what this branch added. `git diff BASE` (two dots, no HEAD) covers the
  # commits *and* the working tree in one pass, so uncommitted work is never invisible.
  if [ -z "$BASE" ]; then
    for CAND in "$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" \
                "$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" \
                origin/main origin/master main master; do
      [ -n "$CAND" ] || continue
      git rev-parse --verify --quiet "$CAND^{commit}" >/dev/null 2>&1 || continue
      M="$(git merge-base "$CAND" HEAD 2>/dev/null)" || continue
      [ -n "$M" ] || continue
      BASE="$M"; BASE_NAME="$CAND"; break
    done
  fi
  # No base at all (no remote, no main, first commit): the working tree against HEAD is the
  # honest answer, and on a branch that never diverged it is the same answer anyway.
  if [ -z "$BASE" ]; then BASE="HEAD"; BASE_NAME="HEAD"; fi
  SHORT="$(git rev-parse --short "$BASE" 2>/dev/null || echo "$BASE")"
  SCOPE="lines added since ${BASE_NAME:-$BASE} ($SHORT), working tree included"

  # -U0 leaves only hunk headers and changed lines, so every '+' line is an added one. The
  # new-file line number comes from the hunk header and advances on added lines alone.
  git -c core.quotepath=false diff -U0 --no-color --no-ext-diff --diff-filter=ACMR "$BASE" -- . 2>/dev/null |
    awk '
      /^\+\+\+ \/dev\/null/ { f = ""; next }
      /^\+\+\+ /            { f = substr($0, 7); next }
      /^@@/                 { if (match($0, /\+[0-9]+/)) ln = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
      /^\+/                 { if (f != "") { printf "%s\t%d\n", f, ln; ln++ } }
    ' > "$PAIRS"

  cut -f1 "$PAIRS" | sort -u | grep -vE "$SKIP" |
    tr '\n' '\0' | xargs -0 grep -Il . 2>/dev/null > "$FILES"

  # A file that was never `git add`ed is not in any diff, and a brand-new file is exactly
  # what an assistant leaves behind — so every line of one counts as added. Ignored files
  # stay ignored (--exclude-standard); this is not a licence to scan build output.
  git ls-files --others --exclude-standard | whole_files

  awk -F'\t' '{ c[$1]++ } END { for (f in c) printf "%s\t%d\n", f, c[f] }' "$PAIRS" >> "$COUNTS"

  if [ ! -s "$FILES" ]; then
    HINT="nothing added in this scope — try \`--base HEAD~1\`, \`--base <ref>\`, or \`--all\`"
  fi
fi

sort -u "$FILES" -o "$FILES" 2>/dev/null
N_FILES="$(wc -l < "$FILES" | tr -d ' ')"
N_LINES="$(awk -F'\t' 'NR == FNR { keep[$0] = 1; next } ($1 in keep) { n += $2 } END { print n + 0 }' "$FILES" "$COUNTS")"

echo "deslop scan"
echo "scope     $SCOPE"
echo "files     ${N_FILES:-0} in scope, ${N_LINES:-0} lines under consideration"
[ -n "$HINT" ] && echo "note      $HINT"
echo

if [ "${N_FILES:-0}" = 0 ]; then
  echo "No files to scan."
  exit 0
fi

# ---------- the patterns ----------
# Each line: <category> <TAB> <where> <TAB> <flags> <TAB> <ERE>
#   where  code | prose | test | any   — which files it is run against
#   flags  i for case-insensitive, - for none
# These are deliberately loose. A pattern that fires on a tenth of what it matches still
# beats reading every changed line, and the skill throws out the nine.
PATTERNS="$TMP/patterns"
cat > "$PATTERNS" <<'EOF'
comment-noise	code	-	(^|[[:space:]])(//|#|--|;;)[[:space:]]*(Step [0-9]|Initialize |Increment |Decrement |Loop (through|over)|Iterate |Check if |Now (we|that)|First,|Next,|Then,|Finally,|Helper (function|method)|Utility (function|method)|Main logic|Constants|Imports|Set (the|up the)|Get the|Create (a|an|the) new|Return (the|a)|Define the|Handle the|Process the|Validate the|Update the|Add (a|an|the)|Remove the|Convert the|Extract the)
comment-banner	code	-	(//|#|/\*)[[:space:]]*[-=*_~]{4,}|(//|#)[[:space:]]*(SECTION|CONSTANTS|HELPERS|TYPES|EXPORTS|MAIN|UTILITIES|IMPORTS)[[:space:]]*(=|-)*[[:space:]]*$
docstring-restates	code	-	(@param[[:space:]]+(\{[^}]*\}[[:space:]]*)?[A-Za-z_]+[[:space:]]+-?[[:space:]]*[Tt]he [A-Za-z_ ]+\.?$|:param [a-z_]+:[[:space:]]*[Tt]he [A-Za-z_ ]+\.?$|@returns?[[:space:]]+(\{[^}]*\}[[:space:]]*)?[Tt]he [A-Za-z_ ]+\.?$|"""[[:space:]]*[A-Z][a-z]+s? the [a-z_ ]+\.?[[:space:]]*"""$)
type-escape	code	-	\bas any\b|\bas unknown as\b|@ts-(ignore|nocheck|expect-error)|#[[:space:]]*type:[[:space:]]*ignore|\beslint-disable|//[[:space:]]*nolint|#\[allow\(dead_code|\bunwrap\(\)|\.unwrap_or_default\(\)|\bObject\b[[:space:]]*\]|:[[:space:]]*any\b|\bAny\b\]|\binterface\{\}|@SuppressWarnings|# noqa$|# pylint: disable
swallowed-error	code	-	except([[:space:]]+[A-Za-z_.]+([[:space:]]+as[[:space:]]+[a-z_]+)?)?:[[:space:]]*$|except[[:space:]]*:|catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*\}|catch[[:space:]]*(\([^)]*\))?[[:space:]]*\{[[:space:]]*(console|log|logger)\.[a-zA-Z]+\([^;]*\);?[[:space:]]*\}|if[[:space:]]+err[[:space:]]*!=[[:space:]]*nil[[:space:]]*\{[[:space:]]*return[[:space:]]+nil|rescue[[:space:]]*(=>|$)|\.catch\(\(?\)?[[:space:]]*=>[[:space:]]*(\{[[:space:]]*\}|null|undefined)\)|contextlib\.suppress
defensive-fallback	code	-	\?\?[[:space:]]*(\[\]|\{\}|''|""|0|null|undefined)|\|\|[[:space:]]*(\[\]|\{\})|\bhasattr\(|getattr\([^,]+,[^,]+,[[:space:]]*(None|""|\[\]|\{\})\)|\.get\([^,)]+,[[:space:]]*(\[\]|\{\}|None|0|""))|typeof[[:space:]]+[A-Za-z_.]+[[:space:]]*(!|=)==[[:space:]]*['"]undefined['"]|isinstance\([a-z_]+,[[:space:]]*\(?[a-z]+,|\bassert[[:space:]]+[a-z_]+[[:space:]]+is[[:space:]]+not[[:space:]]+None
placeholder	any	i	\b(TODO|FIXME|XXX|HACK)\b|NotImplementedError|\btodo!\(|unimplemented!\(|panic!\("(not|todo)|for now[,.]|in a real (implementation|app|world|system)|in production[,;] you|would (be|go) here|placeholder (for|value)|dummy (data|value|implementation)|stub(bed)? (out|for|implementation)|should (work|be fine)|hopefully|not implemented yet|coming soon|left as an exercise
naming-inflation	code	-	\b(Enhanced|Improved|Robust|Advanced|Comprehensive|Intelligent|Smart|Ultimate|Unified|Optimized|Modernized|Simplified|Streamlined|Powerful|Flexible|Seamless)[A-Z_]|\b(enhanced|improved|robust|comprehensive|optimized|unified|advanced)_[a-z]|[A-Za-z]V2\b|_v2\b|_new\b|_old\b|_final\b|Impl2?\b|\bhandleTheEvent\b|Wrapper\b
stdlib-reimpl	code	-	(function|const|let|var|def|func|fn|class)[[:space:]]+[A-Za-z_]*(deepClone|deep_clone|deepCopy|deepMerge|isEmpty|is_empty|groupBy|group_by|chunk|chunked|capitalize|titleCase|debounce|throttle|sleep|delay|retry|uuid|randomId|slugify|flatten|unique|dedupe|deduplicate|clamp|range|zip|omit|pick|memoize)\b
log-noise	code	-	console\.(log|debug|info)\(|^[[:space:]]*print\(|println!\(|fmt\.Print|System\.out\.print|logger?\.(debug|info)\([^)]*(starting|finished|done|success|entering|exiting|about to|called with)
emoji	any	-	(🚀|✅|❌|✨|🎉|🔥|💡|⚠️|📝|🎯|🛠|🧪|🔒|⚡|👍|🙌|📦|🔧|💪|🌟|🤖|📊|🎨|🧹|✔️|❗)
test-theater	test	-	expect\(true\)|assert[[:space:]]+True[[:space:]]*$|assertTrue\(True\)|expect\(1\)\.toBe\(1\)|toHaveBeenCalled\(\)|assert_called_once\(\)[[:space:]]*$|\.toBeDefined\(\)|\.toBeTruthy\(\)|assert[[:space:]]+[a-z_]+[[:space:]]+is[[:space:]]+not[[:space:]]+None[[:space:]]*$|@pytest.mark.skip|\.skip\(|xit\(|it\.todo\(
compat-shim	code	i	backwards?[- ]compat|kept for compat|legacy (support|alias|path)|@deprecated|deprecated:|for compatibility|re-?export(ed)? for
prose-vocab	prose	i	\b(delve|tapestry|a testament to|pivotal|crucial|intricate|meticulous|seamless(ly)?|leverag(e|es|ing)|underscores the|showcas(e|es|ing)|foster(s|ing)?|the landscape of|the realm of|boasts|vibrant|elevat(e|es|ing)|unlock(s|ing)? the|streamlin(e|es|ing)|holistic|nestled|harness(es|ing) the|robust|comprehensive|cutting-edge|game-chang(er|ing)|state-of-the-art|in today's|ever-(evolving|changing)|paradigm|myriad|plethora|navigat(e|ing) the)\b
prose-construction	prose	i	not (just|only|merely) [^.]{1,60} but|it'?s not [^.,]{1,40}, it'?s|it'?s important to (note|remember)|it is worth noting|at its core|that said,|in conclusion|let'?s (dive|explore)|dive(s|ing)? into|when it comes to|plays a (vital|key|crucial|significant) role|,[[:space:]]+(ensuring|enabling|allowing|providing|making|helping|empowering)[[:space:]]+[a-z]|whether you'?re|from [a-z ]+ to [a-z ]+, |is more than just
prose-format	prose	-	^[[:space:]]*[-*+][[:space:]]+\*\*[^*]{2,40}\*\*[[:space:]]*[:—-]|^#{1,6}[[:space:]]+(Conclusion|Key Takeaways|Final Thoughts|Overview|Introduction|Summary|Benefits|Key Features|Why (This|It) Matters|Future (Work|Outlook|Directions))[[:space:]]*$
assistant-residue	any	i	great question|i hope this helps|let me know if|as an ai|feel free to|certainly!|absolutely!|here'?s a (breakdown|summary|quick)|i'?ve (created|updated|added|implemented|refactored)|happy to (help|adjust)|\[CITATION NEEDED\]|oaicite|contentReference|turn[0-9]+search|as of my (last )?(knowledge|training)
EOF

# ---------- run them ----------
# One grep per category over the whole file list, then the added-line filter. Cheaper than
# one grep per file, and the `xargs` split keeps the argument list under its limit.
HITS="$TMP/hits"; : > "$HITS"
TOTAL=0

while IFS="$(printf '\t')" read -r CAT WHERE FLAGS PAT; do
  [ -n "${CAT:-}" ] || continue
  # The file subset this category applies to. Tests are code too — a pattern marked `code`
  # still runs over a test file; `test` alone is the one that doesn't run over anything else.
  SUBSET="$TMP/subset"; : > "$SUBSET"
  while IFS= read -r f; do
    case "$WHERE" in
      any)   printf '%s\n' "$f" >> "$SUBSET" ;;
      prose) is_prose "$f" && printf '%s\n' "$f" >> "$SUBSET" ;;
      code)  is_prose "$f" || printf '%s\n' "$f" >> "$SUBSET" ;;
      test)  case "$f" in *[Tt]est*|*[Ss]pec*|*_test.*|*.test.*|*.spec.*) printf '%s\n' "$f" >> "$SUBSET" ;; esac ;;
    esac
  done < "$FILES"
  [ -s "$SUBSET" ] || continue

  GFLAGS="-nHE"; [ "$FLAGS" = i ] && GFLAGS="-nHEi"
  RAW="$TMP/raw"; : > "$RAW"
  # A pattern that is broken on this grep must not take the whole scan down with it.
  tr '\n' '\0' < "$SUBSET" | xargs -0 grep $GFLAGS -- "$PAT" >> "$RAW" 2>/dev/null

  [ -s "$RAW" ] || continue
  # Keep only hits on lines that are in scope, and trim each to something readable.
  awk -F: -v cat="$CAT" -v pairsfile="$PAIRS" -v OFS="" '
    BEGIN {
      while ((getline line < pairsfile) > 0) {
        split(line, p, "\t")
        if (p[2] == "*") whole[p[1]] = 1; else inscope[p[1] "\t" p[2]] = 1
      }
    }
    {
      file = $1; lineno = $2
      if (!(file in whole) && !((file "\t" lineno) in inscope)) next
      text = $0
      sub(/^[^:]*:[^:]*:/, "", text)
      gsub(/^[[:space:]]+/, "", text)
      if (length(text) > 110) text = substr(text, 1, 107) "..."
      printf "%s:%s\t%s\t%s\n", file, lineno, cat, text
    }
  ' "$RAW" >> "$HITS"
done < "$PATTERNS"

# ---------- report ----------
if [ ! -s "$HITS" ]; then
  echo "## candidates"
  echo "none — no pattern matched anything in scope."
  echo
else
  echo "## candidates"
  echo "Each line is a *candidate*, not a finding. Judge it against the file it lives in."
  echo
  CATS="$(cut -f2 "$HITS" | sort | uniq -c | sort -rn)"
  printf '%s\n' "$CATS" | while read -r COUNT CAT; do
    [ -n "$CAT" ] || continue
    # The caps exist so a big scan stays readable, but a silently truncated report is a
    # report that lies. Whatever is cut off is counted and named.
    if [ "$TOTAL" -ge "$MAX_TOTAL" ]; then
      echo "(cut off at $MAX_TOTAL hits — raise DESLOP_MAX_TOTAL, or narrow the scope, to see the rest)"
      echo
      break
    fi
    # Counted after dedupe: two patterns in one category can match the same line, and
    # "... 4 more" has to mean four lines you can't see, not four matches you can.
    LIST="$TMP/cat"
    awk -F'\t' -v c="$CAT" '$2 == c { printf "%s  %s\n", $1, $3 }' "$HITS" |
      sort -u -t: -k1,1 -k2,2n > "$LIST"
    SHOWN="$(wc -l < "$LIST" | tr -d ' ')"
    echo "### $CAT ($SHOWN)"
    head -n "$MAX" "$LIST"
    [ "$SHOWN" -gt "$MAX" ] && echo "    ... $((SHOWN - MAX)) more, same category"
    echo
    TOTAL=$((TOTAL + SHOWN))
  done
fi

# ---------- density ----------
# Not a hit list: a per-file rate. One em dash is a punctuation mark, fourteen in a README is
# a fingerprint, and the same goes for emoji and bolded bullet leads. Rates are only worth
# reading next to the rest of the repo, so the skill compares these against files nobody
# touched rather than against zero.
echo "## density"
# Bounded on purpose: prose files and files something already flagged, capped well above what
# is printed. A three-grep pass over every file in a whole-repo scan costs more than the scan.
DENSITY="$TMP/density"
{
  awk -F'\t' '{ f = $1; sub(/:[0-9]+$/, "", f); print f }' "$HITS" 2>/dev/null
  while IFS= read -r f; do is_prose "$f" && printf '%s\n' "$f"; done < "$FILES"
} | sort -u | head -n 60 > "$DENSITY"

{
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    LINES="$(awk -F'\t' -v f="$f" '$1 == f { n += $2 } END { print n + 0 }' "$COUNTS")"
    [ "${LINES:-0}" -gt 0 ] || continue
    DASH="$(grep -oF -- '—' "$f" 2>/dev/null | wc -l | tr -d ' ')"
    EMOJI="$(grep -oE -- '(🚀|✅|❌|✨|🎉|🔥|💡|📝|🎯|🧪|⚡|👍|🙌|📦|🔧|🌟|🤖|📊|🎨)' "$f" 2>/dev/null | wc -l | tr -d ' ')"
    BOLD="$(grep -cE -- '^[[:space:]]*[-*+][[:space:]]+\*\*[^*]{2,40}\*\*[[:space:]]*[:—-]' "$f" 2>/dev/null | tr -d ' ')"
    [ "${DASH:-0}" = 0 ] && [ "${EMOJI:-0}" = 0 ] && [ "${BOLD:-0}" = 0 ] && continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$f" "${DASH:-0}" "${EMOJI:-0}" "${BOLD:-0}" "$LINES"
  done < "$DENSITY"
} | sort -t"$(printf '\t')" -k2,2nr -k3,3nr | head -n 20 > "$TMP/density.rows"

if [ -s "$TMP/density.rows" ]; then
  { printf 'file\tem-dash\temoji\tbold-bullets\tin-scope-lines\n'; cat "$TMP/density.rows"; } |
    awk -F'\t' '{ printf "%-52s %8s %6s %13s %15s\n", $1, $2, $3, $4, $5 }'
else
  echo "nothing worth a rate — no em dashes, emoji or bolded bullet leads in scope"
fi
echo

# ---------- what the repo can check for itself ----------
# Named, never run. Dead code and duplication need a real tool, and which one is the repo's
# business; running an unknown binary out of a Stop-hook-adjacent script is not this script's.
echo "## tools present"
FOUND=""
for T in knip ts-prune vulture jscpd eslint ruff vale deadcode staticcheck; do
  command -v "$T" >/dev/null 2>&1 && FOUND="$FOUND $T"
done
for T in knip jscpd eslint; do
  [ -f "node_modules/.bin/$T" ] && FOUND="$FOUND node_modules/.bin/$T"
done
if [ -n "$FOUND" ]; then
  echo "on PATH:$FOUND"
  echo "(dead code and duplication are theirs to find, not this scan's)"
else
  echo "none of knip / vulture / jscpd / eslint / ruff / vale found"
fi
exit 0
