#!/bin/bash
# PreToolUse hook: auto-approve Read tool and read-only Bash commands
set -euo pipefail

# EPOCHREALTIME is a bash>=5.0 builtin variable (no subprocess spawn); used by
# log_decision() to record how long this hook took, without adding a timing
# subprocess of its own. Left empty (and duration_ms logged as "NA") on
# older bash (e.g. macOS default /bin/bash 3.2).
HOOK_START_TIME="${EPOCHREALTIME:-}"

payload=$(cat)
tool_name=$(echo "$payload" | jq -r '.tool_name // ""')

# Resolve repo root (handles symlink from ~/.claude/hooks/)
HOOK_INVOKED_PATH="${BASH_SOURCE[0]}"
CODEX_HOOK_INVOCATION=0
case "$HOOK_INVOKED_PATH" in
    */.codex/hooks/*) CODEX_HOOK_INVOCATION=1 ;;
esac

_SCRIPT="$HOOK_INVOKED_PATH"
[ -L "$_SCRIPT" ] && _SCRIPT="$(readlink "$_SCRIPT")"
REPO_DIR="$(cd "$(dirname "$_SCRIPT")/.." && pwd)"
LOG_FILE="${REPO_DIR}/logs/auto-approve/$(date '+%Y-%m').log"

# shellcheck source=hooks/lib/approval-safety.sh
. "${REPO_DIR}/hooks/lib/approval-safety.sh"
# shellcheck source=hooks/lib/session-id.sh
. "${REPO_DIR}/hooks/lib/session-id.sh"

STATE_ROOT="${CLAUDE_CODE_KIT_STATE_HOME:-${XDG_STATE_HOME:-${HOME}/.local/state}/claude-code-kit}"
SESSION_ID="$(session_id_resolve "$payload")"
SESSION_ID_IS_FALLBACK=0
case "$SESSION_ID" in process-*) SESSION_ID_IS_FALLBACK=1 ;; esac
SESSION_DIR="${CLAUDE_CODE_KIT_SESSION_DIR:-${STATE_ROOT}/sessions/${SESSION_ID}}"
SESSION_APPROVED_FILE="${CLAUDE_CODE_KIT_SESSION_APPROVED_FILE:-${SESSION_DIR}/session-approved}"
SESSION_TMP_ROOT="${CLAUDE_CODE_KIT_TMP_ROOT:-/tmp/claude-code-kit}"
SESSION_TMP_DIR="${SESSION_TMP_ROOT}/${SESSION_ID}"

is_codex_invocation() {
    [ "$CODEX_HOOK_INVOCATION" = "1" ] ||
        [ -n "${CODEX_MANAGED_BY_NPM:-}" ] ||
        [ -n "${CODEX_MANAGED_BY_BUN:-}" ] ||
        [ -n "${CODEX_CI:-}" ] ||
        [ -n "${CODEX_THREAD_ID:-}" ]
}

AGENT="claude"
is_codex_invocation && AGENT="codex"
LOG_SESSION_ID="$SESSION_ID"
[ "$SESSION_ID_IS_FALLBACK" = "1" ] && LOG_SESSION_ID="n/a"

ensure_session_dir() {
    mkdir -p "$SESSION_DIR"
    chmod 700 "$STATE_ROOT" "${STATE_ROOT}/sessions" "$SESSION_DIR" 2>/dev/null || true
}

ensure_session_tmp_dir() {
    [ -L "$SESSION_TMP_ROOT" ] && return 1
    [ -L "$SESSION_TMP_DIR" ] && return 1
    mkdir -p "$SESSION_TMP_DIR" || return 1
    chmod 700 "$SESSION_TMP_DIR" 2>/dev/null || true
    [ -L "$SESSION_TMP_DIR" ] && return 1
    return 0
}

is_session_approved_path() {
    local path="$1"
    local norm_path norm_approved
    norm_path=$(realpath -m "$path" 2>/dev/null || printf '%s' "$path")
    norm_approved=$(realpath -m "$SESSION_APPROVED_FILE" 2>/dev/null || printf '%s' "$SESSION_APPROVED_FILE")
    [ "$norm_path" = "$norm_approved" ]
}

is_session_tmp_file() {
    local path="$1"
    local norm_path norm_tmp
    ensure_session_tmp_dir || return 1
    norm_path=$(realpath -m "$path" 2>/dev/null || printf '%s' "$path")
    norm_tmp=$(realpath -m "$SESSION_TMP_DIR" 2>/dev/null || printf '%s' "$SESSION_TMP_DIR")
    case "$norm_path" in
        "$norm_tmp"/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Like is_session_tmp_file, but also accepts the session tmp directory itself
# (not only paths strictly beneath it) — used to approve `mkdir -p
# "$SESSION_TMP_DIR"`, which targets the directory itself rather than a file
# inside it.
is_session_tmp_dir_or_descendant() {
    local path="$1"
    local norm_path norm_tmp
    ensure_session_tmp_dir || return 1
    norm_path=$(realpath -m "$path" 2>/dev/null || printf '%s' "$path")
    norm_tmp=$(realpath -m "$SESSION_TMP_DIR" 2>/dev/null || printf '%s' "$SESSION_TMP_DIR")
    case "$norm_path" in
        "$norm_tmp"|"$norm_tmp"/*) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_git_directory_prefix() {
    local seg="$1"
    local git_c_pattern
    git_c_pattern="^git[[:space:]]+-C[[:space:]]+(\"[^\"]*\"|'[^']*'|[^[:space:]]+)[[:space:]]+(.+)$"
    if [[ "$seg" =~ $git_c_pattern ]]; then
        printf 'git %s' "${BASH_REMATCH[2]}"
    else
        printf '%s' "$seg"
    fi
}

has_unsupported_expansion() {
    # $() is handled separately by _subshells_are_safe; only reject backtick and process substitution
    printf '%s' "$1" | grep -qE '`|[<>]\('
}

# Return 0 if the segment contains a $ variable/parameter reference that bash
# will actually evaluate (i.e. outside single quotes). Callers use this to
# guard allowlist branches whose safety determination scans the literal text
# for the absence of a dangerous flag, or requires an exact single-token
# shape. Two distinct hazards make any such reference unsafe to auto-approve:
#   1. Unquoted: bash word-splits (and can glob-expand) the value at
#      execution time, turning what looks like one literal token into an
#      arbitrary number of argv entries / hidden flags.
#   2. Double-quoted: word-splitting does not apply, but the resolved value
#      is still opaque to this literal-text scan and can itself BE a single
#      dangerous flag (e.g. OUT='--output=/tmp/x'; git diff "$OUT"), which
#      defeats an exclusion scan just as effectively.
# Only single-quoted $ is exempt: bash performs no expansion at all inside
# single quotes, so e.g. an awk/sed script's own '$1' field syntax is inert
# and safe regardless of content. $(...) subshells are validated and
# placeholder-stripped by the caller before this runs, so any remaining $
# here is a plain variable/parameter reference, not a command substitution.
_has_variable_expansion() {
    local input="$1"
    local i char quote="" escaped=0
    local n="${#input}"
    for ((i = 0; i < n; i++)); do
        char="${input:i:1}"

        # No escape mechanism inside single quotes (POSIX): a literal
        # backslash there does not escape the closing quote, so this check
        # must run before escape handling or a stray backslash just before
        # the closing quote (e.g. 'foo\') is misread as escaping it.
        if [ "$quote" = "'" ]; then
            [ "$char" = "'" ] && quote=""
            continue
        fi

        if [ "$escaped" = "1" ]; then
            escaped=0
            continue
        fi
        if [ "$char" = "\\" ]; then
            escaped=1
            continue
        fi

        [ "$char" = '$' ] && return 0

        # A quote character only changes state when it is not itself a
        # literal character inside the OTHER quote style: a ' inside "..."
        # (and a " inside '...', already handled by the early continue
        # above) has no special meaning in bash and must not toggle state.
        case "$char" in
            "'") [ -z "$quote" ] && quote="'" ;;
            '"')
                if [ "$quote" = '"' ]; then
                    quote=""
                elif [ -z "$quote" ]; then
                    quote='"'
                fi
                ;;
        esac
    done
    return 1
}

# Return 0 if $input contains a '>' that bash would actually interpret as a
# file-write redirect: unquoted, and not immediately followed by '&' (fd
# duplication, e.g. 2>&1, handled separately by split_shell_segments). Reuses
# the same single/double-quote + backslash-escape grammar as
# _has_variable_expansion so that a '>' used as a comparison operator inside
# a quoted string (e.g. awk -F: '$1>130 && $1<200') is not misread as a
# redirect. $(...) subshells are not tracked here — any '>' inside one is
# still unquoted shell syntax at this scan's level and is correctly flagged;
# the subshell's own content is independently validated later by
# _subshells_are_safe.
_has_unquoted_write_redirect() {
    local input="$1"
    local i char quote="" escaped=0
    local n="${#input}"
    for ((i = 0; i < n; i++)); do
        char="${input:i:1}"

        if [ "$quote" = "'" ]; then
            [ "$char" = "'" ] && quote=""
            continue
        fi

        if [ "$escaped" = "1" ]; then
            escaped=0
            continue
        fi
        if [ "$char" = "\\" ]; then
            escaped=1
            continue
        fi

        if [ "$char" = '>' ] && [ -z "$quote" ] && [ "${input:i+1:1}" != '&' ]; then
            return 0
        fi

        case "$char" in
            "'") [ -z "$quote" ] && quote="'" ;;
            '"')
                if [ "$quote" = '"' ]; then
                    quote=""
                elif [ -z "$quote" ]; then
                    quote='"'
                fi
                ;;
        esac
    done
    return 1
}

# Single source of truth for bash's quoting/escaping grammar as it relates to
# $(...) command substitution. Scans $input once, tracking single quotes (no
# escapes), double quotes, ANSI-C $'...' quotes (escapes apply, but $(...) and
# nested quoting are not recognized inside them), backslash escapes, and
# $(...) nesting (recognized even inside "...", sharing one paren-depth
# counter with any bare "(" / ")" once already inside a substitution) to find
# the start/end index of every TOP-LEVEL $(...) span. _extract_subshell_contents
# and _strip_subshells both build on this single pass instead of each
# reimplementing the grammar, which is what let fixes land in one function
# but not the other across past review rounds (see
# docs/L3_implementation/hooks/auto_approve_readonly.md).
#
# Prints "<start> <end>" (0-based, end = index of the matching ')') one pair
# per line, in the order each top-level span closes.
_find_top_level_subshell_spans() {
    local input="$1"
    local i char n="${#input}"
    local depth=0 quote="" escaped=0 start=0 stack_top
    local -a quote_stack=()
    local ansiq="ANSI_C_QUOTE"

    for ((i = 0; i < n; i++)); do
        char="${input:i:1}"

        # Single quotes: POSIX defines no escape mechanism inside them, so
        # this must be checked before the generic escape handling below —
        # otherwise a literal backslash immediately before the closing quote
        # (e.g. the trailing \ in 'foo\') would be misread as escaping it,
        # leaving the quote incorrectly open for the rest of the input.
        if [ "$quote" = "'" ]; then
            [ "$char" = "'" ] && quote=""
            continue
        fi

        # Generic backslash-escape handling, shared by double quotes, ANSI-C
        # quotes, and unquoted text. Real bash's double-quote escape set
        # (\$, \`, \", \\) is a subset of "escape consumes the next character
        # verbatim" — the extra characters this over-approximates never carry
        # special meaning to this tokenizer anyway (they are not one of
        # $ ' " ( )), so the wider rule is a safe simplification for the
        # narrow job of finding matching quotes/parens, not a behavior change.
        if [ "$escaped" = "1" ]; then
            escaped=0
            continue
        fi
        if [ "$char" = "\\" ]; then
            escaped=1
            continue
        fi

        # ANSI-C quoting ($'...'): escapes apply (handled above), but unlike
        # "..." real bash does not recognize $(...) or nested quoting inside
        # it, so this closes on the next unescaped ' without looking for
        # anything else.
        if [ "$quote" = "$ansiq" ]; then
            [ "$char" = "'" ] && quote=""
            continue
        fi

        # $(...) command substitution is recognized even inside "..." in real
        # bash, so this runs before the quote='"' consume-check below. A
        # top-level open (depth 0 -> 1) records the span start; nested opens
        # push the enclosing quote state so it cannot leak into (and later
        # desync) the nested level's own tracking.
        if [ "$char" = '$' ] && [ "${input:i+1:1}" = '(' ]; then
            [ "$depth" -eq 0 ] && start=$i
            quote_stack+=("$quote"); quote=""
            depth=$((depth + 1)); i=$((i + 1)); continue
        fi

        # $'...' is a lexical token recognized only when not already inside
        # another quote at this nesting level — real bash gives $' no special
        # meaning inside "..." or '...'.
        if [ "$char" = '$' ] && [ "${input:i+1:1}" = "'" ] && [ -z "$quote" ]; then
            quote="$ansiq"; i=$((i + 1)); continue
        fi

        if [ "$quote" = '"' ]; then
            [ "$char" = '"' ] && quote=""
            continue
        fi

        case "$char" in
            "'") quote="'" ;;
            '"') quote='"' ;;
            '(')
                if [ "$depth" -gt 0 ]; then
                    quote_stack+=("$quote"); quote=""
                    depth=$((depth + 1))
                fi
                ;;
            ')')
                if [ "$depth" -gt 0 ]; then
                    depth=$((depth - 1))
                    stack_top=$((${#quote_stack[@]} - 1))
                    quote="${quote_stack[$stack_top]}"
                    unset "quote_stack[$stack_top]"
                    [ "$depth" -eq 0 ] && printf '%s %s\n' "$start" "$i"
                fi
                ;;
        esac
    done
}

# Extract the contents of each top-level $(...) group, one per line, for
# recursive safety validation. Thin wrapper over _find_top_level_subshell_spans
# — content is sliced directly from the span indices rather than
# re-accumulated character by character.
_extract_subshell_contents() {
    local input="$1"
    local start end
    while read -r start end; do
        printf '%s\n' "${input:start+2:end-start-2}"
    done < <(_find_top_level_subshell_spans "$input")
}

# Replace each top-level $(...) with the __SUBSHELL_SAFE__ placeholder.
# The caller must have already verified the subshell contents via
# _subshells_are_safe. Thin wrapper over _find_top_level_subshell_spans.
_strip_subshells() {
    local input="$1"
    local result="" pos=0
    local start end
    while read -r start end; do
        result+="${input:pos:start-pos}__SUBSHELL_SAFE__"
        pos=$((end + 1))
    done < <(_find_top_level_subshell_spans "$input")
    result+="${input:pos}"
    printf '%s' "$result"
}

# Return 0 if the segment looks like a pure variable assignment with no command execution.
# Accepts: VAR=value, VAR="quoted string", VAR='quoted', VAR=__SUBSHELL_SAFE__
# Rejects: VAR=value cmd arg  (env-var prefix — unquoted space after the value)
_is_pure_assignment() {
    local seg="$1"
    printf '%s' "$seg" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' || return 1
    local value="${seg#*=}" i char q=""
    for ((i = 0; i < ${#value}; i++)); do
        char="${value:i:1}"
        if [ "$q" = "'" ]; then [ "$char" = "'" ] && q=""; continue; fi
        if [ "$q" = '"' ]; then [ "$char" = '"' ] && q=""; continue; fi
        case "$char" in
            "'") q="'" ;;
            '"') q='"' ;;
            ' '|$'\t') return 1 ;;
        esac
    done
    return 0
}

# Return 0 if every $(...) in the input contains only read-only commands.
# Recursively calls is_safe_segment on the content of each subshell.
_subshells_are_safe() {
    local input="$1"
    printf '%s' "$input" | grep -qE '\$\(' || return 0
    local content norm_content seg
    while IFS= read -r content; do
        [ -z "$content" ] && continue
        norm_content=$(printf '%s' "$content" | \
            sed 's/\\|/__ESCAPED_PIPE__/g; s/[0-9]*>>\/dev\/null//g; s/[0-9]*>\/dev\/null//g; s/&>>\/dev\/null//g; s/&>\/dev\/null//g')
        while IFS= read -r seg; do
            seg=$(printf '%s' "$seg" | sed 's/__ESCAPED_PIPE__/\\|/g; s/^[[:space:]]*//; s/[[:space:]]*$//')
            [ -z "$seg" ] && continue
            is_safe_segment "$seg" || return 1
        done < <(split_shell_segments "$norm_content")
    done < <(_extract_subshell_contents "$input")
    return 0
}

