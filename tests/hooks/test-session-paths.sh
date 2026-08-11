#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${REPO_DIR}/hooks/lib/session-paths.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

failures=0

assert_eq() {
    local actual=$1 expected=$2 description=$3
    if [ "$actual" = "$expected" ]; then
        printf 'PASS: %s\n' "$description"
    else
        printf 'FAIL: %s (expected %q, got %q)\n' "$description" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

# --- session-approved: default formula ---
out=$(env -u CLAUDE_CODE_KIT_SESSION_DIR -u CLAUDE_CODE_KIT_SESSION_APPROVED_FILE \
      CLAUDE_CODE_KIT_SESSION_ID="sid1" \
      CLAUDE_CODE_KIT_STATE_HOME="${TMP_DIR}/state" \
      bash "$SCRIPT" session-approved)
assert_eq "$out" "${TMP_DIR}/state/sessions/sid1/session-approved" \
    'session-approved: default formula honors CLAUDE_CODE_KIT_STATE_HOME'

# --- session-approved: CLAUDE_CODE_KIT_SESSION_DIR override ---
out=$(CLAUDE_CODE_KIT_SESSION_ID="sid1" \
      CLAUDE_CODE_KIT_SESSION_DIR="${TMP_DIR}/custom-session-dir" \
      bash "$SCRIPT" session-approved)
assert_eq "$out" "${TMP_DIR}/custom-session-dir/session-approved" \
    'session-approved: CLAUDE_CODE_KIT_SESSION_DIR override is honored'

# --- session-approved: CLAUDE_CODE_KIT_SESSION_APPROVED_FILE override (highest priority) ---
out=$(CLAUDE_CODE_KIT_SESSION_ID="sid1" \
      CLAUDE_CODE_KIT_SESSION_DIR="${TMP_DIR}/custom-session-dir" \
      CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="${TMP_DIR}/explicit-file" \
      bash "$SCRIPT" session-approved)
assert_eq "$out" "${TMP_DIR}/explicit-file" \
    'session-approved: CLAUDE_CODE_KIT_SESSION_APPROVED_FILE overrides everything else'

# --- session-tmp-dir: default root ---
out=$(env -u CLAUDE_CODE_KIT_TMP_ROOT \
      CLAUDE_CODE_KIT_SESSION_ID="sid2" \
      bash "$SCRIPT" session-tmp-dir)
assert_eq "$out" "/tmp/claude-code-kit/sid2" \
    'session-tmp-dir: default root is /tmp/claude-code-kit'

# --- session-tmp-dir: CLAUDE_CODE_KIT_TMP_ROOT override ---
out=$(CLAUDE_CODE_KIT_SESSION_ID="sid2" \
      CLAUDE_CODE_KIT_TMP_ROOT="${TMP_DIR}/tmproot" \
      bash "$SCRIPT" session-tmp-dir)
assert_eq "$out" "${TMP_DIR}/tmproot/sid2" \
    'session-tmp-dir: CLAUDE_CODE_KIT_TMP_ROOT override is honored'

# --- invoked through a symlink (mirrors the installed ~/.claude/hooks/lib/... path) ---
SYMLINK_DIR="${TMP_DIR}/installed/hooks/lib"
mkdir -p "$SYMLINK_DIR"
ln -s "$SCRIPT" "${SYMLINK_DIR}/session-paths.sh"
out=$(CLAUDE_CODE_KIT_SESSION_ID="sid3" bash "${SYMLINK_DIR}/session-paths.sh" session-tmp-dir)
assert_eq "$out" "/tmp/claude-code-kit/sid3" \
    'resolves correctly when invoked through a symlink (installed-path simulation)'

# --- unknown / missing mode exits non-zero with a usage message ---
if bash "$SCRIPT" 2>/dev/null; then
    printf 'FAIL: %s\n' 'missing mode should exit non-zero'
    failures=$((failures + 1))
else
    printf 'PASS: %s\n' 'missing mode exits non-zero'
fi

if bash "$SCRIPT" bogus-mode 2>/dev/null; then
    printf 'FAIL: %s\n' 'unknown mode should exit non-zero'
    failures=$((failures + 1))
else
    printf 'PASS: %s\n' 'unknown mode exits non-zero'
fi

if ((failures > 0)); then
    printf '\n%d session-paths test(s) failed.\n' "$failures"
    exit 1
fi

printf '\nAll session-paths tests passed.\n'
