---
name: work
description: Execute the unified single-issue or multi-issue repository work workflow by loading and following commands/work.md exactly. Use this when the user requests /work behavior.
---

# Work Skill

## Source Of Truth

`~/.codex/commands/work.md` is the single authoritative definition of the work workflow.

## Required Behavior

1. Read `commands/work.md`.
2. Execute that workflow exactly as written.
3. Treat `/work` as the session owner and only implementation entry point for both single and multiple issue input.
4. Validate the complete issue input atomically before project-wide investigation or mutation.
5. Pass the complete project-wide context to delegated workflows and preserve `/work` ownership of workspace cleanup and stash restoration.
6. Do not reinterpret, simplify, or merge it with other workflows unless `commands/work.md` explicitly instructs you to do so.
7. If any instruction conflicts with your assumptions, follow `commands/work.md`.

## Scope Guard

- Do not edit `commands/work.md` from this skill.
- If the file is missing or unreadable, report that you cannot run work workflow until it is restored.
