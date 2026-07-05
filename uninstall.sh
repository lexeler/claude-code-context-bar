#!/usr/bin/env bash
#
# Remove context-bar. Safe: only strips the statusLine if it is context-bar's,
# backs up settings.json first, and never deletes anything else.
#
set -euo pipefail

main() {
  local CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  local DEST="$CLAUDE_DIR/context-bar.sh"
  local SETTINGS="$CLAUDE_DIR/settings.json"

  if [ -f "$DEST" ]; then rm -f "$DEST"; echo "OK removed $DEST"; else echo "-  $DEST not found"; fi

  if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
    cp "$SETTINGS" "$SETTINGS.backup.$(date +%Y%m%d%H%M%S)"
    SETTINGS="$SETTINGS" python3 - <<'PY'
import json, os, sys
path = os.environ["SETTINGS"]
try:
    with open(path) as f: data = json.load(f)
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    sl = data.get("statusLine")
    if isinstance(sl, dict) and "context-bar.sh" in str(sl.get("command", "")):
        data.pop("statusLine", None)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False); f.write("\n")
        os.replace(tmp, path)
        print("OK removed context-bar statusLine from settings.json")
    else:
        print("-  statusLine isn't context-bar's - left untouched")
PY
  fi
  echo "OK restart Claude Code"
}

main "$@"
