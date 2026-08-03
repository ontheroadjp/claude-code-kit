#!/usr/bin/env bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PR_REVIEW="$REPO_DIR/commands/pr-review.md"
PR_REVIEW_EXEC="$REPO_DIR/commands/pr-review-exec.md"
GIT_PR="$REPO_DIR/commands/git-pr.md"
SKILL="$REPO_DIR/skills/pr-review/SKILL.md"
SKILL_EXEC="$REPO_DIR/skills/pr-review-exec/SKILL.md"

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

# --- commands/pr-review.md: thin orchestrator contract ---

assert_contains "$PR_REVIEW" 'MAX_REVIEW_ROUNDS=3' 'review loop is bounded'
assert_contains "$PR_REVIEW" 'AI_REVIEW_TOKEN' 'reviewer token prefers AI_REVIEW_TOKEN'
assert_contains "$PR_REVIEW" 'CODEX_REVIEW_TOKEN' 'reviewer token falls back to CODEX_REVIEW_TOKEN'
assert_contains "$PR_REVIEW" 'REVIEWER_LOGIN' 'reviewer identity is validated'
assert_contains "$PR_REVIEW" 'CURRENT_AGENT' 'the orchestrator determines which tool is currently running, not an opposite reviewer agent'
assert_absent "$PR_REVIEW" 'IMPLEMENTER_AGENT' 'the old implementer/opposite-reviewer variable naming was removed'
assert_absent "$PR_REVIEW" 'REVIEWER_AGENT' 'reviewer is no longer a separate vendor from the current agent'
assert_contains "$PR_REVIEW" 'codex exec' 'a Codex current agent spawns a fresh codex exec review sub-agent'
assert_contains "$PR_REVIEW" '--sandbox workspace-write' 'the Codex reviewer runs with a workspace-write sandbox'
assert_contains "$PR_REVIEW" 'sandbox_workspace_write.network_access=true' 'the Codex reviewer sandbox explicitly enables network access'
assert_absent "$PR_REVIEW" '--dangerously-bypass-approvals-and-sandbox' 'the Codex reviewer does not bypass the sandbox by default'
assert_contains "$PR_REVIEW" '--skip-git-repo-check' 'the Codex reviewer runs outside a git repository (scratch cwd)'
assert_contains "$PR_REVIEW" 'GH_REPO_FULL_NAME' 'the orchestrator resolves the repo full name for reviewers running outside the working tree'
assert_contains "$PR_REVIEW" 'claude -p' 'a Claude current agent spawns a fresh claude -p review sub-agent'
assert_absent "$PR_REVIEW" '--tools "Read,Bash"' 'the nonexistent --tools flag was removed (claude CLI has no --tools option)'
assert_contains "$PR_REVIEW" 'Bash(gh pr diff *),Bash(gh pr view *),Bash(gh pr review *),Bash(gh api user *)' 'the Claude reviewer allowedTools list scopes Bash to specific gh subcommands'
assert_contains "$PR_REVIEW" 'Bash(gh pr review *)' 'the Claude reviewer is only allowed to run gh pr review, not arbitrary Bash'
assert_absent "$PR_REVIEW" '"Edit"' 'the Claude reviewer is not granted the Edit tool'
assert_absent "$PR_REVIEW" '"Write"' 'the Claude reviewer is not granted the Write tool'
assert_contains "$PR_REVIEW" 'pr-review-exec.md' 'the orchestrator delegates review execution to pr-review-exec'
assert_contains "$PR_REVIEW" 'PREV_REVIEW_ID' 'the orchestrator detects whether the reviewer actually posted a new review'
assert_contains "$PR_REVIEW" 'commitId' 'the orchestrator checks the posted review is bound to the current head commit'
assert_contains "$PR_REVIEW" 'headRefOid' 'the orchestrator compares the review commit against the current PR head'
assert_contains "$PR_REVIEW" 'session-approved 外' 'fixes are limited to the approved scope'
assert_contains "$PR_REVIEW" 'ROUND == MAX_REVIEW_ROUNDS' 'the final round does not start an unreviewed fix'
assert_absent "$PR_REVIEW" 'gh pr merge ' 'the workflow contains no merge command'
assert_absent "$PR_REVIEW" 'git checkout main' 'the workflow does not check out main'
assert_absent "$PR_REVIEW" 'git pull ' 'the workflow does not pull main'
assert_absent "$PR_REVIEW" '--delete-branch' 'the workflow does not delete branches'

