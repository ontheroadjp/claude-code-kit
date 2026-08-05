#!/bin/bash
# shellcheck disable=SC2016  # AWK scripts below are single-quoted intentionally; $ must stay literal
# shellcheck disable=SC2183  # printf '%Ns' with no argument is the intentional zero-arg padding idiom
set -euo pipefail

LOG_FILE="$HOME/.claude/token-usage.log"
LINES=20
SHOW_ALL=false
MODE="list"

usage() {
  cat <<'EOF'
Usage: show-token-usage.sh [-n <count>] [-a|--all] [MODE]

Modes (default: list):
  --sum       Aggregated totals, averages, and cost
  --model     Per-model breakdown with cost
  --cost      Daily cost timeline and period summary
  --project   Project ranking by cost
  --time      Hourly usage heatmap
  --anomaly   Low-cache and high token-density sessions

Options:
  -n <count>  Last N entries (default: 20, list mode only)
  -a, --all   All entries (list mode only)
  -h, --help  This help
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n)        shift; LINES="${1:?-n requires a number}"; shift ;;
    -a|--all)  SHOW_ALL=true; shift ;;
    --sum)     MODE="sum";     shift ;;
    --model)   MODE="model";   shift ;;
    --cost)    MODE="cost";    shift ;;
    --project) MODE="project"; shift ;;
    --time)    MODE="time";    shift ;;
    --anomaly) MODE="anomaly"; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

[[ ! -f "$LOG_FILE" ]] && { echo "Error: log file not found: $LOG_FILE" >&2; exit 1; }

# ─── AWK: list view ───────────────────────────────────────────────────────────

PARSE_AWK='
/^\[/ {
  gsub(/=[ \t]+/, "=")
  ts = substr($0, 2, 19)
  name = model = branch = cwd = "-"
  turns = tot = 0; cache_ratio = cost = 0
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "name")        name        = kv[2]
    if (kv[1] == "model")       { model = kv[2]; sub(/^claude-/, "", model) }
    if (kv[1] == "turns")       turns       = kv[2] + 0
    if (kv[1] == "total")       tot         = kv[2] + 0
    if (kv[1] == "cache_ratio") cache_ratio = kv[2] + 0
    if (kv[1] == "cost_usd")    cost        = kv[2] + 0
    if (kv[1] == "branch")      branch      = kv[2]
    if (kv[1] == "cwd")         cwd         = kv[2]
  }
  printf "%-19s  %-18s  %-20s  %4d  %7d  %5.1f%%  $%7.4f  %-15s  %s\n", \
    ts, name, model, turns, tot, cache_ratio, cost, branch, cwd
}'

# ─── AWK: sum view ────────────────────────────────────────────────────────────

SUM_AWK='
/^\[/ {
  gsub(/=[ \t]+/, "=")
  turns = inp = out = cr = cc = tot = cost = 0
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "input")        inp   = kv[2] + 0
    if (kv[1] == "output")       out   = kv[2] + 0
    if (kv[1] == "cache_read")   cr    = kv[2] + 0
    if (kv[1] == "cache_create") cc    = kv[2] + 0
    if (kv[1] == "total")        tot   = kv[2] + 0
    if (kv[1] == "turns")        turns = kv[2] + 0
    if (kv[1] == "cost_usd")     cost  = kv[2] + 0
  }
  sessions++
  total_inp += inp; total_out += out
  total_cr  += cr;  total_cc  += cc
  total_tok += tot; total_turns += turns
  total_cost += cost
}
END {
  denom     = total_inp + total_cr
  hit_rate  = (denom > 0)        ? (total_cr * 100.0 / denom)      : 0
  turns_avg = (sessions > 0)     ? (total_turns  / sessions)       : 0
  tok_avg   = (sessions > 0)     ? (total_tok    / sessions)       : 0
  cost_avg  = (sessions > 0)     ? (total_cost   / sessions)       : 0
  cost_turn = (total_turns > 0)  ? (total_cost   / total_turns)    : 0
  printf "  sessions        : %d\n",     sessions
  printf "  turns  (avg)    : %.1f\n",   turns_avg
  printf "  input           : %d\n",     total_inp
  printf "  output          : %d\n",     total_out
  printf "  cache_read      : %d\n",     total_cr
  printf "  cache_create    : %d\n",     total_cc
  printf "  total           : %d\n",     total_tok
  printf "  total  (avg)    : %.0f\n",   tok_avg
  printf "  cache hit rate  : %.1f%%\n", hit_rate
  printf "  ─────────────────────────────\n"
  printf "  total cost      : $%.4f\n",  total_cost
  printf "  cost / session  : $%.4f\n",  cost_avg
  printf "  cost / turn     : $%.4f\n",  cost_turn
}'

