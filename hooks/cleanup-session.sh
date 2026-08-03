#!/bin/bash
# Stop hook: delete the current AI session approval file and temp directory
set -euo pipefail

payload=$(cat)

HOOK_INVOKED_PATH="${BASH_SOURCE[0]}"
_SCRIPT="$HOOK_INVOKED_PATH"
[ -L "$_SCRIPT" ] && _SCRIPT="$(readlink "$_SCRIPT")"
REPO_DIR="$(cd "$(dirname "$_SCRIPT")/.." && pwd)"

# shellcheck source=hooks/lib/session-id.sh
. "${REPO_DIR}/hooks/lib/session-id.sh"

STATE_ROOT="${CLAUDE_CODE_KIT_STATE_HOME:-${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code-kit}"
SESSION_ID="$(session_id_resolve "$payload")"
SESSION_DIR="${CLAUDE_CODE_KIT_SESSION_DIR:-${STATE_ROOT}/sessions/${SESSION_ID}}"
SESSION_APPROVED_FILE="${CLAUDE_CODE_KIT_SESSION_APPROVED_FILE:-${SESSION_DIR}/session-approved}"

[ -f "$SESSION_APPROVED_FILE" ] && rm -f "$SESSION_APPROVED_FILE"
case "$SESSION_DIR" in
    "$STATE_ROOT"/sessions/*) rmdir "$SESSION_DIR" 2>/dev/null || true ;;
esac
exit 0
