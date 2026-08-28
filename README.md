# core-toolkit-for-claude

A structured AI-driven development workflow toolkit for Claude Code and Codex CLI. It packages slash-command specifications, Codex skills, Claude/Codex hook scripts, shared templates, and a VitePress documentation site.

It is not a collection of prompts alone. The toolkit normalizes heterogeneous repositories into a common Repository Model, uses agreed work contracts and implementation-ready Issues as durable units of development, fixes repeatable workflow boundaries, and leaves contextual problem solving to the agent.

Its core design is:

**Repository Normalization + Issue-driven Development + Deterministic Workflow + Agentic Judgment**

## What this toolkit does

Repositories differ in structure, documentation, tooling, test commands, architecture, and conventions. Rediscovering all of that for every task wastes tokens and time, introduces execution variance, and makes important context easier to miss.

The toolkit builds an AI-oriented information model containing repository structure, development and verification methods, design intent, implementation references, and evidence-backed investigation paths. It then keeps that model aligned with implementation changes.

The toolkit does not aim to maximize agent autonomy. It deliberately fixes the structures, gates, artifacts, and approval points that make continuous development reproducible, while leaving investigation, planning, implementation choices, trade-offs, test design, and exceptional handling to the agent where contextual reasoning adds value.

## Core Design

### Three things are deliberately fixed

The workflow is built around three stable control points:

1. **Documentation structure** — repository knowledge is normalized into a common model and kept aligned with implementation.
2. **Implementation work contracts** — purpose, constraints, scope, and completion conditions are agreed and normally represented by implementation-ready Issues.
3. **Implementation workflow** — required gates, procedure order, artifacts, and human approval points are defined by the repository rather than left to per-session discretion.

Within those structures, the agent retains authority to investigate, identify change targets, formulate plans, compare approaches, evaluate trade-offs, implement, select verification methods, and handle exceptional situations.

In short: **the repository defines the workflow; the agent designs the solution; humans retain direction and approval.**

### Repository Normalization

Generated documentation is both human-facing documentation and an AI working substrate. It reduces repeated discovery and provides short, evidence-backed paths into implementation. Stored documentation remains an investigation starting point rather than unquestioned truth; current implementation and diff remain authoritative.

### Issue-driven Development

Implementation does not begin from an unstructured conversation alone. Continuous development is organized around an agreed work contract whose standard representation is an implementation-ready Issue. Unresolved requirements can remain in a human-led discussion until direction, constraints, scope, and completion conditions are clear.

Requirement refinement is not a one-way state machine. If a later adjustment exposes a new unresolved concern, the human can stop implementation and return the topic to discussion.

### Deterministic Fast Path + Agentic Fallback

Repeatable operations remain deterministic when that improves safety, correctness, reproducibility, or token efficiency. Exceptional or insufficiently modeled cases may use agentic fallback, but fallback does not bypass mandatory gates, work contracts, guardrails, or human approval boundaries.

Agent autonomy is therefore not the objective. The objective is to place autonomy where reasoning adds value while fixing workflow elements whose variability creates rework, inconsistency, or risk.

### Observability-driven Improvement

Workflow rules are evaluated from execution evidence rather than a preference for procedural or agentic design. A fixed step that consistently prevents rework remains fixed; a step that repeatedly creates waste or fails to handle contextual variation is a candidate for simplification or delegation back to the agent.

The platform-independent philosophy is defined in `docs/L0_concept/`. Its system responsibilities, operational policies, and implementation are described in `docs/L1_project/` through `docs/L3_implementation/`.

## Features

| Command | Purpose |
|---|---|
| `/work` | Main implementation entry point. Routes agenda-labeled issues to `/mtg`, tells the user to run `/triage-issues-for-hazard` first for hazard-candidate-labeled issues; otherwise gates, investigates, and routes to patch or task flow. |
| `/work-multi` | Explicit opt-in entry point that runs the exact same `/work` workflow inside a dedicated `EnterWorktree`-isolated worktree, for deliberate concurrent-session use. Records the original working tree and links only explicitly needed untracked/ignored paths; its self-created links are automatically excluded from status checks. |
| `/task-manager` | Batch executor for one to three user-provided implementation issues. After combined plan and complete Draft-set approvals, it delegates each approved source PR and head SHA to `/git-pr-merge` in input order, then performs one localized documentation pass. |
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
| `/git-pr-merge` | Delivers one explicitly reviewed Draft or Ready PR: pins the approved head SHA, refreshes the actual PR branch with latest main in an owned worktree, validates the current head, and squash-merges it. Also serves as `/task-manager`'s sequential source-delivery component. |
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