is_safe_test_expression() {
    local expression="$1"
    has_unsupported_expansion "$expression" && return 1
    printf '%s' "$expression" | grep -qE '[;&|<>]' && return 1
    printf '%s' "$expression" | grep -qE '^(test[[:space:]]+.+|\[[[:space:]].*[[:space:]]\])$'
}

is_safe_git_read_command() {
    local seg
    # Checked on the raw, pre-normalization argument: normalize_git_directory_prefix
    # discards the "-C <dir>" operand entirely from its output, so a variable
    # reference hidden there (e.g. DIR='repo branch -D victim'; git -C $DIR diff)
    # would otherwise be invisible to this guard.
    _has_variable_expansion "$1" && return 1
    seg=$(normalize_git_directory_prefix "$1")

    has_unsupported_expansion "$seg" && return 1
    # --output exclusion (and the branch/tag exclusion-then-allow checks below)
    # scan literal text for a dangerous flag; a variable reference can smuggle
    # that flag past them at execution time, so refuse to classify any git
    # segment referencing one as read-only.
    printf '%s' "$seg" | grep -qE '(^|[[:space:]])--output([=[:space:]]|$)' && return 1

    printf '%s' "$seg" | grep -qE '^git[[:space:]]+(status|log|diff|show|describe|rev-parse|ls-files|ls-tree|cat-file|blame|shortlog|merge-base)([[:space:]]|$)' && return 0
    printf '%s' "$seg" | grep -qE '^git[[:space:]]+stash[[:space:]]+list([[:space:]]|$)' && return 0
    printf '%s' "$seg" | grep -qE '^git[[:space:]]+worktree[[:space:]]+list([[:space:]]|$)' && return 0

    [ "$seg" = "git branch" ] && return 0
    if printf '%s' "$seg" | grep -qE '^git[[:space:]]+branch[[:space:]]+'; then
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-d|-D|-m|-M|-c|-C|--delete|--move|--copy|--edit-description|--set-upstream-to|--unset-upstream)([=[:space:]]|$)' && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(--list|--show-current|--contains|--no-contains|--merged|--no-merged|-a|-r|-v|-vv)([=[:space:]]|$)' && return 0
        return 1
    fi

    printf '%s' "$seg" | grep -qE '^git[[:space:]]+remote([[:space:]]+-v)?[[:space:]]*$' && return 0
    printf '%s' "$seg" | grep -qE '^git[[:space:]]+remote[[:space:]]+(show|get-url)([[:space:]]|$)' && return 0

    [ "$seg" = "git tag" ] && return 0
    if printf '%s' "$seg" | grep -qE '^git[[:space:]]+tag[[:space:]]+'; then
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-d|-a|-s|-u|-m|-F|-f|--delete|--annotate|--sign|--local-user|--message|--file|--force)([=[:space:]]|$)' && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-l|-n|-v|--list|--contains|--no-contains|--points-at|--merged|--no-merged)([=[:space:]]|$)' && return 0
        return 1
    fi

    [ "$seg" = "git reflog" ] && return 0
    printf '%s' "$seg" | grep -qE '^git[[:space:]]+reflog[[:space:]]+(show|exists)([[:space:]]|$)' && return 0

    printf '%s' "$seg" | grep -qE '^git[[:space:]]+config[[:space:]]+(-l|--list|--get|--get-all|--get-regexp|--get-urlmatch)([=[:space:]]|$)' && return 0

    return 1
}

