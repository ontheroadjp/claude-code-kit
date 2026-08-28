#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion strings intentionally contain literal Markdown backticks
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TASK_MANAGER="$REPO_DIR/commands/task-manager.md"
TASK_MANAGER_SKILL="$REPO_DIR/skills/task-manager/SKILL.md"

failures=0

assert_exists() {
  local file=$1
  local description=$2

  if [ -f "$file" ]; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

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

assert_exists "$TASK_MANAGER" 'task-manager command exists'
assert_exists "$TASK_MANAGER_SKILL" 'task-manager Codex skill exists'

# Input boundary: one through three issues, no queue for a fourth issue.
assert_contains "$TASK_MANAGER" '/task-manager #123' 'single-issue invocation is documented'
assert_contains "$TASK_MANAGER" '/task-manager #123 #456 #789' 'three-issue invocation is documented'
assert_contains "$TASK_MANAGER" '^#[1-9][0-9]*$' 'issue tokens have an explicit validation contract'
assert_contains "$TASK_MANAGER" '1〜3件: 次へ進む。' 'one to three issues are accepted'
assert_contains "$TASK_MANAGER" '4件以上' 'four or more issues are rejected'
assert_contains "$TASK_MANAGER" '重複番号' 'duplicate issues are rejected'
assert_contains "$TASK_MANAGER" '待ち行列を作ってはなりません' 'a fourth issue is not queued'

# Planning gate and real sub-agent workers.
assert_contains "$TASK_MANAGER" 'branch・worktree作成、file編集、commit、push、issue/PR書き込みを行いません' 'preflight is read-only'
assert_contains "$TASK_MANAGER" '明確な承認が得られるまで次へ進みません' 'all plans require approval before mutation'
assert_contains "$TASK_MANAGER" '実体のある sub-agent' 'task-workers are real sub-agents'
assert_contains "$TASK_MANAGER" 'MAX_TASK_WORKERS = 3' 'worker concurrency is fixed at three'
assert_contains "$TASK_MANAGER" 'sub-agent model overrideを指定せず、親agentのmodelを継承する' 'workers inherit the parent model'
assert_contains "$TASK_MANAGER" 'Role: task-worker' 'worker launch payload names the role'
assert_contains "$TASK_MANAGER" 'structured handoff' 'workers return a structured handoff'
assert_contains "$TASK_MANAGER" 'gh pr create --draft' 'workers create Draft source PRs directly'
assert_contains "$TASK_MANAGER" '<type>(#<issue-number>): <English description>' 'source PR titles match the work task flow Conventional Commit format'
assert_contains "$TASK_MANAGER" 'primary implementation commitと同じtype' 'source PR titles align with their primary implementation commits'
assert_contains "$TASK_MANAGER" 'commitが1件か複数かにかかわらず' 'source PR title format is independent of commit count'
assert_contains "$TASK_MANAGER" 'documentation変更を含まない' 'source PRs exclude documentation'

# Batch review, ordered delegated delivery, and automatic docs delivery.
assert_contains "$TASK_MANAGER" 'complete Draft PR setを再提示' 'Draft rejection loops over the complete set'
assert_contains "$TASK_MANAGER" 'approved head SHA、approved scope/behavior、final validation plan' 'batch approval fixes per-PR delegated context'
assert_contains "$TASK_MANAGER" 'source PRを入力順に1本ずつ委譲' 'source PRs are delegated in input order'
assert_contains "$TASK_MANAGER" '`commands/git-pr-merge.md`を完全にRead' 'task-manager delegates to the reusable delivery workflow'
assert_contains "$TASK_MANAGER" '最初を含む各PR' 'the first PR also receives latest-main delivery handling'
assert_contains "$TASK_MANAGER" 'approved_head_sha:' 'delegation includes approved head SHA'
assert_contains "$TASK_MANAGER" 'approved_scope_or_behavior:' 'delegation includes approved scope and behavior'
assert_contains "$TASK_MANAGER" 'final_validation_plan:' 'delegation includes final validation plan'
assert_contains "$TASK_MANAGER" 'complete set全体ではなくそのPRだけ' 'unknown commits return only one PR to review'
assert_contains "$TASK_MANAGER" 'delivery state machineを複製しません' 'delivery state machine is not duplicated'
assert_absent "$TASK_MANAGER" '## Phase 4: actual source PR の逐次deliveryとsquash merge' 'embedded delivery phase is removed'
assert_absent "$TASK_MANAGER" 'git merge --no-ff origin/main' 'task-manager does not duplicate latest-main merge mechanics'
assert_contains "$TASK_MANAGER" 'lightweight development validation' 'parallel validation is lightweight development feedback'
assert_contains "$TASK_MANAGER" 'parallel phaseのvalidationはdelivery validationの代わりにはなりません' 'parallel validation is not authoritative delivery validation'
assert_contains "$TASK_MANAGER" '`1 issue = 1 source PR = 1 main commit`' 'source delivery preserves one linear main commit per issue'
assert_contains "$TASK_MANAGER" 'squash SHAの`origin/main`反映' 'merged state is confirmed before advancing'
assert_contains "$TASK_MANAGER" 'rollback-capableな単一transactionとして扱いません' 'partial source delivery is not modeled as rollback-capable'
assert_contains "$TASK_MANAGER" 'completed PRとpending PR' 'interrupted delivery reports recoverable state'
assert_contains "$TASK_MANAGER" 'issue 選定、batch compatibility、conflict-risk、merge順最適化、repository全体の進捗管理を行わない' 'task-manager does not assume product-manager responsibilities'
assert_absent "$TASK_MANAGER" 'fresh integration worktree' 'no synthetic integration worktree remains'
assert_absent "$TASK_MANAGER" 'resolution reuse artifact' 'no resolution reuse artifact remains'
assert_absent "$TASK_MANAGER" 'validated combined tree hash' 'no synthetic combined tree artifact remains'
assert_absent "$TASK_MANAGER" '`AUTO_MERGE`' 'no conflict preimage artifact remains'
assert_absent "$TASK_MANAGER" '`git apply --check`' 'no resolution patch replay remains'
assert_contains "$TASK_MANAGER" 'merged batch source PR の changed-file union' 'docs scope is the merged batch file union'
assert_contains "$TASK_MANAGER" 'documentation finalization 開始時点の latest main' 'latest main is documentation truth'
assert_contains "$TASK_MANAGER" 'Added source:' 'added sources create L3 documents'
assert_contains "$TASK_MANAGER" 'Modified source:' 'modified sources update L3 documents'
assert_contains "$TASK_MANAGER" 'Deleted source:' 'deleted sources retire or remove L3 documents'
assert_contains "$TASK_MANAGER" 'Renamed source:' 'renamed sources move L3 documents and regenerate citations'
assert_contains "$TASK_MANAGER" 'relevant aggregate documentation、README、test indexes、configuration、schemas、public surfaces' 'aggregate documentation surfaces are evaluated'
assert_contains "$TASK_MANAGER" 'documentation-only updateの後にsource repository testをlocalで再実行しない' 'docs-only updates do not rerun source tests'
assert_contains "$TASK_MANAGER" '追加のユーザー承認なしでReady化し、直ちにmergeする' 'documentation PR merges without a third gate'
assert_contains "$TASK_MANAGER" '全 source PR と documentation PR の merge 確認後' 'partial completion is never success'
assert_contains "$TASK_MANAGER" 'source complete / documentation incomplete' 'documentation failure reports partial completion'
assert_contains "$TASK_MANAGER" 'standalone `/init-docs`' 'documentation failure directs standalone recovery'
assert_contains "$TASK_MANAGER" 'completion commentを投稿' 'issue completion comments have an execution step'
assert_contains "$TASK_MANAGER" 'comment投稿失敗はmerge failureにせず' 'comment failure is a manual follow-up'

# Initial constraints and strict independence.
assert_contains "$TASK_MANAGER" 'batch stateを永続化しない' 'batch state is in-memory only'
assert_contains "$TASK_MANAGER" 'cross-session resume' 'cross-session resume is explicitly out of scope'
assert_contains "$TASK_MANAGER" 'distributed lock' 'distributed locking is explicitly out of scope'
assert_contains "$TASK_MANAGER" 'GitHub Actionsへbatch stateを永続化しない' 'GitHub Actions is not a state manager'
assert_contains "$TASK_MANAGER" '上記のcommand・skillを実行、委譲、source、wrap、runtime Readしてはなりません' 'existing workflows remain prohibited runtime dependencies'
assert_absent "$TASK_MANAGER" 'commands/work.md` を Read' 'task-manager does not delegate to work.md'
assert_absent "$TASK_MANAGER" 'commands/task.md` を Read' 'task-manager does not delegate to task.md'
assert_absent "$TASK_MANAGER" '`/docs-sync` を自動実行' 'task-manager does not invoke docs-sync'
assert_absent "$TASK_MANAGER" '`/git-pr` を実行' 'task-manager does not invoke git-pr'

# Skill wiring remains narrow and does not expose task-worker publicly.
# shellcheck disable=SC2088  # Literal documentation contract must retain the installed ~ path.
assert_contains "$TASK_MANAGER_SKILL" '~/.codex/commands/task-manager.md' 'skill points to the task-manager source of truth'
assert_contains "$TASK_MANAGER_SKILL" 'one real `task-worker` sub-agent per accepted issue' 'skill preserves real worker delegation'
assert_contains "$TASK_MANAGER_SKILL" 'inherits the parent model' 'skill preserves model inheritance'
assert_contains "$TASK_MANAGER_SKILL" 'Delegate each approved source PR to `commands/git-pr-merge.md`' 'skill preserves delivery delegation'
assert_contains "$TASK_MANAGER_SKILL" 'Do not expose `task-worker` as a standalone user command or skill.' 'task-worker remains internal'
assert_absent "$TASK_MANAGER_SKILL" 'commands/work.md' 'skill does not depend on work.md'
assert_absent "$TASK_MANAGER_SKILL" 'commands/task.md' 'skill does not depend on task.md'

if ((failures > 0)); then
  printf '\n%d task-manager contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll task-manager contract tests passed.\n'
