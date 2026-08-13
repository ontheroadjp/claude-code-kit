#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_DIR}/scripts/worktree-status.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0

assert_contains() {
    local value=$1 pattern=$2 description=$3
    if [[ "$value" == *"$pattern"* ]]; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n' "$description"
        failures=$((failures + 1))
    fi
}

assert_not_contains() {
    local value=$1 pattern=$2 description=$3
    if [[ "$value" != *"$pattern"* ]]; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n' "$description"
        failures=$((failures + 1))
    fi
}

SOURCE_DIR="${TMP_DIR}/source"
WORKTREE_DIR="${TMP_DIR}/workspace/.claude/worktrees/test"
HOME_DIR="${TMP_DIR}/home"
SESSION_TMP_DIR="${TMP_DIR}/session-tmp"
mkdir -p "$SOURCE_DIR" "$WORKTREE_DIR" "${HOME_DIR}/.codex/hooks/lib" "$SESSION_TMP_DIR"

(
    cd "$SOURCE_DIR"
    git init -q
    git config user.email test@example.com
    git config user.name test
    printf 'tracked\n' > tracked.txt
    git add tracked.txt
    git commit -qm init
    printf 'linked\n' > linked.txt
    mkdir -p .pytest_cache
    printf 'cache\n' > .pytest_cache/.gitignore
)

(
    cd "$WORKTREE_DIR"
    git init -q
    git config user.email test@example.com
    git config user.name test
    printf 'tracked\n' > tracked.txt
    git add tracked.txt
    git commit -qm init
    ln -s "${SOURCE_DIR}/linked.txt" linked.txt
    mkdir -p .pytest_cache
    ln -s "${SOURCE_DIR}/.pytest_cache/.gitignore" .pytest_cache/.gitignore
    printf 'real\n' > real.txt
    printf 'changed\n' > tracked.txt
)

cat > "${HOME_DIR}/.codex/hooks/lib/session-paths.sh" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "${SESSION_TMP_DIR}"
EOF
chmod +x "${HOME_DIR}/.codex/hooks/lib/session-paths.sh"
printf 'linked.txt\n.pytest_cache/.gitignore\n' > "${SESSION_TMP_DIR}/worktree-untracked-symlinks.txt"

filtered_status="$(cd "$WORKTREE_DIR" && HOME="$HOME_DIR" bash "$SCRIPT")"
assert_not_contains "$filtered_status" 'linked.txt' 'manifest-listed symlink is excluded'
assert_not_contains "$filtered_status" '.pytest_cache/' 'aggregated parent directory of a manifest entry is excluded'
assert_contains "$filtered_status" '?? real.txt' 'real untracked change remains visible'
assert_contains "$filtered_status" ' M tracked.txt' 'tracked modification remains visible'

normal_dir="${TMP_DIR}/normal"
mkdir -p "$normal_dir"
(
    cd "$normal_dir"
    git init -q
    git config user.email test@example.com
    git config user.name test
    printf 'real\n' > real.txt
)
normal_status="$(cd "$normal_dir" && HOME="$HOME_DIR" bash "$SCRIPT")"
assert_contains "$normal_status" '?? real.txt' 'non-worktree status is returned unchanged'

if ((failures > 0)); then
    printf '\n%d worktree-status test(s) failed.\n' "$failures"
    exit 1
fi

printf '\nAll worktree-status tests passed.\n'