split_shell_segments() {
    local input="$1" current="" quote="" char next prev
    local escaped=0 i
    for ((i = 0; i < ${#input}; i++)); do
        char="${input:i:1}"
        next="${input:i+1:1}"
        prev=""
        [ "$i" -gt 0 ] && prev="${input:i-1:1}"

        if [ "$quote" = "'" ]; then
            current+="$char"
            [ "$char" = "'" ] && quote=""
            continue
        fi
        if [ "$escaped" = "1" ]; then
            current+="$char"
            escaped=0
            continue
        fi
        if [ "$char" = "\\" ]; then
            current+="$char"
            escaped=1
            continue
        fi
        if [ "$quote" = '"' ]; then
            current+="$char"
            [ "$char" = '"' ] && quote=""
            continue
        fi
        if [ "$char" = "'" ] || [ "$char" = '"' ]; then
            quote="$char"
            current+="$char"
            continue
        fi

        case "$char" in
            $'\n'|';'|'|')
                printf '%s\n' "$current"
                current=""
                [ "$next" = "$char" ] && i=$((i + 1))
                ;;
            '&')
                # fd-duplication redirect (e.g. 2>&1, >&2, >&-): the '&' directly
                # follows a '>' and is followed by a bare fd number or '-', not a
                # filename. Real bash treats `>&word` as a file-write redirect
                # when word is NOT numeric/'-' (equivalent to `&>word`), so this
                # must stay narrow — only the fd-duplication shape is exempted
                # from background-operator treatment; `>&somefile` still falls
                # through to the else branch below and is correctly rejected.
                if [ "$prev" = '>' ] && [[ "${input:i+1}" =~ ^(-|[0-9]+)([[:space:]\;\&\|]|$) ]]; then
                    current+="$char"
                elif [ "$next" = '&' ]; then
                    printf '%s\n' "$current"
                    current=""
                    i=$((i + 1))
                else
                    printf '%s\n' "$current"
                    printf '%s\n' '__UNSUPPORTED_BACKGROUND_OPERATOR__'
                    current=""
                fi
                ;;
            *) current+="$char" ;;
        esac
    done
    printf '%s\n' "$current"
}

