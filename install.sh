#!/usr/bin/env bash
#
# Install a plugin from this repo without the plugin system.
#
#   ./install.sh <plugin> --global          into ~/.claude/   (every repo)
#   ./install.sh <plugin> --local           into ./.claude/   (this repo only)
#   ./install.sh <plugin> --local PATH      into PATH/.claude/
#   ./install.sh <plugin> --uninstall --global | --local [PATH]
#   ./install.sh --list                     what's installable
#
# Works from a clone, or standalone over curl:
#   curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh \
#     | bash -s -- adversarial-review --global
#
# What each plugin installs is described by its own plugins/<name>/install.manifest,
# so this script stays generic: it never mentions a specific plugin. Not everything
# installable is a plugin — a manifest can also just seed a file (see the `personal` verb).
set -uo pipefail

# Override to install from a fork or a branch: SKILLS_RAW=https://raw.githubusercontent.com/you/Skills/dev
REPO_RAW="${SKILLS_RAW:-https://raw.githubusercontent.com/adrianj98/Skills/main}"

PLUGIN=""; SCOPE=""; DEST_ARG=""; UNINSTALL=0; NO_HOOK=0; DRY=0; LIST=0
SETTINGS_FILE="settings.json"

usage() {
cat <<'USAGE'
Install a plugin from this repo without the plugin system.

  install.sh <plugin> --global          into ~/.claude/     (every repo, just you)
  install.sh <plugin> --local           into ./.claude/     (this repo, committed)
  install.sh <plugin> --local PATH      into PATH/.claude/
  install.sh <plugin> --uninstall --global | --local [PATH]
  install.sh --list                     list the installable plugins

  --repo         alias for --local
  --plugin NAME  same as the positional <plugin>
  --dir PATH     unambiguous form of `--local PATH`
  --private      register hooks in settings.local.json (gitignored) instead
  --no-hook      skip any hooks the plugin registers (everything else still installs)
  --dry-run      print what would happen, change nothing

Copies the plugin's files into that .claude/ directory, rewrites its plugin-relative
paths to real ones, and merges any hooks into your settings.json rather than
overwriting it. Re-running is idempotent; --uninstall reverses it.

USAGE
printf 'From a clone:  ./install.sh <plugin> --global\nStandalone:    curl -fsSL %s/install.sh | bash -s -- <plugin> --global\n' "$REPO_RAW"
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --global)    SCOPE=global ;;
    # `--local PATH` takes an optional path, but only swallows the next argument when it
    # is a directory that exists — otherwise that argument is the plugin name. `--dir` is
    # the unambiguous form.
    --local|--repo) SCOPE=repo; case "${2:-}" in -*|"") ;; *) [ -d "$2" ] && { DEST_ARG="$2"; shift; } ;; esac ;;
    --dir)       SCOPE=repo; DEST_ARG="${2:-}"; [ -n "$DEST_ARG" ] || die "--dir needs a path"; shift ;;
    --plugin)    PLUGIN="${2:-}"; [ -n "$PLUGIN" ] || die "--plugin needs a name"; shift ;;
    --private|--settings-local) SETTINGS_FILE="settings.local.json" ;;
    --uninstall) UNINSTALL=1 ;;
    --no-hook|--no-hooks) NO_HOOK=1 ;;
    --dry-run)   DRY=1 ;;
    --list|-l)   LIST=1 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          die "unknown option: $1 (try --help)" ;;
    *)           [ -z "$PLUGIN" ] || die "more than one plugin given: $PLUGIN, $1"; PLUGIN="$1" ;;
  esac
  shift
done

# ---------- where the plugin sources come from ----------
# A clone next to this script, if there is one; otherwise curl from GitHub.
# BASH_SOURCE is unset when this script is piped into bash, and `set -u` makes a bare
# ${BASH_SOURCE[0]} noisy there. Default it, and fall back to the cwd.
SELF="${BASH_SOURCE[0]:-}"
HERE="$(cd "$(dirname "${SELF:-.}")" 2>/dev/null && pwd || pwd)"
LOCAL_PLUGINS="$HERE/plugins"
[ -d "$LOCAL_PLUGINS" ] || LOCAL_PLUGINS=""
# One scratch dir for the whole run: downloads land here, and so does the sed script.
# Created up front rather than lazily, so it survives being referenced from a subshell.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fetch()  { command -v curl >/dev/null 2>&1 || die "no local copy found and curl is unavailable"
           curl -fsSL "$1" -o "$2"; }

