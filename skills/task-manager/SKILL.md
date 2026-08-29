---
name: task-manager
description: Orchestrate delegated task workers only when commands/work.md routes an accepted multi-issue invocation to commands/task-manager.md.
---

# Task Manager Skill

## Source Of Truth

`~/.codex/commands/task-manager.md` is the single authoritative definition of the internal multi-issue orchestrator.

## Required Behavior

1. Read `commands/task-manager.md` completely.
2. Execute it only with the complete accepted-issue and project-context handoff from `/work`.
3. Use one real delegated `task-worker` sub-agent per accepted issue, up to three, without model overrides.
4. Require every worker to read and execute delegated worker mode in `commands/task.md` instead of reproducing task investigation and delivery rules.
5. Preserve the same worker across plan approval, implementation, documentation, validation, and Ready PR creation when possible.
6. Keep plan and Ready PR approval states independent while preserving fixed input-order delivery through `commands/git-pr-merge.md`.
7. Return completion, failure, and remaining-worktree state to `/work`; never own parent workspace cleanup or stash restoration.
8. Do not reinterpret or duplicate the workflow.

## Scope Guard

- `/task-manager` is not a standalone implementation entry point. Without a valid `/work` handoff, direct the user to `/work #x #y` and stop.
- Do not expose `task-worker` as a standalone user command or skill.
- If the command file is missing or unreadable, report that multi-issue orchestration cannot run until it is restored.
