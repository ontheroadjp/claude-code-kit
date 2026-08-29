#!/bin/bash
# Best-effort semantic event writer for one logical /work run.
# Logging must never alter the workflow, so normal mode deliberately returns 0.

set -uo pipefail

STRICT=0
if [ "${1:-}" = "--strict" ]; then
    STRICT=1
    shift
fi

fail() {
    printf 'work-run-events: %s\n' "$1" >&2
    if [ "$STRICT" -eq 1 ]; then
        exit 1
    fi
    exit 0
}

SCRIPT_PATH="${BASH_SOURCE[0]}"
[ -L "$SCRIPT_PATH" ] && SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
REPO_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)" || fail "cannot resolve repository"
# shellcheck source=hooks/lib/session-id.sh
. "${REPO_DIR}/hooks/lib/session-id.sh" || fail "cannot load session id helper"

SESSION_ID="$(session_id_resolve "")" || fail "cannot resolve agent session"
SESSION_TMP_ROOT="${CLAUDE_CODE_KIT_TMP_ROOT:-/tmp/claude-code-kit}"
CONTEXT_DIR="${SESSION_TMP_ROOT}/${SESSION_ID}"
CONTEXT_FILE="${CONTEXT_DIR}/work-run-context.json"

safe_token() {
    [[ "$1" =~ ^[A-Za-z0-9._/@:+-]{1,240}$ ]]
}

is_run_id() {
    [[ "$1" =~ ^[0-9a-f]{24}$ ]]
}

is_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

is_sha() {
    [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

allowed_event() {
    case "$1" in
        run_started|gate_result|routing_result|worker_registered|issue_state_changed|approval_wait_started|approval_wait_finished|pr_created|approved_head_recorded|main_refresh_result|validation_result|delivery_result|docs_sync_result|cleanup_result|run_finished) return 0 ;;
        *) return 1 ;;
    esac
}

allowed_key() {
    local event="$1"
    local key="$2"
    case "${event}:${key}" in
        run_started:issue_number|run_started:base_sha|gate_result:issue_number|gate_result:outcome|gate_result:reason_code|routing_result:issue_number|routing_result:route|worker_registered:issue_number|worker_registered:worker_id|worker_registered:branch|worker_registered:worktree|worker_registered:worker_session_id|issue_state_changed:issue_number|issue_state_changed:state|approval_wait_started:issue_number|approval_wait_started:approval_kind|approval_wait_finished:issue_number|approval_wait_finished:approval_kind|approval_wait_finished:outcome|pr_created:issue_number|pr_created:pr_number|pr_created:pr_url|pr_created:head_sha|approved_head_recorded:issue_number|approved_head_recorded:pr_number|approved_head_recorded:head_sha|main_refresh_result:issue_number|main_refresh_result:pr_number|main_refresh_result:outcome|main_refresh_result:conflict_count|validation_result:issue_number|validation_result:pr_number|validation_result:outcome|delivery_result:issue_number|delivery_result:pr_number|delivery_result:outcome|delivery_result:head_sha|docs_sync_result:issue_number|docs_sync_result:outcome|cleanup_result:outcome|cleanup_result:remaining_worktrees|cleanup_result:stash_restored|run_finished:outcome|run_finished:reason_code) return 0 ;;
        *) return 1 ;;
    esac
}

