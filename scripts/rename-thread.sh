#!/usr/bin/env bash
# Persist a Claude Code custom title for the active session.  This is best
# effort: callers continue their workflow when no Claude Code session exists.
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  printf 'Usage: %s <thread-name>\n' "$0" >&2
  exit 2
fi

if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
  exit 0
fi

project_key=$(printf '%s' "$PWD" | tr -c 'A-Za-z0-9._-' '-')
transcript_path="${HOME}/.claude/projects/${project_key}/${CLAUDE_CODE_SESSION_ID}.jsonl"

if [ ! -f "$transcript_path" ]; then
  exit 0
fi

title_json=$(jq -Rn --arg title "$1" '$title')
session_id_json=$(jq -Rn --arg session_id "$CLAUDE_CODE_SESSION_ID" '$session_id')
timestamp_json=$(jq -Rn --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '$timestamp')

printf '{"type":"custom-title","customTitle":%s,"sessionId":%s,"timestamp":%s}\n' \
  "$title_json" "$session_id_json" "$timestamp_json" >>"$transcript_path"
