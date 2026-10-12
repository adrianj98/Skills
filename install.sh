#!/usr/bin/env bash
#
# Install a plugin from this repo without the plugin system.
#
#   ./install.sh <plugin> --global          into ~/.claude/   (every repo)
#   ./install.sh <plugin> --local           into ./.claude/   (this repo only)
#   ./install.sh <plugin> --local PATH      into PATH/.claude/
#   ./install.sh <plugin> --uninstall --global | --local [PATH]
#   ./install.sh all --global               every plugin at once
#   ./install.sh <plugin> --devin           into Devin, through `devin plugins install`
#   ./install.sh <plugin> --skill NAME      only that skill from the plugin's remote repos
#   ./install.sh --list                     what's installable
#   ./install.sh <plugin> --list            the skills a plugin's remote repos offer
#
# Works from a clone, or standalone over curl:
#   curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh \
#     | bash -s -- adversarial-review --global
#
# What each plugin installs is described by its own plugins/<name>/install.manifest,
# so this script stays generic: it never mentions a specific plugin. Not everything
# installable is a plugin — a manifest can also just seed a file (see the `personal` verb),
# or pull skills straight from someone else's GitHub repo (see the `remote` verb), or be a mod,
# a hooks module Claude loads whole from CLAUDE_CODE_PLUGIN_DIRS (see the `mod` verb).
set -uo pipefail

# Override to install from a fork or a branch: SKILLS_RAW=https://raw.githubusercontent.com/you/Skills/dev
REPO_RAW="${SKILLS_RAW:-https://raw.githubusercontent.com/adrianj98/Skills/main}"
# What `--devin` hands to `devin plugins install`: a GitHub owner/repo or a git URL.
DEVIN_SOURCE="${SKILLS_DEVIN_SOURCE:-adrianj98/Skills}"
# Where `remote` lines download repo tarballs from: <this>/<owner>/<repo>/tar.gz/<ref>.
GITHUB_TARBALLS="${SKILLS_GITHUB_TARBALLS:-https://codeload.github.com}"

PLUGIN=""; SCOPE=""; DEST_ARG=""; UNINSTALL=0; NO_HOOK=0; DRY=0; LIST=0; ONLY=""
SETTINGS_FILE="settings.json"

usage() {
cat <<'USAGE'
Install a plugin from this repo without the plugin system.

  install.sh <plugin> --global          into ~/.claude/     (every repo, just you)
  install.sh <plugin> --local           into ./.claude/     (this repo, committed)
  install.sh <plugin> --local PATH      into PATH/.claude/
  install.sh <plugin> --uninstall --global | --local [PATH]
  install.sh all --global               every plugin (also works with --uninstall)
  install.sh <plugin> --devin           into Devin: your personal plugins, which Devin
                                        Cloud sessions and every signed-in machine load
  install.sh <plugin> --skill NAME      only that skill from the plugin's `remote` repos
                                        (repeat it, or comma-separate: --skill a,b)
  install.sh --list                     list the installable plugins
  install.sh <plugin> --list            list the skills its `remote` repos offer

  --repo         alias for --local
  --all          same as the plugin name `all`
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
    --devin)     SCOPE=devin ;;
    # `--local PATH` takes an optional path, but only swallows the next argument when it
    # is a directory that exists — otherwise that argument is the plugin name. `--dir` is
    # the unambiguous form.
    --local|--repo) SCOPE=repo; case "${2:-}" in -*|"") ;; *) [ -d "$2" ] && { DEST_ARG="$2"; shift; } ;; esac ;;
    --dir)       SCOPE=repo; DEST_ARG="${2:-}"; [ -n "$DEST_ARG" ] || die "--dir needs a path"; shift ;;
    --plugin)    PLUGIN="${2:-}"; [ -n "$PLUGIN" ] || die "--plugin needs a name"; shift ;;
    --skill|--skills) [ -n "${2:-}" ] || die "--skill needs a name"; ONLY="$ONLY ${2//,/ }"; shift ;;
    --private|--settings-local) SETTINGS_FILE="settings.local.json" ;;
    --uninstall) UNINSTALL=1 ;;
    --no-hook|--no-hooks) NO_HOOK=1 ;;
    --dry-run)   DRY=1 ;;
    --list|-l)   LIST=1 ;;
    --all)       [ -z "$PLUGIN" ] || die "more than one plugin given: $PLUGIN, all"; PLUGIN=all ;;
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

if [ "$LIST" = 1 ] && { [ -z "$PLUGIN" ] || [ "$PLUGIN" = all ]; }; then
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
if [ -z "$SCOPE" ] && [ "$LIST" = 0 ]; then usage >&2; die "pick a scope: --global, --local [PATH] or --devin"; fi