available() { # one plugin name per line
  if [ -n "$LOCAL_PLUGINS" ]; then
    for d in "$LOCAL_PLUGINS"/*/; do
      [ -f "$d/install.manifest" ] && basename "$d"
    done
  else
    # plugins/index lists everything install.sh can install, which is a superset of the
    # marketplace: some entries (CLAUDE.local.md) are just files, not plugins.
    local i m; i="$TMP/index"
    if [ -f "$i" ] || fetch "$REPO_RAW/plugins/index" "$i" 2>/dev/null; then
      grep '[^[:space:]]' "$i"; return 0
    fi
    m="$TMP/marketplace.json"
    [ -f "$m" ] || fetch "$REPO_RAW/.claude-plugin/marketplace.json" "$m" || return 1
    sed -n 's|.*"source"[[:space:]]*:[[:space:]]*"\./plugins/\([^"]*\)".*|\1|p' "$m"
  fi
}

manifest_field() { # manifest_field <file> <key>  — first `key value...` line
  sed -n "s/^$2[[:space:]]\{1,\}//p" "$1" | head -1
}

if [ "$LIST" = 1 ]; then
  say "Installable:"
  found=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    found=1
    m="$LOCAL_PLUGINS/$p/install.manifest"
    if [ -z "$LOCAL_PLUGINS" ]; then
      m="$TMP/$p.manifest"
      fetch "$REPO_RAW/plugins/$p/install.manifest" "$m" 2>/dev/null || m=""
    fi
    printf '  %-22s %s\n' "$p" "$([ -f "${m:-}" ] && manifest_field "$m" about)"
  done <<EOL
$(available)
EOL
  [ "$found" = 1 ] || die "could not list plugins"
  say ""
  say "  install.sh <plugin> --global      (or --local, for this repo only)"
  exit 0
fi

if [ -z "$PLUGIN" ]; then
  names="$(available)"
  count="$(printf '%s\n' "$names" | grep -c '[^[:space:]]')"
  if [ "$count" = 1 ]; then
    PLUGIN="$(printf '%s\n' "$names" | grep '[^[:space:]]' | head -1)"
  else
    usage >&2
    say "" >&2
    say "available plugins:" >&2
    printf '%s\n' "$names" | sed 's/^/  /' >&2
    die "pick a plugin"
  fi
fi
if [ -z "$SCOPE" ]; then usage >&2; die "pick a scope: --global or --local [PATH]"; fi

# ---------- destination ----------
if [ "$SCOPE" = global ]; then
  BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  ROOT="$BASE"
  LABEL="globally ($ROOT)"
  # Path tokens baked into settings.json and into the installed files. Absolute paths break
  # the moment a teammate clones the repo elsewhere, so use the env vars Claude exports.
  REF_BASE='${CLAUDE_CONFIG_DIR:-$HOME/.claude}'
  REF_ROOT="$REF_BASE"
else
  BASE="${DEST_ARG:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  [ -d "$BASE" ] || die "not a directory: $BASE"
  ROOT="$BASE/.claude"
  LABEL="in $BASE"
  REF_BASE='$CLAUDE_PROJECT_DIR'
  REF_ROOT="$REF_BASE/.claude"
fi
SETTINGS="$ROOT/$SETTINGS_FILE"

# ---------- the plugin's manifest ----------
SRC=""
if [ -n "$LOCAL_PLUGINS" ] && [ -f "$LOCAL_PLUGINS/$PLUGIN/install.manifest" ]; then
  SRC="$LOCAL_PLUGINS/$PLUGIN"
else
  SRC="$TMP/$PLUGIN"
  mkdir -p "$SRC"
  fetch "$REPO_RAW/plugins/$PLUGIN/install.manifest" "$SRC/install.manifest" \
    || die "no such plugin: $PLUGIN (try --list)"
fi
MANIFEST="$SRC/install.manifest"
PLUGIN_NAME="$(manifest_field "$MANIFEST" name)"; PLUGIN_NAME="${PLUGIN_NAME:-$PLUGIN}"

body() { grep -v '^[[:space:]]*#' "$MANIFEST" | grep -v '^[[:space:]]*$'; }
# file/bin/personal <src> <dest> <desc...>  |  hook <Event> <src> <dest> <desc...>
payload() { body | awk '
  function rest(n,  s,i) { s=""; for (i=n;i<=NF;i++) s = s (i>n ? " " : "") $i; return s }
  $1=="file"||$1=="bin"||$1=="personal" { print $1"\t"$2"\t"$3"\t"rest(4) }
  $1=="hook"            { print "hook:"$2"\t"$3"\t"$4"\t"rest(5) }'; }

expand_ref() { local t="${1//@ROOT@/$REF_ROOT}"; printf '%s' "${t//@BASE@/$REF_BASE}"; }

# ---------- uninstall ----------
if [ "$UNINSTALL" = 1 ]; then
  say "Removing $PLUGIN_NAME $LABEL"
  while IFS="$(printf '\t')" read -r kind src dest desc; do
    [ -n "$dest" ] || continue
    # `personal` files are the user's own writing by the time they are installed.
    [ "$kind" = personal ] && continue
    f="$ROOT/$dest"
    [ -e "$f" ] && { run "rm -f '$f'"; say "  removed $dest"; }
    # Prune directories the install created, innermost first, only while empty.
    d="$(dirname "$f")"
    while [ "$d" != "$ROOT" ] && [ "${d#$ROOT/}" != "$d" ]; do
      run "rmdir '$d' 2>/dev/null || true"; d="$(dirname "$d")"
    done
    case "$kind" in hook:*)
      if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
        run "python3 - '$SETTINGS' '${kind#hook:}' '$(basename "$dest")' <<'PY'
import json,sys,pathlib
path,event,ident=sys.argv[1],sys.argv[2],sys.argv[3]
p=pathlib.Path(path); d=json.loads(p.read_text() or '{}')
entries=d.get('hooks',{}).get(event,[])
keep=[e for e in entries if ident not in json.dumps(e)]
if keep: d['hooks'][event]=keep
else:
    d.get('hooks',{}).pop(event,None)
    if not d.get('hooks'): d.pop('hooks',None)
p.write_text(json.dumps(d,indent=2)+chr(10))
PY"
        say "  unregistered the ${kind#hook:} hook from $SETTINGS_FILE"
      fi ;;
    esac
  done <<EOL
$(payload)
EOL
  body | sed -n 's/^note[[:space:]]\{1,\}//p' | while IFS= read -r n; do say "  note: $n"; done
  say "Done."
  exit 0
fi

# ---------- fetch sources ----------
if [ "$SRC" != "$LOCAL_PLUGINS/$PLUGIN" ]; then
  say "Downloading $PLUGIN from $REPO_RAW"
  while IFS="$(printf '\t')" read -r kind src dest desc; do
    [ -n "$src" ] || continue
    mkdir -p "$SRC/$(dirname "$src")"
    fetch "$REPO_RAW/plugins/$PLUGIN/$src" "$SRC/$src" || die "download failed: $src"
  done <<EOL
$(payload)
EOL
fi

# ---------- rewrite rules ----------
# The plugin's files address themselves through ${CLAUDE_PLUGIN_ROOT} and /plugin:skill
# names, neither of which exists in a direct install. The manifest's `rewrite from to`
# lines map them onto real paths and bare skill names; @ROOT@ is the install root.
SEDSCRIPT="$TMP/rewrite.sed"
: > "$SEDSCRIPT"
esc_pat() { printf '%s' "$1" | sed 's/[.[\*^$\/\\]/\\&/g'; }
esc_rep() { printf '%s' "$1" | sed 's/[\/&\\]/\\&/g'; }
while read -r verb from to; do
  [ "$verb" = rewrite ] || continue
  printf 's/%s/%s/g\n' "$(esc_pat "$from")" "$(esc_rep "$(expand_ref "$to")")" >> "$SEDSCRIPT"
done <<EOL
$(body)
EOL

PAD="                                  "   # lines up with the %-32s columns above

# A personal file that lands in a git work tree should not show up in git status. Use
# .git/info/exclude rather than the tracked .gitignore, so nobody else's repo is touched.
exclude_from_git() {
  local dir top rel ex
  dir="$(dirname "$1")"
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  [ -n "$top" ] || return 0
  rel="${1#$top/}"
  git -C "$top" check-ignore -q "$rel" 2>/dev/null && { say "$PAD already git-ignored"; return 0; }
  # --absolute-git-dir, because plain --git-dir answers relative to the repo, not to us.
  ex="$(git -C "$top" rev-parse --absolute-git-dir)/info/exclude"
  run "mkdir -p '$(dirname "$ex")' && printf '%s\n' '$rel' >> '$ex'"
  say "$PAD git-excluded via .git/info/exclude"
}

# ---------- install ----------
say "Installing $PLUGIN_NAME $LABEL"
HOOK_CMDS=""
while IFS="$(printf '\t')" read -r kind src dest desc; do
  [ -n "$dest" ] || continue
  case "$kind" in
    hook:*) [ "$NO_HOOK" = 1 ] && { say "  (skipped $dest: --no-hook)"; continue; } ;;
    personal)
      # Not a config file: it goes next to the repo, it is the user's to edit, and an
      # existing one is never overwritten.
      target="$BASE/$dest"
      if [ -e "$target" ]; then
        printf '  %-32s %s\n' "$dest" "kept the one you already have"
      else
        run "mkdir -p '$(dirname "$target")'"
        run "sed -f '$SEDSCRIPT' '$SRC/$src' > '$target'"
        printf '  %-32s %s\n' "$dest" "$desc"
        exclude_from_git "$target"
      fi
      continue ;;
  esac
  run "mkdir -p '$ROOT/$(dirname "$dest")'"
  run "sed -f '$SEDSCRIPT' '$SRC/$src' > '$ROOT/$dest'"
  case "$kind" in bin|hook:*) run "chmod +x '$ROOT/$dest'" ;; esac
  printf '  %-32s %s\n' "$dest" "$desc"
  case "$kind" in
    hook:*) HOOK_CMDS="$HOOK_CMDS${kind#hook:}	$dest
" ;;
  esac
done <<EOL
$(payload)
EOL

# ---------- register hooks ----------
if [ -n "$HOOK_CMDS" ]; then
  if command -v python3 >/dev/null 2>&1; then
    while IFS="$(printf '\t')" read -r event dest; do
      [ -n "$dest" ] || continue
      run "python3 - '$SETTINGS' '$event' '$REF_ROOT/$dest' '$(basename "$dest")' <<'PY'
import json,sys,pathlib
path,event,hook,ident=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
p=pathlib.Path(path); p.parent.mkdir(parents=True,exist_ok=True)
try: d=json.loads(p.read_text())
except Exception: d={}
entries=d.setdefault('hooks',{}).setdefault(event,[])
if ident not in json.dumps(entries):
    entries.append({'matcher':'','hooks':[{'type':'command','command':'bash \\\"%s\\\"' % hook}]})
p.write_text(json.dumps(d,indent=2)+chr(10))
PY"
      printf '  %-32s registered the %s hook\n' "$SETTINGS_FILE" "$event"
    done <<EOL
$HOOK_CMDS
EOL
  else
    say ""
    say "  python3 not found — add this to $SETTINGS yourself:"
    while IFS="$(printf '\t')" read -r event dest; do
      [ -n "$dest" ] || continue
      cat <<JSON
    { "hooks": { "$event": [ { "matcher": "",
        "hooks": [ { "type": "command", "command": "bash \"$REF_ROOT/$dest\"" } ] } ] } }
JSON
    done <<EOL
$HOOK_CMDS
EOL
  fi
fi

# ---------- tips ----------
say ""
say "Done. Try it:"
body | sed -n 's/^tip[[:space:]]\{1,\}//p' | while IFS= read -r t; do say "  $(expand_ref "$t")"; done
[ "$SCOPE" = repo ] && [ -d "$ROOT" ] && { say ""; say "Committed at $ROOT — teammates get it on clone."; }
exit 0
