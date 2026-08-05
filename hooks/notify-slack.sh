#!/bin/bash
set -euo pipefail

webhook_url="${CLAUDE_CODE_KIT_WAIT_NOTIFY_SLACK_WEBHOOK_URL:-}"
[ -z "$webhook_url" ] && exit 0

payload=$(cat)

event=$(printf '%s' "$payload" | jq -r '.hook_event_name // "Unknown"')
cwd=$(printf '%s'   "$payload" | jq -r '.cwd // ""')
session=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"')
message=$(printf '%s' "$payload" | jq -r '.message // ""')

project=$(printf '%s' "$cwd" | awk -F/ '{ for (i=NF; i>0; i--) if ($i != "") { print $i; exit } }')
[ -z "$project" ] && project="unknown"

branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || printf '%s' "unknown")
session_short=$(printf '%s' "$session" | cut -c1-8)

case "$event" in
  Notification)
    title=":bell: Claude Code: permission/input needed"
    body="${message:-Waiting for user input}"
    ;;
  Stop)
    title=":white_check_mark: Claude Code: response finished"
    body="Waiting for next instruction"
    ;;
  *)
    title=":information_source: Claude Code: $event"
    body="${message:-(no message)}"
    ;;
esac

# shellcheck disable=SC2016  # printf format string; $ must stay literal
text=$(printf '*%s*\n%s\n`%s` @ `%s` (session %s)' \
  "$title" "$body" "$project" "$branch" "$session_short")

json=$(jq -nc --arg t "$text" '{text: $t}')

curl -sS --max-time 5 -X POST \
  -H 'Content-Type: application/json' \
  --data "$json" \
  "$webhook_url" >/dev/null 2>&1 || true

exit 0
