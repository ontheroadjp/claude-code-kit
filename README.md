# claude-code-kit

A collection of custom slash commands for [Claude Code](https://claude.ai/code) that provide a structured AI-driven development workflow — from implementation through documentation sync and PR publication.

## Commands

| Command | Purpose |
|---|---|
| `/task` | Entry point for all file changes. Routes to patch flow (no docs needed) or task flow (docs required). |
| `/patch` | Lightweight fixes without documentation changes. Branch + commit → user ff-merges. |
| `/docs-sync` | Syncs `docs/*` to match implementation changes using `git diff` as truth, then publishes the draft PR. |
| `/init-docs` | Full re-observation and reconstruction of project design docs. Run when `/docs-sync` hits a HARD STOP. |

### Workflow Overview

```
/task
  ├── docs not required → patch flow: branch → commit → user merges
  └── docs required     → task flow:  issue → implement → draft PR → /docs-sync → PR published
```

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- `git`
- `gh` (GitHub CLI, authenticated)

## Installation

> **Symlink-only principle:** All files placed under `~/.claude/` must be symlinks pointing to this repository — never actual file copies. This repo is the single source of truth; `~/.claude/` is just a reference point.

### 1. Symlink the commands (global — all repos)

```bash
ln -s /path/to/claude-code-kit/commands/task.md       ~/.claude/commands/task.md
ln -s /path/to/claude-code-kit/commands/patch.md      ~/.claude/commands/patch.md
ln -s /path/to/claude-code-kit/commands/docs-sync.md  ~/.claude/commands/docs-sync.md
ln -s /path/to/claude-code-kit/commands/init-docs.md  ~/.claude/commands/init-docs.md
ln -s /path/to/claude-code-kit/commands/templates     ~/.claude/commands/templates
```

The commands are now available as `/task`, `/patch`, `/docs-sync`, and `/init-docs` in any Claude Code session.

### 2. Symlink CLAUDE.md (global — all repos)

```bash
ln -s /path/to/claude-code-kit/CLAUDE.md ~/.claude/CLAUDE.md
```

Claude Code auto-loads `~/.claude/CLAUDE.md` in every session, so the AI operating instructions apply to all repositories automatically. If a repo needs different instructions, place a local `CLAUDE.md` in its root — local takes precedence over global.

### 3. Symlink the token usage hook (optional)

```bash
mkdir -p ~/.claude/hooks
ln -s /path/to/claude-code-kit/hooks/log-token-usage.sh ~/.claude/hooks/log-token-usage.sh
```

Then add the following to `~/.claude/settings.json`:

```json
"hooks": {
    "Stop": [
        {
            "matcher": "",
            "hooks": [
                {
                    "type": "command",
                    "command": "bash ~/.claude/hooks/log-token-usage.sh"
                }
            ]
        }
    ]
}
```

At the end of every Claude Code session, token usage is appended to `~/.claude/token-usage.log`:

```
[2026-05-23 20:54:56] session=abc123  input=  1411  output=445336  cache_read=80565208  cache_create=1092677  total=1539424
```

## Repository Structure

```
hooks/
  log-token-usage.sh   # Stop hook — logs token usage per session to ~/.claude/token-usage.log
commands/
  task.md          # Main entry point — routes to patch or task flow
  patch.md         # Lightweight fix flow
  docs-sync.md     # Documentation sync and PR publication
  init-docs.md     # Full docs reconstruction
  templates/
    issue.md       # GitHub issue template
    pr.md          # Pull request template
docs/
  .ai/
    repo.profile.json       # Machine-readable repo profile
  L1_project/               # Project overview docs
  L2_development/           # Development and operation docs
  L3_implementation/        # Implementation specification docs
CLAUDE.md                   # AI operating instructions (auto-loaded by Claude Code)
```

## Design Principles

- **`git diff` is truth** — AI summaries are supplementary only
- **Docs changes are isolated** — `/task` never touches `docs/*`; only `/docs-sync` does
- **Minimal updates** — `/docs-sync` updates only what changed, never rewrites wholesale
- **HARD STOP escalation** — when `/docs-sync` cannot reason about a change, it stops and requires `/init-docs`
