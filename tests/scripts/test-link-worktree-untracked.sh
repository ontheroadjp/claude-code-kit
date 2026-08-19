#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_DIR}/scripts/link-worktree-untracked.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0

assert_symlink_to() {
    local path=$1 expected_target=$2 description=$3
    if [[ -L "$path" && "$(readlink "$path")" == "$expected_target" ]]; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n' "$description"
        failures=$((failures + 1))
    fi
}

assert_absent() {
    local path=$1 description=$2
    if [[ ! -e "$path" && ! -L "$path" ]]; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s\n' "$description"
        failures=$((failures + 1))
    fi
}

assert_fails() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'FAIL: %s\n' "$description"
        failures=$((failures + 1))
    else
        printf 'PASS: %s\n' "$description"
    fi
}

SRC_DIR="${TMP_DIR}/src"
DST_DIR="${TMP_DIR}/dst"
HOME_DIR="${TMP_DIR}/home"
SESSION_TMP_DIR="${TMP_DIR}/session-tmp"
mkdir -p "$SRC_DIR" "$DST_DIR" "${HOME_DIR}/.codex/hooks/lib"

(
    cd "$SRC_DIR"
    git init -q
    git config user.email 'test@example.com'
    git config user.name test
    printf '.claude/\n' > .gitignore
    mkdir -p .claude/worktrees/dummy site
    printf '{}\n' > .claude/settings.local.json
    printf 'tracked\n' > tracked.txt
    printf 'site readme\n' > site/README.md
    git add .gitignore tracked.txt site/README.md
    git commit -qm init
    printf 'untracked\n' > untracked.txt
    mkdir -p untracked_dir
    printf 'x\n' > untracked_dir/file.txt
    mkdir -p site/node_modules
    printf 'pkg\n' > site/node_modules/pkg.js
)

cat > "${HOME_DIR}/.codex/hooks/lib/session-paths.sh" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "${SESSION_TMP_DIR}"
EOF
chmod +x "${HOME_DIR}/.codex/hooks/lib/session-paths.sh"

(
    cd "$DST_DIR"
    git init -q >/dev/null
    HOME="$HOME_DIR" bash "$SCRIPT" prepare "$SRC_DIR"
)

MANIFEST="${SESSION_TMP_DIR}/worktree-untracked-symlinks.txt"
SOURCE_FILE="${SESSION_TMP_DIR}/worktree-untracked-source.txt"
if [[ -f "$MANIFEST" && "$(<"$SOURCE_FILE")" == "$SRC_DIR" ]]; then
    printf 'PASS: %s\n' 'prepare records the source and creates an empty manifest'
else
    printf 'FAIL: %s\n' 'prepare records the source and creates an empty manifest'
    failures=$((failures + 1))
fi
assert_absent "${DST_DIR}/untracked.txt" 'prepare does not eagerly link top-level files'
assert_absent "${DST_DIR}/site/node_modules" 'prepare does not eagerly link ignored directories'

(
    cd "$DST_DIR"
    HOME="$HOME_DIR" bash "$SCRIPT" link untracked.txt
    HOME="$HOME_DIR" bash "$SCRIPT" link site/node_modules
    HOME="$HOME_DIR" bash "$SCRIPT" link untracked.txt
)

assert_symlink_to "${DST_DIR}/untracked.txt" "${SRC_DIR}/untracked.txt" \
    'requested top-level untracked file is symlinked'
assert_symlink_to "${DST_DIR}/site/node_modules" "${SRC_DIR}/site/node_modules" \
    'requested ignored directory nested in a tracked directory is symlinked'
assert_absent "${DST_DIR}/untracked_dir" 'unrequested untracked directory remains absent'
assert_absent "${DST_DIR}/.claude" '.claude is never eagerly linked'

if [[ "$(grep -cxF 'untracked.txt' "$MANIFEST")" == 1 ]] \
    && grep -qxF 'site/node_modules' "$MANIFEST"; then
    printf 'PASS: %s\n' 'manifest records each lazy-created link exactly once'
else
    printf 'FAIL: %s\n' 'manifest records each lazy-created link exactly once'
    failures=$((failures + 1))
fi

