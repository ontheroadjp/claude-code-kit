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
assert_contains "$TASK_MANAGER" '#<issue-number> <English title>' 'source PR titles match the work task flow format'
assert_contains "$TASK_MANAGER" 'documentation変更を含まない' 'source PRs exclude documentation'

# Batch review, actual-branch sequential refresh, and automatic docs delivery.
assert_contains "$TASK_MANAGER" 'complete Draft PR setを再提示' 'Draft rejection loops over the complete set'
assert_contains "$TASK_MANAGER" '承認時点の全source PR番号とhead SHA' 'batch approval fixes reviewed PR heads'
assert_contains "$TASK_MANAGER" 'source PRを入力順に1本ずつ処理' 'source PRs merge in input order'
assert_contains "$TASK_MANAGER" '最初のPRを含む各source PR' 'every source PR is refreshed, including the first'
assert_contains "$TASK_MANAGER" 'actual PR branchをcheckout' 'refresh operates on the actual source PR branch'
assert_contains "$TASK_MANAGER" 'normal non-rewriting merge' 'latest main is incorporated without history rewriting'
assert_contains "$TASK_MANAGER" 'actual branch上で一度だけ解消' 'conflicts are resolved once on the actual branch'
assert_contains "$TASK_MANAGER" 'focusedしたtestだけを実行' 'conflict repairs run focused tests'
assert_contains "$TASK_MANAGER" 'clean base refreshでは' 'clean refreshes have an explicit validation rule'
assert_contains "$TASK_MANAGER" 'local fallbackとして実行' 'missing CI coverage has a local fallback'
assert_contains "$TASK_MANAGER" 'missing、skipped、対応不明のvalidationをpassとして扱わない' 'missing validation is never treated as passing'
assert_contains "$TASK_MANAGER" 'required GitHub checksの完了を待ち' 'required checks validate the pushed head'
assert_contains "$TASK_MANAGER" 'latest main SHAがStep 1で記録した値から進んでいれば' 'main drift restarts refresh validation'
assert_contains "$TASK_MANAGER" 'expected head SHAと一致することをguard' 'the expected PR head is guarded before merge'
assert_contains "$TASK_MANAGER" '対象PRだけをReady化' 'only the next source PR becomes ready'
assert_contains "$TASK_MANAGER" 'merge API resultをauthoritative' 'the merge operation is the authoritative result'
assert_contains "$TASK_MANAGER" 'refresh loopへ戻る' 'base drift or merge rejection retries the refresh loop'
assert_contains "$TASK_MANAGER" 'latest mainへ反映されたこと' 'merged state is confirmed on main before advancing'
assert_contains "$TASK_MANAGER" 'materialに変える場合' 'material repairs return to the Draft set gate'
assert_absent "$TASK_MANAGER" 'fresh integration worktree' 'no synthetic integration worktree remains'
assert_absent "$TASK_MANAGER" 'resolution reuse artifact' 'no resolution reuse artifact remains'
assert_absent "$TASK_MANAGER" 'validated combined tree hash' 'no synthetic combined tree artifact remains'
assert_absent "$TASK_MANAGER" '`AUTO_MERGE`' 'no conflict preimage artifact remains'
assert_absent "$TASK_MANAGER" '`git apply --check`' 'no resolution patch replay remains'
assert_contains "$TASK_MANAGER" '`mergeable`値を事前条件としてpollしない' 'mergeable polling is not a prerequisite'
assert_contains "$TASK_MANAGER" 'merged batch source PR の changed-file union' 'docs scope is the merged batch file union'
assert_contains "$TASK_MANAGER" 'documentation finalization 開始時点の latest main' 'latest main is documentation truth'
assert_contains "$TASK_MANAGER" 'documentation-only updateの後にsource repository testをlocalで再実行しない' 'docs-only updates do not rerun source tests'
assert_contains "$TASK_MANAGER" '追加のユーザー承認なしでReady化し、直ちにmergeする' 'documentation PR merges without a third gate'
assert_contains "$TASK_MANAGER" '全 source PR と documentation PR の merge 確認後' 'partial completion is never success'

# Initial constraints and strict independence.
assert_contains "$TASK_MANAGER" 'batch stateを永続化しない' 'batch state is in-memory only'
assert_contains "$TASK_MANAGER" 'cross-session resume' 'cross-session resume is explicitly out of scope'
assert_contains "$TASK_MANAGER" 'distributed lock' 'distributed locking is explicitly out of scope'
assert_contains "$TASK_MANAGER" 'GitHub Actionsへbatch stateを永続化しない' 'GitHub Actions is not a state manager'
assert_contains "$TASK_MANAGER" '上記の command・skill を実行、委譲、source、wrap、runtime Read してはなりません' 'existing workflows are prohibited runtime dependencies'
assert_absent "$TASK_MANAGER" 'commands/work.md` を Read' 'task-manager does not delegate to work.md'
assert_absent "$TASK_MANAGER" 'commands/task.md` を Read' 'task-manager does not delegate to task.md'
assert_absent "$TASK_MANAGER" '`/docs-sync` を自動実行' 'task-manager does not invoke docs-sync'
assert_absent "$TASK_MANAGER" '`/git-pr` を実行' 'task-manager does not invoke git-pr'

# Skill wiring remains narrow and does not expose task-worker publicly.
# shellcheck disable=SC2088  # Literal documentation contract must retain the installed ~ path.
assert_contains "$TASK_MANAGER_SKILL" '~/.codex/commands/task-manager.md' 'skill points to the task-manager source of truth'
assert_contains "$TASK_MANAGER_SKILL" 'one real `task-worker` sub-agent per accepted issue' 'skill preserves real worker delegation'
assert_contains "$TASK_MANAGER_SKILL" 'inherits the parent model' 'skill preserves model inheritance'
assert_contains "$TASK_MANAGER_SKILL" 'Do not expose `task-worker` as a standalone user command or skill.' 'task-worker remains internal'
assert_absent "$TASK_MANAGER_SKILL" 'commands/work.md' 'skill does not depend on work.md'
assert_absent "$TASK_MANAGER_SKILL" 'commands/task.md' 'skill does not depend on task.md'

if ((failures > 0)); then
  printf '\n%d task-manager contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll task-manager contract tests passed.\n'