# ---------- all ----------
# Run this same script once per plugin, with the same flags.
if [ "$PLUGIN" = all ]; then
  [ -z "$ONLY" ] || die "--skill picks from one plugin: install.sh <plugin> --skill NAME"
  if [ -n "$SELF" ] && [ -f "$SELF" ]; then ME="$SELF"
  else ME="$TMP/install.sh"; fetch "$REPO_RAW/install.sh" "$ME" || die "could not download install.sh"; fi
  FLAGS=()
  if [ "$SCOPE" = global ]; then FLAGS+=(--global); elif [ "$SCOPE" = devin ]; then FLAGS+=(--devin); else FLAGS+=(--dir "${DEST_ARG:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"); fi
  [ "$SETTINGS_FILE" = settings.local.json ] && FLAGS+=(--private)
  [ "$UNINSTALL" = 1 ] && FLAGS+=(--uninstall)
  [ "$NO_HOOK" = 1 ] && FLAGS+=(--no-hook)
  [ "$DRY" = 1 ] && FLAGS+=(--dry-run)
  failed=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    SKILLS_RAW="$REPO_RAW" bash "$ME" --plugin "$p" "${FLAGS[@]}" || failed="$failed $p"
    say ""
  done <<EOL
$(available)
EOL
  [ -z "$failed" ] || die "failed:$failed"
  exit 0
fi

# ---------- devin ----------
# Devin reads the plugin's .claude-plugin/plugin.json as it is, so there is nothing to copy
# or rewrite: its own plugin system fetches the plugin from git and records it in your
# personal plugins, which is what a Devin Cloud session loads.
if [ "$SCOPE" = devin ]; then
  command -v devin >/dev/null 2>&1 || die "the devin CLI is not on PATH"
  if [ -n "$LOCAL_PLUGINS" ]; then [ -f "$LOCAL_PLUGINS/$PLUGIN/.claude-plugin/plugin.json" ]
  else fetch "$REPO_RAW/plugins/$PLUGIN/.claude-plugin/plugin.json" "$TMP/plugin.json" 2>/dev/null; fi \
    || { say "Skipping $PLUGIN: not a plugin, so Devin has nothing to install"; exit 0; }
  if [ "$UNINSTALL" = 1 ]; then
    say "Removing $PLUGIN from Devin"
    run "devin plugins remove '$PLUGIN' --yes" || die "devin could not remove $PLUGIN"
  else
    say "Installing $PLUGIN into Devin from $DEVIN_SOURCE"
    # devin exits 0 when the plugin landed on this machine but never reached Devin Cloud.
    run "devin plugins install '$DEVIN_SOURCE#plugins/$PLUGIN' --yes 2>&1 | tee '$TMP/devin.out'" \
      || die "devin could not install $PLUGIN"
    grep -q 'not synced' "$TMP/devin.out" 2>/dev/null \
      && die "$PLUGIN is on this machine only: Devin Cloud did not take it"
  fi
  exit 0
fi

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

