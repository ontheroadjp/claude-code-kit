#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion strings intentionally contain literal Markdown backticks
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMMAND="$REPO_DIR/commands/git-pr-merge.md"
SKILL="$REPO_DIR/skills/git-pr-merge/SKILL.md"
failures=0

assert_exists() {
  local file=$1 description=$2
  if [[ -e "$file" ]]; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

assert_contains() {
  local file=$1 pattern=$2 description=$3
  if grep -Fq -- "$pattern" "$file"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

assert_absent() {
  local file=$1 pattern=$2 description=$3
  if grep -Fq -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$description"
  fi
}

assert_exists "$COMMAND" 'git-pr-merge command exists'
assert_exists "$SKILL" 'git-pr-merge Codex skill exists'

assert_contains "$COMMAND" '/git-pr-merge #123' 'single PR invocation is documented'
assert_contains "$COMMAND" '表示したPRとcurrent head SHAをレビュー済み' 'standalone invocation requires explicit review approval'
assert_contains "$COMMAND" 'approved_head_sha: <full remote head SHA>' 'delegated context carries approved head SHA'
assert_contains "$COMMAND" '1項目でも欠ける場合は停止' 'incomplete delegation never bypasses approval'
assert_contains "$COMMAND" 'current remote head SHAを`approved_head_sha`と比較' 'remote head is compared with approved head'
assert_contains "$COMMAND" 'unknown commitを1件でも検出したら' 'unknown commits stop delivery'
assert_contains "$COMMAND" '影響したPRだけを再承認対象' 'unknown commit reapproval is PR-specific'
assert_contains "$COMMAND" 'active invocationが' 'known commits are scoped to the active flow'
assert_contains "$COMMAND" 'full SHA、parent SHA、目的、changed paths' 'known commits require recorded evidence'
assert_contains "$COMMAND" 'git merge --no-ff origin/main' 'latest main is merged without rewriting'
assert_contains "$COMMAND" 'Draft/Readyの違いはReady transition' 'Draft and Ready share refresh and validation'
assert_contains "$COMMAND" 'current post-refresh head' 'validation targets the refreshed head'
assert_contains "$COMMAND" 'CIがplanの一部だけをcover' 'partial CI coverage uses local validation'
assert_contains "$COMMAND" 'missing、pendingのまま、skipped、neutral' 'ambiguous validation cannot pass'
assert_contains "$COMMAND" 'actual PR head branch上で解消' 'conflicts are repaired on the actual branch'
assert_contains "$COMMAND" 'materialに変える場合' 'material conflict repair requires review'
assert_contains "$COMMAND" 'local `main`をcheckout、edit、conflict repair、commit、pushに使用しない' 'local main workspace is prohibited'
assert_contains "$COMMAND" '親のmain workspaceへfallbackしない' 'dirty or unclear worktrees do not fall back to main'
assert_contains "$COMMAND" 'gh pr merge <PR> --squash' 'merge is explicitly squash'
assert_contains "$COMMAND" 'delivery直前に記録したlatest-main SHA' 'delivery verifies latest-main inclusion'
assert_contains "$COMMAND" 'branchとworktreeのcleanupはcaller' 'cleanup remains caller-owned'
assert_absent "$COMMAND" 'git push origin main' 'direct push to main is absent'
assert_absent "$COMMAND" 'git checkout main' 'checkout of local main is absent'
assert_absent "$COMMAND" 'git switch main' 'switch to local main is absent'
assert_absent "$COMMAND" 'git rebase' 'rebase is absent'
assert_absent "$COMMAND" 'git push --force' 'force push is absent'
assert_absent "$COMMAND" 'git reset' 'reset is absent'

# shellcheck disable=SC2088  # Literal installed path is part of the documentation contract.
assert_contains "$SKILL" '~/.codex/commands/git-pr-merge.md' 'skill points to installed source of truth'
assert_contains "$SKILL" 'explicitly approved head SHA' 'skill preserves approval guard'
assert_contains "$SKILL" 'Never fall back to a local main workspace' 'skill preserves workspace invariant'

if ((failures > 0)); then
  printf '\n%d git-pr-merge contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll git-pr-merge contract tests passed.\n'
