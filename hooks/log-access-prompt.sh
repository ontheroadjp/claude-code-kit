#!/bin/bash
# UserPromptSubmit: save latest prompt for session correlation; flush orphaned pending logs
set -euo pipefail

payload=$(cat)
session_id=$(echo "$payload" | jq -r '.session_id // empty')
prompt=$(echo "$payload" | jq -r '.prompt // ""')

[ -z "$session_id" ] && exit 0

SESSION_DIR="/tmp/claude-access-sessions"
mkdir -p "$SESSION_DIR"
printf '%s' "$prompt" > "${SESSION_DIR}/${session_id}.prompt"

STATE_FILE="${SESSION_DIR}/${session_id}.json"

_get_log_file() {
  local script="${BASH_SOURCE[0]}"
  [ -L "$script" ] && script="$(readlink "$script")"
  local repo_dir
  repo_dir="$(cd "$(dirname "$script")/.." && pwd)"
  local log_dir="${repo_dir}/logs/access"
  mkdir -p "$log_dir"
  echo "${log_dir}/$(date '+%Y-%m').log"
}

if [ ! -f "$STATE_FILE" ]; then
  # New session: flush any orphaned pending files from previous sessions
  for pending_file in "${SESSION_DIR}"/*.pending; do
    [ -f "$pending_file" ] || continue
    pending_session=$(basename "$pending_file" .pending)
    [ "$pending_session" = "$session_id" ] && continue
    LOG_FILE=$(_get_log_file)
    cat "$pending_file" >> "$LOG_FILE"
    rm -f "$pending_file"
    # Also clean up the orphaned state and prompt files
    rm -f "${SESSION_DIR}/${pending_session}.json" \
          "${SESSION_DIR}/${pending_session}.prompt"
  done

  timestamp=$(date '+%Y.%m.%d %H.%M')
  jq -n \
    --arg t "$timestamp" \
    --arg p "$prompt" \
    '{start_time:$t, user_instruction:$p, current_phase:"work",
      seq:0, accesses:[], modified_files:[]}' \
    > "$STATE_FILE"
fi
