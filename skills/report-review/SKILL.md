---
name: report-review
description: Evaluate a report-labeled GitHub issue read-only and print evidence-based opinions and proposals. Use when /work delegates a report issue or the user requests /report-review behavior.
---

# Report-Review Skill

## Source Of Truth

`~/.codex/commands/report-review.md` is the single authoritative definition of the report-review workflow.

## Required Behavior

1. Read `commands/report-review.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/report-review.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/report-review.md`.

## Scope Guard

- Do not edit `commands/report-review.md` from this skill.
- If the file is missing or unreadable, report that the report-review workflow cannot run until it is restored.
- Do not create, edit, or delete files.
- Do not change Git state or GitHub issues and pull requests.
- Present the evaluation only in standard output.
