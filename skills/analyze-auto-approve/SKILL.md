---
name: analyze-auto-approve
description: Aggregate logs/auto-approve/*.log via scripts/analyze_auto_approve.py and produce a Facts/Assessment/Opinions/Proposals report plus an HTML file under logs/reports/auto-approve/. Use when /work delegates auto-approve-log analysis or the user requests /analyze-auto-approve behavior.
---

# Analyze-Auto-Approve Skill

## Source Of Truth

`~/.codex/commands/analyze-auto-approve.md` is the single authoritative definition of the analyze-auto-approve workflow.

## Required Behavior

1. Read `commands/analyze-auto-approve.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/analyze-auto-approve.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/analyze-auto-approve.md`.

## Scope Guard

- Do not edit `commands/analyze-auto-approve.md` from this skill.
- If the file is missing or unreadable, report that the analyze-auto-approve workflow cannot run until it is restored.
- Do not create, edit, or delete files other than the single new HTML report under `logs/reports/auto-approve/`.
- Do not change Git state or GitHub issues and pull requests.
- Do not edit `hooks/auto-approve-readonly.sh` or any other hook from this skill — improvement ideas are Proposals only.
- Do not read raw log lines directly; rely on the JSON printed by `scripts/analyze_auto_approve.py`.
