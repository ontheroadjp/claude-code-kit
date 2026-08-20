---
name: task-manager
description: Execute the independent task-manager batch workflow for one to three implementation issues by loading and following commands/task-manager.md exactly. Use when the user requests /task-manager behavior.
---

# Task Manager Skill

## Source Of Truth

`~/.codex/commands/task-manager.md` is the single authoritative definition of the task-manager workflow.

## Required Behavior

1. Read `commands/task-manager.md` completely.
2. Execute that workflow exactly as written.
3. Use one real `task-worker` sub-agent per accepted issue, up to the fixed maximum of three.
4. Omit sub-agent model overrides so every worker inherits the parent model.
5. Keep the workflow independent from all pre-existing implementation and documentation workflows.
6. Do not reinterpret, simplify, or merge it with another workflow unless `commands/task-manager.md` explicitly instructs you to do so.

## Scope Guard

- Do not edit `commands/task-manager.md` from this skill.
- Do not expose `task-worker` as a standalone user command or skill.
- If the command file is missing or unreadable, report that `/task-manager` cannot run until it is restored.
