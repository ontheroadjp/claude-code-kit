#!/bin/bash
# PostToolUse: track file access per phase (work/task/patch)

payload=$(cat)
session_id=$(echo "$payload" | jq -r '.session_id // empty')
tool_name=$(echo "$payload" | jq -r '.tool_name // empty')
tool_input=$(echo "$payload" | jq -c '.tool_input // {}')

[ -z "$session_id" ] || [ -z "$tool_name" ] && exit 0

SESSION_DIR="/tmp/claude-access-sessions"
STATE_FILE="${SESSION_DIR}/${session_id}.json"
PROMPT_FILE="${SESSION_DIR}/${session_id}.prompt"

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
file_path=$(echo "$file_path" | sed "s|${HOME}|~|g")
basename_file=$(basename "$file_path")

# Initialize session state on first work.md read
if [ ! -f "$STATE_FILE" ]; then
  [ "$basename_file" != "work.md" ] && exit 0
  prompt=""
  [ -f "$PROMPT_FILE" ] && prompt=$(cat "$PROMPT_FILE")
  timestamp=$(date '+%Y.%m.%d %H.%M')
  mkdir -p "$SESSION_DIR"
  jq -n \
    --arg t "$timestamp" \
    --arg p "$prompt" \
    '{start_time:$t, user_instruction:$p, current_phase:"work",
      work_files:[], task_files:[], patch_files:[],
      docs_sync_files:[], init_docs_files:[], modified_files:[]}' \
    > "$STATE_FILE"
fi

state=$(cat "$STATE_FILE")

# Phase switching on command file reads
case "$basename_file" in
  work.md)       state=$(echo "$state" | jq '.current_phase="work"') ;;
  task.md)       state=$(echo "$state" | jq '.current_phase="task"') ;;
  patch.md)      state=$(echo "$state" | jq '.current_phase="patch"') ;;
  docs-sync.md)  state=$(echo "$state" | jq '.current_phase="docs_sync"') ;;
  init-docs.md)  state=$(echo "$state" | jq '.current_phase="init_docs"') ;;
esac

# Append to appropriate list (deduplicated)
if [[ "$tool_name" == "Edit" || "$tool_name" == "Write" ]]; then
  state=$(echo "$state" | jq --arg f "$file_path" \
    '.modified_files = (.modified_files + [$f] | unique)')
else
  phase=$(echo "$state" | jq -r '.current_phase')
  state=$(echo "$state" | jq --arg f "$file_path" --arg k "${phase}_files" \
    '.[$k] = (.[$k] + [$f] | unique)')
fi

echo "$state" > "$STATE_FILE"
