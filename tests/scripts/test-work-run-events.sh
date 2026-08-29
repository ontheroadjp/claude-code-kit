#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="${REPO_DIR}/scripts/work-run-events.sh"
TEST_ROOT="$(mktemp -d)"

export CLAUDE_CODE_KIT_TMP_ROOT="${TEST_ROOT}/tmp"
export CLAUDE_CODE_KIT_WORK_RUN_LOG_ROOT="${TEST_ROOT}/logs/work-runs"
export CLAUDE_CODE_KIT_SESSION_ID="parent-session"

run_id=$(bash "$HELPER" --strict start issue_number=401 base_sha=72a11b564b8c6c7a5687b32035351ca580d6707c)
bash "$HELPER" --strict emit routing_result issue_number=401 route=task

CLAUDE_CODE_KIT_SESSION_ID="worker-session" bash "$HELPER" --strict attach "$run_id" \
    issue_number=401 worker_id=worker-401 branch=feat/401-work-run-observability \
    worktree="${TEST_ROOT}/worktree-401" worker_session_id=worker-session
CLAUDE_CODE_KIT_SESSION_ID="worker-session" bash "$HELPER" --strict emit \
    issue_state_changed issue_number=401 state=implementing

for sequence in $(seq 1 20); do
    bash "$HELPER" --strict emit validation_result issue_number=401 pr_number="$sequence" outcome=success &
done
wait

log_file="${CLAUDE_CODE_KIT_WORK_RUN_LOG_ROOT}/$(date -u '+%Y-%m')/${run_id}.jsonl"
jq -e -s '
  length == 24 and
  (map(.sequence) == [range(1;25)]) and
  (map(.work_run_id) | unique == [$run_id]) and
  (map(.agent_session_id) | unique | sort == ["parent-session","worker-session"])
' --arg run_id "$run_id" "$log_file" >/dev/null

if bash "$HELPER" --strict emit routing_result issue_number=401 prompt=secret 2>/dev/null; then
    printf 'FAIL: privacy-unsafe key was accepted\n' >&2
    exit 1
fi

if bash "$HELPER" --strict attach ../../escape issue_number=401 worker_id=worker 2>/dev/null; then
    printf 'FAIL: unsafe work run id was accepted\n' >&2
    exit 1
fi

before=$(wc -l < "$log_file")
bash "$HELPER" emit routing_result issue_number=bad route=task >/dev/null 2>&1
after=$(wc -l < "$log_file")
[ "$before" -eq "$after" ]

printf 'work-run event tests: ok\n'
