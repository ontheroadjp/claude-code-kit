#!/bin/bash
# Shared hook execution-time measurement for hooks that log their own duration_ms
# (hooks/log-token-usage.sh, hooks/log-access-stop.sh). Mirrors the EPOCHREALTIME-based
# calculation hooks/auto-approve-readonly.sh has used inline since issue #219; that file
# is left as-is (untouched, well-tested critical path) and does not source this lib.

# hook_duration_ms <start>
# <start> is an $EPOCHREALTIME value captured at the top of the caller's script (before
# any payload processing). Echoes the elapsed milliseconds, or "NA" if <start> is empty
# (EPOCHREALTIME unsupported: bash < 5.0, e.g. macOS default /bin/bash 3.2).
hook_duration_ms() {
    local start="$1"
    if [ -z "$start" ]; then
        echo "NA"
        return
    fi
    local now="$EPOCHREALTIME"
    local start_sec="${start%.*}" start_usec="${start#*.}"
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
    echo $(( (now_us - start_us) / 1000 ))
}
