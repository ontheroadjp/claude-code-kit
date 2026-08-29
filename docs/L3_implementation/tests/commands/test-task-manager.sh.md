# `tests/commands/test-task-manager.sh`

## 目的・役割

`/work`・`/task`・`/task-manager` と3つの skill adapters の unified entry contract を固定文字列で検証する shell contract test。

## 動作の概要

- `/work` の multi-input、atomic preflight、one-time context、single/multi routing、cleanup ownershipを検証する。
- `/task` の shared delegated mode、supplemental investigation、same-worker continuity、Ready PR handoff、先頭 worker の SHA-bound full-suite evidenceを検証する。
- `/task-manager` が preflight/project investigation/PR creation/reuse policyを複製せず、optional evidence forwarding、independent state、fixed-order deliveryだけを持つことを検証する。
- skill adapters が同じ ownership boundaryを保持することを検証する。

根拠: `tests/commands/test-task-manager.sh:1-103`

## 重要な設計判断

orchestratorだけでなく3 workflow間のabsence contractも検証し、旧来のDraft PR pipelineやduplicated parent investigationの再導入を防ぐ。

## 統合ポイント

- targets: `commands/work.md`, `commands/task.md`, `commands/task-manager.md`
- related: `tests/commands/test-workflow-contracts.sh`, `tests/commands/test-git-pr-merge.sh`

## 注意事項

static Markdown contract testであり、real workersやGitHub PRを起動しない。

## 変更履歴（git log より自動生成）

- 089cf6c feat(#404): reuse SHA-bound full-suite validation
- 9fc5b9a feat(#401): add structured work run observability (#403)
- 72a11b5 feat(#400): unify work entry point (#402)
- b3d7d3b feat(#398): stream task-manager issue pipelines (#399)
- a9fbb5f fix(#369): generate conventional task PR titles (#395)
- a23fda3 #389 Add reusable reviewed PR delivery workflow (#391)
- 6dc29d5 #387 Simplify task-manager source delivery (#388)
- b2b83ac #384 Replace task-manager pre-integration with sequential PR refresh (#385)
- 823f676 #381 Align task-manager source PR titles with work (#382)
- 8a9903f #379 Reuse task-manager integration conflict resolutions (#380)

## Work-run coverage

task-managerが親 `work_run_id`、issue-specific approval wait、approved head correlationを保持することを固定文字列で検証する。

根拠: `tests/commands/test-task-manager.sh:80-82`
