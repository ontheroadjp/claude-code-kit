# `tests/commands/test-hazard-workflows.sh`

Static contract test for generic hazard workflows. It verifies both log analyzers, the generic candidate label, source-appropriate access diagnostics, triage label swaps, and the `/work` gate. It also rejects legacy identifiers in active workflow files, the skill ignore list, and the shared hook-helper README. The test constructs deprecated identifiers from fragments so the test source does not itself retain those complete identifiers.

根拠: `tests/commands/test-hazard-workflows.sh`

## 変更履歴（git log より自動生成）

- c3d9528 feat(#321): remove legacy hazard workflow remnants
- a46be53 feat(#321): unify operational hazard workflows
