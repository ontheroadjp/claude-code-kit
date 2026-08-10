# PR Template (Draft)

<!-- Used by task.md Phase 2 -->
<!-- Fill in the [ ] placeholders -->

Closes #[issue number]

## Summary

### Changed Files
<!-- For each file: what was changed and why -->
- `[file path]`: [what and why]

### Change Type
- [ ] feat (new feature)
- [ ] fix (bug fix)
- [ ] refactor
- [ ] chore (config/build/tooling)
- [ ] docs
- [ ] test
- [ ] other

### Handoff Notes for /docs-sync
<!-- Only include context that cannot be inferred from git diff -->
<!-- File changes, API diffs, and config values are visible in git diff — omit those -->
- Design intent / background: [why this change was made; "none" if obvious]
- Side effects not visible in git diff: [env vars, external services, manual steps, infra; "none" if N/A]
- Potential misreads by docs-sync: [anything that could be misinterpreted; "none" if N/A]
- Specific docs sections to update: [prefer a resolved citation in `file:line-range` form if already located during investigation (e.g. `docs/L3_implementation/specification_summary.md:63-69`), so /docs-sync can reuse it instead of re-locating; otherwise file or section names; "none" if N/A]

## Notes for Reviewers
[Anything reviewers should know; "none" if N/A]
