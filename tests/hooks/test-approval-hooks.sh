#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD_HOOK="${REPO_DIR}/hooks/guard-destructive-cmd.sh"
CLEANUP_HOOK="${REPO_DIR}/hooks/cleanup-session.sh"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_REPO_DIR="${TMP_DIR}/repo"
mkdir -p "${TEST_REPO_DIR}/hooks/lib"
cp "${REPO_DIR}/hooks/auto-approve-readonly.sh" "${TEST_REPO_DIR}/hooks/auto-approve-readonly.sh"
cp "${REPO_DIR}/hooks/lib/approval-safety.sh" "${TEST_REPO_DIR}/hooks/lib/approval-safety.sh"
AUTO_HOOK="${TEST_REPO_DIR}/hooks/auto-approve-readonly.sh"
LOG_FILE="${TEST_REPO_DIR}/logs/auto-approve/$(date '+%Y-%m').log"
SESSION_FILE="${TMP_DIR}/session-approved"
SESSION_ID="test-session-fixed"
TMP_ROOT="${TMP_DIR}/tmp-root"
SESSION_TMP_DIR="${TMP_ROOT}/${SESSION_ID}"

run_auto() {
    local command="$1"
    jq -cn --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' \
        | env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_BY_BUN -u CODEX_CI -u CODEX_THREAD_ID \
            CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            CLAUDE_CODE_KIT_SESSION_ID="$SESSION_ID" \
            CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="$SESSION_FILE" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash "$AUTO_HOOK"
}

run_auto_file_tool() {
    local tool_name="$1" file_path="$2"
    jq -cn --arg tool_name "$tool_name" --arg file_path "$file_path" \
        '{tool_name:$tool_name,tool_input:{file_path:$file_path}}' \
        | CODEX_CI=1 \
            CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            CLAUDE_CODE_KIT_SESSION_ID="$SESSION_ID" \
            CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="$SESSION_FILE" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash "$AUTO_HOOK"
}

run_auto_codex_symlink() {
    local command="$1"
    local codex_hook_dir="${TMP_DIR}/.codex/hooks"
    local codex_hook="${codex_hook_dir}/auto-approve-readonly.sh"
    mkdir -p "$codex_hook_dir"
    ln -sf "$AUTO_HOOK" "$codex_hook"
    jq -cn --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' \
        | CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            CLAUDE_CODE_KIT_SESSION_ID="$SESSION_ID" \
            CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="$SESSION_FILE" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash "$codex_hook"
}

run_cleanup() {
    local session_id="$1"
    jq -cn --arg session_id "$session_id" '{session_id:$session_id}' \
        | CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash "$CLEANUP_HOOK"
}

run_auto_without_session() {
    local command="$1"
    jq -cn --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' \
        | env -u CLAUDE_CODE_KIT_SESSION_ID \
            -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_BY_BUN -u CODEX_CI -u CODEX_THREAD_ID \
            CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            bash "$AUTO_HOOK"
}

run_guard() {
    local command="$1"
    jq -cn --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' \
        | bash "$GUARD_HOOK"
}

assert_json_decision() {
    local output="$1" expected="$2"
    local actual
    actual=$(printf '%s' "$output" | jq -r '.decision')
    if [ "$actual" != "$expected" ]; then
        printf 'Expected decision=%s, got decision=%s\nOutput: %s\n' "$expected" "$actual" "$output" >&2
        exit 1
    fi
}

assert_no_output() {
    local output="$1"
    if [ -n "$output" ]; then
        printf 'Expected no output, got: %s\n' "$output" >&2
        exit 1
    fi
}

assert_log_matches() {
    local pattern="$1"
    local line
    line=$(tail -n 1 "$LOG_FILE")
    if ! printf '%s' "$line" | grep -qE "$pattern"; then
        printf 'Log line did not match pattern %s\nLine: %s\n' "$pattern" "$line" >&2
        exit 1
    fi
}

output=$(run_auto 'git reset --hard')
assert_json_decision "$output" "block"

output=$(run_auto 'rm -fr /usr')
assert_json_decision "$output" "block"

