#!/usr/bin/env bash
#
# Install adversarial review without the plugin system.
#
#   ./install.sh --global          into ~/.claude/           (every repo)
#   ./install.sh --repo            into ./.claude/           (this repo, committed)
#   ./install.sh --repo --local    into ./.claude/, hook registered in settings.local.json
#   ./install.sh --repo PATH       into PATH/.claude/
#   ./install.sh --uninstall --global | --repo [PATH]
#
#   --no-hook   skip the Stop-hook nudge (agent + skill + workflow only)
#   --dry-run   print what would happen, change nothing
#
# Works from a clone, or standalone:
#   curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- --global
#
set -uo pipefail

RAW="https://raw.githubusercontent.com/adrianj98/Skills/main/plugins/adversarial-review"
SCOPE=""; DEST_ARG=""; UNINSTALL=0; NO_HOOK=0; DRY=0; SETTINGS_FILE="settings.json"

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
say()  { printf '%s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --global)    SCOPE=global ;;
    --repo)      SCOPE=repo; case "${2:-}" in -*|"") ;; *) DEST_ARG="$2"; shift ;; esac ;;
    --local)     SETTINGS_FILE="settings.local.json" ;;
    --uninstall) UNINSTALL=1 ;;
    --no-hook)   NO_HOOK=1 ;;
    --dry-run)   DRY=1 ;;
    -h|--help)   awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    *)           die "unknown option: $1 (try --help)" ;;
  esac
  shift
done
[ -n "$SCOPE" ] || die "pick a scope: --global or --repo [PATH]  (see --help)"

# ---------- destination ----------
if [ "$SCOPE" = global ]; then
  ROOT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  LABEL="globally ($ROOT)"
else
  BASE="${DEST_ARG:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  [ -d "$BASE" ] || die "not a directory: $BASE"
  ROOT="$BASE/.claude"
  LABEL="in $BASE"
fi
HOOKS="$ROOT/hooks"
TOGGLE="$HOOKS/adversary"
# Path token baked into settings.json and the skill. Absolute paths break the moment a
# teammate clones the repo to a different directory, so use the env vars Claude exports.
if [ "$SCOPE" = global ]; then
  REF_ROOT='${CLAUDE_CONFIG_DIR:-$HOME/.claude}'
else
  REF_ROOT='$CLAUDE_PROJECT_DIR/.claude'
fi
REF_TOGGLE="$REF_ROOT/hooks/adversary"
REF_STOPHOOK="$REF_ROOT/hooks/require-adversary.sh"
STOPHOOK="$HOOKS/require-adversary.sh"
SETTINGS="$ROOT/$SETTINGS_FILE"

# ---------- uninstall ----------
if [ "$UNINSTALL" = 1 ]; then
  say "Removing adversarial review $LABEL"
  for f in "$ROOT/agents/adversary.md" "$ROOT/skills/adversary/SKILL.md" \
           "$ROOT/workflows/adversarial-review.js" "$TOGGLE" "$STOPHOOK"; do
    [ -e "$f" ] && { run "rm -f '$f'"; say "  removed ${f#$ROOT/}"; }
  done
  [ -d "$ROOT/skills/adversary" ] && run "rmdir '$ROOT/skills/adversary' 2>/dev/null || true"
  if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
    run "python3 - '$SETTINGS' <<'PY'
import json,sys,pathlib
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text() or '{}')
stop=d.get('hooks',{}).get('Stop',[])
keep=[e for e in stop if 'require-adversary' not in json.dumps(e)]
if keep: d['hooks']['Stop']=keep
else:
    d.get('hooks',{}).pop('Stop',None)
    if not d.get('hooks'): d.pop('hooks',None)
p.write_text(json.dumps(d,indent=2)+chr(10))
PY"
    say "  unregistered the Stop hook from $SETTINGS_FILE"
  fi
  say "Done. Your on/off state files (.git/adversary-review, \$CLAUDE_CONFIG_DIR/adversary-review) were left alone."
  exit 0
fi

