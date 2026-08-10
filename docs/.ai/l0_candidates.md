# L0 Promotion Candidates

<!-- Populated by /docs-sync Phase 3 Step 2b, consumed and cleared by /concept-maker. Do not hand-edit except to remove a stale entry. -->

- docs/L3_implementation/commands/init-docs.md:25 — AI must never write directly to docs/L0_concept/; the only write paths are /init-docs (first-time creation only) and /concept-maker (per-candidate wording review + explicit user approval) (issue #273)
- docs/L3_implementation/hooks/auto_approve_readonly.md:280-292 — session-approved write-permission grants should be scoped to the specific target resource (e.g. issue/PR number) rather than granted session-wide, to limit prompt-injection blast radius (issue #297)
