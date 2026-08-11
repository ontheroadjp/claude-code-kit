---
name: triage-issues-for-hazard
description: List hazard-candidate labeled open issues, disclose each source-specific hazard analysis, and ask the user whether to proceed. On yes, direct the user to run /work #N themselves. Use when the user requests /triage-issues-for-hazard behavior.
---

# Triage-Issues-For-Auto-Approve Skill

## Source Of Truth

`~/.codex/commands/triage-issues-for-hazard.md` is the single authoritative definition of the triage-issues-for-hazard workflow.

## Required Behavior

1. Read `commands/triage-issues-for-hazard.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows (including `commands/triage-issues.md`) unless `commands/triage-issues-for-hazard.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/triage-issues-for-hazard.md`.

## Scope Guard

- Do not edit `commands/triage-issues-for-hazard.md` or `commands/triage-issues.md` from this skill.
- If the file is missing or unreadable, report that you cannot run the triage-issues-for-hazard workflow until it is restored.
- Do not perform any GitHub issue, label, or PR operation from this skill — it is read-only.
- Do not invoke `/work` or start implementation from this skill.
