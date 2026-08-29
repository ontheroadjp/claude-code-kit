#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion strings intentionally contain literal Markdown backticks
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK="$REPO_DIR/commands/work.md"
TASK="$REPO_DIR/commands/task.md"
TASK_MANAGER="$REPO_DIR/commands/task-manager.md"
WORK_SKILL="$REPO_DIR/skills/work/SKILL.md"
TASK_SKILL="$REPO_DIR/skills/task/SKILL.md"
TASK_MANAGER_SKILL="$REPO_DIR/skills/task-manager/SKILL.md"

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

assert_absent() {
  local file=$1 pattern=$2 description=$3
  if rg -q --fixed-strings -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$description"
  fi
}

# /work is the atomic, unified entry point.
assert_contains "$WORK" '/work #123 #456 #789' 'work documents multi-issue input'
assert_contains "$WORK" 'Phase 0: atomic read-only preflight' 'work owns atomic preflight'
assert_contains "$WORK" '^#[1-9][0-9]*$' 'work validates every issue token'
assert_contains "$WORK" 'invocation 全体を終了' 'one invalid issue stops the complete invocation'
assert_contains "$WORK" '全 issue が implementation-ready' 'all issues must pass before mutation'
assert_contains "$WORK" 'project-wide context を一度だけ取得' 'project context is acquired once'
assert_contains "$WORK" '2〜3件の accepted issue' 'multi-issue input routes to task-manager'
assert_contains "$WORK" 'multi-issue `/patch` は対象外' 'mixed patch batches remain out of scope'
assert_contains "$WORK" 'stash restoration' 'work owns final stash restoration state'

# /task has one shared ordinary/delegated implementation contract.
assert_contains "$TASK" '### delegated worker mode' 'task defines delegated worker mode'
assert_contains "$TASK" 'shortest-path supplemental investigation' 'delegated task limits supplemental investigation'
assert_contains "$TASK" '同じ worker' 'delegated task preserves worker continuity'
assert_contains "$TASK" 'Ready PR handoff' 'delegated task returns a Ready PR handoff'
assert_contains "$TASK" 'parent cleanup・stash restoration' 'delegated task does not own parent cleanup'
assert_absent "$TASK" 'gh pr create --draft' 'delegated task does not introduce Draft-only delivery'

# task-manager contains orchestration, not duplicated work/task logic.
assert_contains "$TASK_MANAGER" 'internal batch orchestrator' 'task-manager is internal orchestration'
assert_contains "$TASK_MANAGER" 'input validation、issue readiness、project-wide investigation を再実行しない' 'task-manager reuses work preflight'
assert_contains "$TASK_MANAGER" 'delegated `commands/task.md` を完全に Read' 'workers execute the shared task workflow'
assert_contains "$TASK_MANAGER" 'source/test/docs の調査・plan・実装・validation・PR 作成契約を親で複製しない' 'task-manager does not duplicate task contracts'
assert_contains "$TASK_MANAGER" 'MAX_TASK_WORKERS = 3' 'worker concurrency stays bounded'
for state in investigating awaiting_plan_approval implementing awaiting_pr_approval delivery_eligible delivering completed failed; do
  assert_contains "$TASK_MANAGER" "$state" "state $state is defined"
done
assert_contains "$TASK_MANAGER" 'worker message を到着順に処理' 'approval results are streamed'
assert_contains "$TASK_MANAGER" 'Ready PR をレビュー' 'Ready PR approval is issue-specific'
assert_contains "$TASK_MANAGER" '先行 issue がすべて `completed`' 'delivery remains in input order'
assert_contains "$TASK_MANAGER" '`commands/git-pr-merge.md` を完全に Read' 'delivery delegates to git-pr-merge'
assert_contains "$TASK_MANAGER" 'return to /work' 'task-manager returns lifecycle state to work'
assert_contains "$TASK_MANAGER" 'parent workspace、stash、force cleanup を操作しない' 'task-manager does not own cleanup'
assert_absent "$TASK_MANAGER" 'gh pr create --draft' 'task-manager no longer duplicates PR creation'
assert_absent "$TASK_MANAGER" 'README の Features・Design Principles・Usage' 'task-manager no longer duplicates project investigation'

# Skill adapters preserve the unified ownership boundaries.
assert_contains "$WORK_SKILL" 'single and multiple issue input' 'work skill exposes unified entry'
assert_contains "$WORK_SKILL" 'workspace cleanup and stash restoration' 'work skill preserves cleanup ownership'
assert_contains "$TASK_SKILL" 'delegated worker mode' 'task skill supports delegated execution'
assert_contains "$TASK_SKILL" 'Ready PR creation' 'task skill preserves Ready PR delivery'
assert_contains "$TASK_MANAGER_SKILL" 'only when commands/work.md routes' 'task-manager skill is internal'
assert_contains "$TASK_MANAGER_SKILL" 'Without a valid `/work` handoff' 'direct task-manager invocation stops'
assert_contains "$TASK_MANAGER_SKILL" 'never own parent workspace cleanup or stash restoration' 'task-manager skill returns cleanup to work'

if ((failures > 0)); then
  printf '\n%d unified work contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll unified work contract tests passed.\n'
