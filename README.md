# claude-code-kit

A collection of custom slash commands for [Claude Code](https://claude.ai/code) that provide a structured AI-driven development workflow — from implementation through documentation sync and PR publication.

## Features

| Command | Purpose |
|---|---|
| `/task` | Entry point for all file changes. Routes to patch flow (no docs needed) or task flow (docs required). |
| `/patch` | Lightweight fixes without documentation changes. Branch + commit → user ff-merges. |
| `/docs-sync` | Syncs `docs/*` to match implementation changes using `git diff` as truth, then publishes the draft PR. |
| `/init-docs` | Full re-observation and reconstruction of project design docs. Run when `/docs-sync` hits a HARD STOP. |
| `/review-resolve` | Fetches PR review comments and guides the user through addressing or declining each one interactively. |

## Installation

> **Symlink-only principle:** All files placed under `~/.claude/` must be symlinks pointing to this repository — never actual file copies. This repo is the single source of truth; `~/.claude/` is just a reference point.

### 0. Symlink the shared templates (required by all tools)

```bash
mkdir -p ~/.config/claude-code-kit
ln -s /path/to/claude-code-kit/commands/templates ~/.config/claude-code-kit/templates
```

Templates are stored in `~/.config/claude-code-kit/templates/` so both Claude Code and Codex CLI can reference them from a single location.

### 1. Symlink the commands (global — all repos)

```bash
ln -s /path/to/claude-code-kit/commands/task.md            ~/.claude/commands/task.md
ln -s /path/to/claude-code-kit/commands/patch.md           ~/.claude/commands/patch.md
ln -s /path/to/claude-code-kit/commands/docs-sync.md       ~/.claude/commands/docs-sync.md
ln -s /path/to/claude-code-kit/commands/init-docs.md       ~/.claude/commands/init-docs.md
ln -s /path/to/claude-code-kit/commands/review-resolve.md  ~/.claude/commands/review-resolve.md
```

The commands are now available as `/task`, `/patch`, `/docs-sync`, `/init-docs`, and `/review-resolve` in any Claude Code session.

### 2. Symlink CLAUDE.md (global — all repos)

```bash
ln -s /path/to/claude-code-kit/CLAUDE.md ~/.claude/CLAUDE.md
```

Claude Code auto-loads `~/.claude/CLAUDE.md` in every session, so the AI operating instructions apply to all repositories automatically. If a repo needs different instructions, place a local `CLAUDE.md` in its root — local takes precedence over global.

### 3. Symlink the hooks (optional)

```bash
mkdir -p ~/.claude/hooks
ln -s /path/to/claude-code-kit/hooks/log-token-usage.sh  ~/.claude/hooks/log-token-usage.sh
ln -s /path/to/claude-code-kit/hooks/log-access-prompt.sh ~/.claude/hooks/log-access-prompt.sh
ln -s /path/to/claude-code-kit/hooks/log-access-tool.sh  ~/.claude/hooks/log-access-tool.sh
ln -s /path/to/claude-code-kit/hooks/log-access-stop.sh  ~/.claude/hooks/log-access-stop.sh
```

Then add the following to `~/.claude/settings.json`:

```json
"hooks": {
    "UserPromptSubmit": [
        { "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/log-access-prompt.sh" }] }
    ],
    "PostToolUse": [
        { "matcher": "", "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/log-access-tool.sh" }] }
    ],
    "Stop": [
        {
            "matcher": "",
            "hooks": [
                { "type": "command", "command": "bash ~/.claude/hooks/log-token-usage.sh" },
                { "type": "command", "command": "bash ~/.claude/hooks/log-access-stop.sh" }
            ]
        }
    ]
}
```

**Token usage hook** — at the end of every session, token usage is appended to `~/.claude/token-usage.log`:

```
[2026-05-23 20:54:56] session=abc123  input=  1411  output=445336  cache_read=80565208  cache_create=1092677  total=1539424
```

**File access log hooks** — when `/work` is invoked, the files accessed in each command phase are appended to `logs/YYYY-MM/access.log` in this repository:

```
---
[日時]
2026.05.24 15.30

[ユーザーからの指示内容]
hooks のみで work/task/patch のファイルアクセスをログに記録したい

[work]
- ~/.claude/commands/work.md
- ~/dev/.../docs/.ai/repo.profile.json

[task]
- ~/.claude/commands/task.md

[patch]

[docs-sync]

[init-docs]

[修正したファイル]
- ~/dev/.../hooks/log-access-tool.sh
```

### Codex CLI (optional)

After completing Steps 0–2 above, symlink for Codex CLI:

```bash
ln -s /path/to/claude-code-kit/commands/task.md       ~/.codex/prompts/task.md
ln -s /path/to/claude-code-kit/commands/patch.md      ~/.codex/prompts/patch.md
ln -s /path/to/claude-code-kit/commands/docs-sync.md  ~/.codex/prompts/docs-sync.md
ln -s /path/to/claude-code-kit/commands/init-docs.md  ~/.codex/prompts/init-docs.md
ln -s /path/to/claude-code-kit/AGENTS.md              ~/.codex/AGENTS.md
```

## Usage

```
/task
  ├── docs not required → patch flow: branch → commit → user merges
  └── docs required     → task flow:  issue → implement → draft PR → /docs-sync → PR published
```

Start every session with `/task` — it asks what you want to do and routes to the appropriate flow automatically.

## Design Principles

- **`git diff` is truth** — AI summaries are supplementary only
- **Docs changes are isolated** — `/task` never touches `docs/*`; only `/docs-sync` does
- **Minimal updates** — `/docs-sync` updates only what changed, never rewrites wholesale
- **HARD STOP escalation** — when `/docs-sync` cannot reason about a change, it stops and requires `/init-docs`
- **Symlink-only** — `~/.claude/` holds no real files; everything symlinks back here

## Repository Structure

```
hooks/
  log-token-usage.sh    # Stop — logs token usage per session to ~/.claude/token-usage.log
  log-access-prompt.sh  # UserPromptSubmit — saves user instruction for session correlation
  log-access-tool.sh    # PostToolUse — tracks Read/Glob/Grep/Edit/Write by command phase
  log-access-stop.sh    # Stop — appends phase-based access log to logs/YYYY-MM/access.log
logs/
  .gitkeep              # directory tracked; log files are gitignored
commands/
  task.md            # Main entry point — routes to patch or task flow
  patch.md           # Lightweight fix flow
  docs-sync.md       # Documentation sync and PR publication
  init-docs.md       # Full docs reconstruction
  review-resolve.md  # Interactive PR review comment resolution
  templates/
    issue.md       # GitHub issue template
    pr.md          # Pull request template
    readme.md      # README.md scaffold template
partials/
  git-commit.md    # Shared commit procedure — Read by commands/* at commit time (not a slash command)
docs/
  .ai/
    repo.profile.json       # Machine-readable repo profile
  L1_project/               # Project overview docs
  L2_development/           # Development and operation docs
  L3_implementation/        # Implementation specification docs
CLAUDE.md                   # AI operating instructions (auto-loaded by Claude Code)
```

## License

MIT
