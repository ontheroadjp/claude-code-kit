#!/usr/bin/env bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE_REPO="$TMP_DIR/repo"
TEST_HOME="$TMP_DIR/home"

mkdir -p \
  "$FIXTURE_REPO/commands" \
  "$FIXTURE_REPO/hooks" \
  "$FIXTURE_REPO/hooks/lib" \
  "$FIXTURE_REPO/scripts" \
  "$FIXTURE_REPO/skills/example" \
  "$FIXTURE_REPO/templates" \
  "$FIXTURE_REPO/global" \
  "$TEST_HOME"

cp "$REPO_DIR/install.sh" "$FIXTURE_REPO/install.sh"
touch "$FIXTURE_REPO/.gitignore"
printf '# claude\n' > "$FIXTURE_REPO/global/CLAUDE.md"
printf '# command\n' > "$FIXTURE_REPO/commands/example.md"
printf '#!/usr/bin/env bash\n' > "$FIXTURE_REPO/hooks/example.sh"
printf '#!/usr/bin/env bash\n' > "$FIXTURE_REPO/hooks/lib/example-lib.sh"
printf '#!/usr/bin/env bash\n' > "$FIXTURE_REPO/scripts/example.sh"
printf '# skill\n' > "$FIXTURE_REPO/skills/example/SKILL.md"
mkdir -p "$TEST_HOME/.codex"
cat > "$TEST_HOME/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.codex/hooks/auto-approve-readonly.sh"
          }
        ]
      }
    ]
  }
}
EOF

for template in README.md issue.md pr.md readme.md; do
  printf '# template\n' > "$FIXTURE_REPO/templates/$template"
done

run_installer() {
  HOME="$TEST_HOME" bash "$FIXTURE_REPO/install.sh" >/dev/null
}

assert_symlink() {
  local link_path=$1
  local expected_target=$2

  if [ ! -L "$link_path" ]; then
    printf 'FAIL: expected symlink %s\n' "$link_path"
    exit 1
  fi

  if [ "$(readlink "$link_path")" != "$expected_target" ]; then
    printf 'FAIL: unexpected target for %s\n' "$link_path"
    exit 1
  fi
}

assert_template_links() {
  local target_dir=$1

  for template in README.md issue.md pr.md readme.md; do
    assert_symlink \
      "$target_dir/$template" \
      "$FIXTURE_REPO/templates/$template"
  done
}

assert_hooks_lib_links() {
  local target_dir=$1

  assert_symlink \
    "$target_dir/example-lib.sh" \
    "$FIXTURE_REPO/hooks/lib/example-lib.sh"
}

assert_script_links() {
  local target_dir=$1

  assert_symlink \
    "$target_dir/example.sh" \
    "$FIXTURE_REPO/scripts/example.sh"
}

assert_codex_auto_approve_registration() {
  local hooks_file="$TEST_HOME/.codex/hooks.json"
  local hook_command='bash ~/.codex/hooks/auto-approve-readonly.sh'

  if jq -e --arg command "$hook_command" \
    '[(.hooks.PreToolUse // [])[] | .hooks[]?.command] | any(. == $command)' \
    "$hooks_file" >/dev/null; then
    printf 'FAIL: legacy Codex PreToolUse auto-approve hook remains registered\n'
    exit 1
  fi

  if ! jq -e --arg command "$hook_command" \
    '[(.hooks.PermissionRequest // [])[] | .hooks[]?.command] | any(. == $command)' \
    "$hooks_file" >/dev/null; then
    printf 'FAIL: Codex PermissionRequest auto-approve hook is not registered\n'
    exit 1
  fi
}

assert_global_claude_links() {
  assert_symlink \
    "$TEST_HOME/.claude/CLAUDE.md" \
    "$FIXTURE_REPO/global/CLAUDE.md"
  assert_symlink \
    "$TEST_HOME/.codex/AGENTS.md" \
    "$FIXTURE_REPO/global/CLAUDE.md"
}

run_installer
assert_template_links "$TEST_HOME/.claude/templates"
assert_template_links "$TEST_HOME/.codex/templates"
assert_hooks_lib_links "$TEST_HOME/.claude/hooks/lib"
assert_hooks_lib_links "$TEST_HOME/.codex/hooks/lib"
assert_script_links "$TEST_HOME/.claude/scripts"
assert_script_links "$TEST_HOME/.codex/scripts"
assert_codex_auto_approve_registration
assert_global_claude_links

LEGACY_CONFIG_DIR="$TEST_HOME/.config/claude-code-kit"
if [ -e "$LEGACY_CONFIG_DIR/templates" ]; then
  printf 'FAIL: legacy template target was created\n'
  exit 1
fi

run_installer
assert_template_links "$TEST_HOME/.claude/templates"
assert_template_links "$TEST_HOME/.codex/templates"
assert_hooks_lib_links "$TEST_HOME/.claude/hooks/lib"
assert_hooks_lib_links "$TEST_HOME/.codex/hooks/lib"
assert_script_links "$TEST_HOME/.claude/scripts"
assert_script_links "$TEST_HOME/.codex/scripts"
assert_codex_auto_approve_registration
assert_global_claude_links

printf 'All install contract tests passed.\n'
