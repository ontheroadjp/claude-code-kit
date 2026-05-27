#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_TARGET="${HOME}/.claude/commands"
SKILLS_TARGET="${HOME}/.codex/skills"

mkdir -p "$COMMANDS_TARGET"
mkdir -p "$SKILLS_TARGET"

echo "Linking commands -> ${COMMANDS_TARGET}"
for src in "$REPO_DIR"/commands/*.md; do
  name="$(basename "$src")"
  ln -sf "$src" "${COMMANDS_TARGET}/${name}"
  echo "  ${COMMANDS_TARGET}/${name} -> ${src}"
done

echo "Linking skills -> ${SKILLS_TARGET}"
for src in "$REPO_DIR"/skills/*/; do
  name="$(basename "$src")"
  ln -sf "$src" "${SKILLS_TARGET}/${name}"
  echo "  ${SKILLS_TARGET}/${name} -> ${src}"
done

echo "Done."