for command in \
    'nl -ba README.md' \
    'cd site' \
    'test -f README.md && echo present' \
    'if [ -f README.md ]; then sed -n '\''1p'\'' README.md; else echo missing; fi' \
    'gh pr checks 143' \
    'git -C /tmp status --porcelain' \
    'rg -n "foo|bar" README.md' \
    'printf value | sed -n '\''1p'\''' \
    'sed -n '\''/error/p'\'' README.md' \
    'sed -e '\''s/error/warning/'\'' README.md' \
    'awk '\''{ getline value; print value }'\'' README.md' \
    'curl --head localhost' \
    'curl -sSI localhost' \
    'node --version' \
    'npm --version' \
    'python --version' \
    'go version' \
    'bash --version' \
    'npm view vitepress version' \
    'npm list --depth=0' \
    'npm config get registry' \
    'npm run' \
    'git merge-base main HEAD' \
    'git merge-base --is-ancestor main HEAD' \
    'pgrep -f node' \
    'gh api repos/octocat/hello-world' \
    'gh api repos/octocat/hello-world --paginate' \
    'gsettings get org.gnome.desktop.interface gtk-theme' \
    'gsettings list-recursively org.gnome.desktop.interface' \
    'journalctl -u ssh -n 50' \
    'journalctl --since today' \
    'gnome-extensions info example-extension-uuid' \
    'gnome-extensions list' \
    'bash -n script.sh' \
    'node --check script.js' \
    'node -c script.js'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

output=$(run_auto $'git diff --check\nnode --version\ncd site')
assert_json_decision "$output" "approve"

output=$(run_auto $'gh pr view 143 --json mergeable,mergeStateStatus,isDraft,state,url,headRefOid\ngh pr checks 143')
assert_json_decision "$output" "approve"

for command in \
    'if [ -f README.md ]; then touch unsafe; fi' \
    'printf value | some-unknown-command' \
    'echo value & touch unsafe' \
    'git branch new-branch' \
    'git branch -d old-branch' \
    'git remote add origin ../repo.git' \
    'git tag v1.0.0' \
    'git tag -d v1.0.0' \
    'git reflog expire --all' \
    'git config user.name example' \
    'git diff --output=/tmp/diff.txt' \
    'find . -delete' \
    'sed -i s/a/b/ README.md' \
    'sed -e '\''w unsafe-output'\'' README.md' \
    'sed '\''1w unsafe-output'\'' README.md' \
    'sed -e '\''e touch unsafe-output'\'' README.md' \
    'sort -o /tmp/sorted README.md' \
    'yq -i .key=value config.yml' \
    'awk '\''BEGIN { system("touch /tmp/unsafe") }'\''' \
    'awk '\''BEGIN { "touch unsafe-output" | getline result }'\''' \
    'env echo value' \
    'date --set tomorrow' \
    'hostname changed-host' \
    'curl -X POST localhost' \
    'curl --data value localhost' \
    'curl -dvalue localhost' \
    'curl -T artifact localhost' \
    'curl -oartifact localhost' \
    'curl -K curl.conf localhost' \
    'curl -so unsafe-output localhost' \
    'curl -sO localhost/file' \
    'npm run docs:build' \
    'npm publish' \
    'npm audit --fix' \
    'npm exec tool' \
    'npm test' \
    'npm version patch' \
    'bash version' \
    'python -v script.py' \
    'ruby version' \
    'pytest' \
    'python -m pytest' \
    'echo "$(some-unknown-command)"' \
    'cat <(some-unknown-command)' \
    'git merge-base --output=/tmp/x main HEAD' \
    'gsettings set org.gnome.desktop.interface gtk-theme Adwaita' \
    'gsettings reset org.gnome.desktop.interface gtk-theme' \
    'journalctl --vacuum-time=1s' \
    'journalctl --rotate' \
    'journalctl --flush' \
    'journalctl --update-catalog' \
    'journalctl --smart-relinquish-var' \
    'gh api repos/octocat/hello-world -X POST' \
    'gh api repos/octocat/hello-world -XPOST' \
    'gh api repos/octocat/hello-world -f key=value' \
    'gh api repos/octocat/hello-world -fkey=value' \
    'gh api repos/octocat/hello-world -Fkey=value' \
    'gh api repos/octocat/hello-world --input body.json' \
    'gnome-extensions disable example-extension-uuid' \
    'gnome-extensions enable example-extension-uuid' \
    'bash -n -c "echo hi"' \
    'bash script.sh' \
    'node --check -e "process.exit(1)"' \
    'node --check -r ./side-effect.js target.js' \
    'node --check --require ./side-effect.js target.js' \
    'node --check --import ./side-effect.js target.js' \
    'node --check --experimental_loader=./side-effect.js target.js' \
    'node --check --experimental-config-file=./config.json target.js' \
    'node --check ./a.js ./b.js' \
    'bash -n -x script.sh' \
    'bash -n script.sh extra-arg' \
    'node script.js'; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# $() with read-only content → approve
