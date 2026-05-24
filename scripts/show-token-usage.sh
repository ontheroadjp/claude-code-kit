#!/bin/bash
set -euo pipefail

LOG_FILE="$HOME/.claude/token-usage.log"
LINES=20
SHOW_ALL=false
SHOW_SUM=false

usage() {
  echo "Usage: $(basename "$0") [-n <count>] [-a|--all] [--sum]"
  echo "  -n <count>   Show last N entries (default: 20)"
  echo "  -a, --all    Show all entries"
  echo "  --sum        Show aggregated totals"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) shift; LINES="${1:?-n requires a number}"; shift ;;
    -a|--all) SHOW_ALL=true; shift ;;
    --sum) SHOW_SUM=true; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: log file not found: $LOG_FILE" >&2
  exit 1
fi

# Normalize padded values ("input=   212" -> "input=212") then parse key=value fields.
PARSE_AWK='
{
  ts = substr($0, 2, 19)
  gsub(/=[ \t]+/, "=")
  session = ""; input = ""; output = ""; cr = ""; cc = ""; tot = ""
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "session")       session = kv[2]
    if (kv[1] == "input")         input   = kv[2]
    if (kv[1] == "output")        output  = kv[2]
    if (kv[1] == "cache_read")    cr      = kv[2]
    if (kv[1] == "cache_create")  cc      = kv[2]
    if (kv[1] == "total")         tot     = kv[2]
  }
  printf "%-19s  %-36s  %8s  %8s  %10s  %10s  %8s\n", ts, session, input, output, cr, cc, tot
}'

SUM_AWK='
{
  gsub(/=[ \t]+/, "=")
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "input")        input        += kv[2]
    if (kv[1] == "output")       output       += kv[2]
    if (kv[1] == "cache_read")   cache_read   += kv[2]
    if (kv[1] == "cache_create") cache_create += kv[2]
    if (kv[1] == "total")        total        += kv[2]
  }
  sessions++
}
END {
  printf "  sessions     : %d\n", sessions
  printf "  input        : %d\n", input
  printf "  output       : %d\n", output
  printf "  cache_read   : %d\n", cache_read
  printf "  cache_create : %d\n", cache_create
  printf "  total        : %d\n", total
}'

if "$SHOW_SUM"; then
  echo "=== Token Usage Totals ==="
  awk "$SUM_AWK" "$LOG_FILE"
  exit 0
fi

printf "%-19s  %-36s  %8s  %8s  %10s  %10s  %8s\n" \
  "timestamp" "session" "input" "output" "cache_read" "cache_crt" "total"
printf '%110s\n' | tr ' ' '-'

if "$SHOW_ALL"; then
  awk "$PARSE_AWK" "$LOG_FILE"
else
  tail -n "$LINES" "$LOG_FILE" | awk "$PARSE_AWK"
fi
