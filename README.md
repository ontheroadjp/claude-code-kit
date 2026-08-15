# core-toolkit-for-claude

A structured AI-driven development workflow toolkit for Claude Code and Codex CLI. It packages slash-command specifications, Codex skills, Claude/Codex hook scripts, shared templates, and a VitePress documentation site.

## Features

| Command | Purpose |
|---|---|
| `/work` | Main implementation entry point. Routes agenda-labeled issues to `/mtg`, tells the user to run `/triage-issues-for-hazard` first for hazard-candidate-labeled issues; otherwise gates, investigates, and routes to patch or task flow. |
| `/work-multi` | Explicit opt-in entry point that runs the exact same `/work` workflow inside a dedicated `EnterWorktree`-isolated worktree, for deliberate concurrent-session use. Records the original working tree and links only explicitly needed untracked/ignored paths; its self-created links are automatically excluded from status checks. |
| `/mtg` | Facilitates a human-led, non-linear discussion for an agenda-labeled issue; implementation issues are created only when the user explicitly runs `/new-issue`. |
| `/analyze-access` | Aggregates `logs/access/*.log` via a Python script, then prints a KPI dashboard (duplicate-read waste) followed by Key Findings & Proposals, and writes an HTML report to `logs/reports/access/`. |
| `/analyze-auto-approve` | Aggregates `logs/auto-approve/*.log` via a Python script, then prints a KPI dashboard (auto-approval rate, routine-op user-prompt rate) followed by Key Findings & Proposals, and writes an HTML report to `logs/reports/auto-approve/`. |
| `/analyze-token-usage` | Aggregates `logs/token-usage/*.log` via a Python script (deduping per-session cumulative rows), then prints a KPI dashboard (cache efficiency) followed by Key Findings & Proposals, and writes an HTML report to `logs/reports/token-usage/`. |
| `/analyze-hazard-scan` | Standalone entry point that analyzes auto-approve allowlist candidates and access-log duplicate-read hazards, then files human-reviewed `hazard-candidate` issues after one batch user approval. Never modifies the hook itself. |
| `/triage-issues` | Standalone entry point for reviewing and cleaning up open issues so they are ready for `/work #N`. |
| `/triage-issues-for-hazard` | Standalone entry point that lists `hazard-candidate` labeled issues, discloses each source-specific hazard analysis verbatim, and on a per-issue yes/no gate directs the user to run `/work #N` themselves. On yes, swaps the issue's label from `hazard-candidate` to `triage-approved` (clearing `/work`'s gate); no other GitHub writes, and never invokes `/work` itself. |
| `/new-issue` | Optional pre-`/work` entry point. Turns a rough idea into one or more GitHub issues. |
| `/review-resolve` | Handles PR review comments interactively without going through `/work`. |
| `/codex-review` | Reviews a PR using the Codex CLI non-interactively, posts the result as a PR approval or change request (requires `CODEX_REVIEW_TOKEN`), and auto-invokes `/review-resolve` when changes are requested. |
| `/patch` | Delegated by `/work` for lightweight fixes without docs changes. |
| `/task` | Delegated by `/work` for implementation that requires docs changes. |
| `/docs-sync` | Syncs `docs/*` and README from `git diff`; on HARD STOP, automatically delegates comprehensive regeneration to `/init-docs` in documentation-only mode, then resumes and writes Docs Sync Result for `/git-pr`. |
| `/git-commit` | Normalizes WIP commits when needed, checks staged changes, and creates a Conventional Commit. |
| `/git-pr` | Reads PR title/body/docs-sync-result from session temp and creates a ready PR. This is the end of the `/work`/`/task` flow — further review and merge are manual. |
| `/init-docs` | Re-observes the repository and reconstructs project design docs. Defaults to standalone mode with its own draft PR; explicit documentation-only mode preserves the current branch and skips commit, push, and PR creation. Creates L0 only when absent. |
| `/concept-maker` | Standalone entry point that processes L0 promotion candidates queued in `docs/.ai/l0_candidates.md` by `/docs-sync`, iterating on wording with the user until explicit approval, then appends to `docs/L0_concept/`. The only AI-facing write path to L0 besides `/init-docs`'s first-time creation. |
| `/coding-general` | Language-independent coding principles. |
| `/coding-py` | Python-specific coding conventions. |
| `/coding-js` | JavaScript-specific coding conventions. |
| `/coding-ts` | TypeScript-specific coding conventions. |
| `/coding-sh` | Shell script-specific coding conventions (ShellCheck). |
| `/coding-react` | Generic React conventions and common anti-patterns. |
| `/coding-nextjs` | Generic Next.js conventions and common anti-patterns. |

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
- `hooks/lib/*.sh` -> `~/.claude/hooks/lib/`
- `hooks/lib/*.sh` -> `~/.codex/hooks/lib/`
- `scripts/*.sh` -> `~/.claude/scripts/`
- `scripts/*.sh` -> `~/.codex/scripts/`
- `skills/*/` -> `~/.codex/skills/`
- `templates/*.md` -> `~/.claude/templates/`
- `templates/*.md` -> `~/.codex/templates/`
- `global/CLAUDE.md` -> `~/.claude/CLAUDE.md`
- `global/CLAUDE.md` -> `~/.codex/AGENTS.md`