# cut -c operates byte-wise under a non-UTF-8-aware locale (e.g. LC_ALL=C),
# which can split a multibyte character at the truncation boundary and emit
# invalid UTF-8 into the log. iconv -c drops any incomplete trailing sequence
# left by the cut, regardless of which locale produced it.
#
# iconv still exits non-zero for an incomplete trailing sequence even with
# -c ("incomplete character or shift sequence at end of buffer"), but it has
# already flushed the cleaned, valid prefix to stdout by that point. Capture
# that output exactly once — do not re-invoke iconv/printf based on its exit
# status, or the fallback output gets appended after the already-flushed
# stdout instead of replacing it.
truncate_utf8_safe() {
    local text="$1" limit="${2:-120}"
    local truncated cleaned
    truncated=$(printf '%s' "$text" | cut -c1-"$limit")
    if command -v iconv >/dev/null 2>&1; then
        cleaned=$(printf '%s' "$truncated" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null)
        if [ -n "$cleaned" ] || [ -z "$truncated" ]; then
            printf '%s' "$cleaned"
            return
        fi
    fi
    printf '%s' "$truncated"
}

_hook_duration_ms() {
    if [ -z "$HOOK_START_TIME" ]; then
        HOOK_DURATION_MS="NA"
        return
    fi
    local now="$EPOCHREALTIME"
    local start_sec="${HOOK_START_TIME%.*}" start_usec="${HOOK_START_TIME#*.}"
    local now_sec="${now%.*}" now_usec="${now#*.}"
    # Right-pad to 6 digits so a short fractional part (e.g. leading-zero
    # microseconds bash prints without them) doesn't shrink the magnitude.
    start_usec="${start_usec}000000"
    start_usec="${start_usec:0:6}"
    now_usec="${now_usec}000000"
    now_usec="${now_usec:0:6}"
    # 10# forces base-10 so a leading-zero usec segment (e.g. "007123") isn't
    # parsed as an invalid octal literal.
    local start_us=$((10#$start_sec * 1000000 + 10#$start_usec))
    local now_us=$((10#$now_sec * 1000000 + 10#$now_usec))
    HOOK_DURATION_MS=$(( (now_us - start_us) / 1000 ))
}

log_decision() {
    local result="$1" tool="$2" detail="${3:-}"
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || return 0
    local short
    short=$(truncate_utf8_safe "$(printf '%s' "$detail" | tr '\n' ' ')" 120)
    _hook_duration_ms
    printf '[%s] agent=%s session=%s result=%-12s tool=%-10s duration_ms=%-6s %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$AGENT" "$LOG_SESSION_ID" \
        "$result" "$tool" "$HOOK_DURATION_MS" "$short" >> "$LOG_FILE" || true
}

emit_approval() {
    if is_codex_invocation; then
        echo '{"decision": "allow"}'
    else
        echo '{"decision": "approve"}'
    fi
}

is_session_approved_file() {
    local path="$1"
    [ -f "$SESSION_APPROVED_FILE" ] || return 1
    while IFS= read -r line; do
        case "$line" in
            ''|\#*) continue ;;
            file:*)
                local approved="${line#file:}"
                local norm_path norm_approved
                norm_path=$(realpath -m "$path" 2>/dev/null || printf '%s' "$path")
                norm_approved=$(realpath -m "$approved" 2>/dev/null || printf '%s' "$approved")
                [ "$norm_path" = "$norm_approved" ] && return 0
                ;;
        esac
    done < "$SESSION_APPROVED_FILE"
    return 1
}

check_session_approved() {
    local seg
    seg=$(normalize_git_directory_prefix "$1")
    [ -f "$SESSION_APPROVED_FILE" ] || return 1
    while IFS= read -r category; do
        case "$category" in
            ''|\#*) continue ;;
            tool:git_write)
                printf '%s' "$seg" | grep -qE '^git[[:space:]]+add(\s|$)' && return 0
                printf '%s' "$seg" | grep -qE '^git[[:space:]]+commit(\s|$)' && return 0
                printf '%s' "$seg" | grep -qE '^git[[:space:]]+merge(\s|$)' && return 0
                printf '%s' "$seg" | grep -qE '^git[[:space:]]+fetch(\s|$)' && return 0
                if printf '%s' "$seg" | grep -qE '^git[[:space:]]+pull(\s|$)'; then
                    if printf '%s' "$seg" | grep -qE '(^|[[:space:]])--ff-only([[:space:]]|$)' \
                        && ! printf '%s' "$seg" | grep -qE '(^|[[:space:]])(--no-ff|--rebase|-r|--force|-f)([=[:space:]]|$)'; then
                        return 0
                    fi
                fi
                printf '%s' "$seg" | grep -qE '^git[[:space:]]+stash([[:space:]]+(push|pop|apply)(\s|$)|[[:space:]]*$)' && return 0
                if printf '%s' "$seg" | grep -qE '^git[[:space:]]+push(\s|$)'; then
                    approval_safety_is_force_push "$seg" || return 0
                fi
                if printf '%s' "$seg" | grep -qE '^git[[:space:]]+(checkout|switch)(\s|$)'; then
                    if ! printf '%s' "$seg" | grep -qE '([[:space:]]--([[:space:]]|$)|^git[[:space:]]+(checkout|switch)[[:space:]]+\.)' \
                        && ! approval_safety_is_force_checkout "$seg"; then
                        return 0
                    fi
                fi
                if printf '%s' "$seg" | grep -qE '^git[[:space:]]+branch(\s|$)'; then
                    approval_safety_is_force_branch_delete "$seg" || return 0
                fi
                ;;
            tool:gh_issue_write)
                printf '%s' "$seg" | grep -qE '^gh[[:space:]]+issue[[:space:]]+(create|edit|close|delete|comment|reopen)(\s|$)' && return 0
                ;;
            tool:gh_pr_write)
                printf '%s' "$seg" | grep -qE '^gh[[:space:]]+pr[[:space:]]+(create|edit|close|comment|reopen|ready|review|checkout|merge)(\s|$)' && return 0
                ;;
        esac
    done < "$SESSION_APPROVED_FILE"
    return 1
}

