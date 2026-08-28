#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion strings intentionally contain literal Markdown backticks
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TASK_MANAGER="$REPO_DIR/commands/task-manager.md"
TASK_MANAGER_SKILL="$REPO_DIR/skills/task-manager/SKILL.md"

failures=0

assert_exists() {
  local file=$1 description=$2
  if [ -f "$file" ]; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

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

assert_exists "$TASK_MANAGER" 'task-manager command exists'
assert_exists "$TASK_MANAGER_SKILL" 'task-manager skill exists'

# Input and read-only preflight remain bounded.
assert_contains "$TASK_MANAGER" '/task-manager #123 #456 #789' 'three issue invocation is documented'
assert_contains "$TASK_MANAGER" '^#[1-9][0-9]*$' 'issue token validation is explicit'
assert_contains "$TASK_MANAGER" '1〜3件: 次へ進む。' 'one through three issues are accepted'
assert_contains "$TASK_MANAGER" '4件以上' 'four or more issues are rejected'
assert_contains "$TASK_MANAGER" '重複番号' 'duplicates are rejected'
assert_contains "$TASK_MANAGER" 'branch・worktree作成、file編集、commit、push、issue/PR書き込みを行いません' 'preflight is read-only'

# Each issue has a visible, independent state machine.
for state in investigating awaiting_plan_approval implementing awaiting_pr_approval delivery_eligible delivering completed failed; do
  assert_contains "$TASK_MANAGER" "$state" "state $state is defined"
done
assert_contains "$TASK_MANAGER" '承認待ち・修復・失敗は、無関係な worker' 'one issue cannot block unrelated work'
assert_contains "$TASK_MANAGER" 'worker message を到着順に処理' 'worker results are streamed rather than batched'
assert_contains "$TASK_MANAGER" 'plan を到着後すぐ提示' 'plans are presented independently'
assert_contains "$TASK_MANAGER" 'その PR をすぐ個別提示' 'Draft PRs are presented independently'
assert_absent "$TASK_MANAGER" 'complete Draft PR set' 'complete Draft set barrier is removed'
assert_absent "$TASK_MANAGER" '全planの承認' 'complete plan set barrier is removed'

# Parent investigation is handed off without routine rereads.
assert_contains "$TASK_MANAGER" 'structured investigation handoff' 'parent produces structured investigation evidence'
assert_contains "$TASK_MANAGER" 'files_and_line_ranges_read:' 'handoff records read ranges'
assert_contains "$TASK_MANAGER" 'established_facts:' 'handoff records facts'
assert_contains "$TASK_MANAGER" 'candidate_changed_files:' 'handoff records candidate files'
assert_contains "$TASK_MANAGER" 'affected_tests_and_configuration:' 'handoff records affected tests and config'
assert_contains "$TASK_MANAGER" 'unresolved_questions:' 'handoff records unknowns'
assert_contains "$TASK_MANAGER" 'stale_citation_findings:' 'handoff records stale citations'
assert_contains "$TASK_MANAGER" '`missing evidence`、`stale evidence`、`base drift`' 'rereads require a concrete reason'
assert_contains "$TASK_MANAGER" 'same worker' 'worker continuity is required by the payload'
assert_contains "$TASK_MANAGER" 'structured investigation handoff、supplemental findings、approved plan' 'replacement workers inherit investigation and approval context'

# Real workers implement work-equivalent PRs including documentation.
assert_contains "$TASK_MANAGER" '実体のある `task-worker` sub-agent' 'workers are real sub-agents'
assert_contains "$TASK_MANAGER" 'MAX_TASK_WORKERS = 3' 'worker concurrency is fixed'
assert_contains "$TASK_MANAGER" 'sub-agent model overrideを指定せず、親agentのmodelを継承する' 'workers inherit the parent model'
assert_contains "$TASK_MANAGER" 'source、tests、対応 L3 per-file docs、aggregate docs、README' 'each PR includes required documentation'
assert_contains "$TASK_MANAGER" 'gh pr create --draft' 'workers create Draft PRs'
assert_contains "$TASK_MANAGER" '<type>(#<issue-number>): <English description>' 'PR title matches task convention'
assert_contains "$TASK_MANAGER" 'documentation completeness' 'parent verifies documentation completeness'

# Delivery eligibility is independent, but merge order is fixed.
assert_contains "$TASK_MANAGER" '先行 issue がすべて `completed`' 'delivery waits only for earlier issues'
assert_contains "$TASK_MANAGER" '後続 issue が先に承認されても eligibility を保持' 'later approved PR remains eligible while waiting'
assert_contains "$TASK_MANAGER" '`commands/git-pr-merge.md` を完全に Read' 'delivery delegates to git-pr-merge'
assert_contains "$TASK_MANAGER" 'approval_source: task-manager issue-specific PR approval' 'delegation carries issue-specific approval'
assert_contains "$TASK_MANAGER" 'known_delivery_changes:' 'delegation identifies mechanical refresh commits'
assert_contains "$TASK_MANAGER" 'latest `origin/main` を取り込む' 'every PR refreshes latest main'
assert_contains "$TASK_MANAGER" 'authoritative validation' 'current head receives authoritative validation'
assert_absent "$TASK_MANAGER" 'git merge --no-ff origin/main' 'delivery mechanics are not duplicated'

# Documentation is refreshed per PR; no final documentation PR exists.
assert_contains "$TASK_MANAGER" 'current `main` の documentation state' 'per-PR docs use current main truth'
assert_contains "$TASK_MANAGER" 'その issue の source、test、documentation 変更だけ' 'final diff remains issue-local'
assert_contains "$TASK_MANAGER" 'citation line、git history、catalog/index、aggregate documentation' 'mechanical docs refresh is recognized'
assert_contains "$TASK_MANAGER" 'final batch documentation worktree、documentation PR' 'batch documentation artifacts are forbidden'
assert_absent "$TASK_MANAGER" '## Phase 5: 独立した局所documentation同期' 'legacy final docs phase is removed'
assert_absent "$TASK_MANAGER" 'documentation PR の自動delivery' 'legacy documentation delivery is removed'

# Reapproval and failure remain local.
assert_contains "$TASK_MANAGER" 'source behavior または public contract' 'material behavior changes require reapproval'
assert_contains "$TASK_MANAGER" 'design decision または security boundary' 'material design/security changes require reapproval'
assert_contains "$TASK_MANAGER" '対象 PR だけ `awaiting_pr_approval`' 'approval reset is localized'
assert_contains "$TASK_MANAGER" '後続 worker の調査、実装、Draft PR 準備を止めません' 'delivery repair does not stop unrelated preparation'
assert_contains "$TASK_MANAGER" '完了済み merge は authoritative' 'partial completion is recoverable without rollback'

# Skill wiring preserves the orchestration contract.
# shellcheck disable=SC2088  # Literal documentation contract must retain the installed ~ path.
assert_contains "$TASK_MANAGER_SKILL" '~/.codex/commands/task-manager.md' 'skill points to source of truth'
assert_contains "$TASK_MANAGER_SKILL" 'complete structured parent investigation handoff' 'skill preserves investigation handoff'
assert_contains "$TASK_MANAGER_SKILL" 'approval wait must not stop unrelated workers' 'skill preserves non-blocking approvals'
assert_contains "$TASK_MANAGER_SKILL" 'user-provided issue order' 'skill preserves fixed delivery order'
assert_contains "$TASK_MANAGER_SKILL" 'never create a final batch documentation PR' 'skill forbids batch docs PR'
assert_contains "$TASK_MANAGER_SKILL" 'Do not expose `task-worker` as a standalone user command or skill.' 'worker remains internal'

if ((failures > 0)); then
  printf '\n%d task-manager contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll task-manager contract tests passed.\n'
