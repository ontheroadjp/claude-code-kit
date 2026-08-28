---
name: task-manager
description: Execute the streaming task-manager workflow for one to three implementation issues by loading and following commands/task-manager.md exactly. Use when the user requests /task-manager behavior.
---

# Task Manager Skill

## Source Of Truth

`~/.codex/commands/task-manager.md` is the single authoritative definition of the task-manager workflow.

## Required Behavior

1. Read `commands/task-manager.md` completely.
2. Execute that workflow exactly as written.
3. Use one real `task-worker` sub-agent per accepted issue, up to the fixed maximum of three.
4. Omit sub-agent model overrides so every worker inherits the parent model.
5. Pass each worker the complete structured parent investigation handoff and preserve the same worker across supplemental investigation, plan approval, implementation, documentation, and Draft PR creation when possible.
6. Keep every issue's plan and PR approval state independent; an approval wait must not stop unrelated workers.
7. Keep delivery sequential in the user-provided issue order and delegate each approved PR to `commands/git-pr-merge.md` exactly as `commands/task-manager.md` requires.
8. Include issue-required documentation in each issue PR and never create a final batch documentation PR.
9. Do not reinterpret, simplify, or merge the workflow with another workflow unless `commands/task-manager.md` explicitly instructs you to do so.

## Scope Guard

- Do not edit `commands/task-manager.md` from this skill.
- Do not expose `task-worker` as a standalone user command or skill.
- If the command file is missing or unreadable, report that `/task-manager` cannot run until it is restored.
