#!/usr/bin/env bash

set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT="$REPO_DIR/setup_statusline_for_codex.sh"

run_setup() {
  local test_home=$1
  HOME="$test_home" bash "$SCRIPT" >/dev/null
}

assert_files_equal() {
  local expected=$1
  local actual=$2

  if ! cmp -s "$expected" "$actual"; then
    printf 'FAIL: files differ: %s %s\n' "$expected" "$actual"
    diff -u "$expected" "$actual" || true
    exit 1
  fi
}

test_fresh_config() {
  local test_home="$TMP_DIR/fresh-home"
  local expected="$TMP_DIR/fresh-expected.toml"
  local snapshot="$TMP_DIR/fresh-snapshot.toml"

  mkdir -p "$test_home"
  cat > "$expected" <<'EOF'
[tui]
status_line = [
  "context-used",
  "used-tokens",
  "five-hour-limit",
  "weekly-limit",
]
EOF

  run_setup "$test_home"
  assert_files_equal "$expected" "$test_home/.codex/config.toml"

  cp "$test_home/.codex/config.toml" "$snapshot"
  run_setup "$test_home"
  assert_files_equal "$snapshot" "$test_home/.codex/config.toml"
}

test_existing_config_without_tui() {
  local test_home="$TMP_DIR/no-tui-home"
  local expected="$TMP_DIR/no-tui-expected.toml"

  mkdir -p "$test_home/.codex"
  cat > "$test_home/.codex/config.toml" <<'EOF'
model = "gpt-5"
EOF
  cat > "$expected" <<'EOF'
model = "gpt-5"

[tui]
status_line = [
  "context-used",
  "used-tokens",
  "five-hour-limit",
  "weekly-limit",
]
EOF

  run_setup "$test_home"
  assert_files_equal "$expected" "$test_home/.codex/config.toml"
}

test_existing_tui_config() {
  local test_home="$TMP_DIR/existing-tui-home"
  local expected="$TMP_DIR/existing-tui-expected.toml"
  local snapshot="$TMP_DIR/existing-tui-snapshot.toml"

  mkdir -p "$test_home/.codex"
  cat > "$test_home/.codex/config.toml" <<'EOF'
model = "gpt-5"

[tui]
notifications = false
status_line = [
  "model-name",
  "context-remaining",
]

[features]
web_search = true
EOF
  cat > "$expected" <<'EOF'
model = "gpt-5"

[tui]
notifications = false
status_line = [
  "context-used",
  "used-tokens",
  "five-hour-limit",
  "weekly-limit",
]

[features]
web_search = true
EOF

  run_setup "$test_home"
  assert_files_equal "$expected" "$test_home/.codex/config.toml"

  cp "$test_home/.codex/config.toml" "$snapshot"
  run_setup "$test_home"
  assert_files_equal "$snapshot" "$test_home/.codex/config.toml"
}

test_fresh_config
test_existing_config_without_tui
test_existing_tui_config

printf 'All Codex status line setup tests passed.\n'
