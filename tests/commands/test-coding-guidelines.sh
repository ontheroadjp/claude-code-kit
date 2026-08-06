#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion patterns intentionally contain literal Markdown backticks
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
failures=0

assert_contains() {
  local file=$1 pattern=$2 description=$3
  if rg -q --fixed-strings -- "$pattern" "$file"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

assert_absent_all() {
  local pattern=$1 description=$2
  shift 2
  if rg -q --fixed-strings -- "$pattern" "$@"; then
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$description"
  fi
}

REACT="$REPO_DIR/commands/coding-react.md"
NEXTJS="$REPO_DIR/commands/coding-nextjs.md"
TASK="$REPO_DIR/commands/task.md"
PATCH="$REPO_DIR/commands/patch.md"
ROOT_SLASH='/'

assert_contains "$REACT" '`coding-general`、`coding-js`、TypeScriptの場合は `coding-ts`' 'React composes language guidelines'
assert_contains "$NEXTJS" '`coding-general`、`coding-js`、`coding-ts`、`coding-react`' 'Next.js composes React and TypeScript guidelines'
assert_contains "$REACT" 'Hookを条件分岐' 'React covers conditional Hook calls'
assert_contains "$REACT" 'list keyにindex、乱数、render時刻を使わない' 'React covers unstable keys'
assert_contains "$NEXTJS" 'Client Componentにする' 'Next.js covers excessive client boundaries'
assert_contains "$NEXTJS" '同一applicationのRoute HandlerをHTTP経由で呼ばない' 'Next.js covers server-side self-fetching'
assert_contains "$NEXTJS" '導入済みversionの公式ドキュメント' 'Next.js requires version-aware verification'
assert_contains "$TASK" 'React + TypeScript (.tsx)' 'task routes TSX through React'
assert_contains "$PATCH" 'Next.js（`next` dependencyまたはNext.js configで判定）' 'patch detects Next.js projects'

assert_absent_all "${ROOT_SLASH}home/" 'guidelines contain no local absolute path' "$REPO_DIR"/commands/coding-*.md
assert_absent_all 'core-toolkit-for-claude' 'guidelines contain no repository-specific name' "$REPO_DIR"/commands/coding-*.md

if ((failures > 0)); then
  printf '\n%d coding guideline contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll coding guideline contract tests passed.\n'