# ---------- fetch sources ----------
# BASH_SOURCE is unset when this script is piped into bash, and `set -u` makes a bare
# ${BASH_SOURCE[0]} noisy there. Default it, and fall back to the cwd.
SELF="${BASH_SOURCE[0]:-}"
SRC="$(cd "$(dirname "${SELF:-.}")" 2>/dev/null && pwd || pwd)/plugins/adversarial-review"
TMP=""
if [ ! -f "$SRC/agents/adversary.md" ]; then
  command -v curl >/dev/null 2>&1 || die "no local copy found and curl is unavailable"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  SRC="$TMP"
  say "Downloading from $RAW"
  for rel in agents/adversary.md skills/adversary/SKILL.md workflows/review.js \
             bin/adversary scripts/require-adversary.sh; do
    mkdir -p "$SRC/$(dirname "$rel")"
    curl -fsSL "$RAW/$rel" -o "$SRC/$rel" || die "download failed: $rel"
  done
fi

say "Installing adversarial review $LABEL"
run "mkdir -p '$ROOT/agents' '$ROOT/skills/adversary' '$ROOT/workflows' '$HOOKS'"

run "cp '$SRC/agents/adversary.md' '$ROOT/agents/adversary.md'"
say "  agents/adversary.md              the reviewer"

run "cp '$SRC/workflows/review.js' '$ROOT/workflows/adversarial-review.js'"
say "  workflows/adversarial-review.js  /adversarial-review"

# The skill ships with plugin-relative paths; rewrite them for a direct install.
run "sed -e 's|\${CLAUDE_PLUGIN_ROOT}/bin/adversary|$REF_TOGGLE|g' \
         -e 's|/adversarial-review:adversary|/adversary|g' \
         -e 's|/adversarial-review:review|/adversarial-review|g' \
         '$SRC/skills/adversary/SKILL.md' > '$ROOT/skills/adversary/SKILL.md'"
say "  skills/adversary/SKILL.md        /adversary  (on, off, status, clear, run)"

run "cp '$SRC/bin/adversary' '$TOGGLE' && chmod +x '$TOGGLE'"
say "  hooks/adversary                  the on/off switch"

# ---------- Stop hook ----------
if [ "$NO_HOOK" = 1 ]; then
  say "  (skipped the Stop hook: --no-hook)"
else
  run "sed 's|/adversarial-review:adversary off|/adversary off|g' \
           '$SRC/scripts/require-adversary.sh' > '$STOPHOOK' && chmod +x '$STOPHOOK'"
  say "  hooks/require-adversary.sh       the Stop-hook nudge"

  if command -v python3 >/dev/null 2>&1; then
    run "python3 - '$SETTINGS' '$REF_STOPHOOK' <<'PY'
import json,sys,pathlib
path,hook=sys.argv[1],sys.argv[2]
p=pathlib.Path(path); p.parent.mkdir(parents=True,exist_ok=True)
try: d=json.loads(p.read_text())
except Exception: d={}
stop=d.setdefault('hooks',{}).setdefault('Stop',[])
if 'require-adversary' not in json.dumps(stop):
    stop.append({'matcher':'','hooks':[{'type':'command','command':'bash \\\"%s\\\"' % hook}]})
p.write_text(json.dumps(d,indent=2)+chr(10))
PY"
    printf '  %-32s registered the Stop hook\n' "$SETTINGS_FILE"
  else
    say ""
    say "  python3 not found — add this to $SETTINGS yourself:"
    cat <<JSON
    { "hooks": { "Stop": [ { "matcher": "",
        "hooks": [ { "type": "command", "command": "bash \"$REF_STOPHOOK\"" } ] } ] } }
JSON
  fi
fi

say ""
say "Done. Try it:"
say "  /adversary status                       is it on, and why"
say "  /adversary run                          review the current diff now"
say "  /adversarial-review                     the full workflow, with refutation voting"
say "  bash \"$REF_TOGGLE\" off   silence the nudge in this repo"
[ "$SCOPE" = repo ] && say "" && say "Committed at $ROOT — teammates get it on clone."
exit 0
