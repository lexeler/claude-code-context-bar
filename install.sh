#!/usr/bin/env bash
# One-line installer for context-bar (Claude Code status line).
#   curl -fsSL https://raw.githubusercontent.com/lexeler/claude-code-context-bar/main/install.sh | bash
set -euo pipefail

REPO="lexeler/claude-code-context-bar"
RAW="https://raw.githubusercontent.com/${REPO}/main"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/context-bar.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

mkdir -p "$CLAUDE_DIR"

echo "→ downloading context-bar.sh"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$RAW/context-bar.sh" -o "$DEST"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$DEST" "$RAW/context-bar.sh"
else
  echo "error: need curl or wget" >&2; exit 1
fi
chmod +x "$DEST"

# Back up existing settings, then merge the statusLine key (preserving everything else).
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak" || true

if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" "$DEST" <<'PY'
import json, os, sys
path, cmd = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        data = json.load(open(path))
    except Exception:
        os.rename(path, path + ".broken")   # keep the unparsable file aside
        data = {}
if not isinstance(data, dict):
    data = {}
data["statusLine"] = {"type": "command", "command": cmd, "padding": 0}
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
elif command -v jq >/dev/null 2>&1; then
  [ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  tmp="$(mktemp)"
  jq --arg c "$DEST" '.statusLine = {type:"command", command:$c, padding:0}' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
else
  echo
  echo "note: neither python3 nor jq found — add this to $SETTINGS yourself:"
  echo '  "statusLine": { "type": "command", "command": "'"$DEST"'", "padding": 0 }'
fi

echo "✓ installed → $DEST"
echo "✓ restart Claude Code to see the bar"
