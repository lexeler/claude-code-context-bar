#!/usr/bin/env bash
# Remove context-bar and its status line entry.
set -euo pipefail
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/context-bar.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

rm -f "$DEST" && echo "✓ removed $DEST"

if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
  cp "$SETTINGS" "$SETTINGS.bak"
  python3 - "$SETTINGS" <<'PY'
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    data.pop("statusLine", None)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
PY
  echo "✓ removed statusLine from settings.json"
fi
echo "✓ restart Claude Code"
