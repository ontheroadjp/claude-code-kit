#!/usr/bin/env bash
# Lazily symlink explicitly requested untracked or ignored paths into a worktree.
set -euo pipefail

CLAUDE_SESSION_PATHS="${HOME}/.claude/hooks/lib/session-paths.sh"
CODEX_SESSION_PATHS="${HOME}/.codex/hooks/lib/session-paths.sh"
MANIFEST_NAME='worktree-untracked-symlinks.txt'
SOURCE_NAME='worktree-untracked-source.txt'

usage() {
    echo "Usage: $0 prepare <source-working-tree> | link <relative-path> | venv <relative-path>" >&2
    exit 1
}

session_tmp_dir() {
    local session_paths=""

    if [[ -f "$CLAUDE_SESSION_PATHS" ]]; then
        session_paths="$CLAUDE_SESSION_PATHS"
    elif [[ -f "$CODEX_SESSION_PATHS" ]]; then
        session_paths="$CODEX_SESSION_PATHS"
    else
        echo 'session-paths.sh is required for lazy worktree links' >&2
        exit 1
    fi

    bash "$session_paths" session-tmp-dir
}

reject_unsafe_path() {
    local relative_path=$1

    case "$relative_path" in
        ''|/*|.|..|../*|*/../*|*/..|.git|.git/*|.claude|.claude/*)
            echo "refusing unsafe worktree link path: $relative_path" >&2
            exit 1
            ;;
    esac
}

is_linkable_source_path() {
    local source=$1 relative_path=$2 entry status reported_path

    while IFS= read -r -d '' entry; do
        status=${entry:0:2}
        reported_path=${entry:3}
        reported_path=${reported_path%/}

        case "$status" in
            '??'|'!!') ;;
            *) continue ;;
        esac

        if [[ "$relative_path" == "$reported_path" || "$relative_path" == "$reported_path/"* ]]; then
            return 0
        fi
    done < <(git -C "$source" status --porcelain -z --ignored=matching -- "$relative_path")

    return 1
}

append_manifest_path() {
    local manifest=$1 relative_path=$2

    if ! grep -qxF -- "$relative_path" "$manifest"; then
        printf '%s\n' "$relative_path" >> "$manifest"
    fi
}

if [[ "$#" -lt 1 ]]; then
    usage
fi

tmp_dir="$(session_tmp_dir)"
manifest="${tmp_dir}/${MANIFEST_NAME}"
source_file="${tmp_dir}/${SOURCE_NAME}"

case "$1" in
    prepare)
        [[ "$#" -eq 2 ]] || usage
        source_dir="$(cd "$2" && pwd)"
        git -C "$source_dir" rev-parse --show-toplevel >/dev/null
        mkdir -p "$tmp_dir"

        if [[ -f "$source_file" ]] && [[ "$(<"$source_file")" != "$source_dir" ]]; then
            echo 'lazy worktree linker is already prepared for another source' >&2
            exit 1
        fi

        printf '%s\n' "$source_dir" > "$source_file"
        touch "$manifest"
        ;;
    link)
        [[ "$#" -eq 2 ]] || usage
        relative_path=${2%/}
        reject_unsafe_path "$relative_path"

        if [[ ! -f "$source_file" ]]; then
            echo 'lazy worktree linker is not prepared for this session' >&2
            exit 1
        fi

        source_dir="$(<"$source_file")"
        if ! is_linkable_source_path "$source_dir" "$relative_path"; then
            echo "refusing path that is not untracked or ignored in source: $relative_path" >&2
            exit 1
        fi

        mkdir -p "$(dirname "$relative_path")"
        if [[ -L "$relative_path" ]]; then
            if [[ "$(readlink "$relative_path")" != "${source_dir}/${relative_path}" ]]; then
                echo "refusing existing symlink with another target: $relative_path" >&2
                exit 1
            fi
        elif [[ -e "$relative_path" ]]; then
            echo "refusing existing non-symlink path: $relative_path" >&2
            exit 1
        else
            ln -s "${source_dir}/${relative_path}" "$relative_path"
        fi

        append_manifest_path "$manifest" "$relative_path"
        ;;
    venv)
        [[ "$#" -eq 2 ]] || usage
        relative_path=${2%/}
        reject_unsafe_path "$relative_path"

        case "$(basename -- "$relative_path")" in
            venv|.venv) ;;
            *)
                echo "refusing venv build for non-venv path: $relative_path" >&2
                exit 1
                ;;
        esac

        if [[ -e "$relative_path" || -L "$relative_path" ]]; then
            echo "refusing existing path for venv build: $relative_path" >&2
            exit 1
        fi

        if ! git check-ignore -q -- "${relative_path}/"; then
            echo "refusing venv build for path not covered by .gitignore: $relative_path" >&2
            exit 1
        fi

        mkdir -p "$tmp_dir"
        mkdir -p "$(dirname "$relative_path")"
        if command -v uv >/dev/null 2>&1; then
            uv venv "$relative_path"
        else
            python3 -m venv "$relative_path"
        fi

        append_manifest_path "$manifest" "$relative_path"
        ;;
    *) usage ;;
esac
