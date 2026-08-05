---
name: concept-maker
description: Execute the repository concept-maker workflow by loading and following commands/concept-maker.md exactly. Use this when the user requests /concept-maker behavior or wants to promote L3-discovered decisions to docs/L0_concept/.
---

# Concept-Maker Skill

## Source Of Truth

`~/.codex/commands/concept-maker.md` is the single authoritative definition of the concept-maker workflow.

## Required Behavior

1. Read `commands/concept-maker.md`.
2. Execute that workflow exactly as written.
3. Do not reinterpret, simplify, or merge it with other workflows unless `commands/concept-maker.md` explicitly instructs you to do so.
4. If any instruction conflicts with your assumptions, follow `commands/concept-maker.md`.

## Scope Guard

- Do not edit `commands/concept-maker.md` from this skill.
- If the file is missing or unreadable, report that you cannot run the concept-maker workflow until it is restored.
- Never write to `docs/L0_concept/concept.md` or `policy.md` without the per-candidate wording back-and-forth and explicit user approval defined in `commands/concept-maker.md` Step 2.
