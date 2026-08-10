---
name: work-multi
description: Execute the repository work workflow inside an isolated EnterWorktree worktree, for deliberate concurrent-session use, by loading and following commands/work-multi.md exactly. Use this when the user requests /work-multi behavior.
---

# Work Multi Skill

## Source Of Truth

`~/.codex/commands/work-multi.md` is the single authoritative definition of the worktree-isolated work workflow.

## Required Behavior

1. Read `commands/work-multi.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/work-multi.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/work-multi.md`.

## Scope Guard

- Do not edit `commands/work-multi.md` from this skill.
- If the file is missing or unreadable, report that you cannot run the work-multi workflow until it is restored.
