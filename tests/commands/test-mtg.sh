#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion strings are literal Markdown excerpts; backticks must stay literal

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK="$REPO_DIR/commands/work.md"
MTG="$REPO_DIR/commands/mtg.md"
SKILL="$REPO_DIR/skills/mtg/SKILL.md"

failures=0

assert_contains() {
  local file=$1
  local pattern=$2
  local description=$3

  if rg -q --fixed-strings -- "$pattern" "$file"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

assert_absent() {
  local file=$1
  local pattern=$2
  local description=$3

  if rg -q --fixed-strings -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  else
    printf 'PASS: %s\n' "$description"
  fi
}

assert_contains "$WORK" 'label に `agenda` が完全一致で含まれる場合' 'work requires an exact agenda label match'
assert_contains "$WORK" '`commands/mtg.md` を Read' 'work delegates agenda issues to mtg'
assert_absent "$WORK" 'commands/report-review.md' 'work no longer routes report-review issues'

assert_contains "$MTG" '固定的な段階遷移は強制しません' 'mtg allows non-linear discussion'
assert_contains "$MTG" 'ユーザーが明示的に実行を指示した場合にのみ実行する' 'mtg only runs new-issue on explicit user instruction'
assert_contains "$MTG" 'ユーザーが close を宣言するまで agenda を終了しない' 'mtg leaves closure to the user'
assert_contains "$MTG" 'gh api --paginate "repos/{owner}/{repo}/issues/<番号>/comments"' 'mtg retrieves every agenda issue comment'
assert_contains "$MTG" '全コメント（過去の議事録を含む）を対話の起点として保持する' 'mtg uses prior minutes as discussion context'
assert_contains "$MTG" '今回の mtg の開始時刻として記録する' 'mtg records the meeting start time'
assert_contains "$MTG" '今回の mtg をここまでとして終了することを明示的に宣言した場合' 'mtg posts minutes when the user ends a meeting'
assert_contains "$MTG" '日付、Step 1 で記録した開始時刻、終了宣言時点の終了時刻を必ず明記する' 'mtg minutes require date and timestamps'
assert_contains "$MTG" '議事録の投稿は agenda issue の close とは別の操作である' 'mtg distinguishes minutes from closing the agenda'
assert_contains "$MTG" '**Facts**' 'mtg can structure detailed discussion as facts'
assert_contains "$MTG" '**Assessment**' 'mtg can structure detailed discussion as assessment'
assert_contains "$MTG" '**Opinions**' 'mtg can structure detailed discussion as opinions'
assert_contains "$MTG" '**Proposals**' 'mtg can structure detailed discussion as proposals'
assert_contains "$MTG" 'issue に最終要約をコメントし、issue を close する' 'mtg only closes after the user-confirmed summary'
assert_contains "$SKILL" 'commands/mtg.md' 'the skill points to the command source of truth'
assert_contains "$SKILL" 'Do not start `/new-issue` unless the user explicitly instructs it.' 'the skill preserves the explicit issue-creation gate'
assert_contains "$SKILL" 'Do not end or close an agenda unless the user explicitly declares close.' 'the skill preserves user-led closure'

if ((failures > 0)); then
  printf '\n%d contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll mtg contract tests passed.\n'
