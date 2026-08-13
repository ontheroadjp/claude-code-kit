---
name: mtg
description: Facilitate a human-led discussion for an agenda-labeled GitHub issue. Use when /work delegates an agenda issue or the user requests /mtg behavior.
---

# Mtg Skill

## Source Of Truth

`~/.codex/commands/mtg.md` is the single authoritative definition of the mtg workflow.

## Required Behavior

1. Read `commands/mtg.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/mtg.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/mtg.md`.

## Scope Guard

- Do not edit `commands/mtg.md` from this skill.
- If the file is missing or unreadable, report that the mtg workflow cannot run until it is restored.
- Do not start `/new-issue` unless the user explicitly instructs it.
- Do not end or close an agenda unless the user explicitly declares close.
