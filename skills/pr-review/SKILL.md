---
name: pr-review
description: Review a PR with the opposite AI agent, address valid findings within the approved scope, and leave the latest PR head approved or with requested changes for a human to merge.
---

# PR Review Skill

## Source Of Truth

`~/.codex/commands/pr-review.md` is the single authoritative definition of the PR review workflow.

## Required Behavior

1. Read `commands/pr-review.md` once at the start of the workflow.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/pr-review.md` explicitly instructs you to do so.
4. Keep merge, branch deletion, and main synchronization under human control.

## Scope Guard

- Do not edit `commands/pr-review.md` from this skill.
- If the file is missing or unreadable, report that the PR review workflow cannot run until it is restored.