# The orchestrator no longer pre-computes diffs, pins SHAs, or classifies trivial rounds --
# that machinery was replaced by the reviewer fetching its own diff and posting directly.
assert_absent "$PR_REVIEW" 'TRIVIAL_FIX_MAX_LINES' 'trivial-round classification was removed from the orchestrator'
assert_absent "$PR_REVIEW" 'trivial.flag' 'trivial-round flag files were removed'
assert_absent "$PR_REVIEW" 'confirm-only' 'confirm-only review mode was removed'
assert_absent "$PR_REVIEW" 'incremental.diff' 'incremental diff generation was removed'
assert_absent "$PR_REVIEW" 'PREV_REVIEWED_SHA' 'reviewer-reported head SHA pinning was removed'
assert_absent "$PR_REVIEW" 'REVIEWED_HEAD_SHA' 'the reviewer text output contract was removed'
assert_absent "$PR_REVIEW" 'base-sha.txt' 'per-round base SHA drift files were removed'

# --- commands/pr-review-exec.md: reviewer-only self-contained contract ---

assert_contains "$PR_REVIEW_EXEC" 'REVIEW_TOKEN' 'pr-review-exec requires a review token'
assert_contains "$PR_REVIEW_EXEC" 'export GH_TOKEN="$REVIEW_TOKEN"' 'pr-review-exec exports GH_TOKEN once instead of prefixing every gh call inline'
assert_absent "$PR_REVIEW_EXEC" 'GH_TOKEN="$REVIEW_TOKEN" gh' 'inline GH_TOKEN prefixes on gh calls were removed (they break Bash allowlist pattern matching)'
assert_contains "$PR_REVIEW_EXEC" 'GH_REPO' 'pr-review-exec requires an explicit target repo (cwd may not be inside the repo)'
assert_contains "$PR_REVIEW_EXEC" '--repo "$GH_REPO"' 'pr-review-exec passes --repo explicitly on every gh pr command'
assert_contains "$PR_REVIEW_EXEC" 'REPO_ROOT' 'pr-review-exec resolves CLAUDE.md/AGENTS.md relative to an explicit repo root'
assert_contains "$PR_REVIEW_EXEC" 'codex_apps' 'pr-review-exec forbids GitHub integrations other than the gh CLI (wrong-identity risk)'
assert_contains "$PR_REVIEW_EXEC" 'REVIEWED_HEAD_SHA' 'pr-review-exec records the head SHA it reviewed'
assert_contains "$PR_REVIEW_EXEC" '一致しない場合' 'pr-review-exec refuses to post if the head changed since it fetched the diff'
assert_contains "$PR_REVIEW_EXEC" 'gh pr diff' 'pr-review-exec fetches its own diff'
assert_contains "$PR_REVIEW_EXEC" '--approve' 'pr-review-exec can post an approval'
assert_contains "$PR_REVIEW_EXEC" '--request-changes' 'pr-review-exec can post a change request'
assert_contains "$PR_REVIEW_EXEC" '他のコマンドは実行しない' 'pr-review-exec does not invoke other commands'
assert_absent "$PR_REVIEW_EXEC" 'gh pr merge' 'pr-review-exec cannot merge'
assert_absent "$PR_REVIEW_EXEC" 'git commit' 'pr-review-exec does not commit'
assert_absent "$PR_REVIEW_EXEC" 'git push' 'pr-review-exec does not push'

# --- integration points ---

assert_contains "$GIT_PR" '/pr-review #${PR_NUMBER}' 'git-pr hands a created PR to pr-review'
assert_contains "$SKILL" 'commands/pr-review.md' 'the pr-review skill points to the command source of truth'
assert_contains "$SKILL_EXEC" 'commands/pr-review-exec.md' 'the pr-review-exec skill points to the command source of truth'

if ((failures > 0)); then
  printf '\n%d contract test(s) failed.\n' "$failures"
  exit 1
fi

printf '\nAll pr-review contract tests passed.\n'
