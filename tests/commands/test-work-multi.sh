#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion strings below are literal doc excerpts; $ must stay literal

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK="$REPO_DIR/commands/work.md"
WORK_MULTI="$REPO_DIR/commands/work-multi.md"
WORK_SKILL="$REPO_DIR/skills/work/SKILL.md"
WORK_MULTI_SKILL="$REPO_DIR/skills/work-multi/SKILL.md"
LINK_SCRIPT="$REPO_DIR/scripts/link-worktree-untracked.sh"

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

assert_executable() {
  local file=$1
  local description=$2

  if [ -x "$file" ]; then
    printf 'PASS: %s\n' "$description"
  else
    printf 'FAIL: %s\n' "$description"
    failures=$((failures + 1))
  fi
}

# --- commands/work-multi.md: worktree switch + delegation only, no duplicated gate logic ---
assert_contains "$WORK_MULTI" 'EnterWorktree' 'work-multi calls EnterWorktree'
# shellcheck disable=SC2088  # Literal documentation excerpts must retain the installed ~ path.
assert_contains "$WORK_MULTI" '~/.claude/scripts/link-worktree-untracked.sh' "work-multi invokes Claude Code's installed linker script"
# shellcheck disable=SC2088  # Literal documentation excerpts must retain the installed ~ path.
assert_contains "$WORK_MULTI" '~/.codex/scripts/link-worktree-untracked.sh' "work-multi invokes Codex CLI's installed linker script"
assert_absent "$WORK_MULTI" 'bash scripts/link-worktree-untracked.sh' 'work-multi does not require a linker script in the consumer repository'
assert_contains "$WORK_MULTI" 'commands/work.md' 'work-multi delegates to commands/work.md'
assert_contains "$WORK_MULTI" '一字一句そのまま実行する' 'work-multi executes work.md verbatim, no reinterpretation'
assert_absent "$WORK_MULTI" '### G-0' 'work-multi does not duplicate work.md gate definitions'
assert_absent "$WORK_MULTI" '### G-1' 'work-multi does not duplicate work.md gate definitions'
assert_absent "$WORK_MULTI" '### G-2' 'work-multi does not duplicate work.md gate definitions'

# --- skills/work-multi/SKILL.md mirrors skills/work/SKILL.md's pattern ---
assert_contains "$WORK_MULTI_SKILL" 'commands/work-multi.md' 'the skill points to commands/work-multi.md as source of truth'
assert_contains "$WORK_MULTI_SKILL" 'Do not edit `commands/work-multi.md` from this skill.' 'the skill preserves the scope guard against editing the command'
assert_contains "$WORK_SKILL" 'Do not edit `commands/work.md` from this skill.' 'the work skill has the equivalent scope guard (pattern reference)'

# --- commands/work.md: worktree-path guard and branch-classification predicate ---
assert_contains "$WORK" '.claude/worktrees/' 'work.md G-0 checks for the EnterWorktree worktree path'
assert_contains "$WORK" 'git checkout main' 'work.md G-0 still performs the normal main checkout'
assert_contains "$WORK" 'worktree-` で始まるブランチ' 'work.md branch classification checks the worktree- prefix only'
assert_contains "$WORK" '未コミット変更がある' 'work.md preserves the uncommitted-changes resume check (B.1) for any other non-main branch'

# --- scripts/link-worktree-untracked.sh exists and is executable ---
assert_executable "$LINK_SCRIPT" 'link-worktree-untracked.sh is executable'
assert_contains "$LINK_SCRIPT" 'status --porcelain -z --ignored=matching' 'link-worktree-untracked.sh enumerates untracked/ignored paths via NUL-delimited porcelain output'
assert_contains "$LINK_SCRIPT" '.git|.git/*|.claude|.claude/*' 'link-worktree-untracked.sh excludes .git/.claude and their nested paths'

if ((failures > 0)); then
  printf '\n%d work-multi contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll work-multi contract tests passed.\n'