# ─── AWK: model view ─────────────────────────────────────────────────────────

MODEL_AWK='
/^\[/ {
  gsub(/=[ \t]+/, "=")
  m = "-"
  turns = inp = cr = tot = cost = 0
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "model")       { m = kv[2]; sub(/^claude-/, "", m) }
    if (kv[1] == "turns")       turns = kv[2] + 0
    if (kv[1] == "input")       inp   = kv[2] + 0
    if (kv[1] == "cache_read")  cr    = kv[2] + 0
    if (kv[1] == "total")       tot   = kv[2] + 0
    if (kv[1] == "cost_usd")    cost  = kv[2] + 0
  }
  cnt[m]++
  turns_s[m] += turns; inp_s[m] += inp; cr_s[m]   += cr
  total_s[m] += tot;   cost_s[m] += cost
}
END {
  printf "%-22s  %8s  %10s  %10s  %10s  %12s  %12s\n", \
    "model", "sessions", "turns_avg", "total_avg", "cache%", "cost_total", "cost/session"
  printf "%-22s  %8s  %10s  %10s  %10s  %12s  %12s\n", \
    "──────────────────────", "────────", "──────────", "──────────", "──────────", "────────────", "────────────"
  for (m in cnt) {
    denom = inp_s[m] + cr_s[m]
    ratio = (denom > 0) ? (cr_s[m] * 100.0 / denom) : 0
    printf "%-22s  %8d  %10.1f  %10.0f  %9.1f%%  $%11.4f  $%11.4f\n", \
      m, cnt[m], turns_s[m]/cnt[m], total_s[m]/cnt[m], ratio, cost_s[m], cost_s[m]/cnt[m]
  }
}'

# ─── AWK: cost view ───────────────────────────────────────────────────────────

COST_AWK='
/^\[/ {
  gsub(/=[ \t]+/, "=")
  date = substr($0, 2, 10)
  turns = cost = 0
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "turns")    turns = kv[2] + 0
    if (kv[1] == "cost_usd") cost  = kv[2] + 0
  }
  day_cnt[date]++
  day_turns[date] += turns
  day_cost[date]  += cost
  total_cost      += cost
  total_turns     += turns
  total_sessions  ++
  dates[date]      = 1
}
END {
  n = 0
  for (d in dates) sorted[++n] = d
  for (i = 1; i <= n; i++)
    for (j = i+1; j <= n; j++)
      if (sorted[i] > sorted[j]) { tmp=sorted[i]; sorted[i]=sorted[j]; sorted[j]=tmp }
  printf "%-10s  %8s  %6s  %10s  %12s\n", \
    "date", "sessions", "turns", "cost_usd", "cost/session"
  printf "%-10s  %8s  %6s  %10s  %12s\n", \
    "──────────", "────────", "──────", "──────────", "────────────"
  for (i = 1; i <= n; i++) {
    d = sorted[i]
    printf "%-10s  %8d  %6d  $%9.4f  $%11.4f\n", \
      d, day_cnt[d], day_turns[d], day_cost[d], day_cost[d]/day_cnt[d]
  }
  printf "%-10s  %8s  %6s  %10s  %12s\n", \
    "──────────", "────────", "──────", "──────────", "────────────"
  printf "%-10s  %8d  %6d  $%9.4f  $%11.4f\n", \
    "TOTAL", total_sessions, total_turns, total_cost, \
    (total_sessions > 0 ? total_cost/total_sessions : 0)
}'

# ─── AWK: project view ───────────────────────────────────────────────────────

