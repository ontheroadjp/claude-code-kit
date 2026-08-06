#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${HOME}/.claude"
COMMANDS_TARGET="${HOME}/.claude/commands"
CODEX_COMMANDS_TARGET="${HOME}/.codex/commands"
HOOKS_TARGET="${HOME}/.claude/hooks"
CODEX_HOOKS_TARGET="${HOME}/.codex/hooks"
SKILLS_TARGET="${HOME}/.codex/skills"
CLAUDE_TEMPLATES_TARGET="${HOME}/.claude/templates"
CODEX_TEMPLATES_TARGET="${HOME}/.codex/templates"

mkdir -p "$COMMANDS_TARGET"
mkdir -p "$CODEX_COMMANDS_TARGET"
mkdir -p "$HOOKS_TARGET"
mkdir -p "$CODEX_HOOKS_TARGET"
mkdir -p "$SKILLS_TARGET"
mkdir -p "$CLAUDE_TEMPLATES_TARGET"
mkdir -p "$CODEX_TEMPLATES_TARGET"

echo "Linking commands -> ${CLAUDE_HOME}"
ln -sf "$(basename ${REPO_DIR}/keybindings.json)" "${CLAUDE_HOME}/keybindings.json)"

echo "Linking commands -> ${COMMANDS_TARGET}"
for src in "$REPO_DIR"/commands/*.md; do
  name="$(basename "$src")"
  ln -sf "$src" "${COMMANDS_TARGET}/${name}"
  echo "  ${COMMANDS_TARGET}/${name} -> ${src}"
done

echo "Linking commands -> ${CODEX_COMMANDS_TARGET}"
for src in "$REPO_DIR"/commands/*.md; do
  name="$(basename "$src")"
  ln -sf "$src" "${CODEX_COMMANDS_TARGET}/${name}"
  echo "  ${CODEX_COMMANDS_TARGET}/${name} -> ${src}"
done

echo "Linking hooks -> ${HOOKS_TARGET}"
for src in "$REPO_DIR"/hooks/*.sh; do
  name="$(basename "$src")"
  ln -sf "$src" "${HOOKS_TARGET}/${name}"
  echo "  ${HOOKS_TARGET}/${name} -> ${src}"
done

echo "Linking hooks -> ${CODEX_HOOKS_TARGET}"
for src in "$REPO_DIR"/hooks/*.sh; do
  name="$(basename "$src")"
  ln -sf "$src" "${CODEX_HOOKS_TARGET}/${name}"
  echo "  ${CODEX_HOOKS_TARGET}/${name} -> ${src}"
done

echo "Linking skills -> ${SKILLS_TARGET}"
for src in "$REPO_DIR"/skills/*/; do
  name="$(basename "$src")"
  ln -sf "$src" "${SKILLS_TARGET}/${name}"
  echo "  ${SKILLS_TARGET}/${name} -> ${src}"
done

for target in "$CLAUDE_TEMPLATES_TARGET" "$CODEX_TEMPLATES_TARGET"; do
  echo "Linking templates -> ${target}"
  for src in "$REPO_DIR"/templates/*.md; do
    name="$(basename "$src")"
    ln -sf "$src" "${target}/${name}"
    echo "  ${target}/${name} -> ${src}"
  done
done

echo "Creating self-referential skill symlinks..."
for src in "$REPO_DIR"/skills/*/; do
  name="$(basename "$src")"
  ln -sf "$src" "${src}${name}"
  echo "  ${src}${name} -> ${src}"
done

SETTINGS_FILE="${HOME}/.claude/settings.json"
CODEX_HOOKS_FILE="${HOME}/.codex/hooks.json"

echo "Configuring ${SETTINGS_FILE}..."

if ! command -v jq &>/dev/null; then
    echo "  Warning: jq not found - skipping settings.json and hooks.json updates."
    echo "  Add hook entries manually (see README.md)."
    echo "Done."
    exit 0
fi

[ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"
[ -f "$CODEX_HOOKS_FILE" ] || echo '{}' > "$CODEX_HOOKS_FILE"

# Idempotently add a hook entry: skip if the command is already registered for that event.
# Usage: add_claude_hook <event> <matcher> <command>
add_claude_hook() {
    local event="$1" matcher="$2" cmd="$3"
    local current
    current=$(cat "$SETTINGS_FILE")

    local exists
    exists=$(printf '%s' "$current" | jq -r \
        --arg e "$event" --arg c "$cmd" \
        '[(.hooks[$e] // [])[] | .hooks[]? | .command] | any(. == $c)')

    if [ "$exists" = "true" ]; then
        echo "  Already present [${event}]: ${cmd}"
        return
    fi

    printf '%s' "$current" | jq \
        --arg e "$event" --arg m "$matcher" --arg c "$cmd" \
        '.hooks[$e] = ((.hooks[$e] // []) + [{"matcher": $m, "hooks": [{"type": "command", "command": $c}]}])' \
        > "$SETTINGS_FILE"
    echo "  Added [${event}]: ${cmd}"
}

# Idempotently add a Codex hook entry to ~/.codex/hooks.json.
# Codex uses the same event -> matcher -> hooks JSON shape as Claude Code.
add_codex_hook() {
    local event="$1" matcher="$2" cmd="$3"
    local current
    current=$(cat "$CODEX_HOOKS_FILE")

    local exists
    exists=$(printf '%s' "$current" | jq -r \
        --arg e "$event" --arg c "$cmd" \
        '[(.hooks[$e] // [])[] | .hooks[]? | .command] | any(. == $c)')

    if [ "$exists" = "true" ]; then
        echo "  Already present [Codex ${event}]: ${cmd}"
        return
    fi

    printf '%s' "$current" | jq \
        --arg e "$event" --arg m "$matcher" --arg c "$cmd" \
        '.hooks[$e] = ((.hooks[$e] // []) + [{"matcher": $m, "hooks": [{"type": "command", "command": $c}]}])' \
        > "$CODEX_HOOKS_FILE"
    echo "  Added [Codex ${event}]: ${cmd}"
}

# Remove a hook entry by event+command (for migrations).
remove_claude_hook() {
    local event="$1" cmd="$2"
    local current
    current=$(cat "$SETTINGS_FILE")
    printf '%s' "$current" | jq \
        --arg e "$event" --arg c "$cmd" \
        '.hooks[$e] = [(.hooks[$e] // [])[] | select(([.hooks[] | .command == $c] | any) | not)]' \
        > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    echo "  Removed [${event}]: ${cmd} (if present)"
}

remove_codex_hook() {
    local event="$1" cmd="$2"
    local current
    current=$(cat "$CODEX_HOOKS_FILE")
    printf '%s' "$current" | jq \
        --arg e "$event" --arg c "$cmd" \
        '.hooks[$e] = [(.hooks[$e] // [])[] | select(([.hooks[] | .command == $c] | any) | not)]' \
        > "${CODEX_HOOKS_FILE}.tmp" && mv "${CODEX_HOOKS_FILE}.tmp" "$CODEX_HOOKS_FILE"
    echo "  Removed [Codex ${event}]: ${cmd} (if present)"
}

# Migrate Stop 🔴 → ✅
remove_claude_hook "Stop" "bash ~/.claude/hooks/tmux-agent-status.sh 🔴"
remove_codex_hook  "Stop" "bash ~/.codex/hooks/tmux-agent-status.sh 🔴"

add_claude_hook "PreToolUse"       ""     "bash ~/.claude/hooks/auto-approve-readonly.sh"
add_claude_hook "PreToolUse"       "Bash" "bash ~/.claude/hooks/guard-destructive-cmd.sh"
add_claude_hook "PreToolUse"       ""     "bash ~/.claude/hooks/tmux-agent-status.sh 🔵"
add_claude_hook "UserPromptSubmit" ""     "bash ~/.claude/hooks/log-access-prompt.sh"
add_claude_hook "UserPromptSubmit" ""     "bash ~/.claude/hooks/tmux-agent-status.sh 🔵"
add_claude_hook "PostToolUse"      ""     "bash ~/.claude/hooks/log-access-tool.sh"
add_claude_hook "PostToolUse"      ""     "bash ~/.claude/hooks/tmux-agent-status.sh 🔵"
add_claude_hook "Notification"     ""     "bash ~/.claude/hooks/notify-slack.sh"
add_claude_hook "Notification"     ""     "bash ~/.claude/hooks/tmux-agent-status.sh 🔴"
add_claude_hook "Stop"             ""     "bash ~/.claude/hooks/log-token-usage.sh"
add_claude_hook "Stop"             ""     "bash ~/.claude/hooks/log-access-stop.sh"
add_claude_hook "Stop"             ""     "bash ~/.claude/hooks/cleanup-session.sh"
add_claude_hook "Stop"             ""     "bash ~/.claude/hooks/notify-slack.sh"
add_claude_hook "Stop"             ""     "bash ~/.claude/hooks/tmux-agent-status.sh ✅"

echo "Configuring ${CODEX_HOOKS_FILE}..."
add_codex_hook "PreToolUse"       ""     "bash ~/.codex/hooks/auto-approve-readonly.sh"
add_codex_hook "PreToolUse"       "Bash" "bash ~/.codex/hooks/guard-destructive-cmd.sh"
add_codex_hook "PreToolUse"       ""     "bash ~/.codex/hooks/tmux-agent-status.sh 🔵"
add_codex_hook "UserPromptSubmit" ""     "bash ~/.codex/hooks/log-access-prompt.sh"
add_codex_hook "UserPromptSubmit" ""     "bash ~/.codex/hooks/tmux-agent-status.sh 🔵"
add_codex_hook "PostToolUse"      ""     "bash ~/.codex/hooks/log-access-tool.sh"
add_codex_hook "PostToolUse"      ""     "bash ~/.codex/hooks/tmux-agent-status.sh 🔵"
add_codex_hook "Notification"     ""     "bash ~/.codex/hooks/notify-slack.sh"
add_codex_hook "Notification"     ""     "bash ~/.codex/hooks/tmux-agent-status.sh 🔴"
add_codex_hook "Stop"             ""     "bash ~/.codex/hooks/log-token-usage.sh"
add_codex_hook "Stop"             ""     "bash ~/.codex/hooks/log-access-stop.sh"
add_codex_hook "Stop"             ""     "bash ~/.codex/hooks/cleanup-session.sh"
add_codex_hook "Stop"             ""     "bash ~/.codex/hooks/notify-slack.sh"
add_codex_hook "Stop"             ""     "bash ~/.codex/hooks/tmux-agent-status.sh ✅"
echo "  Review and trust Codex hooks with /hooks before relying on them."

echo "Done."