# ---------- remote skills ----------
# remote <owner/repo[@ref]> <path> <dest> <desc...> — copy <path> out of that GitHub repo
# into <install root>/<dest>. A <path> ending in /* means every directory under it, each
# landing in <dest>/<its name>. One tarball per repo@ref, so no git and no API limits.
remotes() { body | awk '
  function rest(n,  s,i) { s=""; for (i=n;i<=NF;i++) s = s (i>n ? " " : "") $i; return s }
  $1=="remote" { print $2"\t"$3"\t"$4"\t"rest(5) }'; }

# mod <dest> <desc...> — copy the plugin folder whole into <install root>/<dest> and add that
# path to env.CLAUDE_CODE_PLUGIN_DIRS in ~/.claude/settings.json, which is the one place Claude
# reads it from (never a project's settings): a mod installed --local still registers there,
# by absolute path. The engine's own .claude-plugin/types/ is not copied; it rewrites it.
mods() { body | awk '
  function rest(n,  s,i) { s=""; for (i=n;i<=NF;i++) s = s (i>n ? " " : "") $i; return s }
  $1=="mod" { print $2"\t"rest(3) }'; }
MOD_SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
# What goes into CLAUDE_CODE_PLUGIN_DIRS for a folder: ~ for the home directory, else absolute.
mod_ref() { case "$1" in "$HOME"/*) printf '~%s' "${1#$HOME}" ;; *) printf '%s' "$1" ;; esac; }
# plugin_dirs add|remove <path>: edit the env block, keeping every other entry.
plugin_dirs() {
  command -v python3 >/dev/null 2>&1 || { say "  python3 not found — $1 '$2' in env.CLAUDE_CODE_PLUGIN_DIRS of $MOD_SETTINGS yourself"; return 0; }
  run "python3 - '$MOD_SETTINGS' '$1' '$2' <<'PY'
import json,sys,pathlib,os
path,op,entry=sys.argv[1],sys.argv[2],sys.argv[3]
p=pathlib.Path(path); p.parent.mkdir(parents=True,exist_ok=True)
try: d=json.loads(p.read_text())
except Exception: d={}
env=d.setdefault('env',{})
dirs=[x for x in env.get('CLAUDE_CODE_PLUGIN_DIRS','').split(os.pathsep) if x]
if op=='add' and entry not in dirs: dirs.append(entry)
if op=='remove': dirs=[x for x in dirs if x!=entry]
if dirs: env['CLAUDE_CODE_PLUGIN_DIRS']=os.pathsep.join(dirs)
else: env.pop('CLAUDE_CODE_PLUGIN_DIRS',None)
if not env: d.pop('env',None)
p.write_text(json.dumps(d,indent=2)+chr(10))
PY"
}

# The unpacked repo's directory on stdout. Without @ref it is the default branch.
fetch_repo() {
  local repo="${1%@*}" ref="HEAD" dir
  case "$1" in *@*) ref="${1##*@}" ;; esac
  dir="$TMP/remote/${repo//\//_}@$ref"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    command -v curl >/dev/null 2>&1 || { printf 'error: curl is needed for %s\n' "$1" >&2; return 1; }
    curl -fsSL "$GITHUB_TARBALLS/$repo/tar.gz/$ref" | tar xzf - -C "$dir" --strip-components=1 \
      || { printf 'error: could not download %s\n' "$1" >&2; rm -rf "$dir"; return 1; }
  fi
  printf '%s' "$dir"
}

# One `name<TAB>from<TAB>dest` line per thing a remote line covers, narrowed by --skill.
expand_remote() { # expand_remote <repo dir> <path> <dest>
  local d n
  case "$2" in
    */\*) for d in "$1/${2%/\*}"/*/; do
             [ -d "$d" ] || continue
             n="$(basename "$d")"; wanted "$n" && printf '%s\t%s\t%s\n' "$n" "${d%/}" "${3%/}/$n"
           done ;;
    *)     [ -e "$1/$2" ] || { printf 'error: %s is not in the repo\n' "$2" >&2; return 1; }
           n="$(basename "$2")"; wanted "$n" && printf '%s\t%s\t%s\n' "$n" "$1/$2" "$3" ;;
  esac
  return 0
}
wanted() { [ -z "$ONLY" ] && return 0; case " $ONLY " in *" $1 "*) return 0 ;; esac; return 1; }

# What remote installs put where, so --uninstall removes exactly that, even after the
# upstream repo has added or dropped skills.
RECEIPT="$ROOT/.install-receipts/$PLUGIN"

if [ "$LIST" = 1 ]; then
  [ -n "$(remotes)" ] || die "$PLUGIN has no remote skills to pick from; it installs as a whole"
  say "Skills in $PLUGIN_NAME (install.sh $PLUGIN --skill NAME --global):"
  while IFS="$(printf '\t')" read -r spec path dest desc; do
    dir="$(fetch_repo "$spec")" || exit 1
    expand_remote "$dir" "$path" "$dest" | while IFS="$(printf '\t')" read -r n from to; do
      about="$(sed -n 's/^description:[[:space:]]*"\{0,1\}//p' "$from/SKILL.md" 2>/dev/null | head -1 | cut -c1-70)"
      printf '  %-32s %s\n' "$n" "$about"
    done
  done <<EOL
$(remotes)
EOL
  exit 0
fi

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
  while IFS="$(printf '\t')" read -r dest desc; do
    [ -n "$dest" ] || continue
    [ -d "$ROOT/$dest" ] && { run "rm -rf '$ROOT/$dest'"; say "  removed $dest"; }
    plugin_dirs remove "$(mod_ref "$ROOT/$dest")"
    say "  unregistered $dest from CLAUDE_CODE_PLUGIN_DIRS in $MOD_SETTINGS"
  done <<EOL
$(mods)
EOL
  if [ -n "$(remotes)" ]; then
    if [ -f "$RECEIPT" ]; then
      keep=""
      while IFS= read -r dest; do
        [ -n "$dest" ] || continue
        if ! wanted "$(basename "$dest")"; then keep="$keep$dest
"; continue; fi
        # Receipt lines are relative to ROOT; refuse anything that would climb out of it.
        case "/$dest/" in */../*) say "  skipped $dest: not inside $ROOT"; continue ;; esac
        [ -e "$ROOT/$dest" ] && { run "rm -rf '$ROOT/$dest'"; say "  removed $dest"; }
        d="$(dirname "$ROOT/$dest")"
        while [ "$d" != "$ROOT" ] && [ "${d#$ROOT/}" != "$d" ]; do
          run "rmdir '$d' 2>/dev/null || true"; d="$(dirname "$d")"
        done
      done < "$RECEIPT"
      if [ -n "$keep" ]; then run "printf '%s' '$keep' > '$RECEIPT'"
      else run "rm -f '$RECEIPT'"; run "rmdir '$(dirname "$RECEIPT")' 2>/dev/null || true"; fi
    else
      say "  no record of remote skills from $PLUGIN $LABEL — nothing else to remove"
    fi
  fi
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

# A mod without a clone: the whole plugin folder comes out of this repo's tarball, the
# owner/repo and ref read off REPO_RAW (https://raw.githubusercontent.com/<owner>/<repo>/<ref>).
if [ "$SRC" != "$LOCAL_PLUGINS/$PLUGIN" ] && [ -n "$(mods)" ]; then
  spec="$(printf '%s' "$REPO_RAW" | sed -n 's|^https://raw.githubusercontent.com/\([^/]*/[^/]*\)/\(.*\)$|\1@\2|p')"
  [ -n "$spec" ] || die "cannot fetch a mod from $REPO_RAW: expected https://raw.githubusercontent.com/<owner>/<repo>/<ref>"
  dir="$(fetch_repo "$spec")" || die "could not download $spec"
  [ -d "$dir/plugins/$PLUGIN" ] || die "no plugins/$PLUGIN in $spec"
  rm -rf "$SRC"; cp -R "$dir/plugins/$PLUGIN" "$SRC"
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

# Copy a remote directory (or file) into place, replacing what an earlier install left, and
# put its text files through the same rewrite rules as everything else.
copy_remote() { # copy_remote <from> <dest under ROOT>
  local to="$ROOT/$2" f
  rm -rf "$to"; mkdir -p "$(dirname "$to")"; cp -R "$1" "$to"
  find "$to" -type f | while IFS= read -r f; do
    grep -Iq . "$f" 2>/dev/null || continue           # binary or empty: copy as is
    sed -f "$SEDSCRIPT" "$f" > "$TMP/rewritten" && cat "$TMP/rewritten" > "$f"   # keeps the mode
  done
}
got=""
while IFS="$(printf '\t')" read -r spec path dest desc; do
  [ -n "$dest" ] || continue
  dir="$(fetch_repo "$spec")" || die "could not download $spec"
  lines="$(expand_remote "$dir" "$path" "$dest")" || die "bad remote line: $spec $path"
  while IFS="$(printf '\t')" read -r n from to; do
    [ -n "$to" ] || continue
    case "/$to/" in */../*) die "remote dest climbs out of $ROOT: $to" ;; esac
    run "copy_remote '$from' '$to'"
    printf '  %-32s %s\n' "$to" "${desc:-from $spec}"
    got="$got $n"
    run "mkdir -p '$(dirname "$RECEIPT")' && touch '$RECEIPT' && { grep -qxF '$to' '$RECEIPT' || printf '%s\n' '$to' >> '$RECEIPT'; }"
  done <<EOL2
$lines
EOL2
done <<EOL
$(remotes)
EOL
for n in $ONLY; do
  case " $got " in *" $n "*) ;; *) [ -n "$(remotes)" ] && die "no skill named $n in $PLUGIN (try: install.sh $PLUGIN --list)" ;; esac
done

# ---------- mods ----------
while IFS="$(printf '\t')" read -r dest desc; do
  [ -n "$dest" ] || continue
  case "/$dest/" in */../*) die "mod dest climbs out of $ROOT: $dest" ;; esac
  to="$ROOT/$dest"
  run "rm -rf '$to' && mkdir -p '$(dirname "$to")' && cp -R '$SRC' '$to' && rm -rf '$to/install.manifest' '$to/.claude-plugin/types'"
  printf '  %-32s %s\n' "$dest" "$desc"
  plugin_dirs add "$(mod_ref "$to")"
  printf '  %-32s registered in CLAUDE_CODE_PLUGIN_DIRS\n' "$(basename "$MOD_SETTINGS")"
  say "$PAD loads when a session starts (or /reload-plugins)"
done <<EOL
$(mods)
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
