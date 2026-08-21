---
name: git-pr-merge
description: Deliver one explicitly reviewed pull request on top of the latest main with approved-head drift protection, current-head validation, and squash merge. Use when the user requests /git-pr-merge behavior or when commands/task-manager.md delegates an approved source PR.
---

# Git PR Merge Skill

## Source Of Truth

`~/.codex/commands/git-pr-merge.md` is the single authoritative definition of the reviewed PR delivery workflow.

## Required Behavior

1. Read `commands/git-pr-merge.md` completely.
2. Execute that workflow exactly as written.
3. Preserve the distinction between standalone approval and complete delegated approval context.
4. Never fall back to a local main workspace when PR worktree ownership is unavailable or unclear.
5. Do not reinterpret, simplify, or merge it with another workflow unless `commands/git-pr-merge.md` explicitly instructs you to do so.

## Scope Guard

- Do not edit `commands/git-pr-merge.md` from this skill.
- Do not merge a PR without an explicitly approved head SHA.
- Leave branch and worktree cleanup to the caller.
- If the command file is missing or unreadable, report that `/git-pr-merge` cannot run until it is restored.
