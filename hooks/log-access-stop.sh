#!/bin/bash
# Stop: write formatted access log entry if /work was invoked this session

payload=$(cat)
session_id=$(echo "$payload" | jq -r '.session_id // empty')

[ -z "$session_id" ] && exit 0

SESSION_DIR="/tmp/claude-access-sessions"
STATE_FILE="${SESSION_DIR}/${session_id}.json"

[ ! -f "$STATE_FILE" ] && exit 0

state=$(cat "$STATE_FILE")
start_time=$(echo "$state"        | jq -r '.start_time')
user_instruction=$(echo "$state"  | jq -r '.user_instruction')
work_files=$(echo "$state"          | jq -r '.work_files[]' 2>/dev/null || true)
task_files=$(echo "$state"          | jq -r '.task_files[]' 2>/dev/null || true)
patch_files=$(echo "$state"         | jq -r '.patch_files[]' 2>/dev/null || true)
docs_sync_files=$(echo "$state"     | jq -r '.docs_sync_files[]' 2>/dev/null || true)
init_docs_files=$(echo "$state"     | jq -r '.init_docs_files[]' 2>/dev/null || true)
modified_files=$(echo "$state"      | jq -r '.modified_files[]' 2>/dev/null || true)

LOG_DIR="${HOME}/dev/src/github.com/ontheroadjp/claude-code-kit/logs/$(date '+%Y-%m')"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/access.log"

format_list() {
  local items="$1"
  if [ -n "$items" ]; then
    echo "$items" | while IFS= read -r f; do echo "- $f"; done
  fi
}

{
  printf '\n---\n\n'
  printf '[日時]\n%s\n\n' "$start_time"
  printf '[ユーザーからの指示内容]\n%s\n\n' "$user_instruction"
  printf '[work]\n'; format_list "$work_files"; printf '\n'
  printf '[task]\n'; format_list "$task_files"; printf '\n'
  printf '[patch]\n'; format_list "$patch_files"; printf '\n'
  printf '[docs-sync]\n'; format_list "$docs_sync_files"; printf '\n'
  printf '[init-docs]\n'; format_list "$init_docs_files"; printf '\n'
  printf '[修正したファイル]\n'; format_list "$modified_files"; printf '\n'
} >> "$LOG_FILE"

rm -f "$STATE_FILE" "${SESSION_DIR}/${session_id}.prompt"
