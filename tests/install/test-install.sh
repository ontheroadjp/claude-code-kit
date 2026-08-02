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
  "$FIXTURE_REPO/skills/example" \
  "$FIXTURE_REPO/templates" \
  "$TEST_HOME"

cp "$REPO_DIR/install.sh" "$FIXTURE_REPO/install.sh"
printf '# command\n' > "$FIXTURE_REPO/commands/example.md"
printf '#!/usr/bin/env bash\n' > "$FIXTURE_REPO/hooks/example.sh"
printf '# skill\n' > "$FIXTURE_REPO/skills/example/SKILL.md"

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

run_installer
assert_template_links "$TEST_HOME/.claude/templates"
assert_template_links "$TEST_HOME/.codex/templates"

LEGACY_CONFIG_DIR="$TEST_HOME/.config/claude-code-kit"
if [ -e "$LEGACY_CONFIG_DIR/templates" ]; then
  printf 'FAIL: legacy template target was created\n'
  exit 1
fi

run_installer
assert_template_links "$TEST_HOME/.claude/templates"
assert_template_links "$TEST_HOME/.codex/templates"

printf 'All install contract tests passed.\n'