(
    cd "$DST_DIR"
    assert_fails 'tracked paths are rejected' env HOME="$HOME_DIR" bash "$SCRIPT" link tracked.txt
    assert_fails 'unsafe parent traversal is rejected' env HOME="$HOME_DIR" bash "$SCRIPT" link ../untracked.txt
    assert_fails '.claude paths are rejected' env HOME="$HOME_DIR" bash "$SCRIPT" link .claude/settings.local.json
    assert_fails 'unavailable paths are rejected' env HOME="$HOME_DIR" bash "$SCRIPT" link absent.txt
)

# --- venv subcommand: rejection paths that do not require uv or .gitignore setup ---
(
    cd "$DST_DIR"
    assert_fails 'venv build rejects non-venv basenames' env HOME="$HOME_DIR" bash "$SCRIPT" venv notvenv
    assert_fails 'venv build rejects unsafe parent traversal' env HOME="$HOME_DIR" bash "$SCRIPT" venv ../venv
)

mkdir -p "${DST_DIR}/existing-venv-dir/venv"
(
    cd "$DST_DIR"
    assert_fails 'venv build rejects an already-existing target path' \
        env HOME="$HOME_DIR" bash "$SCRIPT" venv existing-venv-dir/venv
)

# --- venv subcommand: .gitignore enforcement (independent of the build tool) ---
(
    cd "$DST_DIR"
    assert_fails 'venv build rejects a target not covered by .gitignore' \
        env HOME="$HOME_DIR" bash "$SCRIPT" venv .venv
)

printf '.venv/\n' >> "${DST_DIR}/.gitignore"

# --- venv subcommand: actual build via uv, when available ---
if command -v uv >/dev/null 2>&1; then
    (
        cd "$DST_DIR"
        HOME="$HOME_DIR" bash "$SCRIPT" venv .venv
    )

    if [[ -d "${DST_DIR}/.venv" && ! -L "${DST_DIR}/.venv" ]]; then
        printf 'PASS: %s\n' 'venv build creates a real directory via uv, not a symlink'
    else
        printf 'FAIL: %s\n' 'venv build creates a real directory via uv, not a symlink'
        failures=$((failures + 1))
    fi

    if grep -qxF '.venv' "$MANIFEST"; then
        printf 'PASS: %s\n' 'venv build records the path in the lazy-link manifest'
    else
        printf 'FAIL: %s\n' 'venv build records the path in the lazy-link manifest'
        failures=$((failures + 1))
    fi

    rm -rf "${DST_DIR}/.venv"
else
    printf 'SKIP: venv build via uv (uv not installed)\n'
fi

# --- venv subcommand: falls back to python3 -m venv when uv is unavailable ---
if command -v python3 >/dev/null 2>&1; then
    uv_dir_real=""
    if uv_path="$(command -v uv 2>/dev/null)"; then
        uv_dir_real="$(cd "$(dirname "$uv_path")" && pwd -P)"
    fi

    fallback_path=""
    IFS=':' read -ra path_dirs <<< "$PATH"
    for path_dir in "${path_dirs[@]}"; do
        if [[ -n "$uv_dir_real" && -d "$path_dir" ]]; then
            resolved_dir="$(cd "$path_dir" && pwd -P)"
            [[ "$resolved_dir" == "$uv_dir_real" ]] && continue
        fi
        fallback_path="${fallback_path:+$fallback_path:}$path_dir"
    done

    (
        cd "$DST_DIR"
        env HOME="$HOME_DIR" PATH="$fallback_path" bash "$SCRIPT" venv .venv
    )

    if [[ -f "${DST_DIR}/.venv/pyvenv.cfg" && ! -L "${DST_DIR}/.venv" ]]; then
        printf 'PASS: %s\n' 'venv build falls back to python3 -m venv when uv is unavailable'
    else
        printf 'FAIL: %s\n' 'venv build falls back to python3 -m venv when uv is unavailable'
        failures=$((failures + 1))
    fi

    rm -rf "${DST_DIR}/.venv"
else
    printf 'SKIP: venv build python3 -m venv fallback (python3 not installed)\n'
fi

if ((failures > 0)); then
    printf '\n%d link-worktree-untracked test(s) failed.\n' "$failures"
    exit 1
fi

printf '\nAll link-worktree-untracked tests passed.\n'
