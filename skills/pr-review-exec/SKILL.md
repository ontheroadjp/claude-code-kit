---
name: pr-review-exec
description: Fetch a PR's diff, review it, and post the result directly to GitHub as a review. Reviewer-only, self-contained, no file edits.
---

# PR Review Exec Skill

## Source Of Truth

`~/.codex/commands/pr-review-exec.md` is the single authoritative definition of this workflow.

## Required Behavior

1. Read `commands/pr-review-exec.md` once at the start of the workflow.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/pr-review-exec.md` explicitly instructs you to do so.
4. Do not invoke `/work`, `/task`, `/patch`, `/pr-review`, or `/review-resolve` from within this workflow.

## Scope Guard

- Do not edit `commands/pr-review-exec.md` from this skill.
- Do not edit any file, run git write operations, or merge/close/delete anything.
- If the file is missing or unreadable, report that the review cannot run until it is restored.
