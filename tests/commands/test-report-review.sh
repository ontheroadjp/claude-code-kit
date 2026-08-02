#!/usr/bin/env bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK="$REPO_DIR/commands/work.md"
REPORT_REVIEW="$REPO_DIR/commands/report-review.md"
SKILL="$REPO_DIR/skills/report-review/SKILL.md"

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

assert_contains "$WORK" "gh issue view <issue番号> --json labels --jq '.labels[].name'" 'work reads issue labels before implementation routing'
assert_contains "$WORK" 'label の name が `report` と完全一致する場合' 'work requires an exact report label match'
assert_contains "$WORK" '`commands/report-review.md` を Read' 'work delegates report issues to report-review'
assert_contains "$WORK" '`commands/task.md`' 'work retains task routing'
assert_contains "$WORK" '`commands/patch.md`' 'work retains patch routing'

assert_contains "$REPORT_REVIEW" 'gh issue view <番号> --json number,title,body,labels,url,state' 'report-review retrieves the complete issue context'
assert_contains "$REPORT_REVIEW" 'ファイルの作成・編集・削除は禁止' 'report-review forbids file changes'
assert_contains "$REPORT_REVIEW" 'GitHub issue / PR の変更は禁止' 'report-review forbids GitHub changes'
assert_contains "$REPORT_REVIEW" '評価結果は GitHub へ投稿せず、標準出力にだけ提示する' 'report-review outputs locally only'
assert_contains "$REPORT_REVIEW" '### Facts' 'report-review separates verified facts'
assert_contains "$REPORT_REVIEW" '### Opinions' 'report-review includes opinions'
assert_contains "$REPORT_REVIEW" '### Proposals' 'report-review includes proposals'
assert_contains "$REPORT_REVIEW" '### Risks and Unknowns' 'report-review exposes uncertainty'

assert_absent "$REPORT_REVIEW" 'gh issue edit ' 'report-review contains no issue edit command'
assert_absent "$REPORT_REVIEW" 'gh issue comment ' 'report-review contains no issue comment command'
assert_absent "$REPORT_REVIEW" 'gh pr create ' 'report-review contains no PR creation command'
assert_absent "$REPORT_REVIEW" 'git commit ' 'report-review contains no commit command'
assert_absent "$REPORT_REVIEW" 'git push ' 'report-review contains no push command'

assert_contains "$SKILL" 'commands/report-review.md' 'the skill points to the command source of truth'
assert_contains "$SKILL" 'Do not create, edit, or delete files.' 'the skill preserves the read-only boundary'

if ((failures > 0)); then
  printf '\n%d contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll report-review contract tests passed.\n'
