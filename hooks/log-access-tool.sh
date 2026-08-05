#!/bin/bash
# PostToolUse: track file access order and duplicates per phase (work/task/patch)
set -euo pipefail

payload=$(cat)
session_id=$(echo "$payload" | jq -r '.session_id // empty')
tool_name=$(echo "$payload" | jq -r '.tool_name // empty')
tool_input=$(echo "$payload" | jq -c '.tool_input // {}')

[ -z "$session_id" ] || [ -z "$tool_name" ] && exit 0

SESSION_DIR="/tmp/claude-access-sessions"
STATE_FILE="${SESSION_DIR}/${session_id}.json"
PENDING_FILE="${SESSION_DIR}/${session_id}.pending"

# Extract relevant path by tool type
case "$tool_name" in
  Read)  file_path=$(echo "$tool_input" | jq -r '.file_path // empty') ;;
  Glob)  file_path=$(echo "$tool_input" | jq -r '.pattern // empty') ;;
  Grep)  file_path=$(echo "$tool_input" | jq -r '.path // empty') ;;
  Edit|Write) file_path=$(echo "$tool_input" | jq -r '.file_path // empty') ;;
  *) exit 0 ;;
esac

[ -z "$file_path" ] && exit 0

# Normalize home directory
file_path=${file_path//$HOME/\~}
basename_file=$(basename "$file_path")

# State file is initialized by log-access-prompt.sh on UserPromptSubmit
[ ! -f "$STATE_FILE" ] && exit 0

state=$(cat "$STATE_FILE")

_get_log_file() {
  local script="${BASH_SOURCE[0]}"
  [ -L "$script" ] && script="$(readlink "$script")"
  local repo_dir
  repo_dir="$(cd "$(dirname "$script")/.." && pwd)"
  local log_dir="${repo_dir}/logs/access"
  mkdir -p "$log_dir"
  echo "${log_dir}/$(date '+%Y-%m').log"
}

# Phase switching on command file reads
case "$basename_file" in
  work.md)
    existing_seq=$(echo "$state" | jq '.seq')
    if [ "$existing_seq" -gt 0 ] && [ -f "$PENDING_FILE" ]; then
      # New /work starting while previous session has data: flush pending to main log
      LOG_FILE=$(_get_log_file)
      cat "$PENDING_FILE" >> "$LOG_FILE"
      rm -f "$PENDING_FILE"
      # Reset state for the new /work session
      latest_prompt=$(cat "${SESSION_DIR}/${session_id}.prompt" 2>/dev/null || echo "")
      timestamp=$(date '+%Y.%m.%d %H.%M')
      state=$(jq -n \
        --arg t "$timestamp" \
        --arg p "$latest_prompt" \
        '{start_time:$t, user_instruction:$p, current_phase:"work",
          seq:0, accesses:[], modified_files:[]}')
    else
      state=$(echo "$state" | jq '.current_phase="work"')
    fi
    ;;
  task.md)       state=$(echo "$state" | jq '.current_phase="task"') ;;
  patch.md)      state=$(echo "$state" | jq '.current_phase="patch"') ;;
  docs-sync.md)  state=$(echo "$state" | jq '.current_phase="docs_sync"') ;;
  init-docs.md)  state=$(echo "$state" | jq '.current_phase="init_docs"') ;;
esac

# Append to accesses (with sequence) or modified_files
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
  state=$(echo "$state" | jq --arg f "$file_path" \
    '.modified_files = (.modified_files + [$f] | unique)')
else
  state=$(echo "$state" | jq \
    --arg f "$file_path" \
    --arg t "$tool_name" \
    '.seq += 1 |
     .accesses += [{seq:.seq, phase:.current_phase, tool:$t, path:$f}]')
fi

echo "$state" > "$STATE_FILE"