It also configures the native Codex TUI status line in `~/.codex/config.toml`, and updates `~/.claude/settings.json` and `~/.codex/hooks.json` when `jq` is available. Codex users should review and trust registered hooks with `/hooks` before relying on them.

### Global AI Instructions

`global/CLAUDE.md` is the distributed framework file (single source of truth), symlinked by `install.sh` to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`. The repo-root `CLAUDE.md` is this repository's own project-local file and is not distributed.

### Status Lines

For Claude Code:

```bash
./scripts/setup_statusline_for_claude.sh
```

This links `scripts/statusline.sh` to `~/.claude/statusline.sh` and adds a `statusLine` entry to `~/.claude/settings.json` when `jq` is available.

For Codex, `./install.sh` automatically runs the idempotent `scripts/setup_statusline_for_codex.sh`. It configures context usage, used tokens, five-hour limit, and weekly limit in `~/.codex/config.toml`. To update only this setting, run:

```bash
./scripts/setup_statusline_for_codex.sh
```

Codex omits status items whose current values are unavailable. Restart the relevant CLI after changing its status line configuration.

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

/git-pr-merge #N
  reviewed PR + approved head SHA -> latest-main refresh -> current-head validation -> squash merge

/work-multi (opt-in, for deliberate concurrent sessions)
  EnterWorktree -> new isolated worktree -> lazily link needed untracked files -> runs /work unchanged

/task-manager #x [#y] [#z] (independent batch workflow; maximum three issues)
  investigate all issues -> approve all plans -> one task-worker per issue -> Draft source PR set
  approve complete Draft set with head SHAs -> delegate every PR to /git-pr-merge in input order
  latest main + merged changed-file union -> localized docs PR -> automatic validation and merge
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
bash tests/commands/test-workflow-contracts.sh
bash tests/commands/test-work-multi.sh
bash tests/commands/test-task-manager.sh
bash tests/commands/test-git-pr-merge.sh
bash tests/commands/test-hazard-workflows.sh
bash tests/install/test-install.sh
bash tests/install/test-setup-statusline-for-codex.sh
bash tests/scripts/test-link-worktree-untracked.sh
bash tests/scripts/test-rename-thread.sh
bash tests/scripts/test-worktree-status.sh
python3 -m pytest tests/scripts/
shellcheck -x $(find . -not -path "./node_modules/*" -not -path "./site/node_modules/*" -not -path "./.git/*" -iname "*.sh")
```

## Design Principles

- The repository defines workflow structure; the agent designs contextual solutions; humans retain direction and approval.
- Normalize repository knowledge and reuse evidence-backed investigation paths instead of rediscovering everything for every task.
- Treat agreed work contracts, normally represented by implementation-ready Issues, as the basic units of continuous development.
- Keep requirement refinement flexible, but do not let the agent silently decide unresolved direction or scope.
- Do not allow the agent to skip mandatory gates, procedure order, required artifacts, or approval points.
- Use deterministic procedures where they improve safety, correctness, reproducibility, or token efficiency.
- Use agentic fallback for exceptional cases without bypassing guardrails or approval boundaries.
- Improve workflow rules from observed execution evidence rather than preference for autonomy or procedure.
- `git diff` is truth for docs sync; PR text is supplemental.
- `/task` creates and updates L3 per-file docs (`docs/L3_implementation/<source-path>.md`) as part of implementation; `/docs-sync` handles all other docs updates and auto-inserts `git log --oneline -10` output into the `## 変更履歴（git log より自動生成）` section of existing L3 per-file docs.
- `/docs-sync` makes minimal updates and, when the structure can no longer be explained locally, runs `/init-docs` in documentation-only mode before resuming its normal commit/result flow.
- `/task-manager` is an executor for the user-provided issue order: source work is isolated per issue, the complete Draft set fixes each approved head SHA, each source PR is delegated in order to `/git-pr-merge`, and documentation is synchronized once after source delivery.
- `/git-pr-merge` never uses a local `main` workspace for delivery or conflict repair; every Draft and Ready PR is refreshed and validated on its actual head branch before explicit squash merge.
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
scripts/setup_statusline_for_claude.sh  Claude Code status line installer
scripts/setup_statusline_for_codex.sh   Codex TUI status line installer
global/CLAUDE.md              distributed framework file (symlinked to ~/.claude/CLAUDE.md and ~/.codex/AGENTS.md)
CLAUDE.md                     this repository's own project-local AI operating guidance
AGENTS.md                     symlink to CLAUDE.md (project-local) for Codex CLI
```
