#!/usr/bin/env bash
# Configure the native Codex TUI status line in ~/.codex/config.toml.

set -euo pipefail

CODEX_DIR="${HOME}/.codex"
CONFIG_FILE="${CODEX_DIR}/config.toml"

mkdir -p "$CODEX_DIR"
[ -f "$CONFIG_FILE" ] || : > "$CONFIG_FILE"

tmp=$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")
trap 'rm -f "$tmp"' EXIT

awk '
function print_status_line() {
    print "status_line = ["
    print "  \"context-used\","
    print "  \"used-tokens\","
    print "  \"five-hour-limit\","
    print "  \"weekly-limit\","
    print "]"
}

BEGIN {
    in_tui = 0
    tui_seen = 0
    status_written = 0
    skipping_status_line = 0
}

skipping_status_line {
    if ($0 ~ /]/) {
        skipping_status_line = 0
    }
    next
}

/^[[:space:]]*\[tui][[:space:]]*(#.*)?$/ {
    in_tui = 1
    tui_seen = 1
    print
    next
}

in_tui && /^[[:space:]]*\[/ {
    if (!status_written) {
        print_status_line()
        status_written = 1
    }
    in_tui = 0
    print
    next
}

in_tui && /^[[:space:]]*status_line[[:space:]]*=/ {
    value = $0
    sub(/^[^=]*=/, "", value)
    print_status_line()
    status_written = 1
    if (value !~ /]/) {
        skipping_status_line = 1
    }
    next
}

{ print }

END {
    if (in_tui && !status_written) {
        print_status_line()
    } else if (!tui_seen) {
        if (NR > 0) {
            print ""
        }
        print "[tui]"
        print_status_line()
    }
}
' "$CONFIG_FILE" > "$tmp"

if cmp -s "$CONFIG_FILE" "$tmp"; then
    echo "Codex status line already configured in $CONFIG_FILE"
else
    if [ -L "$CONFIG_FILE" ]; then
        cp "$tmp" "$CONFIG_FILE"
    else
        mv "$tmp" "$CONFIG_FILE"
    fi
    echo "Codex status line configured in $CONFIG_FILE"
fi

echo "Done. Restart Codex to apply."
