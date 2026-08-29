---
name: task
description: Execute the shared ordinary or delegated repository task workflow by loading and following commands/task.md exactly when an active parent workflow delegates issue-specific implementation.
---

# Task Skill

## Source Of Truth

`~/.codex/commands/task.md` is the single authoritative definition of the task workflow.

## Required Behavior

1. Read `commands/task.md`.
2. Execute that workflow exactly as written.
3. In delegated worker mode, reuse the project-wide context from `/work`, return the issue-specific plan for approval, and continue as the same worker through Ready PR creation.
4. Never rerun `/work` gates, merge the Ready PR, or take ownership of parent workspace cleanup or stash restoration.
5. Do not reinterpret, simplify, or merge it with other workflows unless `commands/task.md` explicitly instructs you to do so.
6. If any instruction conflicts with your assumptions, follow `commands/task.md`.

## Scope Guard

- Do not edit `commands/task.md` from this skill.
- If the file is missing or unreadable, report that you cannot run task workflow until it is restored.