for command in \
    'PR_BODY=$(cat /tmp/file)' \
    'SYNC_RESULT=$(cat /tmp/other)' \
    'SESSION_ID=$(basename "$(dirname "/tmp/x")" 2>/dev/null)' \
    'echo "$(cat /tmp/file)"' \
    $'PR_BODY=$(cat /tmp/a)\nSYNC=$(cat /tmp/b)'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

# $() with unsafe content → prompt fallback
for command in \
    'VAR=$(rm -rf /tmp/x)' \
    'VAR=$(curl -o /tmp/file http://example.com)' \
    'VAR=$(some-unknown-command)'; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# Unquoted variable expansion bypass: a pure-assignment segment stages a
# dangerous flag string, and a later unquoted reference smuggles it past an
# exclusion-based/single-token-shape allowlist check. All must prompt fallback.
for command in \
    'ARGS="--require=./side-effect.js target.js"; node --check $ARGS' \
    "FILE='script.sh extra-arg'; bash -n \$FILE" \
    "OPTS='-o /tmp/evil http://example.com'; curl \$OPTS" \
    "OPTS='-XPOST'; gh api repos/octocat/hello-world \$OPTS" \
    "GITOPT='--output=/tmp/evil'; git diff \$GITOPT" \
    "SEDOPT='-i'; sed \$SEDOPT s/a/b/ README.md" \
    "FINDOPT='-delete'; find . \$FINDOPT" \
    "SORTOPT='-o /tmp/sorted'; sort \$SORTOPT README.md" \
    "DATEOPT='--set tomorrow'; date \$DATEOPT" \
    "JOPT='--rotate'; journalctl \$JOPT"; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# Unquoted variable expansion in flag-invariant plain tools remains safe and
# stays auto-approved (no exclusion/single-token-shape check to bypass).
for command in \
    'FILE=README.md; cat $FILE' \
    'FILE=README.md; grep -n foo $FILE'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

