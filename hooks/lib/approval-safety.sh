#!/bin/bash
# Shared PreToolUse Bash safety checks.

approval_safety_is_force_push() {
    local command="$1"

    printf '%s' "$command" | grep -qE '\bgit\b[^#]*\bpush\b[^#]*([[:space:]]--force([=-][^[:space:]]*)?([[:space:]]|$)|[[:space:]]-[^-[:space:]]*f[^[:space:]]*([[:space:]]|$)|[[:space:]]\+[^[:space:]]+)'
}

approval_safety_is_force_checkout() {
    local command="$1"

    printf '%s' "$command" | grep -qE '\bgit\b[^#]*\b(checkout|switch)\b[^#]*([[:space:]]--force([=[:space:]]|$)|[[:space:]]-[^-[:space:]]*f[^[:space:]]*([[:space:]]|$))'
}

approval_safety_is_force_branch_delete() {
    local command="$1" branch_segment

    while IFS= read -r branch_segment; do
        printf '%s' "$branch_segment" | grep -qE '[[:space:]]-[^-[:space:]]*D[^[:space:]]*([[:space:]]|$)' && return 0
        printf '%s' "$branch_segment" | grep -qE '[[:space:]]-[^-[:space:]]*(d[^[:space:]]*f|f[^[:space:]]*d)[^[:space:]]*([[:space:]]|$)' && return 0

        if printf '%s' "$branch_segment" | grep -qE '([[:space:]]--delete([=[:space:]]|$)|[[:space:]]-d([[:space:]]|$))' \
            && printf '%s' "$branch_segment" | grep -qE '([[:space:]]--force([=[:space:]]|$)|[[:space:]]-f([[:space:]]|$))'; then
            return 0
        fi
    done < <(printf '%s' "$command" | grep -oE '\bgit\b[^;&|#]*\bbranch\b[^;&|#]*' || true)

    return 1
}

approval_safety_destructive_reason() {
    local command="$1"

    if printf '%s' "$command" | grep -qE 'rm\s[^#]*((-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\s+/+($|\s)|(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\s+~/?(\s|$)|(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\s+/(etc|usr|var|bin|sbin|lib|lib64|boot|home|root|dev|proc|sys)(/|\s|$))'; then
        printf '%s\n' "rm -rf targeting system directory detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bdd\b[^#]*\bof=/dev/'; then
        printf '%s\n' "dd writing to block device detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bshred\b[^#]*/dev/'; then
        printf '%s\n' "shred targeting block device detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '(^|\s)wipefs(\s|$)'; then
        printf '%s\n' "wipefs (filesystem signature wipe) detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\btruncate\b[^#]*-s\s*0[^#]*/dev/'; then
        printf '%s\n' "truncate -s 0 targeting block device detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '(^|\s)mkfs(\.|(\s))'; then
        printf '%s\n' "mkfs (filesystem creation/overwrite) detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qF ':(){ :|:& };:'; then
        printf '%s\n' "fork bomb detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\b(chmod|chown)\b[^#]*-[a-zA-Z]*R[a-zA-Z]*\s+/+($|\s)'; then
        printf '%s\n' "chmod/chown -R on filesystem root detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\b(chmod|chown)\b[^#]*-[a-zA-Z]*R[a-zA-Z]*\s+/(etc|usr|var|bin|sbin|lib|lib64|boot|home|root|dev|proc|sys)(/|\s|$)'; then
        printf '%s\n' "chmod/chown -R on system directory detected"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bgit\b[^#]*(filter-branch|filter-repo)\b'; then
        printf '%s\n' "git history rewrite (filter-branch/filter-repo) detected"
        return 0
    fi
    if approval_safety_is_force_push "$command"; then
        printf '%s\n' "git force push may overwrite remote history"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bgit\b[^#]*\breset\b[^#]*--hard\b'; then
        printf '%s\n' "git reset --hard discards all uncommitted changes"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bgit\b[^#]*\bcheckout\b[^#]*(^|\s)\.((\s)|$)'; then
        printf '%s\n' "git checkout . discards uncommitted changes"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bgit\b[^#]*\bcheckout\b[^#]*--\s+\.'; then
        printf '%s\n' "git checkout -- . discards uncommitted changes"
        return 0
    fi
    if approval_safety_is_force_checkout "$command"; then
        printf '%s\n' "git checkout/switch --force may discard uncommitted changes"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bgit\b[^#]*\brestore\b[^#]*(^|\s)\.((\s)|$)'; then
        printf '%s\n' "git restore . discards uncommitted changes"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bgit\b[^#]*\bclean\b[^#]*-[a-zA-Z]*f[a-zA-Z]*d[a-zA-Z]*\b'; then
        printf '%s\n' "git clean -fd permanently removes untracked files"
        return 0
    fi
    if approval_safety_is_force_branch_delete "$command"; then
        printf '%s\n' "git branch force delete permanently deletes a branch"
        return 0
    fi
    if printf '%s' "$command" | grep -qE '\bgit\b[^#]*\bstash\b[^#]*\b(drop|clear)\b'; then
        printf '%s\n' "git stash drop/clear permanently destroys stashed changes"
        return 0
    fi

    return 1
}

approval_safety_emit_block() {
    local reason="$1"
    printf 'Blocked potentially destructive Bash command before auto-approval: %s' "$reason" \
        | jq -Rs '{"decision": "block", "reason": .}'
}
