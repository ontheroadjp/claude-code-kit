#!/usr/bin/env bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PR_REVIEW="$REPO_DIR/commands/pr-review.md"
GIT_PR="$REPO_DIR/commands/git-pr.md"
SKILL="$REPO_DIR/skills/pr-review/SKILL.md"

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

assert_absent() {
  local file=$1
  local pattern=$2
  local description=$3

  if rg -q --fixed-strings -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$description"
  fi
}

assert_contains "$PR_REVIEW" 'MAX_REVIEW_ROUNDS=3' 'review loop is bounded'
assert_contains "$PR_REVIEW" 'codex exec' 'Claude implementation routes review to generic Codex exec'
assert_contains "$PR_REVIEW" '--sandbox read-only' 'the Codex reviewer runs in a read-only sandbox'
assert_contains "$PR_REVIEW" '--ephemeral' 'the Codex reviewer does not persist a session'
assert_contains "$PR_REVIEW" '--output-last-message' 'only the final Codex response is saved for parsing'
assert_absent "$PR_REVIEW" 'codex review' 'the workflow does not use the fixed-format Codex review subcommand'
assert_contains "$PR_REVIEW" 'claude -p' 'Codex implementation routes review to Claude'
assert_contains "$PR_REVIEW" 'REVIEWED_HEAD_SHA' 'review result is bound to a head SHA'
assert_contains "$PR_REVIEW" '--approve' 'approved reviews are posted to GitHub'
assert_contains "$PR_REVIEW" '--request-changes' 'change requests are posted to GitHub'
assert_contains "$PR_REVIEW" 'REVIEWER_LOGIN' 'reviewer identity is validated'
assert_contains "$PR_REVIEW" '--tools "Read"' 'the Claude reviewer receives read-only tools'
assert_contains "$PR_REVIEW" 'session-approved 外' 'fixes are limited to the approved scope'
assert_contains "$PR_REVIEW" 'ROUND == MAX_REVIEW_ROUNDS' 'the final round does not start an unreviewed fix'
assert_contains "$PR_REVIEW" '各ラウンド開始時に最初に base branch を更新する' 'every review round refreshes the base branch first'
assert_contains "$PR_REVIEW" 'git fetch origin "<baseRefName>"' 'the per-round refresh fetches the current base branch'
assert_contains "$PR_REVIEW" 'stale な base から review context を生成・投稿せず、`FAILED` で終了する' 'a failed base refresh stops review context generation'
assert_absent "$PR_REVIEW" 'gh pr merge ' 'the workflow contains no merge command'
assert_absent "$PR_REVIEW" 'git checkout main' 'the workflow does not check out main'
assert_absent "$PR_REVIEW" 'git pull ' 'the workflow does not pull main'
assert_absent "$PR_REVIEW" '--delete-branch' 'the workflow does not delete branches'
assert_contains "$GIT_PR" '/pr-review #${PR_NUMBER}' 'git-pr hands a created PR to pr-review'
assert_contains "$SKILL" 'commands/pr-review.md' 'the skill points to the command source of truth'

if ((failures > 0)); then
  printf '\n%d contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll pr-review contract tests passed.\n'