detect_working_repo_root() {
    git -C "$PWD" rev-parse --show-toplevel 2>/dev/null
}

is_in_working_repo() {
    local path="$1"
    local repo_root
    repo_root=$(detect_working_repo_root) || return 1
    local norm_path norm_root
    norm_path=$(realpath -m "$path" 2>/dev/null || printf '%s' "$path")
    norm_root=$(realpath -m "$repo_root" 2>/dev/null || printf '%s' "$repo_root")
    case "$norm_path" in
        "$norm_root"/*) return 0 ;;
        *) return 1 ;;
    esac
}

do_wip_commit() {
    local detail="${1:-write}"
    local repo_root
    repo_root=$(detect_working_repo_root) || return 1
    git -C "$repo_root" status --porcelain 2>/dev/null | grep -q . || return 0
    git -C "$repo_root" add -A >/dev/null 2>&1 &&
        git -C "$repo_root" commit --no-verify \
            -m "wip: $(date '+%Y-%m-%d %H:%M:%S') before $detail" >/dev/null 2>&1
}

is_rm_rf_on_working_repo_path() {
    local cmd="$1"
    printf '%s' "$cmd" | grep -qE '^rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*[[:space:]]+\S' || \
        printf '%s' "$cmd" | grep -qE '^rm[[:space:]]+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*[[:space:]]+\S' || return 1
    local path
    path=$(printf '%s' "$cmd" | sed 's/^rm[[:space:]]*-[a-zA-Z]*[[:space:]]*//')
    case "$path" in
        ''|*' '*|*$'\t'*|*'$'*|*';'*|*'|'*|*'&'*|*'>'*|*'<'*|*'`'*|*'*'*|*'?'*) return 1 ;;
    esac
    local abs_path
    case "$path" in
        /*) abs_path="$path" ;;
        ./*) abs_path="${PWD}/${path#./}" ;;
        *) abs_path="${PWD}/${path}" ;;
    esac
    local repo_root norm_abs norm_root
    repo_root=$(detect_working_repo_root) || return 1
    norm_abs=$(realpath -m "$abs_path" 2>/dev/null || printf '%s' "$abs_path")
    norm_root=$(realpath -m "$repo_root" 2>/dev/null || printf '%s' "$repo_root")
    [ "$norm_abs" = "$norm_root" ] && return 1
    case "$norm_abs" in
        "$norm_root/.git"|"$norm_root/.git/"*) return 1 ;;
    esac
    case "$norm_abs" in
        "$norm_root"/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Always approve Read tool
if [ "$tool_name" = "Read" ]; then
    file_path=$(echo "$payload" | jq -r '.tool_input.file_path // "-"')
    log_decision "approved" "Read" "$file_path"
    emit_approval
    exit 0
fi

# Write tool: guard session file against scope expansion; approve other paths if session-listed
if [ "$tool_name" = "Write" ]; then
    file_path=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
    if is_session_tmp_file "$file_path"; then
        log_decision "approved" "Write" "$file_path (session-tmp)"
        emit_approval
        exit 0
    fi
    if is_session_approved_path "$file_path"; then
        ensure_session_dir
        # Initial write (file absent) - approve
        if [ ! -f "$SESSION_APPROVED_FILE" ]; then
            log_decision "approved" "Write" "$file_path (session-file initial)"
            emit_approval
            exit 0
        fi
        new_content=$(echo "$payload" | jq -r '.tool_input.content // ""')
        existing_content=$(cat "$SESSION_APPROVED_FILE")
        # Identical content - approve (idempotent)
        if [ "$new_content" = "$existing_content" ]; then
            log_decision "approved" "Write" "$file_path (session-file idempotent)"
            emit_approval
            exit 0
        fi
        # Detect scope expansion: any non-comment line in new content absent from existing
        expanded=""
        while IFS= read -r line; do
            case "$line" in ''|\#*) continue ;; esac
            grep -qxF "$line" "$SESSION_APPROVED_FILE" 2>/dev/null || expanded="${expanded}+ ${line}\n"
        done <<< "$new_content"
        if [ -n "$expanded" ]; then
            reason=$(printf 'session-approved scope expansion blocked.\nNew entries not presented to user in Step 2:\n%b\nTo grant additional permissions, return to Step 2 and obtain user approval.' "$expanded")
            log_decision "blocked" "Write" "$file_path (scope expansion: $expanded)"
            printf '%s' "$reason" | jq -Rs '{"decision": "block", "reason": .}'
            exit 0
        fi
        # New content is narrower than or equal to existing - approve
        log_decision "approved" "Write" "$file_path (session-file narrower)"
        emit_approval
        exit 0
    fi
    if [ "$SESSION_ID_IS_FALLBACK" = "0" ] && is_session_approved_file "$file_path"; then
        log_decision "approved" "Write" "$file_path (session)"
        emit_approval
        exit 0
    fi
    if is_in_working_repo "$file_path"; then
        do_wip_commit "Write $(basename "$file_path")" 2>/dev/null || true
        log_decision "approved" "Write" "$file_path (working-repo)"
        emit_approval
        exit 0
    fi
    log_decision "user_prompt" "Write" "$file_path"
    exit 0
fi

# Edit tool: approve if the path is session-listed
if [ "$tool_name" = "Edit" ]; then
    file_path=$(echo "$payload" | jq -r '.tool_input.file_path // ""')
    if is_session_tmp_file "$file_path"; then
        log_decision "approved" "Edit" "$file_path (session-tmp)"
        emit_approval
        exit 0
    fi
    if [ "$SESSION_ID_IS_FALLBACK" = "0" ] && is_session_approved_file "$file_path"; then
        log_decision "approved" "Edit" "$file_path (session)"
        emit_approval
        exit 0
    fi
    if is_in_working_repo "$file_path"; then
        do_wip_commit "Edit $(basename "$file_path")" 2>/dev/null || true
        log_decision "approved" "Edit" "$file_path (working-repo)"
        emit_approval
        exit 0
    fi
    log_decision "user_prompt" "Edit" "$file_path"
    exit 0
fi

# apply_patch tool: approve if PWD is within a git repo (working repo dynamic defense)
if [ "$tool_name" = "apply_patch" ]; then
    if detect_working_repo_root > /dev/null 2>&1; then
        do_wip_commit "apply_patch" 2>/dev/null || true
        log_decision "approved" "apply_patch" "(working-repo)"
        emit_approval
        exit 0
    fi
    log_decision "user_prompt" "apply_patch" ""
    exit 0
fi

# update_plan: Codex task-tracking metadata only — no side effects
if [ "$tool_name" = "update_plan" ]; then
    log_decision "approved" "update_plan" ""
    emit_approval
    exit 0
fi

# webrun: log payload for visibility before prompting
if [ "$tool_name" = "webrun" ]; then
    _webrun_payload=$(echo "$payload" | jq -c '.tool_input // {}' 2>/dev/null | cut -c1-200)
    log_decision "user_prompt" "webrun" "$_webrun_payload"
    exit 0
fi

if [ "$tool_name" != "Bash" ]; then
    log_decision "user_prompt" "${tool_name:-unknown}" ""
    exit 0
fi

command=$(echo "$payload" | jq -r '.tool_input.command // ""')

# Step 1: session-approved fast path — all segments must match a session-approved category
if [ "$SESSION_ID_IS_FALLBACK" = "0" ] && [ -f "$SESSION_APPROVED_FILE" ]; then
    _sa_norm=$(printf '%s' "$command" \
        | sed 's/\\|/__ESCAPED_PIPE__/g; s/[0-9]*>>\/dev\/null//g; s/[0-9]*>\/dev\/null//g; s/&>>\/dev\/null//g; s/&>\/dev\/null//g')
    _sa_all=1
    while IFS= read -r _sa_seg; do
        _sa_seg=$(printf '%s' "$_sa_seg" | sed 's/__ESCAPED_PIPE__/\\|/g; s/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -z "$_sa_seg" ] && continue
        check_session_approved "$_sa_seg" || { _sa_all=0; break; }
    done < <(split_shell_segments "$_sa_norm")
    if [ "$_sa_all" = "1" ]; then
        log_decision "approved" "Bash" "$command (session)"
        emit_approval
        exit 0
    fi
fi

# Step 2: in-repo rm -rf → dynamic defense (before approval_safety)
if is_rm_rf_on_working_repo_path "$command"; then
    _rm_path=$(printf '%s' "$command" | sed 's/^rm[[:space:]]*-[a-zA-Z]*[[:space:]]*//' | cut -c1-40)
    do_wip_commit "rm $_rm_path" 2>/dev/null || true
    log_decision "approved" "Bash" "$command (working-repo rm)"
    emit_approval
    exit 0