It also updates `~/.claude/settings.json` and `~/.codex/hooks.json` when `jq` is available. Codex users should review and trust registered hooks with `/hooks` before relying on them.

### Global AI Instructions

`global/CLAUDE.md` is the distributed framework file (single source of truth), symlinked by `install.sh` to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. The repo-root `CLAUDE.md` is this repository's own project-local file and is not distributed.

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
  agenda-labeled issue -> /mtg -> human-led discussion and decision making
  hazard-candidate issue -> stops, tells user to run /triage-issues-for-hazard first
  docs not required -> patch flow: branch -> commit -> user ff-merges
  docs required     -> task flow: issue -> implement -> /docs-sync -> ready PR
                       HARD STOP -> /docs-sync runs /init-docs documentation-only -> resumes -> ready PR
                       (end of flow -- review/merge are manual)

/review-resolve #N
  PR review comments -> address/reply/skip interactively -> commit/push/reply as needed

/work-multi (opt-in, for deliberate concurrent sessions)
  EnterWorktree -> new isolated worktree -> lazily link needed untracked files -> runs /work unchanged
```

Site commands are under `site/`:

```bash
cd site && npm run docs:dev
cd site && npm run docs:build
cd site && npm run docs:preview
```

CI runs `npm ci` and `npm run docs:build` in `site/` on push to `main` and on manual workflow dispatch.
A separate CI workflow runs ShellCheck against every `*.sh` file on push and pull request.
Another CI workflow runs `tests/hooks/test-approval-hooks.sh` on push and pull request.

Local verification commands:

```bash
bash tests/hooks/test-approval-hooks.sh
bash tests/hooks/test-session-paths.sh
bash tests/commands/test-mtg.sh
bash tests/commands/test-coding-guidelines.sh
bash tests/commands/test-work-multi.sh
bash tests/install/test-install.sh
bash tests/scripts/test-link-worktree-untracked.sh
bash tests/scripts/test-worktree-status.sh
python3 -m pytest tests/scripts/
shellcheck -x $(find . -not -path "./node_modules/*" -not -path "./site/node_modules/*" -not -path "./.git/*" -iname "*.sh")
```

## Design Principles

- `git diff` is truth for docs sync; PR text is supplemental.
- `/task` creates and updates L3 per-file docs (`docs/L3_implementation/<source-path>.md`) as part of implementation; `/docs-sync` handles all other docs updates and auto-inserts `git log --oneline -10` output into the `## 変更履歴（git log より自動生成）` section of existing L3 per-file docs.
- `/docs-sync` makes minimal updates and, when the structure can no longer be explained locally, runs `/init-docs` in documentation-only mode before resuming its normal commit/result flow.
- `/init-docs` defaults to standalone mode; documentation-only mode is used only when explicitly instructed and never creates a branch, commit, push, or PR.
- `~/.claude/` and `~/.codex/` are symlink-only; this repository remains the source of truth.
- Workspace cleanup uses stash; destructive git operations require explicit human control.
- `docs/L0_concept/` is 100% user-controlled; the only AI write path is `/concept-maker`'s per-candidate wording review and explicit approval, besides `/init-docs`'s first-time creation.

## Repository Structure

```text
.github/workflows/deploy.yml      GitHub Actions for VitePress -> GitHub Pages
.github/workflows/shellcheck.yml  GitHub Actions running ShellCheck against all *.sh
.github/workflows/test.yml        GitHub Actions running the approval hooks test suite
commands/                     Markdown command specifications (includes /git-commit, /git-pr)
hooks/                        Claude Code / Codex hook scripts and shared helpers
skills/                       Codex skill wrappers around commands/*.md
templates/                    Issue, PR, and README templates
docs/                         /init-docs generated L0-L3 design docs
site/                         VitePress documentation site
scripts/                      status line and token usage utilities
tests/                        verification scripts for hooks, workflows, and installer contracts
install.sh                    symlink installer for commands/hooks/skills/templates
setup_statusline.sh           status line installer
global/CLAUDE.md              distributed framework file (symlinked to ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md)
CLAUDE.md                     this repository's own project-local AI operating guidance
AGENTS.md                     symlink to CLAUDE.md (project-local) for Codex CLI
```