validate_value() {
    local key="$1"
    local value="$2"
    case "$key" in
        issue_number|pr_number|conflict_count|remaining_worktrees) is_integer "$value" ;;
        base_sha|head_sha) is_sha "$value" ;;
        outcome) [[ "$value" =~ ^(success|failed|stopped|interrupted|incomplete|approved|rejected|conflict|clean|dirty|skipped)$ ]] ;;
        reason_code) [[ "$value" =~ ^(none|input_gate|repository_gate|issue_gate|workspace_gate|user_stopped|worker_failed|delivery_failed|cleanup_incomplete|external_interruption|logging_unavailable)$ ]] ;;
        route) [[ "$value" =~ ^(task|patch|task_manager|mtg|hazard_triage|stop)$ ]] ;;
        state) [[ "$value" =~ ^(investigating|awaiting_plan_approval|implementing|awaiting_pr_approval|delivery_eligible|delivering|completed|failed)$ ]] ;;
        approval_kind) [[ "$value" =~ ^(plan|implementation|pr|repair)$ ]] ;;
        stash_restored) [[ "$value" =~ ^(true|false|not_applicable)$ ]] ;;
        worker_id|branch|worker_session_id) safe_token "$value" ;;
        worktree) [[ "$value" = /* ]] && [ "${#value}" -le 500 ] && [[ "$value" != *$'\n'* ]] ;;
        pr_url) [[ "$value" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+$ ]] ;;
        *) return 1 ;;
    esac
}

new_run_id() {
    printf '%s' "${SESSION_ID}:$(date -u '+%Y%m%dT%H%M%S.%N'):${BASHPID}:${RANDOM}" \
        | sha256sum | cut -c1-24
}

write_context() {
    local run_id="$1"
    mkdir -p "$CONTEXT_DIR" || return 1
    jq -n --arg run_id "$run_id" --arg session_id "$SESSION_ID" \
        '{run_id:$run_id, agent_session_id:$session_id}' > "${CONTEXT_FILE}.tmp" || return 1
    mv "${CONTEXT_FILE}.tmp" "$CONTEXT_FILE"
}

read_run_id() {
    [ -f "$CONTEXT_FILE" ] || return 1
    jq -er '.run_id' "$CONTEXT_FILE"
}

acquire_lock() {
    local lock_dir="$1"
    local attempt_count=0
    while [ "$attempt_count" -lt 100 ]; do
        if mkdir "$lock_dir" 2>/dev/null; then
            return 0
        fi
        sleep 0.01
        attempt_count=$((attempt_count + 1))
    done
    return 1
}

append_event() {
    local run_id="$1"
    local event="$2"
    shift 2
    local log_root="${CLAUDE_CODE_KIT_WORK_RUN_LOG_ROOT:-${REPO_DIR}/logs/work-runs}"
    local log_dir
    log_dir="${log_root}/$(date -u '+%Y-%m')"
    local log_file="${log_dir}/${run_id}.jsonl"
    local lock_dir="${log_file}.lock"
    local payload='{}'
    local pair key value

    allowed_event "$event" || return 1
    for pair in "$@"; do
        [[ "$pair" == *=* ]] || return 1
        key="${pair%%=*}"
        value="${pair#*=}"
        allowed_key "$event" "$key" || return 1
        validate_value "$key" "$value" || return 1
        if is_integer "$value" && [[ "$key" =~ ^(issue_number|pr_number|conflict_count|remaining_worktrees)$ ]]; then
            payload="$(jq -c --arg key "$key" --argjson value "$value" '. + {($key):$value}' <<< "$payload")" || return 1
        elif [ "$key" = "stash_restored" ]; then
            payload="$(jq -c --arg key "$key" --arg value "$value" '. + {($key):$value}' <<< "$payload")" || return 1
        else
            payload="$(jq -c --arg key "$key" --arg value "$value" '. + {($key):$value}' <<< "$payload")" || return 1
        fi
    done

    mkdir -p "$log_dir" || return 1
    acquire_lock "$lock_dir" || return 1
    local sequence=1
    if [ -s "$log_file" ]; then
        local previous_sequence
        previous_sequence="$(tail -n 1 "$log_file" | jq -er '.sequence')" || {
            rmdir "$lock_dir"
            return 1
        }
        is_integer "$previous_sequence" || {
            rmdir "$lock_dir"
            return 1
        }
        sequence="$((previous_sequence + 1))"
    fi
    local record
    record="$(jq -cn \
        --arg schema_version "1" \
        --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" \
        --arg run_id "$run_id" \
        --arg event "$event" \
        --arg session_id "$SESSION_ID" \
        --argjson sequence "$sequence" \
        --argjson data "$payload" \
        '{schema_version:$schema_version,timestamp:$timestamp,work_run_id:$run_id,sequence:$sequence,event:$event,agent_session_id:$session_id} + $data')" || {
        rmdir "$lock_dir"
        return 1
    }
    printf '%s\n' "$record" >> "$log_file" || {
        rmdir "$lock_dir"
        return 1
    }
    rmdir "$lock_dir"
}

command_start() {
    local run_id
    run_id="$(new_run_id)" || return 1
    write_context "$run_id" || return 1
    append_event "$run_id" run_started "$@" || return 1
    printf '%s\n' "$run_id"
}

command_attach() {
    local run_id="${1:-}"
    shift || true
    is_run_id "$run_id" || return 1
    write_context "$run_id" || return 1
    append_event "$run_id" worker_registered "$@"
}

command_emit() {
    local event="${1:-}"
    shift || true
    local run_id
    run_id="$(read_run_id)" || return 1
    append_event "$run_id" "$event" "$@"
}

case "${1:-}" in
    start)
        shift
        command_start "$@" || fail "start failed"
        ;;
    attach)
        shift
        command_attach "$@" || fail "attach failed"
        ;;
    emit)
        shift
        command_emit "$@" || fail "emit failed"
        ;;
    current)
        read_run_id || fail "no active work run"
        ;;
    *) fail "usage: work-run-events.sh [--strict] <start|attach|emit|current> [arguments]" ;;
esac

exit 0