fi

if destructive_reason=$(approval_safety_destructive_reason "$command"); then
    log_decision "blocked" "Bash" "$command ($destructive_reason)"
    approval_safety_emit_block "$destructive_reason"
    exit 0
fi

# Normalize before write-redirect check and pipe splitting:
#   1. Strip /dev/null redirects (2>/dev/null, >>/dev/null, &>/dev/null, etc.)
#      to avoid false positives from stderr suppression.
#   2. Escape grep-style \| (backslash-pipe) to __ESCAPED_PIPE__ so the pipe
#      splitter below does not fragment grep pattern strings.
command_normalized=$(printf '%s' "$command" \
    | sed 's/\\|/__ESCAPED_PIPE__/g; s/[0-9]*>>\/dev\/null//g; s/[0-9]*>\/dev\/null//g; s/&>>\/dev\/null//g; s/&>\/dev\/null//g')

# Reject if command writes to a file (unquoted > but not >&). Quote-aware so
# a '>' used as a comparison operator inside a quoted string (e.g. awk -F:
# '$1>130 && $1<200') is not misread as a redirect.
if _has_unquoted_write_redirect "$command_normalized"; then
    log_decision "user_prompt" "Bash" "$command"
    exit 0
fi

is_safe_segment() {
    local seg condition
    seg=$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "$seg" ] && return 0

    has_unsupported_expansion "$seg" && return 1

    # If the segment contains $(), validate each subshell's content recursively,
    # then strip them out so the remaining command can be checked against the allowlist.
    if printf '%s' "$seg" | grep -qE '\$\('; then
        _subshells_are_safe "$seg" || return 1
        seg=$(_strip_subshells "$seg")
    fi

    # Pure variable assignment with a safe RHS (e.g. VAR=$(safe_cmd), VAR="string")
    _is_pure_assignment "$seg" && return 0

    case "$seg" in
        then|else|fi) return 0 ;;
        then[[:space:]]*) is_safe_segment "${seg#then}" && return 0; return 1 ;;
        else[[:space:]]*) is_safe_segment "${seg#else}" && return 0; return 1 ;;
    esac
    case "$seg" in
        if[[:space:]]*)
            condition="${seg#if}"
            condition=$(printf '%s' "$condition" | sed 's/^[[:space:]]*//')
            is_safe_test_expression "$condition" && return 0
            return 1
            ;;
    esac
    is_safe_test_expression "$seg" && return 0

    # tee writes to files — block unconditionally regardless of future allowlist additions
    printf '%s' "$seg" | grep -qE '^tee(\s|$)' && return 1

    # git read-only subcommands
    is_safe_git_read_command "$seg" && return 0

    # gh read-only subcommands
    printf '%s' "$seg" | grep -qE '^gh[[:space:]]+(issue|pr|label|repo|release|run|workflow)[[:space:]]+(list|view|status)(\s|$)' && return 0
    printf '%s' "$seg" | grep -qE '^gh[[:space:]]+pr[[:space:]]+checks(\s|$)' && return 0
    printf '%s' "$seg" | grep -qE '^gh[[:space:]]+auth[[:space:]]+status(\s|$)' && return 0
    if printf '%s' "$seg" | grep -qE '^gh[[:space:]]+api(\s|$)'; then
        # A variable reference can smuggle -X/-f/-F/etc past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        # -X/-f/-F accept an attached value with no separator (e.g. -XPOST, -fkey=value)
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-X[^[:space:]]*|-f[^[:space:]]*|-F[^[:space:]]*|--method([=[:space:]]|$)|--field([=[:space:]]|$)|--raw-field([=[:space:]]|$)|--input([=[:space:]]|$))' && return 1
        return 0
    fi
    # Standard read-only Unix tools (prefer fd over find)
    printf '%s' "$seg" | grep -qE '^cd(\s|$)' && return 0
    printf '%s' "$seg" | grep -qE '^(ls|ll|la|cat|head|tail|grep|egrep|fgrep|rg|fd|wc|uniq|cut|tr|echo|printf|pwd|which|type|printenv|du|df|stat|file|basename|dirname|uname|whoami|id|groups|ps|pgrep|jq|column|nl)(\s|$)' && return 0
    if printf '%s' "$seg" | grep -qE '^find(\s|$)'; then
        # A variable reference can smuggle -delete/-exec/etc past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])-(delete|exec|execdir|ok|okdir|fls|fprint|fprintf)([[:space:]]|$)' && return 1
        return 0
    fi
    if printf '%s' "$seg" | grep -qE '^sed(\s|$)'; then
        # A variable reference can smuggle -i/e/w past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-i|--in-place)([^[:space:]]*|$)' && return 1
        printf '%s' "$seg" | grep -qE "(^|[^[:alnum:]_-])([0-9,$]+)?[ew]([[:space:]]|['\"]|$)" && return 1
        return 0
    fi
    if printf '%s' "$seg" | grep -qE '^sort(\s|$)'; then
        # A variable reference can smuggle -o/--output past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-o|--output)([=[:space:]]|$)' && return 1
        return 0
    fi
    if printf '%s' "$seg" | grep -qE '^yq(\s|$)'; then
        # A variable reference can smuggle -i/--inplace past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-i|--inplace)([=[:space:]]|$)' && return 1
        return 0
    fi
    if printf '%s' "$seg" | grep -qE '^awk(\s|$)'; then
        # Quote-tracked, so an awk script's single-quoted $1-style field refs
        # are not flagged — only a genuinely unquoted $ outside the script
        # rejects. A variable reference could otherwise smuggle system()/
        # getline past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE 'system[[:space:]]*\(' && return 1
        printf '%s' "$seg" | grep -qE '\|[[:space:]]*getline([[:space:](;}]|$)' && return 1
        # awk's own print/printf output-redirect operator (e.g. print $1 >
        # "file", printf "%s" >> "file") writes files independently of the
        # shell-level write-redirect check above, which only sees the
        # single-quoted script as opaque text. Reject the whole segment if a
        # '>' appears anywhere after a print/printf keyword — deliberately
        # coarse (it also catches a literal '>' inside a print argument
        # string, e.g. print "a>b") since a false prompt-fallback here is
        # harmless but a missed file write is not.
        printf '%s' "$seg" | grep -qE '\b(print|printf)\b.*>' && return 1
        return 0
    fi
    printf '%s' "$seg" | grep -qE '^env[[:space:]]*$' && return 0
    if printf '%s' "$seg" | grep -qE '^date(\s|$)'; then
        # A variable reference can smuggle -s/--set past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-s|--set)([=[:space:]]|$)' && return 1
        return 0
    fi
    printf '%s' "$seg" | grep -qE '^hostname[[:space:]]*$' && return 0

    # journalctl — read-only log query; exclude maintenance/mutating operations
    if printf '%s' "$seg" | grep -qE '^journalctl(\s|$)'; then
        # A variable reference can smuggle --vacuum-*/--rotate/etc past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(--vacuum-size|--vacuum-time|--vacuum-files|--rotate|--flush|--sync|--relinquish-var|--smart-relinquish-var|--setup-keys|--update-catalog|--force)([=[:space:]]|$)' && return 1
        return 0
    fi

    # gsettings — allow read-only introspection subcommands only
    printf '%s' "$seg" | grep -qE '^gsettings[[:space:]]+(get|list-schemas|list-relocatable-schemas|list-keys|list-children|list-recursively|range|describe|writable)(\s|$)' && return 0

    # gnome-extensions — allow read-only introspection subcommands only
    printf '%s' "$seg" | grep -qE '^gnome-extensions[[:space:]]+(info|list)(\s|$)' && return 0

    # Runtime version / syntax-check-only invocations
    printf '%s' "$seg" | grep -qE '^(node|npm|npx|ruby)[[:space:]]+(--version|-v)[[:space:]]*$' && return 0
    printf '%s' "$seg" | grep -qE '^(python3?|pip3?|cargo|rustc)[[:space:]]+(--version|-V)[[:space:]]*$' && return 0
    printf '%s' "$seg" | grep -qE '^go[[:space:]]+version[[:space:]]*$' && return 0
    printf '%s' "$seg" | grep -qE '^(bash|zsh)[[:space:]]+--version[[:space:]]*$' && return 0
    printf '%s' "$seg" | grep -qE '^codex[[:space:]]+(--version|--help|-h)[[:space:]]*$' && return 0
    # bash -n / node --check: an allowlist of exactly "<cmd> <flag> <file>" with
    # no other tokens, rather than a denylist of dangerous flags. node in
    # particular treats -/_ as interchangeable in long option names and can
    # preload modules via --experimental-config-file, so any denylist of
    # specific flag spellings is provably incomplete; only the single-argument
    # shape is safe to auto-approve.
    # A variable reference — quoted or not — is opaque here: unquoted, bash
    # word-splits it into an arbitrary number of argv entries at execution
    # time; quoted, its resolved value can still itself start with "-" and
    # be parsed as a flag despite the leading-non-dash literal-text check
    # below. Either way it can defeat the single-argument shape these two
    # patterns require, so reject rather than trust the literal-text token.
    if ! _has_variable_expansion "$seg"; then
        printf '%s' "$seg" | grep -qE '^bash[[:space:]]+-n[[:space:]]+[^-[:space:]][^[:space:]]*[[:space:]]*$' && return 0
        printf '%s' "$seg" | grep -qE '^node[[:space:]]+(--check|-c)[[:space:]]+[^-[:space:]][^[:space:]]*[[:space:]]*$' && return 0
        # command -v <name>: read-only path/function/alias lookup, equivalent
        # to `type`. Same single-argument shape rationale as bash -n / node
        # --check above — a variable reference could otherwise smuggle extra
        # tokens or a leading-dash flag past a literal-text check.
        printf '%s' "$seg" | grep -qE '^command[[:space:]]+-v[[:space:]]+[^-[:space:]][^[:space:]]*[[:space:]]*$' && return 0
    fi

    # kill -0 <pid...>: signal 0 sends no actual signal — it only tests
    # whether the process exists and is signalable — so this is a read-only
    # liveness check, not a mutation. Deliberately narrow: only digit-only
    # PIDs (no leading '-', which would target a process GROUP instead) and
    # no other signal/flag are accepted; any other `kill` invocation falls
    # through to the normal prompt.
    if printf '%s' "$seg" | grep -qE '^kill(\s|$)'; then
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE '^kill[[:space:]]+-0([[:space:]]+[0-9]+)+[[:space:]]*$' && return 0
        return 1
    fi

    # mkdir -p restricted to the session tmp directory (or a descendant of
    # it): this repo's own documented convention for AI-agent scratch files
    # (see CLAUDE.md "一時ファイルの作成"). Only the exact `-p <single-path>`
    # shape is accepted — no other flags, no multiple paths — and the target
    # must resolve under SESSION_TMP_DIR, mirroring the Write/Edit tool's
    # existing is_session_tmp_file check.
    if printf '%s' "$seg" | grep -qE '^mkdir(\s|$)'; then
        _has_variable_expansion "$seg" && return 1
        if printf '%s' "$seg" | grep -qE '^mkdir[[:space:]]+-p[[:space:]]+[^[:space:]]+[[:space:]]*$'; then
            local mk_path
            mk_path=$(printf '%s' "$seg" | sed -E 's/^mkdir[[:space:]]+-p[[:space:]]+//; s/[[:space:]]*$//')
            case "$mk_path" in
                \"*\") mk_path="${mk_path#\"}"; mk_path="${mk_path%\"}" ;;
                \'*\') mk_path="${mk_path#\'}"; mk_path="${mk_path%\'}" ;;
            esac
            case "$mk_path" in
                *[\"\'\ ]*) return 1 ;;
            esac
            is_session_tmp_dir_or_descendant "$mk_path" && return 0
        fi
        return 1
    fi

    # curl — allow default GET/HEAD requests only; reject writes and custom methods
    if printf '%s' "$seg" | grep -qE '^curl(\s|$)'; then
        # A variable reference can smuggle -o/-X/--data/etc past this exclusion scan.
        _has_variable_expansion "$seg" && return 1
        printf '%s' "$seg" | grep -qE '(^|[[:space:]])(-[^-[:space:]]*[oOXdFTK][^[:space:]]*|--output|--remote-name|--remote-name-all|--request|--data[^[:space:]]*|--form[^[:space:]]*|--upload-file|--json|--config)([=[:space:]]|$)' && return 1
        return 0
    fi

    # npm — allow metadata inspection only; scripts and package mutations require a prompt
    if printf '%s' "$seg" | grep -qE '^npm(\s|$)'; then
        printf '%s' "$seg" | grep -qE '^npm[[:space:]]+(view|info|show|search|list|ls|outdated|explain|why|prefix|root|help)([[:space:]]|$)' && return 0
        printf '%s' "$seg" | grep -qE '^npm[[:space:]]+config[[:space:]]+(get|list|ls)([[:space:]]|$)' && return 0
        printf '%s' "$seg" | grep -qE '^npm[[:space:]]+run[[:space:]]*$' && return 0
        return 1
    fi

    [ "$SESSION_ID_IS_FALLBACK" = "0" ] && check_session_approved "$seg" && return 0

    return 1
}

# Split on &&, ||, ;, | and verify every segment is read-only.
# Uses command_normalized so that \| inside grep patterns (already replaced
# with __ESCAPED_PIPE__) does not create spurious segments.
while IFS= read -r segment; do
    segment=$(printf '%s' "$segment" | sed 's/__ESCAPED_PIPE__/\\|/g')
    if [ -n "$segment" ] && ! is_safe_segment "$segment"; then
        log_decision "user_prompt" "Bash" "$command"
        exit 0
    fi
done < <(split_shell_segments "$command_normalized")

log_decision "approved" "Bash" "$command"
emit_approval
exit 0
