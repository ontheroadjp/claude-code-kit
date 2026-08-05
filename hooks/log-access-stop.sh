#!/bin/bash
# Stop: write formatted log to pending file (not main log); keep state alive across turns

# Captured before any payload processing so duration_ms reflects this hook's
# own wall-clock cost (the jq transcript re-aggregation below can be slow on
# large transcripts). Empty on bash < 5.0, where EPOCHREALTIME is unsupported.
HOOK_START_TIME="${EPOCHREALTIME:-}"

_SCRIPT="${BASH_SOURCE[0]}"
[ -L "$_SCRIPT" ] && _SCRIPT="$(readlink "$_SCRIPT")"
REPO_DIR="$(cd "$(dirname "$_SCRIPT")/.." && pwd)"
# shellcheck source=hooks/lib/hook-timing.sh
. "${REPO_DIR}/hooks/lib/hook-timing.sh"

payload=$(cat)
session_id=$(echo "$payload"      | jq -r '.session_id // empty')
transcript_path=$(echo "$payload" | jq -r '.transcript_path // empty')

[ -z "$session_id" ] && exit 0

SESSION_DIR="/tmp/claude-access-sessions"
STATE_FILE="${SESSION_DIR}/${session_id}.json"
PENDING_FILE="${SESSION_DIR}/${session_id}.pending"

[ ! -f "$STATE_FILE" ] && exit 0

state=$(cat "$STATE_FILE")

accesses_count=$(echo "$state" | jq '.accesses | length')
if [ "$accesses_count" -eq 0 ]; then
  exit 0
fi

start_time=$(echo "$state"       | jq -r '.start_time')
user_instruction=$(echo "$state" | jq -r '.user_instruction')
total=$(echo "$state"            | jq '.accesses | length')
modified_files=$(echo "$state"   | jq -r '.modified_files[]' 2>/dev/null || true)

format_modified() {
  if [ -n "$modified_files" ]; then
    echo "$modified_files" | while IFS= read -r f; do echo "  - $f"; done
  fi
}

duplicates=$(echo "$state" | jq -r '
  .accesses
  | group_by(.path)
  | map(select(length > 1) | {path: .[0].path, count: length})
  | sort_by(-.count)[]
  | "  - \(.path) (\(.count)回)"
')

phases=$(echo "$state" | jq -r '
  [.accesses[].phase]
  | reduce .[] as $p ([]; if (. | contains([$p])) then . else . + [$p] end)
  | .[]
')

{
  printf '\n---\n\n'
  printf '[日時]\n%s\n\n' "$start_time"
  printf '[ユーザーからの指示内容]\n%s\n\n' "$user_instruction"
  printf '[アクセスサマリ]\n総アクセス数: %d\n' "$total"

  if [ -n "$duplicates" ]; then
    printf '重複アクセス:\n%s\n' "$duplicates"
  else
    printf '重複アクセス: なし\n'
  fi
  printf '\n'

  printf '[フェーズ別アクセス順序]\n'
  while IFS= read -r phase; do
    phase_count=$(echo "$state" | jq --arg p "$phase" '[.accesses[] | select(.phase==$p)] | length')
    printf '[%s] %d件\n' "$phase" "$phase_count"
    echo "$state" | jq -r --arg p "$phase" '
      .accesses[] | select(.phase==$p) |
      "  #\(.seq)  \(.tool)  \(.path)"
    '
    printf '\n'
  done <<< "$phases"

  printf '[修正したファイル]\n'
  format_modified
  printf '\n'

  if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    token_data=$(jq -rsc '
      [.[] | objects | select(.type == "assistant" and .message.usage != null)] as $entries |
      ($entries[-1].message.model // "unknown") as $model |
      ($entries | map(.message.usage) | {
        input:        (map(.input_tokens                // 0) | add // 0),
        output:       (map(.output_tokens               // 0) | add // 0),
        cache_read:   (map(.cache_read_input_tokens     // 0) | add // 0),
        cache_create: (map(.cache_creation_input_tokens // 0) | add // 0)
      }) as $u |
      ($u.input + $u.cache_read) as $denom |
      ($model |
        if test("opus")    then {i:15.0,  o:75.0, cr:1.50, cc:18.75}
        elif test("haiku") then {i:0.80,  o:4.0,  cr:0.08, cc:1.0}
        else                    {i:3.0,   o:15.0, cr:0.30, cc:3.75}
        end
      ) as $price |
      (($u.input * $price.i + $u.output * $price.o +
        $u.cache_read * $price.cr + $u.cache_create * $price.cc) / 1000000) as $cost |
      {
        input:       $u.input,
        output:      $u.output,
        cache_read:  $u.cache_read,
        cache_ratio: (if $denom > 0 then (($u.cache_read * 1000 / $denom | floor) / 10) else 0 end),
        total:       ($u.input + $u.output + $u.cache_create),
        cost_usd:    ($cost * 10000 | round | . / 10000)
      }
    ' "$transcript_path" 2>/dev/null) || token_data=""

    if [ -n "$token_data" ]; then
      t_input=$(echo "$token_data"       | jq -r '.input')
      t_output=$(echo "$token_data"      | jq -r '.output')
      t_cache_read=$(echo "$token_data"  | jq -r '.cache_read')
      t_cache_ratio=$(echo "$token_data" | jq -r '.cache_ratio')
      t_total=$(echo "$token_data"       | jq -r '.total')
      t_cost=$(echo "$token_data"        | jq -r '.cost_usd')
      printf '[トークン使用量]\n'
      printf '  input:       %d\n'   "$t_input"
      printf '  output:      %d\n'   "$t_output"
      printf '  cache_read:  %d  (cache_ratio: %s%%)\n' "$t_cache_read" "$t_cache_ratio"
      printf '  total:       %d\n'   "$t_total"
      printf '  cost_usd:    %s\n'   "$t_cost"
      printf '\n'
    fi
  fi

  # Persist this invocation's duration into state (kept alive across turns,
  # same as accesses/modified_files) so the flushed block reports the full
  # session's Stop-hook overhead, not just the latest call.
  hook_duration_ms_value=$(hook_duration_ms "$HOOK_START_TIME")
  state=$(echo "$state" | jq --arg d "$hook_duration_ms_value" \
    '.hook_durations_ms = ((.hook_durations_ms // []) + [$d])')
  printf '%s' "$state" > "$STATE_FILE"
  hook_durations=$(echo "$state" | jq -r '.hook_durations_ms | join(",")')
  printf '[Hook処理時間]\n%s\n\n' "$hook_durations"
} > "$PENDING_FILE"
# State is kept alive; pending file is flushed to main log when next /work starts
