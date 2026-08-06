---
name: auto-approve-hazard-scan
description: Identify auto-approve allowlist extension candidates from logs/auto-approve/*.log, diagnose each via hooks/auto-approve-readonly.sh --explain, produce an AI hazard checklist, and file auto-approve-candidate labeled issues for candidates with no known hazard, after explicit batch user approval. Use when the user requests /auto-approve-hazard-scan behavior.
---

# Auto-Approve-Hazard-Scan Skill

## Source Of Truth

`~/.codex/commands/auto-approve-hazard-scan.md` is the single authoritative definition of the auto-approve-hazard-scan workflow.

## Required Behavior

1. Read `commands/auto-approve-hazard-scan.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/auto-approve-hazard-scan.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/auto-approve-hazard-scan.md`.

## Scope Guard

- Do not edit `commands/auto-approve-hazard-scan.md` from this skill.
- If the file is missing or unreadable, report that you cannot run the auto-approve-hazard-scan workflow until it is restored.
- Do not edit `hooks/auto-approve-readonly.sh` or any other hook from this skill — hazard findings are proposals filed as issues only.
- Do not create, edit, or close any GitHub issue or label without the explicit batch user approval required by the workflow.
- Do not invoke `/work` or start implementation from this skill.
