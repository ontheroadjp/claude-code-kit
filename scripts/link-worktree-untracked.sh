#!/usr/bin/env bash
# Symlink every untracked/ignored path from a source git working tree into
# the current working tree (a freshly created EnterWorktree worktree).
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <source-working-tree>" >&2
    exit 1
fi

src="$(cd "$1" && pwd)"

git -C "$src" clean -ndx | while IFS= read -r line; do
    rel="${line#Would remove }"
    rel="${rel%/}"

    case "$rel" in
        .git|.claude)
            continue
            ;;
    esac

    if [ -L "$rel" ]; then
        continue
    fi
    if [ -e "$rel" ]; then
        echo "skip (already exists, not a symlink): $rel" >&2
        continue
    fi

    mkdir -p "$(dirname "$rel")"
    ln -s "${src}/${rel}" "$rel"
done
