# core-toolkit-for-claude

A structured AI-driven development workflow toolkit for Claude Code and Codex CLI. It packages slash-command specifications, Codex skills, Claude/Codex hook scripts, shared templates, and a VitePress documentation site.

## Features

| Command | Purpose |
|---|---|
| `/work` | Main entry point. Routes report-labeled issues to read-only review; otherwise gates, investigates, and routes to patch or task flow. |
| `/report-review` | Evaluates a report-labeled issue read-only and prints evidence-based opinions and proposals without changing files or GitHub state. |
| `/triage-issues` | Standalone entry point for reviewing and cleaning up open issues so they are ready for `/work #N`. |
| `/new-issue` | Optional pre-`/work` entry point. Turns a rough idea into one or more GitHub issues. |
| `/review-resolve` | Handles PR review comments interactively without going through `/work`. |
| `/codex-review` | Reviews a PR using the Codex CLI non-interactively, posts the result as a PR approval or change request (requires `CODEX_REVIEW_TOKEN`), and auto-invokes `/review-resolve` when changes are requested. |
| `/pr-review` | Reviews a PR with the opposite AI agent, addresses valid findings within the approved scope, and leaves merge control to a human. |
| `/patch` | Delegated by `/work` for lightweight fixes without docs changes. |
| `/task` | Delegated by `/work` for implementation that requires docs changes. |
| `/docs-sync` | Syncs `docs/*` and README from `git diff`, auto-updates L3 per-file doc change history, then writes Docs Sync Result to session temp for `/git-pr`. |
| `/git-pr` | Reads PR title/body/docs-sync-result from session temp, creates a ready PR, then hands it to `/pr-review`. |
| `/init-docs` | Re-observes the repository and reconstructs project design docs. |
| `/coding-general` | Language-independent coding principles. |
| `/coding-py` | Python-specific coding conventions. |
| `/coding-js` | JavaScript-specific coding conventions. |
| `/coding-ts` | TypeScript-specific coding conventions. |

## Installation

> Symlink-only principle: files placed under `~/.claude/` and `~/.codex/` should be symlinks pointing to this repository. This repository is the single source of truth.

### Quick Install

```bash
./install.sh
```

`install.sh` creates target directories and symlinks:

- `commands/*.md` -> `~/.claude/commands/`
- `commands/*.md` -> `~/.codex/commands/`
- `hooks/*.sh` -> `~/.claude/hooks/`
- `hooks/*.sh` -> `~/.codex/hooks/`
- `skills/*/` -> `~/.codex/skills/`
- `templates/*.md` -> `~/.claude/templates/`
- `templates/*.md` -> `~/.codex/templates/`

It also updates `~/.claude/settings.json` and `~/.codex/hooks.json` when `jq` is available. Codex users should review and trust registered hooks with `/hooks` before relying on them.

### Claude Global Instructions

```bash
ln -s /path/to/core-toolkit-for-claude/CLAUDE.md ~/.claude/CLAUDE.md
```

### Status Line

```bash
./setup_statusline.sh
```

This links `scripts/statusline.sh` to `~/.claude/statusline.sh` and adds a `statusLine` entry to `~/.claude/settings.json` when `jq` is available.

## Usage

```text
/new-issue (optional)
  rough idea -> issue draft(s) -> user runs /work #N

/work (main entry)
  report-labeled issue -> /report-review -> read-only evaluation on standard output
  docs not required -> patch flow: branch -> commit -> user ff-merges
  docs required     -> task flow: issue -> implement -> /docs-sync -> ready PR
                       -> opposite-agent /pr-review -> human merge

/review-resolve #N
  PR review comments -> address/reply/skip interactively -> commit/push/reply as needed
```

Site commands are under `site/`:

```bash
cd site && npm run docs:dev
cd site && npm run docs:build
cd site && npm run docs:preview
```

CI runs `npm ci` and `npm run docs:build` in `site/` on push to `main` and on manual workflow dispatch.

## Design Principles

- `git diff` is truth for docs sync; PR text is supplemental.
- `/task` creates and updates L3 per-file docs (`docs/L3_implementation/<source-path>.md`) as part of implementation; `/docs-sync` handles all other docs updates and auto-inserts `git log --oneline -10` output into the `## 変更履歴（git log より自動生成）` section of existing L3 per-file docs.
- `/docs-sync` makes minimal updates and escalates to `/init-docs` when the structure can no longer be explained locally.
- `~/.claude/` and `~/.codex/` are symlink-only; this repository remains the source of truth.
- Workspace cleanup uses stash; destructive git operations require explicit human control.

## Repository Structure

```text
.github/workflows/deploy.yml  GitHub Actions for VitePress -> GitHub Pages
commands/                     Markdown command specifications (includes /git-commit, /git-pr, /pr-review, /pr-review-exec)
hooks/                        Claude Code / Codex hook scripts and shared helpers
skills/                       Codex skill wrappers around commands/*.md
templates/                    Issue, PR, and README templates
docs/                         /init-docs generated L0-L3 design docs
site/                         VitePress documentation site
scripts/                      status line and token usage utilities
tests/                        verification scripts for hooks, workflows, and installer contracts
install.sh                    symlink installer for commands/hooks/skills/templates
setup_statusline.sh           status line installer
CLAUDE.md                     AI operating guidance source of truth
AGENTS.md                     symlink to CLAUDE.md for Codex CLI
```

## License

MIT
