#!/usr/bin/env bash
# Install statusline.sh: create symlink and update ~/.claude/settings.json

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_SRC="$REPO_DIR/scripts/statusline.sh"
SYMLINK="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

# --- symlink ---
if [ ! -f "$SCRIPT_SRC" ]; then
    echo "ERROR: $SCRIPT_SRC not found" >&2
    exit 1
fi

mkdir -p "$HOME/.claude"

if [ -L "$SYMLINK" ]; then
    echo "Replacing existing symlink: $SYMLINK"
    rm "$SYMLINK"
elif [ -f "$SYMLINK" ]; then
    echo "Backing up existing file: $SYMLINK -> ${SYMLINK}.bak"
    mv "$SYMLINK" "${SYMLINK}.bak"
fi

ln -s "$SCRIPT_SRC" "$SYMLINK"
echo "Symlink created: $SYMLINK -> $SCRIPT_SRC"

# --- settings.json ---
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

if ! command -v jq &>/dev/null; then
    echo "WARNING: jq not found. Add the following to $SETTINGS manually:"
    cat <<'EOF'
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh",
    "padding": 2,
    "refreshInterval": 1
  }
EOF
    exit 0
fi

if jq -e '.statusLine' "$SETTINGS" &>/dev/null; then
    echo "statusLine already configured in $SETTINGS — skipping"
else
    tmp=$(mktemp)
    jq '. + {"statusLine": {"type": "command", "command": "bash ~/.claude/statusline.sh", "padding": 2, "refreshInterval": 1}}' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
    echo "statusLine added to $SETTINGS"
fi

echo "Done. Restart Claude Code to apply."
