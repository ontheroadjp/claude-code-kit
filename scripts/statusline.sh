#!/usr/bin/env bash
# Claude Code status line: context + rate limits

RESET='\033[0m'
CYAN='\033[36m'
YELLOW='\033[33m'
MAGENTA='\033[35m'
DIM='\033[2m'

input=$(cat)

# Context usage
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
ctx_total=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)

# Compute from current_usage when used_percentage is absent
if [ -z "$ctx_pct" ] && [ -n "$ctx_total" ] && [ "$ctx_total" -gt 0 ] 2>/dev/null; then
    ctx_sum=$(echo "$input" | jq -r '
        if .context_window.current_usage != null then
            (.context_window.current_usage.input_tokens // 0)
            + (.context_window.current_usage.output_tokens // 0)
            + (.context_window.current_usage.cache_creation_input_tokens // 0)
            + (.context_window.current_usage.cache_read_input_tokens // 0)
            | tostring
        else
            empty
        end
    ' 2>/dev/null)
    if [ -n "$ctx_sum" ]; then
        ctx_pct=$(echo "scale=1; $ctx_sum * 100 / $ctx_total" | bc)
    fi
fi

# 5-hour rate limit
fh_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
fh_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)

# 7-day rate limit
sd_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
sd_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

parts=()

# Context
if [ -n "$ctx_total" ]; then
    if [ -n "$ctx_pct" ]; then
        ctx_int=${ctx_pct%.*}
        parts+=("${CYAN}CTX:${ctx_int}%${RESET}")
    else
        parts+=("${CYAN}CTX:n/a${RESET}")
    fi
fi

# 5-hour rate limit
if [ -n "$fh_pct" ]; then
    fh_int=${fh_pct%.*}
    if [ -n "$fh_reset" ]; then
        fh_time=$(date -r "$fh_reset" "+%H:%M" 2>/dev/null || date -d "@$fh_reset" "+%H:%M" 2>/dev/null)
        parts+=("${YELLOW}5h:${fh_int}%${DIM}(>${fh_time})${RESET}")
    else
        parts+=("${YELLOW}5h:${fh_int}%${RESET}")
    fi
fi

# 7-day rate limit
if [ -n "$sd_pct" ]; then
    sd_int=${sd_pct%.*}
    if [ -n "$sd_reset" ]; then
        sd_time=$(date -r "$sd_reset" "+%m/%d %H:%M" 2>/dev/null || date -d "@$sd_reset" "+%m/%d %H:%M" 2>/dev/null)
        parts+=("${MAGENTA}7d:${sd_int}%${DIM}(>${sd_time})${RESET}")
    else
        parts+=("${MAGENTA}7d:${sd_int}%${RESET}")
    fi
fi

if [ ${#parts[@]} -gt 0 ]; then
    SEP="${DIM} | ${RESET}"
    result=""
    for i in "${!parts[@]}"; do
        [ "$i" -gt 0 ] && result+="$SEP"
        result+="${parts[$i]}"
    done
    echo -e "$result"
fi
