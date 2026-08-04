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
cp "${REPO_DIR}/hooks/lib/session-id.sh" "${TEST_REPO_DIR}/hooks/lib/session-id.sh"
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
        | env -u CLAUDE_CODE_KIT_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
            -u CODEX_THREAD_ID \
            CLAUDE_CODE_KIT_STATE_HOME="$TMP_DIR/state" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash "$CLEANUP_HOOK"
}

run_auto_without_session() {
    local command="$1"
    jq -cn --arg command "$command" '{tool_name:"Bash",tool_input:{command:$command}}' \
        | env -u CLAUDE_CODE_KIT_SESSION_ID -u CLAUDE_CODE_SESSION_ID \
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
    'for f in README.md CLAUDE.md; do test -f "$f" || echo missing; done' \
    $'for f in README.md CLAUDE.md\ndo\n  test -f "$f"\ndone' \
    'gh pr checks 143' \
    'git -C /tmp status --porcelain' \
    'rg -n "foo|bar" README.md' \
    'printf value | sed -n '\''1p'\''' \
    'echo value | sha256sum' \
    'SESSION_ID="codex-$(printf '\''%s'\'' "$CODEX_THREAD_ID" | sha256sum | cut -c1-16)"' \
    'strings README.md' \
    'readlink AGENTS.md' \
    'ss -ltnp' \
    'apt-cache policy vim' \
    'desktop-file-validate applications/alacritty/Alacritty.desktop' \
    'man keyd' \
    'diff file1.txt file2.txt' \
    'sleep 1' \
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
    'dpkg -l gnome-shell' \
    'dpkg -L gnome-shell' \
    'dpkg -s gnome-shell' \
    'dpkg -S /usr/bin/git' \
    'dpkg --list' \
    'dpkg --listfiles gnome-shell' \
    'dpkg --status gnome-shell' \
    'dpkg --search /usr/bin/git' \
    'gdbus introspect --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications' \
    'gresource list /usr/share/gnome-shell/gnome-shell-theme.gresource' \
    'gresource list-sections /usr/share/gnome-shell/gnome-shell-theme.gresource' \
    'tmux display-message -p "#W"' \
    'tmux list-windows' \
    'tmux list-sessions' \
    'tmux list-panes' \
    'tmux show-options -g' \
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

# git add / commit / fetch in their narrow known-safe shapes must auto-approve
# unconditionally, independent of any session-approved state (no SESSION_FILE
# has been written yet at this point in the test).
for command in \
    'git add README.md' \
    'git add README.md docs/L0_concept/policy.md' \
    'git commit -m "docs: sync documentation"' \
    "git commit --message 'fix: correct typo'" \
    'git fetch' \
    'git fetch origin' \
    'git -C /tmp fetch origin'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

for command in \
    'if [ -f README.md ]; then touch unsafe; fi' \
    'for f in a b; do touch unsafe; done' \
    'for ((i=0;i<3;i++)); do echo $i; done' \
    'for f in $(rm -rf /); do echo "$f"; done' \
    'for f; do echo "$f"; done' \
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
    'dpkg -i package.deb' \
    'dpkg -r gnome-shell' \
    'dpkg -P gnome-shell' \
    'dpkg --configure -a' \
    'dpkg -l -L gnome-shell' \
    'dpkg -l -i package.deb' \
    'dpkg' \
    'dpkg -x package.deb /tmp' \
    'gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.CloseNotification 1' \
    'gresource compile --target=out.gresource src' \
    'tmux send-keys -t 0 "echo hi" Enter' \
    'tmux kill-session -t 0' \
    'tmux kill-window -t 0' \
    'tmux new-session -d' \
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
    'node script.js' \
    'git add -A' \
    'git add --all' \
    'git add .' \
    'git add *' \
    'git add -A README.md' \
    'git add -p README.md' \
    'git commit --amend' \
    'git commit --amend -m "docs: sync documentation"' \
    'git commit -m "docs: sync documentation" --no-verify' \
    'git commit -n -m "docs: sync documentation"' \
    'git commit -a -m "docs: sync documentation"' \
    'git commit -m "docs: sync documentation" README.md' \
    'git commit -m docs' \
    'git commit -m "unterminated' \
    'git fetch origin +main:main' \
    'git fetch origin main:main' \
    'git fetch --all' \
    'git fetch --prune origin'; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# Quote-aware write-redirect detection: a '>' used as a comparison operator
# inside a single-quoted script (not a real file-write redirect) must not be
# misread as one. cmd 2>&1 / cmd 1>&2 (fd duplication, not a background
# operator) must also stay auto-approved when otherwise read-only.
for command in \
    'awk -F: '\''$1>130 && $1<200'\'' README.md' \
    'grep -n foo README.md | awk -F: '\''$1>10 && $1<20'\''' \
    'cat README.md 2>&1' \
    'cat README.md 1>&2'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

# awk's own print/printf output-redirect ('>' / '>>') writes a file
# independently of the shell-level write-redirect check, which sees the
# single-quoted script as opaque text. Must still prompt fallback.
for command in \
    'awk '\''BEGIN { print 1 > "/tmp/unsafe" }'\''' \
    'awk '\''{ print $1 >> "out.txt" }'\'' README.md'; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# '>&word' where word is not a bare fd number/'-' is a real file-write
# redirect in bash (equivalent to &>word), not fd duplication — must not be
# exempted from write-redirect / background-operator rejection.
for command in \
    'cat README.md >&somefile' \
    'echo value >&some-log.txt'; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# command -v <name>: read-only lookup equivalent to `type`.
output=$(run_auto 'command -v codex')
assert_json_decision "$output" "approve"

# command -v with more than a single argument does not match the strict
# single-argument shape and falls back to prompt.
output=$(run_auto 'command -v codex extra-arg')
assert_no_output "$output"

# codex --version / --help: runtime version/help check.
for command in 'codex --version' 'codex --help'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

# codex subcommands are not version/help checks and must prompt fallback.
output=$(run_auto 'codex exec "do something"')
assert_no_output "$output"

# kill -0 <pid...>: signal 0 sends nothing — a pure liveness check.
for command in \
    'kill -0 2475016' \
    'kill -0 111 222 333'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

# Any other kill invocation (real signal, negative/process-group pid, bare
# pid with no signal flag, non-numeric target) must prompt fallback.
for command in \
    'kill -9 2475016' \
    'kill -0 -2475016' \
    'kill 2475016' \
    'kill -0 not-a-pid'; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# mkdir -p restricted to the session tmp directory (or a descendant).
for command in \
    "mkdir -p \"${SESSION_TMP_DIR}\"" \
    "mkdir -p \"${SESSION_TMP_DIR}/subdir\""; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

# mkdir outside the session tmp dir, without -p, or with multiple paths must
# prompt fallback.
for command in \
    'mkdir -p /etc/evil' \
    "mkdir -p ${TMP_ROOT}/other-session" \
    "mkdir \"${SESSION_TMP_DIR}\"" \
    "mkdir -p \"${SESSION_TMP_DIR}\" \"${SESSION_TMP_DIR}/other\""; do
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
    "JOPT='--rotate'; journalctl \$JOPT" \
    "ADDOPT='-A'; git add \$ADDOPT" \
    "MSG='\"pwned\" --amend'; git commit -m \$MSG" \
    "REF='+main:main'; git fetch origin \$REF"; do
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

# Follow-up finding: neither helper tracked single quotes at depth=0 (before
# entering any $(...)), so a literal $( inside a single-quoted argument (e.g.
# curl '$(' ...) was mistaken for a real subshell start. No matching )
# exists anywhere in the string, so depth never returns to 0 and everything
# after it — including a variable reference — is silently dropped from what
# gets validated. Must prompt fallback; single quotes suppress all expansion
# in real bash, so '$(' is just two literal characters.
output=$(run_auto "OPTS='-o /tmp/evil'; curl '\$(' \$OPTS https://example.com")
assert_no_output "$output"

# Follow-up finding: the depth=0 fix above only tracked single quotes, not
# double quotes, so a literal ' appearing inside a "..." string (not
# starting a real quote in real bash) was misread as opening one, which then
# swallowed a genuine following $( that should have been caught and
# recursively validated. Must prompt fallback: cat "foo'$(touch ...)" really
# does run touch in real bash.
output=$(run_auto 'cat "foo'"'"'$(touch /tmp/unsafe)"')
assert_no_output "$output"

# Follow-up finding: nested $(...) did not save/restore the enclosing
# quote state, so a nested substitution inside a double-quoted string one
# level down (e.g. $(printf '%s' "$(touch ...)")) leaked the outer level's
# quote='"' into the nested level, causing the nested closing ) to be
# misread as a literal character inside a (stale) quote instead of closing
# the nested subshell. Depth then never returns to 0, so extraction yields
# no content and the pure-assignment segment is wrongly treated as safe.
# Must prompt fallback: the nested touch really does run in real bash.
output=$(run_auto "X=\$(printf '%s' \"\$(touch /tmp/unsafe)\")")
assert_no_output "$output"

# Redesign (tokenizer unification) regression: the old saw_dollar look-ahead
# flag used only inside _extract_subshell_contents was not reset when an
# escaped character was consumed, so an escaped " could leave saw_dollar
# stuck at 1 and cause a later ( to be misread as starting a nested $(,
# corrupting depth tracking for the rest of the segment. The unified
# tokenizer has no such flag to leak. Must prompt fallback: the nested touch
# really does run in real bash.
output=$(run_auto 'cat $(printf "$\"(" $(touch /tmp/unsafe))')
assert_no_output "$output"

# Redesign (tokenizer unification) regression: ANSI-C quoting ($'...') was
# previously parsed as an ordinary single-quoted string (no escape
# awareness), so an escaped quote inside it (\' — a real escape sequence in
# $'...') was misread as the closing quote, causing the actual closing quote
# and everything after it — including a genuine $(...) — to be misclassified
# as still being inside the string (or, once mis-closed, letting a
# subsequent read-only-looking allowlist match hide the trailing subshell).
# Must prompt fallback: the trailing touch really does run in real bash.
output=$(run_auto "cat \$'foo\\'bar'\$(touch /tmp/unsafe)")
assert_no_output "$output"

mkdir -p "$(dirname "$SESSION_FILE")"
printf '%s\n' 'tool:git_write' > "$SESSION_FILE"
output=$(run_auto 'git reset --hard')
assert_json_decision "$output" "block"

output=$(run_auto 'git status --porcelain')
assert_json_decision "$output" "approve"
assert_log_matches '] agent=claude session=test-session-fixed result=approved[[:space:]]+tool=Bash[[:space:]]+duration_ms=(NA|[0-9]+)[[:space:]]+git status --porcelain$'

output=$(run_auto_codex_symlink 'git status --porcelain')
assert_json_decision "$output" "allow"
assert_log_matches '] agent=codex session=test-session-fixed result=approved[[:space:]]+tool=Bash[[:space:]]+duration_ms=(NA|[0-9]+)[[:space:]]+git status --porcelain$'

output=$(run_auto_without_session 'git status --porcelain')
assert_json_decision "$output" "approve"
assert_log_matches '] agent=claude session=n/a result=approved[[:space:]]+tool=Bash[[:space:]]+duration_ms=(NA|[0-9]+)[[:space:]]+git status --porcelain$'

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

# --- rm [-f] <literal-path> auto-approval tests (issue #248) ---

# rm -f on the current session's own session-approved file → NOT approved.
# session-approved is a protected path (is_rm_protected_path): it is a
# security-control state file, not disposable/recoverable data, so deleting
# it must always fall through to a real human confirmation prompt rather
# than being silently auto-approved (this is what let an agent bypass the
# Write scope-expansion guard by rm-ing the file and rewriting it as if
# fresh — see issue #250).
output=$(run_auto_in_repo "rm -f ${SESSION_FILE}")
assert_no_output "$output"

# bare rm (no -f) on the session-approved file → also NOT approved
output=$(run_auto_in_repo "rm ${SESSION_FILE}")
assert_no_output "$output"

# rm -f on a repo-internal literal path → approved + WIP commit created
echo "to be removed" > "${TEST_GIT_REPO}/to-delete.txt"
git -C "$TEST_GIT_REPO" add -A
git -C "$TEST_GIT_REPO" commit --no-verify -q -m "add to-delete.txt"
echo "dirty again" >> "${TEST_GIT_REPO}/initial.txt"
commits_before=$(git -C "$TEST_GIT_REPO" log --oneline | wc -l | tr -d ' ')
output=$(run_auto_in_repo "rm -f ${TEST_GIT_REPO}/to-delete.txt")
assert_json_decision "$output" "approve"
commits_after=$(git -C "$TEST_GIT_REPO" log --oneline | wc -l | tr -d ' ')
if [ "$commits_after" -le "$commits_before" ]; then
    printf 'Expected WIP commit to be created for literal rm -f, got %s (before %s)\n' \
        "$commits_after" "$commits_before" >&2
    exit 1
fi
if ! git -C "$TEST_GIT_REPO" log --oneline -1 | grep -q "wip:"; then
    printf 'Expected latest commit to be a wip: commit\n' >&2
    exit 1
fi

# rm -f on repo root itself → NOT approved (defeats safety net)
output=$(run_auto_in_repo "rm -f ${TEST_GIT_REPO}")
assert_no_output "$output"

# rm -f on a .git-internal path → NOT approved
output=$(run_auto_in_repo "rm -f ${TEST_GIT_REPO}/.git/config")
assert_no_output "$output"

# rm -f on a path that is neither the session-approved file nor in-repo → NOT approved
output=$(run_auto_in_repo "rm -f /tmp/unrelated-outside-path.txt")
assert_no_output "$output"

# rm -f with a variable reference instead of a literal path → NOT approved
output=$(run_auto_in_repo 'rm -f $SOME_VAR')
assert_no_output "$output"

# rm -f with the session-approved path plus an extra token → NOT approved
output=$(run_auto_in_repo "rm -f ${SESSION_FILE} extra")
assert_no_output "$output"

# rm -f with a glob instead of a literal path → NOT approved
output=$(run_auto_in_repo "rm -f ${TEST_GIT_REPO}/*.txt")
assert_no_output "$output"

# rm -rf (recursive) on the session-approved file → NOT approved by the
# literal-path branch (only plain rm/-f is in scope; -rf stays on the
# separate working-repo-only dynamic defense, which this path doesn't match)
output=$(run_auto_in_repo "rm -rf ${SESSION_FILE}")
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

# --- Concurrent-session isolation regression test (issue #210) ---
# Before the fix, both the hook and commands/*.md derived SESSION_ID by reading
# one shared, unscoped ${STATE_ROOT}/current-session-approved-path file, so
# whichever session's hook ran last "won" that file and a concurrent session's
# later read could resolve the wrong session's path. The fix derives SESSION_ID
# directly from $CLAUDE_CODE_SESSION_ID (mirroring what commands/*.md now do)
# instead of reading any shared file, so this collision must no longer be
# reproducible, and the shared pointer file must never be written at all.
CONCURRENT_STATE_ROOT="${TMP_DIR}/state-concurrent"
SESSION_A_ID="session-A-fixed"
SESSION_B_ID="session-B-fixed"
SESSION_A_APPROVED="${CONCURRENT_STATE_ROOT}/sessions/${SESSION_A_ID}/session-approved"
SESSION_B_APPROVED="${CONCURRENT_STATE_ROOT}/sessions/${SESSION_B_ID}/session-approved"

run_auto_write_as() {
    local id="$1" file_path="$2" content="$3"
    jq -cn --arg file_path "$file_path" --arg content "$content" \
        '{tool_name:"Write",tool_input:{file_path:$file_path,content:$content}}' \
        | env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_BY_BUN -u CODEX_CI -u CODEX_THREAD_ID \
            -u CLAUDE_CODE_KIT_SESSION_ID -u CLAUDE_CODE_KIT_SESSION_APPROVED_FILE \
            CLAUDE_CODE_SESSION_ID="$id" \
            CLAUDE_CODE_KIT_STATE_HOME="$CONCURRENT_STATE_ROOT" \
            CLAUDE_CODE_KIT_TMP_ROOT="$TMP_ROOT" \
            bash "$AUTO_HOOK"
}

# Interleave A's hook firing, then B's, then A's again — this ordering is
# exactly when the removed shared pointer file used to get overwritten by B
# and mislead a subsequent read done on behalf of A.
# Note: the hook only emits an approval decision, it never performs the Write
# itself (the real Write tool would do that after receiving "approve"), so
# these checks assert on the decision only, not on-disk file state.
output=$(run_auto_write_as "$SESSION_A_ID" "$SESSION_A_APPROVED" "tool:git_write")
assert_json_decision "$output" "approve"
output=$(run_auto_write_as "$SESSION_B_ID" "$SESSION_B_APPROVED" "tool:git_write")
assert_json_decision "$output" "approve"
output=$(run_auto_write_as "$SESSION_A_ID" "$SESSION_A_APPROVED" "tool:git_write")
assert_json_decision "$output" "approve"

# Session A must never be auto-approved to write into session B's file (proves
# the two sessions resolve to genuinely different, non-colliding paths).
cross_output=$(run_auto_write_as "$SESSION_A_ID" "$SESSION_B_APPROVED" "tool:git_write")
if [ -n "$cross_output" ]; then
    cross_decision=$(printf '%s' "$cross_output" | jq -r '.decision // empty')
    if [ "$cross_decision" = "approve" ] || [ "$cross_decision" = "allow" ]; then
        printf 'session A was auto-approved to write into session B session-approved file\n' >&2
        exit 1
    fi
fi

# The removed global pointer file must never be recreated by the hook.
if [ -e "${CONCURRENT_STATE_ROOT}/current-session-approved-path" ]; then
    printf 'current-session-approved-path was recreated; the shared pointer file must stay removed\n' >&2
    exit 1
fi

# Absolute-path invocations of already-allowlisted commands under a fixed set
# of known-safe system directories (issue #237 decision, implemented in #244)
# must auto-approve identically to their bare-name equivalents.
for command in \
    '/usr/bin/git status' \
    '/usr/bin/git -C /tmp status --porcelain' \
    '/bin/nl README.md' \
    '/usr/local/bin/rg -n foo README.md' \
    '/usr/bin/git add README.md' \
    '/usr/bin/git commit -m "docs: sync documentation"' \
    '/usr/bin/git fetch origin'; do
    output=$(run_auto "$command")
    assert_json_decision "$output" "approve"
done

# Absolute paths outside the recognized system directories — in particular
# agent-writable locations — must NOT be normalized away: a binary planted at
# such a path bypasses PATH resolution and must not be misclassified as the
# trusted bare command.
for command in \
    '/tmp/evil/git status' \
    '/opt/attacker-controlled/nl README.md' \
    './git status'; do
    output=$(run_auto "$command")
    assert_no_output "$output"
done

# --- Heredoc-aware auto-approve masking regression test (issue #246) ---
# Before the fix, split_shell_segments split a heredoc body on every embedded
# newline, so free-form PR/issue body text (used by commands/git-pr.md,
# new-issue.md, and triage-issues.md via `... --body-file - <<'EOF' ... EOF`)
# never matched any allow-shape and the whole command fell through to a user
# prompt even when tool:gh_pr_write was already approved for the session.
# _mask_quoted_heredoc_bodies collapses a quoted-delimiter heredoc body to a
# single inert placeholder before write-redirect detection, the destructive
# command guard, and split_shell_segments run.

output=$(run_auto $'gh pr create --title "feat: add x" --body-file - <<\'EOF\'\n## Summary\n- did a thing\n- did another thing\n\nEOF')
assert_json_decision "$output" "approve"

# Body content that would otherwise trip other scanners (write-redirect '>',
# the destructive-command guard) must not matter once it is inside a
# quoted-delimiter heredoc body -- it is inert data, never parsed as shell
# syntax by bash.
output=$(run_auto $'gh pr create --title "feat: add x" --body-file - <<\'EOF\'\nscore > 100, before -> after\nrm -rf /\nEOF')
assert_json_decision "$output" "approve"

# A double-quoted delimiter disables body expansion identically to a
# single-quoted one.
output=$(run_auto $'gh pr create --title "feat: add x" --body-file - <<"EOF"\n## Summary\n- did a thing\nEOF')
assert_json_decision "$output" "approve"

# A dangerous operation BEFORE the heredoc operator (outside the masked
# body) must still be blocked -- masking only ever touches the body itself.
output=$(run_auto $'git push --force <<\'EOF\'\nsome note\nEOF')
assert_json_decision "$output" "block"

# Masking must not bypass the session-approval gate itself: the same
# heredoc command with no tool:gh_pr_write approved must still fall through
# to a user prompt.
output=$(run_auto_without_session $'gh pr create --title "feat: add x" --body-file - <<\'EOF\'\n## Summary\n- did a thing\nEOF')
assert_no_output "$output"

# Unquoted-delimiter heredocs ARE subject to bash expansion inside the body,
# so they are deliberately left unmasked (known limitation, not a
# regression) and continue to fall through to a user prompt.
output=$(run_auto $'gh pr create --title "feat: add x" --body-file - <<EOF\n## Summary\n- did a thing\nEOF')
assert_no_output "$output"

printf 'approval hook tests passed\n'
