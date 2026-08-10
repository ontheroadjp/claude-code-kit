#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion strings are literal Markdown excerpts; backticks must remain literal
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
DOCS_SYNC="$REPO_DIR/commands/docs-sync.md"
INIT_DOCS="$REPO_DIR/commands/init-docs.md"
TASK="$REPO_DIR/commands/task.md"
GIT_PR="$REPO_DIR/commands/git-pr.md"

failures=0

assert_contains() {
  local file=$1
  local pattern=$2
  local description=$3

  if rg -q --fixed-strings -- "$pattern" "$file"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

assert_contains "$DOCS_SYNC" '/init-docs` を **documentation-only mode** で自動実行する' 'docs-sync automatically delegates HARD STOP recovery'
assert_contains "$DOCS_SYNC" 'Phase 3 Step 3 へ進み' 'docs-sync rejoins its commit and result-writing phase'
assert_contains "$DOCS_SYNC" '呼び出し元には通常の `/docs-sync` 完了として制御を返す' 'docs-sync hides internal escalation from its caller'
assert_contains "$DOCS_SYNC" 'push・PR 作成を行わない' 'docs-sync preserves the PR responsibility boundary'

assert_contains "$INIT_DOCS" '**standalone mode（デフォルト）**' 'init-docs keeps standalone mode as the default'
assert_contains "$INIT_DOCS" '**documentation-only mode**' 'init-docs exposes documentation-only regeneration'
assert_contains "$INIT_DOCS" '特にモードの指示がない場合' 'init-docs defaults to standalone without an explicit mode'
assert_contains "$INIT_DOCS" 'このモードが明示された場合' 'init-docs enters documentation-only mode only when instructed'
assert_contains "$INIT_DOCS" '呼び出し時の現在ブランチを維持する' 'delegated init-docs preserves the task branch'
assert_contains "$INIT_DOCS" 'commit・push・PR 作成を行わない' 'delegated init-docs does not publish changes'
assert_contains "$INIT_DOCS" 'このフェーズは standalone mode でのみ実行する' 'init-docs skips Phase 7 outside standalone mode'
assert_contains "$INIT_DOCS" '`/git-commit` を実行する' 'init-docs delegates final commit creation to /git-commit'
assert_contains "$INIT_DOCS" 'fixed_message="<上記で組み立てたメッセージ>"' 'init-docs passes the fixed init-docs commit message to /git-commit'

assert_contains "$TASK" '`/docs-sync` 完了後、ユーザー確認なしに即座に `/git-pr` を実行する' 'task remains unaware of docs-sync internal escalation'
assert_contains "$GIT_PR" 'gh pr create --title "<title>"' 'git-pr remains responsible for PR creation'

if ((failures > 0)); then
  printf '\n%d workflow contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll workflow contract tests passed.\n'
