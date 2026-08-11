#!/usr/bin/env bash
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SCAN="$REPO_DIR/commands/analyze-hazard-scan.md"
TRIAGE="$REPO_DIR/commands/triage-issues-for-hazard.md"
WORK="$REPO_DIR/commands/work.md"

assert_contains() {
  local file=$1 pattern=$2 description=$3
  if rg -q --fixed-strings -- "$pattern" "$file"; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    return 1
  fi
}

assert_contains "$SCAN" 'scripts/analyze_auto_approve.py --all' 'scan aggregates auto-approve logs'
assert_contains "$SCAN" 'scripts/analyze_access.py --all' 'scan aggregates access logs'
assert_contains "$SCAN" 'hazard-candidate' 'scan files generic candidate issues'
assert_contains "$SCAN" 'access 候補はコマンド承認ログではないため `--explain` を実行しない' 'access uses source-appropriate diagnostics'
assert_contains "$TRIAGE" 'gh issue list --label hazard-candidate' 'triage selects generic candidate issues'
assert_contains "$TRIAGE" '--remove-label "hazard-candidate" --add-label "triage-approved"' 'triage clears the work gate on approval'
assert_contains "$WORK" '`hazard-candidate` が完全一致' 'work gates generic candidate issues'

if rg -q 'auto-approve-candidate|auto-approve-hazard-scan|triage-issues-for-auto-approve' commands skills README.md CLAUDE.md; then
  printf 'FAIL: legacy hazard names remain in active workflow files\n'
  exit 1
fi

printf 'All hazard workflow contract tests passed.\n'
