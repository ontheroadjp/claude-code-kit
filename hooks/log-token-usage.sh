#!/bin/bash
set -euo pipefail

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
transcript_path=$(echo "$payload" | jq -r '.transcript_path // empty')
session_id=$(echo "$payload" | jq -r '.session_id // "unknown"')

[ -z "$transcript_path" ] || [ ! -f "$transcript_path" ] && exit 0

data=$(jq -rsc '
  [.[] | objects | select(.type == "assistant" and .message.usage != null)] as $entries |
  ([.[] | objects | select(.type == "custom-title") | .customTitle] | last // "") as $session_name |
  ($entries | length) as $turns |
  ($entries[-1].message.model // "unknown") as $model |
  ($entries[0].cwd // "") as $raw_cwd |
  ($entries[0].gitBranch // "unknown") as $branch |
  ($entries | map(.message.usage) |
  {
    input:        (map(.input_tokens                // 0) | add // 0),
    output:       (map(.output_tokens               // 0) | add // 0),
    cache_create: (map(.cache_creation_input_tokens // 0) | add // 0),
    cache_read:   (map(.cache_read_input_tokens     // 0) | add // 0)
  }) as $u |
  ($u.input + $u.cache_read) as $denom |
  ($model |
    if test("opus")  then {i:15.0,  o:75.0, cr:1.50,  cc:18.75}
    elif test("haiku") then {i:0.80, o:4.0,  cr:0.08,  cc:1.0}
    else                    {i:3.0,  o:15.0, cr:0.30,  cc:3.75}
    end
  ) as $price |
  (($u.input * $price.i + $u.output * $price.o +
    $u.cache_read * $price.cr + $u.cache_create * $price.cc) / 1000000) as $cost_usd |
  {
    session_name: $session_name,
    turns:        $turns,
    model:        $model,
    cwd:          ($raw_cwd | split("/") | map(select(length > 0)) | last // "unknown"),
    branch:       $branch,
    input:        $u.input,
    output:       $u.output,
    cache_create: $u.cache_create,
    cache_read:   $u.cache_read,
    total:        ($u.input + $u.output + $u.cache_create),
    cache_ratio:  (if $denom > 0 then (($u.cache_read * 1000 / $denom | floor) / 10) else 0 end),
    cost_usd:     ($cost_usd * 10000 | round | . / 10000)
  }
' "$transcript_path") || exit 0

session_name=$(echo "$data" | jq -r '.session_name')
turns=$(echo "$data"        | jq -r '.turns')
model=$(echo "$data"        | jq -r '.model')
cwd=$(echo "$data"          | jq -r '.cwd')
branch=$(echo "$data"       | jq -r '.branch')
input=$(echo "$data"        | jq -r '.input')
output=$(echo "$data"       | jq -r '.output')
cache_create=$(echo "$data" | jq -r '.cache_create')
cache_read=$(echo "$data"   | jq -r '.cache_read')
total=$(echo "$data"        | jq -r '.total')
cache_ratio=$(echo "$data"  | jq -r '.cache_ratio')
cost_usd=$(echo "$data"     | jq -r '.cost_usd')

log_file="${REPO_DIR}/logs/token-usage/$(date '+%Y-%m').log"
mkdir -p "$(dirname "$log_file")"
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
duration_ms=$(hook_duration_ms "$HOOK_START_TIME")

printf '[%s] session=%-36s  name=%-20s  model=%-30s  turns=%3d  input=%6d  output=%6d  cache_read=%7d  cache_create=%6d  total=%7d  cache_ratio=%5.1f  cost_usd=%8.4f  branch=%-20s  cwd=%-20s  duration_ms=%s\n' \
  "$timestamp" "$session_id" "$session_name" "$model" "$turns" \
  "$input" "$output" "$cache_read" "$cache_create" "$total" \
  "$cache_ratio" "$cost_usd" "$branch" "$cwd" "$duration_ms" \
  >> "$log_file"
