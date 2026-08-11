---
name: analyze-hazard-scan
description: Analyze auto-approve and access logs for evidence-based hazard candidates, and file hazard-candidate issues only after explicit batch user approval. Use when the user requests /analyze-hazard-scan behavior.
---

# Auto-Approve-Hazard-Scan Skill

## Source Of Truth

`~/.codex/commands/analyze-hazard-scan.md` is the single authoritative definition of the analyze-hazard-scan workflow.

## Required Behavior

1. Read `commands/analyze-hazard-scan.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/analyze-hazard-scan.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/analyze-hazard-scan.md`.

## Scope Guard

- Do not edit `commands/analyze-hazard-scan.md` from this skill.
- If the file is missing or unreadable, report that you cannot run the analyze-hazard-scan workflow until it is restored.
- Do not edit `hooks/auto-approve-readonly.sh` or any other hook from this skill — hazard findings are proposals filed as issues only.
- Do not create, edit, or close any GitHub issue or label without the explicit batch user approval required by the workflow.
- Do not invoke `/work` or start implementation from this skill.
