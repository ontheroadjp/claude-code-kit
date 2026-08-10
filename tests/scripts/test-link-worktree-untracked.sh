#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_DIR}/scripts/link-worktree-untracked.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC_DIR="${TMP_DIR}/src"
DST_DIR="${TMP_DIR}/dst"
mkdir -p "$SRC_DIR" "$DST_DIR"

failures=0

assert_symlink_to() {
    local path=$1 expected_target=$2 description=$3
    if [ -L "$path" ] && [ "$(readlink "$path")" = "$expected_target" ]; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n' "$description"
        failures=$((failures + 1))
    fi
}

assert_absent() {
    local path=$1 description=$2
    if [ -e "$path" ] || [ -L "$path" ]; then
        printf 'FAIL: %s\n' "$description"
        failures=$((failures + 1))
    else
        printf 'PASS: %s\n' "$description"
    fi
}

# --- fixture: source working tree ---
(
    cd "$SRC_DIR"
    git init -q
    git config user.email "test@example.com"
    git config user.name "test"
    mkdir -p .claude/worktrees/dummy site
    echo '{}' > .claude/settings.local.json
    echo "tracked" > tracked.txt
    echo "site readme" > site/README.md
    git add tracked.txt site/README.md
    git commit -q -m init
    echo "untracked" > untracked.txt
    mkdir -p untracked_dir
    echo "x" > untracked_dir/file.txt
    mkdir -p site/node_modules
    echo "pkg" > site/node_modules/pkg.js
)

# --- run against destination worktree ---
(
    cd "$DST_DIR"
    git init -q >/dev/null
    bash "$SCRIPT" "$SRC_DIR"
)

assert_symlink_to "${DST_DIR}/untracked.txt" "${SRC_DIR}/untracked.txt" \
    'top-level untracked file is symlinked'
assert_symlink_to "${DST_DIR}/untracked_dir" "${SRC_DIR}/untracked_dir" \
    'top-level untracked directory is symlinked'
assert_symlink_to "${DST_DIR}/site/node_modules" "${SRC_DIR}/site/node_modules" \
    'untracked directory nested inside a tracked directory is symlinked at the correct path'
assert_absent "${DST_DIR}/.git/link-worktree-untracked-marker" \
    '.git is not touched (no stray marker path created inside it)'
assert_absent "${DST_DIR}/.claude" \
    '.claude is excluded entirely (avoids the self-referential worktrees/ loop)'

# --- idempotency: running again must not fail or duplicate ---
(
    cd "$DST_DIR"
    bash "$SCRIPT" "$SRC_DIR"
)
if [ -L "${DST_DIR}/untracked.txt" ]; then
    printf 'PASS: %s\n' 're-running the script is idempotent'
else
    printf 'FAIL: %s\n' 're-running the script is idempotent'
    failures=$((failures + 1))
fi

if ((failures > 0)); then
    printf '\n%d link-worktree-untracked test(s) failed.\n' "$failures"
    exit 1
fi

printf '\nAll link-worktree-untracked tests passed.\n'
