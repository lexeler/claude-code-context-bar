#!/usr/bin/env bash
#
# One-line installer for context-bar (Claude Code status line):
#   curl -fsSL https://raw.githubusercontent.com/lexeler/claude-code-context-bar/main/install.sh | bash
#
# Toggle the 5-hour rate-limit tracker at install time:
#   ... | bash                      # context bar + 5h tracker (default)
#   ... | bash -s -- --no-limit     # context bar only
# Tuning env vars are baked into the status line command if set, e.g.:
#   ... | CCTX_WIDTH=24 CCTX_RMARGIN=8 bash
#
# Safe by design:
#   • wrapped in main() and only invoked at EOF — a truncated download does nothing
#   • verifies the download (non-empty, correct shebang, valid Bash syntax) BEFORE installing
#   • timestamped backup of settings.json; atomic write; keeps all your other settings
#   • touches nothing outside your Claude config dir; no sudo; safe to re-run
#
set -euo pipefail

main() {
  local REPO="lexeler/claude-code-context-bar"
  local RAW="https://raw.githubusercontent.com/${REPO}/main"
  local CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local DEST="$CLAUDE_DIR/context-bar.sh"
  local SETTINGS="$CLAUDE_DIR/settings.json"

  # --- options: 5h tracker on/off (default on) ---
  local limit=1 a
  for a in "$@"; do
    case "$a" in
      --no-limit|--no-5h|--context-only) limit=0 ;;
      --limit|--5h|--full)               limit=1 ;;
      -h|--help)
        echo "usage: install.sh [--no-limit]"
        echo "  --no-limit   context bar only (hide the 5-hour rate-limit tracker)"
        return 0 ;;
    esac
  done

  mkdir -p "$CLAUDE_DIR"

  # 1) Download to a temp file and verify before touching anything real.
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/context-bar.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  echo "-> downloading context-bar.sh"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW/context-bar.sh" -o "$tmp"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp" "$RAW/context-bar.sh"
  else
    echo "error: need curl or wget" >&2; exit 1
  fi
  [ -s "$tmp" ] || { echo "error: download was empty" >&2; exit 1; }
  local first; IFS= read -r first < "$tmp" || true
  case "$first" in '#!'*bash*) : ;; *) echo "error: unexpected file downloaded" >&2; exit 1 ;; esac
  bash -n "$tmp" || { echo "error: downloaded script failed syntax check" >&2; exit 1; }

  # 2) Install only the verified script.
  cp "$tmp" "$DEST"; chmod 0755 "$DEST"
  echo "OK installed -> $DEST"

  # Build the status line command, baking in any chosen options as env prefixes.
  local opts=""
  (( limit == 0 ))               && opts+="CCTX_LIMIT=0 "
  [ -n "${CCTX_THEME:-}" ]       && opts+="CCTX_THEME=${CCTX_THEME} "
  [ -n "${CCTX_WIDTH:-}" ]       && opts+="CCTX_WIDTH=${CCTX_WIDTH} "
  [ -n "${CCTX_LIMIT_WIDTH:-}" ] && opts+="CCTX_LIMIT_WIDTH=${CCTX_LIMIT_WIDTH} "
  [ -n "${CCTX_RMARGIN:-}" ]     && opts+="CCTX_RMARGIN=${CCTX_RMARGIN} "
  local CMD="${opts}${DEST}"

  # 3) Merge statusLine into settings.json, preserving everything else.
  if [ -f "$SETTINGS" ]; then
    local bak="$SETTINGS.backup.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS" "$bak"
    echo "OK backed up settings -> $bak"
  fi

  if command -v python3 >/dev/null 2>&1; then
    CMD="$CMD" SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys
path, cmd = os.environ["SETTINGS"], os.environ["CMD"]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        with open(path) as f: data = json.load(f)
    except Exception:
        broken = path + ".broken"
        os.replace(path, broken)
        print("!  settings.json was not valid JSON; moved aside to %s" % broken, file=sys.stderr)
        data = {}
    else:
        if not isinstance(data, dict):
            sys.stderr.write("error: settings.json is valid JSON but not an object; left untouched.\n")
            sys.stderr.write('       add manually: "statusLine": {"type":"command","command":"%s","padding":0}\n' % cmd)
            sys.exit(3)
_old = data.get("statusLine")
if isinstance(_old, dict):
    _oc = str(_old.get("command", ""))
    if _oc and "context-bar.sh" not in _oc:
        print("!  replacing your existing status line: %s" % _oc, file=sys.stderr)
        print("   (Claude Code allows only one; your backup keeps the old one.)", file=sys.stderr)
data["statusLine"] = {"type": "command", "command": cmd, "padding": 0}
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False); f.write("\n")
os.replace(tmp, path)  # atomic
PY
  elif command -v jq >/dev/null 2>&1; then
    [ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    local t; t="$(mktemp)"
    jq --arg c "$CMD" '.statusLine = {type:"command", command:$c, padding:0}' "$SETTINGS" > "$t" && mv "$t" "$SETTINGS"
  else
    echo; echo "note: no python3 or jq found - add this to $SETTINGS yourself:"
    echo '  "statusLine": { "type": "command", "command": "'"$CMD"'", "padding": 0 }'
    return 0
  fi

  echo "OK statusLine set in $SETTINGS (other settings kept)"
  echo "OK 5h rate-limit tracker: $( (( limit )) && echo on || echo off )"
  echo "OK done - restart Claude Code to see the bar"
}

main "$@"