PROJECT_AWK='
/^\[/ {
  gsub(/=[ \t]+/, "=")
  cwd = "-"
  turns = inp = cr = tot = cost = 0
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "cwd")         cwd   = kv[2]
    if (kv[1] == "turns")       turns = kv[2] + 0
    if (kv[1] == "input")       inp   = kv[2] + 0
    if (kv[1] == "cache_read")  cr    = kv[2] + 0
    if (kv[1] == "total")       tot   = kv[2] + 0
    if (kv[1] == "cost_usd")    cost  = kv[2] + 0
  }
  p_cnt[cwd]++
  p_turns[cwd] += turns; p_inp[cwd] += inp; p_cr[cwd]  += cr
  p_total[cwd] += tot;   p_cost[cwd] += cost
  projects[cwd] = 1
}
END {
  printf "%-30s  %8s  %6s  %11s  %10s  %8s\n", \
    "project", "sessions", "turns", "total_tok", "cost_usd", "cache%"
  printf "%-30s  %8s  %6s  %11s  %10s  %8s\n", \
    "──────────────────────────────", "────────", "──────", "───────────", "──────────", "────────"
  n = 0
  for (p in projects) proj_list[++n] = p
  for (i = 1; i <= n; i++)
    for (j = i+1; j <= n; j++)
      if (p_cost[proj_list[i]] < p_cost[proj_list[j]]) {
        tmp=proj_list[i]; proj_list[i]=proj_list[j]; proj_list[j]=tmp
      }
  for (i = 1; i <= n; i++) {
    p = proj_list[i]
    denom = p_inp[p] + p_cr[p]
    ratio = (denom > 0) ? (p_cr[p] * 100.0 / denom) : 0
    printf "%-30s  %8d  %6d  %11d  $%9.4f  %7.1f%%\n", \
      p, p_cnt[p], p_turns[p], p_total[p], p_cost[p], ratio
  }
}'

# ─── AWK: time view ───────────────────────────────────────────────────────────

TIME_AWK='
/^\[/ {
  gsub(/=[ \t]+/, "=")
  hour = substr($0, 13, 2) + 0
  turns = cost = 0
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "turns")    turns = kv[2] + 0
    if (kv[1] == "cost_usd") cost  = kv[2] + 0
  }
  h_cnt[hour]++
  h_turns[hour] += turns
  h_cost[hour]  += cost
}
END {
  max_cost = 0
  for (h = 0; h < 24; h++) if (h_cost[h] > max_cost) max_cost = h_cost[h]
  printf "%-4s  %8s  %6s  %9s  %s\n", "hour", "sessions", "turns", "cost_usd", "bar"
  printf "%s\n", "────────────────────────────────────────────────────────────────────"
  for (h = 0; h < 24; h++) {
    bar_len = (max_cost > 0) ? int(h_cost[h] * 40 / max_cost) : 0
    bar = ""
    for (b = 0; b < bar_len; b++) bar = bar "█"
    printf "%02d    %8d  %6d  $%8.4f  %s\n", \
      h, h_cnt[h]+0, h_turns[h]+0, h_cost[h]+0, bar
  }
}'

# ─── AWK: anomaly – low cache ─────────────────────────────────────────────────

ANOMALY_LOW_AWK='
/^\[/ {
  gsub(/=[ \t]+/, "=")
  ts = substr($0, 2, 19)
  name = model = "-"
  turns = 0; cache_ratio = cost = 0
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "name")        name        = kv[2]
    if (kv[1] == "model")       { model = kv[2]; sub(/^claude-/, "", model) }
    if (kv[1] == "turns")       turns       = kv[2] + 0
    if (kv[1] == "cache_ratio") cache_ratio = kv[2] + 0
    if (kv[1] == "cost_usd")    cost        = kv[2] + 0
  }
  if (turns > 2 && cache_ratio < 50) {
    printf "%-19s  %-18s  %-20s  %5d  %6.1f%%  $%7.4f\n", \
      ts, name, model, turns, cache_ratio, cost
  }
}'

# ─── AWK: anomaly – high density ──────────────────────────────────────────────

