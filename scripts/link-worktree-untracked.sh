#!/usr/bin/env bash
# Symlink every untracked/ignored path from a source git working tree into
# the current working tree (a freshly created EnterWorktree worktree).
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <source-working-tree>" >&2
    exit 1
fi

src="$(cd "$1" && pwd)"

# Record every path this run symlinks, so callers (e.g. commands/work.md G-2,
# commands/task.md Phase 2) can tell "symlink I created" apart from a real
# uncommitted change without re-deriving it (issue #318). Best-effort: if
# hooks/lib/session-paths.sh isn't installed for either agent, the manifest
# is simply not written and behavior is unchanged from before this file
# existed.
manifest=""
if [ -f "${HOME}/.claude/hooks/lib/session-paths.sh" ]; then
    manifest="$(bash "${HOME}/.claude/hooks/lib/session-paths.sh" session-tmp-dir 2>/dev/null || true)"
elif [ -f "${HOME}/.codex/hooks/lib/session-paths.sh" ]; then
    manifest="$(bash "${HOME}/.codex/hooks/lib/session-paths.sh" session-tmp-dir 2>/dev/null || true)"
fi
if [ -n "$manifest" ]; then
    mkdir -p "$manifest"
    manifest="${manifest}/worktree-untracked-symlinks.txt"
    : > "$manifest"
fi

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
    [ -n "$manifest" ] && printf '%s\n' "$rel" >> "$manifest"
done
