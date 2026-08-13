#!/usr/bin/env bash
# Print workspace status while excluding symlinks recorded for this worktree session.
set -euo pipefail

WORKTREE_PATH_FRAGMENT='.claude/worktrees/'
CLAUDE_SESSION_PATHS="${HOME}/.claude/hooks/lib/session-paths.sh"
CODEX_SESSION_PATHS="${HOME}/.codex/hooks/lib/session-paths.sh"

repo_root="$(git rev-parse --show-toplevel)"
if [[ "$repo_root" != *"$WORKTREE_PATH_FRAGMENT"* ]]; then
    git status --porcelain
    exit 0
fi

session_paths=""
if [[ -f "$CLAUDE_SESSION_PATHS" ]]; then
    session_paths="$CLAUDE_SESSION_PATHS"
elif [[ -f "$CODEX_SESSION_PATHS" ]]; then
    session_paths="$CODEX_SESSION_PATHS"
fi

if [[ -z "$session_paths" ]]; then
    git status --porcelain
    exit 0
fi

session_tmp_dir="$(bash "$session_paths" session-tmp-dir 2>/dev/null || true)"
manifest="${session_tmp_dir}/worktree-untracked-symlinks.txt"
if [[ -z "$session_tmp_dir" || ! -f "$manifest" ]]; then
    git status --porcelain
    exit 0
fi

is_recorded_symlink_status() {
    local entry=$1
    local status=${entry:0:2}
    local path=${entry:3}
    local recorded_path

    case "$status" in
        '??'|'!!') ;;
        *) return 1 ;;
    esac

    path=${path%/}

    while IFS= read -r recorded_path; do
        if [[ "$path" == "$recorded_path" || "$recorded_path" == "$path/"* ]]; then
            return 0
        fi
    done < "$manifest"

    return 1
}

while IFS= read -r -d '' entry; do
    if ! is_recorded_symlink_status "$entry"; then
        printf '%s\n' "$entry"
    fi
done < <(git status --porcelain -z --ignored=matching)
