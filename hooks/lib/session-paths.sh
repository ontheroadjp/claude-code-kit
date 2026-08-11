#!/bin/bash
# Resolves session-scoped filesystem paths for commands/*.md workflows.
#
# Invoked directly (not sourced) so that commands/*.md can obtain an
# absolute path with a single plain command line containing no brace
# expansion (${VAR}) and no command-substitution-into-assignment ($(...)).
# Both constructs are unconditionally rejected by the Claude Code harness's
# worktree-isolation guard when running inside a worktree-isolated session
# (issue #316), regardless of what the command actually does.
#
# Usage: session-paths.sh <session-approved|session-tmp-dir>
set -euo pipefail

_SCRIPT="${BASH_SOURCE[0]}"
[ -L "$_SCRIPT" ] && _SCRIPT="$(readlink "$_SCRIPT")"
SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT")" && pwd)"

# shellcheck source=hooks/lib/session-id.sh
. "${SCRIPT_DIR}/session-id.sh"

case "${1:-}" in
    session-approved)
        SESSION_ID="$(session_id_resolve "")"
        STATE_ROOT="${CLAUDE_CODE_KIT_STATE_HOME:-${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code-kit}"
        SESSION_DIR="${CLAUDE_CODE_KIT_SESSION_DIR:-${STATE_ROOT}/sessions/${SESSION_ID}}"
        printf '%s\n' "${CLAUDE_CODE_KIT_SESSION_APPROVED_FILE:-${SESSION_DIR}/session-approved}"
        ;;
    session-tmp-dir)
        SESSION_ID="$(session_id_resolve "")"
        SESSION_TMP_ROOT="${CLAUDE_CODE_KIT_TMP_ROOT:-/tmp/claude-code-kit}"
        printf '%s\n' "${SESSION_TMP_ROOT}/${SESSION_ID}"
        ;;
    *)
        echo "usage: session-paths.sh <session-approved|session-tmp-dir>" >&2
        exit 1
        ;;
esac
