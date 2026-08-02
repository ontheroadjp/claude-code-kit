# Installation

> **Symlink-only principle:** All files placed under `~/.claude/` and `~/.codex/` must be symlinks pointing to this repository — never actual file copies. This repo is the single source of truth; the home-directory paths are reference points.

## Quick Install

The fastest way to set everything up:

```bash
git clone https://github.com/ontheroadjp/core-toolkit-for-claude.git
cd core-toolkit-for-claude
./install.sh
```

This creates symlinks for:
- `commands/*.md` → `~/.claude/commands/` and `~/.codex/commands/`
- `hooks/*.sh` → `~/.claude/hooks/` and `~/.codex/hooks/`
- `skills/*/` → `~/.codex/skills/`
- `templates/*.md` → `~/.claude/templates/` and `~/.codex/templates/`

Target directories are created automatically. If `jq` is available, the installer also updates `~/.claude/settings.json` and `~/.codex/hooks.json`. Codex users should review and trust registered hooks with `/hooks` before relying on them.

## Manual Setup

### Step 0: Symlink the templates (required)

```bash
mkdir -p ~/.claude/templates ~/.codex/templates
for template in /path/to/core-toolkit-for-claude/templates/*.md; do
  ln -s "$template" ~/.claude/templates/
  ln -s "$template" ~/.codex/templates/
done
```

Template source files remain in this repository. Claude Code resolves the symlinks under `~/.claude/templates/`, while Codex CLI resolves those under `~/.codex/templates/`.

### Step 1: Symlink the commands (global — all repos)

```bash
ln -s /path/to/core-toolkit-for-claude/commands/work.md            ~/.claude/commands/work.md
ln -s /path/to/core-toolkit-for-claude/commands/triage-issues.md   ~/.claude/commands/triage-issues.md
ln -s /path/to/core-toolkit-for-claude/commands/task.md            ~/.claude/commands/task.md
ln -s /path/to/core-toolkit-for-claude/commands/patch.md           ~/.claude/commands/patch.md
ln -s /path/to/core-toolkit-for-claude/commands/docs-sync.md       ~/.claude/commands/docs-sync.md
ln -s /path/to/core-toolkit-for-claude/commands/init-docs.md       ~/.claude/commands/init-docs.md
ln -s /path/to/core-toolkit-for-claude/commands/review-resolve.md  ~/.claude/commands/review-resolve.md
ln -s /path/to/core-toolkit-for-claude/commands/codex-review.md    ~/.claude/commands/codex-review.md
ln -s /path/to/core-toolkit-for-claude/commands/new-issue.md       ~/.claude/commands/new-issue.md
```

Create the same links under `~/.codex/commands/` when installing manually for Codex CLI.

The commands are now available as `/work`, `/triage-issues`, `/new-issue`, `/review-resolve`, `/codex-review`, `/task`, `/patch`, `/docs-sync`, and `/init-docs`.

### Step 2: Symlink CLAUDE.md (global — all repos)

```bash
ln -s /path/to/core-toolkit-for-claude/CLAUDE.md ~/.claude/CLAUDE.md
```

Claude Code auto-loads `~/.claude/CLAUDE.md` in every session, so the AI operating instructions apply to all repositories automatically. If a repo needs different instructions, place a local `CLAUDE.md` in its root — local takes precedence over global.

### Step 3: Symlink the hooks (optional)

```bash
mkdir -p ~/.claude/hooks
ln -s /path/to/core-toolkit-for-claude/hooks/auto-approve-readonly.sh \
      ~/.claude/hooks/auto-approve-readonly.sh
ln -s /path/to/core-toolkit-for-claude/hooks/guard-destructive-cmd.sh \
      ~/.claude/hooks/guard-destructive-cmd.sh
ln -s /path/to/core-toolkit-for-claude/hooks/log-token-usage.sh \
      ~/.claude/hooks/log-token-usage.sh
ln -s /path/to/core-toolkit-for-claude/hooks/log-access-prompt.sh \
      ~/.claude/hooks/log-access-prompt.sh
ln -s /path/to/core-toolkit-for-claude/hooks/log-access-tool.sh \
      ~/.claude/hooks/log-access-tool.sh
ln -s /path/to/core-toolkit-for-claude/hooks/log-access-stop.sh \
      ~/.claude/hooks/log-access-stop.sh
ln -s /path/to/core-toolkit-for-claude/hooks/cleanup-session.sh \
      ~/.claude/hooks/cleanup-session.sh
```

See [Configuration](./configuration) for registering hooks in `~/.claude/settings.json`.

For Codex CLI, create the same hook symlinks under `~/.codex/hooks/` and register them in `~/.codex/hooks.json`, or run `./install.sh` to do this automatically when `jq` is available.

### Step 4: Symlink Codex skills (Codex CLI)

```bash
mkdir -p ~/.codex/skills
ln -s /path/to/core-toolkit-for-claude/skills/* ~/.codex/skills/
```

Each skill is a thin wrapper that reads the corresponding `commands/*.md` file as its source of truth.

### Step 5: Status line (optional)

Displays context usage and rate limits in the Claude Code status bar:

```bash
./setup_statusline.sh
```

Restart Claude Code to apply.

## Requirements

- [Claude Code](https://claude.ai/code) installed
- Codex CLI installed when using Codex skills or hooks
- Git and gh CLI installed and authenticated
- jq installed
