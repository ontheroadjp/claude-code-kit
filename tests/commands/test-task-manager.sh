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
assert_contains "$TASK" 'full_validation_evidence:' 'first delegated task can return SHA-bound full validation evidence'
assert_contains "$TASK" '後続 worker は先行 delivery により base が変わる' 'later workers do not precompute reusable full validation'
assert_contains "$TASK" 'parent cleanup・stash restoration' 'delegated task does not own parent cleanup'
assert_absent "$TASK" 'gh pr create --draft' 'delegated task does not introduce Draft-only delivery'
assert_contains "$TASK" 'payload の絶対パス（`Command root`・`Work-run events helper`）から直接読む' 'delegated task reads command/helper files from payload paths'
assert_contains "$TASK" 'ファイルシステム探索はしない' 'delegated task does not search the filesystem for command/helper files'

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
assert_contains "$TASK_MANAGER" 'Command root: <absolute installed commands dir for the executing agent' 'worker payload carries the resolved command root'
assert_contains "$TASK_MANAGER" 'Work-run events helper: <absolute installed work-run-events.sh path' 'worker payload carries the resolved work-run helper path'
assert_contains "$TASK_MANAGER" 'filesystem-searching for task.md, coding-*.md, or work-run-events.sh instead of using the payload paths' 'worker must not search the filesystem for command/helper files'
assert_contains "$TASK_MANAGER" 'Read <Command root>/task.md completely' 'worker reads task.md from the payload command root'
assert_contains "$TASK_MANAGER" '複数 issue の plan・実装レビュー・PR gate を1つのプロンプトに束ねて提示すること' 'task-manager forbids batching gates across issues'
assert_contains "$TASK_MANAGER" '複数 issue をまとめて承認・却下させること' 'task-manager forbids one approval covering multiple issues'
assert_contains "$TASK_MANAGER" 'cross-issue の順序待ちが許されるのは Phase 3 の fixed-order delivery だけ' 'cross-issue waiting is limited to fixed-order delivery'
assert_contains "$TASK_MANAGER" '状態遷移のない進捗ナレーション' 'task-manager suppresses idle progress-narration turns'
assert_contains "$TASK" 'この実装レビュー gate も対象 issue 単独で relay され' 'implementation-review gate is relayed per issue'
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
assert_contains "$TASK_MANAGER" 'work_run_id: <logical /work run id' 'task-manager receives the parent work run id'
assert_contains "$TASK_MANAGER" 'approval_wait_started issue_number=<N>' 'task-manager records issue-specific approval waits'
assert_contains "$TASK_MANAGER" 'approved_head_recorded issue_number=<N>' 'task-manager correlates approved PR heads'
assert_contains "$TASK_MANAGER" 'reuse 可否を判断せず' 'task-manager forwards evidence without owning reuse policy'
assert_contains "$TASK_MANAGER" 'full_validation_evidence: <optional' 'task-manager delivery handoff carries optional evidence'

if ((failures > 0)); then
  printf '\n%d unified work contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll unified work contract tests passed.\n'