ANOMALY_DENSE_AWK='
/^\[/ {
  gsub(/=[ \t]+/, "=")
  ts = substr($0, 2, 19)
  name = model = "-"
  turns = inp = out = cr = cc = 0; cost = 0
  for (i = 3; i <= NF; i++) {
    n = split($i, kv, "=")
    if (n < 2) continue
    if (kv[1] == "name")         name  = kv[2]
    if (kv[1] == "model")        { model = kv[2]; sub(/^claude-/, "", model) }
    if (kv[1] == "turns")        turns = kv[2] + 0
    if (kv[1] == "input")        inp   = kv[2] + 0
    if (kv[1] == "output")       out   = kv[2] + 0
    if (kv[1] == "cache_read")   cr    = kv[2] + 0
    if (kv[1] == "cache_create") cc    = kv[2] + 0
    if (kv[1] == "cost_usd")     cost  = kv[2] + 0
  }
  all_tok = inp + out + cr + cc
  tpt = (turns > 1) ? int(all_tok / turns) : 0
  if (tpt > 20000) {
    printf "%-19s  %-18s  %-20s  %5d  %9d  %9d  $%7.4f\n", \
      ts, name, model, turns, tpt, all_tok, cost
  }
}'

# ─── Dispatch ─────────────────────────────────────────────────────────────────

case "$MODE" in
  list)
    printf "%-19s  %-18s  %-20s  %4s  %7s  %6s  %9s  %-15s  %s\n" \
      "timestamp" "name" "model" "turn" "total" "cache%" "cost_usd" "branch" "cwd"
    printf '%s\n' "$(printf '%115s' | tr ' ' '─')"
    if "$SHOW_ALL"; then
      awk "$PARSE_AWK" "$LOG_FILE"
    else
      tail -n "$LINES" "$LOG_FILE" | awk "$PARSE_AWK"
    fi
    ;;

  sum)
    echo "=== Token Usage Summary ==="
    awk "$SUM_AWK" "$LOG_FILE"
    ;;

  model)
    echo "=== Per-Model Breakdown ==="
    awk "$MODEL_AWK" "$LOG_FILE"
    ;;

  cost)
    echo "=== Daily Cost Timeline ==="
    awk "$COST_AWK" "$LOG_FILE"
    echo ""
    echo "=== Period Summary ==="
    cutoff7=$(date  -v-7d  '+%Y-%m-%d' 2>/dev/null || date -d '7 days ago'  '+%Y-%m-%d' 2>/dev/null || echo "0000-00-00")
    cutoff30=$(date -v-30d '+%Y-%m-%d' 2>/dev/null || date -d '30 days ago' '+%Y-%m-%d' 2>/dev/null || echo "0000-00-00")
    awk -v c7="$cutoff7" -v c30="$cutoff30" '
    /^\[/ {
      gsub(/=[ \t]+/, "=")
      date = substr($0, 2, 10)
      cost = 0
      for (i = 3; i <= NF; i++) {
        n = split($i, kv, "=")
        if (n < 2) continue
        if (kv[1] == "cost_usd") cost = kv[2] + 0
      }
      all_cost += cost; all_cnt++
      if (date >= c30) { m30_cost += cost; m30_cnt++ }
      if (date >= c7)  { d7_cost  += cost; d7_cnt++  }
    }
    END {
      printf "  Last  7 days : $%.4f (%d sessions)\n", d7_cost,  d7_cnt
      printf "  Last 30 days : $%.4f (%d sessions)\n", m30_cost, m30_cnt
      printf "  All time     : $%.4f (%d sessions)\n", all_cost, all_cnt
    }' "$LOG_FILE"
    ;;

  project)
    echo "=== Project Ranking (by cost) ==="
    awk "$PROJECT_AWK" "$LOG_FILE"
    ;;

  time)
    echo "=== Hourly Usage Pattern ==="
    awk "$TIME_AWK" "$LOG_FILE"
    ;;

  anomaly)
    echo "=== Low Cache Efficiency (turns > 2, cache < 50%) ==="
    printf "%-19s  %-18s  %-20s  %5s  %7s  %9s\n" \
      "timestamp" "name" "model" "turns" "cache%" "cost_usd"
    printf '%s\n' "$(printf '%85s' | tr ' ' '─')"
    awk "$ANOMALY_LOW_AWK" "$LOG_FILE"
    echo ""
    echo "=== High Token Density (> 20k tokens/turn) ==="
    printf "%-19s  %-18s  %-20s  %5s  %9s  %9s  %9s\n" \
      "timestamp" "name" "model" "turns" "tok/turn" "all_tok" "cost_usd"
    printf '%s\n' "$(printf '%100s' | tr ' ' '─')"
    awk "$ANOMALY_DENSE_AWK" "$LOG_FILE"
    ;;
esac
