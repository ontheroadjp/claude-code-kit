---
name: analyze-token-usage
description: Aggregate logs/token-usage/*.log via scripts/analyze_token_usage.py (deduping per-session cumulative rows) and produce a Facts/Assessment/Opinions/Proposals report plus an HTML file under logs/reports/token-usage/. Use when /work delegates token-usage-log analysis or the user requests /analyze-token-usage behavior.
---

# Analyze-Token-Usage Skill

## Source Of Truth

`~/.codex/commands/analyze-token-usage.md` is the single authoritative definition of the analyze-token-usage workflow.

## Required Behavior

1. Read `commands/analyze-token-usage.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/analyze-token-usage.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/analyze-token-usage.md`.

## Scope Guard

- Do not edit `commands/analyze-token-usage.md` from this skill.
- If the file is missing or unreadable, report that the analyze-token-usage workflow cannot run until it is restored.
- Do not create, edit, or delete files other than the single new HTML report under `logs/reports/token-usage/`.
- Do not change Git state or GitHub issues and pull requests.
- Do not read raw log lines directly; rely on the JSON printed by `scripts/analyze_token_usage.py`.
