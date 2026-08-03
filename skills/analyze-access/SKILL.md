---
name: analyze-access
description: Aggregate logs/access/*.log via scripts/analyze_access.py and produce a Facts/Assessment/Opinions/Proposals report plus an HTML file under logs/reports/access/. Use when /work delegates access-log analysis or the user requests /analyze-access behavior.
---

# Analyze-Access Skill

## Source Of Truth

`~/.codex/commands/analyze-access.md` is the single authoritative definition of the analyze-access workflow.

## Required Behavior

1. Read `commands/analyze-access.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/analyze-access.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/analyze-access.md`.

## Scope Guard

- Do not edit `commands/analyze-access.md` from this skill.
- If the file is missing or unreadable, report that the analyze-access workflow cannot run until it is restored.
- Do not create, edit, or delete files other than the single new HTML report under `logs/reports/access/`.
- Do not change Git state or GitHub issues and pull requests.
- Do not read raw log lines directly; rely on the JSON printed by `scripts/analyze_access.py`.
