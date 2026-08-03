#!/bin/bash
# Shared session ID resolution helpers for hooks/auto-approve-readonly.sh and hooks/cleanup-session.sh.

session_id_sanitize() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

session_id_hash_key() {
    local key="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$key" | sha256sum | cut -c1-16
    else
        printf '%s' "$key" | cksum | awk '{print $1}'
    fi
}

# Resolves the current session id. $1 is an optional raw PreToolUse/Stop hook payload
# JSON string; omit it when calling from a context with no hook payload.
#
# Priority:
#   1. CLAUDE_CODE_KIT_SESSION_ID    - test/override hook
#   2. CLAUDE_CODE_SESSION_ID        - Claude Code's own session id env var, present in
#                                      both the hook process and any Bash-tool-invoked shell
#   3. payload.session_id            - Claude Code hook payload (hook context only)
#   4. hash of payload.transcript_path (hook context only)
#   5. hash of CODEX_THREAD_ID       - Codex CLI
#   6. process-<PPID> fallback (weak; callers must treat this as unresolved)
session_id_resolve() {
    local payload="${1:-}" session_id transcript_path
    session_id="${CLAUDE_CODE_KIT_SESSION_ID:-}"
    [ -z "$session_id" ] && session_id="${CLAUDE_CODE_SESSION_ID:-}"
    if [ -z "$session_id" ] && [ -n "$payload" ]; then
        session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty')
    fi
    if [ -z "$session_id" ] && [ -n "$payload" ]; then
        transcript_path=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
        [ -n "$transcript_path" ] && session_id="transcript-$(session_id_hash_key "$transcript_path")"
    fi
    if [ -z "$session_id" ] && [ -n "${CODEX_THREAD_ID:-}" ]; then
        session_id="codex-$(session_id_hash_key "${CODEX_THREAD_ID}")"
    fi
    if [ -z "$session_id" ]; then
        session_id="process-${PPID:-$$}"
    fi
    session_id_sanitize "$session_id"
}
