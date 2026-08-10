#!/usr/bin/env bash
# Symlink every untracked/ignored path from a source git working tree into
# the current working tree (a freshly created EnterWorktree worktree).
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <source-working-tree>" >&2
    exit 1
fi

src="$(cd "$1" && pwd)"

git -C "$src" status --porcelain -z --ignored=matching | while IFS= read -r -d '' entry; do
    status="${entry:0:2}"
    rel="${entry:3}"

    case "$status" in
        "??"|"!!") ;;
        *) continue ;;
    esac

    rel="${rel%/}"

    case "$rel" in
        .git|.git/*|.claude|.claude/*)
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