# awk script field references ($1, $2, ...) inside a single-quoted script are
# not flagged as unquoted variable expansion.
output=$(run_auto 'awk '\''{ print $1 }'\'' README.md')
assert_json_decision "$output" "approve"

# Round-2 review findings: (1) normalize_git_directory_prefix discards the
# "-C <dir>" operand before the variable guard ran, hiding a variable placed
# there; (2) a double-quoted "$VAR" is not word-split but its resolved value
# can still itself be a single dangerous flag, invisible to exclusion scans;
# (3) escape handling ran before the single-quote check, so a literal
# backslash immediately before a closing single quote (e.g. 'foo\') was
# misread as escaping it, desyncing quote-tracking for the rest of the
# segment. All must prompt fallback.
for command in \
    "DIR='repo branch -D victim'; git -C \$DIR diff" \
    'OUT="--output=/tmp/evil"; git diff "$OUT"' \
    "OPTS='-o /tmp/evil'; curl --user-agent 'foo\\' \$OPTS https://example.com" \
    "YQOPT='-i'; yq \$YQOPT .key=value config.yml" \
    "SCRIPT='{system(\"touch unsafe\")}'; awk \$SCRIPT README.md" \
    "OPTS='-o /tmp/evil'; curl --user-agent \"foo'bar\" \$OPTS https://example.com"; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# Round-3 review finding: _extract_subshell_contents / _strip_subshells had
# no escape handling, so an escaped double quote (\") inside a $(...)
# argument was misread as closing the string, miscounting paren depth for
# the rest of the segment. When depth never returns to 0, the trailing text
# (including a variable reference) is silently dropped from what
# _has_variable_expansion ever sees, so it auto-approves. Must prompt fallback.
output=$(run_auto 'OPTS='"'"'-o /tmp/evil'"'"'; curl $(printf https://example.com "\"(") $OPTS')
assert_no_output "$output"

mkdir -p "$(dirname "$SESSION_FILE")"
printf '%s\n' 'tool:git_write' > "$SESSION_FILE"
output=$(run_auto 'git reset --hard')
assert_json_decision "$output" "block"

output=$(run_auto 'git status --porcelain')
assert_json_decision "$output" "approve"
assert_log_matches '] agent=claude session=test-session-fixed result=approved[[:space:]]+tool=Bash[[:space:]]+git status --porcelain$'

output=$(run_auto_codex_symlink 'git status --porcelain')
assert_json_decision "$output" "allow"
assert_log_matches '] agent=codex session=test-session-fixed result=approved[[:space:]]+tool=Bash[[:space:]]+git status --porcelain$'

output=$(run_auto_without_session 'git status --porcelain')
assert_json_decision "$output" "approve"
assert_log_matches '] agent=claude session=n/a result=approved[[:space:]]+tool=Bash[[:space:]]+git status --porcelain$'

output=$(run_auto 'git add hooks/auto-approve-readonly.sh')
assert_json_decision "$output" "approve"

for command in \
    'git fetch origin main' \
    'git -C /tmp fetch origin main' \
    'git pull --ff-only origin main' \
    'git branch -d merged-branch'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

output=$(run_auto $'git status --porcelain\ngit checkout main\ngit pull --ff-only origin main\ngit status --short\ngit log -1 --oneline')
assert_json_decision "$output" "approve"

output=$(run_auto 'test -d . && git branch --show-current && test -f README.md')
assert_json_decision "$output" "approve"

output=$(run_auto $'if [ -f ~/.config/claude-code-kit/partials/git-commit.md ]; then\n  sed -n '\''1,280p'\'' ~/.config/claude-code-kit/partials/git-commit.md\nelse\n  sed -n '\''1,280p'\'' partials/git-commit.md\nfi\ngit add docs/L3_implementation/specification_summary.md\ngit diff --staged\ngit commit -m "docs: sync documentation"\ngit push origin feature\ngit status --porcelain')
assert_json_decision "$output" "approve"

for command in \
    'git pull origin main' \
    'git pull --ff-only --rebase origin main' \
    'gh pr merge 143'; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

for command in \
    'git push origin +main:main' \
    'git checkout -f main' \
    'git checkout --force main' \
    'git switch --force main' \
    'git branch --delete --force old-branch' \
    'git branch -df old-branch'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "block"
done

printf '%s\n' 'tool:git_write' 'tool:gh_pr_write' > "$SESSION_FILE"
output=$(run_auto 'gh pr merge 143')
assert_json_decision "$output" "approve"

output=$(run_auto_file_tool "Write" "${SESSION_TMP_DIR}/scratch.txt")
assert_json_decision "$output" "allow"

output=$(run_auto_file_tool "Edit" "${SESSION_TMP_DIR}/scratch.txt")
assert_json_decision "$output" "allow"

output=$(run_auto_file_tool "Write" "${TMP_ROOT}/other-session/scratch.txt")
assert_no_output "$output"

rm -rf "$SESSION_TMP_DIR"
mkdir -p "$TMP_ROOT" "${TMP_DIR}/symlink-target"
ln -s "${TMP_DIR}/symlink-target" "$SESSION_TMP_DIR"
output=$(run_auto_file_tool "Write" "${SESSION_TMP_DIR}/scratch.txt")
assert_no_output "$output"
rm -f "$SESSION_TMP_DIR"

output=$(run_auto 'gh run rerun 12345')
assert_no_output "$output"

output=$(run_auto 'some-unknown-command --flag')
assert_no_output "$output"

output=$(run_guard 'git reset --hard')
assert_json_decision "$output" "block"

for command in \
    'git push origin +main:main' \
    'git checkout --force main' \
    'git branch --delete --force old-branch'; do
    output=$(run_guard "$command")
    assert_json_decision "$output" "block"
done

output=$(run_guard 'git status --porcelain')
assert_no_output "$output"

output=$(run_guard 'test -d . && git branch --show-current && test -f README.md')
assert_no_output "$output"

run_cleanup "$SESSION_ID"

# --- Working repo dynamic defense tests ---

TEST_GIT_REPO="${TMP_DIR}/test-git-repo"
mkdir -p "$TEST_GIT_REPO"
git -C "$TEST_GIT_REPO" init -q
git -C "$TEST_GIT_REPO" config user.email "ci-test-noreply"
git -C "$TEST_GIT_REPO" config user.name "Test"
echo "initial" > "${TEST_GIT_REPO}/initial.txt"
git -C "$TEST_GIT_REPO" add -A
git -C "$TEST_GIT_REPO" commit --no-verify -q -m "initial commit"

run_auto_in_repo() {
    local command="$1"
    jq -cn --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' \
        | env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_BY_BUN -u CODEX_CI -u CODEX_THREAD_ID \
            CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            CLAUDE_CODE_KIT_SESSION_ID="$SESSION_ID" \
            CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="$SESSION_FILE" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash -c "cd '$TEST_GIT_REPO' && bash '$AUTO_HOOK'"
}

run_file_tool_in_repo() {
    local tool_name="$1" file_path="$2"
    jq -cn --arg tool_name "$tool_name" --arg file_path "$file_path" \
        '{tool_name:$tool_name,tool_input:{file_path:$file_path}}' \
        | env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_BY_BUN -u CODEX_CI -u CODEX_THREAD_ID \
            CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            CLAUDE_CODE_KIT_SESSION_ID="$SESSION_ID" \
            CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="$SESSION_FILE" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash -c "cd '$TEST_GIT_REPO' && bash '$AUTO_HOOK'"
}

run_apply_patch_in_repo() {
    jq -cn '{tool_name:"apply_patch",tool_input:{patch:"dummy"}}' \
        | env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_BY_BUN -u CODEX_CI -u CODEX_THREAD_ID \
            CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            CLAUDE_CODE_KIT_SESSION_ID="$SESSION_ID" \
            CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="$SESSION_FILE" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash -c "cd '$TEST_GIT_REPO' && bash '$AUTO_HOOK'"
}

# Write on repo-internal path → approved
output=$(run_file_tool_in_repo "Write" "${TEST_GIT_REPO}/new.txt")
assert_json_decision "$output" "approve"

# Write outside repo → user_prompt
output=$(run_file_tool_in_repo "Write" "/tmp/outside.txt")
assert_no_output "$output"

# Edit on repo-internal path → approved
output=$(run_file_tool_in_repo "Edit" "${TEST_GIT_REPO}/initial.txt")
assert_json_decision "$output" "approve"

# Edit outside repo → user_prompt
output=$(run_file_tool_in_repo "Edit" "/tmp/outside.txt")
assert_no_output "$output"

# apply_patch inside repo → approved
output=$(run_apply_patch_in_repo)
assert_json_decision "$output" "approve"

# apply_patch outside any repo → user_prompt
output=$(jq -cn '{tool_name:"apply_patch",tool_input:{patch:"dummy"}}' \
    | env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_BY_BUN -u CODEX_CI -u CODEX_THREAD_ID \
        CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
        CLAUDE_CODE_KIT_SESSION_ID="$SESSION_ID" \
        CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="$SESSION_FILE" \
        CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
        bash -c "cd /tmp && bash '$AUTO_HOOK'")
assert_no_output "$output"

# make dirty state for WIP commit tests
echo "modified" >> "${TEST_GIT_REPO}/initial.txt"

# rm -rf on repo-internal subdir → approved + WIP commit created
mkdir -p "${TEST_GIT_REPO}/subdir"
commits_before=$(git -C "$TEST_GIT_REPO" log --oneline | wc -l | tr -d ' ')
output=$(run_auto_in_repo "rm -rf ${TEST_GIT_REPO}/subdir")
assert_json_decision "$output" "approve"
commits_after=$(git -C "$TEST_GIT_REPO" log --oneline | wc -l | tr -d ' ')
if [ "$commits_after" -le "$commits_before" ]; then
    printf 'Expected WIP commit to be created for rm -rf, got %s (before %s)\n' \
        "$commits_after" "$commits_before" >&2
    exit 1
fi
if ! git -C "$TEST_GIT_REPO" log --oneline -1 | grep -q "wip:"; then
    printf 'Expected latest commit to be a wip: commit\n' >&2
    exit 1
fi

# rm -rf on system directory → blocked (static defense, unaffected by repo check)
output=$(run_auto_in_repo "rm -rf /usr")
assert_json_decision "$output" "block"

# rm -rf on repo root itself → NOT approved by dynamic defense (defeats safety net)
output=$(run_auto_in_repo "rm -rf ${TEST_GIT_REPO}")
assert_no_output "$output"

# rm -rf with variable → NOT approved (ambiguous, falls to approval_safety)
output=$(run_auto_in_repo 'rm -rf $SOME_DIR')
assert_no_output "$output"

# rm -rf with multiple paths → NOT approved (ambiguous)
output=$(run_auto_in_repo "rm -rf ${TEST_GIT_REPO}/a ${TEST_GIT_REPO}/b")
assert_no_output "$output"

# Write on repo-internal path with dirty tree → WIP commit is created
echo "more changes" >> "${TEST_GIT_REPO}/initial.txt"
commits_before=$(git -C "$TEST_GIT_REPO" log --oneline | wc -l | tr -d ' ')
output=$(run_file_tool_in_repo "Write" "${TEST_GIT_REPO}/initial.txt")
assert_json_decision "$output" "approve"
commits_after=$(git -C "$TEST_GIT_REPO" log --oneline | wc -l | tr -d ' ')
if [ "$commits_after" -le "$commits_before" ]; then
    printf 'Expected WIP commit for Write with dirty tree, got %s (before %s)\n' \
        "$commits_after" "$commits_before" >&2
    exit 1
fi

# Write on repo-internal path with clean tree → still approved (no WIP commit needed)
# The WIP commit above captured all dirty changes, so tree is now clean
commits_before=$(git -C "$TEST_GIT_REPO" log --oneline | wc -l | tr -d ' ')
output=$(run_file_tool_in_repo "Write" "${TEST_GIT_REPO}/initial.txt")
assert_json_decision "$output" "approve"
commits_after=$(git -C "$TEST_GIT_REPO" log --oneline | wc -l | tr -d ' ')
if [ "$commits_after" -ne "$commits_before" ]; then
    printf 'Expected no WIP commit for Write on clean tree, got %s (before %s)\n' \
        "$commits_after" "$commits_before" >&2
    exit 1
fi

# --- Multibyte log truncation regression test ---
# Force byte-wise `cut -c` (LC_ALL=C) to reproduce the truncation bug: a
# multibyte command long enough to overflow the 120-char log limit at a
# non-character-aligned byte offset must still produce a valid UTF-8,
# grep-matchable log line.
# "echo AB" is a 7-byte ASCII prefix; each subsequent "あ" is 3 bytes, so byte
# offset 120 falls on the middle byte of the 38th "あ" — a genuine
# mid-character split, not a coincidental character boundary.
multibyte_command="echo AB$(printf 'あ%.0s' $(seq 1 45))"
output=$(jq -cn --arg command "$multibyte_command" '{tool_name:"Bash",tool_input:{command:$command}}' \
    | env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_BY_BUN -u CODEX_CI -u CODEX_THREAD_ID \
        LC_ALL=C \
        CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
        CLAUDE_CODE_KIT_SESSION_ID="$SESSION_ID" \
        CLAUDE_CODE_KIT_SESSION_APPROVED_FILE="$SESSION_FILE" \
        CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
        bash "$AUTO_HOOK")
assert_json_decision "$output" "approve"

multibyte_log_line=$(tail -n 1 "$LOG_FILE")
if ! printf '%s' "$multibyte_log_line" | grep -qE 'result=approved[[:space:]]+tool=Bash'; then
    printf 'Multibyte log line not grep-matchable: %s\n' "$multibyte_log_line" >&2
    exit 1
fi
if ! printf '%s' "$multibyte_log_line" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    printf 'Multibyte log line contains invalid UTF-8: %s\n' "$multibyte_log_line" >&2
    exit 1
fi

printf 'approval hook tests passed\n'
