#!/usr/bin/env bash
# shellcheck disable=SC2016  # assertion strings below are literal doc excerpts; $ must stay literal

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK="$REPO_DIR/commands/work.md"
WORK_MULTI="$REPO_DIR/commands/work-multi.md"
WORK_SKILL="$REPO_DIR/skills/work/SKILL.md"
WORK_MULTI_SKILL="$REPO_DIR/skills/work-multi/SKILL.md"
LINK_SCRIPT="$REPO_DIR/scripts/link-worktree-untracked.sh"
STATUS_SCRIPT="$REPO_DIR/scripts/worktree-status.sh"

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

# --- commands/work-multi.md: worktree switch + delegation, no duplicated workflow logic ---
assert_contains "$WORK_MULTI" 'EnterWorktree' 'work-multi calls EnterWorktree'
# shellcheck disable=SC2088  # Literal documentation excerpts must retain the installed ~ path.
assert_contains "$WORK_MULTI" '~/.claude/scripts/link-worktree-untracked.sh' "work-multi invokes Claude Code's installed linker script"
# shellcheck disable=SC2088  # Literal documentation excerpts must retain the installed ~ path.
assert_contains "$WORK_MULTI" '~/.codex/scripts/link-worktree-untracked.sh' "work-multi invokes Codex CLI's installed linker script"
assert_contains "$WORK_MULTI" 'prepare "<0.1 で得た ORIGINAL_WORKDIR の絶対パス>"' 'work-multi prepares the lazy linker without eager links'
assert_contains "$WORK_MULTI" 'Step 0.3 の lazy linker `prepare` 引数にのみ' 'work-multi restricts ORIGINAL_WORKDIR to linker preparation'
assert_contains "$WORK_MULTI" '共有 checkout に `cd` したり、`git -C "$ORIGINAL_WORKDIR"` を使ったりしてはならない' 'work-multi keeps commands in the isolated worktree'
assert_contains "$WORK_MULTI" '`commands/work.md` の Read、現状調査、Git 操作はすべてこの worktree から実行する' 'work-multi runs all workflow operations from the isolated worktree'
assert_contains "$WORK_MULTI" 'link "site/node_modules"' 'work-multi documents linking an explicitly needed path'
assert_contains "$WORK_MULTI" 'lazy link した path は読み取り専用として扱う' 'work-multi treats lazy-linked paths as read-only'
assert_contains "$WORK_MULTI" 'symlink 経由でその path を書き換えるコマンドは実行してはならない' 'work-multi prohibits writes through lazy symlinks'
assert_contains "$WORK_MULTI" '書き込みが必要な path は link する前に、worktree 内へ独立して作成する' 'work-multi requires writable paths to be created independently'
assert_contains "$WORK_MULTI" 'venv <relative-path>' 'work-multi documents the venv subcommand for venv/.venv paths'
assert_contains "$WORK_MULTI" 'link-worktree-untracked.sh venv ".venv"' 'work-multi documents the venv build usage example'
assert_contains "$WORK_MULTI" 'basename が `venv`・`.venv` のいずれでもない場合' 'work-multi documents venv basename restriction'
assert_contains "$WORK_MULTI" '`.gitignore` で ignore されていない場合に失敗する' 'work-multi documents the .gitignore enforcement for venv builds'
assert_contains "$WORK_MULTI" '`venv` サブコマンドで構築した venv/.venv はこの制限の対象外であり' 'work-multi documents that venv-built directories are writable, unlike lazy-linked paths'
assert_absent "$WORK_MULTI" 'bash scripts/link-worktree-untracked.sh' 'work-multi does not require a linker script in the consumer repository'
assert_contains "$WORK_MULTI" 'commands/work.md' 'work-multi delegates to commands/work.md'
assert_contains "$WORK_MULTI" '一字一句そのまま実行する' 'work-multi executes work.md verbatim, no reinterpretation'
assert_contains "$WORK_MULTI" '親 issue の検出、未完了の子 issue の依存関係確認、次に実行すべき子 issue の報告と終了は、`commands/work.md` が一元的に担います' 'work-multi delegates parent-issue handling to work.md'
assert_absent "$WORK_MULTI" 'gh issue view <子issue番号> --json number,title,state,blockedBy' 'work-multi does not duplicate child dependency lookup'
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
assert_contains "$WORK" '親 issue・label の事前ルーティング' 'work.md checks parent issues before label routing'
assert_contains "$WORK" 'subIssues' 'work.md reads native GitHub sub-issues'
assert_contains "$WORK" '本文の未完了 task list' 'work.md supports existing parent task lists'
assert_contains "$WORK" 'blockedBy' 'work.md reads native GitHub issue dependencies'
assert_contains "$WORK" '全 issue が `CLOSED`' 'work.md only selects children whose blockers are closed'
assert_contains "$WORK" '次は `/work #<子issue番号>` を実行してください' 'work.md reports the next child issue and exits'
assert_contains "$WORK" '選んだ子 issue の実装、`/task`・`/patch` へのルーティング、ブランチ作成は行わない' 'work.md never implements a selected child automatically'
assert_contains "$WORK" '子 issue が 0 件の場合に限り、以下の label 判定へ進む' 'work.md skips label routing for parent issues'

# --- scripts/link-worktree-untracked.sh exists and is executable ---
assert_executable "$LINK_SCRIPT" 'link-worktree-untracked.sh is executable'
assert_executable "$STATUS_SCRIPT" 'worktree-status.sh is executable'
assert_contains "$LINK_SCRIPT" 'status --porcelain -z --ignored=matching' 'link-worktree-untracked.sh enumerates untracked/ignored paths via NUL-delimited porcelain output'
assert_contains "$LINK_SCRIPT" '.git|.git/*|.claude|.claude/*' 'link-worktree-untracked.sh excludes .git/.claude and their nested paths'
assert_contains "$LINK_SCRIPT" 'venv|.venv)' 'link-worktree-untracked.sh restricts the venv subcommand to venv/.venv basenames'
assert_contains "$LINK_SCRIPT" 'command -v uv' 'link-worktree-untracked.sh requires uv for the venv subcommand'
assert_contains "$LINK_SCRIPT" 'git check-ignore -q -- "${relative_path}/"' 'link-worktree-untracked.sh verifies venv targets are gitignored before building'
assert_contains "$LINK_SCRIPT" 'uv venv "$relative_path"' 'link-worktree-untracked.sh builds the venv via uv instead of symlinking'
assert_contains "$WORK" 'worktree-status.sh' 'work.md delegates self-created symlink filtering to the shared status helper'
assert_contains "$STATUS_SCRIPT" 'worktree-untracked-symlinks.txt' 'worktree-status.sh reads the linker manifest'

if ((failures > 0)); then
  printf '\n%d work-multi contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll work-multi contract tests passed.\n'
