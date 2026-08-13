#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCRIPT="$REPO_DIR/scripts/rename-thread.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

WORKSPACE="$TMP_DIR/workspace"
HOME_DIR="$TMP_DIR/home"
SESSION_ID='12345678-1234-1234-1234-123456789abc'
mkdir -p "$WORKSPACE"

project_key=$(printf '%s' "$WORKSPACE" | tr -c 'A-Za-z0-9._-' '-')
transcript="$HOME_DIR/.claude/projects/$project_key/$SESSION_ID.jsonl"
mkdir -p "$(dirname "$transcript")"
printf '{"type":"user"}\n' >"$transcript"

(
  cd "$WORKSPACE"
  HOME="$HOME_DIR" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$SCRIPT" 'fix/rename-thread-script'
)

jq -e --arg title 'fix/rename-thread-script' --arg session "$SESSION_ID" '
  select(.type == "custom-title")
  | .customTitle == $title and .sessionId == $session and (.timestamp | type == "string")
' "$transcript" >/dev/null

before_lines=$(wc -l <"$transcript")
(
  cd "$WORKSPACE"
  HOME="$HOME_DIR" "$SCRIPT" 'ignored-without-session'
)
after_lines=$(wc -l <"$transcript")
if [ "$before_lines" -ne "$after_lines" ]; then
  printf 'FAIL: script changed a transcript without CLAUDE_CODE_SESSION_ID\n'
  exit 1
fi

if (
  cd "$WORKSPACE"
  HOME="$HOME_DIR" CLAUDE_CODE_SESSION_ID="$SESSION_ID" "$SCRIPT" ''
); then
  printf 'FAIL: empty title unexpectedly succeeded\n'
  exit 1
fi

printf 'All rename-thread tests passed.\n'
